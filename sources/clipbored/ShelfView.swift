import AppKit
import SwiftUI

// MARK: - ShelfView

// NSTableView owns viewport materialization and scrolling; the model remains
// the single owner of selection, including range anchors and Stack order.
final class ShelfView: NSVisualEffectView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  let viewModel: ShelfModel
  let onClose: () -> Void
  let onSettings: () -> Void
  let onPreview: () -> Void
  let table = ShelfTable()
  let searchField = NSSearchField()
  let sidebar = UI.stack([])
  let emptyLabel = UI.label("Copy something to start your history", secondary: true)
  var listScroll: NSScrollView!
  var mainStack: NSStackView!
  var hoverRow = -1
  var defersReloads = false
  var sidebarButtons: [SidebarButton] = []
  weak var activeWritingToolsTextView: NSTextView?

  init(
    viewModel: ShelfModel, onClose: @escaping () -> Void, onSettings: @escaping () -> Void = {},
    onPreview: @escaping () -> Void = {}
  ) {
    self.viewModel = viewModel
    self.onClose = onClose
    self.onSettings = onSettings
    self.onPreview = onPreview
    super.init(frame: .zero)
    configure()
    viewModel.onVisibleItemsChanged = { [weak self] _ in self?.reload() }
    viewModel.onSearchTextChanged = { [weak self] text in
      self?.searchField.stringValue = text
      self?.presentSearch(expanded: !text.isEmpty || self?.isSearchFieldEditing == true)
    }
    viewModel.onSelectedIndexChanged = { [weak self] _ in self?.updateSelection() }
    viewModel.onSelectedItemsChanged = { [weak self] in self?.updateSelection() }
    viewModel.onCollectionsChanged = { [weak self] in self?.updateSidebar() }
    viewModel.onSortModeChanged = { [weak self] _ in self?.updateSidebar() }
    viewModel.onStackChanged = { [weak self] in self?.updateSidebar() }
    reload()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var isSearchFieldEditing: Bool { searchField.currentEditor() != nil }
  var searchTextForKeyboardShortcut: String { searchField.stringValue }
  var visibleCardPageStep: Int { max(1, Int(listScroll.contentView.bounds.height / 68)) }

  private func configure() {
    material = .hudWindow
    blendingMode = .behindWindow
    state = .active
    colored(nil, radius: 14)
    searchField.delegate = self
    searchField.sendsSearchStringImmediately = true
    searchField.placeholderString = "Search clips"
    searchField.setAccessibilityLabel("Search clipboard history")
    searchField.isHidden = true
    let search = ActionButton("Search", symbol: "magnifyingglass") { [weak self] in self?.focusSearch() }
    let clear = ActionButton("Clear History", symbol: "trash") { [weak self] in self?.showClearHistoryMenu() }
    let settings = ActionButton("Settings", symbol: "gearshape") { [weak self] in self?.onSettings() }
    let spacer = NSView()
    let toolbar = UI.stack([search, searchField, spacer, clear, settings], vertical: false)
    searchField.translatesAutoresizingMaskIntoConstraints = false
    let searchWidth = searchField.widthAnchor.constraint(equalToConstant: 180)
    searchWidth.priority = .defaultHigh
    searchWidth.isActive = true
    table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip")))
    table.headerView = nil
    table.backgroundColor = .clear
    table.selectionHighlightStyle = .none
    table.intercellSpacing = NSSize(width: 0, height: 10)
    table.allowsMultipleSelection = true
    table.dataSource = self
    table.delegate = self
    table.setDraggingSourceOperationMask(.copy, forLocal: false)
    table.setDraggingSourceOperationMask(.move, forLocal: true)
    table.onClick = { [weak self] row, event in
      guard let self, row >= 0 else { return }
      self.collapseSearchFieldIfIdle()
      self.viewModel.selectItem(at: row, mode: selectionMode(from: event.modifierFlags))
      if event.clickCount == 2 { self.viewModel.pasteSelected() }
    }
    table.onHover = { [weak self] row in self?.setHoverRow(row) }
    table.onText = { [weak self] text in self?.startSearchFromShelf(text) }
    table.onMove = { [weak self] delta, extending in
      guard let self else { return }
      self.viewModel.moveSelection(delta, extending: extending)
      self.focusSelectedCardForKeyboardNavigation()
    }
    table.makeMenu = { [weak self] row in self?.clipMenu(at: row) }
    listScroll = UI.scroll(table)
    let sidebarScroll = UI.scroll(sidebar, topAligned: true)
    sidebarScroll.hasVerticalScroller = false
    sidebarScroll.sized(width: 38)
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    sidebar.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor).isActive = true
    let content = UI.stack([sidebarScroll, listScroll], vertical: false)
    content.alignment = .top
    mainStack = UI.stack([toolbar, content])
    mainStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 20, right: 12)
    addPinnedSubview(mainStack)
    NSLayoutConstraint.activate([
      toolbar.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -24),
      content.widthAnchor.constraint(equalTo: toolbar.widthAnchor),
      sidebarScroll.heightAnchor.constraint(equalTo: content.heightAnchor),
      listScroll.heightAnchor.constraint(equalTo: content.heightAnchor),
    ])
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      emptyLabel.centerXAnchor.constraint(equalTo: listScroll.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: listScroll.centerYAnchor),
      emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: listScroll.widthAnchor, constant: -24),
    ])
  }

  func reload() {
    guard !defersReloads else { return }
    hoverRow = -1
    table.reloadData()
    emptyLabel.isHidden = !viewModel.visibleItems.isEmpty
    emptyLabel.stringValue =
      !viewModel.searchText.isEmpty
      ? "No matching clips. Try a broader search."
      : viewModel.isStackFilterSelected
        ? "Stack is empty. Add clips or enable Stack capture."
        : viewModel.totalItemCount == 0 ? "Copy something to start your history" : "No clips in this view"
    updateSelection()
    updateSidebar()
  }

  func updateSelection() {
    guard !defersReloads else { return }
    let indices = IndexSet(viewModel.visibleItems.indices.filter { viewModel.isItemSelected(at: $0) })
    table.selectRowIndexes(indices, byExtendingSelection: false)
    let visible = table.rows(in: table.visibleRect)
    for row in visible.location..<NSMaxRange(visible) where row >= 0 && row < viewModel.visibleItems.count {
      (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ShelfCell)?.setSelected(indices.contains(row))
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { viewModel.visibleItems.count }
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { row == hoverRow ? 220 : 58 }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let id = NSUserInterfaceItemIdentifier("clip")
    let cell = table.makeView(withIdentifier: id, owner: nil) as? ShelfCell ?? ShelfCell()
    cell.identifier = id
    let item = viewModel.visibleItems[row]
    cell.render(
      item, number: row < 9 ? row + 1 : nil, expanded: row == hoverRow, selected: viewModel.isItemSelected(at: row),
      color: collectionColor(forCollectionNamed: item.collectionName ?? ""))
    if row == hoverRow {
      viewModel.loadThumbnail(for: item) { [weak cell] image in
        guard cell?.itemID == item.id else { return }
        cell?.setThumbnail(image)
      }
    }
    return cell
  }

  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
    let writers = rowIndexes.flatMap { viewModel.pasteboardWriters(forItemAt: $0) }
    guard !writers.isEmpty, let first = rowIndexes.first else { return false }
    pasteboard.clearContents()
    guard pasteboard.writeObjects(writers) else { return false }
    pasteboard.setString(viewModel.visibleItems[first].id.uuidString, forType: ClipboardItemDragPasteboard.itemIDType)
    return true
  }

  func setHoverRow(_ row: Int) {
    guard row != hoverRow else { return }
    let changed = IndexSet([hoverRow, row].filter { $0 >= 0 && $0 < viewModel.visibleItems.count })
    hoverRow = row
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
      table.noteHeightOfRows(withIndexesChanged: changed)
    }
    table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
  }

  func focusSelectedCardForKeyboardNavigation() {
    setHoverRow(-1)
    window?.makeFirstResponder(table)
    table.scrollRowToVisible(viewModel.selectedIndex)
  }

  func focusSelectedCollectionChip() {
    if let button = sidebarButtons.first(where: { $0.state == .on }) {
      window?.makeFirstResponder(button)
      button.scrollToVisible(button.bounds)
    }
  }

  func setBottomSafeInset(_ inset: CGFloat) { mainStack.edgeInsets.bottom = inset }
  func beginOpeningTransition() { defersReloads = true }
  func finishOpeningTransition() {
    defersReloads = false
    reload()
  }
  func prepareForShow() {
    searchField.stringValue = ""
    viewModel.searchText = ""
    presentSearch(expanded: false)
  }

  func focusSearch() {
    presentSearch(expanded: true)
    window?.makeFirstResponder(searchField)
  }
  func collapseSearchFieldIfIdle() { if searchField.stringValue.isEmpty { presentSearch(expanded: false) } }
  func presentSearch(expanded: Bool) { searchField.isHidden = !expanded }

  @discardableResult func clearSearchForKeyboardCancel() -> Bool {
    guard !searchField.stringValue.isEmpty else { return false }
    searchField.stringValue = ""
    viewModel.searchText = ""
    focusSearch()
    return true
  }

  func startSearchFromShelf(_ text: String) {
    focusSearch()
    searchField.stringValue += text
    viewModel.searchText = searchField.stringValue
  }

  func controlTextDidChange(_ notification: Notification) { viewModel.searchText = searchField.stringValue }
  func controlTextDidEndEditing(_ notification: Notification) { collapseSearchFieldIfIdle() }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
    switch command {
    case #selector(NSResponder.insertNewline(_:)): viewModel.pasteSelected()
    case #selector(NSResponder.cancelOperation(_:)): if !clearSearchForKeyboardCancel() { onClose() }
    case #selector(NSResponder.moveUp(_:)): viewModel.moveSelection(-1)
    case #selector(NSResponder.moveDown(_:)): viewModel.moveSelection(1)
    default: return false
    }
    table.scrollRowToVisible(viewModel.selectedIndex)
    return true
  }
}

