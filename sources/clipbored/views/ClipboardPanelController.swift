import AppKit
import QuickLookUI

struct ClipboardPanelAnimationProfile {
  let showDuration: TimeInterval
  let hideDuration: TimeInterval
  let reflowDuration: TimeInterval
  let easing: CAMediaTimingFunctionName
}

struct ClipboardPanelReflowPlan {
  let frame: NSRect
  let bottomSafeInset: CGFloat
}

enum ClipboardPanelShortcutAction: Equatable {
  case copy
  case copyPlainText
  case edit
  case focusSearch
  case newCollection
  case nextCollection
  case open
  case pastePlainText
  case pasteStackNext
  case preview
  case previousCollection
  case rename
  case reveal
  case showInClipboard
  case toggleCapturePause
  case toggleStack
  case toggleStackCapture
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

final class ClipboardPanelController: NSObject, NSWindowDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  private enum Animation {
    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.16
    static let reflowDuration: TimeInterval = 0.18
    static let easing: CAMediaTimingFunctionName = .easeInEaseOut

    static func duration(_ preferredDuration: TimeInterval) -> TimeInterval {
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : preferredDuration
    }
  }
  private enum Metrics {
    static let preferredVerticalShelfWidth: CGFloat = 336
    static let minimumVerticalShelfWidth: CGFloat = 320
    static let maximumVerticalShelfWidthRatio: CGFloat = 0.30
    static let minimumBottomInset: CGFloat = 18
    static let maximumBottomInset: CGFloat = 20
    static let hiddenDockRevealInsetLimit: CGFloat = 8
  }

  private var panel: NSPanel!
  private var panelView: ClipboardPanelView!
  private let settings: SettingsModel
  private(set) var isVisible = false
  private var clickMonitor: Any?
  private var keyMonitor: Any?
  private var targetApplication: NSRunningApplication?
  private var activeScreenSnapshot: (screenFrame: CGRect, visibleFrame: CGRect)?
  private let pollClipboardNow: () -> Void
  private let preferredScreenProvider: () -> NSScreen?
  private let openSettings: () -> Void
  private var isAnimating = false
  private var quickLookURL: URL?
  private var linkPreviewController: LinkPreviewWindowController?
  private var screenParametersObserver: NSObjectProtocol?
  private static let quickPasteKeyCodes: [UInt16: Int] = [
    18: 0,
    19: 1,
    20: 2,
    21: 3,
    23: 4,
    22: 5,
    26: 6,
    28: 7,
    25: 8
  ]
  private static let collectionShortcuts: [UInt16: ClipboardSortMode] = [
    18: .mostRecent,
    19: .mostUsed,
    20: .text,
    21: .links,
    23: .images,
    22: .files,
    26: .pinned,
    28: .audio,
    25: .colors,
    29: .code
  ]

  private let viewModel: ClipboardPanelViewModel

