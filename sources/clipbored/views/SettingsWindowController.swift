import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
  private enum Metrics {
    static let windowSize = NSSize(width: 820, height: 650)
    static let minimumWindowSize = NSSize(width: 740, height: 460)
    static let settingsLabelWidth: CGFloat = 128
  }
  private enum ControlCommand: Int {
    case historyLength, defaultSort
    case launchAtLogin, showMenuBarIcon, showDockIcon
    case soundVolume, previewCopySound, previewPasteSound
    case pauseCapture
    case requestAccessibility, refreshAccessibility
    case cacheLimit
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
  private let previewSound: (ClipboardSound) -> Void
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
  private var selectedTabIndex = 0
  private var sectionButtons: [NSButton] = []
  private var controlBindings: [SettingsControlBinding] = []

  private let historyLabel = NSTextField(labelWithString: "")
  private let historyStepper = NSStepper()
  private let historyRetentionPopup = NSPopUpButton()
  private let pruneDuplicatesButton = NSButton()
  private let keepFirstImageButton = NSButton()
  private let defaultSortPopup = NSPopUpButton()
  private let launchAtLoginButton = NSButton()
  private let showMenuBarIconButton = NSButton()
  private let goldMenuBarIconButton = NSButton()
  private let showDockIconButton = NSButton()
  private let panelSidePopup = NSPopUpButton()
  private let shelfLayoutPopup = NSPopUpButton()
  private var shelfSideRow: NSView?
  private let shelfWidthPopup = NSPopUpButton()
  private let largerShelfTextButton = NSButton()
  private let copySoundButton = NSButton()
  private let pasteSoundButton = NSButton()
  private let copySoundPreview = ShelfNavigationButton()
  private let pasteSoundPreview = ShelfNavigationButton()
  private let soundVolumeSlider = NSSlider()
  private let soundVolumeLabel = NSTextField(labelWithString: "")
  private var shortcutRecorders: [Int: ShortcutRecorderButton] = [:]
  private let launchStatusLabel = NSTextField(labelWithString: "")

  private let shortcutStatusLabel = NSTextField(labelWithString: "")

  private let pauseCaptureButton = NSButton()
  private let captureStatusLabel = NSTextField(labelWithString: "")
  private let excludeSensitiveButton = NSButton()
  private let includeImageTextButton = NSButton()
  private var allowedKindButtons: [(ClipboardItemKind, NSButton)] = []

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
    settings: SettingsModel, store: ClipboardStore, cacheService: ClipboardCacheService,
    cloudSyncService: ClipboardCloudSyncServicing = ClipboardCloudSyncService(), previewSound: @escaping (ClipboardSound) -> Void = { _ in }
  ) {
    self.settings = settings
    self.store = store
    self.cacheService = cacheService
    self.cloudSyncService = cloudSyncService
    self.previewSound = previewSound
    super.init()

    let windowRect = NSRect(origin: .zero, size: Metrics.windowSize)
    let window = NSWindow(
      contentRect: windowRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.title = "Goldfish Settings"
    window.backgroundColor = ClipboardShelfStyle.windowBackground
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.contentView = makeContentView()
    window.isReleasedWhenClosed = false
    window.contentMinSize = Metrics.minimumWindowSize
    window.delegate = self
    window.center()
    self.window = window
    settings.observe { [weak self] change in DispatchQueue.main.async { self?.refreshFromSettings(for: change) } }
    refreshFromSettings(refreshCloudSyncStatus: true)
    fitSelectedTab(animated: false)
  }

  func show() {
    guard let window else { return }
    refreshFromSettings(refreshCloudSyncStatus: true)
    fitSelectedTab(animated: false)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) { commitPendingEditorDrafts() }

  private func makeContentView() -> NSView {
    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.tabViewType = .noTabsNoBorder
    tabView.addTabViewItem(tab("General", generalSettingsView()))
    tabView.addTabViewItem(tab("Shortcuts", shortcutSettingsView()))
    tabView.addTabViewItem(tab("Capture", captureSettingsView()))
    tabView.addTabViewItem(tab("Privacy", privacySettingsView()))
    tabView.addTabViewItem(tab("Performance", performanceSettingsView()))
    tabView.addTabViewItem(tab("Data", dataSettingsView()))

    let sidebar = NSVisualEffectView()
    sidebar.material = .sidebar
    sidebar.blendingMode = .behindWindow
    sidebar.state = .active
    let brand = NSTextField(labelWithString: "Goldfish")
    brand.font = .systemFont(ofSize: 19, weight: .semibold)
    let brandIcon = NSImageView(image: NSImage(systemSymbolName: "fish.fill", accessibilityDescription: nil) ?? NSImage())
    brandIcon.contentTintColor = ClipboardShelfStyle.brandAccent
    brandIcon.widthAnchor.constraint(equalToConstant: 26).isActive = true
    let brandRow = NSStackView(views: [brandIcon, brand])
    brandRow.spacing = 8
    let symbols = ["slider.horizontal.3", "command", "doc.on.clipboard", "lock.shield", "speedometer", "externaldrive"]
    let navigation = NSStackView()
    navigation.orientation = .vertical
    navigation.alignment = .leading
    navigation.spacing = 4
    for (index, title) in Self.tabTitles.enumerated() {
      let button = ShelfNavigationButton(title: title, target: self, action: #selector(settingsSectionChanged(_:)))
      button.tag = index
      button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)
      button.imagePosition = .imageLeading
      button.image?.size = NSSize(width: 16, height: 16)
      button.alignment = .left
      button.font = .systemFont(ofSize: 13, weight: .medium)
      button.setAccessibilityLabel(title)
      button.state = index == 0 ? .on : .off
      button.heightAnchor.constraint(equalToConstant: 36).isActive = true
      navigation.addArrangedSubview(button)
      button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
      sectionButtons.append(button)
    }
    let container = NSView()
    for view in [sidebar, tabView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)
    }
    for view in [brandRow, navigation] {
      view.translatesAutoresizingMaskIntoConstraints = false
      sidebar.addSubview(view)
    }
    NSLayoutConstraint.activate([
      sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor), sidebar.topAnchor.constraint(equalTo: container.topAnchor),
      sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 180),
      brandRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),
      brandRow.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 26),
      navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
      navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
      navigation.topAnchor.constraint(equalTo: brandRow.bottomAnchor, constant: 28),
      tabView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 28),
      tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
      tabView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 28),
      tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
    ])
    return container
  }

  @objc private func settingsSectionChanged(_ sender: NSButton) {
    let index = sender.tag
    guard index >= 0, index < tabView.numberOfTabViewItems else { return }
    commitPendingEditorDrafts()
    selectedTabIndex = index
    for button in sectionButtons {
      button.state = button.tag == index ? .on : .off
      button.needsDisplay = true
    }
    tabView.selectTabViewItem(at: index)
    fitSelectedTab(animated: false)
  }

  private func fitSelectedTab(animated: Bool) {
    // Settings keeps a stable frame as sections change. Long pages scroll.
    window?.contentView?.layoutSubtreeIfNeeded()
    tabView.selectedTabViewItem?.view?.needsLayout = true
    tabView.selectedTabViewItem?.view?.layoutSubtreeIfNeeded()
  }

  private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
    let item = NSTabViewItem(identifier: title)
    item.label = title
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 25, weight: .bold)
    let subtitles = [
      "General": "Make Goldfish feel at home on your Mac.", "Shortcuts": "Keep your hands on the keyboard.",
      "Capture": "Choose what your clipboard remembers.", "Privacy": "Control how your history is stored and shared.",
      "Performance": "Balance responsiveness and storage.", "Data": "Back up, restore, and manage your history.",
    ]
    let introduction = caption(subtitles[title] ?? "")
    introduction.font = .systemFont(ofSize: 13)
    let header = NSStackView(views: [heading, introduction])
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 7
    let content = page([header, view])
    content.setCustomSpacing(24, after: header)
    item.view = SettingsPageScrollView(page: content)
    return item
  }

  private func generalSettingsView() -> NSView {
    historyStepper.minValue = Double(AppConfiguration.minHistoryLength)
    historyStepper.maxValue = Double(AppConfiguration.maxHistoryLength)
    historyStepper.increment = 25
    bind(historyStepper, to: .historyLength)
    historyStepper.setAccessibilityLabel("History length")
    configurePopup(
      historyRetentionPopup, setting: \.historyRetention, change: .historyRetention, values: HistoryRetention.allCases, title: { $0.title })
    historyRetentionPopup.setAccessibilityLabel("Keep history")

    configureCheckbox(pruneDuplicatesButton, title: "Ignore duplicate items", setting: \.pruneDuplicates, change: .pruneDuplicates)
    configureCheckbox(
      keepFirstImageButton, title: "Reuse the original image for duplicate copies", setting: \.keepFirstImage, change: .keepFirstImage)
    keepFirstImageButton.toolTip =
      "When duplicate items are ignored, keep the first stored image file. The clip still moves to the top of recent history."
    keepFirstImageButton.setAccessibilityHelp(keepFirstImageButton.toolTip)
    configurePopup(defaultSortPopup, command: .defaultSort)
    defaultSortPopup.setAccessibilityLabel("Sort order")
    addPopupItem("Newest first", 0, to: defaultSortPopup)
    addPopupItem("Most used first", 1, to: defaultSortPopup)
    configureCheckbox(launchAtLoginButton, title: "Launch at login", command: .launchAtLogin)
    configureCheckbox(showMenuBarIconButton, title: "Show Goldfish in the menu bar", command: .showMenuBarIcon)
    configureCheckbox(goldMenuBarIconButton, title: "Gold menu bar icon", setting: \.goldMenuBarIcon, change: .goldMenuBarIcon)
    configureCheckbox(showDockIconButton, title: "Show Goldfish in the Dock", command: .showDockIcon)
    configurePopup(shelfLayoutPopup, setting: \.shelfLayout, change: .other, values: ClipboardShelfLayout.allCases, title: { $0.title })
    shelfLayoutPopup.setAccessibilityLabel("Shelf layout")
    configurePopup(panelSidePopup, setting: \.panelSide, change: .panelSide, values: ClipboardPanelSide.allCases, title: { $0.title })
    panelSidePopup.setAccessibilityLabel("Shelf side")
    configurePopup(shelfWidthPopup, setting: \.shelfWidth, change: .other, values: ClipboardShelfWidth.allCases, title: { $0.title })
    shelfWidthPopup.setAccessibilityLabel("Shelf size")
    configureCheckbox(largerShelfTextButton, title: "Larger text in clips", setting: \.largerShelfText, change: .other)
    configureStatusLabel(launchStatusLabel)

    let sideRow = labeledRow("Shelf side", panelSidePopup)
    shelfSideRow = sideRow
    return page([
      section(
        "History",
        [
          labeledRow("Keep history", historyRetentionPopup), labeledRow("Clip limit", row([historyLabel, historyStepper])),
          pruneDuplicatesButton, keepFirstImageButton,
        ]),
      section(
        "Shelf",
        [
          labeledRow("Sort order", defaultSortPopup), labeledRow("Layout", shelfLayoutPopup), sideRow,
          labeledRow("Shelf size", shelfWidthPopup), largerShelfTextButton,
        ]), soundSettingsSection(),
      section(
        "Startup & visibility", [launchAtLoginButton, showMenuBarIconButton, goldMenuBarIconButton, showDockIconButton, launchStatusLabel]),
    ])
  }

  private func soundSettingsSection() -> NSView {
    configureCheckbox(copySoundButton, title: "Copy sound", setting: \.copySoundEnabled, change: .soundEffects)
    copySoundButton.toolTip = "Play a soft camera click when a copy is captured from any app, or copied from Goldfish."
    copySoundButton.setAccessibilityHelp(copySoundButton.toolTip)
    configureCheckbox(pasteSoundButton, title: "Paste sound", setting: \.pasteSoundEnabled, change: .soundEffects)
    pasteSoundButton.toolTip = "Play a soft camera click when Goldfish sends a paste to another app."
    pasteSoundButton.setAccessibilityHelp(pasteSoundButton.toolTip)
    let soundRows = [
      (copySoundButton, copySoundPreview, ControlCommand.previewCopySound, "Preview copy sound"),
      (pasteSoundButton, pasteSoundPreview, ControlCommand.previewPasteSound, "Preview paste sound"),
    ].map { toggle, preview, command, label -> NSView in
      bind(preview, to: command)
      preview.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
      preview.imagePosition = .imageOnly
      preview.setAccessibilityLabel(label)
      preview.toolTip = label
      preview.widthAnchor.constraint(equalToConstant: 28).isActive = true
      preview.heightAnchor.constraint(equalToConstant: 28).isActive = true
      let space = NSView()
      space.setContentHuggingPriority(.defaultLow, for: .horizontal)
      let row = NSStackView(views: [toggle, space, preview])
      row.alignment = .centerY
      row.spacing = 8
      return row
    }
    soundVolumeSlider.minValue = 0
    soundVolumeSlider.maxValue = 100
    soundVolumeSlider.isContinuous = true
    soundVolumeSlider.setAccessibilityLabel("Sound effects volume")
    soundVolumeSlider.setAccessibilityHelp("Percentage of your Mac's current output volume.")
    soundVolumeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    bind(soundVolumeSlider, to: .soundVolume)
    soundVolumeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    soundVolumeLabel.textColor = .secondaryLabelColor
    soundVolumeLabel.alignment = .right
    soundVolumeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
    let volumeTitle = NSTextField(labelWithString: "Volume")
    volumeTitle.widthAnchor.constraint(equalToConstant: Metrics.settingsLabelWidth).isActive = true
    let volumeRow = NSStackView(views: [volumeTitle, soundVolumeSlider, soundVolumeLabel])
    volumeRow.alignment = .centerY
    volumeRow.spacing = 8
    return section("Sound effects", soundRows + [volumeRow, caption("Soft camera clicks for captured copies and Goldfish pastes.")])
  }

  private func shortcutSettingsView() -> NSView {
    let openRow = shortcutRow("Open Clipboard", binding: settings.openShortcut, baseTag: 100)
    let settingsRow = shortcutRow("Open Settings", binding: settings.settingsShortcut, baseTag: 200)
    configureStatusLabel(shortcutStatusLabel)
    return page([
      section(
        "Shortcuts",
        [openRow, settingsRow, caption("Click a shortcut, then press the new combination. Escape cancels."), shortcutStatusLabel]),
      section(
        "While the shelf is open",
        [
          shortcutReference("Browse clips", keys: "↑  ↓  /  ←  →"), shortcutReference("Preview a clip", keys: "Space"),
          shortcutReference("Paste or copy selection", keys: "Return"), shortcutReference("Paste as plain text", keys: "⇧Return"),
          shortcutReference("Quick paste", keys: "⌘1–9"), shortcutReference("New clip / Edit clip", keys: "⌘N / ⌘E"),
          shortcutReference("Pin / Rename", keys: "⌘P / ⌘R"), shortcutReference("Delete / Undo", keys: "⌫ / ⌘Z"),
        ]),
      section(
        "Find exactly what you copied",
        [
          caption(
            "Start typing to search, or press ⌘F. Narrow your results with filters such as app:Safari, type:image, or pinboard:\"Work\".")
        ]),
    ])
  }

  private func shortcutReference(_ title: String, keys: String) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12)
    let key = NSTextField(labelWithString: keys)
    key.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    key.textColor = ClipboardShelfStyle.secondaryText
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [label, spacer, key])
    row.alignment = .centerY
    return row
  }

  private func captureSettingsView() -> NSView {
    configureCheckbox(pauseCaptureButton, title: "Pause clipboard capture", command: .pauseCapture)
    configureCheckbox(excludeSensitiveButton, title: "Exclude likely secrets", setting: \.excludeSensitive, change: .excludeSensitive)
    configureCheckbox(
      includeImageTextButton, title: "Search in image labels", setting: \.includeImageTextInSearch, change: .includeImageTextInSearch)
    configureStatusLabel(captureStatusLabel)

    let allowedRows = [
      kindCheckbox("Text", .text), kindCheckbox("Code", .code), kindCheckbox("Links", .url), kindCheckbox("Images", .image),
      kindCheckbox("Colors", .color), kindCheckbox("Audio", .audio), kindCheckbox("Videos", .video), kindCheckbox("Rich text", .richText),
      kindCheckbox("PDFs", .pdf), kindCheckbox("Files", .file),
    ]

    return page([
      section("Capture", [pauseCaptureButton, excludeSensitiveButton, includeImageTextButton, captureStatusLabel]),
      section("Allowed content types", [checkboxGrid(allowedRows)]),
      section(
        "Ignored source apps",
        [
          caption(
            "macOS does not identify which app wrote the clipboard. Goldfish applies this list to the app that is frontmost when it notices the change."
          ), IgnoredAppsEditor(settings: settings),
        ]),
    ])
  }

  private func privacySettingsView() -> NSView {
    let storageLabel = caption(
      "History stays in Application Support, encrypted with a local key. Capture pauses if the key is unavailable; storage is restricted to the current user."
    )
    let screenPrivacyLabel = caption(
      "Requests that supported capture tools exclude the shelf. This is not a guarantee; close the shelf before sharing sensitive content.")
    let permissionHelpLabel = caption("Clipboard capture works without this permission. Grant Accessibility only for direct paste.")
    configureCheckbox(clearHistoryOnQuitButton, title: "Clear history on quit", setting: \.clearHistoryOnQuit, change: .clearHistoryOnQuit)
    configureCheckbox(
      hideFromScreenCaptureButton, title: "Hide panel from screen sharing and recordings", setting: \.hideFromScreenCapture,
      change: .hideFromScreenCapture)
    configureStatusLabel(accessibilityStatusLabel)
    let requestButton = button("Open Accessibility Settings", .requestAccessibility)
    let refreshButton = button("Refresh Permission Status", .refreshAccessibility)
    configureStatusLabel(pasteStatusLabel)

    return page([
      section("Local storage", [storageLabel, clearHistoryOnQuitButton]),
      section("Screen privacy", [screenPrivacyLabel, hideFromScreenCaptureButton]),
      section(
        "Paste permission",
        [
          permissionHelpLabel, row([NSTextField(labelWithString: "Accessibility"), accessibilityStatusLabel]),
          row([requestButton, refreshButton]), pasteStatusLabel,
        ]),
    ])
  }

  private func performanceSettingsView() -> NSView {
    configurePopup(
      pollProfilePopup, setting: \.pollProfileRaw, change: .pollProfile, values: AppConfiguration.PollProfile.allCases, title: { $0.title })
    pollProfilePopup.setAccessibilityLabel("Capture responsiveness")
    cacheSlider.minValue = Double(AppConfiguration.minCacheMaxBytes) / 1024 / 1024
    cacheSlider.maxValue = Double(AppConfiguration.maxCacheMaxBytes) / 1024 / 1024
    cacheSlider.numberOfTickMarks = 0
    cacheSlider.allowsTickMarkValuesOnly = false
    bind(cacheSlider, to: .cacheLimit)
    cacheSlider.setAccessibilityLabel("Preview storage limit in megabytes")
    configureStatusLabel(cacheLabel)

    return page([
      section(
        "Capture responsiveness",
        [
          labeledRow("Responsiveness", pollProfilePopup),
          caption("Faster checks catch rapid copies sooner. Slower checks use less energy when you are copying frequently."),
        ]), section("Preview storage", [labeledRow("Limit (MB)", cacheSlider), cacheLabel]),
    ])
  }

  private func dataSettingsView() -> NSView {
    configureStatusLabel(dataStatusLabel)
    dataStatusLabel.isHidden = true
    configureStatusLabel(cloudSyncStatusLabel)
    configureCheckbox(iCloudSyncButton, title: "Back up history to iCloud", command: .iCloudSync)
    configureButton(iCloudSyncNowButton, title: "Back Up Now", command: .pushICloudArchive)
    configureButton(iCloudRestoreButton, title: "Restore from iCloud", command: .pullICloudArchive)
    configureButton(iCloudRevealButton, title: "Reveal Backup File", command: .revealICloudFile)
    configureButton(exportArchiveButton, title: "Export Archive...", command: .exportArchive)
    configureButton(importArchiveButton, title: "Import Archive...", command: .importArchive)
    let archiveLabel = caption(
      "Export your history, Pinboards, and saved attachments. External files stay in their original locations. Archives are not encrypted.")
    let cloudLabel = caption(
      "Keep a backup of your history in iCloud and restore it when needed. Changes don’t sync between Macs. Backups are not encrypted by Goldfish."
    )
    return page([
      section(
        "iCloud Backup",
        [cloudLabel, iCloudSyncButton, row([iCloudSyncNowButton, iCloudRestoreButton, iCloudRevealButton]), cloudSyncStatusLabel]),
      section("Archive", [archiveLabel, row([exportArchiveButton, importArchiveButton])]),
      section(
        "Data",
        [
          button("Open History Folder", .openHistoryFolder),
          row([button("Clear Clipboard History", .clearHistory), button("Clear Thumbnail Cache", .clearCache)]), dataStatusLabel,
        ]),
    ])
  }

  private func page(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    stack.detachesHiddenViews = true
    for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    return stack
  }

  private func section(_ title: String, _ views: [NSView]) -> NSView {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .labelColor
    let stack = NSStackView(views: [titleLabel] + views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.detachesHiddenViews = true
    stack.translatesAutoresizingMaskIntoConstraints = false
    let surface = SettingsSectionView()
    surface.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -18),
    ])
    for view in views where !(view is NSButton) { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    return surface
  }

  private func row(_ views: [NSView]) -> NSView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let stack = NSStackView(views: views + [spacer])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fill
    stack.spacing = 8
    stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return stack
  }

  private func checkboxGrid(_ controls: [NSButton]) -> NSView {
    let rows = stride(from: 0, to: controls.count, by: 2).map { index in
      let pair = NSStackView(views: Array(controls[index..<min(index + 2, controls.count)]))
      pair.distribution = .fillEqually
      pair.spacing = 12
      return pair
    }
    let grid = NSStackView(views: rows)
    grid.orientation = .vertical
    grid.alignment = .leading
    grid.spacing = 8
    for row in rows { row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true }
    return grid
  }

  private func labeledRow(_ title: String, _ control: NSView) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.widthAnchor.constraint(equalToConstant: Metrics.settingsLabelWidth).isActive = true
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if control is NSSlider {
      let result = NSStackView(views: [label, control])
      result.alignment = .centerY
      result.spacing = 8
      return result
    }
    return row([label, control])
  }

  private func caption(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = ClipboardShelfStyle.secondaryText
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

  private func configureCheckbox(
    _ control: NSButton, title: String, setting: ReferenceWritableKeyPath<SettingsModel, Bool>, change: SettingsModel.Change
  ) {
    control.setButtonType(.switch)
    control.title = title
    control.setAccessibilityLabel(title)
    controlBindings.append(.checkbox(control, settings: settings, key: setting, change: change))
  }

  private func configurePopup<Value: RawRepresentable>(
    _ popup: NSPopUpButton, setting: ReferenceWritableKeyPath<SettingsModel, Value>, change: SettingsModel.Change, values: [Value],
    title: (Value) -> String
  ) where Value.RawValue == Int {
    controlBindings.append(.popup(popup, settings: settings, key: setting, change: change, values: values, title: title))
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
    label.textColor = ClipboardShelfStyle.secondaryText
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
    label.widthAnchor.constraint(equalToConstant: Metrics.settingsLabelWidth).isActive = true

    let recorder = ShortcutRecorderButton(binding: binding, label: "\(title) shortcut")
    recorder.onRecord = { [weak self] candidate in
      guard let self else { return "Settings closed" }
      let message = self.shortcutValidationMessage(for: candidate, isOpenShortcut: baseTag == 100)
      self.settings.setShortcutStatus(message: message ?? "")
      guard message == nil else { return message }
      if baseTag == 100 { self.settings.openShortcut = candidate } else { self.settings.settingsShortcut = candidate }
      return nil
    }
    shortcutRecorders[baseTag] = recorder
    return row([label, recorder])
  }

  private func refreshFromSettings(for change: SettingsModel.Change) {
    controlBindings.forEach { $0.refresh(for: change) }
    shortcutRecorders[100]?.binding = settings.openShortcut
    shortcutRecorders[200]?.binding = settings.settingsShortcut
    switch change {
    case .maxHistoryItems: refreshHistoryLimitControls()
    case .defaultSortMode: refreshDefaultSortControl()
    case .imageCacheMaxBytes: refreshCacheControls()
    case .pruneDuplicates: keepFirstImageButton.isEnabled = settings.pruneDuplicates
    case .openShortcut, .settingsShortcut: refreshShortcutStatusLabel()
    case .launchAtLogin: refreshLaunchAtLoginControls()
    case .status: refreshStatusIndicators(refreshCloudSyncStatus: false)
    case .captureStatus: refreshCaptureStatusLabel()
    case .cloudSync: refreshCloudSyncControls(refreshStatus: settings.iCloudSyncEnabled && cachedCloudSyncStatus == nil)
    case .ignoredItemKinds: refreshAllowedKindControls()
    case .pauseCapture: refreshPauseCaptureControls()
    case .soundEffects: refreshSoundControls()
    case .showMenuBarIcon, .goldMenuBarIcon, .showDockIcon: refreshVisibilityControls()
    case .historyRetention, .includeImageTextInSearch, .ignoredApps, .keepFirstImage, .excludeSensitive, .hideFromScreenCapture,
      .clearHistoryOnQuit, .pollProfile, .panelSide:
      break
    default: refreshFromSettings(refreshCloudSyncStatus: false)
    }
  }

  private func refreshFromSettings(refreshCloudSyncStatus: Bool = false) {
    controlBindings.forEach { $0.refresh() }
    refreshHistoryLimitControls()
    refreshDefaultSortControl()
    keepFirstImageButton.isEnabled = settings.pruneDuplicates
    refreshLaunchAtLoginControls()
    refreshVisibilityControls()
    refreshSoundControls()
    shelfSideRow?.isHidden = settings.shelfLayout == .cards

    refreshPauseCaptureControls()
    refreshAllowedKindControls()

    refreshCacheControls()
    refreshStatusIndicators(refreshCloudSyncStatus: refreshCloudSyncStatus)
  }

  private func refreshHistoryLimitControls() {
    historyLabel.stringValue = "\(settings.maxHistoryItems) clips"
    historyStepper.integerValue = settings.maxHistoryItems
  }

  private func refreshDefaultSortControl() { select(defaultSortPopup, rawValue: settings.sortByUsage ? 1 : 0) }

  private func refreshAllowedKindControls() {
    for (kind, button) in allowedKindButtons { button.state = settings.ignoredItemKindsRaw.contains(kind.rawValue) ? .off : .on }
  }

  private func refreshLaunchAtLoginControls() {
    launchAtLoginButton.state = settings.launchAtLogin ? .on : .off
    let presentation = Self.launchAtLoginStatusPresentation(storedStatus: settings.launchAtLoginErrorMessage)
    launchStatusLabel.stringValue = presentation.message
    launchStatusLabel.isHidden = presentation.message.isEmpty
    launchStatusLabel.textColor = presentation.textColor
  }

  static func launchAtLoginStatusPresentation(storedStatus: String) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else { return ("", .secondaryLabelColor) }
    return (storedStatus, .systemRed)
  }

  private func refreshVisibilityControls() {
    showMenuBarIconButton.state = settings.showMenuBarIcon ? .on : .off
    goldMenuBarIconButton.isEnabled = settings.showMenuBarIcon
    showDockIconButton.state = settings.showDockIcon ? .on : .off
  }

  private func refreshSoundControls() {
    soundVolumeSlider.doubleValue = settings.soundVolume * 100
    soundVolumeLabel.stringValue = "\(Int((settings.soundVolume * 100).rounded()))%"
    copySoundPreview.isEnabled = settings.soundVolume > 0
    pasteSoundPreview.isEnabled = settings.soundVolume > 0
  }

  private func refreshPauseCaptureControls() {
    pauseCaptureButton.state = settings.pauseCapture ? .on : .off
    refreshCaptureStatusLabel()
  }

  private func refreshCaptureStatusLabel() { setCaptureStatusLabel(settings.captureStatusMessage) }

  private func setCaptureStatusLabel(_ message: String) {
    let presentation = Self.captureStatusPresentation(storedStatus: message)
    captureStatusLabel.stringValue = presentation.message
    captureStatusLabel.textColor = presentation.textColor
  }

  static func captureStatusPresentation(storedStatus: String) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else { return ("Capture status will appear after the app sees clipboard activity.", .secondaryLabelColor) }
    return (storedStatus, captureStatusColor(for: storedStatus))
  }

  private static func captureStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
    if lowercasedMessage.hasPrefix("captured") || lowercasedMessage.hasPrefix("allowed content types updated")
      || lowercasedMessage.contains("capture running") || lowercasedMessage.contains("capture is running")
      || lowercasedMessage.contains("capture resumed")
    {
      return .systemGreen
    }
    if lowercasedMessage.hasPrefix("error") || lowercasedMessage.contains("failed") || lowercasedMessage.contains("could not") {
      return .systemRed
    }
    if lowercasedMessage.hasPrefix("skipped") || lowercasedMessage.contains("ignored") || lowercasedMessage.contains("paused")
      || lowercasedMessage.contains("at least one")
    {
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
    let presentation = Self.shortcutStatusPresentation(storedStatus: settings.shortcutStatusMessage)
    shortcutStatusLabel.stringValue = presentation.message
    shortcutStatusLabel.textColor = presentation.textColor
  }

  static func shortcutStatusPresentation(storedStatus: String) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else { return ("Registered", .systemGreen) }
    return (storedStatus, .systemRed)
  }

  private func refreshAccessibilityPermissionStatusLabel() {
    let presentation = Self.accessibilityPermissionStatusPresentation(
      storedStatus: settings.accessibilityPermissionStatusMessage, isTrusted: AccessibilityPermissionService.isTrusted)
    accessibilityStatusLabel.stringValue = presentation.message
    accessibilityStatusLabel.textColor = presentation.textColor
  }

  static func accessibilityPermissionStatusPresentation(storedStatus: String, isTrusted: Bool) -> (message: String, textColor: NSColor) {
    let trimmedStatus = storedStatus.clipboardTrimmed
    guard trimmedStatus.isEmpty else { return (trimmedStatus, .systemOrange) }
    return isTrusted ? ("Granted", .systemGreen) : ("Not granted (clipboard capture still works; paste falls back to copy)", .systemOrange)
  }

  private func refreshPasteStatusLabel() {
    let presentation = Self.pasteStatusPresentation(storedStatus: settings.pasteStatusMessage)
    pasteStatusLabel.stringValue = presentation.message
    pasteStatusLabel.textColor = presentation.textColor
  }

  static func pasteStatusPresentation(storedStatus: String) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else { return ("No paste action yet.", .secondaryLabelColor) }
    return (storedStatus, pasteStatusColor(for: storedStatus))
  }

  private static func pasteStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
    if lowercasedMessage.contains("could not") || lowercasedMessage.contains("failed") { return .systemRed }
    if lowercasedMessage.contains("grant accessibility") || lowercasedMessage.contains("not granted") { return .systemOrange }
    if lowercasedMessage.hasPrefix("pasted") || lowercasedMessage.hasPrefix("copied") { return .systemGreen }
    return .secondaryLabelColor
  }

  private func refreshCacheControls() {
    cacheSlider.doubleValue = Double(settings.imageCacheMaxBytes) / 1024 / 1024
    cacheLabel.stringValue = "\(cacheLimitMegabytes) MB for previews. Original clips are stored separately."
  }

  private var cacheLimitMegabytes: Int { Int((Double(settings.imageCacheMaxBytes) / 1024 / 1024).rounded()) }

  private func setDataStatus(_ message: String) {
    let presentation = Self.dataStatusPresentation(storedStatus: message)
    dataStatusLabel.stringValue = presentation.message
    dataStatusLabel.isHidden = presentation.message.isEmpty
    dataStatusLabel.textColor = presentation.textColor
    if selectedTabIndex == 5 { fitSelectedTab(animated: false) }
  }

  static func dataStatusPresentation(storedStatus: String) -> (message: String, textColor: NSColor) {
    let storedStatus = storedStatus.clipboardTrimmed
    guard !storedStatus.isEmpty else { return ("", .secondaryLabelColor) }
    return (storedStatus, dataStatusColor(for: storedStatus))
  }

  private static func dataStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
    if lowercasedMessage.contains("could not") || lowercasedMessage.contains("couldn") || lowercasedMessage.contains("denied")
      || lowercasedMessage.contains("error") || lowercasedMessage.contains("failed") || lowercasedMessage.contains("invalid")
      || lowercasedMessage.contains("missing") || lowercasedMessage.contains("not permitted") || lowercasedMessage.contains("unavailable")
    {
      return .systemRed
    }
    if lowercasedMessage.contains("skipped") { return .systemOrange }
    if lowercasedMessage.hasPrefix("exported") || lowercasedMessage.hasPrefix("imported") || lowercasedMessage.hasPrefix("cleared") {
      return .systemGreen
    }
    return .secondaryLabelColor
  }

  private func refreshCloudSyncControls(refreshStatus: Bool) {
    iCloudSyncButton.state = settings.iCloudSyncEnabled ? .on : .off
    let cloudStatus = cloudSyncStatus(refresh: refreshStatus)
    let presentation = Self.cloudSyncStatusPresentation(
      storedStatus: settings.cloudSyncStatusMessage, isSyncEnabled: settings.iCloudSyncEnabled, cloudStatus: cloudStatus)
    cloudSyncStatusLabel.stringValue = presentation.message
    cloudSyncStatusLabel.textColor = presentation.textColor
    let cloudActionsEnabled = settings.iCloudSyncEnabled && cloudStatus?.isAvailable == true && !dataOperationInProgress
    iCloudSyncNowButton.isEnabled = cloudActionsEnabled
    iCloudRestoreButton.isEnabled = cloudActionsEnabled
    iCloudRevealButton.isEnabled = cloudActionsEnabled
  }

  static func cloudSyncStatusPresentation(storedStatus: String, isSyncEnabled: Bool, cloudStatus: ClipboardCloudSyncStatus?) -> (
    message: String, textColor: NSColor
  ) {
    let storedStatus = storedStatus.clipboardTrimmed
    if !storedStatus.isEmpty { return (storedStatus, cloudSyncStatusColor(for: storedStatus)) }

    if !isSyncEnabled { return ("iCloud Backup is off.", .secondaryLabelColor) }

    guard let cloudStatus else { return ("iCloud Backup is unavailable.", .systemOrange) }

    return (cloudStatus.message, cloudStatus.isAvailable ? .secondaryLabelColor : .systemOrange)
  }

  private static func cloudSyncStatusColor(for message: String) -> NSColor {
    let lowercasedMessage = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
    if lowercasedMessage.contains("failed") { return .systemRed }
    if lowercasedMessage.contains("unavailable") || lowercasedMessage.contains("turn on") || lowercasedMessage.contains("skipped") {
      return .systemOrange
    }
    if lowercasedMessage.hasPrefix("backed up") || lowercasedMessage.hasPrefix("restored") || lowercasedMessage.hasPrefix("opened") {
      return .systemGreen
    }
    return .secondaryLabelColor
  }

  private func cloudSyncStatus(refresh: Bool) -> ClipboardCloudSyncStatus? {
    guard settings.iCloudSyncEnabled else {
      cachedCloudSyncStatus = nil
      return nil
    }

    if refresh || cachedCloudSyncStatus == nil { cachedCloudSyncStatus = cloudSyncService.status() }
    return cachedCloudSyncStatus
  }

  private func commitPendingEditorDrafts() { shortcutRecorders.values.forEach { $0.cancelRecording() } }

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
    case .defaultSort: settings.sortByUsage = defaultSortPopup.selectedItem?.representedObject as? Int == 1
    case .soundVolume:
      settings.soundVolume = soundVolumeSlider.doubleValue / 100
      refreshSoundControls()
    case .previewCopySound: previewSound(.copy)
    case .previewPasteSound: previewSound(.paste)
    case .launchAtLogin:
      let enabled = launchAtLoginButton.state == .on
      settings.launchAtLogin = enabled
      if !enabled { settings.setLaunchAtLoginStatus(message: "") }
      refreshLaunchAtLoginControls()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refreshLaunchAtLoginControls() }
    case .showMenuBarIcon:
      let shouldShow = showMenuBarIconButton.state == .on
      settings.showMenuBarIcon = shouldShow
      if !shouldShow && !settings.showDockIcon { settings.showDockIcon = true }
      refreshVisibilityControls()
    case .showDockIcon:
      let shouldShow = showDockIconButton.state == .on
      settings.showDockIcon = shouldShow
      if !shouldShow && !settings.showMenuBarIcon { settings.showMenuBarIcon = true }
      refreshVisibilityControls()
    case .pauseCapture:
      settings.pauseCaptureUntil = nil
      settings.pauseCapture = pauseCaptureButton.state == .on
    case .requestAccessibility: requestAccessibilityAccess()
    case .refreshAccessibility: refreshAccessibilityPermissionStatus()
    case .cacheLimit:
      let megabytes = Int(cacheSlider.doubleValue.rounded())
      settings.imageCacheMaxBytes = Int64(megabytes * 1024 * 1024)
      refreshCacheControls()
    case .iCloudSync:
      let enabled = iCloudSyncButton.state == .on
      settings.iCloudSyncEnabled = enabled
      settings.setCloudSyncStatus(message: "")
      if !enabled { cachedCloudSyncStatus = nil }
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

  private func requestAccessibilityAccess() {
    _ = AccessibilityPermissionService.requestPromptIfNeeded()
    if !AccessibilityPermissionService.isTrusted { AccessibilityPermissionService.openSystemSettings() }
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted ? "" : "Accessibility permission not granted.")
    refreshAccessibilityPermissionStatus()
  }

  private func refreshAccessibilityPermissionStatus() {
    settings.setAccessibilityPermissionStatus(
      message: AccessibilityPermissionService.isTrusted ? "" : "Accessibility permission not granted.")
    refreshAccessibilityPermissionStatusLabel()
  }

  private func openHistoryFolder() { NSWorkspace.shared.open(ClipboardStore.storageDirectory()) }

  private func exportClipboardArchive() {
    let panel = NSSavePanel()
    panel.title = "Export Goldfish Archive"
    ClipboardArchivePanel.configure(panel)
    panel.nameFieldStringValue = ClipboardArchivePanel.suggestedName(defaultArchiveFileName())

    guard let window, window.attachedSheet == nil else { return }
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      self.setDataStatus("Exporting archive…")
      self.performDataOperation({ [store = self.store] in Result { try store.exportArchive(to: url) } }) { [weak self] result in
        switch result {
        case .success(let summary): self?.setDataStatus("Exported \(summary.itemCount) clips and \(summary.sidecarCount) attachments.")
        case .failure(let error): self?.setDataStatus(error.localizedDescription)
        }
      }
    }
  }

  private func importClipboardArchive() {
    let panel = NSOpenPanel()
    panel.title = "Import Goldfish Archive"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    ClipboardArchivePanel.configure(panel)

    guard let window, window.attachedSheet == nil else { return }
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      self.setDataStatus("Importing archive…")
      self.performDataOperation({ [store = self.store] in Result { try store.importArchive(from: url) } }) { [weak self] result in
        switch result {
        case .success(let summary):
          var message = "Imported \(summary.itemCount) clips and \(summary.sidecarCount) attachments."
          if summary.skippedItemCount > 0 || summary.skippedSidecarCount > 0 {
            message += " Skipped \(summary.skippedItemCount) clips and \(summary.skippedSidecarCount) attachments."
          }
          self?.setDataStatus(message)
        case .failure(let error): self?.setDataStatus(error.localizedDescription)
        }
      }
    }
  }

  private func pushICloudSyncArchive() {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Backup before backing up.")
      return
    }

    settings.setCloudSyncStatus(message: "Backing up to iCloud…")
    performDataOperation({ [cloudSyncService, store] in
      Result {
        let summary = try cloudSyncService.push(store: store)
        return (summary, cloudSyncService.status())
      }
    }) { [weak self] result in
      switch result {
      case .success(let (summary, status)):
        self?.cachedCloudSyncStatus = status
        self?.settings.setCloudSyncStatus(
          message: "Backed up \(summary.itemCount) clips and \(summary.sidecarCount) attachments to iCloud.")
      case .failure(let error): self?.settings.setCloudSyncStatus(message: "iCloud Backup failed: \(error.localizedDescription)")
      }
    }
  }

  private func pullICloudSyncArchive() {
    guard settings.iCloudSyncEnabled else {
      settings.setCloudSyncStatus(message: "Turn on iCloud Backup before restoring.")
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
      case .failure(let error): self?.settings.setCloudSyncStatus(message: "iCloud Backup failed: \(error.localizedDescription)")
      }
    }
  }

  private func performDataOperation<ResultValue>(_ operation: @escaping () -> ResultValue, completion: @escaping (ResultValue) -> Void) {
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
      settings.setCloudSyncStatus(message: "Opened iCloud backup location.")
    } catch { settings.setCloudSyncStatus(message: "iCloud Backup failed: \(error.localizedDescription)") }
  }

  private func clearClipboardHistory() {
    confirmDestructiveAction(
      title: "Clear Clipboard History?",
      message:
        "This permanently removes all clips, including pinned clips and Pinboard contents, and saved attachments. Your current system clipboard stays unchanged.",
      buttonTitle: "Clear History"
    ) { [weak self] in
      self?.store.removeAll()
      self?.cacheService.clearTemporaryPreviews()
      self?.setDataStatus("Cleared clipboard history.")
    }
  }

  private func clearThumbnailCache() {
    confirmDestructiveAction(
      title: "Clear Thumbnail Cache?",
      message: "This removes cached previews. Goldfish will recreate them when needed. Your saved clips remain available.",
      buttonTitle: "Clear Cache"
    ) { [weak self] in
      self?.cacheService.clearCache()
      self?.setDataStatus("Cleared thumbnail cache.")
    }
  }

  private func confirmDestructiveAction(title: String, message: String, buttonTitle: String, onConfirm: @escaping () -> Void) {
    guard let window, window.attachedSheet == nil else { return }
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: buttonTitle)
    alert.buttons[0].keyEquivalent = "\u{1b}"
    alert.buttons[1].keyEquivalent = ""
    alert.window.defaultButtonCell = nil
    alert.window.initialFirstResponder = alert.buttons[0]
    alert.beginSheetModal(for: window) { response in if response == .alertSecondButtonReturn { onConfirm() } }
  }

  private func defaultArchiveFileName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    return "Goldfish-\(formatter.string(from: Date())).\(ClipboardArchiveService.fileExtension)"
  }

  private func shortcutValidationMessage(for binding: ShortcutBinding, isOpenShortcut: Bool) -> String? {
    if let failure = ShortcutManager.validationFailure(for: binding) { return failure.message }

    let otherBinding = isOpenShortcut ? settings.settingsShortcut : settings.openShortcut
    if binding == otherBinding { return ShortcutManager.RegistrationStatus.conflict(binding.displayText).message }

    return nil
  }

}
