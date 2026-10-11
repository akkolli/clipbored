import AppKit

// A view has exactly one scope. The reducer commits related filter changes
// together and reports the effects to deliver after the new state is visible.
struct ShelfFilter {
  typealias Categories = ShelfModel.CategoryFilterSelection
  enum Scope: Equatable {
    case history, stack
    case collection(String)
    case union(Categories)
  }
  enum Category: Equatable {
    case builtin(ShelfCategory)
    case pinboard(String)
  }
  enum Action {
    case search(String)
    case category(ShelfCategory)
    case selectCategory(ShelfCategory)
    case collection(String)
    case toggle(Category)
    case history, stack, leaveStack
    case replaceCollection(String, String?)
  }
  enum Change { case reload, search, sort, collections, stack }
  var sort: ShelfCategory
  var query = ""
  var scope = Scope.history

  var collectionName: String? {
    if case .collection(let name) = scope { return name }
    return nil
  }
  var categories: Categories {
    if case .union(let selection) = scope { return selection }
    return .empty
  }

  mutating func reduce(_ action: Action) -> Set<Change> {
    switch action {
    case .search(let text):
      guard query != text else { return [] }
      let reload = ShelfModel.normalizedSearchValue(query) != ShelfModel.normalizedSearchValue(text)
      query = text
      return reload ? [.reload, .search] : [.search]
    case .category(let mode), .selectCategory(let mode):
      guard sort != mode || scope != .history else { return [] }
      var notifyCollections = false
      if case .selectCategory = action { notifyCollections = scope != .history }
      sort = mode
      scope = .history
      return notifyCollections ? [.reload, .sort, .collections] : [.reload, .sort]
    case .collection(let name):
      guard scope != .collection(name) else { return [] }
      scope = .collection(name)
      return [.reload]
    case .stack:
      guard scope != .stack else { return [] }
      let collectionChanged = collectionName != nil || !categories.isEmpty
      scope = .stack
      return collectionChanged ? [.reload, .collections] : [.reload]
    case .leaveStack:
      guard scope == .stack else { return [] }
      scope = .history
      return [.reload, .stack]
    case .history:
      var changes: Set<Change> = [.reload]
      if !query.isEmpty { changes.insert(.search) }
      if sort != .mostRecent { changes.insert(.sort) }
      if collectionName != nil || !categories.isEmpty { changes.insert(.collections) }
      query = ""
      sort = .mostRecent
      scope = .history
      return changes
    case .toggle(let category):
      var selection = categories
      if case .history = scope { selection = Categories(sortModeRawValues: [sort.rawValue], collectionNameKeys: []) }
      if let name = collectionName {
        selection = Categories(sortModeRawValues: [], collectionNameKeys: [name.lowercased()])
      }
      var modes = selection.sortModeRawValues
      var boards = selection.collectionNameKeys
      if scope == .history, sort == .mostRecent, category != .builtin(.mostRecent) {
        modes.remove(ShelfCategory.mostRecent.rawValue)
      }
      switch category {
      case .builtin(let mode): if !modes.insert(mode.rawValue).inserted { modes.remove(mode.rawValue) }
      case .pinboard(let name): if !boards.insert(name).inserted { boards.remove(name) }
      }
      selection = Categories(sortModeRawValues: modes, collectionNameKeys: boards)
      scope = selection.isEmpty ? .history : .union(selection)
      if selection.isEmpty { sort = .mostRecent }
      return [.reload, .sort, .collections]
    case .replaceCollection(let oldName, let newName):
      if collectionName?.caseInsensitiveCompare(oldName) == .orderedSame {
        scope = newName.map(Scope.collection) ?? .history
      } else if case .union(let selected) = scope {
        var boards = selected.collectionNameKeys
        if boards.remove(oldName.lowercased()) != nil, let newName { boards.insert(newName.lowercased()) }
        let updated = Categories(sortModeRawValues: selected.sortModeRawValues, collectionNameKeys: boards)
        scope = updated.isEmpty ? .history : .union(updated)
      }
      return [.reload, .collections]
    }
  }
}

// MARK: - ShelfModel

final class ShelfModel {
  static let searchDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    let calendar = Calendar.searchCalendar
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static let searchLocale = Locale(identifier: "en_US_POSIX")
  static let fallbackSourceDeviceName = Clip.localDeviceName

