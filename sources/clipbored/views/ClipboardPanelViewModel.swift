import Foundation
import AppKit

final class ClipboardPanelViewModel {
  private(set) var visibleItems: [ClipboardItem] = [] {
    didSet { notifyMain { self.onVisibleItemsChanged?(self.visibleItems) } }
  }
  var searchText: String = "" {
    didSet {
      guard oldValue != searchText else { return }
      selectedItemID = selectedItem?.id
      recomputeVisibleItems()
    }
  }
  var sortMode: ClipboardSortMode {
    didSet {
      guard oldValue != sortMode else { return }
      selectedCollectionName = nil
      settings.defaultSortMode = sortMode
      recomputeVisibleItems()
      onSortModeChanged?(sortMode)
    }
  }
  private(set) var selectedCollectionName: String? {
    didSet {
      guard oldValue != selectedCollectionName else { return }
      recomputeVisibleItems()
      onCollectionsChanged?()
    }
  }
  var selectedIndex: Int = 0 {
    didSet {
      guard oldValue != selectedIndex else { return }
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    }
  }
  private(set) var statusMessage: String = "" {
    didSet { notifyMain { self.onStatusMessageChanged?(self.statusMessage) } }
  }

  private var items: [ClipboardItem] = []
  private let store: ClipboardStore
  private let settings: SettingsModel
  private let cacheService: ClipboardCacheService
  private let pasteService: PasteActionService
  private var selectedItemID: UUID?
  private var stackItemIDs: [UUID] = [] {
    didSet {
      guard oldValue != stackItemIDs else { return }
      notifyMain { self.onStackChanged?() }
    }
  }
  var targetApplicationProvider: () -> NSRunningApplication? = { nil }
  var willPasteToTarget: () -> Void = {}
  var onVisibleItemsChanged: (([ClipboardItem]) -> Void)?
  var onSelectedIndexChanged: ((Int) -> Void)?
  var onStatusMessageChanged: ((String) -> Void)?
  var onSortModeChanged: ((ClipboardSortMode) -> Void)?
  var onCollectionsChanged: (() -> Void)?
  var onStackChanged: (() -> Void)?
  var onCaptureStatusChanged: (() -> Void)?

  init(store: ClipboardStore, settings: SettingsModel, cacheService: ClipboardCacheService) {
    self.store = store
    self.settings = settings
    self.cacheService = cacheService
    self.sortMode = settings.defaultSortMode
    self.pasteService = PasteActionService(cacheService: cacheService)

    store.observeItems { [weak self] list in
      self?.notifyMain {
        self?.items = list
        self?.recomputeVisibleItems()
      }
    }
    settings.observe { [weak self] change in
      guard case .captureStatus = change else { return }
      self?.notifyMain {
        self?.statusMessage = ""
        self?.onStatusMessageChanged?("")
        self?.onCaptureStatusChanged?()
      }
    }
  }

  var selectedItem: ClipboardItem? {
    guard selectedIndex >= 0, selectedIndex < visibleItems.count else { return nil }
    return visibleItems[selectedIndex]
  }

  var totalItemCount: Int {
    items.count
  }

  var stackCount: Int {
    stackItemIDs.count
  }

  var collectionNames: [String] {
    let assignedNames = Set(
      items.compactMap { item -> String? in
        ClipboardCollectionDefaults.normalizedName(item.collectionName)
      }
    )
    let defaultNames = ClipboardCollectionDefaults.names.filter { assignedNames.contains($0) }
    let customNames = assignedNames
      .filter { !ClipboardCollectionDefaults.names.contains($0) }
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return defaultNames + customNames
  }

  func collectionCount(for sortMode: ClipboardSortMode) -> Int {
    let query = searchText.clipboardTrimmed.lowercased()
    return computeVisibleItems(from: items, query: query, sortMode: sortMode).count
  }

  func collectionCount(named name: String) -> Int {
    let query = searchText.clipboardTrimmed.lowercased()
    return computeVisibleItems(from: items, query: query, sortMode: sortMode, collectionName: name).count
  }

  var captureStatusMessage: String {
    settings.captureStatusMessage
  }

  func thumbnail(for item: ClipboardItem) -> NSImage? {
    cacheService.previewThumbnail(for: item)
  }

