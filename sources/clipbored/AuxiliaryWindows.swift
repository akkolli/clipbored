import AppKit
import SwiftUI
import WebKit

// MARK: - Setup

final class SetupController: NSObject, NSWindowDelegate {
  enum ShortcutChoice: String, CaseIterable { case pasteStyle, clipBoredDefault, current }
  struct PresentationChoice: Equatable {
    let showMenuBarIcon: Bool
    let showDockIcon: Bool
  }
  static let pasteStyleOpenShortcut = ShortcutBinding(
    key: "v", modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
  static func normalizedPresentation(showMenuBarIcon: Bool, showDockIcon: Bool) -> PresentationChoice {
    PresentationChoice(showMenuBarIcon: showMenuBarIcon || !showDockIcon, showDockIcon: showDockIcon)
  }
  static func initialShortcutChoice(for binding: ShortcutBinding, onboardingCompleted: Bool) -> ShortcutChoice {
    if binding == pasteStyleOpenShortcut { return .pasteStyle }
    if binding == Configuration.defaultOpenShortcut { return onboardingCompleted ? .clipBoredDefault : .pasteStyle }
    return .current
  }
  static func shortcutBinding(for choice: ShortcutChoice, current: ShortcutBinding) -> ShortcutBinding {
    switch choice {
    case .pasteStyle: return pasteStyleOpenShortcut
    case .clipBoredDefault: return Configuration.defaultOpenShortcut
    case .current: return current
    }
  }
  private let settings: Preferences
  private let onFinish: () -> Void
  private var window: NSWindow?
  private var didComplete = false
  let draft: SetupDraft

  init(settings: Preferences, onOpenAccessibility: @escaping () -> Void, onFinish: @escaping () -> Void) {
    self.settings = settings
    self.onFinish = onFinish
    draft = SetupDraft(settings)
    super.init()
    draft.finish = { [weak self] apply in self?.completeSetup(apply: apply) }
    draft.permission = { [weak self] in
      onOpenAccessibility()
      self?.refreshPermissionStatus()
    }
    let window = UI.window("Set Up Goldfish", size: NSSize(width: 600, height: 540), style: [.titled, .closable])
    UI.host(SetupForm(draft: draft), in: window, delegate: self)
    self.window = window
    refreshPermissionStatus()
  }
  func show() {
    draft.load(settings)
    refreshPermissionStatus()
    UI.show(window)
  }
  func refreshPermissionStatus() { draft.trusted = AccessibilityPermissionService.isTrusted }
  func windowWillClose(_ notification: Notification) { completeSetup(apply: false, close: false) }
  private func completeSetup(apply: Bool, close: Bool = true) {
    guard !didComplete else { return }
    didComplete = true
    if apply {
      settings.openShortcut = Self.shortcutBinding(for: draft.shortcut, current: settings.openShortcut)
      settings.historyRetention = draft.retention
      let presentation = Self.normalizedPresentation(showMenuBarIcon: draft.menuBar, showDockIcon: draft.dock)
      settings.showMenuBarIcon = presentation.showMenuBarIcon
      settings.showDockIcon = presentation.showDockIcon
      settings.launchAtLogin = draft.login
      settings.iCloudSyncEnabled = draft.sync
    }
    settings.markAccessibilityNoticeShown()
    settings.markOnboardingCompleted()
    if close {
      window?.delegate = nil
      window?.close()
    }
    onFinish()
  }
}

final class SetupDraft: ObservableObject {
  @Published var shortcut = SetupController.ShortcutChoice.pasteStyle
  @Published var retention = HistoryRetention.oneMonth
  @Published var menuBar = true
  @Published var dock = false
  @Published var login = false
  @Published var sync = false
  @Published var trusted = false
  private(set) var currentShortcut = Configuration.defaultOpenShortcut
  var finish: ((Bool) -> Void)?
  var permission: (() -> Void)?
  init(_ settings: Preferences) { load(settings) }
  func load(_ settings: Preferences) {
    currentShortcut = settings.openShortcut
    shortcut = SetupController.initialShortcutChoice(
      for: currentShortcut, onboardingCompleted: settings.onboardingCompleted)
    retention = settings.historyRetention
    let presentation = SetupController.normalizedPresentation(
      showMenuBarIcon: settings.showMenuBarIcon, showDockIcon: settings.showDockIcon)
    menuBar = presentation.showMenuBarIcon
    dock = presentation.showDockIcon
    login = settings.launchAtLogin
    sync = settings.iCloudSyncEnabled
  }
}

private struct SetupForm: View {
  @ObservedObject var draft: SetupDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Set Up Goldfish").font(.title.bold())
      Text("Choose the shortcut, history window, and system entry points for this Mac.").foregroundStyle(.secondary)
      Form {
        Section("Open Goldfish") {
          Picker("Shortcut", selection: $draft.shortcut) {
            Text("Shift-Command-V").tag(SetupController.ShortcutChoice.pasteStyle)
            Text("Command-Option-V").tag(SetupController.ShortcutChoice.clipBoredDefault)
            if ![SetupController.pasteStyleOpenShortcut, Configuration.defaultOpenShortcut].contains(
              draft.currentShortcut)
            {
              Text("Keep Current (\(draft.currentShortcut.displayText))").tag(SetupController.ShortcutChoice.current)
            }
          }.accessibilityLabel("Open Goldfish shortcut")
        }
        Section("History") {
          Picker("Keep History", selection: $draft.retention) {
            ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
          }
        }
        Section("System") {
          Toggle("Show Goldfish in the menu bar", isOn: $draft.menuBar)
          Toggle("Show Goldfish in the Dock", isOn: $draft.dock)
          Toggle("Launch at login", isOn: $draft.login)
          Toggle("Sync history with iCloud when available", isOn: $draft.sync)
        }
        Section("Automatic Paste") {
          Text("Accessibility is only needed when Goldfish pastes directly into the previous app.").font(.caption)
          Text(draft.trusted ? "Granted" : "Not granted; paste actions will copy instead.").foregroundColor(
            draft.trusted ? .green : .orange)
          Button("Open Accessibility Settings") { draft.permission?() }
        }
      }.formStyle(.grouped)
      HStack {
        Spacer()
        Button("Skip") { draft.finish?(false) }
        Button("Finish Setup") { draft.finish?(true) }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).onChange(of: draft.menuBar) { if !$0 && !draft.dock { draft.menuBar = true } }.onChange(
      of: draft.dock
    ) { if !$0 && !draft.menuBar { draft.menuBar = true } }
  }
}