// MARK: - ShelfControls

enum ClipboardItemDragPasteboard {
  static let itemIDType = NSPasteboard.PasteboardType("com.clipbored.clipboard-item-id")
}

func shelfSearchText(from event: NSEvent) -> String? {
  guard event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty, let text = event.characters,
    !text.isEmpty, text.rangeOfCharacter(from: .controlCharacters) == nil
  else { return nil }
  return text
}

func selectionMode(from modifiers: NSEvent.ModifierFlags) -> SelectionMode {
  if modifiers.contains(.shift) { return .range }
  return modifiers.contains(.command) ? .toggle : .replace
}

final class ShelfTable: NSTableView {
  var onClick: (Int, NSEvent) -> Void = { _, _ in }
  var onHover: (Int) -> Void = { _ in }
  var onText: (String) -> Void = { _ in }
  var onMove: (Int, Bool) -> Void = { _, _ in }
  var makeMenu: (Int) -> NSMenu? = { _ in nil }
  private var tracking: NSTrackingArea?
  private var lastMousePoint: NSPoint?

  override func mouseDown(with event: NSEvent) {
    onClick(row(at: convert(event.locationInWindow, from: nil)), event)
    window?.makeFirstResponder(self)
    super.mouseDown(with: event)
  }

  override func menu(for event: NSEvent) -> NSMenu? { makeMenu(row(at: convert(event.locationInWindow, from: nil))) }