  struct StructuredFilterMatcher {
    let tokens: [String]
    let exactValue: String?
  }

  struct StructuredFilterValue {
    let value: String
    let isExact: Bool
  }

  struct ParsedSearchQuery {
    var textTokens: [String] = []
    var appTokenGroups: [StructuredFilterMatcher] = []
    var deviceTokenGroups: [StructuredFilterMatcher] = []
    var collectionTokenGroups: [StructuredFilterMatcher] = []
    var typeKinds: Set<ClipKind> = []
    var createdAfter: Date?
    var createdBefore: Date?
    var pinned: Bool?

    var isEmpty: Bool {
      textTokens.isEmpty && appTokenGroups.isEmpty && deviceTokenGroups.isEmpty && collectionTokenGroups.isEmpty
        && typeKinds.isEmpty && createdAfter == nil && createdBefore == nil && pinned == nil
    }
  }

  struct VisibleItemsCacheKey: Hashable {
    let query: String
    let sortMode: Int
    let collectionNameKey: String?
    let sortModeFilterRawValues: [Int]
    let collectionNameFilterKeys: [String]
  }

  struct CategoryFilterSelection: Hashable {
    let sortModeRawValues: Set<Int>
    let collectionNameKeys: Set<String>

    static let empty = CategoryFilterSelection(sortModeRawValues: [], collectionNameKeys: [])

    var isEmpty: Bool { sortModeRawValues.isEmpty && collectionNameKeys.isEmpty }

    var totalCount: Int { sortModeRawValues.count + collectionNameKeys.count }
  }

  struct IndexedClipboardItem {
    let offset: Int
    let item: Clip
  }

  struct SearchMatchCacheEntry {
    let query: String
    let indexedItems: [IndexedClipboardItem]
  }

  struct SearchDocumentFingerprint: Equatable {
    let kindRawValue: Int
    let displayText: String
    let payload: String
    let customTitle: String?
    let sourceApp: String?
    let sourceAppBundleID: String?
    let collectionName: String?
    let sourceDeviceName: String?
    let ocrText: String?
  }

  struct SearchDocument {
    let fingerprint: SearchDocumentFingerprint
    let text: String
    let textIncludingOCR: String
    let sourceValues: [String]
    let sourceText: String
    let device: String
    let collection: String
  }

  struct ThumbnailRequestKey: Hashable {
    let itemID: UUID
    let kindRawValue: Int
    let source: String?
  }

  enum TransferIntent {
    case copy
    case paste
  }

  enum TransferContext {
    case single
    case selected
    case stackItem
    case stackText
  }

  var visibleItems: [Clip] = [] {
    didSet {
      var nextItemByID: [UUID: Clip] = [:]
      nextItemByID.reserveCapacity(visibleItems.count)
      var nextIndexByID: [UUID: Int] = [:]
      nextIndexByID.reserveCapacity(visibleItems.count)
      for (index, item) in visibleItems.enumerated() {
        if nextItemByID[item.id] == nil { nextItemByID[item.id] = item }
        if nextIndexByID[item.id] == nil { nextIndexByID[item.id] = index }
      }
      visibleItemByID = nextItemByID
      visibleIndexByID = nextIndexByID
      guard !isRecomputingVisibleItems else { return }
      notifyVisibleItemsChanged()
    }
  }

  private var filter: ShelfFilter
  var searchText: String {
    get { filter.query }
    set { changeFilter(.search(newValue)) }
  }
  var sortMode: ShelfCategory {
    get { filter.sort }
    set { if newValue != sortMode { changeFilter(.category(newValue)) } }
  }
  var selectedCollectionName: String? { filter.collectionName }
  var isStackFilterSelected: Bool { filter.scope == .stack }

  func changeFilter(_ action: ShelfFilter.Action) {
    let oldSort = filter.sort
    let changes = filter.reduce(action)
    if oldSort != filter.sort { settings.defaultSortMode = filter.sort }
    if changes.contains(.reload) {
      if case .search = action { selectedItemID = selectedItem?.id }
      recomputeVisibleItems()
    }
    if changes.contains(.search) { notifyMain { self.onSearchTextChanged?(self.searchText) } }
    if changes.contains(.sort) { onSortModeChanged?(sortMode) }
    if changes.contains(.collections) { onCollectionsChanged?() }
    if changes.contains(.stack) { onStackChanged?() }
  }

