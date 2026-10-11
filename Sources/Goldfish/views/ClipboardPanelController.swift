import AppKit

struct ClipboardPanelReflowPlan {
  let frame: NSRect
  let bottomSafeInset: CGFloat
}

enum ClipboardPanelShortcutAction: Equatable {
  case close
  case copy
  case copyPlainText
  case edit
  case focusSearch
  case newCollection
  case newText
  case nextCollection
  case open
  case pastePlainText
  case preview
  case previousCollection
  case rename
  case reveal
  case showInClipboard
  case toggleCapturePause
  case togglePin
  case undoDelete
}

enum ClipboardPanelNavigationAction: Equatable {
  case first
  case last
  case next
  case pageNext
  case pagePrevious
  case previous
}

enum ClipboardPanelSelectionAction: Equatable {
  case extendFirst
  case extendLast
  case extendNext
  case extendPageNext
  case extendPagePrevious
  case extendPrevious
  case selectAll
}

final class ClipboardPanelController: NSObject, NSWindowDelegate {
  // The shelf is a transient menu-bar overlay. The Dock sits above floating
  // windows, so use the lowest standard level above it while the shelf is open.
  static let shelfWindowLevel: NSWindow.Level = .statusBar

  private enum Animation {
    static let showDuration: TimeInterval = 0.28
    static let hideDuration: TimeInterval = 0.20
    static let reflowDuration: TimeInterval = 0.18
    static let easing: CAMediaTimingFunctionName = .easeInEaseOut

    static func duration(_ preferredDuration: TimeInterval) -> TimeInterval {
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : preferredDuration
    }
  }
  private enum Metrics {
    static let minimumVerticalShelfWidth: CGFloat = 320
    static let maximumVerticalShelfWidthRatio: CGFloat = 0.50
  }

  private var panel: KeyablePanel!
  private var panelView: ClipboardPanelView!
  private let settings: SettingsModel
  private(set) var isVisible = false
  var statusItemFrameProvider: () -> NSRect? = { nil }
  private var clickMonitor: Any?
  private var keyMonitor: Any?
  private var hoverRefreshTimer: Timer?
  private var lastHoverPointerLocation: NSPoint?
  private var targetApplication: NSRunningApplication?
  private var activeScreenSnapshot: (screenFrame: CGRect, visibleFrame: CGRect)?
  private let pollClipboardNow: () -> Void
  private let preferredScreenProvider: () -> NSScreen?
  private let openSettings: () -> Void
  private var isAnimating = false
  private var visibilityAnimationGeneration = 0
  private var lastAutomaticDismissalUptime: TimeInterval?
  private var filePreviewController: ClipboardPreviewWindowController?
  private var isPresentingPreview = false
  private var isDismissingPreviews = false
  private var linkPreviewController: LinkPreviewWindowController?
  private var screenParametersObserver: NSObjectProtocol?
  private static let quickPasteKeyCodes: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
  private static let collectionShortcuts: [UInt16: ClipboardSortMode] = [
    18: .mostRecent, 19: .mostUsed, 20: .text, 21: .links, 23: .images, 22: .files, 26: .pinned, 28: .audio, 25: .colors, 29: .code,
  ]

  private let viewModel: ClipboardPanelViewModel

