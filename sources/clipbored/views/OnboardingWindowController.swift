import AppKit

final class OnboardingWindowController: NSObject, NSWindowDelegate {
  enum ShortcutChoice: String {
    case pasteStyle
    case clipBoredDefault
    case current
  }

  struct PresentationChoice: Equatable {
    let showMenuBarIcon: Bool
    let showDockIcon: Bool
  }

  static let pasteStyleOpenShortcut = ShortcutBinding(
    key: "v",
    modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
  )

  static func normalizedPresentation(showMenuBarIcon: Bool, showDockIcon: Bool) -> PresentationChoice {
    if showMenuBarIcon || showDockIcon {
      return PresentationChoice(showMenuBarIcon: showMenuBarIcon, showDockIcon: showDockIcon)
    }
    return PresentationChoice(showMenuBarIcon: true, showDockIcon: false)
  }

  static func initialShortcutChoice(for binding: ShortcutBinding, onboardingCompleted: Bool) -> ShortcutChoice {
    if binding == pasteStyleOpenShortcut {
      return .pasteStyle
    }
    if binding == AppConfiguration.defaultOpenShortcut {
      return onboardingCompleted ? .clipBoredDefault : .pasteStyle
    }
    return .current
  }

  static func shortcutBinding(for choice: ShortcutChoice, current: ShortcutBinding) -> ShortcutBinding {
    switch choice {
    case .pasteStyle:
      return pasteStyleOpenShortcut
    case .clipBoredDefault:
      return AppConfiguration.defaultOpenShortcut
    case .current:
      return current
    }
  }

  private let settings: SettingsModel
  private let onOpenAccessibility: () -> Void
  private let onFinish: () -> Void
  private var window: NSWindow?
  private var didComplete = false

  private let shortcutPopup = NSPopUpButton()
  private let historyRetentionPopup = NSPopUpButton()
  private let showMenuBarIconButton = NSButton()
  private let showDockIconButton = NSButton()
  private let launchAtLoginButton = NSButton()
  private let iCloudSyncButton = NSButton()
  private let permissionStatusLabel = NSTextField(labelWithString: "")

  init(
    settings: SettingsModel,
    onOpenAccessibility: @escaping () -> Void,
    onFinish: @escaping () -> Void
  ) {
    self.settings = settings
    self.onOpenAccessibility = onOpenAccessibility
    self.onFinish = onFinish
    super.init()

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Set Up ClipBored"
    window.contentView = makeContentView()
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.center()
    self.window = window
    refreshFromSettings()
  }

