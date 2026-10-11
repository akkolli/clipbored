import AppKit

// MARK: - ShelfModel — Selection

extension ShelfModel {
  func selectItem(at index: Int, mode: SelectionMode = .replace) {
    guard index >= 0 && index < visibleItems.count else { return }
    let item = visibleItems[index]
    switch mode {
    case .replace: setActiveSelection(item, at: index, selectedIDs: [item.id], anchorID: item.id)
    case .toggle:
      var nextIDs = selectedItemIDs.isEmpty ? selectedItem.map { [$0.id] } ?? [] : selectedItemIDs
      if nextIDs.contains(item.id) {
        if nextIDs.count > 1 { nextIDs.removeAll { $0 == item.id } }
      } else {
        nextIDs.append(item.id)
      }
      setActiveSelection(item, at: index, selectedIDs: nextIDs, anchorID: item.id)
    case .range:
      let anchorIndex = selectionAnchorItemID.flatMap { visibleIndexByID[$0] } ?? selectedIndex
      let lower = min(anchorIndex, index)
      let upper = max(anchorIndex, index)
      let rangeIDs = visibleItems[lower...upper].map(\.id)
      let anchorID = visibleItems[anchorIndex].id
      setActiveSelection(item, at: index, selectedIDs: rangeIDs, anchorID: anchorID)
    case .activate:
      if selectedItemIDSet.contains(item.id), selectedItemIDs.count > 1 {
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
    if previousIndex == 0 { notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) } }
  }

  func selectLastItem() {
    guard !visibleItems.isEmpty else { return }
    let lastIndex = visibleItems.count - 1
    let previousIndex = selectedIndex
    setIndexBasedSelection(at: lastIndex)
    if previousIndex == lastIndex { notifyMain { self.onSelectedIndexChanged?(self.selectedIndex) } }
  }

