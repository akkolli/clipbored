import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  struct StatusMenuPresentation: Equatable {
    let summary: String
    let detail: String?
  }

  private static let statusMenuTextLimit = 68

  private var cacheService: ClipboardCacheService!
  private var settings: SettingsModel!
  private var store: ClipboardStore!
  private var monitor: ClipboardMonitorService!
  private var panelController: ClipboardPanelController!
  private var settingsController: SettingsWindowController!
  private var shortcutManager: ShortcutManager!
  private var lifecycleService: AppLifecycleService!
  private var statusItem: NSStatusItem?
  private var statusMenu: NSMenu?

  func applicationDidFinishLaunching(_ notification: Notification) {
    settings = SettingsModel()
    cacheService = ClipboardCacheService()
    store = ClipboardStore(settings: settings, cacheService: cacheService)
    monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    panelController = ClipboardPanelController(
      store: store,
      settings: settings,
      cacheService: cacheService,
      preferredScreen: { [weak self] in
        self?.statusItem?.button?.window?.screen
      },
      pollClipboardNow: { [weak monitor] in
        monitor?.pollNowAndWait()
      },
      openSettings: { [weak self] in
        self?.openSettings()
      }
    )
    settingsController = SettingsWindowController(settings: settings, store: store, cacheService: cacheService)
    lifecycleService = AppLifecycleService()
    shortcutManager = ShortcutManager(
      onOpenClipboardPanel: { [weak self] in
        DispatchQueue.main.async {
          self?.panelController.toggle()
        }
      },
      onOpenSettings: { [weak self] in
        DispatchQueue.main.async {
          self?.refreshAccessibilityPermissionMessage()
          self?.settingsController.show()
        }
      },
      onStatusChange: { [weak self] status in
        DispatchQueue.main.async {
          self?.settings.setShortcutStatus(message: status.message)
        }
      },
      openShortcut: settings.openShortcut,
      settingsShortcut: settings.settingsShortcut
    )
    bindSettings()
    monitor.setPaused(settings.pauseCapture)
    monitor.start()
    shortcutManager.start()

    applyLaunchAtLoginSetting(settings.launchAtLogin)

    refreshStatusItem()
    configureMainMenu()
    requestInitialAccessibilityPermissionIfNeeded()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    refreshAccessibilityPermissionMessage()
  }

  func applicationWillTerminate(_ notification: Notification) {
    monitor.stop()
    shortcutManager.stop()
    cacheService.clearTemporaryPreviews(wait: true)
    if settings.clearHistoryOnQuit {
      store.removeAll()
      store.flushPersistenceForTesting()
      cacheService.clearCache()
      cacheService.flushForTesting()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  @objc private func showClipboardPanel() {
    panelController.toggle()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    if shouldOpenStatusMenu(for: event) {
      popStatusMenu(from: sender)
      return
    }

    showClipboardPanel()
  }

  private func shouldOpenStatusMenu(for event: NSEvent?) -> Bool {
    guard let event else { return false }
    return Self.shouldOpenStatusMenu(eventType: event.type, modifierFlags: event.modifierFlags)
  }

  static func shouldOpenStatusMenu(eventType: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) -> Bool {
    switch eventType {
    case .rightMouseDown, .rightMouseUp:
      return true
    case .leftMouseDown, .leftMouseUp:
      return modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
    case .otherMouseDown, .otherMouseUp:
      return true
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      return false
    default:
      return false
    }
  }

  private func statusMenuTemplate() -> NSMenu {
    Self.makeStatusMenu(
      presentation: Self.statusMenuPresentation(
        historyCount: store.items.count,
        isCapturePaused: settings.pauseCapture,
        captureStatus: settings.captureStatusMessage,
        pasteStatus: settings.pasteStatusMessage,
        shortcutStatus: settings.shortcutStatusMessage,
        accessibilityStatus: settings.accessibilityPermissionStatusMessage,
        launchAtLoginStatus: settings.launchAtLoginErrorMessage
      ),
      isCapturePaused: settings.pauseCapture,
      openShortcut: settings.openShortcut,
      settingsShortcut: settings.settingsShortcut,
      target: self
    )
  }

  private func refreshStatusMenu() {
    statusMenu = statusMenuTemplate()
  }

  static func statusMenuPresentation(
    historyCount: Int,
    isCapturePaused: Bool,
    captureStatus: String,
    pasteStatus: String,
    shortcutStatus: String,
    accessibilityStatus: String,
    launchAtLoginStatus: String
  ) -> StatusMenuPresentation {
    let captureState = isCapturePaused ? "Capture Paused" : "Capture Running"
    let summary = "\(captureState) - \(clipCountText(historyCount))"
    let status = firstPresentStatus([
      isCapturePaused ? "Capture is paused." : nil,
      captureStatus,
      pasteStatus,
      shortcutStatus,
      launchAtLoginStatus,
      accessibilityStatus
    ])
    return StatusMenuPresentation(
      summary: boundedStatusText(summary),
      detail: status.map { boundedStatusText($0) }
    )
  }

  static func makeStatusMenu(
    presentation: StatusMenuPresentation,
    isCapturePaused: Bool,
    openShortcut: ShortcutBinding,
    settingsShortcut: ShortcutBinding,
    target: AnyObject?
  ) -> NSMenu {
    let menu = NSMenu(title: "ClipBored")
    menu.autoenablesItems = false
    addDisabledMenuItem("ClipBored", to: menu, symbolName: "doc.on.clipboard")
    addDisabledMenuItem(presentation.summary, to: menu, symbolName: isCapturePaused ? "pause.circle" : "checkmark.circle")
    if let detail = presentation.detail {
      addDisabledMenuItem(detail, to: menu, symbolName: "info.circle")
    }
    menu.addItem(NSMenuItem.separator())

    addActionMenuItem(
      "Show Clipboard",
      action: #selector(showClipboardPanel),
      target: target,
      keyEquivalent: openShortcut.key,
      keyEquivalentModifierMask: modifierFlags(for: openShortcut),
      symbolName: "rectangle.bottomthird.inset.filled",
      to: menu
    )
    addActionMenuItem(
      "Settings\u{2026}",
      action: #selector(openSettings),
      target: target,
      keyEquivalent: settingsShortcut.key,
      keyEquivalentModifierMask: modifierFlags(for: settingsShortcut),
      symbolName: "gearshape",
      to: menu
    )
    menu.addItem(NSMenuItem.separator())

    let pause = addActionMenuItem(
      isCapturePaused ? "Resume Capture" : "Pause Capture",
      action: #selector(togglePauseCapture),
      target: target,
      symbolName: isCapturePaused ? "play.fill" : "pause.fill",
      to: menu
    )
    pause.state = isCapturePaused ? .on : .off

    menu.addItem(NSMenuItem.separator())
    addActionMenuItem(
      "Quit ClipBored",
      action: #selector(quitApp),
      target: target,
      keyEquivalent: "q",
      keyEquivalentModifierMask: .command,
      symbolName: "power",
      to: menu
    )
    return menu
  }

  @objc private func openSettings() {
    refreshAccessibilityPermissionMessage()
    settingsController.show()
  }

  @objc private func togglePauseCapture() {
    settings.pauseCapture.toggle()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  private func refreshStatusItem() {
    guard settings.showMenuBarIcon else {
      if let statusItem {
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
      }
      return
    }

    if statusItem == nil {
      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    if let button = statusItem?.button {
      if let icon = appIconImage() {
        button.image = icon
      } else if let icon = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "ClipBored") {
        icon.isTemplate = true
        button.image = icon
      }
      button.toolTip = "ClipBored"
      button.sendAction(on: [
        .leftMouseUp,
        .rightMouseUp,
        .otherMouseUp
      ])
      button.target = self
      button.action = #selector(statusItemClicked(_:))
    }
    refreshStatusMenu()
    statusItem?.menu = nil
  }

  private func popStatusMenu(from button: NSStatusBarButton) {
    refreshStatusMenu()
    statusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
  }

  @discardableResult
  private func addMenuItem(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    menu.addItem(item)
    return item
  }

  private static func firstPresentStatus(_ candidates: [String?]) -> String? {
    for candidate in candidates {
      guard let value = candidate?.clipboardTrimmed, !value.isEmpty else { continue }
      return value
    }
    return nil
  }

  private static func clipCountText(_ count: Int) -> String {
    if count <= 0 { return "No clips" }
    if count == 1 { return "1 clip" }
    return "\(count) clips"
  }

  private static func boundedStatusText(_ value: String) -> String {
    let collapsed = value
      .split { $0.isWhitespace || $0.isNewline }
      .joined(separator: " ")
      .clipboardTrimmed
    guard collapsed.count > statusMenuTextLimit else { return collapsed }
    return String(collapsed.prefix(statusMenuTextLimit - 3)).clipboardTrimmed + "..."
  }

  @discardableResult
  private static func addDisabledMenuItem(_ title: String, to menu: NSMenu, symbolName: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    item.image = menuImage(symbolName)
    menu.addItem(item)
    return item
  }

  @discardableResult
  private static func addActionMenuItem(
    _ title: String,
    action: Selector,
    target: AnyObject?,
    keyEquivalent: String = "",
    keyEquivalentModifierMask: NSEvent.ModifierFlags = [],
    symbolName: String,
    to menu: NSMenu
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.keyEquivalentModifierMask = keyEquivalentModifierMask
    item.target = target
    item.isEnabled = true
    item.image = menuImage(symbolName)
    menu.addItem(item)
    return item
  }

  private static func menuImage(_ symbolName: String) -> NSImage? {
    guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
      return nil
    }
    image.size = NSSize(width: 15, height: 15)
    image.isTemplate = true
    return image
  }

  private static func modifierFlags(for binding: ShortcutBinding) -> NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: binding.modifierFlags)
  }

  private func configureMainMenu() {
    let appMenu = NSMenuItem()
    let appSubMenu = NSMenu(title: "ClipBored")
    let settingsShortcut = self.settings.settingsShortcut
    let settings = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettings),
      keyEquivalent: settingsShortcut.key
    )
    settings.keyEquivalentModifierMask = menuModifierFlags(settingsShortcut)
    settings.target = self
    appSubMenu.addItem(settings)
    appSubMenu.addItem(NSMenuItem.separator())
    let quit = NSMenuItem(title: "Quit ClipBored", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    appSubMenu.addItem(quit)
    appMenu.submenu = appSubMenu

    let editMenu = NSMenuItem()
    let editSubMenu = NSMenu(title: "Edit")
    let openShortcut = self.settings.openShortcut
    let showClipboard = NSMenuItem(
      title: "Show Clipboard",
      action: #selector(showClipboardPanel),
      keyEquivalent: openShortcut.key
    )
    showClipboard.keyEquivalentModifierMask = menuModifierFlags(openShortcut)
    showClipboard.target = self
    editSubMenu.addItem(showClipboard)
    editMenu.submenu = editSubMenu

    let mainMenu = NSMenu()
    mainMenu.addItem(appMenu)
    mainMenu.addItem(editMenu)
    NSApp.mainMenu = mainMenu
  }

  private func bindSettings() {
    settings.observe { [weak self] change in
      guard let self else { return }
      DispatchQueue.main.async {
        self.handleSettingsChange(change)
      }
    }
  }

  private func handleSettingsChange(_ change: SettingsModel.Change) {
    switch change {
    case .maxHistoryItems:
      store.updateHistoryLimit(settings.maxHistoryItems)
    case .imageCacheMaxBytes:
      cacheService.purgeIfNeeded(maxBytes: settings.imageCacheMaxBytes)
    case .openShortcut, .settingsShortcut:
      let status = shortcutManager.reconfigure(openShortcut: settings.openShortcut, settingsShortcut: settings.settingsShortcut)
      settings.setShortcutStatus(message: status.message)
      refreshStatusItem()
      configureMainMenu()
    case .launchAtLogin:
      applyLaunchAtLoginSetting(settings.launchAtLogin)
    case .showMenuBarIcon:
      refreshStatusItem()
    case .pauseCapture:
      monitor.setPaused(settings.pauseCapture)
      if settings.showMenuBarIcon {
        refreshStatusMenu()
      }
    case .pollProfile:
      monitor.setPaused(settings.pauseCapture)
    case .status, .other:
      break
    case .captureStatus:
      break
    }
  }

  private func applyLaunchAtLoginSetting(_ shouldLaunch: Bool) {
    let result = lifecycleService.applyLaunchAtLogin(shouldLaunch)
    switch result {
    case .success:
      settings.setLaunchAtLoginStatus(message: "")
      if settings.launchAtLogin != shouldLaunch {
        settings.launchAtLogin = shouldLaunch
      }
    case .noChange:
      settings.setLaunchAtLoginStatus(message: "")
    case .failure(let message):
      settings.setLaunchAtLoginStatus(message: "Launch-at-login failed: \(message)")
      let actualState = lifecycleService.isEnabled()
      if settings.launchAtLogin != actualState {
        settings.launchAtLogin = actualState
      }
    }
  }

  private func refreshAccessibilityPermissionMessage() {
    if AccessibilityPermissionService.isTrusted {
      settings.setAccessibilityPermissionStatus(message: "")
    } else {
      settings.setAccessibilityPermissionStatus(message: "Accessibility permission not granted. Capture still works; paste falls back to copy.")
    }
    refreshStatusItem()
  }

  private func requestInitialAccessibilityPermissionIfNeeded() {
    refreshAccessibilityPermissionMessage()
    if AccessibilityPermissionService.isTrusted {
      return
    }

    if !settings.accessibilityNoticeShown {
      settings.markAccessibilityNoticeShown()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        self?.showAccessibilityPermissionNoticeIfNeeded()
      }
    }
  }

  private func showAccessibilityPermissionNoticeIfNeeded() {
    guard !AccessibilityPermissionService.isTrusted else {
      refreshAccessibilityPermissionMessage()
      return
    }

    let alert = NSAlert()
    alert.messageText = "Allow automatic paste?"
    alert.informativeText = "ClipBored can capture clipboard history without extra permission. Grant Accessibility only if you want selected clips to paste directly into the previous app; otherwise paste actions will copy the clip for you."
    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Later")
    alert.alertStyle = .warning

    if alert.runModal() == .alertFirstButtonReturn {
      _ = AccessibilityPermissionService.requestPromptIfNeeded()
      if !AccessibilityPermissionService.isTrusted {
        AccessibilityPermissionService.openSystemSettings()
      }
    }
    refreshAccessibilityPermissionMessage()
  }

  private func menuModifierFlags(_ binding: ShortcutBinding) -> NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: binding.modifierFlags)
  }

  private func appIconImage() -> NSImage? {
    guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: url)
    else {
      return nil
    }
    icon.size = NSSize(width: 18, height: 18)
    icon.isTemplate = false
    return icon
  }

}