  init(
    pasteboard: NSPasteboard = .general, store: ClipboardStore, settings: SettingsModel, cacheService: ClipboardCacheService,
    dataCoordinator: ClipboardDataCoordinator = ClipboardDataCoordinator(), preferredScreen: @escaping () -> NSScreen? = { nil },
    pollClipboardNow: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {},
    transferFeedback: @escaping (ClipboardSound) -> Void = { _ in }
  ) {
    self.settings = settings
    self.viewModel = ClipboardPanelViewModel(
      pasteboard: pasteboard, store: store, settings: settings, cacheService: cacheService, dataCoordinator: dataCoordinator,
      transferFeedback: transferFeedback)
    self.pollClipboardNow = pollClipboardNow
    self.openSettings = openSettings
    self.preferredScreenProvider = preferredScreen
    super.init()

    viewModel.targetApplicationProvider = { [weak self] in self?.targetApplication }
    viewModel.willPasteToTarget = { [weak self] in self?.hide(immediate: true) }

    panelView = ClipboardPanelView(
      viewModel: viewModel, onClose: { [weak self] in self?.hide() }, onPreview: { [weak self] in self?.previewSelected() })

    let initialScreen = NSScreen.main
    let initialScreenFrame = initialScreen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let contentSize =
      settings.shelfLayout == .cards
      ? Self.panelFrames(
        forScreenFrame: initialScreenFrame, visibleFrame: initialScreen?.visibleFrame ?? initialScreenFrame,
        preferredWidth: CGFloat(settings.shelfWidth.rawValue), layout: .cards, largerText: settings.largerShelfText
      ).shown.size : NSSize(width: 336 + ClipboardShelfControls.contentTypeRailAllowance, height: 760)
    panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
      styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    panel.contentView = panelView
    panelView.onMenuDismiss = { [weak self] in self?.dismissIfFocusLeftShelf() }
    panel.hasShadow = false
    panel.isFloatingPanel = true
    panel.level = Self.shelfWindowLevel
    panel.acceptsMouseMovedEvents = true
    panel.onPointerMoved = { [weak self] location in
      guard let self else { return }
      self.lastHoverPointerLocation = location
      self.panelView.updateHoverForPointer(atWindowLocation: location)
    }
    panel.hidesOnDeactivate = false
    panel.delegate = self
    panel.isOpaque = false
    panel.backgroundColor = NSColor.clear
    panel.collectionBehavior = Self.panelCollectionBehavior
    panel.becomesKeyOnlyIfNeeded = false
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.standardWindowButton(.closeButton)?.isHidden = true
    applyPanelSharingSetting()

    settings.observe { [weak self] change in
      guard change == .hideFromScreenCapture || change == .panelSide || change == .other else { return }
      DispatchQueue.main.async {
        if change == .hideFromScreenCapture { self?.applyPanelSharingSetting() } else { self?.reflowPanelForScreenChange() }
      }
    }

    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.reflowPanelForScreenChange() }
  }

  deinit {
    hoverRefreshTimer?.invalidate()
    removeClickMonitor()
    removeKeyMonitor()
    if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
  }

  func toggle(preferredScreen explicitScreen: NSScreen? = nil) { if isVisible { hide() } else { show(preferredScreen: explicitScreen) } }

  func toggleFromStatusItem(_ event: NSEvent?, preferredScreen: NSScreen? = nil) {
    // Focus loss can reach us before the status button's mouse-down action.
    // If that click already dismissed the shelf, it must not toggle it open.
    // Compare event ordering, not an animation duration or debounce interval:
    // a genuinely later click can reopen immediately, even while closing.
    if let event, event.type == .leftMouseDown, let dismissedAt = lastAutomaticDismissalUptime, event.timestamp <= dismissedAt { return }
    toggle(preferredScreen: preferredScreen)
  }

  func createCollection() {
    performWhenVisible { [weak self] in
      guard let self else { return }
      self.panelView.createCollection()
    }
  }

  func createTextClip() { performWhenVisible { [weak self] in self?.panelView.createTextClip() } }

  func didCaptureItem(_ item: ClipboardItem) { viewModel.didCaptureItem(item) }

  func show(preferredScreen explicitScreen: NSScreen? = nil) {
    if isVisible { return }
    lastAutomaticDismissalUptime = nil
    let wasAnimating = isAnimating
    visibilityAnimationGeneration += 1
    let generation = visibilityAnimationGeneration
    isAnimating = true
    isVisible = true

    rememberTargetApplication()
    pollClipboardNow()

    guard let screen = preferredScreen(explicitScreen: explicitScreen) else {
      isVisible = false
      isAnimating = false
      return
    }
    activeScreenSnapshot = (screen.frame, screen.visibleFrame)
    let frames = Self.panelFrames(
      forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame, side: settings.panelSide,
      preferredWidth: CGFloat(settings.shelfWidth.rawValue), layout: settings.shelfLayout, largerText: settings.largerShelfText)
    panelView.setBottomSafeInset(
      settings.shelfLayout == .cards ? 14 : Self.contentBottomInset(forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame))
    if !wasAnimating {
      panel.setFrame(frames.hidden, display: false)
      panel.alphaValue = 0.0
    }
    panel.makeKeyAndOrderFront(nil)
    panelView.prepareForShow()
    viewModel.selectFirstItem()
    panelView.beginOpeningTransition(fromLeft: settings.panelSide == .left)
    startHoverRefresh()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.duration(Animation.showDuration)
      context.allowsImplicitAnimation = true
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.85, 0.25, 1)
      panel.animator().setFrame(frames.shown, display: true)
      panel.animator().alphaValue = 1.0
    } completionHandler: { [weak self] in
      guard let self, self.visibilityAnimationGeneration == generation else { return }
      self.isAnimating = false
      self.panelView.finishOpeningTransition()
      guard self.isVisible else { return }
      self.installClickMonitor()
      if !self.panelView.resumeTextEditorIfNeeded() { self.panelView.focusSelectedCardForKeyboardNavigation() }
    }

    installKeyMonitor()
  }

  func hide() { hide(immediate: false) }

  @discardableResult func dismissForSettings() -> Bool {
    guard panel.attachedSheet == nil, !panelView.hasActiveTextEditor else {
      (panel.attachedSheet ?? panelView.presentedTextEditorWindow)?.makeKeyAndOrderFront(nil)
      return false
    }
    hide(immediate: true)
    return true
  }

  private func requestSettings() {
    guard dismissForSettings() else { return }
    openSettings()
  }

  func hide(immediate: Bool) {
    guard panel.attachedSheet == nil else {
      panel.attachedSheet?.makeKeyAndOrderFront(nil)
      return
    }
    guard isVisible || (immediate && isAnimating) else { return }
    visibilityAnimationGeneration += 1
    let generation = visibilityAnimationGeneration
    isVisible = false
    stopHoverRefresh()
    panelView.suspendTextEditor()
    panelView.dismissMenus()
    dismissPreviews()
    panelView.clearPointerHoverStates(animated: false)
    removeClickMonitor()
    removeKeyMonitor()
    if immediate {
      isAnimating = false
      panelView.finishOpeningTransition()
      panel.orderOut(nil)
      isVisible = false
      removeClickMonitor()
      removeKeyMonitor()
      activeScreenSnapshot = nil
      return
    }

    let screenFrames = activeScreenSnapshot ?? activeScreenFrames()
    let hidden = Self.panelFrames(
      forScreenFrame: screenFrames.screenFrame, visibleFrame: screenFrames.visibleFrame, side: settings.panelSide,
      preferredWidth: CGFloat(settings.shelfWidth.rawValue), layout: settings.shelfLayout, largerText: settings.largerShelfText
    ).hidden
    isAnimating = true
    panelView.beginClosingTransition()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.duration(Animation.hideDuration)
      context.allowsImplicitAnimation = true
      context.timingFunction = CAMediaTimingFunction(name: Animation.easing)
      panel.animator().alphaValue = 0.0
      panel.animator().setFrame(hidden, display: true)
    } completionHandler: { [weak self] in
      guard let self, self.visibilityAnimationGeneration == generation else { return }
      self.panel.orderOut(nil)
      self.panel.alphaValue = 1.0
      self.isAnimating = false
      self.activeScreenSnapshot = nil
      self.panelView.finishOpeningTransition()
    }
  }

  private func startHoverRefresh() {
    stopHoverRefresh()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.refreshHoverFromPointer() }
    RunLoop.main.add(timer, forMode: .common)
    hoverRefreshTimer = timer
  }

  private func stopHoverRefresh() {
    hoverRefreshTimer?.invalidate()
    hoverRefreshTimer = nil
    lastHoverPointerLocation = nil
  }

  private func refreshHoverFromPointer() {
    guard isVisible, panel.isVisible else { return }
    let location = panel.mouseLocationOutsideOfEventStream
    guard lastHoverPointerLocation != location else { return }
    lastHoverPointerLocation = location
    panelView.updateHoverForPointer(atWindowLocation: location)
  }

  private func performWhenVisible(_ action: @escaping () -> Void) {
    if isVisible, !isAnimating {
      action()
      return
    }

    show()
    let animationDelay = Animation.duration(Animation.showDuration)
    let deadline = DispatchTime.now() + animationDelay + (animationDelay > 0 ? 0.03 : 0)
    DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
      guard let self, self.isVisible else { return }
      action()
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    guard panel.attachedSheet == nil else { return }
    guard !isPrimaryStatusItemClick(NSApp.currentEvent) else { return }
    dismissIfFocusLeftShelf()
  }

  private func dismissIfFocusLeftShelf() {
    // Resignation arrives before the new key window is installed. Give sheets,
    // menus and our preview a chance to take focus before deciding to dismiss.
    let generation = visibilityAnimationGeneration
    DispatchQueue.main.async { [weak self] in
      guard let self, self.visibilityAnimationGeneration == generation, self.isVisible, !self.isPresentingPreview,
        self.panel.attachedSheet == nil
      else { return }
      let ownedWindows = [
        self.panel, self.filePreviewController?.window, self.linkPreviewController?.window, self.panelView.presentedMenuWindow,
        self.panelView.presentedTextEditorWindow,
      ]
      guard !ownedWindows.contains(where: { $0?.isKeyWindow == true }) else { return }
      self.dismissForOutsideInteraction()
    }
  }

  private func dismissForOutsideInteraction() {
    guard isVisible, panel.attachedSheet == nil else { return }
    lastAutomaticDismissalUptime = ProcessInfo.processInfo.systemUptime
    hide()
  }

  private func isPrimaryStatusItemClick(_ event: NSEvent?) -> Bool {
    guard let event else { return false }
    return Self.isPrimaryStatusItemClick(
      eventType: event.type, modifiers: event.modifierFlags, location: NSEvent.mouseLocation, statusItemFrame: statusItemFrameProvider())
  }

  static func isPrimaryStatusItemClick(
    eventType: NSEvent.EventType, modifiers: NSEvent.ModifierFlags, location: NSPoint, statusItemFrame: NSRect?
  ) -> Bool {
    guard eventType == .leftMouseDown || eventType == .leftMouseUp, !modifiers.contains(.control), let statusItemFrame else { return false }
    return statusItemFrame.contains(location)
  }

  func windowWillBeginSheet(_ notification: Notification) { panel.hidesOnDeactivate = false }
  func windowDidEndSheet(_ notification: Notification) {
    guard isVisible else { return }
    panel.makeKeyAndOrderFront(nil)
    panelView.focusSelectedCardForKeyboardNavigation()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    if let editor = panelView.presentedTextEditorWindow, editor.isVisible {
      DispatchQueue.main.async { [weak self, weak editor] in
        guard let self, let editor, self.isVisible, self.panel.isKeyWindow, self.panelView.presentedTextEditorWindow === editor else {
          return
        }
        editor.makeKeyAndOrderFront(nil)
      }
      return
    }
    if let menu = panelView.presentedMenuWindow, menu.isVisible {
      // Nonactivating panels can briefly give focus back to the mouse-down
      // window after its button opens a child. Keep the menu's keyboard scope.
      DispatchQueue.main.async { [weak self, weak menu] in
        guard let self, let menu, self.isVisible, self.panelView.presentedMenuWindow === menu, menu.isVisible, self.panel.isKeyWindow else {
          return
        }
        menu.makeKeyAndOrderFront(nil)
      }
      return
    }
    if !panelView.isSearchFieldEditing { panelView.focusSelectedCardForKeyboardNavigation() }
  }

  private func preferredScreen(explicitScreen: NSScreen? = nil) -> NSScreen? {
    let point = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    return Self.selectedOpenScreen(
      explicit: explicitScreen, preferred: preferredScreenProvider(), pointer: pointerScreen, fallback: NSScreen.screens.first)
  }

  static func selectedOpenScreen<Screen>(explicit: Screen?, preferred: Screen?, pointer: Screen?, fallback: Screen?) -> Screen? {
    explicit ?? preferred ?? pointer ?? fallback
  }

  static func selectedReflowScreen<Screen>(
    currentPanel: Screen?, lastKnown: Screen?, preferred: Screen?, pointer: Screen?, fallback: Screen?
  ) -> Screen? { currentPanel ?? lastKnown ?? preferred ?? pointer ?? fallback }

  static func panelFrames(
    forScreenFrame screenFrame: CGRect, visibleFrame: CGRect, side: ClipboardPanelSide = .right, preferredWidth: CGFloat = 420,
    layout: ClipboardShelfLayout = .sidebar, largerText: Bool = false
  ) -> (shown: NSRect, hidden: NSRect) {
    let intersectedFrame = visibleFrame.intersection(screenFrame)
    let effectiveFrame = intersectedFrame.width > 0 && intersectedFrame.height > 0 ? intersectedFrame : screenFrame
    if layout == .cards {
      let card = ClipboardItemCardLayout.gallery(
        width: ClipboardShelfWidth(rawValue: Int(preferredWidth)) ?? .standard, largerText: largerText)
      let margin = min(12, max(0, screenFrame.width / 20))
      let width = max(1, screenFrame.width - margin * 2)
      // One toolbar row, card lift clearance, and a dedicated scrollbar lane.
      // Span the display, including space reserved for a side or bottom Dock.
      let height = min(max(1, effectiveFrame.maxY - screenFrame.minY - 24), card.height + 102)
      let shown = NSRect(x: screenFrame.minX + margin, y: screenFrame.minY + 12, width: width, height: height)
      return (shown, shown.offsetBy(dx: 0, dy: -22))
    }
    return verticalPanelFrames(forScreenFrame: screenFrame, effectiveFrame: effectiveFrame, side: side, preferredWidth: preferredWidth)
  }

  private static func verticalPanelFrames(
    forScreenFrame screenFrame: CGRect, effectiveFrame: CGRect, side: ClipboardPanelSide, preferredWidth: CGFloat
  ) -> (shown: NSRect, hidden: NSRect) {
    let margin: CGFloat = min(12, max(0, min(effectiveFrame.width, effectiveFrame.height) / 20))
    let available = effectiveFrame.insetBy(dx: margin, dy: margin)
    // The vertical type rail expands inward so it never steals width from the
    // clip cards or forces the standard two-column grid back to one column.
    let targetWidth = panelWidth(
      within: max(1, available.width), preferredWidth: preferredWidth + ClipboardShelfControls.contentTypeRailAllowance)
    let shownX = side == .left ? available.minX : available.maxX - targetWidth
    // The shelf is above the Dock. Keep its top below the menu bar, but let
    // its bottom reach the display edge instead of stopping at the Dock's
    // reserved visible-frame boundary.
    let bottom = screenFrame.minY + margin
    let shown = NSRect(x: shownX, y: bottom, width: targetWidth, height: max(1, available.maxY - bottom))
    return (shown, shown.offsetBy(dx: side == .left ? -18 : 18, dy: 0))
  }

  private static func panelWidth(within visibleWidth: CGFloat, preferredWidth: CGFloat) -> CGFloat {
    let available = max(1, visibleWidth)
    let preferred = min(preferredWidth, floor(available * Metrics.maximumVerticalShelfWidthRatio))
    return min(available, max(Metrics.minimumVerticalShelfWidth, preferred))
  }

  static func contentBottomInset(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
    // Keep the footer comfortably inset from the shelf's rounded bottom edge.
    16
  }

  static var panelCollectionBehavior: NSWindow.CollectionBehavior { [.moveToActiveSpace, .fullScreenAuxiliary, .transient] }

  static func reflowPlan(
    forScreenFrame screenFrame: CGRect, visibleFrame: CGRect, side: ClipboardPanelSide = .right, preferredWidth: CGFloat = 420,
    layout: ClipboardShelfLayout = .sidebar, largerText: Bool = false
  ) -> ClipboardPanelReflowPlan {
    let frames = panelFrames(
      forScreenFrame: screenFrame, visibleFrame: visibleFrame, side: side, preferredWidth: preferredWidth, layout: layout,
      largerText: largerText)
    return ClipboardPanelReflowPlan(
      frame: frames.shown,
      bottomSafeInset: layout == .cards ? 14 : contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame))
  }

  static func panelSharingType(hideFromScreenCapture: Bool) -> NSWindow.SharingType { hideFromScreenCapture ? .none : .readOnly }

  private func applyPanelSharingSetting() {
    panel.sharingType = Self.panelSharingType(hideFromScreenCapture: settings.hideFromScreenCapture)
  }

  private func rememberTargetApplication() {
    if targetApplication?.isTerminated == true { targetApplication = nil }
    guard let frontmost = NSWorkspace.shared.frontmostApplication,
      frontmost.processIdentifier != NSRunningApplication.current.processIdentifier
    else { return }
    targetApplication = frontmost
  }

  private func removeClickMonitor() {
    if let clickMonitor {
      NSEvent.removeMonitor(clickMonitor)
      self.clickMonitor = nil
    }
  }

  private func installKeyMonitor() {
    removeKeyMonitor()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true), self.panelView.isSearchFieldEditing,
        Self.searchFieldPreviewShortcut(
          forKeyCode: event.keyCode, modifiers: event.modifierFlags, searchText: self.panelView.searchTextForKeyboardShortcut)
      {
        self.previewSelected()
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
        let index = Self.quickPasteIndex(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
      {
        self.viewModel.pasteItem(at: index)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
        let index = Self.quickPastePlainTextIndex(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
      {
        self.viewModel.pasteItemPlainText(at: index)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
        let mode = Self.collectionShortcutMode(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
      {
        self.viewModel.sortMode = mode
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
        Self.matchesShortcut(keyCode: event.keyCode, modifiers: event.modifierFlags, binding: self.settings.settingsShortcut)
      {
        self.requestSettings()
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
        let action = Self.commandShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
      {
        if self.panelView.isSearchFieldEditing, [.copy, .undoDelete, .previousCollection, .nextCollection].contains(action) {
          return event
        }
        self.performShortcutAction(action)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
        let action = Self.modifiedShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
      {
        self.performShortcutAction(action)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event),
        let action = Self.selectionShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
      {
        self.performSelectionAction(action)
        return nil
      }
      guard self.shouldHandlePanelKeyEvent(event) else { return event }
      if let action = Self.navigationShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.performNavigationAction(action)
        return nil
      }
      switch event.keyCode {
      case 53:
        if !self.panelView.clearSearchForKeyboardCancel() { self.hide() }
        return nil
      case 49:
        self.previewSelected()
        return nil
      case 36:
        self.viewModel.pasteSelected()
        return nil
      case 51, 117:
        self.viewModel.deleteSelected()
        return nil
      default: return event
      }
    }
  }

  private func performNavigationAction(_ action: ClipboardPanelNavigationAction) {
    switch action {
    case .first: viewModel.selectFirstItem()
    case .last: viewModel.selectLastItem()
    case .next: viewModel.moveSelection(1)
    case .pageNext: viewModel.moveSelection(panelView.visibleCardPageStep)
    case .pagePrevious: viewModel.moveSelection(-panelView.visibleCardPageStep)
    case .previous: viewModel.moveSelection(-1)
    }
    panelView.focusSelectedCardForKeyboardNavigation()
  }

  private func performSelectionAction(_ action: ClipboardPanelSelectionAction) {
    switch action {
    case .extendFirst: viewModel.selectItem(at: 0, mode: .range)
    case .extendLast: viewModel.selectItem(at: viewModel.visibleItems.count - 1, mode: .range)
    case .extendNext: extendSelection(by: 1)
    case .extendPageNext: extendSelection(by: panelView.visibleCardPageStep)
    case .extendPagePrevious: extendSelection(by: -panelView.visibleCardPageStep)
    case .extendPrevious: extendSelection(by: -1)
    case .selectAll: viewModel.selectAllVisibleItems()
    }
    panelView.focusSelectedCardForKeyboardNavigation()
  }

  private func extendSelection(by delta: Int) {
    let count = viewModel.visibleItems.count
    guard count > 0 else { return }
    let target = max(0, min(count - 1, viewModel.selectedIndex + delta))
    viewModel.selectItem(at: target, mode: .range)
  }

  private func performShortcutAction(_ action: ClipboardPanelShortcutAction) {
    switch action {
    case .close: hide()
    case .copy: viewModel.copySelected()
    case .copyPlainText: viewModel.copySelectedPlainText()
    case .edit: panelView.editSelectedClip()
    case .focusSearch: panelView.focusSearch()
    case .newCollection: panelView.createCollection()
    case .newText: panelView.createTextClip()
    case .nextCollection: viewModel.selectAdjacentCollection(delta: 1)
    case .open: viewModel.openSelected()
    case .pastePlainText: viewModel.pasteSelectedPlainText()
    case .preview: previewSelected()
    case .previousCollection: viewModel.selectAdjacentCollection(delta: -1)
    case .rename: panelView.renameSelectedClip()
    case .reveal: viewModel.revealSelected()
    case .showInClipboard: panelView.showSelectedInClipboard()
    case .toggleCapturePause: toggleCapturePauseFromShortcut()
    case .togglePin: viewModel.togglePinSelected()
    case .undoDelete: viewModel.undoLastDelete()
    }
  }

  private func toggleCapturePauseFromShortcut() {
    settings.pauseCaptureUntil = nil
    if settings.pauseCapture {
      settings.pauseCapture = false
      settings.setCaptureStatus(message: "Capture resumed.")
    } else {
      settings.pauseCapture = true
      settings.setCaptureStatus(message: "Capture is paused.")
    }
  }

  private func previewSelected() {
    guard panel.attachedSheet == nil, !panelView.hasActiveTextEditor else { return }
    isPresentingPreview = true
    defer { isPresentingPreview = false }
    dismissPreviews()
    if let request = viewModel.linkPreviewRequestForSelected() {
      let controller = LinkPreviewWindowController()
      linkPreviewController = controller
      configurePreviewLifecycle(controller)
      controller.show(request, relativeTo: panel)
      return
    }
    guard let url = viewModel.previewURLForSelected(), let item = viewModel.selectedItem else {
      viewModel.reportPreviewUnavailable()
      return
    }
    let controller = ClipboardPreviewWindowController(url: url, title: ClipboardItemCardContentFormatter().titleText(for: item))
    filePreviewController = controller
    configurePreviewLifecycle(controller)
    controller.present(relativeTo: panel)
  }

  private func configurePreviewLifecycle(_ controller: ClipboardAuxiliaryWindowController) {
    controller.onClose = { [weak self] in
      guard let self, self.isVisible, !self.isDismissingPreviews else { return }
      self.panel.makeKeyAndOrderFront(nil)
      self.panelView.focusSelectedCardForKeyboardNavigation()
    }
    controller.onResignKey = { [weak self] in self?.dismissIfFocusLeftShelf() }
  }

  private func dismissPreviews() {
    isDismissingPreviews = true
    filePreviewController?.close()
    linkPreviewController?.close()
    filePreviewController = nil
    linkPreviewController = nil
    isDismissingPreviews = false
  }

  private func shouldHandlePanelKeyEvent(_ event: NSEvent) -> Bool { shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: false) }

  private func shouldHandlePanelKeyEvent(_ event: NSEvent, allowSearchFieldEditing: Bool) -> Bool {
    guard panel.attachedSheet == nil, !panelView.hasActiveTextEditor else { return false }
    if panel.firstResponder is ShelfFilterButton, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
      [36, 49, 125, 126].contains(event.keyCode)
    {
      return false
    }
    if !allowSearchFieldEditing, self.panelView.isSearchFieldEditing { return false }

    guard let keyWindow = NSApp.keyWindow, keyWindow == panel else { return false }

    // If a key event belongs to this panel while it has lost key status temporarily
    // during opening/animations, still allow keyboard shortcuts.
    return event.windowNumber == panel.windowNumber || NSApp.window(withWindowNumber: event.windowNumber) === panel
  }

  static func quickPasteIndex(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == .command else { return nil }
    return quickPasteKeyCodes[keyCode]
  }

  static func navigationShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelNavigationAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    if relevantModifiers == .command {
      switch keyCode {
      case 126: return .first
      case 125: return .last
      default: return nil
      }
    }
    guard relevantModifiers.isEmpty else { return nil }
    switch keyCode {
    case 115: return .first
    case 119: return .last
    case 124: return .next
    case 121: return .pageNext
    case 116: return .pagePrevious
    case 123: return .previous
    default: return nil
    }
  }

  static func selectionShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelSelectionAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    if relevantModifiers == .command { return keyCode == 0 ? .selectAll : nil }
    guard relevantModifiers == .shift else { return nil }
    switch keyCode {
    case 115: return .extendFirst
    case 119: return .extendLast
    case 124: return .extendNext
    case 121: return .extendPageNext
    case 116: return .extendPagePrevious
    case 123: return .extendPrevious
    default: return nil
    }
  }

  static func quickPastePlainTextIndex(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == [.command, .shift] else { return nil }
    return quickPasteKeyCodes[keyCode]
  }

  static func collectionShortcutMode(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardSortMode? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == [.command, .option] else { return nil }
    return collectionShortcuts[keyCode]
  }

  static func searchFieldPreviewShortcut(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags, searchText: String) -> Bool {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    return keyCode == 49 && relevantModifiers.isEmpty && searchText.clipboardTrimmed.isEmpty
  }

  static func matchesShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, binding: ShortcutBinding) -> Bool {
    guard ShortcutManager.virtualKeyCode(for: binding.key) == keyCode else { return false }
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    let bindingModifiers = NSEvent.ModifierFlags(rawValue: binding.modifierFlags).intersection(.deviceIndependentFlagsMask)
    return relevantModifiers == bindingModifiers
  }

  static func commandShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelShortcutAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == .command else { return nil }
    switch keyCode {
    case 13: return .close
    case 8: return .copy
    case 3: return .focusSearch
    case 14: return .edit
    case 45: return .newText
    case 35: return .togglePin
    case 31: return .open
    case 5: return .showInClipboard
    case 16: return .preview
    case 15: return .rename
    case 17: return .toggleCapturePause
    case 6: return .undoDelete
    case 123: return .previousCollection
    case 124: return .nextCollection
    default: return nil
    }
  }

  static func modifiedShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelShortcutAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    if relevantModifiers == .shift { return keyCode == 36 ? .pastePlainText : nil }
    guard relevantModifiers == [.command, .shift] else { return nil }
    switch keyCode {
    case 45: return .newCollection
    case 9: return .pastePlainText
    default: return nil
    }
  }

  private func installClickMonitor() {
    removeClickMonitor()
    guard isVisible else { return }
    let panelWindowNumber = panel.windowNumber
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self else { return }
      guard self.isVisible else { return }
      guard self.panel.attachedSheet == nil else { return }
      // The status button owns this click. Dismissing here would make its
      // toggle action see a hidden shelf and immediately reopen it.
      guard !self.isPrimaryStatusItemClick(event) else { return }

      if event.windowNumber == panelWindowNumber { return }

      if NSApp.window(withWindowNumber: event.windowNumber) === self.panel { return }

      let point = NSEvent.mouseLocation
      let ownedWindows = [
        self.panel, self.filePreviewController?.window, self.linkPreviewController?.window, self.panelView.presentedMenuWindow,
        self.panelView.presentedTextEditorWindow,
      ]
      if !ownedWindows.contains(where: { $0?.isVisible == true && $0?.frame.contains(point) == true }) {
        self.dismissForOutsideInteraction()
      }
    }
  }

  private func reflowPanelForScreenChange() {
    guard isVisible else { return }
    guard !isAnimating else { return }
    let point = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    guard
      let screen = Self.selectedReflowScreen(
        currentPanel: panel.screen, lastKnown: screen(matchingFrame: activeScreenSnapshot?.screenFrame),
        preferred: preferredScreenProvider(), pointer: pointerScreen, fallback: NSScreen.screens.first)
    else { return }

    activeScreenSnapshot = (screen.frame, screen.visibleFrame)
    let plan = Self.reflowPlan(
      forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame, side: settings.panelSide,
      preferredWidth: CGFloat(settings.shelfWidth.rawValue), layout: settings.shelfLayout, largerText: settings.largerShelfText)
    panelView.setBottomSafeInset(plan.bottomSafeInset)

    isAnimating = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.duration(Animation.reflowDuration)
      context.allowsImplicitAnimation = true
      context.timingFunction = CAMediaTimingFunction(name: Animation.easing)
      panel.animator().setFrame(plan.frame, display: true)
    } completionHandler: { [weak self] in
      self?.isAnimating = false
      self?.installClickMonitor()
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func activeScreenFrames() -> (screenFrame: CGRect, visibleFrame: CGRect) {
    let pointer = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) {
      return (screen.frame, screen.visibleFrame)
    }

    let fallback = preferredScreen() ?? NSScreen.screens.first
    return (fallback?.frame ?? .zero, fallback?.visibleFrame ?? .zero)
  }

  private func screen(matchingFrame frame: CGRect?) -> NSScreen? {
    guard let frame else { return nil }
    return NSScreen.screens.first { $0.frame == frame }
  }
}

private final class KeyablePanel: NSPanel {
  var onPointerMoved: ((NSPoint) -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func sendEvent(_ event: NSEvent) {
    super.sendEvent(event)
    if event.type == .mouseMoved { onPointerMoved?(event.locationInWindow) }
  }
}
