import Foundation
import AppKit

enum ClipboardSelectionMode {
  case replace
  case toggle
  case range
  case hover
  case activate
}

struct ClipboardCollectionCountSummary {
  fileprivate let sortModeCounts: [Int: Int]
  fileprivate let collectionCounts: [String: Int]

  func count(for sortMode: ClipboardSortMode) -> Int {
    sortModeCounts[sortMode.rawValue] ?? 0
  }

  func count(named name: String) -> Int {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return 0 }
    return collectionCounts[normalizedName.lowercased()] ?? 0
  }
}

struct ClipboardCategorySelectionSnapshot: Equatable {
  let sortMode: ClipboardSortMode
  let selectedCollectionName: String?
  let isStackFilterSelected: Bool
  let selectedSortModeFilterRawValues: Set<Int>
  let selectedCollectionNameFilters: [String]
  let selectedItemID: UUID?
  let selectedItemIDs: [UUID]
  let selectionAnchorItemID: UUID?
  let selectedIndex: Int
}

final class ClipboardPanelViewModel {
  private static let searchDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    let calendar = Calendar.searchCalendar
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
  private static let searchLocale = Locale(identifier: "en_US_POSIX")

  private struct StructuredFilterMatcher {
    let tokens: [String]
    let exactValue: String?
  }

  private struct StructuredFilterValue {
    let value: String
    let isExact: Bool
  }

  private struct ParsedSearchQuery {
    var textTokens: [String] = []
    var appTokenGroups: [StructuredFilterMatcher] = []
    var deviceTokenGroups: [StructuredFilterMatcher] = []
    var collectionTokenGroups: [StructuredFilterMatcher] = []
    var typeKinds: Set<ClipboardItemKind> = []
    var createdAfter: Date?
    var createdBefore: Date?
    var pinned: Bool?

    var isEmpty: Bool {
      textTokens.isEmpty
        && appTokenGroups.isEmpty
        && deviceTokenGroups.isEmpty
        && collectionTokenGroups.isEmpty
        && typeKinds.isEmpty
        && createdAfter == nil
        && createdBefore == nil
        && pinned == nil
    }
  }

  private struct VisibleItemsCacheKey: Hashable {
    let query: String
    let sortMode: Int
    let collectionNameKey: String?
    let sortModeFilterRawValues: [Int]
    let collectionNameFilterKeys: [String]
  }

  private struct CategoryFilterSelection: Hashable {
    let sortModeRawValues: [Int]
    let collectionNameKeys: [String]

    static let empty = CategoryFilterSelection(sortModeRawValues: [], collectionNameKeys: [])

    var isEmpty: Bool {
      sortModeRawValues.isEmpty && collectionNameKeys.isEmpty
    }

    var totalCount: Int {
      sortModeRawValues.count + collectionNameKeys.count
    }
  }

  private struct IndexedClipboardItem {
    let offset: Int
    let item: ClipboardItem
  }

  private enum VisibleItemsSortOrdering {
    case recency
    case useCount
    case lastUsed
    case original
  }

  private(set) var visibleItems: [ClipboardItem] = [] {
    didSet {
      var nextItemByID: [UUID: ClipboardItem] = [:]
      nextItemByID.reserveCapacity(visibleItems.count)
      var nextIndexByID: [UUID: Int] = [:]
      nextIndexByID.reserveCapacity(visibleItems.count)
      for (index, item) in visibleItems.enumerated() {
        if nextItemByID[item.id] == nil {
          nextItemByID[item.id] = item
        }
        if nextIndexByID[item.id] == nil {
          nextIndexByID[item.id] = index
        }
      }
      visibleItemByID = nextItemByID
      visibleIndexByID = nextIndexByID
      guard !isRecomputingVisibleItems else { return }
      notifyVisibleItemsChanged()
    }
  }
  var searchText: String = "" {
    didSet {
      guard oldValue != searchText else { return }
      guard !isBatchingFilterSelectionChanges else { return }
      guard Self.normalizedSearchValue(oldValue) != Self.normalizedSearchValue(searchText) else {
        notifyMain { self.onSearchTextChanged?(self.searchText) }
        return
      }
      selectedItemID = selectedItem?.id
      recomputeVisibleItems()
      notifyMain { self.onSearchTextChanged?(self.searchText) }
    }
  }
  var sortMode: ClipboardSortMode {
    didSet {
      guard oldValue != sortMode else { return }
      guard !isBatchingFilterSelectionChanges else {
        if !suppressDefaultSortModePersistence {
          settings.defaultSortMode = sortMode
        }
        return
      }
      selectedSortModeFilterRawValues.removeAll(keepingCapacity: true)
      selectedCollectionNameFilters.removeAll(keepingCapacity: true)
      isBatchingFilterSelectionChanges = true
      isStackFilterSelected = false
      selectedCollectionName = nil
      isBatchingFilterSelectionChanges = false
      if !suppressDefaultSortModePersistence {
        settings.defaultSortMode = sortMode
      }
      recomputeVisibleItems()
      onSortModeChanged?(sortMode)
    }
  }
  private(set) var selectedCollectionName: String? {
    didSet {
      guard oldValue != selectedCollectionName else { return }
      guard !isBatchingFilterSelectionChanges else { return }
      recomputeVisibleItems()
      onCollectionsChanged?()
    }
  }
  private(set) var isStackFilterSelected = false {
    didSet {
      guard oldValue != isStackFilterSelected else { return }
      guard !isBatchingFilterSelectionChanges else { return }
      recomputeVisibleItems()
      onStackChanged?()
    }
  }
  private(set) var isStackCaptureEnabled = false {
    didSet {
      guard oldValue != isStackCaptureEnabled else { return }
      if !isStackCaptureEnabled, isStackFilterSelected, stackItemIDs.isEmpty {
        isStackFilterSelected = false
      }
      notifyMain { self.onStackChanged?() }
    }
  }
  var selectedIndex: Int = 0 {
    didSet {
      guard oldValue != selectedIndex else { return }
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    }
  }
  private(set) var selectedItemIDs: [UUID] = [] {
    didSet {
      selectedItemIDSet = Set(selectedItemIDs)
      guard oldValue != selectedItemIDs else { return }
      notifyMain { self.onSelectedItemsChanged?() }
    }
  }
  private(set) var statusMessage: String = "" {
    didSet { notifyMain { self.onStatusMessageChanged?(self.statusMessage) } }
  }

  private var items: [ClipboardItem] = [] {
    didSet {
      rebuildItemIndexes()
      collectionNamesCache = nil
      visibleItemsCache.removeAll(keepingCapacity: true)
      collectionCountCache = nil
    }
  }
  private let store: ClipboardStore
  private let settings: SettingsModel
  private let cacheService: ClipboardCacheService
  private let pasteService: PasteActionService
  private let imageTextExtractor: (NSImage) -> String?
  private var selectedItemID: UUID?
  private var selectionAnchorItemID: UUID?
  private var isRecomputingVisibleItems = false
  private var isBatchingFilterSelectionChanges = false
  private var selectedSortModeFilterRawValues: Set<Int> = []
  private var selectedCollectionNameFilters: [String] = []
  private var suppressDefaultSortModePersistence = false
  private var isApplyingLocalCollectionMutation = false
  private var isDeferringLocalStoreRecompute = false
  private var pendingDeletionUndo: [ClipboardStoreRemoval] = []
  private var collectionCountCache: (query: String, summary: ClipboardCollectionCountSummary)?
  private var collectionNamesCache: [String]?
  private var visibleItemsCache: [VisibleItemsCacheKey: [ClipboardItem]] = [:]
  private var itemByID: [UUID: ClipboardItem] = [:]
  private var itemIDSet: Set<UUID> = []
  private var indexedItemsByCollectionKey: [String: [IndexedClipboardItem]] = [:]
  private var indexedItemsBySortMode: [Int: [IndexedClipboardItem]] = [:]
  private var assignedCollectionNamesByKey: [String: String] = [:]
  private var visibleItemByID: [UUID: ClipboardItem] = [:]
  private var visibleIndexByID: [UUID: Int] = [:]
  private var selectedItemIDSet: Set<UUID> = []
  private var stackItemIDSet: Set<UUID> = []
  private var stackItemIDs: [UUID] = [] {
    didSet {
      stackItemIDSet = Set(stackItemIDs)
      guard oldValue != stackItemIDs else { return }
      notifyMain { self.onStackChanged?() }
    }
  }

  deinit {
    purgePendingDeletionUndo()
  }

  var targetApplicationProvider: () -> NSRunningApplication? = { nil }
  var willPasteToTarget: () -> Void = {}
  var onVisibleItemsChanged: (([ClipboardItem]) -> Void)?
  var onSearchTextChanged: ((String) -> Void)?
  var onSelectedIndexChanged: ((Int) -> Void)?
  var onSelectedItemsChanged: (() -> Void)?
  var onStatusMessageChanged: ((String) -> Void)?
  var onSortModeChanged: ((ClipboardSortMode) -> Void)?
  var onCollectionsChanged: (() -> Void)?
  var onStackChanged: (() -> Void)?
  var onCaptureStatusChanged: (() -> Void)?
  var onCompactModeChanged: (() -> Void)?
  var onPanelLayoutChanged: (() -> Void)?

  #if DEBUG
  private(set) var debugVisibleItemsFullScanCount = 0
  private(set) var debugVisibleItemsIndexedLookupCount = 0
  private(set) var debugCollectionCountFullScanCount = 0
  private(set) var debugCollectionCountIndexedLookupCount = 0
  #endif

  init(
    store: ClipboardStore,
    settings: SettingsModel,
    cacheService: ClipboardCacheService,
    imageTextExtractor: @escaping (NSImage) -> String? = ImageTextExtractor.recognizedText(in:)
  ) {
    self.store = store
    self.settings = settings
    self.cacheService = cacheService
    self.sortMode = settings.defaultSortMode
    self.pasteService = PasteActionService(cacheService: cacheService)
    self.imageTextExtractor = imageTextExtractor

    store.observeItems { [weak self] list in
      guard let self else { return }
      let shouldDeferRecompute = self.isDeferringLocalStoreRecompute
      self.notifyMain {
        self.items = list
        if shouldDeferRecompute {
          return
        }
        self.recomputeVisibleItems()
      }
    }
    settings.observe { [weak self] change in
      self?.notifyMain {
        switch change {
        case .captureStatus:
          self?.statusMessage = ""
          self?.onStatusMessageChanged?("")
          self?.onCaptureStatusChanged?()
        case .collections:
          guard let self else { return }
          self.collectionNamesCache = nil
          guard !self.isApplyingLocalCollectionMutation else { return }
          self.recomputeVisibleItems()
          self.onCollectionsChanged?()
        case .compactMode:
          self?.onCompactModeChanged?()
        case .panelLayout:
          self?.onPanelLayoutChanged?()
        case .defaultSortMode:
          guard let self else { return }
          self.sortMode = self.settings.defaultSortMode
        case .includeImageTextInSearch:
          self?.collectionCountCache = nil
          self?.visibleItemsCache.removeAll(keepingCapacity: true)
          self?.recomputeVisibleItems()
        default:
          break
        }
      }
    }
  }