  var isStackCaptureEnabled = false {
    didSet {
      guard oldValue != isStackCaptureEnabled else { return }
      if !isStackCaptureEnabled, isStackFilterSelected, stackItemIDs.isEmpty { changeFilter(.leaveStack) }
      notifyMain { self.onStackChanged?() }
    }
  }

  var selectedIndex: Int = 0 {
    didSet {
      guard oldValue != selectedIndex else { return }
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    }
  }

  var selectedItemIDs: [UUID] = [] {
    didSet {
      guard oldValue != selectedItemIDs else { return }
      selectedItemIDSet = Set(selectedItemIDs)
      notifyMain { self.onSelectedItemsChanged?() }
    }
  }

  var statusMessage: String = "" {
    didSet {
      guard oldValue != statusMessage else { return }
      notifyMain { self.onStatusMessageChanged?(self.statusMessage) }
    }
  }

  var items: [Clip] = [] {
    didSet {
      rebuildItemIndexes()
      collectionNamesCache = nil
      visibleItemsCache.removeAll(keepingCapacity: true)
      collectionCountCache = nil
      searchMatchCache = nil
      stackItemsNeedPruning = true
      searchDocumentsByItemID = searchDocumentsByItemID.filter { itemIDSet.contains($0.key) }
    }
  }