  func selectItem(at index: Int) {
    guard index >= 0 && index < visibleItems.count else { return }
    selectedIndex = index
  }

  func selectFirstItem() {
    guard !visibleItems.isEmpty else { return }
    selectedItemID = nil
    if selectedIndex == 0 {
      notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) }
    } else {
      selectedIndex = 0
    }
  }

  func moveSelection(_ delta: Int) {
    let count = visibleItems.count
    guard count > 0 else { return }
    let target = max(0, min(count - 1, selectedIndex + delta))
    selectedIndex = target
  }

  func pasteSelected() {
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

  func copySelected() {
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
    return stackItemIDs.contains(visibleItems[index].id)
  }

  func toggleSelectedStackMembership() {
    guard let item = selectedItem else { return }
    if let existingIndex = stackItemIDs.firstIndex(of: item.id) {
      stackItemIDs.remove(at: existingIndex)
      statusMessage = "Removed from Stack"
      return
    }

    stackItemIDs.append(item.id)
    statusMessage = "Added to Stack"
  }

  func clearStack() {
    guard !stackItemIDs.isEmpty else {
      statusMessage = "Stack is empty"
      return
    }
    stackItemIDs.removeAll()
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

  func pasteboardWriters(forItemAt index: Int) -> [NSPasteboardWriting] {
    guard index >= 0 && index < visibleItems.count else { return [] }
    return pasteService.pasteboardWriters(for: visibleItems[index])
  }

  func editableTextForSelected() -> String? {
    guard let item = selectedItem, item.kind == .text else { return nil }
    return item.payload
  }

  func editableTextForItem(at index: Int) -> String? {
    guard index >= 0 && index < visibleItems.count else { return nil }
    let item = visibleItems[index]
    guard item.kind == .text else { return nil }
    return item.payload
  }

  func updateSelectedText(to text: String) {
    guard let item = selectedItem, item.kind == .text else { return }
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
      statusMessage = "Updated text clip"
    }
  }

  func previewURLForSelected() -> URL? {
    guard let item = selectedItem else { return nil }
    return previewURL(for: item)
  }

  internal func previewURL(for item: ClipboardItem) -> URL? {
    cacheService.temporaryPreviewURL(for: item)
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
    default:
      break
    }
  }

  func deleteSelected() {
    guard let item = selectedItem else { return }
    store.remove(item.id)
    let next = max(0, min(visibleItems.count - 2, selectedIndex))
    selectedIndex = next
  }

  func togglePinSelected() {
    guard let item = selectedItem else { return }
    store.togglePin(item.id)
  }

  func assignSelected(to collectionName: String?) {
    guard let item = selectedItem else { return }
    selectedItemID = item.id
    let normalizedName = ClipboardCollectionDefaults.normalizedName(collectionName)
    store.setCollection(item.id, name: normalizedName)
    if let normalizedName {
      statusMessage = "Added to \(normalizedName)"
    } else {
      statusMessage = "Removed from collection"
    }
  }

  func selectCollection(named name: String) {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return }
    selectedCollectionName = normalizedName
  }

  func clearSearch() {
    searchText = ""
  }

  func recomputeVisibleItems() {
    pruneStackItems()
    let previousSelection = selectedItemID
    let query = searchText.clipboardTrimmed.lowercased()
    visibleItems = computeVisibleItems(from: items, query: query, sortMode: sortMode, collectionName: selectedCollectionName)

    if let selectedID = previousSelection, let index = visibleItems.firstIndex(where: { $0.id == selectedID }) {
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
    onCollectionsChanged?()
  }

  private func nextStackItem() -> ClipboardItem? {
    pruneStackItems()
    guard let id = stackItemIDs.first else { return nil }
    return items.first { $0.id == id }
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

  private func consumeStackItem(_ id: UUID) {
    guard let index = stackItemIDs.firstIndex(of: id) else { return }
    stackItemIDs.remove(at: index)
  }

  private func pruneStackItems() {
    guard !stackItemIDs.isEmpty else { return }
    let existingIDs = Set(items.map(\.id))
    let pruned = stackItemIDs.filter { existingIDs.contains($0) }
    if pruned != stackItemIDs {
      stackItemIDs = pruned
    }
  }

  internal func computeVisibleItems(
    from items: [ClipboardItem],
    query: String,
    sortMode: ClipboardSortMode,
    collectionName: String? = nil
  ) -> [ClipboardItem] {
    let tokens = searchTokens(from: query.lowercased())
    let filtered = tokens.isEmpty
      ? items.enumerated().map { ($0.offset, $0.element) }
      : items.enumerated().compactMap { index, item in
      let text = searchableText(for: item)
      return tokens.allSatisfy { text.contains($0) } ? (index, item) : nil
    }
    let collectionFiltered: [(Int, ClipboardItem)]
    if let collectionName = ClipboardCollectionDefaults.normalizedName(collectionName) {
      collectionFiltered = filtered.filter {
        $0.1.collectionName?.caseInsensitiveCompare(collectionName) == .orderedSame
      }
    } else {
      collectionFiltered = filtered
    }

    func fallback(_ lhs: (Int, ClipboardItem), _ rhs: (Int, ClipboardItem)) -> Bool {
      return lhs.0 < rhs.0
    }

    func sortByUsage(_ lhs: (Int, ClipboardItem), _ rhs: (Int, ClipboardItem)) -> Bool {
      if lhs.1.lastUsedAt == rhs.1.lastUsedAt {
        return fallback(lhs, rhs)
      }
      return lhs.1.lastUsedAt > rhs.1.lastUsedAt
    }

    if ClipboardCollectionDefaults.normalizedName(collectionName) != nil {
      return collectionFiltered
        .sorted {
          if $0.1.lastUsedAt == $1.1.lastUsedAt {
            if $0.1.createdAt == $1.1.createdAt { return fallback($0, $1) }
            return $0.1.createdAt > $1.1.createdAt
          }
          return $0.1.lastUsedAt > $1.1.lastUsedAt
        }
        .map(\.1)
    }

    switch sortMode {
    case .mostRecent:
      return collectionFiltered
        .sorted {
          if $0.1.lastUsedAt == $1.1.lastUsedAt {
            if $0.1.createdAt == $1.1.createdAt { return fallback($0, $1) }
            return $0.1.createdAt > $1.1.createdAt
          }
          return $0.1.lastUsedAt > $1.1.lastUsedAt
        }
        .map(\.1)

    case .mostUsed:
      return collectionFiltered
        .sorted {
          if $0.1.useCount == $1.1.useCount { return sortByUsage($0, $1) }
          return $0.1.useCount > $1.1.useCount
        }
        .map(\.1)

    case .images:
      return collectionFiltered
        .filter { $0.1.kind == .image }
        .sorted(by: sortByUsage)
        .map(\.1)

    case .links:
      return collectionFiltered
        .filter { $0.1.kind == .url }
        .sorted(by: sortByUsage)
        .map(\.1)

    case .text:
      return collectionFiltered
        .filter { $0.1.kind == .text || $0.1.kind == .richText }
        .sorted(by: sortByUsage)
        .map(\.1)

    case .files:
      return collectionFiltered
        .filter { $0.1.kind == .file || $0.1.kind == .pdf }
        .sorted(by: sortByUsage)
        .map(\.1)

    case .audio:
      return collectionFiltered
        .filter { $0.1.kind == .audio }
        .sorted(by: sortByUsage)
        .map(\.1)

    case .pinned:
      return collectionFiltered
        .filter { $0.1.isPinned }
        .sorted {
          if $0.1.lastUsedAt == $1.1.lastUsedAt {
            if $0.1.createdAt == $1.1.createdAt {
              return fallback($0, $1)
            }
            return $0.1.createdAt > $1.1.createdAt
          }
          return $0.1.lastUsedAt > $1.1.lastUsedAt
        }
        .map(\.1)

    @unknown default:
      return collectionFiltered
        .sorted(by: { lhs, rhs in
          return fallback(lhs, rhs)
        })
        .map(\.1)
    }
  }

  private func searchableText(for item: ClipboardItem) -> String {
    var base = item.searchableText
    if settings.includeImageTextInSearch, let ocrText = item.ocrText {
      base += " \(ocrText.lowercased())"
    }
    return base
  }

  private func searchTokens(from query: String) -> [String] {
    query
      .split { character in
        character.isWhitespace || character.isPunctuation
      }
      .map(String.init)
  }

  private func notifyMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.async(execute: block)
    }
  }
}
