import AppKit
import QuickLookUI

// MARK: - ShelfController

final class ShelfController: NSObject, NSWindowDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  enum Animation {
    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.16
    static let reflowDuration: TimeInterval = 0.18

    static func duration(_ preferredDuration: TimeInterval) -> TimeInterval {
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : preferredDuration
    }
  }

  enum Metrics {
    static let preferredVerticalShelfWidth: CGFloat = 336
    static let minimumVerticalShelfWidth: CGFloat = 320
    static let maximumVerticalShelfWidthRatio: CGFloat = 0.30
    static let minimumBottomInset: CGFloat = 18
    static let maximumBottomInset: CGFloat = 20
    static let hiddenDockRevealInsetLimit: CGFloat = 8
  }

  var panel: NSPanel!
  var panelView: ShelfView!
  let settings: Preferences
  var isVisible = false
  private var clickMonitor: Any?
  var keyMonitor: Any?
  private var targetApplication: NSRunningApplication?
  var activeScreenSnapshot: (screenFrame: CGRect, visibleFrame: CGRect)?
  private let pollClipboardNow: () -> Void
  let preferredScreenProvider: () -> NSScreen?
  let openSettings: () -> Void
  var isAnimating = false
  var quickLookURL: URL?
  var linkPreviewController: LinkPreviewController?
  private var screenParametersObserver: NSObjectProtocol?
  let viewModel: ShelfModel

  init(
    store: HistoryStore, settings: Preferences, cacheService: MediaCache,
    preferredScreen: @escaping () -> NSScreen? = { nil }, pollClipboardNow: @escaping () -> Void = {},
    openSettings: @escaping () -> Void = {}
  ) {
    self.settings = settings
    self.viewModel = ShelfModel(store: store, settings: settings, cacheService: cacheService)
    self.pollClipboardNow = pollClipboardNow
    self.openSettings = openSettings
    self.preferredScreenProvider = preferredScreen
    super.init()

    viewModel.targetApplicationProvider = { [weak self] in self?.targetApplication }
    viewModel.willPasteToTarget = { [weak self] in self?.hide(immediate: true) }

    panelView = ShelfView(
      viewModel: viewModel, onClose: { [weak self] in self?.hide() },
      onSettings: { [weak self] in self?.openSettings() }, onPreview: { [weak self] in self?.previewSelected() })

    panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: 336, height: 760), styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
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
    [NSWindow.ButtonType.miniaturizeButton, .zoomButton, .closeButton].forEach {
      panel.standardWindowButton($0)?.isHidden = true
    }
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
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.reflowPanelForScreenChange() }
  }

  deinit {
    removeClickMonitor()
    removeKeyMonitor()
    if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
  }

  func toggle(preferredScreen explicitScreen: NSScreen? = nil) {
    if isVisible { hide() } else { show(preferredScreen: explicitScreen) }
  }

  func createCollection() { performWhenVisible { [weak self] in self?.panelView.createCollection() } }

  func toggleStackCaptureMode() { viewModel.toggleStackCaptureMode() }

  func addCapturedItemToStack(_ item: Clip) { viewModel.addCapturedItemToStack(item) }

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
      forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame, side: settings.panelSide)
    panelView.setBottomSafeInset(
      Self.contentBottomInset(forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame))
    panel.setFrame(frames.hidden, display: false)
    panel.alphaValue = 0.0
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panelView.prepareForShow()
    viewModel.selectFirstItem()
    panelView.beginOpeningTransition()

    UI.animate(
      Animation.showDuration,
      changes: {
        panel.animator().setFrame(frames.shown, display: true)
        panel.animator().alphaValue = 1.0
      },
      completion: { [weak self] in
        guard let self else { return }
        self.isAnimating = false
        self.panelView.finishOpeningTransition()
        guard self.isVisible else { return }
        self.installClickMonitor()
        self.panelView.focusSelectedCardForKeyboardNavigation()
      })

    installKeyMonitor()
  }

  func hide() { hide(immediate: false) }

  func hide(immediate: Bool) {
    guard isVisible || isAnimating else { return }
    if immediate {
      finishHiding()
      return
    }

    let screenFrames = activeScreenSnapshot ?? activeScreenFrames()
    let hidden = Self.panelFrames(
      forScreenFrame: screenFrames.screenFrame, visibleFrame: screenFrames.visibleFrame, side: settings.panelSide
    ).hidden
    isAnimating = true

    UI.animate(
      Animation.hideDuration,
      changes: {
        panel.animator().alphaValue = 0.0
        panel.animator().setFrame(hidden, display: true)
      }, completion: { [weak self] in self?.finishHiding() })
  }

  private func finishHiding() {
    panel.orderOut(nil)
    panel.alphaValue = 1
    isVisible = false
    isAnimating = false
    activeScreenSnapshot = nil
    panelView.finishOpeningTransition()
    removeClickMonitor()
    removeKeyMonitor()
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

  func windowDidResignKey(_ notification: Notification) { hide() }

  func windowDidBecomeKey(_ notification: Notification) { panelView.focusSelectedCardForKeyboardNavigation() }

  private func rememberTargetApplication() {
    let frontmost = NSWorkspace.shared.frontmostApplication
    let ownPID = NSRunningApplication.current.processIdentifier
    targetApplication = frontmost?.processIdentifier == ownPID ? nil : frontmost
  }

  private func removeClickMonitor() {
    if let clickMonitor {
      NSEvent.removeMonitor(clickMonitor)
      self.clickMonitor = nil
    }
  }

  func installClickMonitor() {
    removeClickMonitor()
    guard isVisible else { return }
    let panelWindowNumber = panel.windowNumber
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self, self.isVisible, event.windowNumber != panelWindowNumber,
        NSApp.window(withWindowNumber: event.windowNumber) !== self.panel,
        !self.panel.frame.contains(NSEvent.mouseLocation)
      else { return }
      self.hide()
    }
  }
}