// MARK: - LinkPreviewController

final class LinkPreviewController: NSWindowController, WKNavigationDelegate {
  enum Metrics {
    static let minimumWidth: CGFloat = 760
    static let minimumHeight: CGFloat = 420
    static let preferredHeight: CGFloat = 560
    static let margin: CGFloat = 24
    static let panelGap: CGFloat = 14
    static let toolbarHeight: CGFloat = 52
    static let toolbarLeadingInset: CGFloat = 86
  }

  private let webView: WKWebView
  private let titleLabel = UI.label("", weight: .semibold, lines: 1)
  private let addressLabel = UI.label(
    "", size: NSFont.smallSystemFontSize, secondary: true, lines: 1, truncation: .byTruncatingMiddle, monospaced: true)
  private let statusLabel = UI.label("", size: NSFont.smallSystemFontSize, secondary: true, lines: 1)
  private let progressIndicator = NSProgressIndicator()
  private let openURL: (URL) -> Void
  private lazy var controls: [ActionButton] = [
    ActionButton("Back", symbol: "chevron.left") { [weak self] in self?.webView.goBack() },
    ActionButton("Forward", symbol: "chevron.right") { [weak self] in self?.webView.goForward() },
    ActionButton("Reload", symbol: "arrow.clockwise") { [weak self] in self?.webView.reload() },
    ActionButton("Open in Browser", symbol: "arrow.up.right.square") { [weak self] in
      guard let self, let url = self.currentPageURL else { return }
      self.openURL(url)
    },
  ]
  private var observations: [NSKeyValueObservation] = []
  private var currentPageURL: URL?
  private var acceptsObservedPageTitles = false