  init(
    store: ClipboardStore,
    settings: SettingsModel,
    cacheService: ClipboardCacheService,
    preferredScreen: @escaping () -> NSScreen? = { nil },
    pollClipboardNow: @escaping () -> Void = {},
    openSettings: @escaping () -> Void = {}
  ) {
    self.settings = settings
    self.viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    self.pollClipboardNow = pollClipboardNow
    self.openSettings = openSettings
    self.preferredScreenProvider = preferredScreen
    super.init()

    viewModel.targetApplicationProvider = { [weak self] in
      self?.targetApplication
    }
    viewModel.willPasteToTarget = { [weak self] in
      self?.hide(immediate: true)
    }

    panelView = ClipboardPanelView(
      viewModel: viewModel,
      onClose: { [weak self] in self?.hide() },
      onSettings: { [weak self] in self?.openSettings() },
      onPreview: { [weak self] in self?.previewSelected() }
    )

    let contentSize = NSSize(width: 336, height: 760)
    panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
      styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.contentView = panelView
    panel.hasShadow = false
    panel.level = .statusBar
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = true
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
      guard change == .hideFromScreenCapture || change == .panelSide else { return }
      DispatchQueue.main.async {
        if change == .hideFromScreenCapture {
          self?.applyPanelSharingSetting()
        } else {
          self?.reflowPanelForScreenChange()
        }
      }
    }

    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reflowPanelForScreenChange()
    }
  }

  deinit {
    removeClickMonitor()
    removeKeyMonitor()
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
  }

  func toggle(preferredScreen explicitScreen: NSScreen? = nil) {
    if isVisible {
      hide()
    } else {
      show(preferredScreen: explicitScreen)
    }
  }

  func createCollection() {
    performWhenVisible { [weak self] in
      guard let self else { return }
      self.panelView.createCollection()
    }
  }

  func toggleStackCaptureMode() {
    viewModel.toggleStackCaptureMode()
  }

  func addCapturedItemToStack(_ item: ClipboardItem) {
    viewModel.addCapturedItemToStack(item)
  }

  func show(preferredScreen explicitScreen: NSScreen? = nil) {
    if isVisible || isAnimating { return }
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
      forScreenFrame: screen.frame,
      visibleFrame: screen.visibleFrame,
      side: settings.panelSide
    )
    panelView.setBottomSafeInset(Self.contentBottomInset(forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame))
    panel.setFrame(frames.hidden, display: false)
    panel.alphaValue = 0.0
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panelView.prepareForShow()
    viewModel.selectFirstItem()
    panelView.beginOpeningTransition()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.duration(Animation.showDuration)
      context.allowsImplicitAnimation = true
      context.timingFunction = CAMediaTimingFunction(name: Animation.easing)
      panel.animator().setFrame(frames.shown, display: true)
      panel.animator().alphaValue = 1.0
    } completionHandler: { [weak self] in
      guard let self else { return }
      self.isAnimating = false
      self.panelView.finishOpeningTransition()
      guard self.isVisible else { return }
      self.installClickMonitor()
      self.panelView.focusSelectedCardForKeyboardNavigation()
    }

    installKeyMonitor()
  }

  func hide() {
    hide(immediate: false)
  }

  func hide(immediate: Bool) {
    guard isVisible || isAnimating else { return }
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
      forScreenFrame: screenFrames.screenFrame,
      visibleFrame: screenFrames.visibleFrame,
      side: settings.panelSide
    ).hidden
    isAnimating = true

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.duration(Animation.hideDuration)
      context.allowsImplicitAnimation = true
      context.timingFunction = CAMediaTimingFunction(name: Animation.easing)
      panel.animator().alphaValue = 0.0
      panel.animator().setFrame(hidden, display: true)
    } completionHandler: { [weak self] in
      self?.panel.orderOut(nil)
      self?.panel.alphaValue = 1.0
      self?.isVisible = false
      self?.isAnimating = false
      self?.activeScreenSnapshot = nil
      self?.panelView.finishOpeningTransition()
      self?.removeClickMonitor()
      self?.removeKeyMonitor()
    }
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
    hide()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    panelView.focusSelectedCardForKeyboardNavigation()
  }

  private func preferredScreen(explicitScreen: NSScreen? = nil) -> NSScreen? {
    let point = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    return Self.selectedOpenScreen(
      explicit: explicitScreen,
      preferred: preferredScreenProvider(),
      pointer: pointerScreen,
      fallback: NSScreen.screens.first
    )
  }

  static func selectedOpenScreen<Screen>(
    explicit: Screen?,
    preferred: Screen?,
    pointer: Screen?,
    fallback: Screen?
  ) -> Screen? {
    explicit ?? preferred ?? pointer ?? fallback
  }

  static func selectedReflowScreen<Screen>(
    currentPanel: Screen?,
    lastKnown: Screen?,
    preferred: Screen?,
    pointer: Screen?,
    fallback: Screen?
  ) -> Screen? {
    currentPanel ?? lastKnown ?? preferred ?? pointer ?? fallback
  }

  static func panelFrames(forScreenFrame screenFrame: CGRect) -> (shown: NSRect, hidden: NSRect) {
    return panelFrames(forScreenFrame: screenFrame, visibleFrame: screenFrame)
  }

  static func panelFrames(
    forScreenFrame screenFrame: CGRect,
    visibleFrame: CGRect,
    side: ClipboardPanelSide = .right
  ) -> (shown: NSRect, hidden: NSRect) {
    let intersectedFrame = visibleFrame.intersection(screenFrame)
    let effectiveFrame = intersectedFrame.width > 0 && intersectedFrame.height > 0 ? intersectedFrame : screenFrame
    return verticalPanelFrames(forScreenFrame: screenFrame, effectiveFrame: effectiveFrame, side: side)
  }

  private static func verticalPanelFrames(
    forScreenFrame screenFrame: CGRect,
    effectiveFrame: CGRect,
    side: ClipboardPanelSide
  ) -> (shown: NSRect, hidden: NSRect) {
    let targetWidth = panelWidth(within: max(1, effectiveFrame.width))
    let targetHeight = max(1, floor(effectiveFrame.maxY - screenFrame.minY))
    let shownX: CGFloat
    let hiddenX: CGFloat
    switch side {
    case .left:
      shownX = effectiveFrame.minX
      hiddenX = shownX - targetWidth - 1
    case .right:
      shownX = effectiveFrame.maxX - targetWidth
      hiddenX = effectiveFrame.maxX + 1
    }
    let shown = NSRect(
      x: shownX,
      y: screenFrame.minY,
      width: targetWidth,
      height: targetHeight
    )
    let hidden = NSRect(
      x: hiddenX,
      y: shown.minY,
      width: shown.width,
      height: targetHeight
    )
    return (shown, hidden)
  }

  private static func panelWidth(within visibleWidth: CGFloat) -> CGFloat {
    let available = max(1, visibleWidth)
    let preferred = min(Metrics.preferredVerticalShelfWidth, floor(available * Metrics.maximumVerticalShelfWidthRatio))
    return min(available, max(Metrics.minimumVerticalShelfWidth, preferred))
  }

  static func contentBottomInset(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
    let dockInset = visibleBottomDockInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
    return max(Metrics.minimumBottomInset, min(Metrics.maximumBottomInset, dockInset + 2))
  }

  private static func visibleBottomDockInset(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
    let inset = max(0, visibleFrame.minY - screenFrame.minY)
    return inset > Metrics.hiddenDockRevealInsetLimit ? inset : 0
  }

  static var animationProfile: ClipboardPanelAnimationProfile {
    ClipboardPanelAnimationProfile(
      showDuration: Animation.showDuration,
      hideDuration: Animation.hideDuration,
      reflowDuration: Animation.reflowDuration,
      easing: Animation.easing
    )
  }

  static var panelCollectionBehavior: NSWindow.CollectionBehavior {
    [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
  }

  static func reflowPlan(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> ClipboardPanelReflowPlan {
    let frames = panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
    return ClipboardPanelReflowPlan(
      frame: frames.shown,
      bottomSafeInset: contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
    )
  }

  static func reflowPlan(
    forScreenFrame screenFrame: CGRect,
    visibleFrame: CGRect,
    side: ClipboardPanelSide = .right
  ) -> ClipboardPanelReflowPlan {
    let frames = panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      side: side
    )
    return ClipboardPanelReflowPlan(
      frame: frames.shown,
      bottomSafeInset: contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
    )
  }

  static func panelSharingType(hideFromScreenCapture: Bool) -> NSWindow.SharingType {
    hideFromScreenCapture ? .none : .readOnly
  }

  private func applyPanelSharingSetting() {
    panel.sharingType = Self.panelSharingType(hideFromScreenCapture: settings.hideFromScreenCapture)
  }

  private func rememberTargetApplication() {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else {
      targetApplication = nil
      return
    }

    if frontmost.processIdentifier == NSRunningApplication.current.processIdentifier {
      targetApplication = nil
      return
    }

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
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         self.panelView.isSearchFieldEditing,
         Self.searchFieldPreviewShortcut(
           forKeyCode: event.keyCode,
           modifiers: event.modifierFlags,
           searchText: self.panelView.searchTextForKeyboardShortcut
         ) {
        self.previewSelected()
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         let index = Self.quickPasteIndex(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.viewModel.pasteItem(at: index)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         let index = Self.quickPastePlainTextIndex(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.viewModel.pasteItemPlainText(at: index)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         let mode = Self.collectionShortcutMode(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.viewModel.sortMode = mode
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         Self.matchesShortcut(
           keyCode: event.keyCode,
           modifiers: event.modifierFlags,
           binding: self.settings.settingsShortcut
         ) {
        self.openSettings()
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         let action = Self.commandShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.performShortcutAction(action)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         let action = Self.modifiedShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.performShortcutAction(action)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event),
         let action = Self.selectionShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
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
        if !self.panelView.clearSearchForKeyboardCancel() {
          self.hide()
        }
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
      case 35:
        self.viewModel.togglePinSelected()
        return nil
      default:
        return event
      }
    }
  }

  private func performNavigationAction(_ action: ClipboardPanelNavigationAction) {
    switch action {
    case .first:
      viewModel.selectFirstItem()
    case .last:
      viewModel.selectLastItem()
    case .next:
      viewModel.moveSelection(1)
    case .pageNext:
      viewModel.moveSelection(panelView.visibleCardPageStep)
    case .pagePrevious:
      viewModel.moveSelection(-panelView.visibleCardPageStep)
    case .previous:
      viewModel.moveSelection(-1)
    }
    panelView.focusSelectedCardForKeyboardNavigation()
  }

  private func performSelectionAction(_ action: ClipboardPanelSelectionAction) {
    switch action {
    case .extendFirst:
      viewModel.selectItem(at: 0, mode: .range)
    case .extendLast:
      viewModel.selectItem(at: viewModel.visibleItems.count - 1, mode: .range)
    case .extendNext:
      extendSelection(by: 1)
    case .extendPageNext:
      extendSelection(by: panelView.visibleCardPageStep)
    case .extendPagePrevious:
      extendSelection(by: -panelView.visibleCardPageStep)
    case .extendPrevious:
      extendSelection(by: -1)
    case .selectAll:
      viewModel.selectAllVisibleItems()
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
    case .copy:
      viewModel.copySelected()
    case .copyPlainText:
      viewModel.copySelectedPlainText()
    case .edit:
      panelView.editSelectedClip()
    case .focusSearch:
      panelView.focusSearch()
    case .newCollection:
      panelView.createCollection()
    case .nextCollection:
      viewModel.selectAdjacentCollection(delta: 1)
    case .open:
      viewModel.openSelected()
    case .pastePlainText:
      viewModel.pasteSelectedPlainText()
    case .pasteStackNext:
      viewModel.pasteNextStackItem()
    case .preview:
      previewSelected()
    case .previousCollection:
      viewModel.selectAdjacentCollection(delta: -1)
    case .rename:
      panelView.renameSelectedClip()
    case .reveal:
      viewModel.revealSelected()
    case .showInClipboard:
      panelView.showSelectedInClipboard()
    case .toggleCapturePause:
      toggleCapturePauseFromShortcut()
    case .toggleStack:
      viewModel.toggleSelectedStackMembership()
    case .toggleStackCapture:
      viewModel.toggleStackCaptureMode()
    case .undoDelete:
      viewModel.undoLastDelete()
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
    if let request = viewModel.linkPreviewRequestForSelected() {
      quickLookURL = nil
      QLPreviewPanel.shared()?.orderOut(nil)
      showLinkPreview(request)
      return
    }

    guard let url = viewModel.previewURLForSelected() else { return }
    linkPreviewController?.close()
    quickLookURL = url
    guard let previewPanel = QLPreviewPanel.shared() else {
      NSWorkspace.shared.open(url)
      return
    }
    previewPanel.dataSource = self
    previewPanel.delegate = self
    previewPanel.currentPreviewItemIndex = 0
    previewPanel.makeKeyAndOrderFront(nil)
  }

  private func showLinkPreview(_ request: LinkPreviewRequest) {
    let controller = linkPreviewController ?? LinkPreviewWindowController()
    linkPreviewController = controller
    controller.show(request, relativeTo: panel)
  }

  private func shouldHandlePanelKeyEvent(_ event: NSEvent) -> Bool {
    shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: false)
  }

  private func shouldHandlePanelKeyEvent(_ event: NSEvent, allowSearchFieldEditing: Bool) -> Bool {
    if !allowSearchFieldEditing, self.panelView.isSearchFieldEditing {
      return false
    }

    guard let keyWindow = NSApp.keyWindow,
          keyWindow == panel else {
      return false
    }

    // If a key event belongs to this panel while it has lost key status temporarily
    // during opening/animations, still allow keyboard shortcuts.
    return event.windowNumber == panel.windowNumber
      || NSApp.window(withWindowNumber: event.windowNumber) === panel
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
    if relevantModifiers == .command {
      return keyCode == 0 ? .selectAll : nil
    }
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

  static func matchesShortcut(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    binding: ShortcutBinding
  ) -> Bool {
    guard ShortcutManager.virtualKeyCode(for: binding.key) == keyCode else { return false }
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    let bindingModifiers = NSEvent.ModifierFlags(rawValue: binding.modifierFlags)
      .intersection(.deviceIndependentFlagsMask)
    return relevantModifiers == bindingModifiers
  }

  static func commandShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelShortcutAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == .command else { return nil }
    switch keyCode {
    case 8:
      return .copy
    case 3:
      return .focusSearch
    case 14:
      return .edit
    case 31:
      return .open
    case 5:
      return .showInClipboard
    case 16:
      return .preview
    case 15:
      return .rename
    case 17:
      return .toggleCapturePause
    case 6:
      return .undoDelete
    case 123:
      return .previousCollection
    case 124:
      return .nextCollection
    default:
      return nil
    }
  }

  static func modifiedShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelShortcutAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    if relevantModifiers == .shift {
      return keyCode == 36 ? .pastePlainText : nil
    }
    guard relevantModifiers == [.command, .shift] else { return nil }
    switch keyCode {
    case 1:
      return .toggleStack
    case 8:
      return .toggleStackCapture
    case 45:
      return .newCollection
    case 9:
      return .pastePlainText
    case 36:
      return .pasteStackNext
    default:
      return nil
    }
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    quickLookURL == nil ? 0 : 1
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    quickLookURL as NSURL?
  }

  #if DEBUG
  var debugPanelFrame: NSRect {
    panel.frame
  }

  var debugPanelAlpha: CGFloat {
    panel.alphaValue
  }

  var debugIsAnimating: Bool {
    isAnimating
  }

  func debugSetSearchFieldText(_ text: String) {
    panelView.debugSetSearchFieldText(text)
  }

  var debugSearchFieldText: String {
    panelView.debugSearchFieldText
  }

  var debugSearchFieldWidth: CGFloat {
    panelView.debugSearchFieldWidth
  }

  var debugSearchFieldPlaceholderText: String {
    panelView.debugSearchFieldPlaceholderText
  }

  var debugSearchFieldIsVisible: Bool {
    panelView.debugSearchFieldIsVisible
  }

  var debugSearchIconButtonIsVisible: Bool {
    panelView.debugSearchIconButtonIsVisible
  }

  var debugIsSearchFieldEditing: Bool {
    panelView.isSearchFieldEditing
  }
  #endif

  private func installClickMonitor() {
    removeClickMonitor()
    guard isVisible else { return }
    let panelWindowNumber = panel.windowNumber
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self else { return }
      guard self.isVisible else { return }

      if event.windowNumber == panelWindowNumber {
        return
      }

      if NSApp.window(withWindowNumber: event.windowNumber) === self.panel {
        return
      }

      let point = NSEvent.mouseLocation
      if !self.panel.frame.contains(point) {
        self.hide()
      }
    }
  }

  private func reflowPanelForScreenChange() {
    guard isVisible else { return }
    guard !isAnimating else { return }
    let point = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    guard let screen = Self.selectedReflowScreen(
      currentPanel: panel.screen,
      lastKnown: screen(matchingFrame: activeScreenSnapshot?.screenFrame),
      preferred: preferredScreenProvider(),
      pointer: pointerScreen,
      fallback: NSScreen.screens.first
    ) else { return }

    activeScreenSnapshot = (screen.frame, screen.visibleFrame)
    let plan = Self.reflowPlan(
      forScreenFrame: screen.frame,
      visibleFrame: screen.visibleFrame,
      side: settings.panelSide
    )
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
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private extension CGRect {
  var center: NSPoint {
    NSPoint(x: midX, y: midY)
  }
}
