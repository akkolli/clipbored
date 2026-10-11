import AppKit
import ApplicationServices
import Carbon
import Foundation
import ServiceManagement

// MARK: - GoldfishApp

@main struct GoldfishApp {
  private static let appDelegate = AppDelegate()

  static func main() {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.delegate = appDelegate
    application.activate(ignoringOtherApps: true)
    application.run()
  }
}

// MARK: - AppDelegate

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

  static let statusMenuTextLimit = 68
  static let temporaryPauseDurations = [
    CapturePauseDuration(title: "Pause for 5 Minutes", seconds: 5 * 60, symbolName: "timer"),
    CapturePauseDuration(title: "Pause for 30 Minutes", seconds: 30 * 60, symbolName: "timer"),
    CapturePauseDuration(title: "Pause for 1 Hour", seconds: 60 * 60, symbolName: "clock"),
  ]

  var cacheService: MediaCache!
  var cloudSyncService: ArchiveSync!
  var settings: Preferences!
  var store: HistoryStore!
  var monitor: CaptureMonitor!
  var panelController: ShelfController!
  var settingsController: SettingsController!
  var onboardingController: SetupController?
  var shortcutManager: ShortcutManager!
  var lifecycleService: AppLifecycleService!
  var statusItem: NSStatusItem?
  var statusMenu: NSMenu?
  var pauseResumeTimer: Timer?
  var cloudSyncPushWorkItem: DispatchWorkItem?
  let cloudSyncOperationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "clipbored.cloud-sync"
    queue.qualityOfService = .utility
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  let cloudSyncStateLock = NSLock()
  var suppressCloudSyncPush = false
  var cloudSyncOperationGeneration = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    settings = Preferences()
    cacheService = MediaCache()
    cloudSyncService = ArchiveSync()
    store = HistoryStore(settings: settings, cacheService: cacheService)
    monitor = CaptureMonitor(store: store, cacheService: cacheService, settings: settings)
    panelController = ShelfController(
      store: store, settings: settings, cacheService: cacheService,
      pollClipboardNow: { [weak monitor] in monitor?.pollNow() }, openSettings: { [weak self] in self?.openSettings() })
    monitor.onCapturedItem = { [weak self] item in self?.panelController.addCapturedItemToStack(item) }
    settingsController = SettingsController(
      settings: settings, store: store, cacheService: cacheService, cloudSyncService: cloudSyncService)
    lifecycleService = AppLifecycleService()
    shortcutManager = ShortcutManager(
      onOpenClipboardPanel: { [weak self] in DispatchQueue.main.async { self?.panelController.toggle() } },
      onToggleStackCapture: { [weak self] in DispatchQueue.main.async { self?.panelController.toggleStackCaptureMode() }
      },
      onStatusChange: { [weak self] status in
        DispatchQueue.main.async { self?.settings.setShortcutStatus(message: status.message) }
      }, openShortcut: settings.openShortcut)
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
    cloudSyncOperationQueue.cancelAllOperations()
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

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - AppDelegate — Settings

extension AppDelegate {
  static func shouldResumeExpiredCapturePause(isCapturePaused: Bool, pauseCaptureUntil: Date?, now: Date) -> Bool {
    guard isCapturePaused, let pauseCaptureUntil else { return false }
    return pauseCaptureUntil <= now
  }

  static func capturePauseStatusText(isCapturePaused: Bool, pauseCaptureUntil: Date?, now: Date) -> String? {
    guard isCapturePaused else { return nil }
    guard let pauseCaptureUntil, pauseCaptureUntil > now else { return "Capture is paused." }

    let seconds = max(0, pauseCaptureUntil.timeIntervalSince(now))
    if seconds < 60 { return "Capture is paused for less than a minute." }

    let minutes = Int(ceil(seconds / 60))
    if minutes < 60 { return "Capture is paused for \(minutes) more \(pluralized("minute", minutes))." }

    let hours = Int(ceil(Double(minutes) / 60))
    return "Capture is paused for \(hours) more \(pluralized("hour", hours))."
  }

  func bindSettings() {
    settings.observe { [weak self] change in
      guard let self else { return }
      DispatchQueue.main.async { self.handleSettingsChange(change) }
    }
  }