  func moveSelection(_ delta: Int, extending: Bool = false) {
    let count = visibleItems.count
    guard count > 0 else { return }
    let target = max(0, min(count - 1, selectedIndex + delta))
    if extending { selectItem(at: target, mode: .range) } else { setIndexBasedSelection(at: target) }
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

  func isItemSelected(at index: Int) -> Bool {
    guard index >= 0 && index < visibleItems.count else { return false }
    return selectedItemIDSet.contains(visibleItems[index].id)
  }

  func deleteSelected() {
    let selectedItems = selectedItemsInSelectionOrder()
    guard !selectedItems.isEmpty else { return }

    purgePendingDeletionUndo()
    let originalVisibleCount = visibleItems.count
    let firstDeletedVisibleIndex =
      selectedItems.compactMap { item in visibleItems.firstIndex { $0.id == item.id } }.min() ?? selectedIndex

    let removalOrder = selectedItems.sorted { lhs, rhs in
      let lhsIndex = items.firstIndex { $0.id == lhs.id } ?? -1
      let rhsIndex = items.firstIndex { $0.id == rhs.id } ?? -1
      return lhsIndex > rhsIndex
    }
    let removals = removalOrder.compactMap { item in store.remove(item.id, purgeManagedCache: false) }
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
    for id in ids { store.remove(id) }
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

    let restoredIDs = removals.sorted(by: { $0.index < $1.index }).map(\.item.id)
    let visibleRestoredIDs = restoredIDs.filter { visibleIndexByID[$0] != nil }
    if let firstRestoredID = visibleRestoredIDs.first, let restoredIndex = visibleIndexByID[firstRestoredID] {
      setActiveSelection(
        visibleItems[restoredIndex], at: restoredIndex, selectedIDs: visibleRestoredIDs, anchorID: firstRestoredID)
    }

    let noun = removals.count == 1 ? "clip" : "clips"
    statusMessage = "Restored \(removals.count) \(noun)"
  }

  func showSelectedInClipboard() {
    guard canShowSelectedInClipboard, let item = selectedItem else { return }
    selectedItemID = item.id

    changeFilter(.history)

    if let index = visibleIndexByID[item.id] {
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
    let query = Self.normalizedSearchValue(searchText)
    if isStackFilterSelected {
      let stackedItems = stackItemIDs.compactMap { itemByID[$0] }
      visibleItems = computeStackVisibleItems(from: stackedItems, query: query)
    } else {
      visibleItems = cachedVisibleItems(
        query: query, sortMode: sortMode, collectionName: selectedCollectionName,
        categoryFilters: activeCategoryFilterSelection())
    }

    if let selectedID = previousSelection, let index = visibleIndexByID[selectedID] {
      selectedIndex = index
    } else if selectedIndex >= visibleItems.count {
      selectedIndex = max(0, visibleItems.count - 1)
    } else if selectedIndex < 0 {
      selectedIndex = 0
    }

    if visibleItems.isEmpty { selectedIndex = 0 }

    selectedItemID = selectedItem?.id
    let visibleSelectedIDs = previousSelectedIDs.filter { visibleIndexByID[$0] != nil }
    if previousSelection == nil {
      selectedItemIDs = selectedItemID.map { [$0] } ?? []
    } else if !visibleSelectedIDs.isEmpty {
      selectedItemIDs = visibleSelectedIDs
    } else if let selectedItemID {
      selectedItemIDs = [selectedItemID]
    } else {
      selectedItemIDs = []
    }
    if let selectionAnchorItemID, visibleIndexByID[selectionAnchorItemID] == nil {
      self.selectionAnchorItemID = selectedItemID
    }
  }

  func notifyVisibleItemsChanged() { notifyMain { self.onVisibleItemsChanged?(self.visibleItems) } }

  private func setActiveSelection(_ item: Clip, at index: Int, selectedIDs: [UUID], anchorID: UUID?) {
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
    if selectedIndex != index { selectedIndex = index }
  }

  private func uniqueIDs(_ ids: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return ids.filter { seen.insert($0).inserted }
  }

  func selectedItemsInSelectionOrder() -> [Clip] {
    let items = selectedItemIDs.compactMap { visibleItemByID[$0] }
    return items.isEmpty ? selectedItem.map { [$0] } ?? [] : items
  }

  func purgePendingDeletionUndo() {
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
}

// MARK: - ShelfModel — Transfers

extension ShelfModel {
  func pasteSelected() { performSelectedTransfer(.paste) }

  func pasteSelectedPlainText() { performSelectedTransfer(.paste, asPlainText: true) }

  func pasteItem(at index: Int, plainText: Bool = false) {
    guard visibleItems.indices.contains(index) else { return }
    selectItem(at: index)
    performSelectedTransfer(.paste, asPlainText: plainText)
  }

  func copySelected() { performSelectedTransfer(.copy) }

  func copySelectedPlainText() { performSelectedTransfer(.copy, asPlainText: true) }

  func isItemStacked(at index: Int) -> Bool {
    guard index >= 0 && index < visibleItems.count else { return false }
    return stackItemIDSet.contains(visibleItems[index].id)
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

  func addVisibleItemsToStack() { addToStack(visibleItems, scope: "visible") }

  func toggleStackCaptureMode() {
    isStackCaptureEnabled.toggle()
    statusMessage = isStackCaptureEnabled ? "Stack capture is on" : "Stack capture is off"
  }

  func addCapturedItemToStack(_ item: Clip) {
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
    changeFilter(.stack)
  }

  func clearStack() {
    guard !stackItemIDs.isEmpty else {
      statusMessage = "Stack is empty"
      return
    }
    stackItemIDs.removeAll()
    changeFilter(.leaveStack)
    statusMessage = "Cleared Stack"
  }

  func copyNextStackItem() { performNextStackTransfer(.copy) }

  func pasteNextStackItem() { performNextStackTransfer(.paste) }

  func copyStackAsText() { performStackTextTransfer(.copy) }

  func pasteStackAsText() { performStackTextTransfer(.paste) }

  func addSelectedItemsToStack() { addToStack(selectedItemsInSelectionOrder(), scope: "selected") }

  private func addToStack(_ items: [Clip], scope: String) {
    pruneStackItems()
    guard !items.isEmpty else {
      statusMessage = "No \(scope) clips to stack"
      return
    }
    let newIDs = items.map(\.id).filter { !stackItemIDSet.contains($0) }
    guard !newIDs.isEmpty else {
      statusMessage = "\(scope.capitalized) clips are already in Stack"
      return
    }
    stackItemIDs.append(contentsOf: newIDs)
    let noun = newIDs.count == 1 ? "clip" : "clips"
    statusMessage = "Added \(newIDs.count) \(scope == "selected" ? "selected " : "")\(noun) to Stack"
  }

  func copySelectedItemsAsText() { performSelectedTransfer(.copy, asPlainText: true, forceGroup: true) }

  func pasteSelectedItemsAsText() { performSelectedTransfer(.paste, asPlainText: true, forceGroup: true) }

  func pasteboardWriters(forItemAt index: Int) -> [NSPasteboardWriting] {
    guard index >= 0 && index < visibleItems.count else { return [] }
    return pasteService.pasteboardWriters(for: visibleItems[index])
  }

  private func nextStackItem() -> Clip? {
    pruneStackItems()
    return stackItemIDs.first.flatMap { itemByID[$0] }
  }

  private func plainTextPackage(for items: [Clip]) -> (text: String, items: [Clip])? {
    let pairs = items.compactMap { item -> (Clip, String)? in
      guard let text = pasteService.plainText(for: item)?.clipboardTrimmed, !text.isEmpty else { return nil }
      return (item, text)
    }
    guard !pairs.isEmpty else { return nil }
    return (pairs.map(\.1).joined(separator: "\n\n"), pairs.map(\.0))
  }

  private func stackPlainTextPackage() -> (text: String, items: [Clip])? {
    pruneStackItems()
    return plainTextPackage(for: stackItemIDs.compactMap { itemByID[$0] })
  }

  private func performSelectedTransfer(_ intent: TransferIntent, asPlainText: Bool = false, forceGroup: Bool = false) {
    let items = selectedItemsInSelectionOrder()
    let isGroup = forceGroup || items.count > 1

    if asPlainText && isGroup {
      guard let package = plainTextPackage(for: items) else {
        statusMessage = "Selection has no text to \(intent == .copy ? "copy" : "paste")"
        return
      }
      completeTransfer(plainTextTransfer(intent, value: package.text), items: package.items, context: .selected)
      return
    }

    guard let item = items.first else { return }
    let result = asPlainText ? plainTextTransfer(intent, item: item) : originalTransfer(intent, items: items)
    completeTransfer(result, items: items, context: isGroup ? .selected : .single)
  }

  private func performNextStackTransfer(_ intent: TransferIntent) {
    guard let item = nextStackItem() else {
      statusMessage = "Stack is empty"
      return
    }
    completeTransfer(originalTransfer(intent, items: [item]), items: [item], context: .stackItem)
  }

  private func performStackTextTransfer(_ intent: TransferIntent) {
    guard let package = stackPlainTextPackage() else {
      statusMessage = "Stack has no text to \(intent == .copy ? "copy" : "paste")"
      return
    }
    completeTransfer(plainTextTransfer(intent, value: package.text), items: package.items, context: .stackText)
  }

  private func originalTransfer(_ intent: TransferIntent, items: [Clip]) -> PasteService.PasteActionResult {
    if let item = items.first, items.count == 1 {
      return intent == .copy
        ? pasteService.copy(item) : pasteService.paste(item, targetApp: targetApplicationProvider())
    }
    return intent == .copy
      ? pasteService.copy(items) : pasteService.paste(items, targetApp: targetApplicationProvider())
  }

  private func plainTextTransfer(_ intent: TransferIntent, item: Clip) -> PasteService.PasteActionResult {
    intent == .copy
      ? pasteService.copyPlainText(item) : pasteService.pastePlainText(item, targetApp: targetApplicationProvider())
  }

  private func plainTextTransfer(_ intent: TransferIntent, value: String) -> PasteService.PasteActionResult {
    intent == .copy
      ? pasteService.copyPlainText(value) : pasteService.pastePlainText(value, targetApp: targetApplicationProvider())
  }

  private func completeTransfer(_ result: PasteService.PasteActionResult, items: [Clip], context: TransferContext) {
    if case .failed(let message) = result {
      statusMessage = message
      if case .single = context { settings.setPasteStatus(message: message) }
      return
    }

    if case .pasted = result { willPasteToTarget() } else if case .pastedPlainText = result { willPasteToTarget() }

    switch context {
    case .stackItem:
      if let item = items.first {
        consumeStackItem(item.id)
        store.markUsed(item.id)
      }
    case .stackText:
      for item in items {
        store.markUsed(item.id)
        consumeStackItem(item.id, refreshActiveStackFilter: false)
      }
      if stackItemIDs.isEmpty { changeFilter(.leaveStack) } else if isStackFilterSelected { recomputeVisibleItems() }
    case .single, .selected: for item in items { store.markUsed(item.id) }
    }

    selectedItemID = items.first?.id
    statusMessage = transferStatus(result, count: items.count, context: context)
    settings.setPasteStatus(message: statusMessage)
  }

  private func transferStatus(_ result: PasteService.PasteActionResult, count: Int, context: TransferContext) -> String
  {
    let noun = count == 1 ? "clip" : "clips"
    switch (context, result) {
    case (.single, _): return result.message
    case (.stackItem, .pasted): return "Pasted from Stack"
    case (.stackItem, .copied): return "Copied from Stack"
    case (.stackItem, .copiedNeedsPermission):
      return "Copied from Stack. Grant Accessibility access to paste automatically."
    case (.selected, .pasted): return "Pasted \(count) selected \(noun)"
    case (.selected, .copied): return "Copied \(count) selected \(noun)"
    case (.selected, .copiedNeedsPermission):
      return "Copied \(count) selected \(noun). Grant Accessibility access to paste automatically."
    case (.selected, .pastedPlainText): return "Pasted \(count) selected \(noun) as Text"
    case (.selected, .copiedPlainText): return "Copied \(count) selected \(noun) as Text"
    case (.selected, .copiedPlainTextNeedsPermission):
      return "Copied \(count) selected \(noun) as Text. Grant Accessibility access to paste automatically."
    case (.stackText, .pastedPlainText): return "Pasted \(count) Stack \(noun) as Text"
    case (.stackText, .copiedPlainText): return "Copied \(count) Stack \(noun) as Text"
    case (.stackText, .copiedPlainTextNeedsPermission):
      return "Copied \(count) Stack \(noun) as Text. Grant Accessibility access to paste automatically."
    default: return result.message
    }
  }

  private func consumeStackItem(_ id: UUID, refreshActiveStackFilter: Bool = true) {
    guard let index = stackItemIDs.firstIndex(of: id) else { return }
    stackItemIDs.remove(at: index)
    if refreshActiveStackFilter && isStackFilterSelected { recomputeVisibleItems() }
  }

  func pruneStackItems() {
    guard stackItemsNeedPruning else { return }
    stackItemsNeedPruning = false
    guard !stackItemIDs.isEmpty else { return }
    let pruned = stackItemIDs.filter { itemIDSet.contains($0) }
    if pruned != stackItemIDs { stackItemIDs = pruned }
    if stackItemIDs.isEmpty && isStackFilterSelected && !isStackCaptureEnabled { changeFilter(.leaveStack) }
  }
}

// MARK: - ShelfModel — Media

extension ShelfModel {
  /// Loads preview media away from the main thread and coalesces matching in-flight requests.
  /// The completion is always delivered asynchronously on the main queue.
  func loadThumbnail(for item: Clip, completion: @escaping (NSImage?) -> Void) {
    guard let requestKey = thumbnailRequestKey(for: item) else {
      DispatchQueue.main.async { completion(nil) }
      return
    }

    thumbnailRequestLock.lock()
    if var completions = thumbnailCompletionsByRequest[requestKey] {
      completions.append(completion)
      thumbnailCompletionsByRequest[requestKey] = completions
      thumbnailRequestLock.unlock()
      return
    }
    thumbnailCompletionsByRequest[requestKey] = [completion]
    thumbnailRequestLock.unlock()

    thumbnailLoadQueue.addOperation { [self] in
      let thumbnail = self.thumbnailLoader(item)
      self.finishThumbnailRequest(requestKey, thumbnail: thumbnail)
    }
  }

  func editableTextForSelected() -> String? {
    guard let item = selectedItem, item.kind == .text || item.kind == .code else { return nil }
    return item.payload
  }

  func editableTitleForSelected() -> String? {
    guard let item = selectedItem else { return nil }
    return item.customTitle ?? ""
  }

  func updateSelectedTitle(to title: String) {
    guard let item = selectedItem else { return }
    let normalizedTitle = Clip.normalizedCustomTitle(title)
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

  func rotateSelectedImageClockwise(completion: (() -> Void)? = nil) {
    guard let item = selectedItem, item.kind == .image else { return }
    let imagePath = item.imagePath ?? item.payload
    selectedItemID = item.id
    mediaActionQueue.addOperation { [weak self] in
      guard let self else { return }
      let message: String
      if let data = self.cacheService.data(for: imagePath), let image = NSImage(data: data),
        let rotated = image.rotatedClockwise(), let fullData = rotated.pngData(),
        let thumbnailData = rotated.resized(to: CGSize(width: 320, height: 320)).pngData(),
        let fullPath = self.cacheService.cacheImageSidecarData(fullData, id: item.id),
        let thumbnailPath = self.cacheService.cacheImageSidecarData(
          thumbnailData, id: item.id, fileNamePrefix: "thumb"),
        self.store.updateImage(
          item.id, imagePath: fullPath, thumbnailPath: thumbnailPath, payloadHash: self.store.hashData(fullData))
      {
        message = "Rotated image"
      } else {
        message = "Could not rotate image"
      }
      self.finishMediaAction(message: message, completion: completion)
    }
  }

  func extractTextFromSelectedImage(completion: (() -> Void)? = nil) {
    guard let item = selectedItem, item.kind == .image else { return }
    let imagePath = item.imagePath ?? item.payload
    selectedItemID = item.id
    mediaActionQueue.addOperation { [weak self] in
      guard let self else { return }
      let message: String
      if let data = self.cacheService.data(for: imagePath), let image = NSImage(data: data) {
        if let text = ImageTextExtractor.normalizedRecognizedText(self.imageTextExtractor(image)) {
          message =
            self.store.updateImageText(item.id, ocrText: text)
            ? "Extracted text from image" : "Could not save image text"
        } else {
          message = "No text found in image"
        }
      } else {
        message = "Could not read image"
      }
      self.finishMediaAction(message: message, completion: completion)
    }
  }

  private func finishMediaAction(message: String, completion: (() -> Void)?) {
    DispatchQueue.main.async { [weak self] in
      self?.statusMessage = message
      completion?()
    }
  }

  func previewURLForSelected() -> URL? {
    guard let item = selectedItem else { return nil }
    return previewURL(for: item)
  }

  func linkPreviewRequestForSelected() -> LinkPreview? {
    guard let item = selectedItem else { return nil }
    return linkPreviewRequest(for: item)
  }

  internal func previewURL(for item: Clip) -> URL? { cacheService.temporaryPreviewURL(for: item) }

  internal func linkPreviewRequest(for item: Clip) -> LinkPreview? {
    guard item.kind == .url, let url = URL(string: item.payload.clipboardTrimmed),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else { return nil }

    let title = item.displayText.clipboardTrimmed.isEmpty ? url.absoluteString : item.displayText
    return LinkPreview(url: url, title: title)
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
    case .image, .pdf, .audio, .video:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.open(url)
    case .color: break
    default: break
    }
  }

  func revealSelected() {
    guard let item = selectedItem else { return }
    switch item.kind {
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      guard !urls.isEmpty, urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
      NSWorkspace.shared.activateFileViewerSelecting(urls)
    case .image, .pdf, .audio, .video:
      guard let url = cacheService.temporaryReadableURL(for: item) else { return }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .color: break
    default: break
    }
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
      statusMessage = "\(item.kind.statusName) items are already ignored"
      return
    }

    settings.ignoredItemKindsRaw.append(item.kind.rawValue)
    if settings.ignoredItemKindsRaw.contains(item.kind.rawValue) {
      statusMessage = "Ignored \(item.kind.statusName) items for future captures"
    } else {
      statusMessage = "At least one content type must stay enabled."
    }
  }

  private func sourceIgnoreRule(for item: Clip) -> (value: String, displayName: String)? {
    if let bundleID = item.sourceAppBundleId?.clipboardTrimmed, !bundleID.isEmpty {
      let sourceApp = item.sourceApp?.clipboardTrimmed
      let display = sourceApp?.isEmpty == false ? sourceApp ?? bundleID : bundleID
      return (bundleID, display)
    }

    if let sourceApp = item.sourceApp?.clipboardTrimmed, !sourceApp.isEmpty { return (sourceApp, sourceApp) }

    return nil
  }

  private func thumbnailRequestKey(for item: Clip) -> ThumbnailRequestKey? {
    let source: String?
    switch item.kind {
    case .url, .image: source = item.thumbnailPath
    case .pdf, .file, .video: source = item.payload
    case .text, .unknown, .audio, .richText, .color, .code: return nil
    }
    return ThumbnailRequestKey(itemID: item.id, kindRawValue: item.kind.rawValue, source: source)
  }

  private func finishThumbnailRequest(_ requestKey: ThumbnailRequestKey, thumbnail: NSImage?) {
    thumbnailRequestLock.lock()
    let completions = thumbnailCompletionsByRequest.removeValue(forKey: requestKey) ?? []
    thumbnailRequestLock.unlock()
    guard !completions.isEmpty else { return }

    DispatchQueue.main.async { for completion in completions { completion(thumbnail) } }
  }

}