  #if DEBUG
  func debugResetVisibleItemsPerformanceCounters() {
    debugVisibleItemsFullScanCount = 0
    debugVisibleItemsIndexedLookupCount = 0
    debugCollectionCountFullScanCount = 0
    debugCollectionCountIndexedLookupCount = 0
  }
  #endif

  var selectedItem: ClipboardItem? {
    guard selectedIndex >= 0, selectedIndex < visibleItems.count else { return nil }
    return visibleItems[selectedIndex]
  }

  var selectedItemCount: Int {
    selectedItemsInSelectionOrder().count
  }

  var canShowSelectedInClipboard: Bool {
    selectedItem != nil && canShowVisibleItemsInClipboard
  }

  var canShowVisibleItemsInClipboard: Bool {
    !visibleItems.isEmpty
      && (!searchText.clipboardTrimmed.isEmpty
          || sortMode != .mostRecent
          || selectedCollectionName != nil
          || !activeCategoryFilterSelection().isEmpty
          || isStackFilterSelected)
  }

  var totalItemCount: Int {
    items.count
  }

  var stackCount: Int {
    stackItemIDs.count
  }

  var stackTitle: String {
    "Stack"
  }

  var isCompactModeEnabled: Bool {
    false
  }

  var panelLayout: ClipboardPanelLayout {
    .vertical
  }

  func toggleCompactMode() {
    statusMessage = "Compact Mode was removed"
  }

  var collectionNames: [String] {
    if let collectionNamesCache {
      return collectionNamesCache
    }

    let assignedNames = Set(assignedCollectionNamesByKey.values)
    let configuredNames = settings.customCollectionNames
    let configuredNameSet = Set(configuredNames.map { $0.lowercased() })
    let allNames = assignedNames.union(configuredNames)
    let defaultNames = ClipboardCollectionDefaults.names.filter { allNames.contains($0) }
    var configuredCustomNames: [String] = []
    for name in configuredNames where !ClipboardCollectionDefaults.names.contains(name) {
      guard !configuredCustomNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
      configuredCustomNames.append(name)
    }
    let assignedCustomNames = assignedNames
      .filter { !ClipboardCollectionDefaults.names.contains($0) }
      .filter { !configuredNameSet.contains($0.lowercased()) }
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    let names = defaultNames + configuredCustomNames + assignedCustomNames
    collectionNamesCache = names
    return names
  }

  var searchFilterSourceAppNames: [String] {
    uniqueSearchFacetValues(items.compactMap(\.sourceApp))
  }

  var searchFilterDeviceNames: [String] {
    uniqueSearchFacetValues(items.map { Optional($0.effectiveSourceDeviceName) })
  }

  func collectionCount(for sortMode: ClipboardSortMode) -> Int {
    collectionCountSummary().count(for: sortMode)
  }

  func collectionCount(named name: String) -> Int {
    collectionCountSummary().count(named: name)
  }

  func collectionCountSummary() -> ClipboardCollectionCountSummary {
    let query = searchText.clipboardTrimmed.lowercased()
    if let collectionCountCache, collectionCountCache.query == query {
      return collectionCountCache.summary
    }

    let parsedQuery = parseSearchQuery(query)
    var sortModeCounts = Dictionary(uniqueKeysWithValues: ClipboardSortMode.allCases.map { ($0.rawValue, 0) })
    var collectionCounts: [String: Int] = [:]

    if parsedQuery.isEmpty {
      for mode in ClipboardSortMode.allCases {
        sortModeCounts[mode.rawValue] = indexedItemsBySortMode[mode.rawValue]?.count ?? 0
      }
      for (collectionKey, indexedItems) in indexedItemsByCollectionKey {
        collectionCounts[collectionKey] = indexedItems.count
      }
      #if DEBUG
      debugCollectionCountIndexedLookupCount += 1
      #endif
    } else {
      for item in items {
        if !matchesSearchQuery(item, query: parsedQuery) {
          continue
        }

        for mode in ClipboardSortMode.allCases where mode.includes(item) {
          sortModeCounts[mode.rawValue, default: 0] += 1
        }
        if let collectionName = ClipboardCollectionDefaults.normalizedName(item.collectionName) {
          collectionCounts[collectionName.lowercased(), default: 0] += 1
        }
      }
      #if DEBUG
      debugCollectionCountFullScanCount += 1
      #endif
    }

    let summary = ClipboardCollectionCountSummary(
      sortModeCounts: sortModeCounts,
      collectionCounts: collectionCounts
    )
    collectionCountCache = (query, summary)
    return summary
  }

  func shouldShowCategory(for sortMode: ClipboardSortMode) -> Bool {
    collectionCount(for: sortMode) > 0 || isSortModeCategorySelected(sortMode)
  }

  func isSortModeCategorySelected(_ mode: ClipboardSortMode) -> Bool {
    guard !isStackFilterSelected else { return false }
    let selection = activeCategoryFilterSelection()
    if !selection.isEmpty {
      return selection.sortModeRawValues.contains(mode.rawValue)
    }
    return selectedCollectionName == nil && sortMode == mode
  }

