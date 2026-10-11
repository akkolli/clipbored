import AppKit
import SwiftUI

// MARK: - Window and data operations

final class SettingsController: NSObject, NSWindowDelegate {
  static let allowedContentTypesValidationMessage = "At least one content type must stay enabled."
  static let allowedContentTypesUpdatedMessage = "Allowed content types updated."
  let settings: Preferences
  let store: HistoryStore
  let cacheService: MediaCache
  let cloudSyncService: ArchiveSyncing
  let form: SettingsFormState
  let dataOperationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "clipbored.settings.data-operations"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  var window: NSWindow?

  init(
    settings: Preferences, store: HistoryStore, cacheService: MediaCache,
    cloudSyncService: ArchiveSyncing = ArchiveSync()
  ) {
    self.settings = settings
    self.store = store
    self.cacheService = cacheService
    self.cloudSyncService = cloudSyncService
    self.form = SettingsFormState(settings: settings)
    super.init()
    form.action = { [weak self] action in
      guard let self else { return }
      switch action {
      case .export: self.exportClipboardArchive()
      case .import: self.importClipboardArchive()
      case .push: self.pushICloudSyncArchive()
      case .pull: self.pullICloudSyncArchive()
      case .revealCloud: self.revealICloudSyncFile()
      case .folder: self.openHistoryFolder()
      case .clearHistory: self.clearClipboardHistory()
      case .clearCache: self.clearThumbnailCache()
      case .permission: self.refreshAccessibilityPermissionStatus(prompt: true)
      case .refreshPermission: self.refreshAccessibilityPermissionStatus()
      case .refreshCloud: self.refreshCloudSyncControls(refreshStatus: true)
      }
    }
    settings.observe { [weak self] _ in DispatchQueue.main.async { self?.refreshFromSettings() } }
    let window = UI.window(
      "Goldfish Settings", size: NSSize(width: 620, height: 520), minimum: NSSize(width: 560, height: 440))
    UI.host(SettingsForm(model: form), in: window, delegate: self)
    self.window = window
    refreshFromSettings()
  }

  func show() {
    refreshFromSettings()
    UI.show(window)
  }
  func windowWillClose(_ notification: Notification) { commitPendingEditorDrafts() }
  func commitPendingEditorDrafts() { form.commit() }
  func refreshFromSettings() {
    form.refresh()
    refreshCloudSyncControls(refreshStatus: false)
  }
  func refreshCloudSyncControls(refreshStatus: Bool) {
    if !settings.iCloudSyncEnabled {
      form.cloudStatus = nil
    } else if refreshStatus || form.cloudStatus == nil {
      form.cloudStatus = cloudSyncService.status()
    }
  }
  func refreshAccessibilityPermissionStatus(prompt: Bool = false) {
    if prompt {
      _ = AccessibilityPermissionService.requestPromptIfNeeded()
      if !AccessibilityPermissionService.isTrusted { AccessibilityPermissionService.openSystemSettings() }
    }
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted ? "" : "Accessibility permission not granted.")
    form.refresh()
  }
  func setDataStatus(_ message: String) { form.dataStatus = message }
}

// MARK: - Drafts and preference bindings

final class SettingsFormState: ObservableObject {
  enum Action {
    case export, `import`, push, pull, revealCloud, folder, clearHistory, clearCache, permission, refreshPermission,
      refreshCloud
  }
  struct ShortcutDraft: Equatable {
    var key: String
    var flags: UInt
    init(_ binding: ShortcutBinding) {
      key = binding.key.uppercased()
      flags = binding.modifierFlags
    }
  }
  let settings: Preferences
  var action: ((Action) -> Void)?
  @Published var ignoredApps: String
  @Published var shortcuts: [ShortcutDraft]
  @Published var dataStatus = ""
  @Published var busy = false
  @Published var page = 0
  @Published var cloudStatus: ArchiveSyncStatus?
  private var savedApps: String
  private var savedShortcuts: [ShortcutDraft]