  func show() {
    guard let window else { return }
    refreshFromSettings()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func refreshPermissionStatus() {
    let isTrusted = AccessibilityPermissionService.isTrusted
    permissionStatusLabel.stringValue = isTrusted ? "Granted" : "Not granted; paste actions will copy instead."
    permissionStatusLabel.textColor = isTrusted ? .systemGreen : .systemOrange
  }

  func windowWillClose(_ notification: Notification) {
    guard !didComplete else { return }
    completeSetup(applySelections: false, closeWindow: false)
  }

  private func makeContentView() -> NSView {
    configureShortcutPopup()
    configureHistoryRetentionPopup()
    configureCheckbox(showMenuBarIconButton, title: "Show ClipBored in the menu bar", action: #selector(entryPointChanged))
    configureCheckbox(showDockIconButton, title: "Show ClipBored in the Dock", action: #selector(entryPointChanged))
    configureCheckbox(launchAtLoginButton, title: "Launch at login", action: nil)
    configureCheckbox(iCloudSyncButton, title: "Sync history with iCloud when available", action: nil)
    configureStatusLabel(permissionStatusLabel)

    let content = NSView()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)

    let titleLabel = NSTextField(labelWithString: "Set Up ClipBored")
    titleLabel.font = .boldSystemFont(ofSize: 22)
    let subtitleLabel = caption("Choose the shortcut, history window, and system entry points for this Mac.")
    let header = NSStackView(views: [titleLabel, subtitleLabel])
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 4

    stack.addArrangedSubview(header)
    stack.addArrangedSubview(section("Open ClipBored", [
      labeledRow("Shortcut", shortcutPopup)
    ]))
    stack.addArrangedSubview(section("History", [
      labeledRow("Keep History", historyRetentionPopup)
    ]))
    stack.addArrangedSubview(section("System", [
      showMenuBarIconButton,
      showDockIconButton,
      launchAtLoginButton,
      iCloudSyncButton
    ]))
    stack.addArrangedSubview(section("Automatic Paste", [
      caption("Accessibility is only needed when ClipBored pastes directly into the previous app."),
      labeledRow("Accessibility", permissionStatusLabel),
      button("Open Accessibility Settings", #selector(openAccessibilitySettings))
    ]))
    stack.addArrangedSubview(NSView())
    stack.addArrangedSubview(buttonRow())

    if let spacer = stack.arrangedSubviews.dropLast().last {
      spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
      shortcutPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
      historyRetentionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
    ])

    return content
  }

  private func configureShortcutPopup() {
    shortcutPopup.removeAllItems()
    addShortcutItem("Shift-Command-V", .pasteStyle)
    addShortcutItem("Command-Option-V", .clipBoredDefault)
    if settings.openShortcut != Self.pasteStyleOpenShortcut,
       settings.openShortcut != AppConfiguration.defaultOpenShortcut {
      addShortcutItem("Keep Current (\(settings.openShortcut.displayText))", .current)
    }
    shortcutPopup.setAccessibilityLabel("Open ClipBored shortcut")
  }

  private func configureHistoryRetentionPopup() {
    historyRetentionPopup.removeAllItems()
    for retention in HistoryRetention.allCases {
      historyRetentionPopup.addItem(withTitle: retention.title)
      historyRetentionPopup.lastItem?.representedObject = retention.rawValue
    }
    historyRetentionPopup.setAccessibilityLabel("Keep History")
  }

  private func addShortcutItem(_ title: String, _ choice: ShortcutChoice) {
    shortcutPopup.addItem(withTitle: title)
    shortcutPopup.lastItem?.representedObject = choice.rawValue
  }

  private func refreshFromSettings() {
    selectShortcut(Self.initialShortcutChoice(for: settings.openShortcut, onboardingCompleted: settings.onboardingCompleted))
    select(historyRetentionPopup, rawValue: settings.historyRetention.rawValue)
    let presentation = Self.normalizedPresentation(
      showMenuBarIcon: settings.showMenuBarIcon,
      showDockIcon: settings.showDockIcon
    )
    showMenuBarIconButton.state = presentation.showMenuBarIcon ? .on : .off
    showDockIconButton.state = presentation.showDockIcon ? .on : .off
    launchAtLoginButton.state = settings.launchAtLogin ? .on : .off
    iCloudSyncButton.state = settings.iCloudSyncEnabled ? .on : .off
    refreshPermissionStatus()
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
    label.widthAnchor.constraint(equalToConstant: 120).isActive = true
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

  private func buttonRow() -> NSView {
    let skipButton = NSButton(title: "Skip", target: self, action: #selector(skipSetup))
    skipButton.bezelStyle = .rounded
    skipButton.setAccessibilityLabel("Skip setup")

    let finishButton = NSButton(title: "Finish Setup", target: self, action: #selector(finishSetup))
    finishButton.bezelStyle = .rounded
    finishButton.keyEquivalent = "\r"
    finishButton.setAccessibilityLabel("Finish setup")

    let spacer = NSView()
    let stack = NSStackView(views: [spacer, skipButton, finishButton])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 10
    stack.widthAnchor.constraint(equalToConstant: 520).isActive = true
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return stack
  }

  private func configureCheckbox(_ control: NSButton, title: String, action: Selector?) {
    control.setButtonType(.switch)
    control.title = title
    control.target = action == nil ? nil : self
    control.action = action
    control.setAccessibilityLabel(title)
  }

  private func configureStatusLabel(_ label: NSTextField) {
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.lineBreakMode = .byTruncatingTail
  }

  private func selectShortcut(_ choice: ShortcutChoice) {
    for item in shortcutPopup.itemArray where item.representedObject as? String == choice.rawValue {
      shortcutPopup.select(item)
      return
    }
  }

  private func select(_ popup: NSPopUpButton, rawValue: Int) {
    for item in popup.itemArray where item.representedObject as? Int == rawValue {
      popup.select(item)
      return
    }
  }

  private func selectedShortcutChoice() -> ShortcutChoice {
    guard let rawValue = shortcutPopup.selectedItem?.representedObject as? String,
          let choice = ShortcutChoice(rawValue: rawValue)
    else {
      return .pasteStyle
    }
    return choice
  }

  @objc private func entryPointChanged() {
    let presentation = Self.normalizedPresentation(
      showMenuBarIcon: showMenuBarIconButton.state == .on,
      showDockIcon: showDockIconButton.state == .on
    )
    showMenuBarIconButton.state = presentation.showMenuBarIcon ? .on : .off
    showDockIconButton.state = presentation.showDockIcon ? .on : .off
  }

  @objc private func openAccessibilitySettings() {
    onOpenAccessibility()
    refreshPermissionStatus()
  }

  @objc private func finishSetup() {
    completeSetup(applySelections: true, closeWindow: true)
  }

  @objc private func skipSetup() {
    completeSetup(applySelections: false, closeWindow: true)
  }

  private func completeSetup(applySelections: Bool, closeWindow: Bool) {
    guard !didComplete else { return }
    didComplete = true

    if applySelections {
      applySelectedSettings()
    }
    settings.markAccessibilityNoticeShown()
    settings.markOnboardingCompleted()

    if closeWindow {
      window?.delegate = nil
      window?.close()
    }
    onFinish()
  }

  private func applySelectedSettings() {
    settings.openShortcut = Self.shortcutBinding(for: selectedShortcutChoice(), current: settings.openShortcut)
    if let rawValue = historyRetentionPopup.selectedItem?.representedObject as? Int,
       let retention = HistoryRetention(rawValue: rawValue) {
      settings.historyRetention = retention
    }

    let presentation = Self.normalizedPresentation(
      showMenuBarIcon: showMenuBarIconButton.state == .on,
      showDockIcon: showDockIconButton.state == .on
    )
    settings.showMenuBarIcon = presentation.showMenuBarIcon
    settings.showDockIcon = presentation.showDockIcon
    settings.launchAtLogin = launchAtLoginButton.state == .on
    settings.iCloudSyncEnabled = iCloudSyncButton.state == .on
  }

  #if DEBUG
  var debugShowMenuBarIconIsEnabled: Bool {
    showMenuBarIconButton.state == .on
  }

  var debugShowDockIconIsEnabled: Bool {
    showDockIconButton.state == .on
  }
  #endif
}