  func isCollectionCategorySelected(named name: String) -> Bool {
    guard !isStackFilterSelected else { return false }
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return false }
    let key = normalizedName.lowercased()
    let selection = activeCategoryFilterSelection()
    if !selection.isEmpty {
      return selection.collectionNameKeys.contains(key)
    }
    return selectedCollectionName?.caseInsensitiveCompare(normalizedName) == .orderedSame
  }

  var captureStatusMessage: String {
    settings.captureStatusMessage
  }

  func thumbnail(for item: ClipboardItem) -> NSImage? {
    cacheService.previewThumbnail(for: item)
  }

  func selectItem(at index: Int, mode: ClipboardSelectionMode = .replace) {
    guard index >= 0 && index < visibleItems.count else { return }
    let item = visibleItems[index]
    switch mode {
    case .replace:
      setActiveSelection(item, at: index, selectedIDs: [item.id], anchorID: item.id)
    case .toggle:
      var nextIDs = selectedItemIDs.isEmpty ? selectedItem.map { [$0.id] } ?? [] : selectedItemIDs
      if nextIDs.contains(item.id) {
        if nextIDs.count > 1 {
          nextIDs.removeAll { $0 == item.id }
        }
      } else {
        nextIDs.append(item.id)
      }
      setActiveSelection(item, at: index, selectedIDs: nextIDs, anchorID: item.id)
    case .range:
      let anchorIndex = selectionAnchorItemID
        .flatMap { anchorID in visibleItems.firstIndex { $0.id == anchorID } }
        ?? selectedIndex
      let lower = min(anchorIndex, index)
      let upper = max(anchorIndex, index)
      let rangeIDs = visibleItems[lower...upper].map(\.id)
      let anchorID = visibleItems[anchorIndex].id
      setActiveSelection(item, at: index, selectedIDs: rangeIDs, anchorID: anchorID)
    case .hover:
      setActiveSelection(item, at: index, selectedIDs: [item.id], anchorID: item.id)
    case .activate:
      if selectedItemIDs.contains(item.id), selectedItemIDs.count > 1 {
        setActiveSelection(item, at: index, selectedIDs: selectedItemIDs, anchorID: selectionAnchorItemID ?? item.id)
      } else {
        setActiveSelection(item, at: index, selectedIDs: [item.id], anchorID: item.id)
      }
    }
  }

  func selectFirstItem() {
    guard !visibleItems.isEmpty else { return }
    let previousIndex = selectedIndex
    setIndexBasedSelection(at: 0)
    if previousIndex == 0 {
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    }
  }

  func selectLastItem() {
    guard !visibleItems.isEmpty else { return }
    let lastIndex = visibleItems.count - 1
    let previousIndex = selectedIndex
    setIndexBasedSelection(at: lastIndex)
    if previousIndex == lastIndex {
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    }
  }

  func moveSelection(_ delta: Int) {
    let count = visibleItems.count
    guard count > 0 else { return }
    let target = max(0, min(count - 1, selectedIndex + delta))
    setIndexBasedSelection(at: target)
  }

  func selectAllVisibleItems() {
    guard !visibleItems.isEmpty else {
      selectedItemIDs = []
      statusMessage = "No clips to select"
      return
    }

    let activeIndex = max(0, min(visibleItems.count - 1, selectedIndex))
    let activeItem = visibleItems[activeIndex]
    selectedItemID = activeItem.id
    selectionAnchorItemID = activeItem.id
    selectedItemIDs = visibleItems.map(\.id)
    if selectedIndex == activeIndex {
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    } else {
      selectedIndex = activeIndex
    }
    let noun = visibleItems.count == 1 ? "clip" : "clips"
    statusMessage = "Selected \(visibleItems.count) \(noun)"
  }

  func pasteSelected() {
    if selectedItemCount > 1 {
      pasteSelectedItems()
      return
    }
    guard let item = selectedItem else { return }
    let result = pasteService.paste(item, targetApp: targetApplicationProvider())
    if case .pasted = result {
      willPasteToTarget()
    }
    if case .failed = result {} else {
      store.markUsed(item.id)
      selectedItemID = item.id
    }
    statusMessage = result.message
    settings.setPasteStatus(message: result.message)
  }

  func pasteSelectedPlainText() {
    if selectedItemCount > 1 {
      pasteSelectedItemsAsText()
      return
    }
    guard let item = selectedItem else { return }
    let result = pasteService.pastePlainText(item, targetApp: targetApplicationProvider())
    if case .pastedPlainText = result {
      willPasteToTarget()
    }
    if case .failed = result {} else {
      store.markUsed(item.id)
      selectedItemID = item.id
    }
    statusMessage = result.message
    settings.setPasteStatus(message: result.message)
  }

  func pasteItem(at index: Int) {
    guard index >= 0 && index < visibleItems.count else { return }
    selectItem(at: index)
    pasteSelected()
  }

  func pasteItemPlainText(at index: Int) {
    guard index >= 0 && index < visibleItems.count else { return }
    selectItem(at: index)
    pasteSelectedPlainText()
  }

  func copySelected() {
    if selectedItemCount > 1 {
      copySelectedItems()
      return
    }
    guard let item = selectedItem else { return }
    let result = pasteService.copy(item)
    if case .failed = result {} else {
      store.markUsed(item.id)
      selectedItemID = item.id
    }
    statusMessage = result.message
    settings.setPasteStatus(message: result.message)
  }

  func copySelectedPlainText() {
    if selectedItemCount > 1 {
      copySelectedItemsAsText()
      return
    }
    guard let item = selectedItem else { return }
    let result = pasteService.copyPlainText(item)
    if case .failed = result {} else {
      store.markUsed(item.id)
      selectedItemID = item.id
    }
    statusMessage = result.message
    settings.setPasteStatus(message: result.message)
  }

  func isItemStacked(at index: Int) -> Bool {
    guard index >= 0 && index < visibleItems.count else { return false }
    return stackItemIDSet.contains(visibleItems[index].id)
  }

  func isItemSelected(at index: Int) -> Bool {
    guard index >= 0 && index < visibleItems.count else { return false }
    return selectedItemIDSet.contains(visibleItems[index].id)
  }

  func toggleSelectedStackMembership() {
    guard let item = selectedItem else { return }
    if stackItemIDs.contains(item.id) {
      consumeStackItem(item.id)
      statusMessage = "Removed from Stack"
      return
    }

    stackItemIDs.append(item.id)
    statusMessage = "Added to Stack"
  }

  func addVisibleItemsToStack() {
    pruneStackItems()
    guard !visibleItems.isEmpty else {
      statusMessage = "No visible clips to stack"
      return
    }

    let newIDs = visibleItems
      .map(\.id)
      .filter { !stackItemIDSet.contains($0) }
    guard !newIDs.isEmpty else {
      statusMessage = "Visible clips are already in Stack"
      return
    }

    stackItemIDs.append(contentsOf: newIDs)
    let noun = newIDs.count == 1 ? "clip" : "clips"
    statusMessage = "Added \(newIDs.count) \(noun) to Stack"
  }

  func toggleStackCaptureMode() {
    isStackCaptureEnabled.toggle()
    statusMessage = isStackCaptureEnabled ? "Stack capture is on" : "Stack capture is off"
  }

  func addCapturedItemToStack(_ item: ClipboardItem) {
    guard isStackCaptureEnabled else { return }
    pruneStackItems()
    stackItemIDs.append(item.id)
    if isStackFilterSelected {
      selectedItemID = item.id
      selectionAnchorItemID = item.id
      selectedItemIDs = [item.id]
      recomputeVisibleItems()
    }
    let noun = stackItemIDs.count == 1 ? "clip" : "clips"
    statusMessage = "Captured to Stack (\(stackItemIDs.count) \(noun))"
  }

  func selectStack() {
    guard !stackItemIDs.isEmpty || isStackCaptureEnabled else { return }
    let collectionChanged = selectedCollectionName != nil
      || !selectedSortModeFilterRawValues.isEmpty
      || !selectedCollectionNameFilters.isEmpty
    let stackChanged = !isStackFilterSelected
    guard collectionChanged || stackChanged else { return }
    isBatchingFilterSelectionChanges = true
    selectedCollectionName = nil
    selectedSortModeFilterRawValues.removeAll(keepingCapacity: true)
    selectedCollectionNameFilters.removeAll(keepingCapacity: true)
    isStackFilterSelected = true
    isBatchingFilterSelectionChanges = false
    recomputeVisibleItems()
    if collectionChanged {
      onCollectionsChanged?()
    }
  }

  func clearStackSelection() {
    guard isStackFilterSelected else { return }
    isStackFilterSelected = false
  }

  func clearStack() {
    guard !stackItemIDs.isEmpty else {
      statusMessage = "Stack is empty"
      return
    }
    stackItemIDs.removeAll()
    isStackFilterSelected = false
    statusMessage = "Cleared Stack"
  }

  func copyNextStackItem() {
    guard let item = nextStackItem() else {
      statusMessage = "Stack is empty"
      return
    }

    let result = pasteService.copy(item)
    handleStackActionResult(result, item: item)
  }

  func pasteNextStackItem() {
    guard let item = nextStackItem() else {
      statusMessage = "Stack is empty"
      return
    }

    let result = pasteService.paste(item, targetApp: targetApplicationProvider())
    if case .pasted = result {
      willPasteToTarget()
    }
    handleStackActionResult(result, item: item)
  }

  func copyStackAsText() {
    guard let package = stackPlainTextPackage() else {
      statusMessage = "Stack has no text to copy"
      return
    }

    let result = pasteService.copyPlainText(package.text)
    handleStackPlainTextActionResult(result, items: package.items)
  }

  func pasteStackAsText() {
    guard let package = stackPlainTextPackage() else {
      statusMessage = "Stack has no text to paste"
      return
    }

    let result = pasteService.pastePlainText(package.text, targetApp: targetApplicationProvider())
    if case .pastedPlainText = result {
      willPasteToTarget()
    }
    handleStackPlainTextActionResult(result, items: package.items)
  }

  func addSelectedItemsToStack() {
    pruneStackItems()
    let selectedItems = selectedItemsInSelectionOrder()
    guard !selectedItems.isEmpty else {
      statusMessage = "No selected clips to stack"
      return
    }

    let newIDs = selectedItems
      .map(\.id)
      .filter { !stackItemIDSet.contains($0) }
    guard !newIDs.isEmpty else {
      statusMessage = "Selected clips are already in Stack"
      return
    }

    stackItemIDs.append(contentsOf: newIDs)
    let noun = newIDs.count == 1 ? "clip" : "clips"
    statusMessage = "Added \(newIDs.count) selected \(noun) to Stack"
  }

  func copySelectedItems() {
    let selectedItems = selectedItemsInSelectionOrder()
    guard selectedItems.count > 1 else {
      copySelected()
      return
    }

    let result = pasteService.copy(selectedItems)
    handleSelectedActionResult(result, items: selectedItems)
  }

  func pasteSelectedItems() {
    let selectedItems = selectedItemsInSelectionOrder()
    guard selectedItems.count > 1 else {
      pasteSelected()
      return
    }

    let result = pasteService.paste(selectedItems, targetApp: targetApplicationProvider())
    if case .pasted = result {
      willPasteToTarget()
    }
    handleSelectedActionResult(result, items: selectedItems)
  }

  func copySelectedItemsAsText() {
    guard let package = selectedPlainTextPackage() else {
      statusMessage = "Selection has no text to copy"
      return
    }

    let result = pasteService.copyPlainText(package.text)
    handleSelectedPlainTextActionResult(result, items: package.items)
  }

  func pasteSelectedItemsAsText() {
    guard let package = selectedPlainTextPackage() else {
      statusMessage = "Selection has no text to paste"
      return
    }

    let result = pasteService.pastePlainText(package.text, targetApp: targetApplicationProvider())
    if case .pastedPlainText = result {
      willPasteToTarget()
    }
    handleSelectedPlainTextActionResult(result, items: package.items)
  }

  func pasteboardWriters(forItemAt index: Int) -> [NSPasteboardWriting] {
    guard index >= 0 && index < visibleItems.count else { return [] }
    return pasteService.pasteboardWriters(for: visibleItems[index])
  }

  func editableTextForSelected() -> String? {
    guard let item = selectedItem, item.kind == .text || item.kind == .code else { return nil }
    return item.payload
  }

  func editableTextForItem(at index: Int) -> String? {
    guard index >= 0 && index < visibleItems.count else { return nil }
    let item = visibleItems[index]
    guard item.kind == .text || item.kind == .code else { return nil }
    return item.payload
  }

  func editableTitleForSelected() -> String? {
    guard let item = selectedItem else { return nil }
    return item.customTitle ?? ""
  }

  @discardableResult
  func createTextClip(_ text: String, now: Date = Date()) -> ClipboardItem? {
    let trimmed = text.clipboardTrimmed
    guard !trimmed.isEmpty else {
      statusMessage = "Text clip cannot be empty"
      return nil
    }

    let kind: ClipboardItemKind = CodeSnippetPayload.isLikelyCode(trimmed) ? .code : .text
    let displayText = kind == .code ? CodeSnippetPayload.title(from: trimmed) : trimmed
    let collectionName = selectedCollectionName.flatMap(ClipboardCollectionDefaults.normalizedName)
    let payloadHash = store.hashString(trimmed)
    let item = ClipboardItem(
      id: UUID(),
      kind: kind,
      displayText: displayText,
      payload: trimmed,
      payloadHash: payloadHash,
      createdAt: now,
      lastUsedAt: now,
      useCount: 0,
      sourceApp: AppConfiguration.appName,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: Bundle.main.bundleIdentifier,
      collectionName: collectionName
    )

    let selectedID = settings.pruneDuplicates
      ? items.first(where: { $0.payloadHash == payloadHash })?.id ?? item.id
      : item.id
    selectedItemID = selectedID
    selectionAnchorItemID = selectedID
    selectedItemIDs = [selectedID]

    let searchChanged = !searchText.clipboardTrimmed.isEmpty
    let stackChanged = isStackFilterSelected
    let targetSortMode: ClipboardSortMode? = collectionName == nil && !sortMode.includes(item)
      ? (kind == .code ? .code : .text)
      : nil

    isBatchingFilterSelectionChanges = true
    if stackChanged {
      isStackFilterSelected = false
    }
    if searchChanged {
      searchText = ""
    }
    if let targetSortMode {
      sortMode = targetSortMode
    }
    isBatchingFilterSelectionChanges = false

    let storedItem = store.upsert(item)
    if searchChanged {
      notifyMain { self.onSearchTextChanged?(self.searchText) }
    }
    if let targetSortMode {
      onSortModeChanged?(targetSortMode)
    }
    if store.items.contains(where: { $0.id == storedItem.id }) {
      selectedItemID = storedItem.id
      selectionAnchorItemID = storedItem.id
      selectedItemIDs = [storedItem.id]
      statusMessage = kind == .code ? "Created code clip" : "Created text clip"
      return storedItem
    }
    statusMessage = kind == .code ? "Created code clip" : "Created text clip"
    return item
  }

  func updateSelectedTitle(to title: String) {
    guard let item = selectedItem else { return }
    let normalizedTitle = ClipboardItem.normalizedCustomTitle(title)
    guard item.customTitle != normalizedTitle else {
      statusMessage = "No changes"
      return
    }

    selectedItemID = item.id
    store.setCustomTitle(item.id, title: normalizedTitle)
    statusMessage = normalizedTitle == nil ? "Cleared clip title" : "Renamed clip"
  }

  func updateSelectedText(to text: String) {
    guard let item = selectedItem, item.kind == .text || item.kind == .code else { return }
    let trimmed = text.clipboardTrimmed
    guard !trimmed.isEmpty else {
      statusMessage = "Text clip cannot be empty"
      return
    }
    guard item.payload != text else {
      statusMessage = "No changes"
      return
    }

    selectedItemID = item.id
    if store.updateText(item.id, text: text) {
      statusMessage = item.kind == .code ? "Updated code clip" : "Updated text clip"
    }
  }

  func rotateSelectedImageClockwise() {
    guard let item = selectedItem, item.kind == .image else { return }
    let imagePath = item.imagePath ?? item.payload
    guard let data = cacheService.data(for: imagePath),
          let image = NSImage(data: data),
          let rotated = image.rotatedClockwise(),
          let fullData = rotated.pngData(),
          let thumbnailData = rotated.resized(to: CGSize(width: 320, height: 320)).pngData(),
          let fullPath = cacheService.cacheImageSidecarData(fullData, id: item.id),
          let thumbnailPath = cacheService.cacheImageSidecarData(thumbnailData, id: item.id, fileNamePrefix: "thumb") else {
      statusMessage = "Could not rotate image"
      return
    }

    selectedItemID = item.id
    let payloadHash = store.hashData(fullData)
    if store.updateImage(
      item.id,
      imagePath: fullPath,
      thumbnailPath: thumbnailPath,
      payloadHash: payloadHash
    ) {
      statusMessage = "Rotated image"
    } else {
      statusMessage = "Could not rotate image"
    }
  }

  func extractTextFromSelectedImage() {
    guard let item = selectedItem, item.kind == .image else { return }
    let imagePath = item.imagePath ?? item.payload
    guard let data = cacheService.data(for: imagePath),
          let image = NSImage(data: data) else {
      statusMessage = "Could not read image"
      return
    }

    guard let text = ImageTextExtractor.normalizedRecognizedText(imageTextExtractor(image)) else {
      statusMessage = "No text found in image"
      return
    }

    selectedItemID = item.id
    if store.updateImageText(item.id, ocrText: text) {
      statusMessage = "Extracted text from image"
    } else {
      statusMessage = "Could not save image text"
    }
  }

  func previewURLForSelected() -> URL? {
    guard let item = selectedItem else { return nil }
    return previewURL(for: item)
  }

  func linkPreviewRequestForSelected() -> LinkPreviewRequest? {
    guard let item = selectedItem else { return nil }
    return linkPreviewRequest(for: item)
  }

  internal func previewURL(for item: ClipboardItem) -> URL? {
    cacheService.temporaryPreviewURL(for: item)
  }

  internal func linkPreviewRequest(for item: ClipboardItem) -> LinkPreviewRequest? {
    guard item.kind == .url,
          let url = URL(string: item.payload.clipboardTrimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
      return nil
    }

    let title = item.displayText.clipboardTrimmed.isEmpty ? url.absoluteString : item.displayText
    return LinkPreviewRequest(url: url, title: title)
  }

  func openSelected() {
    guard let item = selectedItem else { return }
    switch item.kind {
    case .url:
      guard let url = URL(string: item.payload) else { return }
      NSWorkspace.shared.open(url)
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      guard !urls.isEmpty, urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
      NSWorkspace.shared.activateFileViewerSelecting(urls)
    case .image:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.open(url)
    case .pdf:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.open(url)
    case .audio:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.open(url)
    case .video:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.open(url)
    case .color:
      break
    default:
      break
    }
  }

  func revealSelected() {
    guard let item = selectedItem else { return }
    switch item.kind {
    case .image:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      guard !urls.isEmpty, urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
      NSWorkspace.shared.activateFileViewerSelecting(urls)
    case .pdf:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .audio:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .video:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .color:
      break
    default:
      break
    }
  }

  func deleteSelected() {
    let selectedItems = selectedItemsInSelectionOrder()
    guard !selectedItems.isEmpty else { return }

    purgePendingDeletionUndo()
    let originalVisibleCount = visibleItems.count
    let firstDeletedVisibleIndex = selectedItems
      .compactMap { item in visibleItems.firstIndex { $0.id == item.id } }
      .min() ?? selectedIndex

    let removalOrder = selectedItems.sorted { lhs, rhs in
      let lhsIndex = items.firstIndex { $0.id == lhs.id } ?? -1
      let rhsIndex = items.firstIndex { $0.id == rhs.id } ?? -1
      return lhsIndex > rhsIndex
    }
    let removals = removalOrder.compactMap { item in
      store.remove(item.id, purgeManagedCache: false)
    }
    guard !removals.isEmpty else { return }

    pendingDeletionUndo = removals
    let removedIDs = Set(removals.map(\.item.id))
    stackItemIDs.removeAll { removedIDs.contains($0) }

    if visibleItems.isEmpty {
      selectedIndex = 0
      selectedItemID = nil
      selectionAnchorItemID = nil
      selectedItemIDs = []
    } else {
      let remainingVisibleCount = originalVisibleCount - removals.count
      let nextIndex = max(0, min(visibleItems.count - 1, min(firstDeletedVisibleIndex, remainingVisibleCount)))
      setIndexBasedSelection(at: nextIndex)
    }

    let noun = removals.count == 1 ? "clip" : "clips"
    statusMessage = "Deleted \(removals.count) \(noun)"
  }

  func clearHistory(since cutoff: Date) {
    purgePendingDeletionUndo()
    let ids = items.filter { $0.createdAt >= cutoff }.map(\.id)
    guard !ids.isEmpty else {
      finishClearHistory(removedCount: 0)
      return
    }
    isDeferringLocalStoreRecompute = true
    for id in ids {
      store.remove(id)
    }
    isDeferringLocalStoreRecompute = false
    recomputeVisibleItems()
    finishClearHistory(removedCount: ids.count)
  }

  func undoLastDelete() {
    guard !pendingDeletionUndo.isEmpty else {
      statusMessage = "Nothing to undo"
      return
    }

    let removals = pendingDeletionUndo
    pendingDeletionUndo = []
    store.restore(removals)

    let restoredIDs = removals
      .sorted(by: { $0.index < $1.index })
      .map(\.item.id)
    let visibleRestoredIDs = restoredIDs.filter { id in
      visibleItems.contains { $0.id == id }
    }
    if let firstRestoredID = visibleRestoredIDs.first,
       let restoredIndex = visibleItems.firstIndex(where: { $0.id == firstRestoredID }) {
      setActiveSelection(
        visibleItems[restoredIndex],
        at: restoredIndex,
        selectedIDs: visibleRestoredIDs,
        anchorID: firstRestoredID
      )
    }

    let noun = removals.count == 1 ? "clip" : "clips"
    statusMessage = "Restored \(removals.count) \(noun)"
  }

  func togglePinSelected() {
    guard let item = selectedItem else { return }
    store.togglePin(item.id)
  }

  func assignSelected(to collectionName: String?) {
    guard let item = selectedItem else { return }
    selectedItemID = item.id
    assign(item: item, to: collectionName)
  }

  func assignItem(withID id: UUID, to collectionName: String?) {
    guard let item = items.first(where: { $0.id == id }) else { return }
    selectedItemID = selectedItem?.id
    assign(item: item, to: collectionName)
  }

  func ignoreSelectedSourceApp() {
    guard let item = selectedItem else { return }
    guard let rule = sourceIgnoreRule(for: item) else {
      statusMessage = "Source app unavailable"
      return
    }

    let existing = settings.ignoredApps.map { $0.clipboardTrimmed.lowercased() }
    guard !existing.contains(rule.value.lowercased()) else {
      statusMessage = "\(rule.displayName) is already ignored"
      return
    }

    settings.ignoredApps.append(rule.value)
    statusMessage = "Ignored \(rule.displayName) for future captures"
  }

  func ignoreSelectedKind() {
    guard let item = selectedItem else { return }
    guard !settings.ignoredItemKindsRaw.contains(item.kind.rawValue) else {
      statusMessage = "\(Self.statusKindName(item.kind)) items are already ignored"
      return
    }

    settings.ignoredItemKindsRaw.append(item.kind.rawValue)
    if settings.ignoredItemKindsRaw.contains(item.kind.rawValue) {
      statusMessage = "Ignored \(Self.statusKindName(item.kind)) items for future captures"
    } else {
      statusMessage = "At least one content type must stay enabled."
    }
  }

  func categorySelectionSnapshot() -> ClipboardCategorySelectionSnapshot {
    ClipboardCategorySelectionSnapshot(
      sortMode: sortMode,
      selectedCollectionName: selectedCollectionName,
      isStackFilterSelected: isStackFilterSelected,
      selectedSortModeFilterRawValues: selectedSortModeFilterRawValues,
      selectedCollectionNameFilters: selectedCollectionNameFilters,
      selectedItemID: selectedItemID,
      selectedItemIDs: selectedItemIDs,
      selectionAnchorItemID: selectionAnchorItemID,
      selectedIndex: selectedIndex
    )
  }

  func previewSortMode(_ mode: ClipboardSortMode) {
    applyCategorySelectionSnapshot(
      ClipboardCategorySelectionSnapshot(
        sortMode: mode,
        selectedCollectionName: nil,
        isStackFilterSelected: false,
        selectedSortModeFilterRawValues: [],
        selectedCollectionNameFilters: [],
        selectedItemID: selectedItemID,
        selectedItemIDs: selectedItemIDs,
        selectionAnchorItemID: selectionAnchorItemID,
        selectedIndex: selectedIndex
      ),
      persistDefaultSortMode: false,
      restoreItemSelection: false
    )
  }

  func previewCollection(named name: String) {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return }
    applyCategorySelectionSnapshot(
      ClipboardCategorySelectionSnapshot(
        sortMode: sortMode,
        selectedCollectionName: normalizedName,
        isStackFilterSelected: false,
        selectedSortModeFilterRawValues: [],
        selectedCollectionNameFilters: [],
        selectedItemID: selectedItemID,
        selectedItemIDs: selectedItemIDs,
        selectionAnchorItemID: selectionAnchorItemID,
        selectedIndex: selectedIndex
      ),
      persistDefaultSortMode: false,
      restoreItemSelection: false
    )
  }

  func previewStack() {
    applyCategorySelectionSnapshot(
      ClipboardCategorySelectionSnapshot(
        sortMode: sortMode,
        selectedCollectionName: nil,
        isStackFilterSelected: true,
        selectedSortModeFilterRawValues: [],
        selectedCollectionNameFilters: [],
        selectedItemID: selectedItemID,
        selectedItemIDs: selectedItemIDs,
        selectionAnchorItemID: selectionAnchorItemID,
        selectedIndex: selectedIndex
      ),
      persistDefaultSortMode: false,
      restoreItemSelection: false
    )
  }

  func restoreCategorySelection(_ snapshot: ClipboardCategorySelectionSnapshot) {
    applyCategorySelectionSnapshot(snapshot, persistDefaultSortMode: false, restoreItemSelection: true)
  }

  func commitCategorySelection() {
    settings.defaultSortMode = sortMode
  }

  private func applyCategorySelectionSnapshot(
    _ snapshot: ClipboardCategorySelectionSnapshot,
    persistDefaultSortMode: Bool,
    restoreItemSelection: Bool
  ) {
    let categoryChanged = sortMode != snapshot.sortMode
      || selectedCollectionName != snapshot.selectedCollectionName
      || isStackFilterSelected != snapshot.isStackFilterSelected
      || selectedSortModeFilterRawValues != snapshot.selectedSortModeFilterRawValues
      || selectedCollectionNameFilters != snapshot.selectedCollectionNameFilters
    let selectionChanged = restoreItemSelection && (
      selectedItemID != snapshot.selectedItemID
        || selectedItemIDs != snapshot.selectedItemIDs
        || selectionAnchorItemID != snapshot.selectionAnchorItemID
        || selectedIndex != snapshot.selectedIndex
    )
    guard categoryChanged || selectionChanged else {
      if persistDefaultSortMode {
        settings.defaultSortMode = sortMode
      }
      return
    }

    let previousSortMode = sortMode
    let previousStackSelection = isStackFilterSelected
    let previousBatching = isBatchingFilterSelectionChanges
    let previousPersistenceSuppression = suppressDefaultSortModePersistence
    isBatchingFilterSelectionChanges = true
    suppressDefaultSortModePersistence = !persistDefaultSortMode
    isStackFilterSelected = snapshot.isStackFilterSelected
    selectedCollectionName = snapshot.selectedCollectionName
    selectedSortModeFilterRawValues = snapshot.selectedSortModeFilterRawValues
    selectedCollectionNameFilters = snapshot.selectedCollectionNameFilters
    sortMode = snapshot.sortMode
    isBatchingFilterSelectionChanges = previousBatching
    suppressDefaultSortModePersistence = previousPersistenceSuppression

    if restoreItemSelection {
      selectedItemID = snapshot.selectedItemID
      selectedItemIDs = snapshot.selectedItemIDs
      selectionAnchorItemID = snapshot.selectionAnchorItemID
      selectedIndex = snapshot.selectedIndex
    }

    if persistDefaultSortMode {
      settings.defaultSortMode = sortMode
    }

    recomputeVisibleItems()
    if previousSortMode != sortMode {
      onSortModeChanged?(sortMode)
    } else {
      onSortModeChanged?(sortMode)
    }
    onCollectionsChanged?()
    if previousStackSelection != isStackFilterSelected {
      onStackChanged?()
    }
  }

  func selectSortMode(_ mode: ClipboardSortMode, extending: Bool = false) {
    if extending {
      toggleSortModeCategoryFilter(mode)
      return
    }
    let categoryFiltersChanged = !selectedSortModeFilterRawValues.isEmpty || !selectedCollectionNameFilters.isEmpty
    let stackChanged = isStackFilterSelected
    let collectionChanged = selectedCollectionName != nil
    if categoryFiltersChanged || stackChanged || collectionChanged {
      isBatchingFilterSelectionChanges = true
      isStackFilterSelected = false
      selectedCollectionName = nil
      selectedSortModeFilterRawValues.removeAll(keepingCapacity: true)
      selectedCollectionNameFilters.removeAll(keepingCapacity: true)
      sortMode = mode
      isBatchingFilterSelectionChanges = false
      settings.defaultSortMode = mode
      recomputeVisibleItems()
      onSortModeChanged?(mode)
      onCollectionsChanged?()
      return
    }
    sortMode = mode
  }

  func selectCollection(named name: String) {
    selectCollection(named: name, extending: false)
  }

  func selectCollection(named name: String, extending: Bool) {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return }
    if extending {
      toggleCollectionCategoryFilter(named: normalizedName)
      return
    }
    let stackChanged = isStackFilterSelected
    let collectionChanged = selectedCollectionName != normalizedName
    let categoryFiltersChanged = !selectedSortModeFilterRawValues.isEmpty || !selectedCollectionNameFilters.isEmpty
    guard stackChanged || collectionChanged || categoryFiltersChanged else { return }
    isBatchingFilterSelectionChanges = true
    isStackFilterSelected = false
    selectedSortModeFilterRawValues.removeAll(keepingCapacity: true)
    selectedCollectionNameFilters.removeAll(keepingCapacity: true)
    selectedCollectionName = normalizedName
    isBatchingFilterSelectionChanges = false
    recomputeVisibleItems()
  }

  private func toggleSortModeCategoryFilter(_ mode: ClipboardSortMode) {
    var sortModeRawValues = selectedSortModeFilterRawValues
    var collectionNames = selectedCollectionNameFilters
    let seeded = seedCategoryFiltersIfNeeded(sortModeRawValues: &sortModeRawValues, collectionNames: &collectionNames)
    if seeded, mode != .mostRecent, sortModeRawValues == Set([ClipboardSortMode.mostRecent.rawValue]) {
      sortModeRawValues.remove(ClipboardSortMode.mostRecent.rawValue)
    }

    if sortModeRawValues.contains(mode.rawValue) {
      sortModeRawValues.remove(mode.rawValue)
    } else {
      sortModeRawValues.insert(mode.rawValue)
    }
    applyCategoryFilters(sortModeRawValues: sortModeRawValues, collectionNames: collectionNames)
  }

  private func toggleCollectionCategoryFilter(named name: String) {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return }
    var sortModeRawValues = selectedSortModeFilterRawValues
    var collectionNames = selectedCollectionNameFilters
    let seeded = seedCategoryFiltersIfNeeded(sortModeRawValues: &sortModeRawValues, collectionNames: &collectionNames)
    if seeded, sortModeRawValues == Set([ClipboardSortMode.mostRecent.rawValue]) {
      sortModeRawValues.remove(ClipboardSortMode.mostRecent.rawValue)
    }

    if let existingIndex = collectionNames.firstIndex(where: { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
      collectionNames.remove(at: existingIndex)
    } else {
      collectionNames.append(normalizedName)
    }
    applyCategoryFilters(sortModeRawValues: sortModeRawValues, collectionNames: collectionNames)
  }

  @discardableResult
  private func seedCategoryFiltersIfNeeded(sortModeRawValues: inout Set<Int>, collectionNames: inout [String]) -> Bool {
    guard sortModeRawValues.isEmpty && collectionNames.isEmpty else { return false }
    if let selectedCollectionName {
      collectionNames = [selectedCollectionName]
    } else if !isStackFilterSelected {
      sortModeRawValues = [sortMode.rawValue]
    }
    return true
  }

  private func applyCategoryFilters(sortModeRawValues: Set<Int>, collectionNames: [String]) {
    let normalizedCollectionNames = uniqueNormalizedCollectionNames(collectionNames)
    if sortModeRawValues.isEmpty && normalizedCollectionNames.isEmpty {
      let shouldManuallyRecompute = sortMode == .mostRecent
      selectedSortModeFilterRawValues.removeAll(keepingCapacity: true)
      selectedCollectionNameFilters.removeAll(keepingCapacity: true)
      isBatchingFilterSelectionChanges = true
      isStackFilterSelected = false
      selectedCollectionName = nil
      isBatchingFilterSelectionChanges = false
      sortMode = .mostRecent
      if shouldManuallyRecompute {
        recomputeVisibleItems()
        onSortModeChanged?(sortMode)
        onCollectionsChanged?()
      }
      statusMessage = "Selected Clipboard"
      return
    }

    isBatchingFilterSelectionChanges = true
    isStackFilterSelected = false
    selectedCollectionName = nil
    selectedSortModeFilterRawValues = sortModeRawValues
    selectedCollectionNameFilters = normalizedCollectionNames
    isBatchingFilterSelectionChanges = false
    recomputeVisibleItems()
    onSortModeChanged?(sortMode)
    onCollectionsChanged?()

    let count = activeCategoryFilterSelection().totalCount
    let noun = count == 1 ? "category" : "categories"
    statusMessage = "Filtered \(count) \(noun)"
  }

  private func uniqueNormalizedCollectionNames(_ names: [String]) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for name in names {
      guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { continue }
      let key = normalizedName.lowercased()
      guard seen.insert(key).inserted else { continue }
      result.append(normalizedName)
    }
    return result
  }

  func selectAdjacentCollection(delta: Int) {
    guard delta != 0 else { return }
    let names = collectionNames
    guard !names.isEmpty else {
      statusMessage = "No collections"
      return
    }

    let targetIndex: Int
    if let selectedCollectionName,
       let currentIndex = names.firstIndex(where: { $0.caseInsensitiveCompare(selectedCollectionName) == .orderedSame }) {
      targetIndex = (currentIndex + delta + names.count) % names.count
    } else {
      targetIndex = delta > 0 ? 0 : names.count - 1
    }

    let targetName = names[targetIndex]
    selectCollection(named: targetName)
    statusMessage = "Selected \(targetName)"
  }

  func createCollection(named name: String, colorHex: String? = nil, selectAfterCreate: Bool = true) {
    isApplyingLocalCollectionMutation = true
    let createdName = settings.ensureCollection(named: name, colorHex: colorHex)
    isApplyingLocalCollectionMutation = false
    collectionNamesCache = nil
    guard let normalizedName = createdName else { return }
    statusMessage = "Created \(normalizedName)"
    if selectAfterCreate {
      selectCollection(named: normalizedName)
    } else {
      recomputeVisibleItems()
      onCollectionsChanged?()
    }
  }

  func collectionColorHex(named name: String) -> String? {
    settings.collectionColorHex(forCollectionNamed: name)
  }

  @discardableResult
  func exportCollection(named name: String, to url: URL) throws -> ClipboardArchiveSummary {
    let summary = try store.exportCollection(named: name, to: url)
    if let normalizedName = ClipboardCollectionDefaults.normalizedName(name) {
      let noun = summary.itemCount == 1 ? "clip" : "clips"
      statusMessage = "Exported \(normalizedName) Pinboard with \(summary.itemCount) \(noun)"
    }
    return summary
  }

  func reportCollectionExportFailure(_ error: Error) {
    statusMessage = "Export failed: \(error.localizedDescription)"
  }

  func updateCollection(named currentName: String, to newName: String, colorHex: String? = nil) {
    guard let normalizedCurrentName = ClipboardCollectionDefaults.normalizedName(currentName) else {
      return
    }

    isApplyingLocalCollectionMutation = true
    let updatedName = settings.updateCollection(named: normalizedCurrentName, to: newName, colorHex: colorHex)
    isApplyingLocalCollectionMutation = false
    collectionNamesCache = nil
    guard let normalizedNewName = updatedName else { return }

    let selectionChanged = selectedCollectionName?.caseInsensitiveCompare(normalizedCurrentName) == .orderedSame
    isDeferringLocalStoreRecompute = true
    for item in items where item.collectionName?.caseInsensitiveCompare(normalizedCurrentName) == .orderedSame {
      store.setCollection(item.id, name: normalizedNewName)
    }
    if selectionChanged {
      isBatchingFilterSelectionChanges = true
      selectedCollectionName = normalizedNewName
      isBatchingFilterSelectionChanges = false
    }
    isDeferringLocalStoreRecompute = false
    onCollectionsChanged?()
    recomputeVisibleItems()
    statusMessage = "Updated \(normalizedNewName)"
  }

  func deleteCollection(named name: String) {
    isApplyingLocalCollectionMutation = true
    let deletedName = settings.deleteCollection(named: name)
    isApplyingLocalCollectionMutation = false
    collectionNamesCache = nil
    guard let normalizedName = deletedName else { return }
    let matchingIDs = items
      .filter { $0.collectionName?.caseInsensitiveCompare(normalizedName) == .orderedSame }
      .map(\.id)
    let selectionChanged = selectedCollectionName?.caseInsensitiveCompare(normalizedName) == .orderedSame
    isDeferringLocalStoreRecompute = true
    for id in matchingIDs {
      store.remove(id)
    }
    if selectionChanged {
      isBatchingFilterSelectionChanges = true
      selectedCollectionName = nil
      selectedCollectionNameFilters.removeAll { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }
      isBatchingFilterSelectionChanges = false
    } else {
      selectedCollectionNameFilters.removeAll { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }
    }
    isDeferringLocalStoreRecompute = false
    onCollectionsChanged?()
    recomputeVisibleItems()
    statusMessage = "Deleted \(normalizedName)"
  }

  func clearSearch() {
    searchText = ""
  }

  func showSelectedInClipboard() {
    guard canShowSelectedInClipboard, let item = selectedItem else { return }
    selectedItemID = item.id

    let searchChanged = !searchText.isEmpty
    let stackChanged = isStackFilterSelected
    let collectionChanged = selectedCollectionName != nil
      || !selectedSortModeFilterRawValues.isEmpty
      || !selectedCollectionNameFilters.isEmpty
    let sortChanged = sortMode != .mostRecent

    isBatchingFilterSelectionChanges = true
    if searchChanged {
      searchText = ""
    }
    if stackChanged {
      isStackFilterSelected = false
    }
    if collectionChanged {
      selectedCollectionName = nil
      selectedSortModeFilterRawValues.removeAll(keepingCapacity: true)
      selectedCollectionNameFilters.removeAll(keepingCapacity: true)
    }
    if sortChanged {
      sortMode = .mostRecent
    }
    isBatchingFilterSelectionChanges = false

    recomputeVisibleItems()
    if searchChanged {
      notifyMain { self.onSearchTextChanged?(self.searchText) }
    }
    if sortChanged {
      onSortModeChanged?(sortMode)
    }
    if collectionChanged {
      onCollectionsChanged?()
    }

    if let index = visibleItems.firstIndex(where: { $0.id == item.id }) {
      selectedIndex = index
      selectedItemID = item.id
    }
    statusMessage = "Showing in Clipboard"
  }

  func recomputeVisibleItems() {
    pruneStackItems()
    isRecomputingVisibleItems = true
    defer {
      isRecomputingVisibleItems = false
      notifyVisibleItemsChanged()
    }
    let previousSelection = selectedItemID
    let previousSelectedIDs = selectedItemIDs
    let query = searchText.clipboardTrimmed.lowercased()
    if isStackFilterSelected {
      let stackedItems = stackItemIDs.compactMap { itemByID[$0] }
      visibleItems = computeStackVisibleItems(from: stackedItems, query: query)
    } else {
      visibleItems = cachedVisibleItems(
        query: query,
        sortMode: sortMode,
        collectionName: selectedCollectionName,
        categoryFilters: activeCategoryFilterSelection()
      )
    }

    if let selectedID = previousSelection, let index = visibleIndexByID[selectedID] {
      selectedIndex = index
    } else if selectedIndex >= visibleItems.count {
      selectedIndex = max(0, visibleItems.count - 1)
    } else if selectedIndex < 0 {
      selectedIndex = 0
    }

    if visibleItems.isEmpty {
      selectedIndex = 0
    }

    selectedItemID = selectedItem?.id
    let visibleIDs = Set(visibleIndexByID.keys)
    let visibleSelectedIDs = previousSelectedIDs.filter { visibleIDs.contains($0) }
    if previousSelection == nil {
      selectedItemIDs = selectedItemID.map { [$0] } ?? []
    } else if !visibleSelectedIDs.isEmpty {
      selectedItemIDs = visibleSelectedIDs
    } else if let selectedItemID {
      selectedItemIDs = [selectedItemID]
    } else {
      selectedItemIDs = []
    }
    if let selectionAnchorItemID, !visibleIDs.contains(selectionAnchorItemID) {
      self.selectionAnchorItemID = selectedItemID
    }
  }

  private func notifyVisibleItemsChanged() {
    notifyMain { self.onVisibleItemsChanged?(self.visibleItems) }
  }

  private func setActiveSelection(
    _ item: ClipboardItem,
    at index: Int,
    selectedIDs: [UUID],
    anchorID: UUID?
  ) {
    selectedItemID = item.id
    selectionAnchorItemID = anchorID
    selectedItemIDs = uniqueIDs(selectedIDs)
    if selectedIndex == index {
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    } else {
      selectedIndex = index
    }
  }

  private func setIndexBasedSelection(at index: Int) {
    guard index >= 0 && index < visibleItems.count else { return }
    let item = visibleItems[index]
    selectedItemID = nil
    selectionAnchorItemID = item.id
    selectedItemIDs = [item.id]
    if selectedIndex != index {
      selectedIndex = index
    }
  }

  private func uniqueIDs(_ ids: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return ids.filter { seen.insert($0).inserted }
  }

  private func rebuildItemIndexes() {
    var nextItemByID: [UUID: ClipboardItem] = [:]
    nextItemByID.reserveCapacity(items.count)
    var nextItemIDSet = Set<UUID>()
    nextItemIDSet.reserveCapacity(items.count)
    var nextCollectionItems: [String: [IndexedClipboardItem]] = [:]
    var nextAssignedCollectionNames: [String: String] = [:]
    var nextSortModeItems: [Int: [IndexedClipboardItem]] = [:]
    var allItems: [IndexedClipboardItem] = []
    allItems.reserveCapacity(items.count)

    for (offset, item) in items.enumerated() {
      if nextItemByID[item.id] == nil {
        nextItemByID[item.id] = item
      }
      nextItemIDSet.insert(item.id)

      let indexedItem = IndexedClipboardItem(offset: offset, item: item)
      allItems.append(indexedItem)

      if let collectionName = ClipboardCollectionDefaults.normalizedName(item.collectionName) {
        let collectionKey = collectionName.lowercased()
        nextAssignedCollectionNames[collectionKey] = collectionName
        nextCollectionItems[collectionKey, default: []].append(indexedItem)
      }

      appendIndexedItem(indexedItem, for: item, to: &nextSortModeItems)
    }

    nextSortModeItems[ClipboardSortMode.mostRecent.rawValue] = allItems
    nextSortModeItems[ClipboardSortMode.mostUsed.rawValue] = allItems
    itemByID = nextItemByID
    itemIDSet = nextItemIDSet
    indexedItemsByCollectionKey = nextCollectionItems
    indexedItemsBySortMode = nextSortModeItems
    assignedCollectionNamesByKey = nextAssignedCollectionNames
  }

  private func appendIndexedItem(
    _ indexedItem: IndexedClipboardItem,
    for item: ClipboardItem,
    to indexedItemsBySortMode: inout [Int: [IndexedClipboardItem]]
  ) {
    switch item.kind {
    case .image:
      indexedItemsBySortMode[ClipboardSortMode.images.rawValue, default: []].append(indexedItem)
    case .url:
      indexedItemsBySortMode[ClipboardSortMode.links.rawValue, default: []].append(indexedItem)
    case .text, .richText:
      indexedItemsBySortMode[ClipboardSortMode.text.rawValue, default: []].append(indexedItem)
    case .code:
      indexedItemsBySortMode[ClipboardSortMode.text.rawValue, default: []].append(indexedItem)
      indexedItemsBySortMode[ClipboardSortMode.code.rawValue, default: []].append(indexedItem)
    case .file, .pdf:
      indexedItemsBySortMode[ClipboardSortMode.files.rawValue, default: []].append(indexedItem)
    case .audio:
      indexedItemsBySortMode[ClipboardSortMode.audio.rawValue, default: []].append(indexedItem)
    case .color:
      indexedItemsBySortMode[ClipboardSortMode.colors.rawValue, default: []].append(indexedItem)
    case .video:
      indexedItemsBySortMode[ClipboardSortMode.videos.rawValue, default: []].append(indexedItem)
    case .unknown:
      break
    }

    if item.isPinned {
      indexedItemsBySortMode[ClipboardSortMode.pinned.rawValue, default: []].append(indexedItem)
    }
  }

  private func uniqueSearchFacetValues(_ values: [String?]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      guard let normalized = value?.clipboardTrimmed, !normalized.isEmpty else { continue }
      let key = Self.normalizedSearchValue(normalized)
      guard seen.insert(key).inserted else { continue }
      result.append(normalized)
    }
    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private func selectedItemsInSelectionOrder() -> [ClipboardItem] {
    let selectedItems = selectedItemIDs.compactMap { visibleItemByID[$0] }
    if !selectedItems.isEmpty {
      return selectedItems
    }
    return selectedItem.map { [$0] } ?? []
  }

  private func nextStackItem() -> ClipboardItem? {
    pruneStackItems()
    guard let id = stackItemIDs.first else { return nil }
    return itemByID[id]
  }

  private func stackPlainTextPackage() -> (text: String, items: [ClipboardItem])? {
    pruneStackItems()
    let pairs: [(item: ClipboardItem, text: String)] = stackItemIDs.compactMap { id in
      guard let item = itemByID[id],
            let text = pasteService.plainText(for: item)?.clipboardTrimmed,
            !text.isEmpty else {
        return nil
      }
      return (item, text)
    }
    guard !pairs.isEmpty else { return nil }
    return (pairs.map(\.text).joined(separator: "\n\n"), pairs.map(\.item))
  }

  private func selectedPlainTextPackage() -> (text: String, items: [ClipboardItem])? {
    let pairs: [(item: ClipboardItem, text: String)] = selectedItemsInSelectionOrder().compactMap { item in
      guard let text = pasteService.plainText(for: item)?.clipboardTrimmed, !text.isEmpty else {
        return nil
      }
      return (item, text)
    }
    guard !pairs.isEmpty else { return nil }
    return (pairs.map(\.text).joined(separator: "\n\n"), pairs.map(\.item))
  }

  private func handleStackActionResult(_ result: PasteActionService.PasteActionResult, item: ClipboardItem) {
    if case .failed(let message) = result {
      statusMessage = message
      return
    }

    consumeStackItem(item.id)
    store.markUsed(item.id)
    selectedItemID = item.id
    switch result {
    case .copiedNeedsPermission:
      statusMessage = "Copied from Stack. Grant Accessibility access to paste automatically."
    case .pasted:
      statusMessage = "Pasted from Stack"
    case .copied:
      statusMessage = "Copied from Stack"
    default:
      statusMessage = result.message
    }
    settings.setPasteStatus(message: statusMessage)
  }

  private func handleStackPlainTextActionResult(_ result: PasteActionService.PasteActionResult, items: [ClipboardItem]) {
    if case .failed(let message) = result {
      statusMessage = message
      return
    }

    for item in items {
      store.markUsed(item.id)
      consumeStackItem(item.id, refreshActiveStackFilter: false)
    }
    if stackItemIDs.isEmpty {
      isStackFilterSelected = false
    } else if isStackFilterSelected {
      recomputeVisibleItems()
    }
    selectedItemID = items.first?.id
    let noun = items.count == 1 ? "clip" : "clips"
    switch result {
    case .pastedPlainText:
      statusMessage = "Pasted \(items.count) Stack \(noun) as Text"
    case .copiedPlainTextNeedsPermission:
      statusMessage = "Copied \(items.count) Stack \(noun) as Text. Grant Accessibility access to paste automatically."
    case .copiedPlainText:
      statusMessage = "Copied \(items.count) Stack \(noun) as Text"
    default:
      statusMessage = result.message
    }
    settings.setPasteStatus(message: statusMessage)
  }

  private func handleSelectedActionResult(_ result: PasteActionService.PasteActionResult, items: [ClipboardItem]) {
    if case .failed(let message) = result {
      statusMessage = message
      return
    }

    for item in items {
      store.markUsed(item.id)
    }
    selectedItemID = items.first?.id
    let noun = items.count == 1 ? "clip" : "clips"
    switch result {
    case .pasted:
      statusMessage = "Pasted \(items.count) selected \(noun)"
    case .copiedNeedsPermission:
      statusMessage = "Copied \(items.count) selected \(noun). Grant Accessibility access to paste automatically."
    case .copied:
      statusMessage = "Copied \(items.count) selected \(noun)"
    default:
      statusMessage = result.message
    }
    settings.setPasteStatus(message: statusMessage)
  }

  private func handleSelectedPlainTextActionResult(_ result: PasteActionService.PasteActionResult, items: [ClipboardItem]) {
    if case .failed(let message) = result {
      statusMessage = message
      return
    }

    for item in items {
      store.markUsed(item.id)
    }
    selectedItemID = items.first?.id
    let noun = items.count == 1 ? "clip" : "clips"
    switch result {
    case .pastedPlainText:
      statusMessage = "Pasted \(items.count) selected \(noun) as Text"
    case .copiedPlainTextNeedsPermission:
      statusMessage = "Copied \(items.count) selected \(noun) as Text. Grant Accessibility access to paste automatically."
    case .copiedPlainText:
      statusMessage = "Copied \(items.count) selected \(noun) as Text"
    default:
      statusMessage = result.message
    }
    settings.setPasteStatus(message: statusMessage)
  }

  private func consumeStackItem(_ id: UUID, refreshActiveStackFilter: Bool = true) {
    guard let index = stackItemIDs.firstIndex(of: id) else { return }
    stackItemIDs.remove(at: index)
    if refreshActiveStackFilter && isStackFilterSelected {
      recomputeVisibleItems()
    }
  }

  private func pruneStackItems() {
    guard !stackItemIDs.isEmpty else { return }
    let pruned = stackItemIDs.filter { itemIDSet.contains($0) }
    if pruned != stackItemIDs {
      stackItemIDs = pruned
    }
    if stackItemIDs.isEmpty && isStackFilterSelected && !isStackCaptureEnabled {
      isStackFilterSelected = false
    }
  }

  private func purgePendingDeletionUndo() {
    guard !pendingDeletionUndo.isEmpty else { return }
    store.purgeManagedCacheReferences(for: pendingDeletionUndo)
    pendingDeletionUndo = []
  }

  private func finishClearHistory(removedCount: Int) {
    guard removedCount > 0 else {
      statusMessage = "No clips to clear"
      return
    }
    let noun = removedCount == 1 ? "clip" : "clips"
    statusMessage = "Cleared \(removedCount) \(noun)"
  }

  private func computeStackVisibleItems(from items: [ClipboardItem], query: String) -> [ClipboardItem] {
    let parsedQuery = parseSearchQuery(query)
    guard !parsedQuery.isEmpty else { return items }
    return items.filter { matchesSearchQuery($0, query: parsedQuery) }
  }

  private func cachedVisibleItems(
    query: String,
    sortMode: ClipboardSortMode,
    collectionName: String?,
    categoryFilters: CategoryFilterSelection = .empty
  ) -> [ClipboardItem] {
    let collectionNameKey = ClipboardCollectionDefaults.normalizedName(collectionName)?.lowercased()
    let key = VisibleItemsCacheKey(
      query: query,
      sortMode: sortMode.rawValue,
      collectionNameKey: collectionNameKey,
      sortModeFilterRawValues: categoryFilters.sortModeRawValues,
      collectionNameFilterKeys: categoryFilters.collectionNameKeys
    )
    if let cached = visibleItemsCache[key] {
      return cached
    }

    let computed: [ClipboardItem]
    if query.isEmpty,
       var indexedItems = indexedVisibleItems(
         sortMode: sortMode,
         collectionName: collectionName,
         categoryFilters: categoryFilters
       ) {
      sortIndexedItems(
        &indexedItems,
        ordering: sortOrdering(sortMode: sortMode, collectionName: collectionName, categoryFilters: categoryFilters)
      )
      computed = indexedItems.map(\.item)
      #if DEBUG
      debugVisibleItemsIndexedLookupCount += 1
      #endif
    } else {
      computed = computeVisibleItems(
        from: items,
        query: query,
        sortMode: sortMode,
        collectionName: collectionName,
        categoryFilters: categoryFilters
      )
      #if DEBUG
      debugVisibleItemsFullScanCount += 1
      #endif
    }
    if visibleItemsCache.count > 24 {
      visibleItemsCache.removeAll(keepingCapacity: true)
    }
    visibleItemsCache[key] = computed
    return computed
  }

  private func indexedVisibleItems(
    sortMode: ClipboardSortMode,
    collectionName: String?,
    categoryFilters: CategoryFilterSelection = .empty
  ) -> [IndexedClipboardItem]? {
    if !categoryFilters.isEmpty {
      return indexedVisibleItems(matching: categoryFilters)
    }
    if let collectionKey = ClipboardCollectionDefaults.normalizedName(collectionName)?.lowercased() {
      return indexedItemsByCollectionKey[collectionKey] ?? []
    }
    return indexedItemsBySortMode[sortMode.rawValue]
  }

  private func indexedVisibleItems(matching categoryFilters: CategoryFilterSelection) -> [IndexedClipboardItem] {
    var indexedItemsByID: [UUID: IndexedClipboardItem] = [:]

    for rawValue in categoryFilters.sortModeRawValues {
      for indexedItem in indexedItemsBySortMode[rawValue] ?? [] {
        if indexedItemsByID[indexedItem.item.id] == nil {
          indexedItemsByID[indexedItem.item.id] = indexedItem
        }
      }
    }

    for collectionKey in categoryFilters.collectionNameKeys {
      for indexedItem in indexedItemsByCollectionKey[collectionKey] ?? [] {
        if indexedItemsByID[indexedItem.item.id] == nil {
          indexedItemsByID[indexedItem.item.id] = indexedItem
        }
      }
    }

    return Array(indexedItemsByID.values)
  }

  internal func computeVisibleItems(
    from items: [ClipboardItem],
    query: String,
    sortMode: ClipboardSortMode,
    collectionName: String? = nil
  ) -> [ClipboardItem] {
    computeVisibleItems(
      from: items,
      query: query,
      sortMode: sortMode,
      collectionName: collectionName,
      categoryFilters: .empty
    )
  }

  private func computeVisibleItems(
    from items: [ClipboardItem],
    query: String,
    sortMode: ClipboardSortMode,
    collectionName: String? = nil,
    categoryFilters: CategoryFilterSelection = .empty
  ) -> [ClipboardItem] {
    let parsedQuery = parseSearchQuery(query)
    let normalizedCollectionName = ClipboardCollectionDefaults.normalizedName(collectionName)
    var filtered: [IndexedClipboardItem] = []
    filtered.reserveCapacity(items.count)

    for (offset, item) in items.enumerated() {
      if !parsedQuery.isEmpty, !matchesSearchQuery(item, query: parsedQuery) {
        continue
      }
      if !categoryFilters.isEmpty {
        guard itemMatchesCategoryFilters(item, filters: categoryFilters) else {
          continue
        }
      } else if let normalizedCollectionName {
        guard item.collectionName?.caseInsensitiveCompare(normalizedCollectionName) == .orderedSame else {
          continue
        }
      } else if !sortMode.includes(item) {
        continue
      }
      filtered.append(IndexedClipboardItem(offset: offset, item: item))
    }

    sortIndexedItems(
      &filtered,
      ordering: sortOrdering(sortMode: sortMode, collectionName: collectionName, categoryFilters: categoryFilters)
    )
    return filtered.map(\.item)
  }

  private func sortOrdering(
    sortMode: ClipboardSortMode,
    collectionName: String?,
    categoryFilters: CategoryFilterSelection = .empty
  ) -> VisibleItemsSortOrdering {
    if categoryFilters.totalCount > 1 {
      return .recency
    }
    if let rawValue = categoryFilters.sortModeRawValues.first,
       let mode = ClipboardSortMode(rawValue: rawValue),
       categoryFilters.collectionNameKeys.isEmpty {
      return sortOrdering(sortMode: mode, collectionName: nil)
    }
    if !categoryFilters.collectionNameKeys.isEmpty {
      return .recency
    }
    if ClipboardCollectionDefaults.normalizedName(collectionName) != nil {
      return .recency
    }

    switch sortMode {
    case .mostRecent, .pinned:
      return .recency
    case .mostUsed:
      return .useCount
    case .images, .links, .text, .files, .audio, .videos, .colors, .code:
      return .lastUsed
    @unknown default:
      return .original
    }
  }

  private func activeCategoryFilterSelection() -> CategoryFilterSelection {
    guard !selectedSortModeFilterRawValues.isEmpty || !selectedCollectionNameFilters.isEmpty else {
      return .empty
    }
    let sortModeRawValues = selectedSortModeFilterRawValues.sorted()
    let collectionKeys = selectedCollectionNameFilters
      .compactMap { ClipboardCollectionDefaults.normalizedName($0)?.lowercased() }
      .sorted()
    return CategoryFilterSelection(
      sortModeRawValues: sortModeRawValues,
      collectionNameKeys: collectionKeys
    )
  }

  private func itemMatchesCategoryFilters(_ item: ClipboardItem, filters: CategoryFilterSelection) -> Bool {
    for rawValue in filters.sortModeRawValues {
      if let mode = ClipboardSortMode(rawValue: rawValue), mode.includes(item) {
        return true
      }
    }

    guard let collectionName = ClipboardCollectionDefaults.normalizedName(item.collectionName)?.lowercased() else {
      return false
    }
    return filters.collectionNameKeys.contains(collectionName)
  }

  private func sortIndexedItems(
    _ items: inout [IndexedClipboardItem],
    ordering: VisibleItemsSortOrdering
  ) {
    guard items.count > 1 else { return }
    items.sort { lhs, rhs in
      switch ordering {
      case .recency:
        return recencyPrecedes(lhs, rhs)
      case .useCount:
        return useCountPrecedes(lhs, rhs)
      case .lastUsed:
        return lastUsedPrecedes(lhs, rhs)
      case .original:
        return lhs.offset < rhs.offset
      }
    }
  }

  private func recencyPrecedes(_ lhs: IndexedClipboardItem, _ rhs: IndexedClipboardItem) -> Bool {
    if lhs.item.lastUsedAt == rhs.item.lastUsedAt {
      if lhs.item.createdAt == rhs.item.createdAt {
        return lhs.offset < rhs.offset
      }
      return lhs.item.createdAt > rhs.item.createdAt
    }
    return lhs.item.lastUsedAt > rhs.item.lastUsedAt
  }

  private func useCountPrecedes(_ lhs: IndexedClipboardItem, _ rhs: IndexedClipboardItem) -> Bool {
    if lhs.item.useCount == rhs.item.useCount {
      return lastUsedPrecedes(lhs, rhs)
    }
    return lhs.item.useCount > rhs.item.useCount
  }

  private func lastUsedPrecedes(_ lhs: IndexedClipboardItem, _ rhs: IndexedClipboardItem) -> Bool {
    if lhs.item.lastUsedAt == rhs.item.lastUsedAt {
      return lhs.offset < rhs.offset
    }
    return lhs.item.lastUsedAt > rhs.item.lastUsedAt
  }

  private func searchableText(for item: ClipboardItem) -> String {
    var base = Self.normalizedSearchValue(item.searchableText)
    if settings.includeImageTextInSearch, let ocrText = item.ocrText {
      base += " \(Self.normalizedSearchValue(ocrText))"
    }
    return base
  }

  private func matchesSearchQuery(_ item: ClipboardItem, query: ParsedSearchQuery) -> Bool {
    if !query.textTokens.isEmpty {
      let text = searchableText(for: item)
      guard query.textTokens.allSatisfy({ text.contains($0) }) else { return false }
    }

    if !query.appTokenGroups.isEmpty {
      let sourceValues = [item.sourceApp, item.sourceAppBundleId]
        .compactMap { $0 }
        .map(normalizedStructuredValue)
        .filter { !$0.isEmpty }
      let sourceText = sourceValues.joined(separator: " ")
      guard !sourceValues.isEmpty,
            query.appTokenGroups.contains(where: { group in
              if let exactValue = group.exactValue {
                return sourceValues.contains(exactValue)
              }
              return group.tokens.allSatisfy { sourceText.contains($0) }
            }) else {
        return false
      }
    }

    if !query.deviceTokenGroups.isEmpty {
      let device = normalizedStructuredValue(item.effectiveSourceDeviceName)
      guard query.deviceTokenGroups.contains(where: { group in
        if let exactValue = group.exactValue {
          return device == exactValue
        }
        return group.tokens.allSatisfy { device.contains($0) }
      }) else {
        return false
      }
    }

    if !query.collectionTokenGroups.isEmpty {
      guard let collectionName = item.collectionName,
            !collectionName.clipboardTrimmed.isEmpty else {
        return false
      }
      let collection = normalizedStructuredValue(collectionName)
      guard !collection.isEmpty,
            query.collectionTokenGroups.contains(where: { group in
              if let exactValue = group.exactValue {
                return collection == exactValue
              }
              return group.tokens.allSatisfy { collection.contains($0) }
            }) else {
        return false
      }
    }

    if !query.typeKinds.isEmpty, !query.typeKinds.contains(item.kind) {
      return false
    }

    if let pinned = query.pinned, item.isPinned != pinned {
      return false
    }

    if let createdAfter = query.createdAfter, item.createdAt < createdAfter {
      return false
    }

    if let createdBefore = query.createdBefore, item.createdAt >= createdBefore {
      return false
    }

    return true
  }

  private func parseSearchQuery(_ query: String) -> ParsedSearchQuery {
    var parsed = ParsedSearchQuery()
    for part in searchParts(from: query) {
      guard !part.isEmpty else { continue }
      guard let delimiter = part.firstIndex(of: ":") else {
        parsed.textTokens.append(contentsOf: searchTokens(from: part))
        continue
      }

      let key = Self.normalizedSearchValue(String(part[..<delimiter]))
      let value = String(part[part.index(after: delimiter)...]).clipboardTrimmed
      guard !value.isEmpty, applyStructuredSearchToken(key: key, value: value, to: &parsed) else {
        parsed.textTokens.append(contentsOf: searchTokens(from: part))
        continue
      }
    }
    return parsed
  }

  @discardableResult
  private func applyStructuredSearchToken(key: String, value: String, to query: inout ParsedSearchQuery) -> Bool {
    switch key {
    case "app", "source", "from":
      let groups = structuredTokenGroups(from: value)
      guard !groups.isEmpty else { return false }
      query.appTokenGroups.append(contentsOf: groups)
      return true
    case "device", "devices", "machine", "computer":
      let groups = structuredTokenGroups(from: value)
      guard !groups.isEmpty else { return false }
      query.deviceTokenGroups.append(contentsOf: groups)
      return true
    case "collection", "folder", "list", "pinboard", "pinboards", "board", "boards":
      let groups = structuredTokenGroups(from: value)
      guard !groups.isEmpty else { return false }
      query.collectionTokenGroups.append(contentsOf: groups)
      return true
    case "type", "kind":
      var matchedKinds = Set<ClipboardItemKind>()
      for segment in structuredValueSegments(from: value) {
        guard let kinds = itemKinds(matching: segment.value), !kinds.isEmpty else { return false }
        matchedKinds.formUnion(kinds)
      }
      guard !matchedKinds.isEmpty else { return false }
      query.typeKinds.formUnion(matchedKinds)
      return true
    case "pin", "pinned":
      guard let pinned = booleanValue(from: value) else { return false }
      query.pinned = pinned
      return true
    case "after", "since":
      guard let start = startOfDay(from: value) else { return false }
      query.createdAfter = maxDate(query.createdAfter, start)
      return true
    case "before", "until":
      guard let start = startOfDay(from: value) else { return false }
      query.createdBefore = minDate(query.createdBefore, start)
      return true
    case "on", "date":
      guard let start = startOfDay(from: value),
            let end = Calendar.searchCalendar.date(byAdding: .day, value: 1, to: start) else {
        return false
      }
      query.createdAfter = maxDate(query.createdAfter, start)
      query.createdBefore = minDate(query.createdBefore, end)
      return true
    default:
      return false
    }
  }

  private func searchParts(from query: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var quotedBy: Character?
    var isEscaping = false

    func flushCurrent() {
      let part = current.clipboardTrimmed
      if !part.isEmpty {
        parts.append(part)
      }
      current = ""
    }

    for character in query {
      if isEscaping {
        current.append("\\")
        current.append(character)
        isEscaping = false
        continue
      }

      if character == "\\" && quotedBy != nil {
        isEscaping = true
        continue
      }

      if character == "\"" || character == "'" {
        if quotedBy == character {
          current.append(character)
          quotedBy = nil
          continue
        }
        if quotedBy == nil {
          quotedBy = character
          current.append(character)
          continue
        }
      }

      if character.isWhitespace && quotedBy == nil {
        flushCurrent()
      } else {
        current.append(character)
      }
    }

    if isEscaping {
      current.append("\\")
    }
    flushCurrent()
    return parts
  }

  private func structuredValueSegments(from value: String) -> [StructuredFilterValue] {
    splitStructuredValues(from: value)
      .compactMap { segment in
        let trimmed = segment.clipboardTrimmed
        guard !trimmed.isEmpty else { return nil }
        if let unquoted = unquotedStructuredValue(trimmed) {
          let normalized = normalizedStructuredValue(unquoted)
          return normalized.isEmpty ? nil : StructuredFilterValue(value: normalized, isExact: true)
        }
        let normalized = normalizedStructuredValue(trimmed)
        return normalized.isEmpty ? nil : StructuredFilterValue(value: normalized, isExact: false)
      }
  }

  private func structuredTokenGroups(from value: String) -> [StructuredFilterMatcher] {
    structuredValueSegments(from: value)
      .compactMap { segment in
        let tokens = searchTokens(from: segment.value)
        guard !tokens.isEmpty else { return nil }
        return StructuredFilterMatcher(tokens: tokens, exactValue: segment.isExact ? segment.value : nil)
      }
  }

  private func splitStructuredValues(from value: String) -> [String] {
    var segments: [String] = []
    var current = ""
    var quotedBy: Character?
    var isEscaping = false

    func flushCurrent() {
      segments.append(current)
      current = ""
    }

    for character in value {
      if isEscaping {
        current.append("\\")
        current.append(character)
        isEscaping = false
        continue
      }

      if character == "\\" && quotedBy != nil {
        isEscaping = true
        continue
      }

      if character == "\"" || character == "'" {
        if quotedBy == character {
          current.append(character)
          quotedBy = nil
          continue
        }
        if quotedBy == nil {
          quotedBy = character
          current.append(character)
          continue
        }
      }

      if character == "," && quotedBy == nil {
        flushCurrent()
      } else {
        current.append(character)
      }
    }

    if isEscaping {
      current.append("\\")
    }
    flushCurrent()
    return segments
  }

  private func unquotedStructuredValue(_ value: String) -> String? {
    guard let first = value.first,
          (first == "\"" || first == "'"),
          value.last == first,
          value.count >= 2 else {
      return nil
    }
    let inner = String(value.dropFirst().dropLast())
    var unescaped = ""
    var isEscaping = false
    for character in inner {
      if isEscaping {
        unescaped.append(character)
        isEscaping = false
      } else if character == "\\" {
        isEscaping = true
      } else {
        unescaped.append(character)
      }
    }
    if isEscaping {
      unescaped.append("\\")
    }
    return unescaped
  }

  private func normalizedStructuredValue(_ value: String) -> String {
    Self.normalizedSearchValue(value)
  }

  private func itemKinds(matching value: String) -> Set<ClipboardItemKind>? {
    switch value {
    case "text", "plain":
      return [.text]
    case "richtext", "rich-text", "rtf", "html":
      return [.richText]
    case "note", "notes", "writing":
      return [.text, .richText]
    case "code", "snippet", "snippets", "source", "programming", "script", "scripts", "json", "css", "sql":
      return [.code]
    case "link", "links", "url", "urls", "web":
      return [.url]
    case "image", "images", "photo", "photos", "picture", "pictures":
      return [.image]
    case "file", "files", "finder":
      return [.file, .pdf]
    case "pdf", "pdfs", "document", "documents":
      return [.pdf]
    case "audio", "sound", "music":
      return [.audio]
    case "video", "videos", "movie", "movies", "mp4", "quicktime", "mov":
      return [.video]
    case "color", "colors", "swatch", "swatches", "hex":
      return [.color]
    case "unknown", "item":
      return [.unknown]
    default:
      return nil
    }
  }

  private func booleanValue(from value: String) -> Bool? {
    switch Self.normalizedSearchValue(value) {
    case "1", "true", "yes", "y", "on":
      return true
    case "0", "false", "no", "n", "off":
      return false
    default:
      return nil
    }
  }

  private func startOfDay(from value: String) -> Date? {
    guard let date = Self.searchDateFormatter.date(from: value) else { return nil }
    return Calendar.searchCalendar.startOfDay(for: date)
  }

  private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
    guard let lhs else { return rhs }
    return max(lhs, rhs)
  }

  private func minDate(_ lhs: Date?, _ rhs: Date) -> Date {
    guard let lhs else { return rhs }
    return min(lhs, rhs)
  }

  private func assign(item: ClipboardItem, to collectionName: String?) {
    let normalizedName = ClipboardCollectionDefaults.normalizedName(collectionName)
    if let normalizedName {
      isApplyingLocalCollectionMutation = true
      settings.ensureCollection(named: normalizedName)
      isApplyingLocalCollectionMutation = false
    }
    isDeferringLocalStoreRecompute = true
    store.setCollection(item.id, name: normalizedName)
    isDeferringLocalStoreRecompute = false
    recomputeVisibleItems()
    onCollectionsChanged?()
    if let normalizedName {
      statusMessage = "Added to \(normalizedName)"
    } else {
      statusMessage = "Removed from collection"
    }
  }

  private func sourceIgnoreRule(for item: ClipboardItem) -> (value: String, displayName: String)? {
    if let bundleID = item.sourceAppBundleId?.clipboardTrimmed, !bundleID.isEmpty {
      let sourceApp = item.sourceApp?.clipboardTrimmed
      let display = sourceApp?.isEmpty == false ? sourceApp ?? bundleID : bundleID
      return (bundleID, display)
    }

    if let sourceApp = item.sourceApp?.clipboardTrimmed, !sourceApp.isEmpty {
      return (sourceApp, sourceApp)
    }

    return nil
  }

  private static func statusKindName(_ kind: ClipboardItemKind) -> String {
    let name = kind.displayName
    return name == name.uppercased() ? name : name.capitalized
  }

  private func searchTokens(from query: String) -> [String] {
    Self.normalizedSearchValue(query)
      .split { character in
        character.isWhitespace || character.isPunctuation
      }
      .map(String.init)
  }

  private static func normalizedSearchValue(_ value: String) -> String {
    value.clipboardTrimmed
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: searchLocale)
      .lowercased()
  }

  private func notifyMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.async(execute: block)
    }
  }
}

private extension Calendar {
  static var searchCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }
}