  init(openURL: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }) {
    self.openURL = openURL
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

    webView = WKWebView(frame: .zero, configuration: configuration)
    let window = UI.window(
      "Link Preview", size: NSSize(width: Metrics.minimumWidth, height: Metrics.preferredHeight),
      minimum: NSSize(width: 560, height: 420),
      style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true

    super.init(window: window)
    configureContent(in: window)
    configureObservations()
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show(_ request: LinkPreview, relativeTo parent: NSWindow?) {
    prepareForPreview(request)
    if let parent, let window { window.setFrame(Self.previewFrame(relativeTo: parent), display: false) }
    UI.show(window)
    webView.load(URLRequest(url: request.url))
  }

  private func prepareForPreview(_ request: LinkPreview) {
    currentPageURL = request.url
    acceptsObservedPageTitles = false
    setTitleText(Self.displayTitle(for: request))
    setAddress(request.url)
    setStatus("Loading")
  }

  private static func displayTitle(for request: LinkPreview) -> String {
    request.title.clipboardTrimmed.isEmpty ? request.url.host ?? "Link Preview" : request.title
  }

  static func previewFrame(relativeTo parent: NSWindow) -> NSRect {
    let visibleFrame = parent.screen?.visibleFrame ?? parent.frame
    return previewFrame(parentFrame: parent.frame, visibleFrame: visibleFrame)
  }

  static func previewFrame(parentFrame: NSRect, visibleFrame: NSRect) -> NSRect {
    let usableWidth = max(1, visibleFrame.width - (Metrics.margin * 2))
    let width = min(max(Metrics.minimumWidth, floor(parentFrame.width * 0.72)), usableWidth)
    let usableHeight = max(1, visibleFrame.height - (Metrics.margin * 2))
    let abovePanelY = parentFrame.maxY + Metrics.panelGap
    let availableAbovePanel = visibleFrame.maxY - abovePanelY - Metrics.margin
    let preferredHeight = min(Metrics.preferredHeight, usableHeight)
    let height =
      availableAbovePanel >= Metrics.minimumHeight ? min(preferredHeight, availableAbovePanel) : preferredHeight
    let centeredX = parentFrame.midX - (width / 2)
    let x = min(max(visibleFrame.minX + Metrics.margin, centeredX), visibleFrame.maxX - width - Metrics.margin)
    let preferredY = availableAbovePanel >= Metrics.minimumHeight ? abovePanelY : visibleFrame.midY - (height / 2)
    let y = min(max(visibleFrame.minY + Metrics.margin, preferredY), visibleFrame.maxY - height - Metrics.margin)
    return NSRect(x: floor(x), y: floor(y), width: floor(width), height: floor(height))
  }

  private func configureContent(in window: NSWindow) {
    webView.navigationDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    let content = NSView().colored(.windowBackgroundColor)
    window.contentView = content
    let toolbar = NSVisualEffectView().sized(height: Metrics.toolbarHeight)
    toolbar.material = .windowBackground
    toolbar.blendingMode = .withinWindow
    toolbar.state = .active
    [titleLabel, addressLabel].forEach { $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
    controls.forEach { $0.sized(width: 30, height: 30).contentTintColor = .labelColor }
    let titles = UI.stack([titleLabel, addressLabel], spacing: 2)
    let row = UI.stack(
      [UI.stack(controls, vertical: false, spacing: 4), titles, NSView(), statusLabel], vertical: false, spacing: 14)
    row.edgeInsets = NSEdgeInsets(top: 0, left: Metrics.toolbarLeadingInset, bottom: 0, right: 16)
    toolbar.addPinnedSubview(row)
    statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
    progressIndicator.isIndeterminate = false
    progressIndicator.maxValue = 1
    progressIndicator.controlSize = .small
    progressIndicator.style = .bar
    toolbar.addPinnedSubview(progressIndicator.sized(height: 2), edges: [.leading, .trailing, .bottom])
    let column = UI.stack([toolbar, webView], spacing: 0)
    content.addPinnedSubview(column)
    [toolbar, webView].forEach { $0.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
  }

  private func configureObservations() {
    observations = [
      webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
        self?.progressIndicator.doubleValue = view.estimatedProgress
        self?.progressIndicator.isHidden = view.estimatedProgress >= 1
      }, webView.observe(\.title, options: [.new]) { [weak self] view, _ in self?.applyObservedPageTitle(view.title) },
      webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
        self?.controls[0].isEnabled = view.canGoBack
      },
      webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
        self?.controls[1].isEnabled = view.canGoForward
      },
    ]
  }

  private func applyObservedPageTitle(_ title: String?) {
    guard acceptsObservedPageTitles, let title = title?.clipboardTrimmed, !title.isEmpty else { return }
    setTitleText(title)
  }

  private func setTitleText(_ text: String) {
    titleLabel.stringValue = text
    titleLabel.toolTip = text
    window?.title = text
  }

  private func setAddress(_ url: URL) {
    currentPageURL = url
    let text = url.absoluteString
    addressLabel.stringValue = text
    addressLabel.toolTip = text
  }

  private func setStatus(_ text: String) {
    statusLabel.stringValue = text
    statusLabel.toolTip = text.isEmpty ? nil : text
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    acceptsObservedPageTitles = true
    setStatus("Loading")
    if let url = webView.url { setAddress(url) }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    setStatus("")
    if let url = webView.url { setAddress(url) }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    handleNavigationFailure(error)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    handleNavigationFailure(error)
  }

  private func handleNavigationFailure(_ error: Error) {
    guard !Self.isNavigationCancellation(error) else { return }
    setStatus("Could not load")
  }

  private static func isNavigationCancellation(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isNavigationCancellation(underlying) }
    return false
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }

    let scheme = url.scheme?.lowercased()
    guard scheme == "http" || scheme == "https" else {
      openURL(url)
      decisionHandler(.cancel)
      return
    }

    decisionHandler(.allow)
  }

}