  let store: HistoryStore
  let settings: Preferences
  let cacheService: MediaCache
  let pasteService: PasteService
  let imageTextExtractor: (NSImage) -> String?
  let thumbnailLoader: (Clip) -> NSImage?
  let thumbnailLoadQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "clipboard.panel.thumbnail-loader"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 2
    return queue
  }()

  let mediaActionQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "clipboard.panel.media-actions"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  let thumbnailRequestLock = NSLock()
  var thumbnailCompletionsByRequest: [ThumbnailRequestKey: [(NSImage?) -> Void]] = [:]
  var selectedItemID: UUID?
  var selectionAnchorItemID: UUID?
  var isRecomputingVisibleItems = false
  var isApplyingLocalCollectionMutation = false
  var isDeferringLocalStoreRecompute = false
  var pendingDeletionUndo: [HistoryRemoval] = []
  var collectionCountCache: (query: String, summary: CategoryCounts)?
  var collectionNamesCache: [String]?
  var visibleItemsCache: [VisibleItemsCacheKey: [Clip]] = [:]
  var searchMatchCache: SearchMatchCacheEntry?
  var searchDocumentsByItemID: [UUID: SearchDocument] = [:]
  var itemByID: [UUID: Clip] = [:]
  var itemIDSet: Set<UUID> = []
  var indexedItemsByCollectionKey: [String: [IndexedClipboardItem]] = [:]
  var indexedItemsBySortMode: [Int: [IndexedClipboardItem]] = [:]
  var assignedCollectionNamesByKey: [String: String] = [:]
  var visibleItemByID: [UUID: Clip] = [:]
  var visibleIndexByID: [UUID: Int] = [:]
  var selectedItemIDSet: Set<UUID> = []
  var stackItemIDSet: Set<UUID> = []
  var stackItemsNeedPruning = false
  var stackItemIDs: [UUID] = [] {
    didSet {
      guard oldValue != stackItemIDs else { return }
      stackItemIDSet = Set(stackItemIDs)
      notifyMain { self.onStackChanged?() }
    }
  }

  deinit { purgePendingDeletionUndo() }

  var targetApplicationProvider: () -> NSRunningApplication? = { nil }
  var willPasteToTarget: () -> Void = {}
  var onVisibleItemsChanged: (([Clip]) -> Void)?
  var onSearchTextChanged: ((String) -> Void)?
  var onSelectedIndexChanged: ((Int) -> Void)?
  var onSelectedItemsChanged: (() -> Void)?
  var onStatusMessageChanged: ((String) -> Void)?
  var onSortModeChanged: ((ShelfCategory) -> Void)?
  var onCollectionsChanged: (() -> Void)?
  var onStackChanged: (() -> Void)?
  var onCaptureStatusChanged: (() -> Void)?

  init(
    store: HistoryStore, settings: Preferences, cacheService: MediaCache,
    imageTextExtractor: @escaping (NSImage) -> String? = ImageTextExtractor.recognizedText(in:),
    thumbnailLoader: ((Clip) -> NSImage?)? = nil
  ) {
    self.store = store
    self.settings = settings
    self.cacheService = cacheService
    self.filter = ShelfFilter(sort: settings.defaultSortMode)
    self.pasteService = PasteService(cacheService: cacheService)
    self.imageTextExtractor = imageTextExtractor
    self.thumbnailLoader = thumbnailLoader ?? { cacheService.previewThumbnail(for: $0) }

    store.observeItems { [weak self] list in
      guard let self else { return }
      let shouldDeferRecompute = self.isDeferringLocalStoreRecompute
      self.notifyMain {
        self.items = list
        if shouldDeferRecompute { return }
        self.recomputeVisibleItems()
      }
    }
    settings.observe { [weak self] change in
      self?.notifyMain {
        switch change {
        case .captureStatus:
          self?.statusMessage = ""
          self?.onCaptureStatusChanged?()
        case .collections:
          guard let self else { return }
          self.collectionNamesCache = nil
          guard !self.isApplyingLocalCollectionMutation else { return }
          self.onCollectionsChanged?()
        case .defaultSortMode:
          guard let self else { return }
          self.sortMode = self.settings.defaultSortMode
        case .includeImageTextInSearch:
          guard let self else { return }
          self.collectionCountCache = nil
          self.visibleItemsCache.removeAll(keepingCapacity: true)
          self.searchMatchCache = nil
          let query = Self.normalizedSearchValue(self.searchText)
          guard !query.isEmpty, !self.parseSearchQuery(query).textTokens.isEmpty else { return }
          self.recomputeVisibleItems()
        default: break
        }
      }
    }
  }

  var selectedItem: Clip? {
    guard selectedIndex >= 0, selectedIndex < visibleItems.count else { return nil }
    return visibleItems[selectedIndex]
  }

  var selectedItemCount: Int {
    let visibleSelectionCount = selectedItemIDs.reduce(into: 0) { count, id in
      if visibleItemByID[id] != nil { count += 1 }
    }
    if visibleSelectionCount > 0 { return visibleSelectionCount }
    return selectedItem == nil ? 0 : 1
  }

  var canShowSelectedInClipboard: Bool { selectedItem != nil && canShowVisibleItemsInClipboard }

  var canShowVisibleItemsInClipboard: Bool {
    !visibleItems.isEmpty
      && (!searchText.clipboardTrimmed.isEmpty || sortMode != .mostRecent || selectedCollectionName != nil
        || !filter.categories.isEmpty || isStackFilterSelected)
  }

  var totalItemCount: Int { items.count }

  var stackCount: Int { stackItemIDs.count }

  var collectionNames: [String] {
    if let collectionNamesCache { return collectionNamesCache }

    let assignedNames = Set(assignedCollectionNamesByKey.values)
    let configuredNames = settings.customCollectionNames
    let configuredNameSet = Set(configuredNames.map { $0.lowercased() })
    let allNames = assignedNames.union(configuredNames)
    let defaultNames = Pinboards.names.filter { allNames.contains($0) }
    var configuredCustomNames: [String] = []
    for name in configuredNames where !Pinboards.names.contains(name) {
      guard !configuredCustomNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
        continue
      }
      configuredCustomNames.append(name)
    }
    let assignedCustomNames = assignedNames.filter { !Pinboards.names.contains($0) }.filter {
      !configuredNameSet.contains($0.lowercased())
    }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    let names = defaultNames + configuredCustomNames + assignedCustomNames
    collectionNamesCache = names
    return names
  }

  var captureStatusMessage: String { settings.captureStatusMessage }

  func notifyMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
  }
}

// MARK: - PanelModelTypes

enum SelectionMode {
  case replace
  case toggle
  case range
  case activate
}

struct CategoryCounts {
  let sortModeCounts: [Int: Int]
  let collectionCounts: [String: Int]

  func count(for sortMode: ShelfCategory) -> Int { sortModeCounts[sortMode.rawValue] ?? 0 }

  func count(named name: String) -> Int {
    guard let normalizedName = Pinboards.normalizedName(name) else { return 0 }
    return collectionCounts[normalizedName.lowercased()] ?? 0
  }
}

extension Calendar {
  static var searchCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }
}

// MARK: - ShelfModel — Collections