  init(settings: Preferences) {
    self.settings = settings
    savedApps = settings.ignoredApps.joined(separator: ", ")
    ignoredApps = savedApps
    savedShortcuts = [ShortcutDraft(settings.openShortcut), ShortcutDraft(settings.settingsShortcut)]
    shortcuts = savedShortcuts
  }
  func refresh() {
    let currentApps = settings.ignoredApps.joined(separator: ", ")
    if ignoredApps == savedApps { ignoredApps = currentApps }
    savedApps = currentApps
    let currentShortcuts = [ShortcutDraft(settings.openShortcut), ShortcutDraft(settings.settingsShortcut)]
    for index in shortcuts.indices {
      if shortcuts[index] == savedShortcuts[index] { shortcuts[index] = currentShortcuts[index] }
    }
    savedShortcuts = currentShortcuts
    objectWillChange.send()
  }
  func binding<Value>(_ key: ReferenceWritableKeyPath<Preferences, Value>, changed: (() -> Void)? = nil) -> Binding<
    Value
  > {
    Binding(
      get: { self.settings[keyPath: key] },
      set: {
        self.settings[keyPath: key] = $0
        changed?()
        self.objectWillChange.send()
      })
  }
  func commit() {
    if ignoredApps != savedApps {
      settings.ignoredApps = ignoredApps.split { $0 == "," || $0 == "\n" }.map { $0.clipboardTrimmed }.filter {
        !$0.isEmpty
      }
      savedApps = settings.ignoredApps.joined(separator: ", ")
      ignoredApps = savedApps
    }
    for index in shortcuts.indices where shortcuts[index] != savedShortcuts[index] { commitShortcut(index) }
  }
  func commitShortcut(_ index: Int) {
    let draft = shortcuts[index]
    let input = draft.key.clipboardTrimmed
    var key = input
    var explicitFlags: UInt = 0
    for (symbol, flag) in Self.modifiers where input.contains(symbol) {
      explicitFlags |= flag.rawValue
      key = key.replacingOccurrences(of: symbol, with: "")
    }
    key = key.clipboardTrimmed
    let updated = ShortcutBinding(key: key, modifierFlags: explicitFlags == 0 ? draft.flags : explicitFlags)
    let other = index == 0 ? settings.settingsShortcut : settings.openShortcut
    let error: String?
    if key.count != 1 {
      error =
        input.isEmpty
        ? "" : ShortcutManager.RegistrationStatus.unsupportedShortcut(key.isEmpty ? input : updated.displayText).message
    } else if let failure = ShortcutManager.validationFailure(for: updated) {
      error = failure.message
    } else if [other, ShortcutManager.stackCaptureShortcut].contains(updated) {
      error = ShortcutManager.RegistrationStatus.conflict(updated.displayText).message
    } else {
      error = nil
    }
    settings.setShortcutStatus(message: error ?? "")
    if error == nil { if index == 0 { settings.openShortcut = updated } else { settings.settingsShortcut = updated } }
    let current = index == 0 ? settings.openShortcut : settings.settingsShortcut
    shortcuts[index] = ShortcutDraft(current)
    savedShortcuts[index] = shortcuts[index]
  }
  static let modifiers: [(String, NSEvent.ModifierFlags)] = [
    ("⌘", .command), ("⌥", .option), ("⌃", .control), ("⇧", .shift),
  ]
}

// MARK: - Native forms

private struct SettingsForm: View {
  @ObservedObject var model: SettingsFormState
  @FocusState private var appsFocused: Bool
  private var settings: Preferences { model.settings }
  private let pages = ["General", "Shortcuts", "Capture", "Privacy", "Performance", "Data"]

