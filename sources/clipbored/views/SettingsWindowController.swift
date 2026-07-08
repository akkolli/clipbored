import AppKit

private final class TopAlignedSettingsDocumentView: NSView {
  override var isFlipped: Bool {
    true
  }
}

final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate {
  private enum Metrics {
    static let windowSize = NSSize(width: 720, height: 620)
    static let minimumWindowSize = NSSize(width: 620, height: 560)
    static let settingsContentMinimumWidth: CGFloat = 520
    static let settingsLabelWidth: CGFloat = 150
  }
  private static let allowedContentTypesValidationMessage = "At least one content type must stay enabled."
  private static let allowedContentTypesUpdatedMessage = "Allowed content types updated."

  private let settings: SettingsModel
  private let store: ClipboardStore
  private let cacheService: ClipboardCacheService
  private let cloudSyncService: ClipboardCloudSyncServicing
  private var window: NSWindow?
  private var cachedCloudSyncStatus: ClipboardCloudSyncStatus?
  private let tabView = NSTabView()

  private let historyLabel = NSTextField(labelWithString: "")
  private let historyStepper = NSStepper()
  private let historyRetentionPopup = NSPopUpButton()
  private let pruneDuplicatesButton = NSButton()
  private let keepFirstImageButton = NSButton()
  private let defaultSortPopup = NSPopUpButton()
  private let launchAtLoginButton = NSButton()
  private let showMenuBarIconButton = NSButton()
  private let showDockIconButton = NSButton()
  private let panelSidePopup = NSPopUpButton()
  private let launchStatusLabel = NSTextField(labelWithString: "")

  private var openShortcutControls: ShortcutControlSet?
  private var settingsShortcutControls: ShortcutControlSet?
  private var editingShortcutFieldTag: Int?
  private let shortcutStatusLabel = NSTextField(labelWithString: "")

  private let pauseCaptureButton = NSButton()
  private let captureStatusLabel = NSTextField(labelWithString: "")
  private let excludeSensitiveButton = NSButton()
  private let includeImageTextButton = NSButton()
  private var allowedKindButtons: [(ClipboardItemKind, NSButton)] = []
  private let ignoredAppsTextView = NSTextView()
  private var ignoredAppsEditorIsEditing = false
  private var ignoredAppsEditorHasDraft = false

  private let clearHistoryOnQuitButton = NSButton()
  private let hideFromScreenCaptureButton = NSButton()
  private let accessibilityStatusLabel = NSTextField(labelWithString: "")
  private let pasteStatusLabel = NSTextField(labelWithString: "")

  private let pollProfilePopup = NSPopUpButton()
  private let cacheSlider = NSSlider()
  private let cacheLabel = NSTextField(labelWithString: "")
  private let dataStatusLabel = NSTextField(labelWithString: "")
  private let iCloudSyncButton = NSButton()
  private let iCloudSyncNowButton = NSButton()
  private let iCloudRestoreButton = NSButton()
  private let iCloudRevealButton = NSButton()
  private let cloudSyncStatusLabel = NSTextField(labelWithString: "")

  #if DEBUG
  private var debugFullRefreshCountValue = 0
  private var debugIgnoredAppsRefreshCountValue = 0
  private var debugDestructiveActionConfirmationOverride: Bool?
  #endif

  init(
    settings: SettingsModel,
    store: ClipboardStore,
    cacheService: ClipboardCacheService,
    cloudSyncService: ClipboardCloudSyncServicing = ClipboardCloudSyncService()
  ) {
    self.settings = settings
    self.store = store
    self.cacheService = cacheService
    self.cloudSyncService = cloudSyncService
    super.init()

    let windowRect = NSRect(origin: .zero, size: Metrics.windowSize)
    let window = NSWindow(
      contentRect: windowRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "ClipBored Settings"
    window.contentView = makeContentView()
    window.isReleasedWhenClosed = false
    window.minSize = Metrics.minimumWindowSize
    window.delegate = self
    window.center()
    self.window = window
    settings.observe { [weak self] change in
      DispatchQueue.main.async {
        self?.refreshFromSettings(for: change)
      }
    }
    refreshFromSettings(refreshCloudSyncStatus: true)
  }

  func show() {
    guard let window else { return }
    refreshFromSettings(refreshCloudSyncStatus: true)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    commitPendingEditorDrafts()
  }

  private func makeContentView() -> NSView {
    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.addTabViewItem(tab("General", generalSettingsView()))
    tabView.addTabViewItem(tab("Shortcuts", shortcutSettingsView()))
    tabView.addTabViewItem(tab("Capture", captureSettingsView()))
    tabView.addTabViewItem(tab("Privacy", privacySettingsView()))
    tabView.addTabViewItem(tab("Performance", performanceSettingsView()))
    tabView.addTabViewItem(tab("Data  ", dataSettingsView()))

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

  private func tabTitle(for item: NSTabViewItem) -> String {
    item.label.clipboardTrimmed
  }

  private func scrollContainer(for content: NSView) -> NSView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let documentView = TopAlignedSettingsDocumentView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(content)
    scrollView.documentView = documentView
    NSLayoutConstraint.activate([
      documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
      documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
      documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
      documentView.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
      documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
      content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      content.topAnchor.constraint(equalTo: documentView.topAnchor),
      content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
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
    configurePopup(historyRetentionPopup, action: #selector(historyRetentionChanged))
    historyRetentionPopup.setAccessibilityLabel("Keep history")
    for retention in HistoryRetention.allCases {
      addPopupItem(retention.title, retention.rawValue, to: historyRetentionPopup)
    }

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
    configurePopup(panelSidePopup, action: #selector(panelSideChanged))
    panelSidePopup.setAccessibilityLabel("Shelf side")
    for side in ClipboardPanelSide.allCases {
      addPopupItem(side.title, side.rawValue, to: panelSidePopup)
    }
    configureStatusLabel(launchStatusLabel)

    return page([
      section("History", [
        labeledRow("Keep History", historyRetentionPopup),
        row([historyLabel, historyStepper]),
        pruneDuplicatesButton,
        keepFirstImageButton
      ]),
      section("Sort", [
        labeledRow("Default sort", defaultSortPopup)
      ]),
      section("Panel", [
        labeledRow("Shelf side", panelSidePopup)
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
      kindCheckbox("Code", .code),
      kindCheckbox("Links", .url),
      kindCheckbox("Images", .image),
      kindCheckbox("Colors", .color),
      kindCheckbox("Audio", .audio),
      kindCheckbox("Videos", .video),
      kindCheckbox("Rich text", .richText),
      kindCheckbox("PDFs", .pdf),
      kindCheckbox("Files", .file)
    ]

    ignoredAppsTextView.delegate = self
    ignoredAppsTextView.font = .systemFont(ofSize: NSFont.systemFontSize)
    ignoredAppsTextView.isHorizontallyResizable = false
    ignoredAppsTextView.isVerticallyResizable = true
    ignoredAppsTextView.autoresizingMask = [.width]
    ignoredAppsTextView.textContainer?.widthTracksTextView = true
    ignoredAppsTextView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    ignoredAppsTextView.setAccessibilityLabel("Ignored source apps")
    let ignoredScroll = NSScrollView()
    ignoredScroll.hasVerticalScroller = true
    ignoredScroll.hasHorizontalScroller = false
    ignoredScroll.autohidesScrollers = true
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
    let storageLabel = caption("History stays in Application Support. Text and managed media are encrypted with Keychain or an owner-only fallback key.")
    let screenPrivacyLabel = caption("When enabled, the clipboard panel is hidden from screenshots, screen sharing, and screen recordings.")
    let permissionHelpLabel = caption("Clipboard capture works without this permission. Grant Accessibility only for direct paste.")
    configureCheckbox(clearHistoryOnQuitButton, title: "Clear history on quit", action: #selector(clearHistoryOnQuitChanged))
    configureCheckbox(hideFromScreenCaptureButton, title: "Hide panel from screen sharing and recordings", action: #selector(hideFromScreenCaptureChanged))
    configureStatusLabel(accessibilityStatusLabel)
    let requestButton = button("Open Accessibility Settings", #selector(requestAccessibilityAccess))
    let refreshButton = button("Refresh Permission Status", #selector(refreshAccessibilityPermissionStatus))
    configureStatusLabel(pasteStatusLabel)

    return page([
      section("Local storage", [
        storageLabel,
        clearHistoryOnQuitButton
      ]),
      section("Screen privacy", [
        screenPrivacyLabel,
        hideFromScreenCaptureButton
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
    cacheSlider.minValue = Double(AppConfiguration.minCacheMaxBytes) / 1024 / 1024
    cacheSlider.maxValue = Double(AppConfiguration.maxCacheMaxBytes) / 1024 / 1024
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
    configureStatusLabel(dataStatusLabel)
    configureStatusLabel(cloudSyncStatusLabel)
    configureCheckbox(iCloudSyncButton, title: "Sync history with iCloud", action: #selector(iCloudSyncChanged))
    configureButton(iCloudSyncNowButton, title: "Sync Now", action: #selector(pushICloudSyncArchive))
    configureButton(iCloudRestoreButton, title: "Restore from iCloud", action: #selector(pullICloudSyncArchive))
    configureButton(iCloudRevealButton, title: "Reveal Sync File", action: #selector(revealICloudSyncFile))
    let archiveLabel = caption("Export a portable archive for history, Pinboards, and managed attachments. Archives are not encrypted; file references stay path-based.")
    let cloudLabel = caption("Uses the same archive in ClipBored's private iCloud container when iCloud signing and iCloud Drive are available.")
    return page([
      section("iCloud Sync", [
        cloudLabel,
        iCloudSyncButton,
        row([
          iCloudSyncNowButton,
          iCloudRestoreButton,
          iCloudRevealButton
        ]),
        cloudSyncStatusLabel
      ]),
      section("Archive", [
        archiveLabel,
        row([
          button("Export Archive...", #selector(exportClipboardArchive)),
          button("Import Archive...", #selector(importClipboardArchive))
        ])
      ]),
      section("Data", [
        button("Open History Folder", #selector(openHistoryFolder)),
        button("Clear Clipboard History", #selector(clearClipboardHistory)),
        button("Clear Thumbnail Cache", #selector(clearThumbnailCache)),
        dataStatusLabel
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
    let minimumWidth = stack.widthAnchor.constraint(greaterThanOrEqualToConstant: Metrics.settingsContentMinimumWidth)
    minimumWidth.priority = .defaultLow
    minimumWidth.isActive = true
    return stack
  }

  private func row(_ views: [NSView]) -> NSView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fill
    stack.spacing = 10
    stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return stack
  }

  private func labeledRow(_ title: String, _ control: NSView) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.widthAnchor.constraint(equalToConstant: Metrics.settingsLabelWidth).isActive = true
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
    let control = NSButton()
    configureButton(control, title: title, action: action)
    return control
  }

  private func configureButton(_ control: NSButton, title: String, action: Selector) {
    control.title = title
    control.target = self
    control.action = action
    control.bezelStyle = .rounded
    control.setAccessibilityLabel(title)
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
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    label.usesSingleLineMode = false
    label.cell?.wraps = true
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

  private func refreshFromSettings(for change: SettingsModel.Change) {
    switch change {
    case .maxHistoryItems:
      refreshHistoryLimitControls()
    case .historyRetention:
      refreshHistoryRetentionControl()
    case .defaultSortMode:
      refreshDefaultSortControl()
    case .imageCacheMaxBytes:
      refreshCacheControls()
    case .includeImageTextInSearch:
      includeImageTextButton.state = settings.includeImageTextInSearch ? .on : .off
    case .pruneDuplicates:
      pruneDuplicatesButton.state = settings.pruneDuplicates ? .on : .off
    case .openShortcut:
      refreshShortcutControls(openShortcutControls, binding: settings.openShortcut)
      refreshShortcutStatusLabel()
    case .settingsShortcut:
      refreshShortcutControls(settingsShortcutControls, binding: settings.settingsShortcut)
      refreshShortcutStatusLabel()
    case .launchAtLogin:
      refreshLaunchAtLoginControls()
    case .status:
      refreshStatusIndicators(refreshCloudSyncStatus: false)
    case .captureStatus:
      refreshCaptureStatusLabel()
    case .cloudSync:
      refreshCloudSyncControls(refreshStatus: settings.iCloudSyncEnabled && cachedCloudSyncStatus == nil)
    case .ignoredApps:
      refreshIgnoredAppsTextView()
    case .ignoredItemKinds:
      refreshAllowedKindControls()
    case .keepFirstImage:
      keepFirstImageButton.state = settings.keepFirstImage ? .on : .off
    case .excludeSensitive:
      excludeSensitiveButton.state = settings.excludeSensitive ? .on : .off
    case .pauseCapture:
      refreshPauseCaptureControls()
    case .hideFromScreenCapture:
      hideFromScreenCaptureButton.state = settings.hideFromScreenCapture ? .on : .off
    case .clearHistoryOnQuit:
      clearHistoryOnQuitButton.state = settings.clearHistoryOnQuit ? .on : .off
    case .pollProfile:
      select(pollProfilePopup, rawValue: settings.pollProfileRaw.rawValue)
    case .panelLayout:
      select(panelSidePopup, rawValue: settings.panelSide.rawValue)
    case .showMenuBarIcon:
      refreshVisibilityControls()
    case .showDockIcon:
      refreshVisibilityControls()
    default:
      refreshFromSettings(refreshCloudSyncStatus: false)
    }
  }

  private func refreshFromSettings(refreshCloudSyncStatus: Bool = false) {
    #if DEBUG
    debugFullRefreshCountValue += 1
    #endif

    refreshHistoryLimitControls()
    refreshHistoryRetentionControl()
    pruneDuplicatesButton.state = settings.pruneDuplicates ? .on : .off
    keepFirstImageButton.state = settings.keepFirstImage ? .on : .off
    refreshDefaultSortControl()
    refreshLaunchAtLoginControls()
    refreshVisibilityControls()
    select(panelSidePopup, rawValue: settings.panelSide.rawValue)
    refreshShortcutControls(openShortcutControls, binding: settings.openShortcut)
    refreshShortcutControls(settingsShortcutControls, binding: settings.settingsShortcut)

    refreshPauseCaptureControls()
    excludeSensitiveButton.state = settings.excludeSensitive ? .on : .off
    includeImageTextButton.state = settings.includeImageTextInSearch ? .on : .off
    refreshAllowedKindControls()
    refreshIgnoredAppsTextView()

    clearHistoryOnQuitButton.state = settings.clearHistoryOnQuit ? .on : .off
    hideFromScreenCaptureButton.state = settings.hideFromScreenCapture ? .on : .off

    select(pollProfilePopup, rawValue: settings.pollProfileRaw.rawValue)
    refreshCacheControls()
    refreshStatusIndicators(refreshCloudSyncStatus: refreshCloudSyncStatus)
  }

  private func refreshHistoryLimitControls() {
    historyLabel.stringValue = "History length: \(settings.maxHistoryItems)"
    historyStepper.integerValue = settings.maxHistoryItems
  }

  private func refreshHistoryRetentionControl() {
    select(historyRetentionPopup, rawValue: settings.historyRetention.rawValue)
  }

  private func refreshDefaultSortControl() {
    select(defaultSortPopup, rawValue: settings.defaultSortMode.rawValue)
  }

  private func refreshAllowedKindControls() {
    for (kind, button) in allowedKindButtons {
      button.state = settings.ignoredItemKindsRaw.contains(kind.rawValue) ? .off : .on
    }
  }

  private func refreshLaunchAtLoginControls() {
    launchAtLoginButton.state = settings.launchAtLogin ? .on : .off
    let presentation = Self.launchAtLoginStatusPresentation(
      storedStatus: settings.launchAtLoginErrorMessage
    )
    launchStatusLabel.stringValue = presentation.message
    launchStatusLabel.textColor = presentation.textColor
  }

  static func launchAtLoginStatusPresentation(
    storedStatus: String
  ) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else {
      return ("", .secondaryLabelColor)
    }
    return (storedStatus, .systemRed)
  }

  private func refreshVisibilityControls() {
    showMenuBarIconButton.state = settings.showMenuBarIcon ? .on : .off
    showDockIconButton.state = settings.showDockIcon ? .on : .off
  }

  private func refreshPauseCaptureControls() {
    pauseCaptureButton.state = settings.pauseCapture ? .on : .off
    refreshCaptureStatusLabel()
  }

  private func refreshCaptureStatusLabel() {
    setCaptureStatusLabel(settings.captureStatusMessage)
  }

  private func setCaptureStatusLabel(_ message: String) {
    let presentation = Self.captureStatusPresentation(storedStatus: message)
    captureStatusLabel.stringValue = presentation.message
    captureStatusLabel.textColor = presentation.textColor
  }

  static func captureStatusPresentation(
    storedStatus: String
  ) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else {
      return (
        "Capture status will appear after the app sees clipboard activity.",
        .secondaryLabelColor
      )
    }
    return (storedStatus, captureStatusColor(for: storedStatus))
  }

  private static func captureStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    if lowercasedMessage.hasPrefix("captured")
      || lowercasedMessage.hasPrefix("allowed content types updated")
      || lowercasedMessage.contains("capture running")
      || lowercasedMessage.contains("capture is running")
      || lowercasedMessage.contains("capture resumed") {
      return .systemGreen
    }
    if lowercasedMessage.hasPrefix("error")
      || lowercasedMessage.contains("failed")
      || lowercasedMessage.contains("could not") {
      return .systemRed
    }
    if lowercasedMessage.hasPrefix("skipped")
      || lowercasedMessage.contains("ignored")
      || lowercasedMessage.contains("paused")
      || lowercasedMessage.contains("at least one") {
      return .systemOrange
    }
    return .secondaryLabelColor
  }

  private func refreshStatusIndicators(refreshCloudSyncStatus: Bool) {
    refreshLaunchAtLoginControls()
    refreshShortcutStatusLabel()
    refreshCaptureStatusLabel()
    refreshAccessibilityPermissionStatusLabel()
    refreshPasteStatusLabel()
    refreshCloudSyncControls(refreshStatus: refreshCloudSyncStatus)
  }

  private func refreshShortcutStatusLabel() {
    let presentation = Self.shortcutStatusPresentation(
      storedStatus: settings.shortcutStatusMessage
    )
    shortcutStatusLabel.stringValue = presentation.message
    shortcutStatusLabel.textColor = presentation.textColor
  }

  static func shortcutStatusPresentation(
    storedStatus: String
  ) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else {
      return ("Registered", .systemGreen)
    }
    return (storedStatus, .systemRed)
  }

  private func refreshAccessibilityPermissionStatusLabel() {
    let presentation = Self.accessibilityPermissionStatusPresentation(
      storedStatus: settings.accessibilityPermissionStatusMessage,
      isTrusted: AccessibilityPermissionService.isTrusted
    )
    accessibilityStatusLabel.stringValue = presentation.message
    accessibilityStatusLabel.textColor = presentation.textColor
  }

  static func accessibilityPermissionStatusPresentation(
    storedStatus: String,
    isTrusted: Bool
  ) -> (message: String, textColor: NSColor) {
    let trimmedStatus = storedStatus.clipboardTrimmed
    guard trimmedStatus.isEmpty else {
      return (trimmedStatus, .systemOrange)
    }
    return isTrusted
      ? ("Granted", .systemGreen)
      : ("Not granted (clipboard capture still works; paste falls back to copy)", .systemOrange)
  }

  private func refreshPasteStatusLabel() {
    let presentation = Self.pasteStatusPresentation(
      storedStatus: settings.pasteStatusMessage
    )
    pasteStatusLabel.stringValue = presentation.message
    pasteStatusLabel.textColor = presentation.textColor
  }

  static func pasteStatusPresentation(
    storedStatus: String
  ) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else {
      return ("No paste action yet.", .secondaryLabelColor)
    }
    return (storedStatus, pasteStatusColor(for: storedStatus))
  }

  private static func pasteStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    if lowercasedMessage.contains("could not")
      || lowercasedMessage.contains("failed") {
      return .systemRed
    }
    if lowercasedMessage.contains("grant accessibility")
      || lowercasedMessage.contains("not granted") {
      return .systemOrange
    }
    if lowercasedMessage.hasPrefix("pasted")
      || lowercasedMessage.hasPrefix("copied") {
      return .systemGreen
    }
    return .secondaryLabelColor
  }

  private func refreshCacheControls() {
    cacheSlider.doubleValue = Double(settings.imageCacheMaxBytes) / 1024 / 1024
    cacheLabel.stringValue = "Current cache cap: \(cacheLimitMegabytes) MB"
  }

  private var cacheLimitMegabytes: Int {
    Int((Double(settings.imageCacheMaxBytes) / 1024 / 1024).rounded())
  }

  private func setDataStatus(_ message: String) {
    let presentation = Self.dataStatusPresentation(storedStatus: message)
    dataStatusLabel.stringValue = presentation.message
    dataStatusLabel.textColor = presentation.textColor
  }

  static func dataStatusPresentation(
    storedStatus: String
  ) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else {
      return ("", .secondaryLabelColor)
    }
    return (storedStatus, dataStatusColor(for: storedStatus))
  }

  private static func dataStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    if lowercasedMessage.contains("could not")
      || lowercasedMessage.contains("couldn")
      || lowercasedMessage.contains("denied")
      || lowercasedMessage.contains("error")
      || lowercasedMessage.contains("failed")
      || lowercasedMessage.contains("invalid")
      || lowercasedMessage.contains("missing")
      || lowercasedMessage.contains("not permitted")
      || lowercasedMessage.contains("unavailable") {
      return .systemRed
    }
    if lowercasedMessage.contains("skipped") {
      return .systemOrange
    }
    if lowercasedMessage.hasPrefix("exported")
      || lowercasedMessage.hasPrefix("imported")
      || lowercasedMessage.hasPrefix("cleared") {
      return .systemGreen
    }
    return .secondaryLabelColor
  }

  private func refreshCloudSyncControls(refreshStatus: Bool) {
    iCloudSyncButton.state = settings.iCloudSyncEnabled ? .on : .off
    let cloudStatus = cloudSyncStatus(refresh: refreshStatus)
    let presentation = Self.cloudSyncStatusPresentation(
      storedStatus: settings.cloudSyncStatusMessage,
      isSyncEnabled: settings.iCloudSyncEnabled,
      cloudStatus: cloudStatus
    )
    cloudSyncStatusLabel.stringValue = presentation.message
    cloudSyncStatusLabel.textColor = presentation.textColor
    let cloudActionsEnabled = settings.iCloudSyncEnabled && cloudStatus?.isAvailable == true
    iCloudSyncNowButton.isEnabled = cloudActionsEnabled
    iCloudRestoreButton.isEnabled = cloudActionsEnabled
    iCloudRevealButton.isEnabled = cloudActionsEnabled
  }

  static func cloudSyncStatusPresentation(
    storedStatus: String,
    isSyncEnabled: Bool,
    cloudStatus: ClipboardCloudSyncStatus?
  ) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    if !storedStatus.isEmpty {
      return (storedStatus, cloudSyncStatusColor(for: storedStatus))
    }

    if !isSyncEnabled {
      return ("iCloud Sync is off.", .secondaryLabelColor)
    }

    guard let cloudStatus else {
      return ("iCloud Sync is unavailable.", .systemOrange)
    }

    return (
      cloudStatus.message,
      cloudStatus.isAvailable ? .secondaryLabelColor : .systemOrange
    )
  }

  private static func cloudSyncStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    if lowercasedMessage.contains("failed") {
      return .systemRed
    }
    if lowercasedMessage.contains("unavailable")
      || lowercasedMessage.contains("turn on")
      || lowercasedMessage.contains("skipped") {
      return .systemOrange
    }
    if lowercasedMessage.hasPrefix("synced")
      || lowercasedMessage.hasPrefix("restored")
      || lowercasedMessage.hasPrefix("opened") {
      return .systemGreen
    }
    return .secondaryLabelColor
  }

  private func cloudSyncStatus(refresh: Bool) -> ClipboardCloudSyncStatus? {
    guard settings.iCloudSyncEnabled else {
      cachedCloudSyncStatus = nil
      return nil
    }

    if refresh || cachedCloudSyncStatus == nil {
      cachedCloudSyncStatus = cloudSyncService.status()
    }
    return cachedCloudSyncStatus
  }

  private func refreshIgnoredAppsTextView(force: Bool = false) {
    #if DEBUG
    debugIgnoredAppsRefreshCountValue += 1
    #endif

    guard force || !isEditingIgnoredApps else { return }

    let ignoredAppsText = settings.ignoredApps.joined(separator: ", ")
    if ignoredAppsTextView.string != ignoredAppsText {
      ignoredAppsTextView.string = ignoredAppsText
    }
  }

  private func ignoredApps(from text: String) -> [String] {
    text
      .split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.clipboardTrimmed }
      .filter { !$0.isEmpty }
  }

  private var isEditingIgnoredApps: Bool {
    ignoredAppsEditorIsEditing || ignoredAppsTextView.window?.firstResponder === ignoredAppsTextView
  }

  private func refreshShortcutControls(
    _ controls: ShortcutControlSet?,
    binding: ShortcutBinding,
    forceKeyRefresh: Bool = false
  ) {
    guard let controls else { return }
    if forceKeyRefresh || !isEditingShortcutKeyField(controls.keyField) {
      controls.keyField.stringValue = binding.key.uppercased()
    }
    controls.command.state = binding.has(.command) ? .on : .off
    controls.option.state = binding.has(.option) ? .on : .off
    controls.control.state = binding.has(.control) ? .on : .off
    controls.shift.state = binding.has(.shift) ? .on : .off
  }

  private func isEditingShortcutKeyField(_ field: NSTextField) -> Bool {
    if editingShortcutFieldTag == field.tag { return true }
    guard let editor = field.currentEditor() else { return false }
    return field.window?.firstResponder === editor
  }

  private func commitPendingEditorDrafts() {
    commitIgnoredAppsDraftIfNeeded()
    commitShortcutDraftIfNeeded(openShortcutControls)
    commitShortcutDraftIfNeeded(settingsShortcutControls)
  }

  private func commitIgnoredAppsDraftIfNeeded() {
    guard ignoredAppsEditorHasDraft else {
      ignoredAppsEditorIsEditing = false
      ignoredAppsEditorHasDraft = false
      refreshIgnoredAppsTextView(force: true)
      return
    }

    settings.ignoredApps = ignoredApps(from: ignoredAppsTextView.string)
    ignoredAppsEditorIsEditing = false
    ignoredAppsEditorHasDraft = false
    refreshIgnoredAppsTextView(force: true)
  }

  private func commitShortcutDraftIfNeeded(_ controls: ShortcutControlSet?) {
    guard let controls, isEditingShortcutKeyField(controls.keyField) else { return }
    shortcutChanged(controls.keyField)
    if editingShortcutFieldTag == controls.keyField.tag {
      editingShortcutFieldTag = nil
    }
  }

  private func select(_ popup: NSPopUpButton, rawValue: Int) {
    for item in popup.itemArray where item.representedObject as? Int == rawValue {
      popup.select(item)
      return
    }
  }

  @objc private func historyLengthChanged() {
    settings.maxHistoryItems = historyStepper.integerValue
    refreshHistoryLimitControls()
  }

  @objc private func historyRetentionChanged() {
    if let rawValue = historyRetentionPopup.selectedItem?.representedObject as? Int,
       let retention = HistoryRetention(rawValue: rawValue) {
      settings.historyRetention = retention
    }
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
    let enabled = launchAtLoginButton.state == .on
    settings.launchAtLogin = enabled
    if !enabled {
      settings.setLaunchAtLoginStatus(message: "")
    }
    refreshLaunchAtLoginControls()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.refreshLaunchAtLoginControls()
    }
  }

  @objc private func showMenuBarIconChanged() {
    let shouldShowMenuBarIcon = showMenuBarIconButton.state == .on
    settings.showMenuBarIcon = shouldShowMenuBarIcon
    if !shouldShowMenuBarIcon && !settings.showDockIcon {
      settings.showDockIcon = true
    }
    refreshVisibilityControls()
  }

  @objc private func showDockIconChanged() {
    let shouldShowDockIcon = showDockIconButton.state == .on
    settings.showDockIcon = shouldShowDockIcon
    if !shouldShowDockIcon && !settings.showMenuBarIcon {
      settings.showMenuBarIcon = true
    }
    refreshVisibilityControls()
  }

  @objc private func panelSideChanged() {
    if let rawValue = panelSidePopup.selectedItem?.representedObject as? Int,
       let side = ClipboardPanelSide(rawValue: rawValue) {
      settings.panelSide = side
    }
  }

  @objc private func shortcutChanged(_ sender: NSControl) {
    let isOpenShortcut = sender.tag < 200
    let controls = isOpenShortcut ? openShortcutControls : settingsShortcutControls
    guard let controls else { return }

    let current = isOpenShortcut ? settings.openShortcut : settings.settingsShortcut
    let parsed = parseShortcut(controls.keyField.stringValue)
    let hasExplicitModifiers = shortcutInputHasExplicitModifiers(controls.keyField.stringValue)
    var flags = NSEvent.ModifierFlags(rawValue: hasExplicitModifiers ? parsed?.modifierFlags ?? 0 : current.modifierFlags)
    setFlag(&flags, .command, hasExplicitModifiers ? parsed?.has(.command) == true : controls.command.state == .on)
    setFlag(&flags, .option, hasExplicitModifiers ? parsed?.has(.option) == true : controls.option.state == .on)
    setFlag(&flags, .control, hasExplicitModifiers ? parsed?.has(.control) == true : controls.control.state == .on)
    setFlag(&flags, .shift, hasExplicitModifiers ? parsed?.has(.shift) == true : controls.shift.state == .on)

    guard let key = parsed?.key ?? shortcutKey(from: controls.keyField.stringValue) else {
      settings.setShortcutStatus(message: invalidShortcutStatusMessage(
        for: controls.keyField.stringValue,
        modifierFlags: flags
      ) ?? "")
      refreshShortcutControls(controls, binding: current, forceKeyRefresh: true)
      refreshShortcutStatusLabel()
      return
    }

    let updated = ShortcutBinding(key: key, modifierFlags: flags.rawValue)
    if let validationMessage = shortcutValidationMessage(for: updated, isOpenShortcut: isOpenShortcut) {
      settings.setShortcutStatus(message: validationMessage)
      refreshShortcutControls(controls, binding: current, forceKeyRefresh: true)
      refreshShortcutStatusLabel()
      return
    }

    settings.setShortcutStatus(message: "")
    if isOpenShortcut {
      settings.openShortcut = updated
    } else {
      settings.settingsShortcut = updated
    }
    refreshShortcutControls(
      controls,
      binding: updated,
      forceKeyRefresh: sender === controls.keyField || !isEditingShortcutKeyField(controls.keyField)
    )
    refreshShortcutStatusLabel()
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, field.tag == 100 || field.tag == 200 else { return }
    editingShortcutFieldTag = field.tag
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, field.tag == 100 || field.tag == 200 else { return }
    shortcutChanged(field)
    if editingShortcutFieldTag == field.tag {
      editingShortcutFieldTag = nil
    }
  }

  @objc private func pauseCaptureChanged() {
    if pauseCaptureButton.state == .on {
      settings.pauseCaptureUntil = nil
      settings.pauseCapture = true
    } else {
      settings.pauseCapture = false
      settings.pauseCaptureUntil = nil
    }
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
    let visibleKindRawValues = Set(allowedKindButtons.map { $0.0.rawValue })
    let ignoredVisibleKindRawValues = Set(ignored.filter { visibleKindRawValues.contains($0) })
    if visibleKindRawValues.isSubset(of: ignoredVisibleKindRawValues) {
      let message = Self.allowedContentTypesValidationMessage
      sender.state = .on
      settings.setCaptureStatus(message: message)
      setCaptureStatusLabel(message)
      return
    }
    settings.ignoredItemKindsRaw = ignored
    if settings.captureStatusMessage == Self.allowedContentTypesValidationMessage {
      settings.setCaptureStatus(message: Self.allowedContentTypesUpdatedMessage)
    }
  }

  func textDidBeginEditing(_ notification: Notification) {
    guard notification.object as? NSTextView === ignoredAppsTextView else { return }
    ignoredAppsEditorIsEditing = true
    ignoredAppsEditorHasDraft = false
  }

  func textDidChange(_ notification: Notification) {
    guard notification.object as? NSTextView === ignoredAppsTextView else { return }
    ignoredAppsEditorHasDraft = true
  }

  func textDidEndEditing(_ notification: Notification) {
    guard notification.object as? NSTextView === ignoredAppsTextView else { return }
    commitIgnoredAppsDraftIfNeeded()
  }

  @objc private func clearHistoryOnQuitChanged() {
    settings.clearHistoryOnQuit = clearHistoryOnQuitButton.state == .on
  }

  @objc private func hideFromScreenCaptureChanged() {
    settings.hideFromScreenCapture = hideFromScreenCaptureButton.state == .on
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
    refreshAccessibilityPermissionStatusLabel()
  }

  @objc private func pollProfileChanged() {
    if let rawValue = pollProfilePopup.selectedItem?.representedObject as? Int,
       let profile = AppConfiguration.PollProfile(rawValue: rawValue) {
      settings.pollProfileRaw = profile
    }
  }

  @objc private func cacheLimitChanged() {
    let megabytes = Int(cacheSlider.doubleValue.rounded())
    settings.imageCacheMaxBytes = Int64(megabytes * 1024 * 1024)
    refreshCacheControls()
  }

  @objc private func iCloudSyncChanged() {
    let enabled = iCloudSyncButton.state == .on
    settings.iCloudSyncEnabled = enabled
    settings.setCloudSyncStatus(message: "")
    if !enabled {
      cachedCloudSyncStatus = nil
    }
    refreshCloudSyncControls(refreshStatus: enabled && cachedCloudSyncStatus == nil)
  }

  @objc private func openHistoryFolder() {
    NSWorkspace.shared.open(ClipboardStore.storageDirectory())
  }

  @objc private func exportClipboardArchive() {
    let panel = NSSavePanel()
    panel.title = "Export ClipBored Archive"
    panel.nameFieldStringValue = defaultArchiveFileName()
    configureArchivePanel(panel)

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let summary = try store.exportArchive(to: url)
      setDataStatus("Exported \(summary.itemCount) clips and \(summary.sidecarCount) attachments.")
    } catch {
      setDataStatus(error.localizedDescription)
    }
  }

  @objc private func importClipboardArchive() {
    let panel = NSOpenPanel()
    panel.title = "Import ClipBored Archive"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    configureArchivePanel(panel)

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let summary = try store.importArchive(from: url)
      var message = "Imported \(summary.itemCount) clips and \(summary.sidecarCount) attachments."
      if summary.skippedItemCount > 0 || summary.skippedSidecarCount > 0 {
        message += " Skipped \(summary.skippedItemCount) clips and \(summary.skippedSidecarCount) attachments."
      }
      setDataStatus(message)
    } catch {
      setDataStatus(error.localizedDescription)
    }
  }

  @objc private func pushICloudSyncArchive() {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Sync before syncing.")
      return
    }

    do {
      let summary = try cloudSyncService.push(store: store)
      cachedCloudSyncStatus = cloudSyncService.status()
      settings.setCloudSyncStatus(message: "Synced \(summary.itemCount) clips and \(summary.sidecarCount) attachments to iCloud.")
    } catch {
      settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
    }
  }

  @objc private func pullICloudSyncArchive() {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Sync before restoring.")
      return
    }

    do {
      let summary = try cloudSyncService.pull(store: store)
      cachedCloudSyncStatus = cloudSyncService.status()
      var message = "Restored \(summary.itemCount) clips and \(summary.sidecarCount) attachments from iCloud."
      if summary.skippedItemCount > 0 || summary.skippedSidecarCount > 0 {
        message += " Skipped \(summary.skippedItemCount) clips and \(summary.skippedSidecarCount) attachments."
      }
      settings.setCloudSyncStatus(message: message)
    } catch {
      settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
    }
  }

  @objc private func revealICloudSyncFile() {
    do {
      let url = try cloudSyncService.syncArchiveURL()
      if FileManager.default.fileExists(atPath: url.path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } else {
        NSWorkspace.shared.open(url.deletingLastPathComponent())
      }
      cachedCloudSyncStatus = cloudSyncService.status()
      settings.setCloudSyncStatus(message: "Opened iCloud sync location.")
    } catch {
      settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
    }
  }

  @objc private func clearClipboardHistory() {
    guard confirmDestructiveAction(
      title: "Clear Clipboard History?",
      message: "This permanently removes saved clipboard items, app-managed attachments, temporary decrypted previews, and the local fallback encryption key when present. The current system clipboard is not changed.",
      buttonTitle: "Clear History"
    ) else { return }
    store.removeAll()
    cacheService.clearTemporaryPreviews()
    setDataStatus("Cleared clipboard history.")
  }

  @objc private func clearThumbnailCache() {
    guard confirmDestructiveAction(
      title: "Clear Thumbnail Cache?",
      message: "This removes cached image previews and temporary decrypted previews. ClipBored will recreate previews as needed.",
      buttonTitle: "Clear Cache"
    ) else { return }
    cacheService.clearCache()
    setDataStatus("Cleared thumbnail cache.")
  }

  private func confirmDestructiveAction(title: String, message: String, buttonTitle: String) -> Bool {
    #if DEBUG
    if let override = debugDestructiveActionConfirmationOverride {
      return override
    }
    #endif

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: buttonTitle)
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func configureArchivePanel(_ panel: NSSavePanel) {
    panel.setValue([ClipboardArchiveService.fileExtension], forKey: "allowedFileTypes")
  }

  private func defaultArchiveFileName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    return "ClipBored-\(formatter.string(from: Date())).\(ClipboardArchiveService.fileExtension)"
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

    guard plain.count == 1, let key = plain.first else { return nil }
    return ShortcutBinding(key: String(key), modifierFlags: flags.rawValue)
  }

  private func shortcutInputHasExplicitModifiers(_ text: String) -> Bool {
    let cleaned = text.clipboardTrimmed
    return cleaned.contains("⌘")
      || cleaned.contains("⌥")
      || cleaned.contains("⌃")
      || cleaned.contains("⇧")
  }

  private func shortcutKey(from text: String) -> String? {
    let cleaned = text.clipboardTrimmed
    guard cleaned.count == 1 else { return nil }
    guard !["⌘", "⌥", "⌃", "⇧"].contains(cleaned) else { return nil }
    return cleaned.lowercased()
  }

  private func invalidShortcutStatusMessage(
    for text: String,
    modifierFlags: NSEvent.ModifierFlags
  ) -> String? {
    let cleaned = text.clipboardTrimmed
    guard !cleaned.isEmpty else { return nil }

    var explicitFlags = NSEvent.ModifierFlags()
    if cleaned.contains("⌘") { explicitFlags.insert(.command) }
    if cleaned.contains("⌥") { explicitFlags.insert(.option) }
    if cleaned.contains("⌃") { explicitFlags.insert(.control) }
    if cleaned.contains("⇧") { explicitFlags.insert(.shift) }

    let plain = cleaned.replacingOccurrences(of: "⌘", with: "")
      .replacingOccurrences(of: "⌥", with: "")
      .replacingOccurrences(of: "⌃", with: "")
      .replacingOccurrences(of: "⇧", with: "")
      .clipboardTrimmed

    let display: String
    if plain.isEmpty {
      display = cleaned
    } else {
      let flags = explicitFlags.isEmpty ? modifierFlags : explicitFlags
      display = ShortcutBinding(key: plain, modifierFlags: flags.rawValue).displayText
    }
    return ShortcutManager.RegistrationStatus.unsupportedShortcut(display).message
  }

  private func shortcutValidationMessage(for binding: ShortcutBinding, isOpenShortcut: Bool) -> String? {
    if let failure = ShortcutManager.validationFailure(for: binding) {
      return failure.message
    }

    let otherBinding = isOpenShortcut ? settings.settingsShortcut : settings.openShortcut
    if binding == otherBinding {
      return ShortcutManager.RegistrationStatus.conflict(binding.displayText).message
    }

    if binding == ShortcutManager.stackCaptureShortcut {
      return ShortcutManager.RegistrationStatus.conflict(binding.displayText).message
    }

    return nil
  }

  #if DEBUG
  var debugWindowStyleMask: NSWindow.StyleMask {
    window?.styleMask ?? []
  }

  var debugWindowMinSize: NSSize {
    window?.minSize ?? .zero
  }

  var debugWindowContentSize: NSSize {
    window?.contentView?.bounds.size ?? .zero
  }

  var debugRawSettingsTabLabels: [String] {
    tabView.tabViewItems.map(\.label)
  }

  func debugSetWindowContentSize(_ size: NSSize) {
    window?.setContentSize(size)
    window?.contentView?.layoutSubtreeIfNeeded()
  }

  var debugSettingsTabLayoutMetrics: [(label: String, viewport: NSSize, document: NSSize, hasHorizontalScroller: Bool)] {
    let originalSelection = tabView.selectedTabViewItem
    defer {
      if let originalSelection {
        tabView.selectTabViewItem(originalSelection)
      }
      window?.contentView?.layoutSubtreeIfNeeded()
    }

    return tabView.tabViewItems.map { item in
      tabView.selectTabViewItem(item)
      window?.contentView?.layoutSubtreeIfNeeded()
      item.view?.layoutSubtreeIfNeeded()
      guard let scrollView = item.view as? NSScrollView else {
        return (tabTitle(for: item), .zero, .zero, true)
      }
      scrollView.documentView?.layoutSubtreeIfNeeded()
      return (
        tabTitle(for: item),
        scrollView.contentView.bounds.size,
        scrollView.documentView?.frame.size ?? .zero,
        scrollView.hasHorizontalScroller
      )
    }
  }

  var debugSettingsTabLayoutAuditMetrics: [(label: String, overflowingViewCount: Int, zeroSizedControlCount: Int)] {
    let originalSelection = tabView.selectedTabViewItem
    defer {
      if let originalSelection {
        tabView.selectTabViewItem(originalSelection)
      }
      window?.contentView?.layoutSubtreeIfNeeded()
    }

    func visibleDescendants(of root: NSView) -> [NSView] {
      var result: [NSView] = []
      func visit(_ view: NSView) {
        guard !view.isHidden else { return }
        result.append(view)
        for subview in view.subviews {
          visit(subview)
        }
      }
      for subview in root.subviews {
        visit(subview)
      }
      return result
    }

    func shouldAudit(_ view: NSView) -> Bool {
      !(view is NSScroller)
    }

    func canCollapseToZero(_ view: NSView) -> Bool {
      view is NSControl || view is NSTextView
    }

    return tabView.tabViewItems.map { item in
      tabView.selectTabViewItem(item)
      window?.contentView?.layoutSubtreeIfNeeded()
      item.view?.layoutSubtreeIfNeeded()
      guard let scrollView = item.view as? NSScrollView,
            let documentView = scrollView.documentView else {
        return (tabTitle(for: item), 1, 1)
      }

      documentView.layoutSubtreeIfNeeded()
      let auditedViews = visibleDescendants(of: documentView).filter(shouldAudit)
      let documentBounds = documentView.bounds
      let overflowing = auditedViews.filter { view in
        let frame = view.convert(view.bounds, to: documentView)
        return frame.minX < -1 || frame.maxX > documentBounds.width + 1
      }
      let zeroSizedControls = auditedViews.filter { view in
        guard canCollapseToZero(view) else { return false }
        let frame = view.convert(view.bounds, to: documentView)
        return frame.width <= 0.5 || frame.height <= 0.5
      }
      return (tabTitle(for: item), overflowing.count, zeroSizedControls.count)
    }
  }

  var debugSettingsTabContentPlacementMetrics: [(label: String, contentBounds: NSRect, document: NSSize)] {
    let originalSelection = tabView.selectedTabViewItem
    defer {
      if let originalSelection {
        tabView.selectTabViewItem(originalSelection)
      }
      window?.contentView?.layoutSubtreeIfNeeded()
    }

    func visibleControlsAndLabels(of root: NSView) -> [NSView] {
      var result: [NSView] = []
      func visit(_ view: NSView) {
        guard !view.isHidden else { return }
        if view is NSControl || view is NSTextView {
          result.append(view)
        }
        for subview in view.subviews {
          visit(subview)
        }
      }
      for subview in root.subviews {
        visit(subview)
      }
      return result
    }

    return tabView.tabViewItems.map { item in
      tabView.selectTabViewItem(item)
      window?.contentView?.layoutSubtreeIfNeeded()
      item.view?.layoutSubtreeIfNeeded()
      guard let scrollView = item.view as? NSScrollView,
            let documentView = scrollView.documentView else {
        return (tabTitle(for: item), .zero, .zero)
      }

      documentView.layoutSubtreeIfNeeded()
      let bounds = visibleControlsAndLabels(of: documentView)
        .map { $0.convert($0.bounds, to: documentView) }
        .reduce(NSRect.null) { $0.union($1) }
      return (tabTitle(for: item), bounds.isNull ? .zero : bounds, documentView.frame.size)
    }
  }

  var debugCloudSyncStatusText: String {
    cloudSyncStatusLabel.stringValue
  }

  var debugCloudSyncActionButtonsAreEnabled: [Bool] {
    [
      iCloudSyncNowButton.isEnabled,
      iCloudRestoreButton.isEnabled,
      iCloudRevealButton.isEnabled
    ]
  }

  var debugHistoryText: String {
    historyLabel.stringValue
  }

  var debugHistoryStepperValue: Int {
    historyStepper.integerValue
  }

  var debugCacheStatusText: String {
    cacheLabel.stringValue
  }

  var debugCacheSliderMegabytes: Int {
    Int(cacheSlider.doubleValue.rounded())
  }

  var debugDataStatusText: String {
    dataStatusLabel.stringValue
  }

  var debugDataStatusColor: NSColor {
    dataStatusLabel.textColor ?? .clear
  }

  var debugDataStatusSectionTitle: String {
    guard let section = dataStatusLabel.superview as? NSStackView,
          let titleLabel = section.arrangedSubviews.first as? NSTextField else {
      return ""
    }
    return titleLabel.stringValue
  }

  var debugPasteStatusText: String {
    pasteStatusLabel.stringValue
  }

  var debugAccessibilityStatusText: String {
    accessibilityStatusLabel.stringValue
  }

  var debugCaptureStatusText: String {
    captureStatusLabel.stringValue
  }

  var debugCaptureStatusColor: NSColor {
    captureStatusLabel.textColor ?? .clear
  }

  var debugStatusLabelsAllowWrapping: Bool {
    [
      launchStatusLabel,
      shortcutStatusLabel,
      captureStatusLabel,
      accessibilityStatusLabel,
      pasteStatusLabel,
      cacheLabel,
      dataStatusLabel,
      cloudSyncStatusLabel
    ].allSatisfy { label in
      label.lineBreakMode == .byWordWrapping
        && label.maximumNumberOfLines == 0
        && !label.usesSingleLineMode
        && (label.cell?.wraps ?? false)
    }
  }

  var debugDefaultSortTitle: String {
    defaultSortPopup.selectedItem?.title ?? ""
  }

  var debugPruneDuplicatesIsEnabled: Bool {
    pruneDuplicatesButton.state == .on
  }

  var debugKeepFirstImageIsEnabled: Bool {
    keepFirstImageButton.state == .on
  }

  var debugIncludeImageTextIsEnabled: Bool {
    includeImageTextButton.state == .on
  }

  var debugExcludeSensitiveIsEnabled: Bool {
    excludeSensitiveButton.state == .on
  }

  var debugClearHistoryOnQuitIsEnabled: Bool {
    clearHistoryOnQuitButton.state == .on
  }

  var debugLaunchAtLoginIsEnabled: Bool {
    launchAtLoginButton.state == .on
  }

  var debugShowMenuBarIconIsEnabled: Bool {
    showMenuBarIconButton.state == .on
  }

  var debugShowDockIconIsEnabled: Bool {
    showDockIconButton.state == .on
  }

  var debugLaunchStatusText: String {
    launchStatusLabel.stringValue
  }

  var debugOpenShortcutKeyText: String {
    openShortcutControls?.keyField.stringValue ?? ""
  }

  var debugSettingsShortcutKeyText: String {
    settingsShortcutControls?.keyField.stringValue ?? ""
  }

  var debugShortcutStatusText: String {
    shortcutStatusLabel.stringValue
  }

  var debugFullRefreshCount: Int {
    debugFullRefreshCountValue
  }

  var debugIgnoredAppsRefreshCount: Int {
    debugIgnoredAppsRefreshCountValue
  }

  var debugIgnoredAppsText: String {
    ignoredAppsTextView.string
  }

  var debugIgnoredAppsEditorIsFocused: Bool {
    isEditingIgnoredApps
  }

  @discardableResult
  func debugFocusIgnoredAppsEditor() -> Bool {
    textDidBeginEditing(Notification(name: NSText.didBeginEditingNotification, object: ignoredAppsTextView))
    _ = window?.makeFirstResponder(ignoredAppsTextView)
    return isEditingIgnoredApps
  }

  func debugSetIgnoredAppsText(_ text: String) {
    ignoredAppsTextView.string = text
    textDidChange(Notification(name: NSText.didChangeNotification, object: ignoredAppsTextView))
  }

  func debugSetHistoryStepperValue(_ value: Int) {
    historyStepper.integerValue = value
    historyLengthChanged()
  }

  func debugSetCacheSliderMegabytes(_ value: Int) {
    cacheSlider.doubleValue = Double(value)
    cacheLimitChanged()
  }

  func debugEndIgnoredAppsEditing() {
    window?.makeFirstResponder(nil)
    textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: ignoredAppsTextView))
  }

  func debugCloseWindow() {
    windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
    window?.makeFirstResponder(nil)
  }

  @discardableResult
  func debugBeginOpenShortcutKeyEditing() -> Bool {
    guard let field = openShortcutControls?.keyField else { return false }
    controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
    _ = window?.makeFirstResponder(field)
    return isEditingShortcutKeyField(field)
  }

  func debugSetOpenShortcutKeyDraft(_ text: String) {
    openShortcutControls?.keyField.stringValue = text
  }

  func debugEndOpenShortcutKeyEditing() {
    guard let field = openShortcutControls?.keyField else { return }
    window?.makeFirstResponder(nil)
    controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
  }

  func debugCommitOpenShortcutKeyText(_ text: String) {
    guard let controls = openShortcutControls else { return }
    controls.keyField.stringValue = text
    shortcutChanged(controls.keyField)
  }

  func debugSetOpenShortcutModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) {
    guard let controls = openShortcutControls else { return }
    controls.command.state = command ? .on : .off
    controls.option.state = option ? .on : .off
    controls.control.state = control ? .on : .off
    controls.shift.state = shift ? .on : .off
    shortcutChanged(controls.command)
  }

  func debugCommitSettingsShortcutKeyText(_ text: String) {
    guard let controls = settingsShortcutControls else { return }
    controls.keyField.stringValue = text
    shortcutChanged(controls.keyField)
  }

  func debugSetLaunchAtLoginEnabled(_ enabled: Bool) {
    launchAtLoginButton.state = enabled ? .on : .off
    launchAtLoginChanged()
  }

  func debugSetShowMenuBarIconEnabled(_ enabled: Bool) {
    showMenuBarIconButton.state = enabled ? .on : .off
    showMenuBarIconChanged()
  }

  func debugSetShowDockIconEnabled(_ enabled: Bool) {
    showDockIconButton.state = enabled ? .on : .off
    showDockIconChanged()
  }

  func debugSetICloudSyncEnabled(_ enabled: Bool) {
    iCloudSyncButton.state = enabled ? .on : .off
    iCloudSyncChanged()
  }

  func debugSetDestructiveActionConfirmation(_ confirmed: Bool?) {
    debugDestructiveActionConfirmationOverride = confirmed
  }

  func debugClearClipboardHistory() {
    clearClipboardHistory()
  }

  func debugClearThumbnailCache() {
    clearThumbnailCache()
  }

  func debugAllowedKindIsEnabled(_ kind: ClipboardItemKind) -> Bool {
    allowedKindButtons.first { $0.0 == kind }?.1.state == .on
  }

  func debugSetAllowedKindEnabled(_ kind: ClipboardItemKind, _ enabled: Bool) {
    guard let button = allowedKindButtons.first(where: { $0.0 == kind })?.1 else { return }
    button.state = enabled ? .on : .off
    allowedKindChanged(button)
  }

  func debugRefreshAccessibilityPermissionStatus() {
    refreshAccessibilityPermissionStatus()
  }
  #endif
}

private struct ShortcutControlSet {
  let keyField: NSTextField
  let command: NSButton
  let option: NSButton
  let control: NSButton
  let shift: NSButton
}