  private func handleSettingsChange(_ change: Preferences.Change) {
    switch change {
    case .maxHistoryItems: store.updateHistoryLimit(settings.maxHistoryItems)
    case .historyRetention: store.normalizeHistoryLength()
    case .imageCacheMaxBytes: cacheService.purgeIfNeeded(maxBytes: settings.imageCacheMaxBytes)
    case .openShortcut:
      let status = shortcutManager.reconfigure(openShortcut: settings.openShortcut)
      settings.setShortcutStatus(message: status.message)
      refreshStatusItem()
      configureMainMenu()
    case .settingsShortcut:
      refreshStatusItem()
      configureMainMenu()
    case .launchAtLogin: applyLaunchAtLoginSetting(settings.launchAtLogin)
    case .showMenuBarIcon: applyPresentation(changedSurface: .menuBar)
    case .showDockIcon: applyPresentation(changedSurface: .dock)
    case .panelSide: break
    case .cloudSync: applyCloudSyncSetting()
    case .pauseCapture: applyCapturePauseSetting()
    case .pollProfile: monitor.setPaused(settings.pauseCapture)
    case .hideFromScreenCapture: break
    case .defaultSortMode, .includeImageTextInSearch, .pruneDuplicates, .ignoredItemKinds, .keepFirstImage,
      .excludeSensitive, .clearHistoryOnQuit:
      break
    case .status, .collections, .ignoredApps, .other: break
    case .captureStatus: break
    }
  }

  func applyCapturePauseSetting(now: Date = Date()) {
    if Self.shouldResumeExpiredCapturePause(
      isCapturePaused: settings.pauseCapture, pauseCaptureUntil: settings.pauseCaptureUntil, now: now)
    {
      settings.pauseCapture = false
      settings.pauseCaptureUntil = nil
      return
    }

    monitor.setPaused(settings.pauseCapture)
    scheduleCapturePauseTimer(now: now)
    if settings.showMenuBarIcon { refreshStatusMenu() }
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
      DispatchQueue.main.async { self?.resumeExpiredCapturePause() }
    }
  }

  private func resumeExpiredCapturePause() {
    guard
      Self.shouldResumeExpiredCapturePause(
        isCapturePaused: settings.pauseCapture, pauseCaptureUntil: settings.pauseCaptureUntil, now: Date())
    else {
      applyCapturePauseSetting()
      return
    }

    settings.pauseCapture = false
    settings.pauseCaptureUntil = nil
  }

  static func presentationPlan(showMenuBarIcon: Bool, showDockIcon: Bool, changedSurface: PresentationSurface?)
    -> PresentationPlan
  {
    var plannedMenuBarIcon = showMenuBarIcon
    var plannedDockIcon = showDockIcon

    if !plannedMenuBarIcon && !plannedDockIcon {
      if changedSurface == .menuBar { plannedDockIcon = true } else { plannedMenuBarIcon = true }
    }

    return PresentationPlan(
      showMenuBarIcon: plannedMenuBarIcon, showDockIcon: plannedDockIcon,
      activationPolicy: plannedDockIcon ? .regular : .accessory)
  }

  func applyPresentation(changedSurface: PresentationSurface?) {
    let plan = Self.presentationPlan(
      showMenuBarIcon: settings.showMenuBarIcon, showDockIcon: settings.showDockIcon, changedSurface: changedSurface)

    if settings.showMenuBarIcon != plan.showMenuBarIcon { settings.showMenuBarIcon = plan.showMenuBarIcon }
    if settings.showDockIcon != plan.showDockIcon { settings.showDockIcon = plan.showDockIcon }

    NSApp.setActivationPolicy(plan.activationPolicy)
    configureMainMenu()
    refreshStatusItem()
  }

  func applyLaunchAtLoginSetting(_ shouldLaunch: Bool) {
    let result = lifecycleService.applyLaunchAtLogin(shouldLaunch)
    switch result {
    case .success:
      settings.setLaunchAtLoginStatus(message: "")
      if settings.launchAtLogin != shouldLaunch { settings.launchAtLogin = shouldLaunch }
    case .noChange: settings.setLaunchAtLoginStatus(message: "")
    case .failure(let message):
      settings.setLaunchAtLoginStatus(message: "Launch-at-login failed: \(message)")
      let actualState = lifecycleService.isEnabled()
      if settings.launchAtLogin != actualState { settings.launchAtLogin = actualState }
    }
  }
}

// MARK: - AppDelegate — Menu

extension AppDelegate {
  @objc private func showClipboardPanel() { panelController.toggle() }