  var body: some View {
    VStack {
      Picker("Settings page", selection: $model.page) { ForEach(pages.indices, id: \.self) { Text(pages[$0]).tag($0) } }
        .pickerStyle(.segmented).labelsHidden().padding([.horizontal, .top], 12)
      Form {
        switch model.page {
        case 0: general
        case 1: shortcuts
        case 2: capture
        case 3: privacy
        case 4: performance
        default: data
        }
      }.formStyle(.grouped)
    }.onChange(of: appsFocused) { if !$0 { model.commit() } }
  }
  private func toggle(_ title: String, _ key: ReferenceWritableKeyPath<Preferences, Bool>, changed: (() -> Void)? = nil)
    -> some View
  { Toggle(title, isOn: model.binding(key, changed: changed)) }
  private func picker<Value: RawRepresentable & CaseIterable & Hashable>(
    _ title: String, _ key: ReferenceWritableKeyPath<Preferences, Value>, label: @escaping (Value) -> String
  ) -> some View {
    Picker(title, selection: model.binding(key)) {
      ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
    }
  }
  private func status(_ value: SettingsController.StatusPresentation) -> some View {
    Text(value.message).font(.caption).foregroundColor(Color(nsColor: value.textColor)).fixedSize(
      horizontal: false, vertical: true)
  }
  private func button(_ title: String, _ action: SettingsFormState.Action) -> some View {
    Button(title) { model.action?(action) }
  }

  private var general: some View {
    Group {
      Section("History") {
        picker("Keep history", \.historyRetention) { $0.title }
        Stepper(
          "History length: \(settings.maxHistoryItems)", value: model.binding(\.maxHistoryItems),
          in: Configuration.minHistoryLength...Configuration.maxHistoryLength, step: 25)
        toggle("Ignore duplicate items", \.pruneDuplicates)
        toggle("Keep first image copy", \.keepFirstImage)
      }
      Section("Sort and panel") {
        picker("Default sort", \.defaultSortMode) { $0.title }
        picker("Shelf side", \.panelSide) { $0.title }
      }
      Section("Lifecycle") {
        toggle("Launch at login", \.launchAtLogin) {
          if !settings.launchAtLogin { settings.setLaunchAtLoginStatus(message: "") }
        }
        toggle("Show Goldfish in the menu bar", \.showMenuBarIcon) {
          if !settings.showMenuBarIcon && !settings.showDockIcon { settings.showDockIcon = true }
        }
        toggle("Show Goldfish in the Dock", \.showDockIcon) {
          if !settings.showMenuBarIcon && !settings.showDockIcon { settings.showMenuBarIcon = true }
        }
        status(SettingsController.launchAtLoginStatusPresentation(storedStatus: settings.launchAtLoginErrorMessage))
      }
    }
  }
  private var shortcuts: some View {
    Section("Shortcuts") {
      ShortcutEditor(model: model, index: 0, title: "Open Goldfish")
      ShortcutEditor(model: model, index: 1, title: "Open Settings")
      status(SettingsController.shortcutStatusPresentation(storedStatus: settings.shortcutStatusMessage))
      Text("Settings is local to the shelf. Stack capture uses Command-Shift-C.").font(.caption)
    }
  }
  private var capture: some View {
    Group {
      Section("Capture") {
        toggle("Pause clipboard capture", \.pauseCapture) { settings.pauseCaptureUntil = nil }
        toggle("Exclude likely secrets", \.excludeSensitive)
        toggle("Search in image labels", \.includeImageTextInSearch)
        status(SettingsController.captureStatusPresentation(storedStatus: settings.captureStatusMessage))
      }
      Section("Allowed content types") {
        ForEach(ClipKind.captureKinds, id: \.rawValue) { kind in
          Toggle(
            kind.displayName.capitalized,
            isOn: Binding(
              get: { !settings.ignoredItemKindsRaw.contains(kind.rawValue) },
              set: { allowed in
                var ignored = Set(settings.ignoredItemKindsRaw)
                if allowed { ignored.remove(kind.rawValue) } else { ignored.insert(kind.rawValue) }
                if Set(ClipKind.captureKinds.map(\.rawValue)).isSubset(of: ignored) {
                  settings.setCaptureStatus(message: SettingsController.allowedContentTypesValidationMessage)
                } else {
                  settings.ignoredItemKindsRaw = ignored.sorted()
                  if settings.captureStatusMessage == SettingsController.allowedContentTypesValidationMessage {
                    settings.setCaptureStatus(message: SettingsController.allowedContentTypesUpdatedMessage)
                  }
                }
                model.objectWillChange.send()
              }))
        }
      }
      Section("Ignored source apps") {
        TextEditor(text: $model.ignoredApps).focused($appsFocused).frame(height: 96).accessibilityLabel(
          "Ignored source apps")
        Text("Separate app names or bundle identifiers with commas or newlines.").font(.caption)
      }
    }
  }
  private var privacy: some View {
    Group {
      Section("Local storage") {
        Text("History and managed media are encrypted with a Keychain or owner-only fallback key.").font(.caption)
        toggle("Clear history on quit", \.clearHistoryOnQuit)
        toggle("Hide panel from screen sharing and recordings", \.hideFromScreenCapture)
      }
      Section("Paste permission") {
        Text("Capture works without Accessibility. Grant it for direct paste.").font(.caption)
        status(
          SettingsController.accessibilityPermissionStatusPresentation(
            storedStatus: settings.accessibilityPermissionStatusMessage,
            isTrusted: AccessibilityPermissionService.isTrusted))
        HStack {
          button("Open Accessibility Settings", .permission)
          button("Refresh Permission Status", .refreshPermission)
        }
        status(SettingsController.pasteStatusPresentation(storedStatus: settings.pasteStatusMessage))
      }
    }
  }
  private var performance: some View {
    Group {
      Section("Polling") { picker("Polling profile", \.pollProfileRaw) { $0.title } }
      Section("Thumbnail cache") {
        Slider(
          value: Binding(
            get: { Double(settings.imageCacheMaxBytes) / 1024 / 1024 },
            set: {
              settings.imageCacheMaxBytes = Int64($0 * 1024 * 1024)
              model.objectWillChange.send()
            }),
          in: Double(Configuration.minCacheMaxBytes) / 1024 / 1024...Double(Configuration.maxCacheMaxBytes) / 1024
            / 1024, step: 1)
        Text("Cache limit: \(settings.imageCacheMaxBytes / 1024 / 1024) MB").font(.caption)
      }
    }
  }
  private var data: some View {
    Group {
      Section("Archives") {
        Text("Archives are portable, unencrypted sensitive backups.").font(.caption)
        HStack {
          button("Export Archive…", .export)
          button("Import Archive…", .import)
        }.disabled(model.busy)
        status(SettingsController.dataStatusPresentation(storedStatus: model.dataStatus))
      }
      Section("iCloud") {
        toggle("Sync history with iCloud", \.iCloudSyncEnabled) { model.action?(.refreshCloud) }
        status(
          SettingsController.cloudSyncStatusPresentation(
            storedStatus: settings.cloudSyncStatusMessage, isSyncEnabled: settings.iCloudSyncEnabled,
            cloudStatus: model.cloudStatus))
        HStack {
          button("Sync Now", .push)
          button("Restore from iCloud", .pull)
          button("Reveal Sync File", .revealCloud)
        }.disabled(model.busy || !settings.iCloudSyncEnabled || model.cloudStatus?.isAvailable != true)
      }
      Section("Storage") {
        button("Open History Folder", .folder)
        HStack {
          button("Clear History", .clearHistory)
          button("Clear Thumbnail Cache", .clearCache)
        }
      }
    }
  }
}

