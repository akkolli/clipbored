import AppKit

final class SettingsWindowController: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
  private let settings: SettingsModel
  private let store: ClipboardStore
  private let cacheService: ClipboardCacheService
  private var window: NSWindow?

  private let historyLabel = NSTextField(labelWithString: "")
  private let historyStepper = NSStepper()
  private let pruneDuplicatesButton = NSButton()
  private let keepFirstImageButton = NSButton()
  private let defaultSortPopup = NSPopUpButton()
  private let launchAtLoginButton = NSButton()
  private let showMenuBarIconButton = NSButton()
  private let showDockIconButton = NSButton()
  private let launchStatusLabel = NSTextField(labelWithString: "")

  private var openShortcutControls: ShortcutControlSet?
  private var settingsShortcutControls: ShortcutControlSet?
  private let shortcutStatusLabel = NSTextField(labelWithString: "")

  private let pauseCaptureButton = NSButton()
  private let captureStatusLabel = NSTextField(labelWithString: "")
  private let excludeSensitiveButton = NSButton()
  private let includeImageTextButton = NSButton()
  private var allowedKindButtons: [(ClipboardItemKind, NSButton)] = []
  private let ignoredAppsTextView = NSTextView()

  private let clearHistoryOnQuitButton = NSButton()
  private let accessibilityStatusLabel = NSTextField(labelWithString: "")
  private let pasteStatusLabel = NSTextField(labelWithString: "")

  private let pollProfilePopup = NSPopUpButton()
  private let cacheSlider = NSSlider()
  private let cacheLabel = NSTextField(labelWithString: "")

  init(settings: SettingsModel, store: ClipboardStore, cacheService: ClipboardCacheService) {
    self.settings = settings
    self.store = store
    self.cacheService = cacheService
    super.init()

    let windowRect = NSRect(x: 0, y: 0, width: 620, height: 560)
    let window = NSWindow(
      contentRect: windowRect,
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "ClipBored Settings"
    window.contentView = makeContentView()
    window.isReleasedWhenClosed = false
    window.center()
    self.window = window
    settings.observe { [weak self] _ in
      DispatchQueue.main.async {
        self?.refreshFromSettings()
      }
    }
    refreshFromSettings()
  }

  func show() {
    guard let window else { return }
    refreshFromSettings()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeContentView() -> NSView {
    let tabView = NSTabView()
    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.addTabViewItem(tab("General", generalSettingsView()))
    tabView.addTabViewItem(tab("Shortcuts", shortcutSettingsView()))
    tabView.addTabViewItem(tab("Capture", captureSettingsView()))
    tabView.addTabViewItem(tab("Privacy", privacySettingsView()))
    tabView.addTabViewItem(tab("Performance", performanceSettingsView()))
    tabView.addTabViewItem(tab("Data", dataSettingsView()))

    let container = NSView()
    container.addSubview(tabView)
    NSLayoutConstraint.activate([
      tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
      tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
      tabView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
      tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
    ])
    return container
  }

  private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
    let item = NSTabViewItem(identifier: title)
    item.label = title
    item.view = scrollContainer(for: view)
    return item
  }

  private func scrollContainer(for content: NSView) -> NSView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.documentView = content
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
    ])
    return scrollView
  }

  private func generalSettingsView() -> NSView {
    historyStepper.minValue = Double(AppConfiguration.minHistoryLength)
    historyStepper.maxValue = Double(AppConfiguration.maxHistoryLength)
    historyStepper.increment = 25
    historyStepper.target = self
    historyStepper.action = #selector(historyLengthChanged)
    historyStepper.setAccessibilityLabel("History length")

    configureCheckbox(pruneDuplicatesButton, title: "Ignore duplicate items", action: #selector(pruneDuplicatesChanged))
    configureCheckbox(keepFirstImageButton, title: "Keep first image copy", action: #selector(keepFirstImageChanged))
    configurePopup(defaultSortPopup, action: #selector(defaultSortChanged))
    defaultSortPopup.setAccessibilityLabel("Default sort")
    for mode in ClipboardSortMode.allCases {
      addPopupItem(mode.title, mode.rawValue, to: defaultSortPopup)
    }
    configureCheckbox(launchAtLoginButton, title: "Launch at login", action: #selector(launchAtLoginChanged))
    configureCheckbox(showMenuBarIconButton, title: "Show ClipBored in the menu bar", action: #selector(showMenuBarIconChanged))
    configureCheckbox(showDockIconButton, title: "Show ClipBored in the Dock", action: #selector(showDockIconChanged))
    configureStatusLabel(launchStatusLabel)

    return page([
      section("History", [
        row([historyLabel, historyStepper]),
        pruneDuplicatesButton,
        keepFirstImageButton
      ]),
      section("Sort", [
        labeledRow("Default sort", defaultSortPopup)
      ]),
      section("Lifecycle", [
        launchAtLoginButton,
        showMenuBarIconButton,
        showDockIconButton,
        launchStatusLabel
      ])
    ])
  }

  private func shortcutSettingsView() -> NSView {
    let openRow = shortcutRow("Open Clipboard", binding: settings.openShortcut, baseTag: 100)
    let settingsRow = shortcutRow("Open Settings", binding: settings.settingsShortcut, baseTag: 200)
    configureStatusLabel(shortcutStatusLabel)
    return page([
      section("Shortcuts", [
        openRow,
        settingsRow,
        shortcutStatusLabel
      ])
    ])
  }

  private func captureSettingsView() -> NSView {
    configureCheckbox(pauseCaptureButton, title: "Pause clipboard capture", action: #selector(pauseCaptureChanged))
    configureCheckbox(excludeSensitiveButton, title: "Exclude likely secrets", action: #selector(excludeSensitiveChanged))
    configureCheckbox(includeImageTextButton, title: "Search in image labels", action: #selector(includeImageTextChanged))
    configureStatusLabel(captureStatusLabel)

    let allowedRows = [
      kindCheckbox("Text", .text),
      kindCheckbox("Links", .url),
      kindCheckbox("Images", .image),
      kindCheckbox("Colors", .color),
      kindCheckbox("Audio", .audio),
      kindCheckbox("Rich text", .richText),
      kindCheckbox("PDFs", .pdf),
      kindCheckbox("Files", .file)
    ]

    ignoredAppsTextView.delegate = self
    ignoredAppsTextView.font = .systemFont(ofSize: NSFont.systemFontSize)
    ignoredAppsTextView.setAccessibilityLabel("Ignored source apps")
    let ignoredScroll = NSScrollView()
    ignoredScroll.hasVerticalScroller = true
    ignoredScroll.borderType = .bezelBorder
    ignoredScroll.documentView = ignoredAppsTextView
    ignoredScroll.heightAnchor.constraint(equalToConstant: 96).isActive = true

    return page([
      section("Capture", [
        pauseCaptureButton,
        excludeSensitiveButton,
        includeImageTextButton,
        captureStatusLabel
      ]),
      section("Allowed content types", allowedRows),
      section("Ignored source apps", [
        ignoredScroll
      ])
    ])
  }

  private func privacySettingsView() -> NSView {
    let storageLabel = caption("Clipboard history is stored locally in Application Support. Text, image cache files, audio clips, and PDF attachments are encrypted with Keychain when available, or an owner-only local fallback key if needed.")
    let permissionHelpLabel = caption("Clipboard history capture works without this permission. Grant Accessibility to paste selected items into the previous app.")
    configureCheckbox(clearHistoryOnQuitButton, title: "Clear history on quit", action: #selector(clearHistoryOnQuitChanged))
    configureStatusLabel(accessibilityStatusLabel)
    let requestButton = button("Open Accessibility Settings", #selector(requestAccessibilityAccess))
    let refreshButton = button("Refresh Permission Status", #selector(refreshAccessibilityPermissionStatus))
    configureStatusLabel(pasteStatusLabel)

    return page([
      section("Local storage", [
        storageLabel,
        clearHistoryOnQuitButton
      ]),
      section("Paste permission", [
        permissionHelpLabel,
        row([NSTextField(labelWithString: "Accessibility"), accessibilityStatusLabel]),
        row([requestButton, refreshButton])
      ]),
      section("Paste status", [
        pasteStatusLabel
      ])
    ])
  }

  private func performanceSettingsView() -> NSView {
    configurePopup(pollProfilePopup, action: #selector(pollProfileChanged))
    pollProfilePopup.setAccessibilityLabel("Polling profile")
    for profile in AppConfiguration.PollProfile.allCases {
      addPopupItem(profile.title, profile.rawValue, to: pollProfilePopup)
    }
    cacheSlider.minValue = 4
    cacheSlider.maxValue = 512
    cacheSlider.numberOfTickMarks = 9
    cacheSlider.allowsTickMarkValuesOnly = true
    cacheSlider.target = self
    cacheSlider.action = #selector(cacheLimitChanged)
    cacheSlider.setAccessibilityLabel("Image cache cap in megabytes")
    configureStatusLabel(cacheLabel)

    return page([
      section("Polling", [
        labeledRow("Polling profile", pollProfilePopup)
      ]),
      section("Cache", [
        labeledRow("Image cache cap (MB)", cacheSlider),
        cacheLabel
      ])
    ])
  }

  private func dataSettingsView() -> NSView {
    page([
      section("Data", [
        button("Open History Folder", #selector(openHistoryFolder)),
        button("Clear Clipboard History", #selector(clearClipboardHistory)),
        button("Clear Thumbnail Cache", #selector(clearThumbnailCache))
      ])
    ])
  }

  private func page(_ views: [NSView]) -> NSView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    return stack
  }

  private func section(_ title: String, _ views: [NSView]) -> NSView {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    let stack = NSStackView(views: [titleLabel] + views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
    return stack
  }

  private func row(_ views: [NSView]) -> NSView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 10
    return stack
  }

  private func labeledRow(_ title: String, _ control: NSView) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.widthAnchor.constraint(equalToConstant: 150).isActive = true
    return row([label, control])
  }

  private func caption(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
    return label
  }

  private func button(_ title: String, _ action: Selector) -> NSButton {
    let control = NSButton(title: title, target: self, action: action)
    control.bezelStyle = .rounded
    control.setAccessibilityLabel(title)
    return control
  }

  private func configureCheckbox(_ control: NSButton, title: String, action: Selector) {
    control.setButtonType(.switch)
    control.title = title
    control.target = self
    control.action = action
    control.setAccessibilityLabel(title)
  }

  private func configureStatusLabel(_ label: NSTextField) {
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.lineBreakMode = .byTruncatingTail
  }

  private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
    popup.removeAllItems()
    popup.target = self
    popup.action = action
  }

  private func addPopupItem(_ title: String, _ rawValue: Int, to popup: NSPopUpButton) {
    popup.addItem(withTitle: title)
    popup.lastItem?.representedObject = rawValue
  }

  private func kindCheckbox(_ title: String, _ kind: ClipboardItemKind) -> NSButton {
    let control = NSButton()
    configureCheckbox(control, title: title, action: #selector(allowedKindChanged(_:)))
    control.tag = kind.rawValue
    allowedKindButtons.append((kind, control))
    return control
  }

  private func shortcutRow(_ title: String, binding: ShortcutBinding, baseTag: Int) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.widthAnchor.constraint(equalToConstant: 120).isActive = true

    let keyField = NSTextField(string: binding.key.uppercased())
    keyField.placeholderString = "Key"
    keyField.alignment = .center
    keyField.delegate = self
    keyField.target = self
    keyField.action = #selector(shortcutChanged(_:))
    keyField.tag = baseTag
    keyField.setAccessibilityLabel("\(title) shortcut key")
    keyField.widthAnchor.constraint(equalToConstant: 56).isActive = true

    let command = modifierButton("⌘", baseTag + 1)
    let option = modifierButton("⌥", baseTag + 2)
    let control = modifierButton("⌃", baseTag + 3)
    let shift = modifierButton("⇧", baseTag + 4)
    let controls = ShortcutControlSet(keyField: keyField, command: command, option: option, control: control, shift: shift)
    if baseTag == 100 {
      openShortcutControls = controls
    } else {
      settingsShortcutControls = controls
    }

    return row([label, keyField, command, option, control, shift])
  }

  private func modifierButton(_ title: String, _ tag: Int) -> NSButton {
    let control = NSButton()
    configureCheckbox(control, title: title, action: #selector(shortcutChanged(_:)))
    control.toolTip = modifierTooltip(title)
    control.tag = tag
    return control
  }

  private func modifierTooltip(_ title: String) -> String {
    switch title {
    case "⌘": return "Command"
    case "⌥": return "Option"
    case "⌃": return "Control"
    case "⇧": return "Shift"
    default: return title
    }
  }

  private func refreshFromSettings() {
    historyLabel.stringValue = "History length: \(settings.maxHistoryItems)"
    historyStepper.integerValue = settings.maxHistoryItems
    pruneDuplicatesButton.state = settings.pruneDuplicates ? .on : .off
    keepFirstImageButton.state = settings.keepFirstImage ? .on : .off
    select(defaultSortPopup, rawValue: settings.defaultSortMode.rawValue)
    launchAtLoginButton.state = settings.launchAtLogin ? .on : .off
    showMenuBarIconButton.state = settings.showMenuBarIcon ? .on : .off
    showDockIconButton.state = settings.showDockIcon ? .on : .off
    launchStatusLabel.stringValue = settings.launchAtLoginErrorMessage

    refreshShortcutControls(openShortcutControls, binding: settings.openShortcut)
    refreshShortcutControls(settingsShortcutControls, binding: settings.settingsShortcut)
    shortcutStatusLabel.stringValue = settings.shortcutStatusMessage.isEmpty ? "Registered" : settings.shortcutStatusMessage

    pauseCaptureButton.state = settings.pauseCapture ? .on : .off
    captureStatusLabel.stringValue = settings.captureStatusMessage.isEmpty ? "Capture status will appear after the app sees clipboard activity." : settings.captureStatusMessage
    excludeSensitiveButton.state = settings.excludeSensitive ? .on : .off
    includeImageTextButton.state = settings.includeImageTextInSearch ? .on : .off
    for (kind, button) in allowedKindButtons {
      button.state = settings.ignoredItemKindsRaw.contains(kind.rawValue) ? .off : .on
    }
    let ignoredAppsText = settings.ignoredApps.joined(separator: ", ")
    if ignoredAppsTextView.string != ignoredAppsText {
      ignoredAppsTextView.string = ignoredAppsText
    }

    clearHistoryOnQuitButton.state = settings.clearHistoryOnQuit ? .on : .off
    let hasAccessibilityPermission = AccessibilityPermissionService.isTrusted
    let permissionStatus = hasAccessibilityPermission
      ? "Granted"
      : "Not granted (clipboard capture still works; paste falls back to copy)"
    accessibilityStatusLabel.stringValue = permissionStatus
    accessibilityStatusLabel.textColor = hasAccessibilityPermission ? .systemGreen : .systemOrange
    pasteStatusLabel.stringValue = settings.pasteStatusMessage.isEmpty ? "No paste action yet." : settings.pasteStatusMessage

    select(pollProfilePopup, rawValue: settings.pollProfileRaw.rawValue)
    cacheSlider.doubleValue = Double(settings.imageCacheMaxBytes) / 1024 / 1024
    cacheLabel.stringValue = "Current cache cap: \(Int(cacheSlider.doubleValue)) MB"
  }

  private func refreshShortcutControls(_ controls: ShortcutControlSet?, binding: ShortcutBinding) {
    guard let controls else { return }
    controls.keyField.stringValue = binding.key.uppercased()
    controls.command.state = binding.has(.command) ? .on : .off
    controls.option.state = binding.has(.option) ? .on : .off
    controls.control.state = binding.has(.control) ? .on : .off
    controls.shift.state = binding.has(.shift) ? .on : .off
  }

  private func select(_ popup: NSPopUpButton, rawValue: Int) {
    for item in popup.itemArray where item.representedObject as? Int == rawValue {
      popup.select(item)
      return
    }
  }

  @objc private func historyLengthChanged() {
    settings.maxHistoryItems = historyStepper.integerValue
    historyLabel.stringValue = "History length: \(settings.maxHistoryItems)"
  }

  @objc private func pruneDuplicatesChanged() {
    settings.pruneDuplicates = pruneDuplicatesButton.state == .on
  }

  @objc private func keepFirstImageChanged() {
    settings.keepFirstImage = keepFirstImageButton.state == .on
  }

  @objc private func defaultSortChanged() {
    if let rawValue = defaultSortPopup.selectedItem?.representedObject as? Int,
       let mode = ClipboardSortMode(rawValue: rawValue) {
      settings.defaultSortMode = mode
    }
  }

  @objc private func launchAtLoginChanged() {
    settings.launchAtLogin = launchAtLoginButton.state == .on
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.refreshFromSettings()
    }
  }

  @objc private func showMenuBarIconChanged() {
    let shouldShowMenuBarIcon = showMenuBarIconButton.state == .on
    settings.showMenuBarIcon = shouldShowMenuBarIcon
    if !shouldShowMenuBarIcon && !settings.showDockIcon {
      settings.showDockIcon = true
    }
  }

  @objc private func showDockIconChanged() {
    let shouldShowDockIcon = showDockIconButton.state == .on
    settings.showDockIcon = shouldShowDockIcon
    if !shouldShowDockIcon && !settings.showMenuBarIcon {
      settings.showMenuBarIcon = true
    }
  }

  @objc private func shortcutChanged(_ sender: NSControl) {
    let isOpenShortcut = sender.tag < 200
    let controls = isOpenShortcut ? openShortcutControls : settingsShortcutControls
    guard let controls else { return }

    let current = isOpenShortcut ? settings.openShortcut : settings.settingsShortcut
    let parsed = parseShortcut(controls.keyField.stringValue)
    var flags = NSEvent.ModifierFlags(rawValue: parsed?.modifierFlags ?? current.modifierFlags)
    setFlag(&flags, .command, controls.command.state == .on || parsed?.has(.command) == true)
    setFlag(&flags, .option, controls.option.state == .on || parsed?.has(.option) == true)
    setFlag(&flags, .control, controls.control.state == .on || parsed?.has(.control) == true)
    setFlag(&flags, .shift, controls.shift.state == .on || parsed?.has(.shift) == true)

    let key = parsed?.key ?? String(controls.keyField.stringValue.clipboardTrimmed.prefix(1)).lowercased()
    guard !key.isEmpty else {
      refreshFromSettings()
      return
    }

    let updated = ShortcutBinding(key: key, modifierFlags: flags.rawValue)
    if isOpenShortcut {
      settings.openShortcut = updated
    } else {
      settings.settingsShortcut = updated
    }
    refreshFromSettings()
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, field.tag == 100 || field.tag == 200 else { return }
    shortcutChanged(field)
  }

  @objc private func pauseCaptureChanged() {
    settings.pauseCapture = pauseCaptureButton.state == .on
  }

  @objc private func excludeSensitiveChanged() {
    settings.excludeSensitive = excludeSensitiveButton.state == .on
  }

  @objc private func includeImageTextChanged() {
    settings.includeImageTextInSearch = includeImageTextButton.state == .on
  }

  @objc private func allowedKindChanged(_ sender: NSButton) {
    guard let kind = ClipboardItemKind(rawValue: sender.tag) else { return }
    var ignored = settings.ignoredItemKindsRaw
    if sender.state == .on {
      ignored.removeAll { $0 == kind.rawValue }
    } else if !ignored.contains(kind.rawValue) {
      ignored.append(kind.rawValue)
    }
    settings.ignoredItemKindsRaw = ignored
  }

  func textDidChange(_ notification: Notification) {
    guard notification.object as? NSTextView === ignoredAppsTextView else { return }
    settings.ignoredApps = ignoredAppsTextView.string
      .split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.clipboardTrimmed }
      .filter { !$0.isEmpty }
  }

  @objc private func clearHistoryOnQuitChanged() {
    settings.clearHistoryOnQuit = clearHistoryOnQuitButton.state == .on
  }

  @objc private func requestAccessibilityAccess() {
    _ = AccessibilityPermissionService.requestPromptIfNeeded()
    if !AccessibilityPermissionService.isTrusted {
      AccessibilityPermissionService.openSystemSettings()
    }
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted ? "" : "Accessibility permission not granted."
    )
    refreshAccessibilityPermissionStatus()
  }

  @objc private func refreshAccessibilityPermissionStatus() {
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted
      ? ""
      : "Accessibility permission not granted."
    )
    refreshFromSettings()
  }

  @objc private func pollProfileChanged() {
    if let rawValue = pollProfilePopup.selectedItem?.representedObject as? Int,
       let profile = AppConfiguration.PollProfile(rawValue: rawValue) {
      settings.pollProfileRaw = profile
    }
  }

  @objc private func cacheLimitChanged() {
    settings.imageCacheMaxBytes = Int64(cacheSlider.doubleValue * 1024 * 1024)
    cacheLabel.stringValue = "Current cache cap: \(Int(cacheSlider.doubleValue)) MB"
  }

  @objc private func openHistoryFolder() {
    NSWorkspace.shared.open(ClipboardStore.storageDirectory())
  }

  @objc private func clearClipboardHistory() {
    guard confirmDestructiveAction(
      title: "Clear Clipboard History?",
      message: "This permanently removes saved clipboard items, app-managed attachments, temporary decrypted previews, and the local fallback encryption key when present. The current system clipboard is not changed.",
      buttonTitle: "Clear History"
    ) else { return }
    store.removeAll()
    cacheService.clearTemporaryPreviews()
  }

  @objc private func clearThumbnailCache() {
    guard confirmDestructiveAction(
      title: "Clear Thumbnail Cache?",
      message: "This removes cached image previews and temporary decrypted previews. ClipBored will recreate previews as needed.",
      buttonTitle: "Clear Cache"
    ) else { return }
    cacheService.clearCache()
  }

  private func confirmDestructiveAction(title: String, message: String, buttonTitle: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: buttonTitle)
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func setFlag(_ flags: inout NSEvent.ModifierFlags, _ flag: NSEvent.ModifierFlags, _ enabled: Bool) {
    if enabled {
      flags.insert(flag)
    } else {
      flags.remove(flag)
    }
  }

  private func parseShortcut(_ text: String) -> ShortcutBinding? {
    let cleaned = text.clipboardTrimmed
    if cleaned.isEmpty { return nil }

    var flags = NSEvent.ModifierFlags()
    if cleaned.contains("⌘") { flags.insert(.command) }
    if cleaned.contains("⌥") { flags.insert(.option) }
    if cleaned.contains("⌃") { flags.insert(.control) }
    if cleaned.contains("⇧") { flags.insert(.shift) }

    let plain = cleaned.replacingOccurrences(of: "⌘", with: "")
      .replacingOccurrences(of: "⌥", with: "")
      .replacingOccurrences(of: "⌃", with: "")
      .replacingOccurrences(of: "⇧", with: "")
      .clipboardTrimmed

    guard let key = plain.first else { return nil }
    return ShortcutBinding(key: String(key), modifierFlags: flags.rawValue)
  }
}

private struct ShortcutControlSet {
  let keyField: NSTextField
  let command: NSButton
  let option: NSButton
  let control: NSButton
  let shift: NSButton
}