// MARK: - PanelControllerTypes

struct ClipboardPanelReflowPlan {
  let frame: NSRect
  let bottomSafeInset: CGFloat
}

enum ClipboardPanelShortcutAction: Equatable {
  case copy, copyPlainText, edit, focusSearch, newCollection, nextCollection, open, pastePlainText, pasteStackNext
  case preview, previousCollection, rename, reveal, showInClipboard, toggleCapturePause, toggleStack,
    toggleStackCapture, undoDelete
}

// Pure keyboard policy; the controller only executes the resolved intent.
enum ShelfKeyboard {
  enum Movement: Equatable { case first, last, next, previous, pageNext, pagePrevious }
  enum Intent: Equatable {
    case paste(Int?, plain: Bool), category(ShelfCategory), command(ClipboardPanelShortcutAction)
    case move(Movement, extending: Bool)
    case settings, selectAll, cancel, preview, delete, pin
  }
  private static let numbers: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
  private static let categories: [UInt16: ShelfCategory] = [
    18: .mostRecent, 19: .mostUsed, 20: .text, 21: .links, 23: .images, 22: .files, 26: .pinned, 28: .audio,
    25: .colors, 29: .code,
  ]
  private static let commands: [UInt: [UInt16: ClipboardPanelShortcutAction]] = [
    NSEvent.ModifierFlags.command.rawValue: [
      8: .copy, 3: .focusSearch, 14: .edit, 31: .open, 5: .showInClipboard, 16: .preview, 15: .rename,
      17: .toggleCapturePause, 6: .undoDelete, 123: .previousCollection, 124: .nextCollection,
    ],
    NSEvent.ModifierFlags([.command, .shift]).rawValue: [
      1: .toggleStack, 8: .toggleStackCapture, 45: .newCollection, 9: .pastePlainText, 36: .pasteStackNext,
    ], NSEvent.ModifierFlags.shift.rawValue: [36: .pastePlainText],
  ]
  private static let movements: [UInt16: Movement] = [
    115: .first, 119: .last, 124: .next, 121: .pageNext, 116: .pagePrevious, 123: .previous,
  ]

  static func resolve(
    keyCode: UInt16, modifiers: NSEvent.ModifierFlags, editingSearch: Bool = false, searchText: String = "",
    settingsShortcut: ShortcutBinding = Configuration.defaultSettingsShortcut
  ) -> Intent? {
    let flags = modifiers.intersection(.deviceIndependentFlagsMask)
    if editingSearch, keyCode == 49, flags.isEmpty, searchText.clipboardTrimmed.isEmpty { return .preview }
    if flags == .command || flags == [.command, .shift], let index = numbers[keyCode] {
      return .paste(index, plain: flags.contains(.shift))
    }
    if flags == [.command, .option], let category = categories[keyCode] { return .category(category) }
    if ShortcutManager.virtualKeyCode(for: settingsShortcut.key) == keyCode,
      flags == NSEvent.ModifierFlags(rawValue: settingsShortcut.modifierFlags).intersection(.deviceIndependentFlagsMask)
    {
      return .settings
    }
    if let command = commands[flags.rawValue]?[keyCode] { return .command(command) }
    guard !editingSearch else { return nil }
    if flags == .command, keyCode == 0 { return .selectAll }
    if flags == .command, keyCode == 126 || keyCode == 125 {
      return .move(keyCode == 126 ? .first : .last, extending: false)
    }
    if flags.isEmpty || flags == .shift, let movement = movements[keyCode] {
      return .move(movement, extending: flags == .shift)
    }
    switch keyCode {
    case 53: return .cancel
    case 49: return .preview
    case 36: return .paste(nil, plain: false)
    case 51, 117: return .delete
    case 35: return .pin
    default: return nil
    }
  }
}