private struct ShortcutEditor: View {
  @ObservedObject var model: SettingsFormState
  let index: Int
  let title: String
  @FocusState private var focused: Bool
  var body: some View {
    HStack {
      Text(title)
      TextField("Key", text: $model.shortcuts[index].key).frame(width: 70).focused($focused).onSubmit {
        model.commitShortcut(index)
      }.accessibilityLabel("\(title) shortcut key")
      ForEach(SettingsFormState.modifiers.indices, id: \.self) { offset in
        let (symbol, flag) = SettingsFormState.modifiers[offset]
        Toggle(
          symbol,
          isOn: Binding(
            get: { model.shortcuts[index].flags & flag.rawValue != 0 },
            set: {
              if $0 {
                model.shortcuts[index].flags |= flag.rawValue
              } else {
                model.shortcuts[index].flags &= ~flag.rawValue
              }
              model.commitShortcut(index)
            })
        ).toggleStyle(.button).accessibilityLabel("\(symbol) modifier for \(title)")
      }
    }.onChange(of: focused) { if !$0 { model.commitShortcut(index) } }
  }
}

// MARK: - SettingsController — Status

extension SettingsController {
  typealias StatusPresentation = (message: String, textColor: NSColor)
  typealias StatusRule = (color: NSColor, prefixes: [String], contains: [String])