extension ShelfModel {
  func collectionCount(for sortMode: ShelfCategory) -> Int { collectionCountSummary().count(for: sortMode) }

  func collectionCount(named name: String) -> Int { collectionCountSummary().count(named: name) }

  func collectionCountSummary() -> CategoryCounts {
    let query = Self.normalizedSearchValue(searchText)
    if let collectionCountCache, collectionCountCache.query == query { return collectionCountCache.summary }

    var sortModeCounts = Dictionary(uniqueKeysWithValues: ShelfCategory.allCases.map { ($0.rawValue, 0) })
    var collectionCounts: [String: Int] = [:]

    if query.isEmpty {
      for mode in ShelfCategory.allCases {
        sortModeCounts[mode.rawValue] = indexedItemsBySortMode[mode.rawValue]?.count ?? 0
      }
      for (collectionKey, indexedItems) in indexedItemsByCollectionKey {
        collectionCounts[collectionKey] = indexedItems.count
      }
    } else {
      for indexedItem in indexedItemsMatchingSearch(query) {
        let item = indexedItem.item
        incrementSortModeCounts(for: item, counts: &sortModeCounts)
        if let collectionName = Pinboards.normalizedName(item.collectionName) {
          collectionCounts[collectionName.lowercased(), default: 0] += 1
        }
      }
    }

    let summary = CategoryCounts(sortModeCounts: sortModeCounts, collectionCounts: collectionCounts)
    collectionCountCache = (query, summary)
    return summary
  }

  func shouldShowCategory(for sortMode: ShelfCategory) -> Bool {
    collectionCount(for: sortMode) > 0 || isSortModeCategorySelected(sortMode)
  }

  func isSortModeCategorySelected(_ mode: ShelfCategory) -> Bool {
    guard !isStackFilterSelected else { return false }
    let selection = activeCategoryFilterSelection()
    if !selection.isEmpty { return selection.sortModeRawValues.contains(mode.rawValue) }
    return selectedCollectionName == nil && sortMode == mode
  }

  func isCollectionCategorySelected(named name: String) -> Bool {
    guard !isStackFilterSelected else { return false }
    guard let normalizedName = Pinboards.normalizedName(name) else { return false }
    let key = normalizedName.lowercased()
    let selection = activeCategoryFilterSelection()
    if !selection.isEmpty { return selection.collectionNameKeys.contains(key) }
    return selectedCollectionName?.caseInsensitiveCompare(normalizedName) == .orderedSame
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
    guard let item = itemByID[id] else { return }
    selectedItemID = selectedItem?.id
    assign(item: item, to: collectionName)
  }

  func selectSortMode(_ mode: ShelfCategory, extending: Bool = false) {
    if extending { toggleCategory(.builtin(mode)) } else { changeFilter(.selectCategory(mode)) }
  }

  func selectCollection(named name: String, extending: Bool = false) {
    guard let name = Pinboards.normalizedName(name) else { return }
    if extending { toggleCategory(.pinboard(name.lowercased())) } else { changeFilter(.collection(name)) }
  }