  @objc private func createCollection() { panelController.createCollection() }

  @objc func toggleStackCaptureMode() { panelController.toggleStackCaptureMode() }

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
    case .rightMouseDown, .rightMouseUp: return true
    case .leftMouseDown, .leftMouseUp: return modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
    case .otherMouseDown, .otherMouseUp: return true
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: return false
    default: return false
    }
  }

  private func statusMenuTemplate() -> NSMenu {
    Self.makeStatusMenu(
      presentation: Self.statusMenuPresentation(
        historyCount: store.items.count, isCapturePaused: settings.pauseCapture,
        pauseCaptureUntil: settings.pauseCaptureUntil, captureStatus: settings.captureStatusMessage,
        pasteStatus: settings.pasteStatusMessage, shortcutStatus: settings.shortcutStatusMessage,
        accessibilityStatus: settings.accessibilityPermissionStatusMessage,
        launchAtLoginStatus: settings.launchAtLoginErrorMessage), isCapturePaused: settings.pauseCapture,
      openShortcut: settings.openShortcut, settingsShortcut: settings.settingsShortcut, target: self)
  }

  func refreshStatusMenu() { statusMenu = statusMenuTemplate() }

  static func statusMenuPresentation(
    historyCount: Int, isCapturePaused: Bool, pauseCaptureUntil: Date? = nil, now: Date = Date(), captureStatus: String,
    pasteStatus: String, shortcutStatus: String, accessibilityStatus: String, launchAtLoginStatus: String
  ) -> StatusMenuPresentation {
    let captureState = isCapturePaused ? "Capture Paused" : "Capture Running"
    let summary = "\(captureState) - \(clipCountText(historyCount))"
    let status = firstPresentStatus([
      capturePauseStatusText(isCapturePaused: isCapturePaused, pauseCaptureUntil: pauseCaptureUntil, now: now),
      captureStatus, pasteStatus, shortcutStatus, launchAtLoginStatus, accessibilityStatus,
    ])
    return StatusMenuPresentation(summary: boundedStatusText(summary), detail: status.map { boundedStatusText($0) })
  }

  typealias MenuEntry = (title: String, action: Selector, key: String, flags: NSEvent.ModifierFlags)

  private static func appendMenuEntries(_ rows: [MenuEntry?], to menu: NSMenu, target: AnyObject?) {
    for row in rows {
      guard let row else {
        menu.addItem(.separator())
        continue
      }
      let item = NSMenuItem(title: row.title, action: row.action, keyEquivalent: row.key)
      item.target = target
      item.keyEquivalentModifierMask = row.flags
      menu.addItem(item)
    }
  }

  static func makeStatusMenu(
    presentation: StatusMenuPresentation, isCapturePaused: Bool, openShortcut: ShortcutBinding,
    settingsShortcut: ShortcutBinding, target: AnyObject?
  ) -> NSMenu {
    let menu = NSMenu(title: "Goldfish")
    menu.autoenablesItems = false
    addDisabledMenuItem("Goldfish", to: menu, symbolName: "doc.on.clipboard")
    addDisabledMenuItem(
      presentation.summary, to: menu, symbolName: isCapturePaused ? "pause.circle" : "checkmark.circle")
    if let detail = presentation.detail { addDisabledMenuItem(detail, to: menu, symbolName: "info.circle") }
    appendMenuEntries(
      [
        nil, ("Show Clipboard", #selector(showClipboardPanel), openShortcut.key, modifierFlags(for: openShortcut)),
        ("New Collection", #selector(createCollection), "n", [.command, .shift]),
        ("Stack Capture", #selector(toggleStackCaptureMode), "c", [.command, .shift]),
        ("Settings…", #selector(openSettings), settingsShortcut.key, modifierFlags(for: settingsShortcut)), nil,
        (isCapturePaused ? "Resume Capture" : "Pause Capture", #selector(togglePauseCapture), "t", .command),
      ], to: menu, target: target)
    menu.items.last?.state = isCapturePaused ? .on : .off
    if !isCapturePaused {
      for duration in temporaryPauseDurations {
        appendMenuEntries([(duration.title, #selector(pauseCaptureForDuration(_:)), "", [])], to: menu, target: target)
        menu.items.last?.representedObject = duration.seconds
        menu.items.last?.image = menuImage(duration.symbolName)
      }
    }
    appendMenuEntries([nil, ("Quit Goldfish", #selector(quitApp), "q", .command)], to: menu, target: target)
    let symbols = [
      "Show Clipboard": "rectangle.bottomthird.inset.filled", "New Collection": "folder.badge.plus",
      "Stack Capture": "square.stack.3d.up.fill", "Settings…": "gearshape", "Quit Goldfish": "power",
      "Pause Capture": "pause.fill", "Resume Capture": "play.fill",
    ]
    for item in menu.items { if let symbol = symbols[item.title] { item.image = menuImage(symbol) } }
    return menu
  }

  @objc func openSettings() {
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

  @objc private func quitApp() { NSApp.terminate(nil) }

  func refreshStatusItem() {
    guard settings.showMenuBarIcon else {
      if let statusItem {
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
      }
      return
    }

    if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }

    if let button = statusItem?.button {
      if let icon = appIconImage() {
        button.image = icon
      } else if let icon = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "Goldfish") {
        icon.isTemplate = true
        button.image = icon
      }
      button.toolTip = "Goldfish"
      button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
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

  static func pluralized(_ singular: String, _ count: Int) -> String { count == 1 ? singular : "\(singular)s" }

  private static func boundedStatusText(_ value: String) -> String {
    let collapsed = value.split { $0.isWhitespace || $0.isNewline }.joined(separator: " ").clipboardTrimmed
    guard collapsed.count > statusMenuTextLimit else { return collapsed }
    return String(collapsed.prefix(statusMenuTextLimit - 3)).clipboardTrimmed + "..."
  }

  @discardableResult private static func addDisabledMenuItem(_ title: String, to menu: NSMenu, symbolName: String)
    -> NSMenuItem
  {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    item.image = menuImage(symbolName)
    menu.addItem(item)
    return item
  }

  private static func menuImage(_ symbolName: String) -> NSImage? {
    guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
    image.size = NSSize(width: 15, height: 15)
    image.isTemplate = true
    return image
  }

  private static func modifierFlags(for binding: ShortcutBinding) -> NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: binding.modifierFlags)
  }

  func configureMainMenu() {
    let rows: [(String, [MenuEntry?])] = [
      (
        "Goldfish",
        [
          (
            "Settings…", #selector(openSettings), settings.settingsShortcut.key,
            Self.modifierFlags(for: settings.settingsShortcut)
          ), nil, ("Quit Goldfish", #selector(quitApp), "q", .command),
        ]
      ),
      (
        "File",
        [
          ("New Collection", #selector(createCollection), "n", [.command, .shift]), nil,
          ("Pause/Resume Capture", #selector(togglePauseCapture), "t", .command),
        ]
      ),
      (
        "Edit",
        [
          (
            "Show Clipboard", #selector(showClipboardPanel), settings.openShortcut.key,
            Self.modifierFlags(for: settings.openShortcut)
          ), ("Stack Capture", #selector(toggleStackCaptureMode), "c", [.command, .shift]),
        ]
      ),
    ]
    let main = NSMenu()
    for (title, entries) in rows {
      let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let menu = NSMenu(title: title)
      Self.appendMenuEntries(entries, to: menu, target: self)
      parent.submenu = menu
      main.addItem(parent)
    }
    NSApp.mainMenu = main
  }

  private func appIconImage() -> NSImage? {
    guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url)
    else { return nil }
    icon.size = NSSize(width: 18, height: 18)
    icon.isTemplate = false
    return icon
  }
}

// MARK: - AppDelegate — Onboarding

extension AppDelegate {
  func refreshAccessibilityPermissionMessage() {
    if AccessibilityPermissionService.isTrusted {
      settings.setAccessibilityPermissionStatus(message: "")
    } else {
      settings.setAccessibilityPermissionStatus(
        message: "Accessibility permission not granted. Capture still works; paste falls back to copy.")
    }
    refreshStatusItem()
  }

  private func requestInitialAccessibilityPermissionIfNeeded() {
    refreshAccessibilityPermissionMessage()
    if AccessibilityPermissionService.isTrusted { return }

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

    let alert = UI.alert(
      "Allow automatic paste?",
      message:
        "Goldfish captures history without extra permission. Grant Accessibility only for direct paste; otherwise paste actions copy the clip.",
      action: "Open Accessibility Settings", cancel: "Later", warning: true)

    if alert.runModal() == .alertFirstButtonReturn {
      _ = AccessibilityPermissionService.requestPromptIfNeeded()
      if !AccessibilityPermissionService.isTrusted { AccessibilityPermissionService.openSystemSettings() }
    }
    refreshAccessibilityPermissionMessage()
  }

  func presentInitialSetupIfNeeded() {
    guard !settings.onboardingCompleted else {
      requestInitialAccessibilityPermissionIfNeeded()
      return
    }

    let controller = SetupController(
      settings: settings, onOpenAccessibility: { [weak self] in self?.openAccessibilitySettingsFromOnboarding() },
      onFinish: { [weak self] in self?.completeInitialSetup() })
    onboardingController = controller
    controller.show()
  }

  private func openAccessibilitySettingsFromOnboarding() {
    settings.markAccessibilityNoticeShown()
    _ = AccessibilityPermissionService.requestPromptIfNeeded()
    if !AccessibilityPermissionService.isTrusted { AccessibilityPermissionService.openSystemSettings() }
    refreshAccessibilityPermissionMessage()
  }

  private func completeInitialSetup() {
    onboardingController = nil
    requestInitialAccessibilityPermissionIfNeeded()
  }
}

// MARK: - AppDelegate — CloudSync

extension AppDelegate {
  func bindCloudSync() {
    var observedInitialItems = false
    store.observeItems { [weak self] _ in
      guard let self else { return }
      if !observedInitialItems {
        observedInitialItems = true
        return
      }
      guard self.settings.iCloudSyncEnabled, !self.isCloudSyncPushSuppressed else { return }
      self.scheduleCloudSyncPush()
    }

    if settings.iCloudSyncEnabled {
      applyCloudSyncSetting()
    } else {
      settings.setCloudSyncStatus(message: "iCloud Sync is off.")
    }
  }

  func applyCloudSyncSetting() {
    cloudSyncPushWorkItem?.cancel()
    cloudSyncPushWorkItem = nil
    cloudSyncOperationGeneration += 1
    let generation = cloudSyncOperationGeneration

    guard settings.iCloudSyncEnabled else {
      setCloudSyncPushSuppressed(false)
      settings.setCloudSyncStatus(message: "iCloud Sync is off.")
      return
    }

    settings.setCloudSyncStatus(message: "Checking iCloud Sync…")
    setCloudSyncPushSuppressed(true)
    cloudSyncOperationQueue.addOperation { [weak self] in
      guard let self else { return }
      let status = self.cloudSyncService.status()
      let result: (message: String, schedulesInitialPush: Bool)
      if !status.isAvailable {
        result = (status.message, false)
      } else {
        do {
          let summary = try self.cloudSyncService.pull(store: self.store)
          result = ("Restored \(summary.itemCount) clips from iCloud.", false)
        } catch ArchiveSyncError.noRemoteArchive(_) {
          result = ("iCloud Sync is ready. No remote archive yet.", true)
        } catch { result = ("iCloud Sync failed: \(error.localizedDescription)", false) }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.setCloudSyncPushSuppressed(false)
        guard generation == self.cloudSyncOperationGeneration, self.settings.iCloudSyncEnabled else { return }
        self.settings.setCloudSyncStatus(message: result.message)
        if result.schedulesInitialPush { self.scheduleCloudSyncPush(after: 1.0) }
      }
    }
  }

  private func scheduleCloudSyncPush(after delay: TimeInterval = 2.0) {
    cloudSyncPushWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in self?.pushCloudSyncArchive() }
    cloudSyncPushWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func pushCloudSyncArchive() {
    guard settings.iCloudSyncEnabled else { return }
    let generation = cloudSyncOperationGeneration
    cloudSyncOperationQueue.addOperation { [weak self] in
      guard let self else { return }
      let message: String
      do {
        let summary = try self.cloudSyncService.push(store: self.store)
        message = "Synced \(summary.itemCount) clips to iCloud."
      } catch { message = "iCloud Sync failed: \(error.localizedDescription)" }
      DispatchQueue.main.async { [weak self] in
        guard let self, generation == self.cloudSyncOperationGeneration, self.settings.iCloudSyncEnabled else { return }
        self.settings.setCloudSyncStatus(message: message)
      }
    }
  }

  private var isCloudSyncPushSuppressed: Bool {
    cloudSyncStateLock.lock()
    defer { cloudSyncStateLock.unlock() }
    return suppressCloudSyncPush
  }

  private func setCloudSyncPushSuppressed(_ suppressed: Bool) {
    cloudSyncStateLock.lock()
    suppressCloudSyncPush = suppressed
    cloudSyncStateLock.unlock()
  }
}

// MARK: - Configuration

enum Configuration {
  static let appName = "Goldfish"
  static let storageName = "ClipBored"  // Existing history, previews and iCloud paths.
  static let storageDirectoryOverrideEnvironmentKey = "CLIPBORED_STORAGE_DIR"
  static let defaultHistoryLength = 300
  static let minHistoryLength = 50
  static let maxHistoryLength = 2000
  static let minCacheMaxBytes: Int64 = 2 * 1024 * 1024
  static let defaultCacheMaxBytes: Int64 = 120 * 1024 * 1024
  static let maxCacheMaxBytes: Int64 = 512 * 1024 * 1024
  static let maxPinnedItems = 250
  static let maxFullImagePixelSize: CGFloat = 1600
  static let maxRecognizedImageTextLength = 4096
  static let maxImageCacheFiles = 1000
  static let defaultOpenShortcut = ShortcutBinding(
    key: "v", modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue)
  static let defaultSettingsShortcut = ShortcutBinding(key: ",", modifierFlags: NSEvent.ModifierFlags.command.rawValue)
  static let defaultIgnoredApps: [String] = [
    "1password", "bitwarden", "lastpass", "dashlane", "keeper", "keepass", "authy",
  ]
  static let defaultPollProfile: PollProfile = .balanced
  static let minResponsiveActiveInterval: TimeInterval = 0.075

  enum PollProfile: Int, CaseIterable {
    case battery = 0
    case balanced = 1
    case responsive = 2

    static let allCases: [PollProfile] = [.battery, .balanced, .responsive]

    var title: String {
      switch self {
      case .battery: return "Battery Saver"
      case .balanced: return "Balanced"
      case .responsive: return "Responsive"
      }
    }

    var idleInterval: TimeInterval {
      switch self {
      case .battery: return 0.50
      case .balanced: return 0.25
      case .responsive: return 0.12
      }
    }

    var activeInterval: TimeInterval {
      switch self {
      case .battery: return 0.12
      case .balanced: return 0.075
      case .responsive: return 0.075
      }
    }

    var idleRecoveryWindow: TimeInterval {
      switch self {
      case .battery: return 3.5
      case .balanced: return 2.0
      case .responsive: return 1.2
      }
    }
  }
}

struct ShortcutBinding: Equatable {
  let key: String
  let modifierFlags: UInt

  init(key: String, modifierFlags: UInt) {
    self.key = key.lowercased()
    self.modifierFlags = modifierFlags
  }

  var displayText: String {
    var text = ""
    if modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0 { text += "⌘" }
    if modifierFlags & NSEvent.ModifierFlags.option.rawValue != 0 { text += "⌥" }
    if modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0 { text += "⌃" }
    if modifierFlags & NSEvent.ModifierFlags.shift.rawValue != 0 { text += "⇧" }
    return text + key.uppercased()
  }

  func matches(_ event: NSEvent) -> Bool {
    guard let eventChar = event.charactersIgnoringModifiers?.lowercased(), eventChar.count == 1 else { return false }
    let mask =
      event.modifierFlags.rawValue
      & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue
        | NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    return eventChar == key && mask == modifierFlags
  }

  func encoded() -> String { "\(modifierFlags)|\(key)" }

  init?(encoded value: String) {
    let parts = value.split(separator: "|")
    guard parts.count == 2, let flags = UInt(parts[0]), let key = parts.last else { return nil }
    self.key = String(key).lowercased()
    self.modifierFlags = flags
  }
}

// MARK: - AppLifecycleService

final class AppLifecycleService {
  enum LaunchAtLoginResult: Equatable {
    case success
    case noChange
    case failure(String)
  }

  private let service = SMAppService.mainApp

  func applyLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginResult {
    do {
      if enabled {
        switch service.status {
        case .notRegistered:
          try service.register()
          return .success
        case .enabled: return .noChange
        default:
          try service.register()
          return .success
        }
      } else if service.status == .enabled {
        try service.unregister()
        return .success
      } else {
        return .noChange
      }
    } catch { return .failure(error.localizedDescription) }
  }

  func isEnabled() -> Bool { service.status == .enabled }
}

// MARK: - AccessibilityPermissionService

enum AccessibilityPermissionService {
  static var isTrusted: Bool { AXIsProcessTrusted() }

  @discardableResult static func requestPromptIfNeeded() -> Bool {
    if isTrusted { return true }

    guard let optionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String? else { return false }
    let options: CFDictionary = [optionPrompt: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openSystemSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
      NSWorkspace.shared.open(url)
    {
      return
    }

    let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    _ = NSWorkspace.shared.open(fallback)
  }
}

// MARK: - ShortcutManager

final class ShortcutManager {
  enum RegistrationStatus: Equatable {
    case registered
    case unsupportedShortcut(String)
    case conflict(String)
    case registrationFailed(String)

    var message: String {
      switch self {
      case .registered: return ""
      case .unsupportedShortcut(let shortcut): return "Unsupported shortcut: \(shortcut)"
      case .conflict(let shortcut): return "Shortcut is already in use: \(shortcut)"
      case .registrationFailed(let message): return "Shortcut registration failed: \(message)"
      }
    }
  }

  private enum HotKeyID: UInt32 {
    case openPanel = 1
    case stackCapture = 3
  }

  private let onOpenClipboardPanel: () -> Void
  private let onToggleStackCapture: () -> Void
  private let onStatusChange: (RegistrationStatus) -> Void
  private var openBinding: ShortcutBinding
  private var openHotKey: EventHotKeyRef?
  private var stackCaptureHotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  init(
    onOpenClipboardPanel: @escaping () -> Void, onToggleStackCapture: @escaping () -> Void = {},
    onStatusChange: @escaping (RegistrationStatus) -> Void = { _ in }, openShortcut: ShortcutBinding
  ) {
    self.onOpenClipboardPanel = onOpenClipboardPanel
    self.onToggleStackCapture = onToggleStackCapture
    self.onStatusChange = onStatusChange
    self.openBinding = openShortcut
  }

  deinit { stop() }

  @discardableResult func start() -> RegistrationStatus {
    stop()

    if let status = Self.validationFailure(for: openBinding) {
      onStatusChange(status)
      return status
    }
    if openBinding == Self.stackCaptureShortcut {
      let status = RegistrationStatus.conflict(Self.stackCaptureShortcut.displayText)
      onStatusChange(status)
      return status
    }

    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handle(event: event)
        return noErr
      }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

    guard installStatus == noErr else {
      let status = RegistrationStatus.registrationFailed(osStatusMessage(installStatus))
      onStatusChange(status)
      return status
    }

    let openStatus = register(binding: openBinding, id: .openPanel, target: &openHotKey)
    guard openStatus == .registered else {
      stop()
      onStatusChange(openStatus)
      return openStatus
    }

    let stackCaptureStatus = register(
      binding: Self.stackCaptureShortcut, id: .stackCapture, target: &stackCaptureHotKey)
    guard stackCaptureStatus == .registered else {
      stop()
      onStatusChange(stackCaptureStatus)
      return stackCaptureStatus
    }

    onStatusChange(.registered)
    return .registered
  }

  @discardableResult func reconfigure(openShortcut: ShortcutBinding) -> RegistrationStatus {
    openBinding = openShortcut
    return start()
  }

  func stop() {
    if let openHotKey { UnregisterEventHotKey(openHotKey) }
    if let stackCaptureHotKey { UnregisterEventHotKey(stackCaptureHotKey) }
    if let eventHandler { RemoveEventHandler(eventHandler) }

    openHotKey = nil
    stackCaptureHotKey = nil
    eventHandler = nil
  }

  private func register(binding: ShortcutBinding, id: HotKeyID, target: inout EventHotKeyRef?) -> RegistrationStatus {
    guard let keyCode = Self.virtualKeyCode(for: binding.key) else { return .unsupportedShortcut(binding.displayText) }

    let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id.rawValue)
    let status = RegisterEventHotKey(
      UInt32(keyCode), Self.carbonModifiers(for: binding.modifierFlags), hotKeyID, GetApplicationEventTarget(), 0,
      &target)

    if status == noErr { return .registered }

    if status == eventHotKeyExistsErr { return .conflict(binding.displayText) }

    return .registrationFailed(osStatusMessage(status))
  }

  static func validationFailure(for binding: ShortcutBinding) -> RegistrationStatus? {
    guard Self.virtualKeyCode(for: binding.key) != nil else { return .unsupportedShortcut(binding.displayText) }
    let required =
      NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue
      | NSEvent.ModifierFlags.control.rawValue
    return binding.modifierFlags & required == 0 ? .unsupportedShortcut(binding.displayText) : nil
  }

  private func handle(event: EventRef?) {
    guard let event else { return }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

    guard status == noErr, hotKeyID.signature == Self.hotKeySignature else { return }

    switch HotKeyID(rawValue: hotKeyID.id) {
    case .openPanel: onOpenClipboardPanel()
    case .stackCapture: onToggleStackCapture()
    case nil: break
    }
  }

  static func virtualKeyCode(for key: String) -> UInt16? {
    guard key.utf8.count == 1, var byte = key.utf8.first else { return nil }
    if byte >= 65, byte <= 90 { byte += 32 }

    switch byte {
    case 97: return UInt16(kVK_ANSI_A)
    case 98: return UInt16(kVK_ANSI_B)
    case 99: return UInt16(kVK_ANSI_C)
    case 100: return UInt16(kVK_ANSI_D)
    case 101: return UInt16(kVK_ANSI_E)
    case 102: return UInt16(kVK_ANSI_F)
    case 103: return UInt16(kVK_ANSI_G)
    case 104: return UInt16(kVK_ANSI_H)
    case 105: return UInt16(kVK_ANSI_I)
    case 106: return UInt16(kVK_ANSI_J)
    case 107: return UInt16(kVK_ANSI_K)
    case 108: return UInt16(kVK_ANSI_L)
    case 109: return UInt16(kVK_ANSI_M)
    case 110: return UInt16(kVK_ANSI_N)
    case 111: return UInt16(kVK_ANSI_O)
    case 112: return UInt16(kVK_ANSI_P)
    case 113: return UInt16(kVK_ANSI_Q)
    case 114: return UInt16(kVK_ANSI_R)
    case 115: return UInt16(kVK_ANSI_S)
    case 116: return UInt16(kVK_ANSI_T)
    case 117: return UInt16(kVK_ANSI_U)
    case 118: return UInt16(kVK_ANSI_V)
    case 119: return UInt16(kVK_ANSI_W)
    case 120: return UInt16(kVK_ANSI_X)
    case 121: return UInt16(kVK_ANSI_Y)
    case 122: return UInt16(kVK_ANSI_Z)
    case 48: return UInt16(kVK_ANSI_0)
    case 49: return UInt16(kVK_ANSI_1)
    case 50: return UInt16(kVK_ANSI_2)
    case 51: return UInt16(kVK_ANSI_3)
    case 52: return UInt16(kVK_ANSI_4)
    case 53: return UInt16(kVK_ANSI_5)
    case 54: return UInt16(kVK_ANSI_6)
    case 55: return UInt16(kVK_ANSI_7)
    case 56: return UInt16(kVK_ANSI_8)
    case 57: return UInt16(kVK_ANSI_9)
    case 44: return UInt16(kVK_ANSI_Comma)
    case 46: return UInt16(kVK_ANSI_Period)
    case 47: return UInt16(kVK_ANSI_Slash)
    case 59: return UInt16(kVK_ANSI_Semicolon)
    case 39: return UInt16(kVK_ANSI_Quote)
    case 91: return UInt16(kVK_ANSI_LeftBracket)
    case 93: return UInt16(kVK_ANSI_RightBracket)
    case 45: return UInt16(kVK_ANSI_Minus)
    case 61: return UInt16(kVK_ANSI_Equal)
    case 96: return UInt16(kVK_ANSI_Grave)
    default: return nil
    }
  }

  static func carbonModifiers(for modifierFlags: UInt) -> UInt32 {
    var carbonFlags: UInt32 = 0
    if modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0 { carbonFlags |= UInt32(cmdKey) }
    if modifierFlags & NSEvent.ModifierFlags.option.rawValue != 0 { carbonFlags |= UInt32(optionKey) }
    if modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0 { carbonFlags |= UInt32(controlKey) }
    if modifierFlags & NSEvent.ModifierFlags.shift.rawValue != 0 { carbonFlags |= UInt32(shiftKey) }
    return carbonFlags
  }

  private static let hotKeySignature: OSType = 0x436C_7042
  static let stackCaptureShortcut = ShortcutBinding(
    key: "c", modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue)

  private func osStatusMessage(_ status: OSStatus) -> String { "OSStatus \(status)" }
}