  private static func status(
    _ stored: String, empty: String = "", emptyColor: NSColor = .secondaryLabelColor, rules: [StatusRule]
  ) -> StatusPresentation {
    let message = stored.clipboardTrimmed
    guard !message.isEmpty else { return (empty, emptyColor) }
    let folded = message.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    for rule in rules
    where rule.prefixes.contains(where: folded.hasPrefix) || rule.contains.contains(where: folded.contains) {
      return (message, rule.color)
    }
    return (message, .secondaryLabelColor)
  }

  static func launchAtLoginStatusPresentation(storedStatus: String) -> StatusPresentation {
    status(storedStatus, rules: [(.systemRed, [""], [])])
  }

  static func shortcutStatusPresentation(storedStatus: String) -> StatusPresentation {
    status(storedStatus, empty: "Registered", emptyColor: .systemGreen, rules: [(.systemRed, [""], [])])
  }

  static func captureStatusPresentation(storedStatus: String) -> StatusPresentation {
    status(
      storedStatus, empty: "Capture status will appear after the app sees clipboard activity.",
      rules: [
        (
          .systemGreen, ["captured", "allowed content types updated"],
          ["capture running", "capture is running", "capture resumed"]
        ), (.systemRed, ["error"], ["failed", "could not"]),
        (.systemOrange, ["skipped"], ["ignored", "paused", "at least one"]),
      ])
  }

  static func pasteStatusPresentation(storedStatus: String) -> StatusPresentation {
    status(
      storedStatus, empty: "No paste action yet.",
      rules: [
        (.systemRed, [], ["could not", "failed"]), (.systemOrange, [], ["grant accessibility", "not granted"]),
        (.systemGreen, ["pasted", "copied"], []),
      ])
  }

  static func dataStatusPresentation(storedStatus: String) -> StatusPresentation {
    status(
      storedStatus,
      rules: [
        (
          .systemRed, [],
          ["could not", "couldn", "denied", "error", "failed", "invalid", "missing", "not permitted", "unavailable"]
        ), (.systemOrange, [], ["skipped"]), (.systemGreen, ["exported", "imported", "cleared"], []),
      ])
  }

  static func accessibilityPermissionStatusPresentation(storedStatus: String, isTrusted: Bool) -> StatusPresentation {
    status(
      storedStatus,
      empty: isTrusted ? "Granted" : "Not granted (clipboard capture still works; paste falls back to copy)",
      emptyColor: isTrusted ? .systemGreen : .systemOrange, rules: [(.systemOrange, [""], [])])
  }

  static func cloudSyncStatusPresentation(storedStatus: String, isSyncEnabled: Bool, cloudStatus: ArchiveSyncStatus?)
    -> StatusPresentation
  {
    let fallback: StatusPresentation =
      !isSyncEnabled
      ? ("iCloud Sync is off.", .secondaryLabelColor)
      : cloudStatus.map { ($0.message, $0.isAvailable ? .secondaryLabelColor : .systemOrange) } ?? (
        "iCloud Sync is unavailable.", .systemOrange
      )
    return status(
      storedStatus, empty: fallback.message, emptyColor: fallback.textColor,
      rules: [
        (.systemRed, [], ["failed"]), (.systemOrange, [], ["unavailable", "turn on", "skipped"]),
        (.systemGreen, ["synced", "restored", "opened"], []),
      ])
  }
}

// MARK: - SettingsController — Data

extension SettingsController {
  func openHistoryFolder() { NSWorkspace.shared.open(HistoryStore.storageDirectory()) }

  func exportClipboardArchive() { transferArchive(importing: false) }
  func importClipboardArchive() { transferArchive(importing: true) }

