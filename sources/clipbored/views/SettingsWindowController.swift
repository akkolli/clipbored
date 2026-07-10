import AppKit

private final class TopAlignedSettingsDocumentView: NSView {
  override var isFlipped: Bool {
    true
  }
}

final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate {
  private enum Metrics {
    static let windowSize = NSSize(width: 620, height: 520)
    static let minimumWindowSize = NSSize(width: 560, height: 440)
    static let settingsContentMinimumWidth: CGFloat = 440
    static let settingsLabelWidth: CGFloat = 128
  }
  private enum ControlCommand: Int {
    case historyLength, historyRetention, pruneDuplicates, keepFirstImage, defaultSort
    case launchAtLogin, showMenuBarIcon, showDockIcon, panelSide
    case pauseCapture, excludeSensitive, includeImageText
    case clearHistoryOnQuit, hideFromScreenCapture, requestAccessibility, refreshAccessibility
    case pollProfile, cacheLimit
    case iCloudSync, pushICloudArchive, pullICloudArchive, revealICloudFile
    case openHistoryFolder, exportArchive, importArchive, clearHistory, clearCache
  }
  private static let tabTitles = ["General", "Shortcuts", "Capture", "Privacy", "Performance", "Data"]
  private static let allowedContentTypesValidationMessage = "At least one content type must stay enabled."
  private static let allowedContentTypesUpdatedMessage = "Allowed content types updated."

  private let settings: SettingsModel
  private let store: ClipboardStore
  private let cacheService: ClipboardCacheService
  private let cloudSyncService: ClipboardCloudSyncServicing
  private let dataOperationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "clipbored.settings.data-operations"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private var dataOperationInProgress = false
  private var window: NSWindow?
  private var cachedCloudSyncStatus: ClipboardCloudSyncStatus?
  private let tabView = NSTabView()
  private let tabSelector = NSSegmentedControl(
    labels: SettingsWindowController.tabTitles,
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )

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
  private let exportArchiveButton = NSButton()
  private let importArchiveButton = NSButton()


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
    tabView.tabViewType = .noTabsNoBorder
    tabView.addTabViewItem(tab("General", generalSettingsView()))
    tabView.addTabViewItem(tab("Shortcuts", shortcutSettingsView()))
    tabView.addTabViewItem(tab("Capture", captureSettingsView()))
    tabView.addTabViewItem(tab("Privacy", privacySettingsView()))
    tabView.addTabViewItem(tab("Performance", performanceSettingsView()))
    tabView.addTabViewItem(tab("Data", dataSettingsView()))

    tabSelector.translatesAutoresizingMaskIntoConstraints = false
    tabSelector.target = self
    tabSelector.action = #selector(settingsTabChanged(_:))
    tabSelector.selectedSegment = 0
    tabSelector.segmentStyle = .rounded

    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    container.addSubview(tabSelector)
    container.addSubview(tabView)
    NSLayoutConstraint.activate([
      tabSelector.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      tabSelector.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      tabSelector.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
      tabSelector.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
      tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
      tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
      tabView.topAnchor.constraint(equalTo: tabSelector.bottomAnchor, constant: 10),
      tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
    ])
    return container
  }

  @objc private func settingsTabChanged(_ sender: NSSegmentedControl) {
    let index = sender.selectedSegment
    guard index >= 0, index < tabView.numberOfTabViewItems else { return }
    tabView.selectTabViewItem(at: index)
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
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let documentView = TopAlignedSettingsDocumentView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(content)
    scrollView.documentView = documentView
    let documentFillsViewport = documentView.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor)
    let documentContainsContent = documentView.bottomAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor)
    NSLayoutConstraint.activate([
      documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
      documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
      documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
      documentFillsViewport,
      documentContainsContent,
      documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
      content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      content.topAnchor.constraint(equalTo: documentView.topAnchor)
    ])
    return scrollView
  }

  private func generalSettingsView() -> NSView {
    historyStepper.minValue = Double(AppConfiguration.minHistoryLength)
    historyStepper.maxValue = Double(AppConfiguration.maxHistoryLength)
    historyStepper.increment = 25
    bind(historyStepper, to: .historyLength)
    historyStepper.setAccessibilityLabel("History length")
    configurePopup(historyRetentionPopup, command: .historyRetention)
    historyRetentionPopup.setAccessibilityLabel("Keep history")
    for retention in HistoryRetention.allCases {
      addPopupItem(retention.title, retention.rawValue, to: historyRetentionPopup)
    }

    configureCheckbox(pruneDuplicatesButton, title: "Ignore duplicate items", command: .pruneDuplicates)
    configureCheckbox(keepFirstImageButton, title: "Keep first image copy", command: .keepFirstImage)
    configurePopup(defaultSortPopup, command: .defaultSort)
    defaultSortPopup.setAccessibilityLabel("Default sort")
    for mode in ClipboardSortMode.allCases {
      addPopupItem(mode.title, mode.rawValue, to: defaultSortPopup)
    }
    configureCheckbox(launchAtLoginButton, title: "Launch at login", command: .launchAtLogin)
    configureCheckbox(showMenuBarIconButton, title: "Show ClipBored in the menu bar", command: .showMenuBarIcon)
    configureCheckbox(showDockIconButton, title: "Show ClipBored in the Dock", command: .showDockIcon)
    configurePopup(panelSidePopup, command: .panelSide)
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
    configureCheckbox(pauseCaptureButton, title: "Pause clipboard capture", command: .pauseCapture)
    configureCheckbox(excludeSensitiveButton, title: "Exclude likely secrets", command: .excludeSensitive)
    configureCheckbox(includeImageTextButton, title: "Search in image labels", command: .includeImageText)
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
    configureCheckbox(clearHistoryOnQuitButton, title: "Clear history on quit", command: .clearHistoryOnQuit)
    configureCheckbox(hideFromScreenCaptureButton, title: "Hide panel from screen sharing and recordings", command: .hideFromScreenCapture)
    configureStatusLabel(accessibilityStatusLabel)
    let requestButton = button("Open Accessibility Settings", .requestAccessibility)
    let refreshButton = button("Refresh Permission Status", .refreshAccessibility)
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
    configurePopup(pollProfilePopup, command: .pollProfile)
    pollProfilePopup.setAccessibilityLabel("Polling profile")
    for profile in AppConfiguration.PollProfile.allCases {
      addPopupItem(profile.title, profile.rawValue, to: pollProfilePopup)
    }
    cacheSlider.minValue = Double(AppConfiguration.minCacheMaxBytes) / 1024 / 1024
    cacheSlider.maxValue = Double(AppConfiguration.maxCacheMaxBytes) / 1024 / 1024
    cacheSlider.numberOfTickMarks = 9
    cacheSlider.allowsTickMarkValuesOnly = true
    bind(cacheSlider, to: .cacheLimit)
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
    configureCheckbox(iCloudSyncButton, title: "Sync history with iCloud", command: .iCloudSync)
    configureButton(iCloudSyncNowButton, title: "Sync Now", command: .pushICloudArchive)
    configureButton(iCloudRestoreButton, title: "Restore from iCloud", command: .pullICloudArchive)
    configureButton(iCloudRevealButton, title: "Reveal Sync File", command: .revealICloudFile)
    configureButton(exportArchiveButton, title: "Export Archive...", command: .exportArchive)
    configureButton(importArchiveButton, title: "Import Archive...", command: .importArchive)
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
          exportArchiveButton,
          importArchiveButton
        ])
      ]),
      section("Data", [
        button("Open History Folder", .openHistoryFolder),
        button("Clear Clipboard History", .clearHistory),
        button("Clear Thumbnail Cache", .clearCache),
        dataStatusLabel
      ])
    ])
  }

  private func page(_ views: [NSView]) -> NSView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    return stack
  }

  private func section(_ title: String, _ views: [NSView]) -> NSView {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    let stack = NSStackView(views: [titleLabel] + views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 7
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

  private func button(_ title: String, _ command: ControlCommand) -> NSButton {
    let control = NSButton()
    configureButton(control, title: title, command: command)
    return control
  }

  private func configureButton(_ control: NSButton, title: String, command: ControlCommand) {
    control.title = title
    bind(control, to: command)
    control.bezelStyle = .rounded
    control.setAccessibilityLabel(title)
  }

  private func configureCheckbox(_ control: NSButton, title: String, command: ControlCommand) {
    configureCheckbox(control, title: title, action: #selector(performControlCommand(_:)))
    control.tag = command.rawValue
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

  private func configurePopup(_ popup: NSPopUpButton, command: ControlCommand) {
    popup.removeAllItems()
    bind(popup, to: command)
  }

  private func bind(_ control: NSControl, to command: ControlCommand) {
    control.tag = command.rawValue
    control.target = self
    control.action = #selector(performControlCommand(_:))
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
    let modifierName = modifierTooltip(title)
    control.toolTip = modifierName
    control.setAccessibilityLabel("\(modifierName) modifier")
    control.setAccessibilityHelp("Include or remove the \(modifierName) key from this shortcut.")
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
    case .panelSide:
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
    let cloudActionsEnabled = settings.iCloudSyncEnabled
      && cloudStatus?.isAvailable == true
      && !dataOperationInProgress
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

  @objc private func performControlCommand(_ sender: NSControl) {
    guard let command = ControlCommand(rawValue: sender.tag) else { return }
    switch command {
    case .historyLength:
      settings.maxHistoryItems = historyStepper.integerValue
      refreshHistoryLimitControls()
    case .historyRetention:
      if let rawValue = historyRetentionPopup.selectedItem?.representedObject as? Int,
         let retention = HistoryRetention(rawValue: rawValue) {
        settings.historyRetention = retention
      }
    case .pruneDuplicates:
      settings.pruneDuplicates = pruneDuplicatesButton.state == .on
    case .keepFirstImage:
      settings.keepFirstImage = keepFirstImageButton.state == .on
    case .defaultSort:
      if let rawValue = defaultSortPopup.selectedItem?.representedObject as? Int,
         let mode = ClipboardSortMode(rawValue: rawValue) {
        settings.defaultSortMode = mode
      }
    case .launchAtLogin:
      let enabled = launchAtLoginButton.state == .on
      settings.launchAtLogin = enabled
      if !enabled {
        settings.setLaunchAtLoginStatus(message: "")
      }
      refreshLaunchAtLoginControls()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.refreshLaunchAtLoginControls()
      }
    case .showMenuBarIcon:
      let shouldShow = showMenuBarIconButton.state == .on
      settings.showMenuBarIcon = shouldShow
      if !shouldShow && !settings.showDockIcon {
        settings.showDockIcon = true
      }
      refreshVisibilityControls()
    case .showDockIcon:
      let shouldShow = showDockIconButton.state == .on
      settings.showDockIcon = shouldShow
      if !shouldShow && !settings.showMenuBarIcon {
        settings.showMenuBarIcon = true
      }
      refreshVisibilityControls()
    case .panelSide:
      if let rawValue = panelSidePopup.selectedItem?.representedObject as? Int,
         let side = ClipboardPanelSide(rawValue: rawValue) {
        settings.panelSide = side
      }
    case .pauseCapture:
      if pauseCaptureButton.state == .on {
        settings.pauseCaptureUntil = nil
        settings.pauseCapture = true
      } else {
        settings.pauseCapture = false
        settings.pauseCaptureUntil = nil
      }
    case .excludeSensitive:
      settings.excludeSensitive = excludeSensitiveButton.state == .on
    case .includeImageText:
      settings.includeImageTextInSearch = includeImageTextButton.state == .on
    case .clearHistoryOnQuit:
      settings.clearHistoryOnQuit = clearHistoryOnQuitButton.state == .on
    case .hideFromScreenCapture:
      settings.hideFromScreenCapture = hideFromScreenCaptureButton.state == .on
    case .requestAccessibility: requestAccessibilityAccess()
    case .refreshAccessibility: refreshAccessibilityPermissionStatus()
    case .pollProfile:
      if let rawValue = pollProfilePopup.selectedItem?.representedObject as? Int,
         let profile = AppConfiguration.PollProfile(rawValue: rawValue) {
        settings.pollProfileRaw = profile
      }
    case .cacheLimit:
      let megabytes = Int(cacheSlider.doubleValue.rounded())
      settings.imageCacheMaxBytes = Int64(megabytes * 1024 * 1024)
      refreshCacheControls()
    case .iCloudSync:
      let enabled = iCloudSyncButton.state == .on
      settings.iCloudSyncEnabled = enabled
      settings.setCloudSyncStatus(message: "")
      if !enabled {
        cachedCloudSyncStatus = nil
      }
      refreshCloudSyncControls(refreshStatus: enabled && cachedCloudSyncStatus == nil)
    case .openHistoryFolder: openHistoryFolder()
    case .exportArchive: exportClipboardArchive()
    case .importArchive: importClipboardArchive()
    case .pushICloudArchive: pushICloudSyncArchive()
    case .pullICloudArchive: pullICloudSyncArchive()
    case .revealICloudFile: revealICloudSyncFile()
    case .clearHistory: clearClipboardHistory()
    case .clearCache: clearThumbnailCache()
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

  private func requestAccessibilityAccess() {
    _ = AccessibilityPermissionService.requestPromptIfNeeded()
    if !AccessibilityPermissionService.isTrusted {
      AccessibilityPermissionService.openSystemSettings()
    }
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted ? "" : "Accessibility permission not granted."
    )
    refreshAccessibilityPermissionStatus()
  }

  private func refreshAccessibilityPermissionStatus() {
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted
      ? ""
      : "Accessibility permission not granted."
    )
    refreshAccessibilityPermissionStatusLabel()
  }

  private func openHistoryFolder() {
    NSWorkspace.shared.open(ClipboardStore.storageDirectory())
  }

  private func exportClipboardArchive() {
    let panel = NSSavePanel()
    panel.title = "Export ClipBored Archive"
    panel.nameFieldStringValue = defaultArchiveFileName()
    configureArchivePanel(panel)

    guard panel.runModal() == .OK, let url = panel.url else { return }
    setDataStatus("Exporting archive…")
    performDataOperation({ [store] in
      Result { try store.exportArchive(to: url) }
    }) { [weak self] result in
      switch result {
      case .success(let summary):
        self?.setDataStatus("Exported \(summary.itemCount) clips and \(summary.sidecarCount) attachments.")
      case .failure(let error):
        self?.setDataStatus(error.localizedDescription)
      }
    }
  }

  private func importClipboardArchive() {
    let panel = NSOpenPanel()
    panel.title = "Import ClipBored Archive"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    configureArchivePanel(panel)

    guard panel.runModal() == .OK, let url = panel.url else { return }
    setDataStatus("Importing archive…")
    performDataOperation({ [store] in
      Result { try store.importArchive(from: url) }
    }) { [weak self] result in
      switch result {
      case .success(let summary):
        var message = "Imported \(summary.itemCount) clips and \(summary.sidecarCount) attachments."
        if summary.skippedItemCount > 0 || summary.skippedSidecarCount > 0 {
          message += " Skipped \(summary.skippedItemCount) clips and \(summary.skippedSidecarCount) attachments."
        }
        self?.setDataStatus(message)
      case .failure(let error):
        self?.setDataStatus(error.localizedDescription)
      }
    }
  }

  private func pushICloudSyncArchive() {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Sync before syncing.")
      return
    }

    settings.setCloudSyncStatus(message: "Syncing with iCloud…")
    performDataOperation({ [cloudSyncService, store] in
      Result {
        let summary = try cloudSyncService.push(store: store)
        return (summary, cloudSyncService.status())
      }
    }) { [weak self] result in
      switch result {
      case .success(let (summary, status)):
        self?.cachedCloudSyncStatus = status
        self?.settings.setCloudSyncStatus(message: "Synced \(summary.itemCount) clips and \(summary.sidecarCount) attachments to iCloud.")
      case .failure(let error):
        self?.settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
      }
    }
  }

  private func pullICloudSyncArchive() {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Sync before restoring.")
      return
    }

    settings.setCloudSyncStatus(message: "Restoring from iCloud…")
    performDataOperation({ [cloudSyncService, store] in
      Result {
        let summary = try cloudSyncService.pull(store: store)
        return (summary, cloudSyncService.status())
      }
    }) { [weak self] result in
      switch result {
      case .success(let (summary, status)):
        self?.cachedCloudSyncStatus = status
        var message = "Restored \(summary.itemCount) clips and \(summary.sidecarCount) attachments from iCloud."
        if summary.skippedItemCount > 0 || summary.skippedSidecarCount > 0 {
          message += " Skipped \(summary.skippedItemCount) clips and \(summary.skippedSidecarCount) attachments."
        }
        self?.settings.setCloudSyncStatus(message: message)
      case .failure(let error):
        self?.settings.setCloudSyncStatus(message: "iCloud Sync failed: \(error.localizedDescription)")
      }
    }
  }

  private func performDataOperation<ResultValue>(
    _ operation: @escaping () -> ResultValue,
    completion: @escaping (ResultValue) -> Void
  ) {
    dataOperationInProgress = true
    exportArchiveButton.isEnabled = false
    importArchiveButton.isEnabled = false
    refreshCloudSyncControls(refreshStatus: false)
    dataOperationQueue.addOperation { [weak self] in
      let result = operation()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.dataOperationInProgress = false
        self.exportArchiveButton.isEnabled = true
        self.importArchiveButton.isEnabled = true
        completion(result)
        self.refreshCloudSyncControls(refreshStatus: false)
      }
    }
  }

  private func revealICloudSyncFile() {
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

  private func clearClipboardHistory() {
    guard confirmDestructiveAction(
      title: "Clear Clipboard History?",
      message: "This permanently removes saved clipboard items, app-managed attachments, temporary decrypted previews, and the local fallback encryption key when present. The current system clipboard is not changed.",
      buttonTitle: "Clear History"
    ) else { return }
    store.removeAll()
    cacheService.clearTemporaryPreviews()
    setDataStatus("Cleared clipboard history.")
  }

  private func clearThumbnailCache() {
    guard confirmDestructiveAction(
      title: "Clear Thumbnail Cache?",
      message: "This removes cached image previews and temporary decrypted previews. ClipBored will recreate previews as needed.",
      buttonTitle: "Clear Cache"
    ) else { return }
    cacheService.clearCache()
    setDataStatus("Cleared thumbnail cache.")
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

}

private struct ShortcutControlSet {
  let keyField: NSTextField
  let command: NSButton
  let option: NSButton
  let control: NSButton
  let shift: NSButton
}
