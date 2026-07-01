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
  case newCollection
  case open
  case pastePlainText
  case pasteStackNext
  case preview
  case reveal
  case showInClipboard
  case toggleStack
}

enum ClipboardPanelNavigationAction: Equatable {
  case first
  case last
  case next
  case pageNext
  case pagePrevious
  case previous
}

final class ClipboardPanelController: NSObject, NSWindowDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  private enum Animation {
    static let showDuration: TimeInterval = 0.16
    static let hideDuration: TimeInterval = 0.12
    static let reflowDuration: TimeInterval = 0.10
    static let easing: CAMediaTimingFunctionName = .easeInEaseOut
  }
  private enum Metrics {
    static let shelfHeightRatio: CGFloat = 0.42
    static let minimumShelfHeight: CGFloat = 408
    static let maximumShelfHeight: CGFloat = 430
    static let minimumBottomInset: CGFloat = 18
    static let maximumBottomInset: CGFloat = 20
  }

  private var panel: NSPanel!
  private var panelView: ClipboardPanelView!
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
    25: .colors
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

    let contentSize = NSSize(width: 1200, height: 420)
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
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.becomesKeyOnlyIfNeeded = false
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.standardWindowButton(.closeButton)?.isHidden = true

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

  func toggle() {
    if isVisible {
      hide()
    } else {
      show()
    }
  }

  func show() {
    if isVisible || isAnimating { return }
    isAnimating = true
    isVisible = true

    rememberTargetApplication()
    pollClipboardNow()

    guard let screen = preferredScreen() else {
      isVisible = false
      isAnimating = false
      return
    }
    activeScreenSnapshot = (screen.frame, screen.visibleFrame)
    let frames = Self.panelFrames(
      forScreenFrame: screen.frame,
      visibleFrame: screen.visibleFrame
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
      context.duration = Animation.showDuration
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
      self.panelView.focusSearchField()
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
      visibleFrame: screenFrames.visibleFrame
    ).hidden
    isAnimating = true

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.hideDuration
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

  func windowDidResignKey(_ notification: Notification) {
    hide()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    panelView.focusSearchField()
  }

  private func preferredScreen() -> NSScreen? {
    if let menuBarScreen = preferredScreenProvider() {
      return menuBarScreen
    }

    let point = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.screens.first
  }

  static func panelFrames(forScreenFrame screenFrame: CGRect) -> (shown: NSRect, hidden: NSRect) {
    return panelFrames(forScreenFrame: screenFrame, visibleFrame: screenFrame)
  }

  static func panelFrames(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> (shown: NSRect, hidden: NSRect) {
    let intersectedFrame = visibleFrame.intersection(screenFrame)
    let effectiveFrame = intersectedFrame.width > 0 && intersectedFrame.height > 0 ? intersectedFrame : screenFrame
    let frameHeight = effectiveFrame.height > 0 ? effectiveFrame.height : max(1, screenFrame.height)
    let height = panelHeight(within: frameHeight)
    let targetWidth = max(1, floor(effectiveFrame.width))
    let shownMinX = effectiveFrame.minX
    let shownMinY = max(screenFrame.minY, visibleFrame.minY)
    let shown = NSRect(
      x: shownMinX,
      y: shownMinY,
      width: targetWidth,
      height: height
    )
    let hidden = NSRect(
      x: shown.minX,
      y: shown.minY - height - 1,
      width: shown.width,
      height: height
    )
    return (shown, hidden)
  }

  private static func panelHeight(within visibleHeight: CGFloat) -> CGFloat {
    let available = max(1, visibleHeight)
    let preferred = floor(available * Metrics.shelfHeightRatio)
    let clamped = min(max(preferred, Metrics.minimumShelfHeight), Metrics.maximumShelfHeight)
    return min(available, clamped)
  }

  static func contentBottomInset(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
    let dockInset = max(0, visibleFrame.minY - screenFrame.minY)
    return max(Metrics.minimumBottomInset, min(Metrics.maximumBottomInset, dockInset + 2))
  }

  static var animationProfile: ClipboardPanelAnimationProfile {
    ClipboardPanelAnimationProfile(
      showDuration: Animation.showDuration,
      hideDuration: Animation.hideDuration,
      reflowDuration: Animation.reflowDuration,
      easing: Animation.easing
    )
  }

  static func reflowPlan(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> ClipboardPanelReflowPlan {
    let frames = panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
    return ClipboardPanelReflowPlan(
      frame: frames.shown,
      bottomSafeInset: contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
    )
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
         let action = Self.commandShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.performShortcutAction(action)
        return nil
      }
      if self.shouldHandlePanelKeyEvent(event, allowSearchFieldEditing: true),
         let action = Self.modifiedShortcutAction(forKeyCode: event.keyCode, modifiers: event.modifierFlags) {
        self.performShortcutAction(action)
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

  private func performShortcutAction(_ action: ClipboardPanelShortcutAction) {
    switch action {
    case .copy:
      viewModel.copySelected()
    case .copyPlainText:
      viewModel.copySelectedPlainText()
    case .newCollection:
      panelView.createCollection()
    case .open:
      viewModel.openSelected()
    case .pastePlainText:
      viewModel.pasteSelectedPlainText()
    case .pasteStackNext:
      viewModel.pasteNextStackItem()
    case .preview:
      previewSelected()
    case .reveal:
      viewModel.revealSelected()
    case .showInClipboard:
      panelView.showSelectedInClipboard()
    case .toggleStack:
      viewModel.toggleSelectedStackMembership()
    }
  }

  private func previewSelected() {
    guard let url = viewModel.previewURLForSelected() else { return }
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

  static func commandShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelShortcutAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == .command else { return nil }
    switch keyCode {
    case 8:
      return .copy
    case 31:
      return .open
    case 5:
      return .showInClipboard
    case 16:
      return .preview
    case 15:
      return .reveal
    default:
      return nil
    }
  }

  static func modifiedShortcutAction(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ClipboardPanelShortcutAction? {
    let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    guard relevantModifiers == [.command, .shift] else { return nil }
    switch keyCode {
    case 1:
      return .toggleStack
    case 8:
      return .copyPlainText
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
    guard let screen = preferredScreen() ?? panel.screen ?? NSScreen.screens.first else { return }

    activeScreenSnapshot = (screen.frame, screen.visibleFrame)
    let plan = Self.reflowPlan(forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    panelView.setBottomSafeInset(plan.bottomSafeInset)

    isAnimating = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Animation.reflowDuration
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