final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

extension CGRect { var center: NSPoint { NSPoint(x: midX, y: midY) } }

// MARK: - ShelfController — Geometry

extension ShelfController {
  func preferredScreen(explicitScreen: NSScreen? = nil) -> NSScreen? {
    let point = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    return Self.selectedOpenScreen(
      explicit: explicitScreen, preferred: preferredScreenProvider(), pointer: pointerScreen,
      fallback: NSScreen.screens.first)
  }

  static func selectedOpenScreen<Screen>(explicit: Screen?, preferred: Screen?, pointer: Screen?, fallback: Screen?)
    -> Screen?
  { explicit ?? preferred ?? pointer ?? fallback }

  static func selectedReflowScreen<Screen>(
    currentPanel: Screen?, lastKnown: Screen?, preferred: Screen?, pointer: Screen?, fallback: Screen?
  ) -> Screen? { currentPanel ?? lastKnown ?? preferred ?? pointer ?? fallback }

  static func panelFrames(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect, side: ClipboardPanelSide = .right)
    -> (shown: NSRect, hidden: NSRect)
  {
    let intersectedFrame = visibleFrame.intersection(screenFrame)
    let effectiveFrame = intersectedFrame.width > 0 && intersectedFrame.height > 0 ? intersectedFrame : screenFrame
    let available = max(1, effectiveFrame.width)
    let width = min(
      available,
      max(
        Metrics.minimumVerticalShelfWidth,
        min(Metrics.preferredVerticalShelfWidth, floor(available * Metrics.maximumVerticalShelfWidthRatio))))
    let shownX = side == .left ? effectiveFrame.minX : effectiveFrame.maxX - width
    let hiddenX = side == .left ? shownX - width - 1 : effectiveFrame.maxX + 1
    let size = NSSize(width: width, height: max(1, floor(effectiveFrame.maxY - screenFrame.minY)))
    return (
      NSRect(origin: NSPoint(x: shownX, y: screenFrame.minY), size: size),
      NSRect(origin: NSPoint(x: hiddenX, y: screenFrame.minY), size: size)
    )
  }

  static func contentBottomInset(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
    let dock = max(0, visibleFrame.minY - screenFrame.minY)
    return max(
      Metrics.minimumBottomInset,
      min(Metrics.maximumBottomInset, (dock > Metrics.hiddenDockRevealInsetLimit ? dock : 0) + 2))
  }

  static var panelCollectionBehavior: NSWindow.CollectionBehavior {
    [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
  }

  static func reflowPlan(forScreenFrame screenFrame: CGRect, visibleFrame: CGRect, side: ClipboardPanelSide = .right)
    -> ClipboardPanelReflowPlan
  {
    let frames = panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame, side: side)
    return ClipboardPanelReflowPlan(
      frame: frames.shown, bottomSafeInset: contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame))
  }

  static func panelSharingType(hideFromScreenCapture: Bool) -> NSWindow.SharingType {
    hideFromScreenCapture ? .none : .readOnly
  }

  func applyPanelSharingSetting() {
    panel.sharingType = Self.panelSharingType(hideFromScreenCapture: settings.hideFromScreenCapture)
  }

  func reflowPanelForScreenChange() {
    guard isVisible, !isAnimating else { return }
    let point = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    guard
      let screen = Self.selectedReflowScreen(
        currentPanel: panel.screen, lastKnown: screen(matchingFrame: activeScreenSnapshot?.screenFrame),
        preferred: preferredScreenProvider(), pointer: pointerScreen, fallback: NSScreen.screens.first)
    else { return }

    activeScreenSnapshot = (screen.frame, screen.visibleFrame)
    let plan = Self.reflowPlan(
      forScreenFrame: screen.frame, visibleFrame: screen.visibleFrame, side: settings.panelSide)
    panelView.setBottomSafeInset(plan.bottomSafeInset)

    isAnimating = true
    UI.animate(
      Animation.reflowDuration, changes: { panel.animator().setFrame(plan.frame, display: true) },
      completion: { [weak self] in
        self?.isAnimating = false
        self?.installClickMonitor()
      })
  }

  func activeScreenFrames() -> (screenFrame: CGRect, visibleFrame: CGRect) {
    let pointer = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) {
      return (screen.frame, screen.visibleFrame)
    }

    let fallback = preferredScreen() ?? NSScreen.screens.first
    return (fallback?.frame ?? .zero, fallback?.visibleFrame ?? .zero)
  }

  func screen(matchingFrame frame: CGRect?) -> NSScreen? {
    guard let frame else { return nil }
    return NSScreen.screens.first { $0.frame == frame }
  }
}