  private func toggleCategory(_ category: ShelfFilter.Category) {
    changeFilter(.toggle(category))
    let count = filter.categories.totalCount
    statusMessage = count == 0 ? "Selected Clipboard" : "Filtered \(count) \(count == 1 ? "category" : "categories")"
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
      let currentIndex = names.firstIndex(where: { $0.caseInsensitiveCompare(selectedCollectionName) == .orderedSame })
    {
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
    if selectAfterCreate { selectCollection(named: normalizedName) } else { onCollectionsChanged?() }
  }

  func collectionColorHex(named name: String) -> String? { settings.collectionColorHex(forCollectionNamed: name) }

  func exportCollection(named name: String, to url: URL, completion: @escaping (Result<ArchiveSummary, Error>) -> Void)
  {
    mediaActionQueue.addOperation { [weak self] in
      guard let self else { return }
      let result = Result { try self.store.exportCollection(named: name, to: url) }
      DispatchQueue.main.async { [weak self] in
        if case .success(let summary) = result, let normalizedName = Pinboards.normalizedName(name) {
          let noun = summary.itemCount == 1 ? "clip" : "clips"
          self?.statusMessage = "Exported \(normalizedName) Pinboard with \(summary.itemCount) \(noun)"
        }
        completion(result)
      }
    }
  }

  func reportCollectionExportFailure(_ error: Error) { statusMessage = "Export failed: \(error.localizedDescription)" }

  func updateCollection(named currentName: String, to newName: String, colorHex: String? = nil) {
    guard let normalizedCurrentName = Pinboards.normalizedName(currentName) else { return }

    isApplyingLocalCollectionMutation = true
    let updatedName = settings.updateCollection(named: normalizedCurrentName, to: newName, colorHex: colorHex)
    isApplyingLocalCollectionMutation = false
    collectionNamesCache = nil
    guard let normalizedNewName = updatedName else { return }

    isDeferringLocalStoreRecompute = true
    for item in items where item.collectionName?.caseInsensitiveCompare(normalizedCurrentName) == .orderedSame {
      store.setCollection(item.id, name: normalizedNewName)
    }
    isDeferringLocalStoreRecompute = false
    changeFilter(.replaceCollection(normalizedCurrentName, normalizedNewName))
    statusMessage = "Updated \(normalizedNewName)"
  }

  func deleteCollection(named name: String) {
    isApplyingLocalCollectionMutation = true
    let deletedName = settings.deleteCollection(named: name)
    isApplyingLocalCollectionMutation = false
    collectionNamesCache = nil
    guard let normalizedName = deletedName else { return }
    let matchingIDs = items.filter { $0.collectionName?.caseInsensitiveCompare(normalizedName) == .orderedSame }.map(
      \.id)
    isDeferringLocalStoreRecompute = true
    for id in matchingIDs { store.remove(id) }
    isDeferringLocalStoreRecompute = false
    changeFilter(.replaceCollection(normalizedName, nil))
    statusMessage = "Deleted \(normalizedName)"
  }

  private func assign(item: Clip, to collectionName: String?) {
    let normalizedName = Pinboards.normalizedName(collectionName)
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
}

// MARK: - ShelfModel — Filtering

extension ShelfModel {
  func rebuildItemIndexes() {
    itemByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    itemIDSet = Set(itemByID.keys)
    let indexed = items.enumerated().map { IndexedClipboardItem(offset: $0.offset, item: $0.element) }
    indexedItemsBySortMode = [ShelfCategory.mostRecent.rawValue: indexed, ShelfCategory.mostUsed.rawValue: indexed]
    indexedItemsByCollectionKey.removeAll(keepingCapacity: true)
    assignedCollectionNamesByKey.removeAll(keepingCapacity: true)
    for entry in indexed {
      if let name = Pinboards.normalizedName(entry.item.collectionName) {
        let key = name.lowercased()
        assignedCollectionNamesByKey[key] = name
        indexedItemsByCollectionKey[key, default: []].append(entry)
      }
      for mode in categoryModes(for: entry.item) { indexedItemsBySortMode[mode.rawValue, default: []].append(entry) }
    }
  }

  private func categoryModes(for item: Clip) -> [ShelfCategory] {
    let modes: [ShelfCategory]
    switch item.kind {
    case .image: modes = [.images]
    case .url: modes = [.links]
    case .text, .richText: modes = [.text]
    case .code: modes = [.text, .code]
    case .file, .pdf: modes = [.files]
    case .audio: modes = [.audio]
    case .color: modes = [.colors]
    case .video: modes = [.videos]
    case .unknown: modes = []
    }
    return item.isPinned ? modes + [.pinned] : modes
  }

  func incrementSortModeCounts(for item: Clip, counts: inout [Int: Int]) {
    for mode in [.mostRecent, .mostUsed] + categoryModes(for: item) { counts[mode.rawValue, default: 0] += 1 }
  }

  func computeStackVisibleItems(from items: [Clip], query: String) -> [Clip] {
    let parsed = parseSearchQuery(query)
    return parsed.isEmpty ? items : items.filter { matchesSearchQuery($0, query: parsed) }
  }

  func indexedItemsMatchingSearch(_ query: String) -> [IndexedClipboardItem] {
    if let cached = searchMatchCache, cached.query == query { return cached.indexedItems }
    let parsed = parseSearchQuery(query)
    let all = indexedItemsBySortMode[ShelfCategory.mostRecent.rawValue] ?? []
    let matches = parsed.isEmpty ? all : all.filter { matchesSearchQuery($0.item, query: parsed) }
    searchMatchCache = SearchMatchCacheEntry(query: query, indexedItems: matches)
    return matches
  }

  func cachedVisibleItems(
    query: String, sortMode: ShelfCategory, collectionName: String?, categoryFilters: CategoryFilterSelection = .empty
  ) -> [Clip] {
    let collectionKey = Pinboards.normalizedName(collectionName)?.lowercased()
    let key = VisibleItemsCacheKey(
      query: query, sortMode: sortMode.rawValue, collectionNameKey: collectionKey,
      sortModeFilterRawValues: categoryFilters.sortModeRawValues.sorted(),
      collectionNameFilterKeys: categoryFilters.collectionNameKeys.sorted())
    if let cached = visibleItemsCache[key] { return cached }
    let candidates: [IndexedClipboardItem]
    if query.isEmpty {
      // Empty queries use the category indexes instead of scanning the whole history.
      if !categoryFilters.isEmpty {
        let groups =
          categoryFilters.sortModeRawValues.map { indexedItemsBySortMode[$0] ?? [] }
          + categoryFilters.collectionNameKeys.map { indexedItemsByCollectionKey[$0] ?? [] }
        candidates = Array(
          Dictionary(groups.flatMap { $0 }.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
      } else if let collectionKey {
        candidates = indexedItemsByCollectionKey[collectionKey] ?? []
      } else {
        candidates = indexedItemsBySortMode[sortMode.rawValue] ?? []
      }
    } else {
      candidates = indexedItemsMatchingSearch(query).filter {
        matchesCategory($0.item, mode: sortMode, collection: collectionKey, filters: categoryFilters)
      }
    }
    let result = sortedItems(candidates, mode: sortMode, collection: collectionKey, filters: categoryFilters)
    if visibleItemsCache.count > 24 { visibleItemsCache.removeAll(keepingCapacity: true) }
    visibleItemsCache[key] = result
    return result
  }

  func computeVisibleItems(from items: [Clip], query: String, sortMode: ShelfCategory, collectionName: String? = nil)
    -> [Clip]
  {
    let parsed = parseSearchQuery(query)
    let collection = Pinboards.normalizedName(collectionName)?.lowercased()
    let candidates = items.enumerated().compactMap { offset, item -> IndexedClipboardItem? in
      guard parsed.isEmpty || matchesSearchQuery(item, query: parsed),
        matchesCategory(item, mode: sortMode, collection: collection, filters: .empty)
      else { return nil }
      return IndexedClipboardItem(offset: offset, item: item)
    }
    return sortedItems(candidates, mode: sortMode, collection: collection, filters: .empty)
  }

  func activeCategoryFilterSelection() -> CategoryFilterSelection { filter.categories }

  private func matchesCategory(_ item: Clip, mode: ShelfCategory, collection: String?, filters: CategoryFilterSelection)
    -> Bool
  {
    if !filters.isEmpty {
      return filters.sortModeRawValues.contains { ShelfCategory(rawValue: $0)?.includes(item) == true }
        || item.collectionName.flatMap(Pinboards.normalizedName).map {
          filters.collectionNameKeys.contains($0.lowercased())
        } == true
    }
    if let collection { return item.collectionName?.lowercased() == collection }
    return mode.includes(item)
  }

  private func sortedItems(
    _ items: [IndexedClipboardItem], mode: ShelfCategory, collection: String?, filters: CategoryFilterSelection
  ) -> [Clip] {
    let selectedMode = filters.sortModeRawValues.first.flatMap(ShelfCategory.init(rawValue:)) ?? mode
    let recent =
      filters.totalCount > 1 || !filters.collectionNameKeys.isEmpty || collection != nil || selectedMode == .mostRecent
      || selectedMode == .pinned
    let mostUsed = !recent && selectedMode == .mostUsed
    return items.sorted { lhs, rhs in
      if mostUsed, lhs.item.useCount != rhs.item.useCount { return lhs.item.useCount > rhs.item.useCount }
      if lhs.item.lastUsedAt != rhs.item.lastUsedAt { return lhs.item.lastUsedAt > rhs.item.lastUsedAt }
      if recent, lhs.item.createdAt != rhs.item.createdAt { return lhs.item.createdAt > rhs.item.createdAt }
      return lhs.offset < rhs.offset
    }.map(\.item)
  }
}