  private func transferArchive(importing: Bool) {
    guard let url = UI.archiveURL(importing: importing) else { return }
    setDataStatus(importing ? "Importing archive…" : "Exporting archive…")
    performDataOperation({ [store] in
      Result { try importing ? store.importArchive(from: url) : store.exportArchive(to: url) }
    }) { [weak self] result in
      switch result {
      case .success(let summary):
        let verb = importing ? "Imported" : "Exported"
        self?.setDataStatus(
          "\(verb) \(summary.itemCount) clips and \(summary.sidecarCount) attachments."
            + (importing ? Self.skippedSummary(summary) : ""))
      case .failure(let error): self?.setDataStatus(error.localizedDescription)
      }
    }
  }

  func pushICloudSyncArchive() { syncArchive(restoring: false) }
  func pullICloudSyncArchive() { syncArchive(restoring: true) }

  private func syncArchive(restoring: Bool) {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Sync before \(restoring ? "restoring" : "syncing").")
      return
    }
    settings.setCloudSyncStatus(message: restoring ? "Restoring from iCloud…" : "Syncing with iCloud…")
    performDataOperation({ [cloudSyncService, store] in
      Result {
        let summary = try restoring ? cloudSyncService.pull(store: store) : cloudSyncService.push(store: store)
        return (summary, cloudSyncService.status())
      }
    }) { [weak self] result in
      switch result {
      case .success(let (summary, status)):
        self?.form.cloudStatus = status
        let verb = restoring ? "Restored" : "Synced"
        let direction = restoring ? "from" : "to"
        var message = "\(verb) \(summary.itemCount) clips and \(summary.sidecarCount) attachments \(direction) iCloud."
        if restoring { message += Self.skippedSummary(summary) }
        self?.settings.setCloudSyncStatus(message: message)
      case .failure(let error):
        self?.settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
      }
    }
  }

  private static func skippedSummary(_ summary: ArchiveSummary) -> String {
    guard summary.skippedItemCount > 0 || summary.skippedSidecarCount > 0 else { return "" }
    return " Skipped \(summary.skippedItemCount) clips and \(summary.skippedSidecarCount) attachments."
  }

  private func performDataOperation<ResultValue>(
    _ operation: @escaping () -> ResultValue, completion: @escaping (ResultValue) -> Void
  ) {
    form.busy = true
    refreshCloudSyncControls(refreshStatus: false)
    dataOperationQueue.addOperation { [weak self] in
      let result = operation()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.form.busy = false
        completion(result)
        self.refreshCloudSyncControls(refreshStatus: false)
      }
    }
  }

  func revealICloudSyncFile() {
    do {
      let url = try cloudSyncService.syncArchiveURL()
      if FileManager.default.fileExists(atPath: url.path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } else {
        NSWorkspace.shared.open(url.deletingLastPathComponent())
      }
      form.cloudStatus = cloudSyncService.status()
      settings.setCloudSyncStatus(message: "Opened iCloud sync location.")
    } catch { settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)") }
  }

  func clearClipboardHistory() {
    guard
      confirmDestructiveAction(
        title: "Clear Clipboard History?",
        message:
          "This permanently removes saved clipboard items, app-managed attachments, temporary decrypted previews, and the local fallback encryption key when present. The current system clipboard is not changed.",
        buttonTitle: "Clear History")
    else { return }
    store.removeAll()
    cacheService.clearTemporaryPreviews()
    setDataStatus("Cleared clipboard history.")
  }

  func clearThumbnailCache() {
    guard
      confirmDestructiveAction(
        title: "Clear Thumbnail Cache?",
        message:
          "This removes cached image previews and temporary decrypted previews. Goldfish will recreate previews as needed.",
        buttonTitle: "Clear Cache")
    else { return }
    cacheService.clearCache()
    setDataStatus("Cleared thumbnail cache.")
  }

  private func confirmDestructiveAction(title: String, message: String, buttonTitle: String) -> Bool {
    let alert = UI.alert(title, message: message, action: buttonTitle, warning: true)
    return alert.runModal() == .alertFirstButtonReturn
  }

}