  override func keyDown(with event: NSEvent) {
    if [125, 126].contains(event.keyCode), event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
      onMove(event.keyCode == 125 ? 1 : -1, event.modifierFlags.contains(.shift))
    } else if let text = shelfSearchText(from: event) {
      onText(text)
    } else {
      super.keyDown(with: event)
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(
      rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self,
      userInfo: nil)
    addTrackingArea(tracking!)
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard point != lastMousePoint else { return }
    lastMousePoint = point
    onHover(row(at: point))
  }

  override func mouseExited(with event: NSEvent) {
    lastMousePoint = nil
    onHover(-1)
  }
}

final class SidebarButton: ActionButton {
  var onDrop: ((UUID) -> Void)?
  var makeMenu: (() -> NSMenu)?
  var onKey: ((NSEvent) -> Bool)?

  override var acceptsFirstResponder: Bool { true }
  override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
  override func keyDown(with event: NSEvent) { if onKey?(event) != true { super.keyDown(with: event) } }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onDrop != nil && sender.draggingPasteboard.string(forType: ClipboardItemDragPasteboard.itemIDType) != nil
      ? .move : []
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let value = sender.draggingPasteboard.string(forType: ClipboardItemDragPasteboard.itemIDType),
      let id = UUID(uuidString: value), let onDrop
    else { return false }
    onDrop(id)
    return true
  }
}

