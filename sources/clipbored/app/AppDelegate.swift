import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  enum PresentationSurface: Equatable {
    case menuBar
    case dock
  }

  struct PresentationPlan: Equatable {
    let showMenuBarIcon: Bool
    let showDockIcon: Bool
    let activationPolicy: NSApplication.ActivationPolicy
  }

  struct StatusMenuPresentation: Equatable {
    let summary: String
    let detail: String?
  }

  struct CapturePauseDuration: Equatable {
    let title: String
    let seconds: TimeInterval
    let symbolName: String
  }

  private static let statusMenuTextLimit = 68
  static let temporaryPauseDurations = [
    CapturePauseDuration(title: "Pause for 5 Minutes", seconds: 5 * 60, symbolName: "timer"),
    CapturePauseDuration(title: "Pause for 30 Minutes", seconds: 30 * 60, symbolName: "timer"),
    CapturePauseDuration(title: "Pause for 1 Hour", seconds: 60 * 60, symbolName: "clock")
  ]

  private var cacheService: ClipboardCacheService!
  private var cloudSyncService: ClipboardCloudSyncService!
  private var settings: SettingsModel!
  private var store: ClipboardStore!
  private var monitor: ClipboardMonitorService!
  private var panelController: ClipboardPanelController!
  private var settingsController: SettingsWindowController!
  private var onboardingController: OnboardingWindowController?
  private var shortcutManager: ShortcutManager!
  private var lifecycleService: AppLifecycleService!
  private var statusItem: NSStatusItem?
  private var statusMenu: NSMenu?
  private var pauseResumeTimer: Timer?
  private var cloudSyncPushWorkItem: DispatchWorkItem?
  private var suppressCloudSyncPush = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    settings = SettingsModel()
    cacheService = ClipboardCacheService()
    cloudSyncService = ClipboardCloudSyncService()
    store = ClipboardStore(settings: settings, cacheService: cacheService)
    monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    panelController = ClipboardPanelController(
      store: store,
      settings: settings,
      cacheService: cacheService,
      pollClipboardNow: { [weak monitor] in
        monitor?.pollNowAndWait()
      },
      openSettings: { [weak self] in
        self?.openSettings()
      }
    )
    monitor.onCapturedItem = { [weak self] item in
      self?.panelController.addCapturedItemToStack(item)
    }
    settingsController = SettingsWindowController(
      settings: settings,
      store: store,
      cacheService: cacheService,
      cloudSyncService: cloudSyncService
    )
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
      onToggleStackCapture: { [weak self] in
        DispatchQueue.main.async {
          self?.panelController.toggleStackCaptureMode()
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
    bindCloudSync()
    applyPresentation(changedSurface: nil)
    applyCapturePauseSetting()
    monitor.start()
    shortcutManager.start()

    applyLaunchAtLoginSetting(settings.launchAtLogin)

    refreshStatusItem()
    configureMainMenu()
    presentInitialSetupIfNeeded()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    refreshAccessibilityPermissionMessage()
    onboardingController?.refreshPermissionStatus()
  }

  func applicationWillTerminate(_ notification: Notification) {
    pauseResumeTimer?.invalidate()
    cloudSyncPushWorkItem?.cancel()
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

  @objc private func createCollection() {
    panelController.createCollection()
  }

  @objc private func toggleStackCaptureMode() {
    panelController.toggleStackCaptureMode()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    if shouldOpenStatusMenu(for: event) {
      popStatusMenu(from: sender)
      return
    }

    showClipboardPanelFromStatusButton(sender)
  }

  private func showClipboardPanelFromStatusButton(_ button: NSStatusBarButton) {
    panelController.toggle(preferredScreen: button.window?.screen)
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
        pauseCaptureUntil: settings.pauseCaptureUntil,
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
    pauseCaptureUntil: Date? = nil,
    now: Date = Date(),
    captureStatus: String,
    pasteStatus: String,
    shortcutStatus: String,
    accessibilityStatus: String,
    launchAtLoginStatus: String
  ) -> StatusMenuPresentation {
    let captureState = isCapturePaused ? "Capture Paused" : "Capture Running"
    let summary = "\(captureState) - \(clipCountText(historyCount))"
    let status = firstPresentStatus([
      capturePauseStatusText(isCapturePaused: isCapturePaused, pauseCaptureUntil: pauseCaptureUntil, now: now),
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
      "New Collection",
      action: #selector(createCollection),
      target: target,
      keyEquivalent: "n",
      keyEquivalentModifierMask: [.command, .shift],
      symbolName: "folder.badge.plus",
      to: menu
    )
    addActionMenuItem(
      "Stack Capture",
      action: #selector(toggleStackCaptureMode),
      target: target,
      keyEquivalent: "c",
      keyEquivalentModifierMask: [.command, .shift],
      symbolName: "square.stack.3d.up.fill",
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
      keyEquivalent: "t",
      keyEquivalentModifierMask: .command,
      symbolName: isCapturePaused ? "play.fill" : "pause.fill",
      to: menu
    )
    pause.state = isCapturePaused ? .on : .off
    if !isCapturePaused {
      for duration in temporaryPauseDurations {
        let item = addActionMenuItem(
          duration.title,
          action: #selector(pauseCaptureForDuration(_:)),
          target: target,
          symbolName: duration.symbolName,
          to: menu
        )
        item.representedObject = duration.seconds
      }
    }

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
    if settings.pauseCapture {
      settings.pauseCapture = false
      settings.pauseCaptureUntil = nil
    } else {
      settings.pauseCaptureUntil = nil
      settings.pauseCapture = true
    }
  }

  @objc private func pauseCaptureForDuration(_ sender: NSMenuItem) {
    let seconds = sender.representedObject as? TimeInterval ?? 0
    guard seconds > 0 else { return }
    settings.pauseCapture = true
    settings.pauseCaptureUntil = Date().addingTimeInterval(seconds)
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

  static func shouldResumeExpiredCapturePause(isCapturePaused: Bool, pauseCaptureUntil: Date?, now: Date) -> Bool {
    guard isCapturePaused, let pauseCaptureUntil else { return false }
    return pauseCaptureUntil <= now
  }

  static func capturePauseStatusText(isCapturePaused: Bool, pauseCaptureUntil: Date?, now: Date) -> String? {
    guard isCapturePaused else { return nil }
    guard let pauseCaptureUntil, pauseCaptureUntil > now else {
      return "Capture is paused."
    }

    let seconds = max(0, pauseCaptureUntil.timeIntervalSince(now))
    if seconds < 60 {
      return "Capture is paused for less than a minute."
    }

    let minutes = Int(ceil(seconds / 60))
    if minutes < 60 {
      return "Capture is paused for \(minutes) more \(pluralized("minute", minutes))."
    }

    let hours = Int(ceil(Double(minutes) / 60))
    return "Capture is paused for \(hours) more \(pluralized("hour", hours))."
  }

  private static func pluralized(_ singular: String, _ count: Int) -> String {
    count == 1 ? singular : "\(singular)s"
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

    let fileMenu = NSMenuItem()
    let fileSubMenu = NSMenu(title: "File")
    let newCollection = NSMenuItem(
      title: "New Collection",
      action: #selector(createCollection),
      keyEquivalent: "n"
    )
    newCollection.keyEquivalentModifierMask = [.command, .shift]
    newCollection.target = self
    fileSubMenu.addItem(newCollection)
    fileSubMenu.addItem(NSMenuItem.separator())
    let pauseCapture = NSMenuItem(
      title: "Pause/Resume Capture",
      action: #selector(togglePauseCapture),
      keyEquivalent: "t"
    )
    pauseCapture.keyEquivalentModifierMask = .command
    pauseCapture.target = self
    fileSubMenu.addItem(pauseCapture)
    fileMenu.submenu = fileSubMenu

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
    let stackCapture = NSMenuItem(
      title: "Stack Capture",
      action: #selector(toggleStackCaptureMode),
      keyEquivalent: "c"
    )
    stackCapture.keyEquivalentModifierMask = [.command, .shift]
    stackCapture.target = self
    editSubMenu.addItem(stackCapture)
    editMenu.submenu = editSubMenu

    let mainMenu = NSMenu()
    mainMenu.addItem(appMenu)
    mainMenu.addItem(fileMenu)
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

  private func bindCloudSync() {
    var observedInitialItems = false
    store.observeItems { [weak self] _ in
      guard let self else { return }
      if !observedInitialItems {
        observedInitialItems = true
        return
      }
      guard self.settings.iCloudSyncEnabled, !self.suppressCloudSyncPush else { return }
      self.scheduleCloudSyncPush()
    }

    if settings.iCloudSyncEnabled {
      applyCloudSyncSetting()
    } else {
      settings.setCloudSyncStatus(message: "iCloud Sync is off.")
    }
  }

  private func handleSettingsChange(_ change: SettingsModel.Change) {
    switch change {
    case .maxHistoryItems:
      store.updateHistoryLimit(settings.maxHistoryItems)
    case .historyRetention:
      store.normalizeHistoryLength()
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
      applyPresentation(changedSurface: .menuBar)
    case .showDockIcon:
      applyPresentation(changedSurface: .dock)
    case .compactMode:
      break
    case .panelLayout:
      break
    case .panelSizing:
      break
    case .cloudSync:
      applyCloudSyncSetting()
    case .pauseCapture:
      applyCapturePauseSetting()
    case .pollProfile:
      monitor.setPaused(settings.pauseCapture)
    case .hideFromScreenCapture:
      break
    case .defaultSortMode, .includeImageTextInSearch, .pruneDuplicates, .ignoredItemKinds, .keepFirstImage, .excludeSensitive, .clearHistoryOnQuit:
      break
    case .status, .collections, .ignoredApps, .other:
      break
    case .captureStatus:
      break
    }
  }

  private func applyCloudSyncSetting() {
    cloudSyncPushWorkItem?.cancel()
    cloudSyncPushWorkItem = nil

    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "iCloud Sync is off.")
      return
    }

    let status = cloudSyncService.status()
    settings.setCloudSyncStatus(message: status.message)
    guard status.isAvailable else { return }
    pullCloudSyncArchiveIfAvailable()
  }

  private func pullCloudSyncArchiveIfAvailable() {
    suppressCloudSyncPush = true
    defer { suppressCloudSyncPush = false }

    do {
      let summary = try cloudSyncService.pull(store: store)
      settings.setCloudSyncStatus(message: "Restored \(summary.itemCount) clips from iCloud.")
    } catch ClipboardCloudSyncError.noRemoteArchive(_) {
      settings.setCloudSyncStatus(message: "iCloud Sync is ready. No remote archive yet.")
      scheduleCloudSyncPush(after: 1.0)
    } catch {
      settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
    }
  }

  private func scheduleCloudSyncPush(after delay: TimeInterval = 2.0) {
    cloudSyncPushWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.pushCloudSyncArchive()
    }
    cloudSyncPushWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func pushCloudSyncArchive() {
    guard settings.iCloudSyncEnabled else { return }
    do {
      let summary = try cloudSyncService.push(store: store)
      settings.setCloudSyncStatus(message: "Synced \(summary.itemCount) clips to iCloud.")
    } catch {
      settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
    }
  }

  private func applyCapturePauseSetting(now: Date = Date()) {
    if Self.shouldResumeExpiredCapturePause(
      isCapturePaused: settings.pauseCapture,
      pauseCaptureUntil: settings.pauseCaptureUntil,
      now: now
    ) {
      settings.pauseCapture = false
      settings.pauseCaptureUntil = nil
      return
    }

    monitor.setPaused(settings.pauseCapture)
    scheduleCapturePauseTimer(now: now)
    if settings.showMenuBarIcon {
      refreshStatusMenu()
    }
  }

  private func scheduleCapturePauseTimer(now: Date = Date()) {
    pauseResumeTimer?.invalidate()
    pauseResumeTimer = nil

    guard settings.pauseCapture, let pauseCaptureUntil = settings.pauseCaptureUntil else { return }
    let interval = pauseCaptureUntil.timeIntervalSince(now)
    guard interval > 0 else {
      settings.pauseCapture = false
      settings.pauseCaptureUntil = nil
      return
    }

    pauseResumeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        self?.resumeExpiredCapturePause()
      }
    }
  }

  private func resumeExpiredCapturePause() {
    guard Self.shouldResumeExpiredCapturePause(
      isCapturePaused: settings.pauseCapture,
      pauseCaptureUntil: settings.pauseCaptureUntil,
      now: Date()
    ) else {
      applyCapturePauseSetting()
      return
    }

    settings.pauseCapture = false
    settings.pauseCaptureUntil = nil
  }

  static func presentationPlan(
    showMenuBarIcon: Bool,
    showDockIcon: Bool,
    changedSurface: PresentationSurface?
  ) -> PresentationPlan {
    var plannedMenuBarIcon = showMenuBarIcon
    var plannedDockIcon = showDockIcon

    if !plannedMenuBarIcon && !plannedDockIcon {
      if changedSurface == .menuBar {
        plannedDockIcon = true
      } else {
        plannedMenuBarIcon = true
      }
    }

    return PresentationPlan(
      showMenuBarIcon: plannedMenuBarIcon,
      showDockIcon: plannedDockIcon,
      activationPolicy: plannedDockIcon ? .regular : .accessory
    )
  }

  private func applyPresentation(changedSurface: PresentationSurface?) {
    let plan = Self.presentationPlan(
      showMenuBarIcon: settings.showMenuBarIcon,
      showDockIcon: settings.showDockIcon,
      changedSurface: changedSurface
    )

    if settings.showMenuBarIcon != plan.showMenuBarIcon {
      settings.showMenuBarIcon = plan.showMenuBarIcon
    }
    if settings.showDockIcon != plan.showDockIcon {
      settings.showDockIcon = plan.showDockIcon
    }

    NSApp.setActivationPolicy(plan.activationPolicy)
    configureMainMenu()
    refreshStatusItem()
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
    alert.informativeText = "ClipBored captures history without extra permission. Grant Accessibility only for direct paste; otherwise paste actions copy the clip."
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

  private func presentInitialSetupIfNeeded() {
    guard !settings.onboardingCompleted else {
      requestInitialAccessibilityPermissionIfNeeded()
      return
    }

    let controller = OnboardingWindowController(
      settings: settings,
      onOpenAccessibility: { [weak self] in
        self?.openAccessibilitySettingsFromOnboarding()
      },
      onFinish: { [weak self] in
        self?.completeInitialSetup()
      }
    )
    onboardingController = controller
    controller.show()
  }

  private func openAccessibilitySettingsFromOnboarding() {
    settings.markAccessibilityNoticeShown()
    _ = AccessibilityPermissionService.requestPromptIfNeeded()
    if !AccessibilityPermissionService.isTrusted {
      AccessibilityPermissionService.openSystemSettings()
    }
    refreshAccessibilityPermissionMessage()
  }

  private func completeInitialSetup() {
    onboardingController = nil
    requestInitialAccessibilityPermissionIfNeeded()
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