// MARK: - ShelfController — Keyboard

extension ShelfController {
  func installKeyMonitor() {
    removeKeyMonitor()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, NSApp.keyWindow == self.panel,
        event.windowNumber == self.panel.windowNumber
          || NSApp.window(withWindowNumber: event.windowNumber) === self.panel,
        let intent = ShelfKeyboard.resolve(
          keyCode: event.keyCode, modifiers: event.modifierFlags, editingSearch: self.panelView.isSearchFieldEditing,
          searchText: self.panelView.searchTextForKeyboardShortcut, settingsShortcut: self.settings.settingsShortcut)
      else { return event }
      self.performKeyboardIntent(intent)
      return nil
    }
  }

  private func performKeyboardIntent(_ intent: ShelfKeyboard.Intent) {
    switch intent {
    case .paste(let index, let plain):
      if let index {
        viewModel.pasteItem(at: index, plainText: plain)
      } else if plain {
        viewModel.pasteSelectedPlainText()
      } else {
        viewModel.pasteSelected()
      }
    case .category(let category): viewModel.sortMode = category
    case .settings: openSettings()
    case .command(let action): performShortcutAction(action)
    case .move(let movement, let extending):
      performMovement(movement, extending: extending)
      panelView.focusSelectedCardForKeyboardNavigation()
    case .selectAll:
      viewModel.selectAllVisibleItems()
      panelView.focusSelectedCardForKeyboardNavigation()
    case .cancel: if !panelView.clearSearchForKeyboardCancel() { hide() }
    case .preview: previewSelected()
    case .delete: viewModel.deleteSelected()
    case .pin: viewModel.togglePinSelected()
    }
  }

  private func performMovement(_ movement: ShelfKeyboard.Movement, extending: Bool) {
    let count = viewModel.visibleItems.count
    guard count > 0 else { return }
    let target: Int
    switch movement {
    case .first: target = 0
    case .last: target = count - 1
    case .next: target = viewModel.selectedIndex + 1
    case .previous: target = viewModel.selectedIndex - 1
    case .pageNext: target = viewModel.selectedIndex + panelView.visibleCardPageStep
    case .pagePrevious: target = viewModel.selectedIndex - panelView.visibleCardPageStep
    }
    if !extending, movement == .first {
      viewModel.selectFirstItem()
    } else if !extending, movement == .last {
      viewModel.selectLastItem()
    } else {
      viewModel.moveSelection(target - viewModel.selectedIndex, extending: extending)
    }
  }

  private func performShortcutAction(_ action: ClipboardPanelShortcutAction) {
    switch action {
    case .copy: viewModel.copySelected()
    case .copyPlainText: viewModel.copySelectedPlainText()
    case .edit: panelView.editSelectedClip()
    case .focusSearch: panelView.focusSearch()
    case .newCollection: panelView.createCollection()
    case .nextCollection: viewModel.selectAdjacentCollection(delta: 1)
    case .open: viewModel.openSelected()
    case .pastePlainText: viewModel.pasteSelectedPlainText()
    case .pasteStackNext: viewModel.pasteNextStackItem()
    case .preview: previewSelected()
    case .previousCollection: viewModel.selectAdjacentCollection(delta: -1)
    case .rename: panelView.renameSelectedClip()
    case .reveal: viewModel.revealSelected()
    case .showInClipboard: panelView.showSelectedInClipboard()
    case .toggleCapturePause: toggleCapturePauseFromShortcut()
    case .toggleStack: viewModel.toggleSelectedStackMembership()
    case .toggleStackCapture: viewModel.toggleStackCaptureMode()
    case .undoDelete: viewModel.undoLastDelete()
    }
  }

  private func toggleCapturePauseFromShortcut() {
    settings.pauseCaptureUntil = nil
    settings.pauseCapture.toggle()
    settings.setCaptureStatus(message: settings.pauseCapture ? "Capture is paused." : "Capture resumed.")
  }

  func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }
}

// MARK: - ShelfController — Preview

extension ShelfController {
  func previewSelected() {
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

  private func showLinkPreview(_ request: LinkPreview) {
    let controller = linkPreviewController ?? LinkPreviewController()
    linkPreviewController = controller
    controller.show(request, relativeTo: panel)
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { quickLookURL == nil ? 0 : 1 }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { quickLookURL as NSURL? }
}