final class ShelfCell: NSTableCellView {
  private static let dates = RelativeDateTimeFormatter()
  private let content = UI.stack([])
  private var previewLabel: NSTextField?
  private var previewImage: NSImageView?
  private(set) var itemID: UUID?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    colored(nil, radius: 10)
    addPinnedSubview(content)
  }
  convenience init() { self.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func render(_ item: Clip, number: Int?, expanded: Bool, selected: Bool, color: NSColor) {
    itemID = item.id
    previewImage = nil
    previewLabel = nil
    content.replace([])
    let accent = item.collectionName == nil ? ClipboardCollectionVisuals.color(for: item.kind.category) : color
    let title = ClipPresentation.title(item)
    let titleLabel = UI.label(
      (number.map { "\($0)  " } ?? "") + title, size: 14, color: .white, weight: .semibold, lines: 1)
    let subtitle = [
      item.kind.displayName, item.sourceApp, Self.dates.localizedString(for: item.createdAt, relativeTo: Date()),
    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    let subtitleLabel = UI.label(subtitle, size: 10, color: .white.withAlphaComponent(0.8), lines: 1)
    let icon = NSImageView(
      image: NSImage(
        systemSymbolName: item.isPinned ? "pin.fill" : item.kind.symbol, accessibilityDescription: item.kind.displayName
      ) ?? NSImage())
    icon.contentTintColor = .white
    let headerContent = UI.stack([icon, UI.stack([titleLabel, subtitleLabel], spacing: 2)], vertical: false)
    let header = NSView().colored(accent).sized(height: 58)
    header.addPinnedSubview(headerContent, inset: 10)
    content.spacing = 0
    content.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    if expanded {
      let raw = ClipPresentation.body(item).clipboardTrimmed
      let lines = raw.components(separatedBy: .newlines)
      let body = lines.first == title ? lines.dropFirst().joined(separator: "\n") : raw
      let label = UI.label(
        body, size: item.kind == .code ? 12 : 13, lines: 6, truncation: .byWordWrapping, monospaced: item.kind == .code)
      previewLabel = label
      let image = NSImageView()
      image.imageScaling = .scaleProportionallyUpOrDown
      image.isHidden = true
      previewImage = image
      let bodyView = NSView().sized(height: 132)
      if item.kind == .color { bodyView.colored(ColorPayload.color(from: item.payload)) }
      bodyView.addPinnedSubview(label, inset: 12)
      bodyView.addPinnedSubview(image, inset: 6)
      let metrics = item.kind == .text || item.kind == .richText ? "\(raw.count) characters" : item.kind.displayName
      let footer = UI.label(
        "\(metrics) • Used \(item.useCount) times" + (item.sourceDeviceName.map { " • \($0)" } ?? ""), size: 10,
        secondary: true, lines: 1
      ).sized(height: 30)
      content.addArrangedSubview(bodyView)
      content.addArrangedSubview(footer)
      bodyView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
    setAccessibilityLabel(title + ". " + subtitle)
    setSelected(selected)
  }

  func setSelected(_ selected: Bool) {
    layer?.borderWidth = selected ? 2 : 0.5
    layer?.borderColor = selected ? NSColor.selectedControlColor.cgColor : NSColor.separatorColor.cgColor
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    setAccessibilityValue(selected ? "Selected" : "Not selected")
  }

  func setThumbnail(_ image: NSImage?) {
    guard let image else { return }
    previewImage?.image = image
    previewImage?.isHidden = false
    previewLabel?.isHidden = true
  }

}

// MARK: - ShelfMenus

extension ShelfView {
  private func add(_ menu: NSMenu, _ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
    menu.addItem(ActionMenuItem(title, enabled: enabled, action: action))
  }

  func clipMenu(at row: Int) -> NSMenu? {
    guard viewModel.visibleItems.indices.contains(row) else { return nil }
    viewModel.selectItem(at: row, mode: viewModel.isItemSelected(at: row) ? .activate : .replace)
    guard let item = viewModel.selectedItem else { return nil }
    let menu = NSMenu([])
    let batch = viewModel.selectedItemCount > 1
    add(menu, batch ? "Paste Selection" : "Paste", viewModel.pasteSelected)
    add(menu, batch ? "Copy Selection" : "Copy", viewModel.copySelected)
    add(menu, "Paste Plain Text", viewModel.pasteSelectedPlainText)
    add(menu, "Copy Plain Text", viewModel.copySelectedPlainText)
    if batch {
      add(menu, "Paste Selection as Text", viewModel.pasteSelectedItemsAsText)
      add(menu, "Copy Selection as Text", viewModel.copySelectedItemsAsText)
      add(menu, "Add Selection to Stack", viewModel.addSelectedItemsToStack)
    }
    if viewModel.canShowSelectedInClipboard { add(menu, "Show in Clipboard", showSelectedInClipboard) }
    add(menu, "Rename…", renameSelectedClip)
    add(
      menu, viewModel.isItemStacked(at: row) ? "Remove from Stack" : "Add to Stack",
      viewModel.toggleSelectedStackMembership)
    menu.submenu("Stack", stackMenu())
    if item.kind == .text || item.kind == .code { add(menu, "Edit…", editSelectedClip) }
    if item.kind == .image {
      add(menu, "Rotate Image") { [weak self] in self?.viewModel.rotateSelectedImageClockwise() }
      add(menu, "Extract Text") { [weak self] in self?.viewModel.extractTextFromSelectedImage() }
    }
    add(menu, "Quick Look", onPreview)
    add(menu, item.isPinned ? "Unpin" : "Pin", viewModel.togglePinSelected)
    let collections = NSMenu([])
    var seen = Set<String>()
    for name in Pinboards.names + viewModel.collectionNames where seen.insert(name.lowercased()).inserted {
      let entry = ActionMenuItem(name) { [weak self] in self?.viewModel.assignSelected(to: name) }
      entry.state = item.collectionName == name ? .on : .off
      collections.addItem(entry)
    }
    add(collections, "New Collection…") { [weak self] in
      guard let self, let request = self.requestCollectionCreation() else { return }
      self.viewModel.createCollection(named: request.name, colorHex: request.colorHex, selectAfterCreate: false)
      self.viewModel.assignSelected(to: request.name)
    }
    if item.collectionName != nil {
      add(collections, "Remove from Collection") { [weak self] in self?.viewModel.assignSelected(to: nil) }
    }
    menu.submenu("Add to Collection", collections)
    let ruleMenu = NSMenu([])
    add(
      ruleMenu, "Ignore \(item.sourceApp ?? item.sourceAppBundleId ?? "Source App")",
      enabled: item.sourceApp != nil || item.sourceAppBundleId != nil, viewModel.ignoreSelectedSourceApp)
    add(ruleMenu, "Ignore \(item.kind.displayName) Items", viewModel.ignoreSelectedKind)
    menu.submenu("Capture Rules", ruleMenu)
    menu.addItem(.separator())
    add(menu, "Open", enabled: item.kind.canOpen, viewModel.openSelected)
    add(menu, "Reveal in Finder", enabled: item.kind.canReveal, viewModel.revealSelected)
    add(menu, "Delete", viewModel.deleteSelected)
    return menu
  }

  func stackMenu() -> NSMenu {
    let menu = NSMenu([])
    add(menu, "Add Visible Clips", viewModel.addVisibleItemsToStack)
    let available = viewModel.stackCount > 0
    add(menu, "Paste Next", enabled: available, viewModel.pasteNextStackItem)
    add(menu, "Copy Next", enabled: available, viewModel.copyNextStackItem)
    add(menu, "Paste as Text", enabled: available, viewModel.pasteStackAsText)
    add(menu, "Copy as Text", enabled: available, viewModel.copyStackAsText)
    add(menu, "Clear Stack", enabled: available, viewModel.clearStack)
    add(
      menu, viewModel.isStackCaptureEnabled ? "Stop Stack Capture" : "Start Stack Capture",
      viewModel.toggleStackCaptureMode)
    return menu
  }

  func showClearHistoryMenu() {
    let menu = NSMenu([])
    for (title, seconds) in [("Past Hour", 3600.0), ("Past Day", 86400.0), ("All Time", -1.0)] {
      add(menu, title) { [weak self] in
        self?.viewModel.clearHistory(since: seconds < 0 ? .distantPast : Date().addingTimeInterval(-seconds))
      }
    }
    menu.popUp(positioning: nil, at: NSPoint(x: bounds.maxX - 60, y: bounds.maxY - 32), in: self)
  }

  func updateSidebar() {
    let oldFocus = sidebarButtons.first { window?.firstResponder === $0 }?.title
    sidebarButtons.removeAll()
    sidebar.replace([])
    let counts = viewModel.collectionCountSummary()
    let symbols = [
      "doc.on.clipboard", "chart.bar.fill", "photo", "link", "text.alignleft", "pin.fill", "doc.fill", "music.note",
      "paintpalette", "chevron.left.forwardslash.chevron.right", "film",
    ]
    for mode in ShelfCategory.allCases where viewModel.shouldShowCategory(for: mode) {
      addSidebar(
        mode.title, symbol: symbols[mode.rawValue], count: counts.count(for: mode),
        selected: viewModel.isSortModeCategorySelected(mode), color: ClipboardCollectionVisuals.color(for: mode)
      ) { [weak self] in
        self?.viewModel.selectSortMode(mode, extending: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
      }
    }
    for name in viewModel.collectionNames {
      let button = addSidebar(
        name, symbol: "folder.fill", count: counts.count(named: name),
        selected: viewModel.isCollectionCategorySelected(named: name), color: collectionColor(forCollectionNamed: name)
      ) { [weak self] in
        self?.viewModel.selectCollection(
          named: name, extending: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
      }
      button.onDrop = { [weak self] id in self?.viewModel.assignItem(withID: id, to: name) }
      button.makeMenu = { [weak self] in
        NSMenu([
          ActionMenuItem("Edit…") { self?.editCollection(named: name) },
          ActionMenuItem("Export…") { self?.exportCollection(named: name) },
          ActionMenuItem("Delete…") { self?.deleteCollection(named: name) },
        ])
      }
      button.registerForDraggedTypes([ClipboardItemDragPasteboard.itemIDType])
    }
    if viewModel.stackCount > 0 || viewModel.isStackCaptureEnabled || viewModel.isStackFilterSelected {
      let button = addSidebar(
        "Stack", symbol: "square.stack.3d.up.fill", count: viewModel.stackCount,
        selected: viewModel.isStackFilterSelected, color: .systemGreen
      ) { [weak self] in self?.viewModel.selectStack() }
      button.makeMenu = { [weak self] in self?.stackMenu() ?? NSMenu() }
      button.toolTip = viewModel.isStackCaptureEnabled ? "Stack capture is on" : "Queued clips"
    }
    addSidebar("New Collection", symbol: "plus", count: 0, selected: false, color: .secondaryLabelColor) {
      [weak self] in self?.createCollection()
    }
    if let oldFocus, let next = sidebarButtons.first(where: { $0.title == oldFocus }) {
      window?.makeFirstResponder(next)
    }
  }

  @discardableResult private func addSidebar(
    _ title: String, symbol: String, count: Int, selected: Bool, color: NSColor, action: @escaping () -> Void
  ) -> SidebarButton {
    let button = SidebarButton(title, symbol: symbol) { [weak self] in
      self?.collapseSearchFieldIfIdle()
      action()
    }
    button.setButtonType(.pushOnPushOff)
    button.state = selected ? .on : .off
    button.contentTintColor = color
    button.toolTip = "\(title) (\(count))"
    button.setAccessibilityValue("\(count) clips. \(selected ? "Selected" : "Not selected")")
    button.sized(width: 34, height: 34)
    button.onKey = { [weak self, weak button] event in
      guard let self, let button else { return false }
      if [125, 126, 115, 119].contains(event.keyCode), let index = self.sidebarButtons.firstIndex(of: button) {
        let target =
          event.keyCode == 115
          ? 0
          : event.keyCode == 119
            ? self.sidebarButtons.count - 1
            : max(0, min(self.sidebarButtons.count - 1, index + (event.keyCode == 125 ? 1 : -1)))
        self.window?.makeFirstResponder(self.sidebarButtons[target])
        self.sidebarButtons[target].scrollToVisible(self.sidebarButtons[target].bounds)
        return true
      }
      if [123, 124].contains(event.keyCode) {
        self.viewModel.moveSelection(event.keyCode == 124 ? 1 : -1)
        self.focusSelectedCardForKeyboardNavigation()
        return true
      }
      if let text = shelfSearchText(from: event) {
        self.startSearchFromShelf(text)
        return true
      }
      return false
    }
    sidebarButtons.append(button)
    sidebar.addArrangedSubview(button)
    return button
  }
}

// MARK: - ShelfDialogs

extension ShelfView {
  func editSelectedClip() {
    viewModel.selectItem(at: viewModel.selectedIndex)
    guard let currentText = viewModel.editableTextForSelected() else { return }

    let textView = Self.makePlainTextEditor(initialText: currentText)
    activeWritingToolsTextView = textView
    defer { if activeWritingToolsTextView === textView { activeWritingToolsTextView = nil } }

    guard
      UI.prompt(
        UI.alert("Edit Text", action: "Save"), accessory: textEditorAccessoryView(for: textView), focus: textView)
    else { return }
    viewModel.updateSelectedText(to: textView.string)
  }

  func renameSelectedClip() {
    viewModel.selectItem(at: viewModel.selectedIndex)
    guard let currentTitle = viewModel.editableTitleForSelected() else { return }

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    input.placeholderString = "Clip title"
    input.stringValue = currentTitle

    let alert = UI.alert(
      "Rename Clip", message: "Give this clip a searchable title. Leave it blank to clear the title.", action: "Save")
    guard UI.prompt(alert, accessory: input, focus: input) else { return }
    viewModel.updateSelectedTitle(to: input.stringValue)
  }

  func showSelectedInClipboard() {
    viewModel.selectItem(at: viewModel.selectedIndex)
    viewModel.showSelectedInClipboard()
    searchField.stringValue = viewModel.searchText
    presentSearch(expanded: !viewModel.searchText.isEmpty)
  }

  static func makePlainTextEditor(initialText: String = "") -> NSTextView {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))

    textView.string = initialText
    textView.font = .systemFont(ofSize: 13)
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.usesAdaptiveColorMappingForDarkAppearance = true
    textView.isAutomaticSpellingCorrectionEnabled = true
    textView.isAutomaticTextReplacementEnabled = true

    if textView.responds(to: NSSelectorFromString("setWritingToolsBehavior:")) {
      textView.setValue(1, forKey: "writingToolsBehavior")
    }
    if textView.responds(to: NSSelectorFromString("setAllowedWritingToolsResultOptions:")) {
      textView.setValue(1, forKey: "allowedWritingToolsResultOptions")
    }
    return textView
  }

  private func textEditorAccessoryView(for textView: NSTextView) -> NSView {
    let scrollView = UI.scroll(textView).sized(width: 460, height: 180)
    scrollView.frame = textView.frame
    scrollView.borderType = .bezelBorder
    guard Self.supportsWritingTools(textView) else { return scrollView }

    let writingToolsButton = NSButton(
      title: "Writing Tools", target: self, action: #selector(showWritingToolsForActiveEditor(_:)))
    writingToolsButton.bezelStyle = .rounded
    writingToolsButton.setAccessibilityLabel("Writing Tools")
    writingToolsButton.toolTip = "Open macOS Writing Tools for this text clip."
    let note = UI.label("Uses macOS Writing Tools when available.", size: NSFont.smallSystemFontSize, secondary: true)
    let row = UI.stack([writingToolsButton, note], vertical: false, spacing: 10)
    let stack = UI.stack([scrollView, row])
    stack.frame = NSRect(x: 0, y: 0, width: 460, height: 218)
    return stack
  }

  static func supportsWritingTools(_ textView: NSTextView) -> Bool {
    textView.responds(to: NSSelectorFromString("showWritingTools:"))
  }

  @objc private func showWritingToolsForActiveEditor(_ sender: NSButton) {
    guard let textView = activeWritingToolsTextView, Self.supportsWritingTools(textView) else { return }
    textView.window?.makeFirstResponder(textView)
    NSApp.sendAction(NSSelectorFromString("showWritingTools:"), to: textView, from: sender)
  }

  func collectionColor(forCollectionNamed name: String) -> NSColor {
    ClipboardCollectionVisuals.color(forCollectionNamed: name, overrideHex: viewModel.collectionColorHex(named: name))
  }

  func createCollection() {
    guard let request = requestCollectionCreation() else { return }
    viewModel.createCollection(named: request.name, colorHex: request.colorHex, selectAfterCreate: true)
    focusSelectedCollectionChip()
  }

  func editCollection(named collectionName: String) {
    guard let request = requestCollectionDetails(named: collectionName) else { return }
    viewModel.updateCollection(named: collectionName, to: request.name, colorHex: request.colorHex)
    focusSelectedCollectionChip()
  }

  func exportCollection(named collectionName: String) {
    guard let url = UI.archiveURL(collection: collectionName) else { return }
    viewModel.exportCollection(named: collectionName, to: url) { [weak self] result in
      if case .failure(let error) = result { self?.viewModel.reportCollectionExportFailure(error) }
    }
  }

  func deleteCollection(named collectionName: String) {
    let count = viewModel.collectionCount(named: collectionName)
    guard confirmDeleteCollection(named: collectionName, count: count) else { return }
    viewModel.deleteCollection(named: collectionName)
    focusSelectedCollectionChip()
  }

  func requestCollectionCreation() -> CollectionCreationRequest? { requestCollectionDetails() }

  private func requestCollectionDetails(named initialName: String? = nil) -> CollectionCreationRequest? {
    let editing = initialName != nil
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    input.placeholderString = "Collection name"
    input.stringValue = initialName ?? ""

    let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 48, height: 28))
    colorWell.color =
      initialName.map { collectionColor(forCollectionNamed: $0) }
      ?? ClipboardCollectionVisuals.defaultColor(forCollectionNamed: "New Collection")

    let colorLabel = UI.label("Color", size: NSFont.smallSystemFontSize, secondary: true, weight: .medium)

    let colorRow = UI.stack([colorLabel, colorWell], vertical: false, spacing: 10)
    let stack = UI.stack([input, colorRow], spacing: 10)
    stack.frame = NSRect(x: 0, y: 0, width: 260, height: 64)

    let alert = UI.alert(
      editing ? "Edit Collection" : "New Collection",
      message: editing ? "Update this collection's name and color." : "Name this collection and choose its color.",
      action: editing ? "Save" : "Create")
    guard UI.prompt(alert, accessory: stack, focus: input), let name = Pinboards.normalizedName(input.stringValue)
    else { return nil }
    return CollectionCreationRequest(name: name, colorHex: ClipboardCollectionVisuals.hexString(for: colorWell.color))
  }

  private func confirmDeleteCollection(named collectionName: String, count: Int) -> Bool {
    let noun = count == 1 ? "clip" : "clips"
    let message =
      count > 0
      ? "This removes \(count) \(noun) in this collection from clipboard history."
      : "This removes the empty collection."
    let alert = UI.alert("Delete \(collectionName)?", message: message, action: "Delete", warning: true)
    return alert.runModal() == .alertFirstButtonReturn
  }
}

// MARK: - ShelfPresentation

enum ClipboardCollectionVisuals {
  private static func rgb(_ components: (CGFloat, CGFloat, CGFloat)) -> NSColor {
    NSColor(calibratedRed: components.0, green: components.1, blue: components.2, alpha: 1)
  }
  private static let customPalette = [
    (0.98, 0.30, 0.32), (0.96, 0.64, 0.00), (0.04, 0.47, 0.95), (0.18, 0.72, 0.34), (0.55, 0.35, 0.88),
    (0.93, 0.12, 0.34), (0.10, 0.62, 0.72), (0.74, 0.42, 0.16),
  ].map(rgb)
  static func color(for mode: ShelfCategory) -> NSColor {
    switch mode {
    case .mostRecent: return .secondaryLabelColor
    case .mostUsed: return rgb((0.58, 0.42, 0.92))
    case .text: return rgb((0.96, 0.64, 0.00))
    case .links: return rgb((0.02, 0.47, 0.98))
    case .images: return rgb((1.00, 0.22, 0.25))
    case .colors: return rgb((0.00, 0.65, 0.74))
    case .audio: return rgb((0.93, 0.12, 0.34))
    case .files: return rgb((0.11, 0.68, 0.36))
    case .pinned: return rgb((0.94, 0.12, 0.48))
    case .code: return rgb((0.25, 0.38, 0.78))
    case .videos: return rgb((0.43, 0.32, 0.94))
    }
  }

  static func color(forCollectionNamed name: String, overrideHex: String? = nil) -> NSColor {
    if let color = color(fromHex: overrideHex) { return color }
    return defaultColor(forCollectionNamed: name)
  }

  static func defaultColor(forCollectionNamed name: String) -> NSColor {
    switch name {
    case "Useful Links": return customPalette[0]
    case "Important Notes": return customPalette[1]
    case "Code Snippets": return customPalette[2]
    case "Read Later": return customPalette[3]
    default: return customPalette[stablePaletteIndex(for: name)]
    }
  }

  static func hexString(for color: NSColor) -> String {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    return "#"
      + [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
        String(format: "%02X", Int(($0 * 255).rounded()))
      }.joined()
  }

  private static func color(fromHex value: String?) -> NSColor? {
    guard let value else { return nil }
    var hex = value.clipboardTrimmed
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6, let rawValue = Int(hex, radix: 16) else { return nil }
    let red = CGFloat((rawValue >> 16) & 0xFF) / 255
    let green = CGFloat((rawValue >> 8) & 0xFF) / 255
    let blue = CGFloat(rawValue & 0xFF) / 255
    return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
  }

  private static func stablePaletteIndex(for name: String) -> Int {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for scalar in name.lowercased().unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return Int(hash % UInt64(customPalette.count))
  }
}

struct CollectionCreationRequest {
  let name: String
  let colorHex: String
}

enum ClipPresentation {
  static func title(_ item: Clip) -> String {
    if let custom = item.customTitle?.clipboardTrimmed, !custom.isEmpty { return custom }
    switch item.kind {
    case .url:
      let title = item.displayText.clipboardTrimmed
      return !title.isEmpty && title != item.payload ? title : URL(string: item.payload)?.host ?? title
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      return urls.count > 1 ? "\(urls.count) files" : urls.first?.lastPathComponent ?? item.displayText
    case .code: return CodeSnippetPayload.title(from: item.payload)
    case .color: return ColorPayload.displayHex(from: item.payload)
    default: return item.displayText.components(separatedBy: .newlines).first ?? item.kind.displayName
    }
  }

  static func body(_ item: Clip) -> String {
    switch item.kind {
    case .text, .unknown: return item.payload
    case .richText: return item.displayText
    case .code: return CodeSnippetPayload.previewLines(from: item.payload, maxLines: 6).joined(separator: "\n")
    case .color: return ColorPayload.componentSummary(from: item.payload)
    case .file: return FilePayload.urls(from: item.payload).prefix(6).map(\.lastPathComponent).joined(separator: "\n")
    case .image: return item.ocrText ?? "Image clip"
    case .pdf: return item.ocrText ?? "PDF document"
    case .audio: return "Sound clip"
    case .video: return "Video clip"
    case .url: return item.payload
    }
  }
}

// MARK: - Controls

enum UI {
  static func alert(
    _ title: String, message: String = "", action: String, cancel: String = "Cancel", warning: Bool = false
  ) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    if warning { alert.alertStyle = .warning }
    alert.addButton(withTitle: action)
    alert.addButton(withTitle: cancel)
    return alert
  }

  static func archiveURL(importing: Bool = false, collection: String? = nil) -> URL? {
    let panel: NSSavePanel = importing ? NSOpenPanel() : NSSavePanel()
    panel.title = collection.map { "Export \($0) Pinboard" } ?? "\(importing ? "Import" : "Export") Goldfish Archive"
    panel.setValue([HistoryArchive.fileExtension], forKey: "allowedFileTypes")
    if let open = panel as? NSOpenPanel {
      open.canChooseFiles = true
      open.canChooseDirectories = false
      open.allowsMultipleSelection = false
    } else {
      let date = DateFormatter()
      date.dateFormat = "yyyy-MM-dd-HHmm"
      let safeName = collection?.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        .joined(separator: "-")
      let suffix = collection == nil ? "" : "-\(safeName.flatMap { $0.isEmpty ? nil : $0 } ?? "Pinboard")"
      panel.nameFieldStringValue = "Goldfish\(suffix)-\(date.string(from: Date())).\(HistoryArchive.fileExtension)"
    }
    return panel.runModal() == .OK ? panel.url : nil
  }

  static func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = vertical ? .vertical : .horizontal
    stack.alignment = vertical ? .leading : .centerY
    stack.spacing = spacing
    return stack
  }

  static func label(
    _ text: String, size: CGFloat = 13, secondary: Bool = false, color: NSColor? = nil,
    weight: NSFont.Weight = .regular, lines: Int = 0, truncation: NSLineBreakMode = .byTruncatingTail,
    monospaced: Bool = false
  ) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font =
      monospaced ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    label.textColor = color ?? (secondary ? .secondaryLabelColor : .labelColor)
    label.maximumNumberOfLines = lines
    label.lineBreakMode = lines == 0 ? .byWordWrapping : truncation
    return label
  }

  static func window(
    _ title: String, size: NSSize, minimum: NSSize? = nil,
    style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    if let minimum { window.minSize = minimum }
    window.center()
    return window
  }

  static func host<Content: View>(_ content: Content, in window: NSWindow, delegate: NSWindowDelegate) {
    let host = NSHostingView(rootView: content)
    host.sizingOptions = []
    window.contentView = host
    window.delegate = delegate
  }

  static func show(_ window: NSWindow?) {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  static func animate(_ duration: TimeInterval, changes: () -> Void, completion: @escaping () -> Void = {}) {
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        context.allowsImplicitAnimation = true
        changes()
      }, completionHandler: completion)
  }

  static func prompt(_ alert: NSAlert, accessory: NSView? = nil, focus: NSView? = nil) -> Bool {
    alert.accessoryView = accessory
    alert.window.initialFirstResponder = focus
    return alert.runModal() == .alertFirstButtonReturn
  }

  static func scroll(_ document: NSView, topAligned: Bool = false) -> NSScrollView {
    let scroll = NSScrollView()
    if topAligned {
      let container = TopAlignedDocumentView()
      container.translatesAutoresizingMaskIntoConstraints = false
      document.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(document)
      scroll.documentView = container
      NSLayoutConstraint.activate([
        container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        container.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        container.bottomAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.bottomAnchor),
        container.bottomAnchor.constraint(greaterThanOrEqualTo: document.bottomAnchor),
        document.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        document.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        document.topAnchor.constraint(equalTo: container.topAnchor),
      ])
    } else {
      scroll.documentView = document
    }
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    return scroll
  }
}

class ActionButton: NSButton {
  private let handler: () -> Void

  init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
    handler = action
    super.init(frame: .zero)
    self.title = title
    target = self
    self.action = #selector(invoke)
    bezelStyle = .rounded
    if let symbol {
      image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      image?.isTemplate = true
      imageScaling = .scaleProportionallyDown
      imagePosition = .imageOnly
      isBordered = false
      toolTip = title
    }
    setAccessibilityLabel(title)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func invoke() { handler() }
}

final class ActionMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
    handler = action
    super.init(title: title, action: nil, keyEquivalent: "")
    target = self
    self.action = #selector(invoke)
    isEnabled = enabled
  }

  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func invoke() { handler() }
}

final class TopAlignedDocumentView: NSView { override var isFlipped: Bool { true } }

// MARK: - NSImage — Helpers

extension NSImage {
  func resized(to fitSize: CGSize) -> NSImage {
    let target = NSSize(width: fitSize.width, height: fitSize.height)
    let currentSize = size
    let ratio = min(target.width / currentSize.width, target.height / currentSize.height, 1.0)

    let newSize = NSSize(width: currentSize.width * ratio, height: currentSize.height * ratio)
    let newImage = NSImage(size: newSize)
    newImage.lockFocus()
    draw(
      in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: currentSize), operation: .sourceOver,
      fraction: 1.0)
    newImage.unlockFocus()
    newImage.size = newSize
    return newImage
  }

  func pngData() -> Data? {
    guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
  }

  func rotatedClockwise() -> NSImage? {
    guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil), cgImage.width > 0, cgImage.height > 0
    else { return nil }

    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let context = CGContext(
        data: nil, width: cgImage.height, height: cgImage.width, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: bitmapInfo)
    else { return nil }

    context.interpolationQuality = .high
    context.translateBy(x: CGFloat(cgImage.height), y: 0)
    context.rotate(by: .pi / 2)
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

    guard let output = context.makeImage() else { return nil }
    return NSImage(cgImage: output, size: NSSize(width: cgImage.height, height: cgImage.width))
  }
}

// MARK: - NSView — Layout

extension NSView {
  @discardableResult func sized(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
    translatesAutoresizingMaskIntoConstraints = false
    if let width { widthAnchor.constraint(equalToConstant: width).isActive = true }
    if let height { heightAnchor.constraint(equalToConstant: height).isActive = true }
    return self
  }

  @discardableResult func colored(_ color: NSColor?, radius: CGFloat = 0) -> Self {
    wantsLayer = true
    layer?.backgroundColor = color?.cgColor
    layer?.cornerRadius = radius
    layer?.masksToBounds = radius > 0
    return self
  }

  func addPinnedSubview(
    _ child: NSView, inset: CGFloat = 0, edges: [NSLayoutConstraint.Attribute] = [.leading, .trailing, .top, .bottom]
  ) {
    child.translatesAutoresizingMaskIntoConstraints = false
    addSubview(child)
    NSLayoutConstraint.activate(
      edges.map { edge in
        NSLayoutConstraint(
          item: child, attribute: edge, relatedBy: .equal, toItem: self, attribute: edge, multiplier: 1,
          constant: [.trailing, .bottom].contains(edge) ? -inset : inset)
      })
  }
}

extension NSStackView {
  func replace(_ views: [NSView]) {
    arrangedSubviews.forEach {
      removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    views.forEach(addArrangedSubview)
  }
}

extension NSMenu {
  convenience init(_ entries: [NSMenuItem]) {
    self.init()
    autoenablesItems = false
    entries.forEach(addItem)
  }
  func submenu(_ title: String, _ menu: NSMenu) {
    let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    entry.submenu = menu
    addItem(entry)
  }
}

// MARK: - String — Whitespace

extension StringProtocol {
  var clipboardTrimmed: String {
    var start = startIndex
    var end = endIndex

    while start < end, self[start].isWhitespace { formIndex(after: &start) }
    while end > start {
      let previous = index(before: end)
      if !self[previous].isWhitespace { break }
      end = previous
    }

    return String(self[start..<end])
  }
}

extension String {
  func normalizedLabel(limit: Int) -> String? {
    let value = split { $0.isWhitespace }.joined(separator: " ")
    return value.isEmpty ? nil : String(value.prefix(limit))
  }
}
