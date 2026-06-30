import AppKit

private struct ClipboardItemCardLayout: Equatable {
  let width: CGFloat
  let height: CGFloat
  let inset: CGFloat
  let headerHeight: CGFloat
  let bodyHeight: CGFloat
  let footerHeight: CGFloat
  let actionButtonSize: CGFloat
  let primaryActionButtonSize: CGFloat
  let actionRailHeight: CGFloat

  static let regular = ClipboardItemCardLayout(
    width: 320,
    height: 244,
    inset: 16,
    headerHeight: 56,
    bodyHeight: 152,
    footerHeight: 36,
    actionButtonSize: 24,
    primaryActionButtonSize: 30,
    actionRailHeight: 34
  )

  static let compact = ClipboardItemCardLayout(
    width: 264,
    height: 220,
    inset: 13,
    headerHeight: 50,
    bodyHeight: 138,
    footerHeight: 32,
    actionButtonSize: 22,
    primaryActionButtonSize: 28,
    actionRailHeight: 32
  )

  var isCompact: Bool {
    self == Self.compact
  }
}

private enum ClipboardCollectionVisuals {
  private static let customPalette: [NSColor] = [
    NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.32, alpha: 1),
    NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.88, alpha: 1),
    NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.72, alpha: 1),
    NSColor(calibratedRed: 0.74, green: 0.42, blue: 0.16, alpha: 1)
  ]

  static func color(for mode: ClipboardSortMode) -> NSColor {
    switch mode {
    case .mostRecent: return .secondaryLabelColor
    case .mostUsed: return NSColor(calibratedRed: 0.58, green: 0.42, blue: 0.92, alpha: 1)
    case .text: return NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1)
    case .links: return NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.98, alpha: 1)
    case .images: return NSColor(calibratedRed: 1.00, green: 0.22, blue: 0.25, alpha: 1)
    case .audio: return NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1)
    case .files: return NSColor(calibratedRed: 0.11, green: 0.68, blue: 0.36, alpha: 1)
    case .pinned: return NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.48, alpha: 1)
    }
  }

  static func color(forCollectionNamed name: String, overrideHex: String? = nil) -> NSColor {
    if let color = color(fromHex: overrideHex) {
      return color
    }
    return defaultColor(forCollectionNamed: name)
  }

  static func defaultColor(forCollectionNamed name: String) -> NSColor {
    switch name {
    case "Useful Links":
      return customPalette[0]
    case "Important Notes":
      return customPalette[1]
    case "Code Snippets":
      return customPalette[2]
    case "Read Later":
      return customPalette[3]
    default:
      return customPalette[stablePaletteIndex(for: name)]
    }
  }

  static func defaultColorHex(forCollectionNamed name: String) -> String {
    hexString(for: defaultColor(forCollectionNamed: name))
  }

  static func hexString(for color: NSColor) -> String {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    let red = Int((rgb.redComponent * 255).rounded())
    let green = Int((rgb.greenComponent * 255).rounded())
    let blue = Int((rgb.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
  }

  private static func color(fromHex value: String?) -> NSColor? {
    guard let value else { return nil }
    var hex = value.clipboardTrimmed
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }
    guard hex.count == 6,
          let rawValue = Int(hex, radix: 16) else {
      return nil
    }
    let red = CGFloat((rawValue >> 16) & 0xFF) / 255
    let green = CGFloat((rawValue >> 8) & 0xFF) / 255
    let blue = CGFloat(rawValue & 0xFF) / 255
    return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
  }

  private static func stablePaletteIndex(for name: String) -> Int {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for scalar in name.lowercased().unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return Int(hash % UInt64(customPalette.count))
  }
}

private struct CollectionCreationRequest {
  let name: String
  let colorHex: String
}

final class ClipboardPanelView: NSVisualEffectView, NSSearchFieldDelegate {
  private enum Metrics {
    static let actionButtonSize: CGFloat = 30
    static let panelTopInset: CGFloat = 12
    static let panelSideInset: CGFloat = 22
    static let actionBarHorizontalPadding: CGFloat = 10
    static let panelStatusBarHeight: CGFloat = 24
    static let minimumBottomInset: CGFloat = 20
    static let panelCornerRadius: CGFloat = 0
    static let compactCardThreshold: CGFloat = 760
    static let emptyStateMinimumWidth: CGFloat = 760
  }

  private enum CardDensity: String {
    case regular
    case compact

    static func fitting(width: CGFloat) -> CardDensity {
      width > 0 && width < Metrics.compactCardThreshold ? .compact : .regular
    }

    var layout: ClipboardItemCardLayout {
      switch self {
      case .regular: return .regular
      case .compact: return .compact
      }
    }

    var cardSpacing: CGFloat {
      switch self {
      case .regular: return 16
      case .compact: return 12
      }
    }

    var cardStackInset: CGFloat {
      switch self {
      case .regular: return 10
      case .compact: return 8
      }
    }

    var railHeight: CGFloat {
      layout.height + (cardStackInset * 2) + 2
    }

    var emptyStateMinimumWidth: CGFloat {
      switch self {
      case .regular: return Metrics.emptyStateMinimumWidth
      case .compact: return 420
      }
    }
  }

  private enum Palette {
    static let panelBorder = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
    static let panelSurface = NSColor.windowBackgroundColor.withAlphaComponent(0.56).cgColor
    static let panelShadow = NSColor.black.withAlphaComponent(0.18).cgColor
    static let panelStatusSurface = NSColor.clear.cgColor
    static let statusDivider = NSColor.clear.cgColor
  }

  private enum StatusTone: String {
    case ready
    case action
    case warning
    case error
    case neutral

    var color: NSColor {
      switch self {
      case .ready:
        return NSColor.systemGreen.withAlphaComponent(0.85)
      case .action:
        return NSColor.controlAccentColor.withAlphaComponent(0.9)
      case .warning:
        return NSColor.systemOrange.withAlphaComponent(0.9)
      case .error:
        return NSColor.systemRed.withAlphaComponent(0.9)
      case .neutral:
        return NSColor.secondaryLabelColor.withAlphaComponent(0.65)
      }
    }
  }

  private let viewModel: ClipboardPanelViewModel
  private let onClose: () -> Void
  private let onSettings: () -> Void
  private let onPreview: () -> Void

  private let searchField = NSSearchField()
  private let collectionScrollView = HorizontalRailScrollView()
  private let collectionStack = NSStackView()
  private let addCollectionButton = NSButton()
  private let stackChip = CollectionChipView(title: "Stack", color: .systemGreen)
  private let itemsStack = NSStackView()
  private let scrollView = HorizontalRailScrollView()
  private let statusLabel = NSTextField(labelWithString: "")
  private let statusResultCountLabel = NSTextField(labelWithString: "")
  private let statusIndicator = NSView()
  private var emptyStateText: (title: String, detail: String)?
  private var mainStack: NSStackView?
  private var bottomSafeInset = Metrics.minimumBottomInset
  private var currentStatusTone: StatusTone = .ready
  private var cardDensity: CardDensity = .regular
  private var scrollViewHeightConstraint: NSLayoutConstraint?
  private var cardViews: [ClipboardItemCardView] = []
  private var collectionButtons: [ClipboardSortMode: CollectionChipView] = [:]
  private var customCollectionButtons: [String: CollectionChipView] = [:]
  private var collectionChipOrder: [CollectionChipView] = []
  private var lastScrollContentWidth: CGFloat = 0
  private var lastCollectionViewportWidth: CGFloat = 0
  private var defersVisualReloads = false
  private var pendingItemReload = false
  private var pendingCollectionReload = false
  #if DEBUG
  private var collectionNameProviderForTesting: (() -> String?)?
  #endif

  init(
    viewModel: ClipboardPanelViewModel,
    onClose: @escaping () -> Void,
    onSettings: @escaping () -> Void = {},
    onPreview: @escaping () -> Void = {}
  ) {
    self.viewModel = viewModel
    self.onClose = onClose
    self.onSettings = onSettings
    self.onPreview = onPreview
    super.init(frame: .zero)
    configureView()
    bindViewModel()
    reloadItems()
    updateSelection()
    updateStatus(viewModel.statusMessage)
    updateResultCount()
    updateCollectionButtons()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func configureView() {
    material = .underWindowBackground
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = Metrics.panelCornerRadius
    layer?.masksToBounds = false
    layer?.backgroundColor = Palette.panelSurface
    layer?.borderWidth = 0.6
    layer?.borderColor = Palette.panelBorder
    layer?.shadowColor = Palette.panelShadow
    layer?.shadowOpacity = 0.18
    layer?.shadowRadius = 20
    layer?.shadowOffset = NSSize(width: 0, height: 10)

    let toolbarIcon = NSImageView(image: appIconImage())
    toolbarIcon.imageScaling = .scaleProportionallyUpOrDown
    toolbarIcon.toolTip = "ClipBored"
    toolbarIcon.widthAnchor.constraint(equalToConstant: 22).isActive = true
    toolbarIcon.heightAnchor.constraint(equalToConstant: 22).isActive = true

    searchField.placeholderString = "Search clips"
    searchField.setAccessibilityLabel("Search clipboard history")
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(searchFieldChanged)
    searchField.sendsSearchStringImmediately = true
    searchField.sendsWholeSearchString = false
    searchField.isBezeled = true
    searchField.placeholderAttributedString = NSAttributedString(
      string: "Search clips",
      attributes: [
        .foregroundColor: NSColor.tertiaryLabelColor
      ]
    )
    searchField.bezelStyle = .roundedBezel
    searchField.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
    searchField.focusRingType = .none
    searchField.toolTip = "Search clipboard history. Supports app:Safari, type:image, date:2026-06-30, after:2026-06-01, and pinned:on."
    searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
    searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true

    collectionStack.orientation = .horizontal
    collectionStack.alignment = .centerY
    collectionStack.distribution = .fill
    collectionStack.spacing = 10
    collectionStack.translatesAutoresizingMaskIntoConstraints = true
    collectionStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    collectionStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
    collectionStack.setAccessibilityLabel("Clipboard collections")

    collectionScrollView.documentView = collectionStack
    collectionScrollView.hasHorizontalScroller = true
    collectionScrollView.hasVerticalScroller = false
    collectionScrollView.autohidesScrollers = true
    collectionScrollView.scrollerStyle = .overlay
    collectionScrollView.drawsBackground = false
    collectionScrollView.borderType = .noBorder
    collectionScrollView.setAccessibilityLabel("Clipboard collections")
    collectionScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    collectionScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    collectionScrollView.heightAnchor.constraint(equalToConstant: 30).isActive = true
    configureAddCollectionButton()
    configureCollectionButtons()

    let settingsButton = iconButton("gearshape", toolTip: "Settings", action: #selector(openSettings))
    let closeButton = iconButton("xmark.circle", toolTip: "Close", action: #selector(closePanel))

    let actionStrip = row([
      settingsButton,
      closeButton
    ])
    actionStrip.spacing = 8
    actionStrip.setContentCompressionResistancePriority(.required, for: .horizontal)
    let actionGroup = groupedToolbar(actionStrip)

    let topSpacer = NSView()
    topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    topSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let topBar = row([
      toolbarIcon,
      searchField,
      topSpacer,
      actionGroup
    ])
    topBar.distribution = .fill
    topBar.setHuggingPriority(.defaultHigh, for: .vertical)
    actionGroup.setContentHuggingPriority(.required, for: .horizontal)
    actionGroup.setContentCompressionResistancePriority(.required, for: .horizontal)

    let filterSpacer = NSView()
    filterSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    filterSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let filterBar = row([
      collectionScrollView,
      filterSpacer
    ])
    filterBar.spacing = 12
    filterBar.distribution = .fill

    itemsStack.orientation = .horizontal
    itemsStack.alignment = .top
    applyCardDensity()
    itemsStack.translatesAutoresizingMaskIntoConstraints = true
    scrollView.documentView = itemsStack
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.setContentHuggingPriority(.required, for: .vertical)
    scrollView.setContentCompressionResistancePriority(.required, for: .vertical)
    scrollViewHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: cardDensity.railHeight)
    scrollViewHeightConstraint?.isActive = true

    statusLabel.font = .systemFont(ofSize: NSFont.systemFontSize - 1)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.maximumNumberOfLines = 1
    statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    statusLabel.toolTip = statusLabel.stringValue
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

    statusIndicator.wantsLayer = true
    statusIndicator.layer?.cornerRadius = 4
    statusIndicator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85).cgColor
    statusIndicator.translatesAutoresizingMaskIntoConstraints = false
    statusIndicator.widthAnchor.constraint(equalToConstant: 8).isActive = true
    statusIndicator.heightAnchor.constraint(equalToConstant: 8).isActive = true
    statusIndicator.setAccessibilityElement(false)

    let statusRow = row([statusIndicator, statusLabel, statusResultCountLabel])
    statusRow.distribution = .fill
    statusRow.alignment = .centerY
    statusRow.spacing = 8
    statusRow.setContentCompressionResistancePriority(.required, for: .vertical)

    statusResultCountLabel.alignment = .right
    statusResultCountLabel.textColor = .secondaryLabelColor
    statusResultCountLabel.lineBreakMode = .byTruncatingTail
    statusResultCountLabel.maximumNumberOfLines = 1
    statusResultCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    statusResultCountLabel.setContentHuggingPriority(.required, for: .horizontal)
    statusResultCountLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    statusResultCountLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
    statusResultCountLabel.font = .systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)

    statusResultCountLabel.setAccessibilityLabel("Result count")
    statusLabel.setAccessibilityLabel("Status")

    let headerStack = NSStackView(views: [topBar, filterBar])
    headerStack.orientation = .vertical
    headerStack.alignment = .leading
    headerStack.spacing = 10
    headerStack.setContentCompressionResistancePriority(.required, for: .vertical)

    let statusContainer = NSView()
    statusContainer.wantsLayer = true
    statusContainer.layer?.backgroundColor = Palette.panelStatusSurface
    statusContainer.layer?.cornerRadius = 8
    statusContainer.layer?.borderWidth = 0
    statusContainer.layer?.borderColor = Palette.statusDivider
    statusContainer.translatesAutoresizingMaskIntoConstraints = false
    statusContainer.addSubview(statusRow)
    NSLayoutConstraint.activate([
      statusRow.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 8),
      statusRow.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -8),
      statusRow.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 4),
      statusRow.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -4),
      statusContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.panelStatusBarHeight)
    ])

    let mainStack = NSStackView(views: [headerStack, scrollView, statusContainer])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 10
    mainStack.edgeInsets = contentInsets()
    mainStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(mainStack)
    self.mainStack = mainStack

    NSLayoutConstraint.activate([
      mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
      mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
      mainStack.topAnchor.constraint(equalTo: topAnchor),
      mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
      headerStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -(Metrics.panelSideInset * 2)),
      topBar.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
      filterBar.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
      scrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -(Metrics.panelSideInset * 2)),
      statusContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -(Metrics.panelSideInset * 2))
    ])

    updateCollectionButtons()
    updateResultCount()
  }

  private func bindViewModel() {
    viewModel.onVisibleItemsChanged = { [weak self] _ in
      self?.handleVisibleItemsChanged()
    }
    viewModel.onSelectedIndexChanged = { [weak self] _ in
      self?.updateSelection()
    }
    viewModel.onStatusMessageChanged = { [weak self] message in
      self?.updateStatus(message)
    }
    viewModel.onSortModeChanged = { [weak self] _ in
      self?.updateCollectionButtons()
    }
    viewModel.onCollectionsChanged = { [weak self] in
      self?.handleCollectionsChanged()
    }
    viewModel.onStackChanged = { [weak self] in
      self?.reloadItems()
      self?.updateSelection()
      self?.configureCollectionButtons()
      self?.updateStatus(self?.viewModel.statusMessage ?? "")
    }
    viewModel.onCaptureStatusChanged = { [weak self] in
      self?.updateStatus(self?.viewModel.statusMessage ?? "")
    }
  }

  private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    return stack
  }

  private func groupedToolbar(_ content: NSView) -> NSView {
    let container = NSVisualEffectView()
    container.material = .sidebar
    container.blendingMode = .withinWindow
    container.wantsLayer = true
    container.translatesAutoresizingMaskIntoConstraints = false
    container.layer?.cornerRadius = 0
    container.layer?.borderWidth = 0
    container.layer?.borderColor = NSColor.clear.cgColor
    container.layer?.backgroundColor = NSColor.clear.cgColor
    content.translatesAutoresizingMaskIntoConstraints = false
    content.setContentCompressionResistancePriority(.required, for: .horizontal)
    container.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    return container
  }

  private func configureCollectionButtons() {
    collectionButtons.removeAll()
    customCollectionButtons.removeAll()
    collectionChipOrder.removeAll()
    for view in collectionStack.arrangedSubviews {
      (view as? CollectionChipView)?.clearKeyboardFocus()
      collectionStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    for mode in ClipboardSortMode.allCases {
      let chip = CollectionChipView(title: collectionTitle(for: mode), color: collectionColor(for: mode))
      chip.toolTip = mode.title
      chip.onPress = { [weak self] in
        self?.viewModel.sortMode = mode
      }
      configureCollectionKeyboardNavigation(for: chip)
      collectionButtons[mode] = chip
      collectionChipOrder.append(chip)
      collectionStack.addArrangedSubview(chip)
    }

    for collectionName in viewModel.collectionNames {
      let chip = CollectionChipView(title: collectionName, color: collectionColor(forCollectionNamed: collectionName))
      chip.toolTip = collectionName
      chip.onPress = { [weak self] in
        self?.viewModel.selectCollection(named: collectionName)
      }
      chip.onDropItem = { [weak self] itemID in
        self?.viewModel.assignItem(withID: itemID, to: collectionName)
      }
      chip.onEdit = { [weak self] in
        self?.editCollection(named: collectionName)
      }
      chip.onDelete = { [weak self] in
        self?.deleteCollection(named: collectionName)
      }
      configureCollectionKeyboardNavigation(for: chip)
      customCollectionButtons[collectionName] = chip
      collectionChipOrder.append(chip)
      collectionStack.addArrangedSubview(chip)
    }
    configureStackChip()
    collectionStack.addArrangedSubview(addCollectionButton)
    updateAddCollectionButtonState()
    sizeCollectionDocument()
  }

  private func configureStackChip() {
    stackChip.toolTip = "Queued clips"
    stackChip.onPress = { [weak self] in
      self?.viewModel.selectStack()
    }
    configureCollectionKeyboardNavigation(for: stackChip)
    if viewModel.stackCount > 0 {
      collectionChipOrder.append(stackChip)
      collectionStack.addArrangedSubview(stackChip)
    }
  }

  private func configureCollectionKeyboardNavigation(for chip: CollectionChipView) {
    chip.onStartSearch = { [weak self] text in
      self?.startSearchFromShelf(text)
    }
    chip.onMoveFocus = { [weak self, weak chip] delta in
      self?.moveCollectionFocus(from: chip, delta: delta)
    }
    chip.onSelectFirst = { [weak self] in
      self?.selectCollectionChip(at: 0)
    }
    chip.onSelectLast = { [weak self] in
      guard let self else { return }
      self.selectCollectionChip(at: self.collectionChipOrder.count - 1)
    }
  }

  private func configureAddCollectionButton() {
    let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New collection")
    image?.isTemplate = true
    addCollectionButton.image = image
    addCollectionButton.imagePosition = .imageOnly
    addCollectionButton.imageScaling = .scaleProportionallyDown
    addCollectionButton.isBordered = false
    addCollectionButton.wantsLayer = true
    addCollectionButton.layer?.cornerRadius = 13
    addCollectionButton.layer?.borderWidth = 0.6
    addCollectionButton.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.16).cgColor
    addCollectionButton.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.26).cgColor
    addCollectionButton.contentTintColor = .secondaryLabelColor
    addCollectionButton.toolTip = "New collection"
    addCollectionButton.setAccessibilityLabel("New collection")
    addCollectionButton.target = self
    addCollectionButton.action = #selector(createCollectionFromToolbar)
    addCollectionButton.translatesAutoresizingMaskIntoConstraints = false
    addCollectionButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
    addCollectionButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
  }

  private func collectionTitle(for mode: ClipboardSortMode) -> String {
    switch mode {
    case .mostRecent: return "Clipboard"
    case .mostUsed: return "Frequent"
    case .text: return "Text"
    case .links: return "Links"
    case .images: return "Images"
    case .audio: return "Audio"
    case .files: return "Files"
    case .pinned: return "Pinned"
    }
  }

  private func collectionColor(for mode: ClipboardSortMode) -> NSColor {
    ClipboardCollectionVisuals.color(for: mode)
  }

  private func collectionColor(forCollectionNamed name: String) -> NSColor {
    ClipboardCollectionVisuals.color(forCollectionNamed: name, overrideHex: viewModel.collectionColorHex(named: name))
  }

  private func applyCardDensity() {
    itemsStack.spacing = cardDensity.cardSpacing
    let inset = cardDensity.cardStackInset
    itemsStack.edgeInsets = NSEdgeInsets(
      top: inset,
      left: inset,
      bottom: inset,
      right: inset
    )
    scrollViewHeightConstraint?.constant = cardDensity.railHeight
  }

  @discardableResult
  private func updateCardDensityForCurrentWidth() -> Bool {
    let targetDensity = CardDensity.fitting(width: bounds.width)
    guard targetDensity != cardDensity else { return false }

    cardDensity = targetDensity
    applyCardDensity()
    reloadItems()
    return true
  }

  private func contentInsets() -> NSEdgeInsets {
    NSEdgeInsets(
      top: Metrics.panelTopInset,
      left: Metrics.panelSideInset,
      bottom: bottomSafeInset,
      right: Metrics.panelSideInset
    )
  }

  private func iconButton(_ systemName: String, toolTip: String, action: Selector) -> NSButton {
    let button = NSButton(title: "", target: self, action: action)
    let image = NSImage(systemSymbolName: systemName, accessibilityDescription: toolTip)
    image?.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.bezelStyle = .smallSquare
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.14).cgColor
    button.layer?.cornerRadius = 7
    button.toolTip = toolTip
    button.contentTintColor = .secondaryLabelColor
    button.setAccessibilityLabel(toolTip)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: Metrics.actionButtonSize).isActive = true
    button.heightAnchor.constraint(equalToConstant: Metrics.actionButtonSize).isActive = true
    return button
  }

  private func appIconImage() -> NSImage {
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let icon = NSImage(contentsOf: url) {
      icon.size = NSSize(width: 22, height: 22)
      return icon
    }
    return NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "ClipBored") ?? NSImage()
  }

  private func reloadItems() {
    cardViews.removeAll()
    lastScrollContentWidth = 0
    for view in itemsStack.arrangedSubviews {
      itemsStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    let items = viewModel.visibleItems
    if items.isEmpty {
      emptyStateText = emptyStateCopy()
      scrollView.documentView = emptyStateView()
    } else {
      emptyStateText = nil
      if scrollView.documentView !== itemsStack {
        scrollView.documentView = itemsStack
      }
      let collectionNames = viewModel.collectionNames
      let layout = cardDensity.layout
      for (index, item) in items.enumerated() {
        let card = ClipboardItemCardView(
          item: item,
          thumbnail: viewModel.thumbnail(for: item),
          index: index,
          layout: layout,
          collectionNames: collectionNames,
          isStacked: viewModel.isItemStacked(at: index),
          stackCount: viewModel.stackCount,
          canShowInClipboard: viewModel.canShowVisibleItemsInClipboard,
          selectedCollectionName: viewModel.selectedCollectionName,
          selectedCollectionColor: viewModel.selectedCollectionName.map { collectionColor(forCollectionNamed: $0) }
        )
        card.onSelect = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
        }
        card.onStartSearch = { [weak self] text in
          self?.startSearchFromShelf(text)
        }
        card.onMoveSelection = { [weak self] delta in
          self?.moveSelectionFromFocusedCard(delta)
        }
        card.onPageSelection = { [weak self] direction in
          guard let self else { return }
          self.moveSelectionFromFocusedCard(direction * self.visibleCardPageStep)
        }
        card.onSelectFirst = { [weak self] in
          self?.selectFirstCardFromFocusedCard()
        }
        card.onSelectLast = { [weak self] in
          self?.selectLastCardFromFocusedCard()
        }
        card.onPaste = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.pasteSelected()
        }
        card.onCopy = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.copySelected()
        }
        card.onPastePlainText = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.pasteSelectedPlainText()
        }
        card.onCopyPlainText = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.copySelectedPlainText()
        }
        card.onToggleStack = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.toggleSelectedStackMembership()
        }
        card.onPasteStackNext = { [weak self] in
          self?.viewModel.pasteNextStackItem()
        }
        card.onCopyStackNext = { [weak self] in
          self?.viewModel.copyNextStackItem()
        }
        card.onClearStack = { [weak self] in
          self?.viewModel.clearStack()
        }
        card.onShowInClipboard = { [weak self] selected in
          self?.showSelectedInClipboard(at: selected)
        }
        card.onRename = { [weak self] selected in
          self?.renameClip(at: selected)
        }
        card.onEditText = { [weak self] selected in
          self?.editText(at: selected)
        }
        card.onPreview = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.onPreview()
        }
        card.onPasteboardWriters = { [weak self] selected in
          self?.viewModel.pasteboardWriters(forItemAt: selected) ?? []
        }
        card.onOpen = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.openSelected()
        }
        card.onReveal = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.revealSelected()
        }
        card.onTogglePin = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.togglePinSelected()
        }
        card.onAssignCollection = { [weak self] selected, collectionName in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.assignSelected(to: collectionName)
        }
        card.onIgnoreSourceApp = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.ignoreSelectedSourceApp()
        }
        card.onIgnoreKind = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.ignoreSelectedKind()
        }
        card.onDelete = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
          self?.viewModel.deleteSelected()
        }
        cardViews.append(card)
        itemsStack.addArrangedSubview(card)
      }
      sizeItemsDocument(itemCount: items.count)
    }

    updateSelection()
    updateStatus(viewModel.statusMessage)
    updateResultCount()
  }

  private func handleVisibleItemsChanged() {
    if defersVisualReloads {
      pendingItemReload = true
      updateStatus(viewModel.statusMessage)
      updateResultCount()
      return
    }

    reloadItems()
    updateCollectionButtons()
  }

  private func handleCollectionsChanged() {
    if defersVisualReloads {
      pendingCollectionReload = true
      return
    }

    configureCollectionButtons()
    updateCollectionButtons()
  }

  private func flushDeferredVisualReloads() {
    let shouldReloadItems = pendingItemReload
    let shouldReloadCollections = pendingCollectionReload
    pendingItemReload = false
    pendingCollectionReload = false

    if shouldReloadCollections {
      configureCollectionButtons()
    }
    if shouldReloadItems {
      reloadItems()
    }
    if shouldReloadItems || shouldReloadCollections {
      updateCollectionButtons()
    }
  }

  private func updateSelection() {
    var selectedCard: ClipboardItemCardView?
    for (index, card) in cardViews.enumerated() {
      let selected = index == viewModel.selectedIndex
      card.setSelected(selected)
      if selected {
        selectedCard = card
      }
    }

    if let selectedCard {
      scrollCardIntoView(selectedCard)
    }
    updateAddCollectionButtonState()
  }

  private func updateAddCollectionButtonState() {
    addCollectionButton.isEnabled = true
    addCollectionButton.alphaValue = 1.0
  }

  private func scrollCardIntoView(_ card: NSView) {
    guard scrollView.documentView === itemsStack else { return }
    guard card.window != nil else { return }
    scrollView.layoutSubtreeIfNeeded()
    itemsStack.layoutSubtreeIfNeeded()

    let frame = card.convert(card.bounds, to: itemsStack)
    let paddedFrame = frame.insetBy(dx: -cardDensity.cardSpacing, dy: 0)
    itemsStack.scrollToVisible(paddedFrame)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  private func moveCollectionFocus(from chip: CollectionChipView?, delta: Int) {
    guard let chip,
          let currentIndex = collectionChipOrder.firstIndex(where: { $0 === chip }) else {
      return
    }
    selectCollectionChip(at: currentIndex + delta)
  }

  private func selectCollectionChip(at index: Int) {
    guard !collectionChipOrder.isEmpty else { return }
    let targetIndex = max(0, min(collectionChipOrder.count - 1, index))
    let title = collectionChipOrder[targetIndex].titleText
    collectionChipOrder[targetIndex].onPress()

    let focusedChip: CollectionChipView?
    if let rebuiltChip = collectionChipOrder.first(where: { $0.titleText == title }) {
      focusedChip = rebuiltChip
    } else if collectionChipOrder.indices.contains(targetIndex) {
      focusedChip = collectionChipOrder[targetIndex]
    } else {
      focusedChip = nil
    }
    guard let focusedChip else { return }
    collectionChipOrder.forEach { $0.clearKeyboardFocus() }
    window?.makeFirstResponder(focusedChip)
    scrollCollectionChipIntoView(focusedChip)
  }

  private func scrollCollectionChipIntoView(_ chip: NSView) {
    guard collectionScrollView.documentView === collectionStack else { return }
    guard chip.window != nil else { return }
    collectionScrollView.layoutSubtreeIfNeeded()
    collectionStack.layoutSubtreeIfNeeded()

    let frame = chip.convert(chip.bounds, to: collectionStack)
    let paddedFrame = frame.insetBy(dx: -10, dy: 0)
    collectionStack.scrollToVisible(paddedFrame)
    collectionScrollView.reflectScrolledClipView(collectionScrollView.contentView)
  }

  private func updateStatus(_ message: String) {
    let text: String
    if !message.isEmpty {
      text = message
    } else if !viewModel.captureStatusMessage.isEmpty {
      text = viewModel.captureStatusMessage
    } else if viewModel.visibleItems.isEmpty {
      text = "Capture is running. Accessibility permission is only needed for automatic paste."
    } else {
      text = "Capture running"
    }
    statusLabel.stringValue = text
    statusLabel.toolTip = statusLabel.stringValue
    updateStatusIndicator(for: text)
  }

  private func updateStatusIndicator(for text: String) {
    currentStatusTone = statusTone(for: text)
    statusIndicator.layer?.backgroundColor = currentStatusTone.color.cgColor
    statusIndicator.toolTip = text
  }

  private func statusTone(for text: String) -> StatusTone {
    let lower = text.lowercased()
    if lower.hasPrefix("captured") || lower.contains("capture running") || lower.contains("capture is running") || lower.contains("capture resumed") {
      return .ready
    }
    if lower.hasPrefix("copied") || lower.hasPrefix("pasted") || lower.hasPrefix("updated") || lower.hasPrefix("renamed") || lower.hasPrefix("added") || lower.hasPrefix("created") || lower.hasPrefix("removed") || lower.hasPrefix("cleared") || lower.hasPrefix("ignored") || lower.hasPrefix("showing") {
      return .action
    }
    if lower.hasPrefix("error") || lower.contains("failed") {
      return .error
    }
    if lower.hasPrefix("skipped") || lower.contains("ignored") || lower.contains("paused") {
      return .warning
    }
    if lower.contains("could not") || lower.contains("not granted") {
      return .error
    }
    return .neutral
  }

  private func updateResultCount() {
    let count = viewModel.visibleItems.count
    let noun = count == 1 ? "clip" : "clips"
    let text: String
    if !viewModel.searchText.clipboardTrimmed.isEmpty {
      text = "\(count) \(noun) matching"
    } else {
      text = "\(count) \(noun)"
    }
    statusResultCountLabel.stringValue = text
    statusResultCountLabel.toolTip = text
  }

  private func editText(at index: Int) {
    viewModel.selectItem(at: index)
    guard let currentText = viewModel.editableTextForSelected() else { return }

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
    textView.string = currentText
    textView.font = .systemFont(ofSize: 13)
    textView.isRichText = false
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.usesAdaptiveColorMappingForDarkAppearance = true

    let scrollView = NSScrollView(frame: textView.frame)
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder
    scrollView.documentView = textView

    let alert = NSAlert()
    alert.messageText = "Edit Text"
    alert.accessoryView = scrollView
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = textView

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    viewModel.updateSelectedText(to: textView.string)
  }

  private func renameClip(at index: Int) {
    viewModel.selectItem(at: index)
    guard let currentTitle = viewModel.editableTitleForSelected() else { return }

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    input.placeholderString = "Clip title"
    input.stringValue = currentTitle

    let alert = NSAlert()
    alert.messageText = "Rename Clip"
    alert.informativeText = "Give this clip a searchable title. Leave it blank to clear the title."
    alert.accessoryView = input
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = input

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    viewModel.updateSelectedTitle(to: input.stringValue)
  }

  private func emptyStateView() -> NSView {
    let width = max(cardDensity.emptyStateMinimumWidth, scrollView.contentView.bounds.width)
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardDensity.railHeight))
    let copy = emptyStateCopy()
    let title = NSTextField(labelWithString: copy.title)
    title.font = .systemFont(ofSize: 14, weight: .medium)
    title.textColor = .labelColor
    title.alignment = .center

    let detail = NSTextField(wrappingLabelWithString: copy.detail)
    detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    detail.textColor = .secondaryLabelColor
    detail.alignment = .center
    detail.maximumNumberOfLines = 3

    let stack = NSStackView(views: [title, detail])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -80)
    ])
    return container
  }

  private func sizeItemsDocument(itemCount: Int) {
    let count = CGFloat(itemCount)
    let contentWidth = (count * cardDensity.layout.width)
      + max(0, count - 1) * cardDensity.cardSpacing
      + (cardDensity.cardStackInset * 2)
    let width = max(scrollView.contentView.bounds.width, contentWidth)
    lastScrollContentWidth = width
    itemsStack.frame = NSRect(x: 0, y: 0, width: width, height: currentListHeight())
    itemsStack.needsLayout = true
    itemsStack.layoutSubtreeIfNeeded()
  }

  private func currentListHeight() -> CGFloat {
    cardDensity.layout.height + (cardDensity.cardStackInset * 2)
  }

  private func emptyStateCopy() -> (title: String, detail: String) {
    if !viewModel.searchText.clipboardTrimmed.isEmpty {
      return (
        "No matching clips",
        "Try a broader search or switch filters."
      )
    }

    if let collectionName = viewModel.selectedCollectionName {
      return (
        "No clips in \(collectionName)",
        "Drag clips here or use Collect to add them."
      )
    }

    if viewModel.totalItemCount == 0 {
      return (
        "Copy something to start your history",
        viewModel.captureStatusMessage.isEmpty
        ? "ClipBored records clipboard changes locally. Accessibility is only needed for automatic paste."
        : viewModel.captureStatusMessage
      )
    }

    switch viewModel.sortMode {
    case .images:
      return ("No images yet", "Image clips are saved when the clipboard contains image data.")
    case .links:
      return ("No links yet", "Links are detected from copied URLs.")
    case .text:
      return ("No text clips yet", "Copied text and rich text appear here.")
    case .files:
      return ("No files yet", "Copied files and PDFs appear here.")
    case .audio:
      return ("No audio yet", "Copied sound clips appear here.")
    case .pinned:
      return ("No pinned clips", "Use the Pin action on a card to keep important clips here.")
    case .mostRecent, .mostUsed:
      return ("No clips in this view", "Switch filters or copy something new.")
    }
  }

  private func updateCollectionButtons() {
    for (mode, chip) in collectionButtons {
      chip.setSelected(viewModel.selectedCollectionName == nil && mode == viewModel.sortMode)
      chip.setCount(viewModel.collectionCount(for: mode))
    }
    for (name, chip) in customCollectionButtons {
      chip.setSelected(viewModel.selectedCollectionName == name)
      chip.setCount(viewModel.collectionCount(named: name))
    }
    stackChip.setSelected(viewModel.isStackFilterSelected)
    stackChip.setCount(viewModel.stackCount)
    sizeCollectionDocument()
  }

  var isSearchFieldEditing: Bool {
    guard let firstResponder = window?.firstResponder else { return false }
    if firstResponder === searchField {
      return true
    }

    if let firstResponderView = firstResponder as? NSView, firstResponderView.isDescendant(of: searchField) {
      return true
    }

    if let editor = searchField.currentEditor(), firstResponder === editor {
      return true
    }

    return false
  }

  var searchTextForKeyboardShortcut: String {
    searchField.stringValue
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override func layout() {
    super.layout()
    _ = updateCardDensityForCurrentWidth()
    let collectionViewportWidth = collectionScrollView.contentView.bounds.width
    if collectionViewportWidth != lastCollectionViewportWidth {
      lastCollectionViewportWidth = collectionViewportWidth
      sizeCollectionDocument()
    }

    guard !scrollView.frame.equalTo(.zero) else { return }
    let contentWidth = scrollView.contentView.bounds.width
    if contentWidth == lastScrollContentWidth {
      return
    }
    lastScrollContentWidth = contentWidth

    if cardViews.isEmpty {
      guard let documentView = scrollView.documentView else { return }
      documentView.frame.size = NSSize(
        width: max(cardDensity.emptyStateMinimumWidth, scrollView.contentView.bounds.width),
        height: currentListHeight()
      )
      return
    }

    sizeItemsDocument(itemCount: cardViews.count)
  }

  private func sizeCollectionDocument() {
    collectionStack.layoutSubtreeIfNeeded()
    let contentWidth = ceil(collectionStack.fittingSize.width)
    let viewportWidth = collectionScrollView.contentView.bounds.width
    let width = max(contentWidth, viewportWidth)
    collectionStack.frame = NSRect(x: 0, y: 0, width: width, height: 30)
  }

  func focusSearchField() {
    window?.makeFirstResponder(searchField)
  }

  @discardableResult
  func clearSearchForKeyboardCancel() -> Bool {
    guard !searchField.stringValue.clipboardTrimmed.isEmpty else { return false }
    searchField.stringValue = ""
    updateSearchText()
    focusSearchField()
    return true
  }

  private func startSearchFromShelf(_ text: String) {
    guard !text.isEmpty else { return }
    focusSearchField()
    searchField.stringValue += text
    updateSearchText()
  }

  func setBottomSafeInset(_ inset: CGFloat) {
    bottomSafeInset = max(Metrics.minimumBottomInset, inset)
    mainStack?.edgeInsets = contentInsets()
    needsLayout = true
  }

  var visibleCardPageStep: Int {
    let span = cardDensity.layout.width + cardDensity.cardSpacing
    guard span > 0 else { return 1 }
    return max(1, Int(floor(scrollView.contentView.bounds.width / span)))
  }

  func focusSelectedCardForKeyboardNavigation() {
    focusSelectedCard()
  }

  func prepareForShow() {
    if !searchField.stringValue.isEmpty {
      searchField.stringValue = ""
      updateSearchText()
    }
    focusSearchField()
  }

  func beginOpeningTransition() {
    defersVisualReloads = true
    pendingItemReload = false
    pendingCollectionReload = false
  }

  func finishOpeningTransition() {
    guard defersVisualReloads else { return }
    defersVisualReloads = false
    flushDeferredVisualReloads()
  }

  #if DEBUG
  var debugVisibleCardCount: Int {
    cardViews.count
  }

  var debugIsDeferringVisualReloads: Bool {
    defersVisualReloads
  }

  var debugDocumentViewFrame: NSRect {
    scrollView.documentView?.frame ?? .zero
  }

  var debugDocumentViewIsCardStack: Bool {
    scrollView.documentView === itemsStack
  }

  var debugContentInsets: NSEdgeInsets {
    mainStack?.edgeInsets ?? NSEdgeInsets()
  }

  var debugPanelCornerRadius: CGFloat {
    layer?.cornerRadius ?? 0
  }

  var debugCardAccessibilityLabels: [String] {
    cardViews.compactMap { $0.accessibilityLabel() }
  }

  var debugCardAccessibilityValues: [String] {
    cardViews.compactMap { $0.accessibilityValue() as? String }
  }

  var debugCardAccessibilityHelps: [String] {
    cardViews.compactMap { $0.accessibilityHelp() }
  }

  var debugCardAcceptsFirstResponder: [Bool] {
    cardViews.map(\.acceptsFirstResponder)
  }

  var debugKeyboardFocusedCardIndexes: [Int] {
    cardViews.enumerated().compactMap { index, card in
      card.debugIsKeyboardFocused ? index : nil
    }
  }

  var debugCardBorderWidths: [CGFloat] {
    cardViews.map(\.debugBorderWidth)
  }

  var debugCardPreviewSummaries: [String] {
    cardViews.map(\.debugPreviewSummary)
  }

  var debugCardTextPreviewTitles: [String] {
    cardViews.map(\.debugTextPreviewTitle)
  }

  var debugCardTextPreviewBodies: [String] {
    cardViews.map(\.debugTextPreviewBody)
  }

  var debugCardPreviewStyles: [String] {
    cardViews.map(\.debugPreviewStyle)
  }

  var debugCardDensity: String {
    cardDensity.rawValue
  }

  var debugCardSizes: [NSSize] {
    cardViews.map { $0.frame.size }
  }

  var debugCardHeaderBadgeSymbols: [String] {
    cardViews.map(\.debugHeaderBadgeSymbol)
  }

  var debugFirstCardHeaderTitle: String {
    cardViews.first?.debugHeaderTitle ?? ""
  }

  var debugFirstCardHeaderSubtitle: String {
    cardViews.first?.debugHeaderSubtitle ?? ""
  }

  var debugFirstCardHeaderColorHex: String {
    cardViews.first?.debugHeaderColorHex ?? ""
  }

  var debugFirstCardFooterDetailText: String {
    cardViews.first?.debugFooterDetailText ?? ""
  }

  var debugFirstCardFooterSourceText: String {
    cardViews.first?.debugFooterSourceText ?? ""
  }

  var debugFirstCardFooterSourceIsHidden: Bool {
    cardViews.first?.debugFooterSourceIsHidden ?? true
  }

  var debugQuickPasteBadgeTexts: [String] {
    cardViews.compactMap(\.debugQuickPasteBadgeText)
  }

  var debugSelectedCardFrameInDocument: NSRect {
    guard viewModel.selectedIndex >= 0, viewModel.selectedIndex < cardViews.count else {
      return .zero
    }
    let card = cardViews[viewModel.selectedIndex]
    return card.convert(card.bounds, to: itemsStack)
  }

  var debugCardRailVisibleRect: NSRect {
    scrollView.contentView.bounds
  }

  var debugCardRailDocumentWidth: CGFloat {
    scrollView.documentView?.frame.width ?? 0
  }

  var debugVisibleCardPageStep: Int {
    visibleCardPageStep
  }

  var debugCardRailOverflowFadeVisibility: [Bool] {
    scrollView.overflowFadeVisibility
  }

  func debugScrollCardRailVertically(deltaY: CGFloat) {
    scrollView.scrollHorizontallyByVerticalDelta(deltaY)
  }

  var debugFirstCardMenuTitles: [String] {
    cardViews.first?.debugMenuTitles ?? []
  }

  var debugFirstCardCollectionMenuTitles: [String] {
    cardViews.first?.debugCollectionMenuTitles ?? []
  }

  var debugFirstCardCollectActionMenuTitles: [String] {
    cardViews.first?.debugCollectActionMenuTitles ?? []
  }

  var debugFirstCardCaptureRuleMenuTitles: [String] {
    cardViews.first?.debugCaptureRuleMenuTitles ?? []
  }

  var debugFirstCardVisibleActionLabels: [String] {
    cardViews.first?.debugVisibleActionLabels ?? []
  }

  var debugFirstCardVisibleActionRailWidth: CGFloat {
    cardViews.first?.debugVisibleActionRailWidth ?? 0
  }

  var debugFirstCardFooterDetailIsHidden: Bool {
    cardViews.first?.debugFooterDetailIsHidden ?? true
  }

  var debugFirstCardHeaderBadgeIsHidden: Bool {
    cardViews.first?.debugHeaderBadgeIsHidden ?? false
  }

  var debugFirstCardHeaderBadgeFrame: NSRect {
    cardViews.first?.debugHeaderBadgeFrame ?? .zero
  }

  var debugStackCornerLabels: [String] {
    cardViews.map(\.debugStackCornerLabel)
  }

  var debugStackCornerHiddenStates: [Bool] {
    cardViews.map(\.debugStackCornerIsHidden)
  }

  var debugFirstCardStackCornerFrame: NSRect {
    cardViews.first?.debugStackCornerFrame ?? .zero
  }

  func debugPressFirstCardStackCornerButton() {
    cardViews.first?.debugPressStackCornerButton()
  }

  var debugResultCountText: String {
    statusResultCountLabel.stringValue
  }

  var debugStatusText: String {
    statusLabel.stringValue
  }

  var debugStatusTone: String {
    currentStatusTone.rawValue
  }

  var debugCollectionTitles: [String] {
    ClipboardSortMode.allCases.compactMap { collectionButtons[$0]?.titleText }
  }

  var debugSelectedCollectionTitle: String? {
    if stackChip.isSelected {
      return stackChip.titleText
    }
    if let custom = customCollectionButtons.first(where: { $0.value.isSelected }) {
      return custom.value.titleText
    }
    return collectionButtons.first(where: { $0.value.isSelected })?.value.titleText
  }

  var debugCollectionCounts: [Int] {
    updateCollectionButtons()
    return ClipboardSortMode.allCases.compactMap { collectionButtons[$0]?.count }
  }

  var debugCollectionCountLabelHiddenStates: [Bool] {
    updateCollectionButtons()
    return ClipboardSortMode.allCases.compactMap { collectionButtons[$0]?.debugCountLabelIsHidden }
  }

  var debugCollectionChipAccessibilityLabels: [String] {
    updateCollectionButtons()
    return ClipboardSortMode.allCases.compactMap { collectionButtons[$0]?.accessibilityLabel() }
  }

  var debugCollectionChipAcceptsFirstResponder: [Bool] {
    ClipboardSortMode.allCases.compactMap { collectionButtons[$0]?.acceptsFirstResponder }
  }

  var debugKeyboardFocusedCollectionTitles: [String] {
    collectionChipOrder.compactMap { $0.debugIsKeyboardFocused ? $0.titleText : nil }
  }

  func debugFocusCollectionChip(_ mode: ClipboardSortMode) -> Bool {
    guard let chip = collectionButtons[mode] else { return false }
    return window?.makeFirstResponder(chip) ?? false
  }

  func debugFocusCard(at index: Int) -> Bool {
    guard index >= 0, index < cardViews.count else { return false }
    return window?.makeFirstResponder(cardViews[index]) ?? false
  }

  func debugPressFocusedResponderWithReturn() {
    debugPressFocusedResponder(characters: "\r", keyCode: 36)
  }

  func debugPressFocusedResponderWithSpace() {
    debugPressFocusedResponder(characters: " ", keyCode: 49)
  }

  func debugPressFocusedResponderKeyCode(_ keyCode: UInt16) {
    debugPressFocusedResponder(characters: "", keyCode: keyCode)
  }

  func debugTypeFocusedResponder(_ characters: String, keyCode: UInt16) {
    debugPressFocusedResponder(characters: characters, keyCode: keyCode)
  }

  func debugSetSearchFieldText(_ text: String) {
    searchField.stringValue = text
    updateSearchText()
  }

  private func debugPressFocusedResponder(characters: String, keyCode: UInt16) {
    guard let window,
          let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
          ) else {
      return
    }
    window.firstResponder?.keyDown(with: event)
  }

  var debugCustomCollectionTitles: [String] {
    viewModel.collectionNames
  }

  var debugCustomCollectionCounts: [Int] {
    updateCollectionButtons()
    return viewModel.collectionNames.compactMap { customCollectionButtons[$0]?.count }
  }

  var debugCustomCollectionCountLabelHiddenStates: [Bool] {
    updateCollectionButtons()
    return viewModel.collectionNames.compactMap { customCollectionButtons[$0]?.debugCountLabelIsHidden }
  }

  var debugCustomCollectionColorHexes: [String: String] {
    Dictionary(uniqueKeysWithValues: viewModel.collectionNames.map { name in
      (name, ClipboardCollectionVisuals.hexString(for: collectionColor(forCollectionNamed: name)))
    })
  }

  var debugStackChipIsVisible: Bool {
    collectionStack.arrangedSubviews.contains(stackChip)
  }

  var debugStackChipCount: Int {
    updateCollectionButtons()
    return stackChip.count
  }

  var debugStackChipIsSelected: Bool {
    stackChip.isSelected
  }

  func debugPressStackChip() {
    stackChip.onPress()
  }

  var debugCollectionRailVisibleWidth: CGFloat {
    collectionScrollView.contentView.bounds.width
  }

  var debugCollectionRailDocumentWidth: CGFloat {
    collectionScrollView.documentView?.frame.width ?? 0
  }

  var debugCollectionRailVisibleRect: NSRect {
    collectionScrollView.contentView.bounds
  }

  var debugCollectionRailOverflowFadeVisibility: [Bool] {
    collectionScrollView.overflowFadeVisibility
  }

  func debugScrollCollectionRailVertically(deltaY: CGFloat) {
    collectionScrollView.scrollHorizontallyByVerticalDelta(deltaY)
  }

  var debugEmptyStateText: (title: String, detail: String)? {
    emptyStateText
  }

  var debugAddCollectionButtonIsEnabled: Bool {
    addCollectionButton.isEnabled
  }

  var debugCollectionRailContainsAddButton: Bool {
    collectionStack.arrangedSubviews.contains(addCollectionButton)
  }

  func debugSetCollectionNameProvider(_ provider: @escaping () -> String?) {
    collectionNameProviderForTesting = provider
  }

  func debugPressAddCollectionButton() {
    createCollectionFromToolbar()
  }

  func debugCustomCollectionMenuTitles(named collectionName: String) -> [String] {
    customCollectionButtons[collectionName]?.debugMenuTitles ?? []
  }

  func debugEditCollection(named collectionName: String, to newName: String, colorHex: String) {
    viewModel.updateCollection(named: collectionName, to: newName, colorHex: colorHex)
  }

  func debugDeleteCollection(named collectionName: String) {
    viewModel.deleteCollection(named: collectionName)
  }

  func debugRenameFirstCard(to title: String) {
    viewModel.selectItem(at: 0)
    viewModel.updateSelectedTitle(to: title)
  }

  func debugShowFirstCardInClipboard() {
    showSelectedInClipboard(at: 0)
  }

  var debugSearchFieldText: String {
    searchField.stringValue
  }

  func debugDropFirstCard(onCollectionNamed collectionName: String) {
    guard let itemID = cardViews.first?.debugItemID else { return }
    customCollectionButtons[collectionName]?.debugDropItem(itemID)
  }

  var debugCustomCollectionDropTargets: [String] {
    viewModel.collectionNames.filter { customCollectionButtons[$0]?.debugAcceptsItemDrops == true }
  }

  #endif

  func controlTextDidChange(_ notification: Notification) {
    guard notification.object as? NSSearchField === searchField else { return }
    updateSearchText()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    guard control === searchField else { return false }

    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      viewModel.pasteSelected()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      if clearSearchForKeyboardCancel() {
        return true
      } else {
        onClose()
      }
      return true
    case #selector(NSResponder.moveUp(_:)):
      viewModel.moveSelection(-1)
      return true
    case #selector(NSResponder.moveDown(_:)):
      viewModel.moveSelection(1)
      return true
    default:
      return false
    }
  }

  @objc private func searchFieldChanged() {
    updateSearchText()
  }

  private func updateSearchText() {
    viewModel.searchText = searchField.stringValue
  }

  private func moveSelectionFromFocusedCard(_ delta: Int) {
    viewModel.moveSelection(delta)
    focusSelectedCard()
  }

  private func selectFirstCardFromFocusedCard() {
    viewModel.selectFirstItem()
    focusSelectedCard()
  }

  private func selectLastCardFromFocusedCard() {
    viewModel.selectLastItem()
    focusSelectedCard()
  }

  private func focusSelectedCard() {
    guard viewModel.selectedIndex >= 0,
          viewModel.selectedIndex < cardViews.count else {
      return
    }
    window?.makeFirstResponder(cardViews[viewModel.selectedIndex])
  }

  @objc private func closePanel() {
    onClose()
  }

  @objc private func openSettings() {
    onSettings()
  }

  func showSelectedInClipboard() {
    showSelectedInClipboard(at: viewModel.selectedIndex)
  }

  private func showSelectedInClipboard(at index: Int) {
    viewModel.selectItem(at: index)
    viewModel.showSelectedInClipboard()
    searchField.stringValue = viewModel.searchText
  }

  func createCollection() {
    createCollectionFromToolbar()
  }

  @objc private func createCollectionFromToolbar() {
    guard let request = requestCollectionCreation() else { return }
    viewModel.createCollection(named: request.name, colorHex: request.colorHex, selectAfterCreate: true)
  }

  private func editCollection(named collectionName: String) {
    guard let request = requestCollectionEdit(named: collectionName) else { return }
    viewModel.updateCollection(named: collectionName, to: request.name, colorHex: request.colorHex)
  }

  private func deleteCollection(named collectionName: String) {
    let count = viewModel.collectionCount(named: collectionName)
    guard confirmDeleteCollection(named: collectionName, count: count) else { return }
    viewModel.deleteCollection(named: collectionName)
  }

  private func requestCollectionCreation() -> CollectionCreationRequest? {
    #if DEBUG
    if let collectionNameProviderForTesting {
      guard let name = ClipboardCollectionDefaults.normalizedName(collectionNameProviderForTesting()) else {
        return nil
      }
      return CollectionCreationRequest(
        name: name,
        colorHex: ClipboardCollectionVisuals.defaultColorHex(forCollectionNamed: name)
      )
    }
    #endif

    return requestCollectionDetails(
      title: "New Collection",
      message: "Name this collection and choose its color.",
      actionTitle: "Create",
      initialName: "",
      initialColor: ClipboardCollectionVisuals.defaultColor(forCollectionNamed: "New Collection")
    )
  }

  private func requestCollectionEdit(named collectionName: String) -> CollectionCreationRequest? {
    requestCollectionDetails(
      title: "Edit Collection",
      message: "Update this collection's name and color.",
      actionTitle: "Save",
      initialName: collectionName,
      initialColor: collectionColor(forCollectionNamed: collectionName)
    )
  }

  private func requestCollectionDetails(
    title: String,
    message: String,
    actionTitle: String,
    initialName: String,
    initialColor: NSColor
  ) -> CollectionCreationRequest? {
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    input.placeholderString = "Collection name"
    input.stringValue = initialName

    let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 48, height: 28))
    colorWell.color = initialColor

    let colorLabel = NSTextField(labelWithString: "Color")
    colorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    colorLabel.textColor = .secondaryLabelColor

    let colorRow = NSStackView(views: [colorLabel, colorWell])
    colorRow.orientation = .horizontal
    colorRow.alignment = .centerY
    colorRow.spacing = 10

    let stack = NSStackView(views: [input, colorRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.frame = NSRect(x: 0, y: 0, width: 260, height: 64)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.accessoryView = stack
    alert.addButton(withTitle: actionTitle)
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = input

    guard alert.runModal() == .alertFirstButtonReturn,
          let name = ClipboardCollectionDefaults.normalizedName(input.stringValue) else {
      return nil
    }
    return CollectionCreationRequest(
      name: name,
      colorHex: ClipboardCollectionVisuals.hexString(for: colorWell.color)
    )
  }

  private func confirmDeleteCollection(named collectionName: String, count: Int) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Delete \(collectionName)?"
    let noun = count == 1 ? "clip" : "clips"
    alert.informativeText = count > 0
      ? "This removes \(count) \(noun) in this collection from clipboard history."
      : "This removes the empty collection."
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

private enum ClipboardItemDragPasteboard {
  static let itemIDType = NSPasteboard.PasteboardType("com.clipbored.clipboard-item-id")
  static let acceptedTypes: [NSPasteboard.PasteboardType] = [
    itemIDType,
    .string,
    .URL,
    .fileURL,
    .tiff,
    .png,
    .pdf,
    .sound,
    .rtf
  ]
}

private func shelfSearchText(from event: NSEvent) -> String? {
  let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
  guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return nil }
  guard let characters = event.characters, !characters.isEmpty else { return nil }
  guard characters.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
  return characters
}

private enum ClipboardCardDragContext {
  static var itemID: UUID?
}

private final class HorizontalRailScrollView: NSScrollView {
  private let leadingFade = RailEdgeFadeView(edge: .leading)
  private let trailingFade = RailEdgeFadeView(edge: .trailing)
  private let fadeWidth: CGFloat = 26

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureOverflowFades()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureOverflowFades()
  }

  override func scrollWheel(with event: NSEvent) {
    let horizontalDelta = event.scrollingDeltaX
    let verticalDelta = event.scrollingDeltaY
    if abs(verticalDelta) > abs(horizontalDelta),
       abs(verticalDelta) > 0,
       canScrollHorizontally {
      scrollHorizontally(by: -verticalDelta)
      return
    }

    super.scrollWheel(with: event)
    updateOverflowFades()
  }

  override func layout() {
    super.layout()
    updateOverflowFades()
  }

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    updateOverflowFades()
  }

  func scrollHorizontallyByVerticalDelta(_ deltaY: CGFloat) {
    scrollHorizontally(by: -deltaY)
  }

  var overflowFadeVisibility: [Bool] {
    updateOverflowFades()
    return [!leadingFade.isHidden, !trailingFade.isHidden]
  }

  private func configureOverflowFades() {
    leadingFade.translatesAutoresizingMaskIntoConstraints = false
    trailingFade.translatesAutoresizingMaskIntoConstraints = false
    leadingFade.isHidden = true
    trailingFade.isHidden = true
    addSubview(leadingFade)
    addSubview(trailingFade)
    NSLayoutConstraint.activate([
      leadingFade.leadingAnchor.constraint(equalTo: leadingAnchor),
      leadingFade.topAnchor.constraint(equalTo: topAnchor),
      leadingFade.bottomAnchor.constraint(equalTo: bottomAnchor),
      leadingFade.widthAnchor.constraint(equalToConstant: fadeWidth),
      trailingFade.trailingAnchor.constraint(equalTo: trailingAnchor),
      trailingFade.topAnchor.constraint(equalTo: topAnchor),
      trailingFade.bottomAnchor.constraint(equalTo: bottomAnchor),
      trailingFade.widthAnchor.constraint(equalToConstant: fadeWidth)
    ])
  }

  private var canScrollHorizontally: Bool {
    maxHorizontalOffset > 0
  }

  private var maxHorizontalOffset: CGFloat {
    guard let documentView else { return 0 }
    return max(0, documentView.frame.width - contentView.bounds.width)
  }

  private func scrollHorizontally(by deltaX: CGFloat) {
    let maxOffset = maxHorizontalOffset
    guard maxOffset > 0 else { return }
    let origin = contentView.bounds.origin
    let targetX = min(max(origin.x + deltaX, 0), maxOffset)
    guard targetX != origin.x else { return }

    contentView.scroll(to: NSPoint(x: targetX, y: origin.y))
    reflectScrolledClipView(contentView)
  }

  private func updateOverflowFades() {
    let maxOffset = maxHorizontalOffset
    guard maxOffset > 0 else {
      leadingFade.isHidden = true
      trailingFade.isHidden = true
      return
    }

    let currentX = contentView.bounds.minX
    leadingFade.isHidden = currentX <= 0.5
    trailingFade.isHidden = currentX >= maxOffset - 0.5
  }
}

private final class RailEdgeFadeView: NSView {
  enum Edge {
    case leading
    case trailing
  }

  private let edge: Edge

  init(edge: Edge) {
    self.edge = edge
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    let color = NSColor.windowBackgroundColor.withAlphaComponent(0.88)
    let clear = color.withAlphaComponent(0)
    let gradient = NSGradient(colors: edge == .leading ? [color, clear] : [clear, color])
    gradient?.draw(in: bounds, angle: 0)
  }
}

private final class CollectionChipView: NSView {
  let titleText: String
  private let color: NSColor
  private let dot = NSView()
  private let label: NSTextField
  private let countLabel = NSTextField(labelWithString: "0")
  private(set) var isSelected = false
  private(set) var count = 0
  private var isKeyboardFocused = false
  private var isDropTargeted = false
  var onPress: () -> Void = {}
  var onStartSearch: (String) -> Void = { _ in }
  var onMoveFocus: (Int) -> Void = { _ in }
  var onSelectFirst: () -> Void = {}
  var onSelectLast: () -> Void = {}
  var onDropItem: ((UUID) -> Void)?
  var onEdit: (() -> Void)?
  var onDelete: (() -> Void)?

  init(title: String, color: NSColor) {
    self.titleText = title
    self.color = color
    self.label = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    configure()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func configure() {
    wantsLayer = true
    focusRingType = .default
    layer?.cornerRadius = 13
    layer?.borderWidth = 0.6
    layer?.borderColor = NSColor.clear.cgColor
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityHelp("Press Return or Space to show \(titleText). Use Left and Right to move between collections.")
    heightAnchor.constraint(equalToConstant: 26).isActive = true
    registerForDraggedTypes(ClipboardItemDragPasteboard.acceptedTypes)

    dot.wantsLayer = true
    dot.layer?.cornerRadius = 4
    dot.layer?.backgroundColor = color.cgColor
    dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
    dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    label.toolTip = label.stringValue

    countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    countLabel.textColor = .secondaryLabelColor
    countLabel.alignment = .center
    countLabel.lineBreakMode = .byTruncatingTail
    countLabel.wantsLayer = true
    countLabel.layer?.cornerRadius = 8
    countLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
    countLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
    countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let stack = NSStackView(views: [dot, label, countLabel])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
      widthAnchor.constraint(lessThanOrEqualToConstant: 164)
    ])
    setSelected(false)
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    label.textColor = selected ? .labelColor : .secondaryLabelColor
    countLabel.textColor = selected ? .labelColor : .tertiaryLabelColor
    countLabel.layer?.backgroundColor = (
      selected
      ? NSColor.controlAccentColor.withAlphaComponent(0.16)
      : NSColor.labelColor.withAlphaComponent(0.07)
    ).cgColor
    updateCountLabelVisibility()
    updateAccessibility()
    updateChrome()
  }

  private func setDropTargeted(_ targeted: Bool) {
    guard isDropTargeted != targeted else { return }
    isDropTargeted = targeted
    updateChrome()
  }

  private func updateChrome() {
    if isDropTargeted {
      layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
      layer?.borderColor = color.withAlphaComponent(0.68).cgColor
    } else if isSelected {
      layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.58).cgColor
      layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(isKeyboardFocused ? 0.74 : 0.34).cgColor
    } else if isKeyboardFocused {
      layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.34).cgColor
      layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.52).cgColor
    } else {
      layer?.backgroundColor = NSColor.clear.cgColor
      layer?.borderColor = NSColor.clear.cgColor
    }
  }

  func setCount(_ count: Int) {
    self.count = count
    countLabel.stringValue = count > 999 ? "999+" : "\(count)"
    updateCountLabelVisibility()
    updateAccessibility()
  }

  private func updateCountLabelVisibility() {
    countLabel.isHidden = count == 0
  }

  private func updateAccessibility() {
    let noun = count == 1 ? "clip" : "clips"
    let selectedText = isSelected ? "selected, " : ""
    setAccessibilityLabel("\(titleText), \(selectedText)\(count) \(noun)")
    setAccessibilityValue("\(count)")
    setAccessibilityHelp("Press Return or Space to show \(titleText). Use Left and Right to move between collections.")
    toolTip = "\(titleText), \(selectedText)\(count) \(noun)"
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func becomeFirstResponder() -> Bool {
    isKeyboardFocused = true
    updateChrome()
    return true
  }

  override func resignFirstResponder() -> Bool {
    isKeyboardFocused = false
    updateChrome()
    return true
  }

  func clearKeyboardFocus() {
    guard isKeyboardFocused else { return }
    isKeyboardFocused = false
    updateChrome()
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    onPress()
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 49:
      onPress()
    case 115:
      onSelectFirst()
    case 119:
      onSelectLast()
    case 123:
      onMoveFocus(-1)
    case 124:
      onMoveFocus(1)
    default:
      if let text = shelfSearchText(from: event) {
        onStartSearch(text)
      } else {
        super.keyDown(with: event)
      }
    }
  }

  override func accessibilityPerformPress() -> Bool {
    onPress()
    return true
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard onEdit != nil || onDelete != nil else { return nil }
    return contextMenu()
  }

  private func contextMenu() -> NSMenu {
    let menu = NSMenu(title: titleText)
    menu.autoenablesItems = false
    if onEdit != nil {
      let item = NSMenuItem(title: "Edit Collection...", action: #selector(editFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onDelete != nil {
      if !menu.items.isEmpty {
        menu.addItem(NSMenuItem.separator())
      }
      let item = NSMenuItem(title: "Delete Collection", action: #selector(deleteFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    return menu
  }

  @objc private func editFromMenu() {
    onEdit?()
  }

  @objc private func deleteFromMenu() {
    onDelete?()
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard onDropItem != nil, draggedItemID(from: sender) != nil else { return [] }
    setDropTargeted(true)
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard onDropItem != nil, draggedItemID(from: sender) != nil else {
      setDropTargeted(false)
      return []
    }
    setDropTargeted(true)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    setDropTargeted(false)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    onDropItem != nil && draggedItemID(from: sender) != nil
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let itemID = draggedItemID(from: sender), let onDropItem else { return false }
    onDropItem(itemID)
    setDropTargeted(false)
    return true
  }

  override func concludeDragOperation(_ sender: NSDraggingInfo?) {
    setDropTargeted(false)
  }

  private func draggedItemID(from sender: NSDraggingInfo) -> UUID? {
    if let itemID = ClipboardCardDragContext.itemID {
      return itemID
    }

    return sender.draggingPasteboard
      .string(forType: ClipboardItemDragPasteboard.itemIDType)
      .flatMap(UUID.init(uuidString:))
  }

  #if DEBUG
  var debugAcceptsItemDrops: Bool {
    onDropItem != nil
  }

  var debugIsKeyboardFocused: Bool {
    isKeyboardFocused
  }

  var debugCountLabelIsHidden: Bool {
    countLabel.isHidden
  }

  func debugDropItem(_ itemID: UUID) {
    onDropItem?(itemID)
  }

  var debugMenuTitles: [String] {
    contextMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }
  #endif
}

private final class AspectFillImageView: NSView {
  private let image: NSImage

  init(image: NSImage) {
    self.image = image
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool {
    true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard bounds.width > 0, bounds.height > 0, image.size.width > 0, image.size.height > 0 else {
      return
    }

    NSBezierPath(rect: bounds).addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
    let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let drawRect = NSRect(
      x: bounds.midX - (drawSize.width / 2),
      y: bounds.midY - (drawSize.height / 2),
      width: drawSize.width,
      height: drawSize.height
    )
    image.draw(
      in: drawRect,
      from: NSRect(origin: .zero, size: image.size),
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: nil
    )
  }
}

private final class ClipboardItemCardView: NSView, NSDraggingSource {
  private enum Metrics {
    static let dragThreshold: CGFloat = 4
    static let actionRailBadgeGap: CGFloat = 8
    static let actionRailLeadingMargin: CGFloat = 10
  }
  private enum Palette {
    static let border = NSColor.separatorColor.withAlphaComponent(0.20).cgColor
    static let selectedBorder = NSColor.controlAccentColor.withAlphaComponent(0.62).cgColor
    static let cardSurface = NSColor.windowBackgroundColor.cgColor
    static let selectedSurface = NSColor.windowBackgroundColor.cgColor
    static let bodyBackground = NSColor.windowBackgroundColor.cgColor
    static let footerBackground = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
    static let divider = NSColor.separatorColor.withAlphaComponent(0.14).cgColor
  }

  private struct ActionRailButtonSpec {
    let systemName: String
    let toolTip: String
    let action: Selector
    let isPrimary: Bool
    let overflowPriority: Int?

    init(
      _ systemName: String,
      toolTip: String,
      action: Selector,
      isPrimary: Bool = false,
      overflowPriority: Int? = nil
    ) {
      self.systemName = systemName
      self.toolTip = toolTip
      self.action = action
      self.isPrimary = isPrimary
      self.overflowPriority = overflowPriority
    }
  }

  var onSelect: (Int) -> Void = { _ in }
  var onMoveSelection: (Int) -> Void = { _ in }
  var onPageSelection: (Int) -> Void = { _ in }
  var onSelectFirst: () -> Void = {}
  var onSelectLast: () -> Void = {}
  var onPaste: (Int) -> Void = { _ in }
  var onCopy: (Int) -> Void = { _ in }
  var onPastePlainText: (Int) -> Void = { _ in }
  var onCopyPlainText: (Int) -> Void = { _ in }
  var onToggleStack: (Int) -> Void = { _ in }
  var onPasteStackNext: () -> Void = {}
  var onCopyStackNext: () -> Void = {}
  var onClearStack: () -> Void = {}
  var onShowInClipboard: (Int) -> Void = { _ in }
  var onRename: (Int) -> Void = { _ in }
  var onEditText: (Int) -> Void = { _ in }
  var onPreview: (Int) -> Void = { _ in }
  var onPasteboardWriters: (Int) -> [NSPasteboardWriting] = { _ in [] }
  var onOpen: (Int) -> Void = { _ in }
  var onReveal: (Int) -> Void = { _ in }
  var onTogglePin: (Int) -> Void = { _ in }
  var onAssignCollection: (Int, String?) -> Void = { _, _ in }
  var onIgnoreSourceApp: (Int) -> Void = { _ in }
  var onIgnoreKind: (Int) -> Void = { _ in }
  var onDelete: (Int) -> Void = { _ in }
  var onStartSearch: (String) -> Void = { _ in }

  private let index: Int
  private let itemID: UUID
  private let layout: ClipboardItemCardLayout
  private let itemKind: ClipboardItemKind
  private let itemIsPinned: Bool
  private let itemIsStacked: Bool
  private let stackCount: Int
  private let canShowInClipboard: Bool
  private let itemSourceAppName: String?
  private let itemSourceAppBundleID: String?
  private let itemCollectionName: String?
  private let activeCollectionName: String?
  private let activeCollectionColor: NSColor?
  private let collectionNames: [String]
  private let contentView = NSView()
  private let footerSourceLabel = NSTextField(labelWithString: "")
  private let footerDetailLabel = NSTextField(labelWithString: "")
  private let actionRail = NSStackView()
  private let stackCornerButton = NSButton()
  private var actionRailButtons: [NSButton] = []
  private weak var headerBadgeView: NSView?
  private weak var headerPinView: NSView?
  private weak var quickPasteBadgeLabel: NSTextField?
  private var isSelected = false
  private var isHovered = false
  private var isKeyboardFocused = false
  private var mouseDownLocation: NSPoint?
  private var trackingAreaRef: NSTrackingArea?

  init(
    item: ClipboardItem,
    thumbnail: NSImage?,
    index: Int,
    layout: ClipboardItemCardLayout = .regular,
    collectionNames: [String] = [],
    isStacked: Bool = false,
    stackCount: Int = 0,
    canShowInClipboard: Bool = false,
    selectedCollectionName: String? = nil,
    selectedCollectionColor: NSColor? = nil
  ) {
    let normalizedItemCollection = ClipboardCollectionDefaults.normalizedName(item.collectionName)
    let normalizedSelectedCollection = ClipboardCollectionDefaults.normalizedName(selectedCollectionName)
    let activeCollection = normalizedSelectedCollection == normalizedItemCollection ? normalizedSelectedCollection : nil
    self.index = index
    self.itemID = item.id
    self.layout = layout
    self.itemKind = item.kind
    self.itemIsPinned = item.isPinned
    self.itemIsStacked = isStacked
    self.stackCount = stackCount
    self.canShowInClipboard = canShowInClipboard
    self.itemSourceAppName = Self.presentSourceText(item.sourceApp)
    self.itemSourceAppBundleID = Self.presentSourceText(item.sourceAppBundleId)
    self.itemCollectionName = normalizedItemCollection
    self.activeCollectionName = activeCollection
    self.activeCollectionColor = activeCollection.map { name in
      selectedCollectionColor ?? ClipboardCollectionVisuals.color(forCollectionNamed: name)
    }
    self.collectionNames = collectionNames.compactMap { ClipboardCollectionDefaults.normalizedName($0) }
    super.init(frame: .zero)
    configure(item: item, thumbnail: thumbnail)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    contentView.layer?.borderWidth = isKeyboardFocused ? 2 : 1
    if selected {
      contentView.layer?.backgroundColor = Palette.selectedSurface
      contentView.layer?.borderColor = isKeyboardFocused
        ? NSColor.controlAccentColor.withAlphaComponent(0.86).cgColor
        : Palette.selectedBorder
    } else if isKeyboardFocused {
      contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
      contentView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.58).cgColor
    } else if isHovered {
      contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
      contentView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
    } else {
      contentView.layer?.backgroundColor = Palette.cardSurface
      contentView.layer?.borderColor = Palette.border
    }
    let emphasized = selected || isKeyboardFocused
    layer?.shadowOpacity = emphasized ? 0.16 : (isHovered ? 0.12 : 0.08)
    layer?.shadowRadius = emphasized ? 16 : 12
    layer?.shadowOffset = NSSize(width: 0, height: emphasized ? 6 : 4)
    layer?.transform = emphasized ? CATransform3DMakeTranslation(0, -4, 0) : CATransform3DIdentity
    setAccessibilityValue(selected ? "Selected" : "Not selected")
    updateActionRailVisibility()
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func becomeFirstResponder() -> Bool {
    isKeyboardFocused = true
    onSelect(index)
    setSelected(isSelected)
    return true
  }

  override func resignFirstResponder() -> Bool {
    isKeyboardFocused = false
    setSelected(isSelected)
    return true
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:
      onPaste(index)
    case 49:
      if canPreview {
        onPreview(index)
      } else {
        onPaste(index)
      }
    case 115:
      onSelectFirst()
    case 116:
      onPageSelection(-1)
    case 119:
      onSelectLast()
    case 121:
      onPageSelection(1)
    case 123:
      onMoveSelection(-1)
    case 124:
      onMoveSelection(1)
    default:
      if let text = shelfSearchText(from: event) {
        onStartSearch(text)
      } else {
        super.keyDown(with: event)
      }
    }
  }

  override func accessibilityPerformPress() -> Bool {
    onPaste(index)
    return true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaRef {
      removeTrackingArea(trackingAreaRef)
    }
    let tracking = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(tracking)
    trackingAreaRef = tracking
  }

  override func mouseEntered(with event: NSEvent) {
    onSelect(index)
    isHovered = true
    setSelected(isSelected)
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    setSelected(isSelected)
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      mouseDownLocation = nil
      onPaste(index)
    } else {
      mouseDownLocation = convert(event.locationInWindow, from: nil)
      onSelect(index)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = mouseDownLocation else { return }
    let current = convert(event.locationInWindow, from: nil)
    guard hypot(current.x - start.x, current.y - start.y) >= Metrics.dragThreshold else {
      return
    }

    mouseDownLocation = nil
    let writers = onPasteboardWriters(index)
    let dragWriters = writers.isEmpty ? [internalDragPasteboardItem()] : writers
    onSelect(index)
    ClipboardCardDragContext.itemID = itemID

    let preview = dragPreviewImage()
    let dragItems = dragWriters.enumerated().map { offset, writer in
      let draggingItem = NSDraggingItem(pasteboardWriter: writer)
      let offsetAmount = CGFloat(offset) * 4
      let frame = NSRect(
        x: bounds.minX + offsetAmount,
        y: bounds.minY - offsetAmount,
        width: bounds.width,
        height: bounds.height
      )
      draggingItem.setDraggingFrame(frame, contents: preview)
      return draggingItem
    }

    let session = beginDraggingSession(with: dragItems, event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
    if dragItems.count > 1 {
      session.draggingFormation = .pile
    }
  }

  private func internalDragPasteboardItem() -> NSPasteboardItem {
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(itemID.uuidString, forType: ClipboardItemDragPasteboard.itemIDType)
    return pasteboardItem
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    .copy
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
    true
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    if ClipboardCardDragContext.itemID == itemID {
      ClipboardCardDragContext.itemID = nil
    }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    onSelect(index)
    return contextMenu()
  }

  #if DEBUG
  private(set) var debugPreviewSummary = ""
  private(set) var debugPreviewStyle = ""
  private(set) var debugHeaderBadgeSymbol = ""
  private(set) var debugHeaderTitle = ""
  private(set) var debugHeaderSubtitle = ""
  private(set) var debugHeaderColorHex = ""
  private(set) var debugTextPreviewTitle = ""
  private(set) var debugTextPreviewBody = ""

  var debugMenuTitles: [String] {
    contextMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  var debugCollectionMenuTitles: [String] {
    guard let collectionMenu = contextMenu().items.first(where: { $0.title == "Add to Collection" })?.submenu else {
      return []
    }
    return collectionMenu.items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  var debugCollectActionMenuTitles: [String] {
    collectionAssignmentMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  var debugCaptureRuleMenuTitles: [String] {
    guard let rulesMenu = contextMenu().items.first(where: { $0.title == "Capture Rules" })?.submenu else {
      return []
    }
    return rulesMenu.items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  var debugVisibleActionLabels: [String] {
    actionRail.isHidden ? [] : actionRailButtons.map { $0.toolTip ?? "" }
  }

  var debugVisibleActionRailWidth: CGFloat {
    guard !actionRail.isHidden else { return 0 }
    return actionRail.constraints.first { constraint in
      constraint.firstAttribute == .width && constraint.secondItem == nil
    }?.constant ?? actionRail.fittingSize.width
  }

  var debugFooterDetailIsHidden: Bool {
    footerDetailLabel.isHidden
  }

  var debugHeaderBadgeIsHidden: Bool {
    headerBadgeView?.isHidden ?? false
  }

  var debugHeaderBadgeFrame: NSRect {
    guard let headerBadgeView else { return .zero }
    return headerBadgeView.convert(headerBadgeView.bounds, to: self)
  }

  var debugStackCornerLabel: String {
    stackCornerButton.toolTip ?? ""
  }

  var debugStackCornerIsHidden: Bool {
    stackCornerButton.isHidden
  }

  var debugStackCornerFrame: NSRect {
    stackCornerButton.convert(stackCornerButton.bounds, to: self)
  }

  func debugPressStackCornerButton() {
    stackCornerButton.performClick(nil)
  }

  var debugQuickPasteBadgeText: String? {
    quickPasteBadgeLabel?.stringValue
  }

  var debugIsKeyboardFocused: Bool {
    isKeyboardFocused
  }

  var debugBorderWidth: CGFloat {
    contentView.layer?.borderWidth ?? 0
  }

  var debugFooterDetailText: String {
    footerDetailLabel.stringValue
  }

  var debugFooterSourceText: String {
    footerSourceLabel.stringValue
  }

  var debugFooterSourceIsHidden: Bool {
    footerSourceLabel.isHidden
  }

  var debugItemID: UUID {
    itemID
  }

  static func debugHex(_ color: NSColor) -> String {
    ClipboardCollectionVisuals.hexString(for: color)
  }
  #endif

  private func contextMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    addMenuItem("Paste", action: #selector(pasteFromMenu), to: menu)
    addMenuItem("Copy", action: #selector(copyFromMenu), to: menu)
    if canPlainText {
      addMenuItem("Paste Plain Text", action: #selector(pastePlainTextFromMenu), to: menu)
      addMenuItem("Copy Plain Text", action: #selector(copyPlainTextFromMenu), to: menu)
    }
    if canShowInClipboard {
      addMenuItem("Show in Clipboard", action: #selector(showInClipboardFromMenu), to: menu)
    }
    addMenuItem("Rename...", action: #selector(renameFromMenu), to: menu)
    addMenuItem(itemIsStacked ? "Remove from Stack" : "Add to Stack", action: #selector(toggleStackFromMenu), to: menu)
    if stackCount > 0 {
      addMenuItem("Paste Stack Next", action: #selector(pasteStackNextFromMenu), to: menu)
      addMenuItem("Copy Stack Next", action: #selector(copyStackNextFromMenu), to: menu)
      addMenuItem("Clear Stack", action: #selector(clearStackFromMenu), to: menu)
    }
    if canEditText {
      addMenuItem("Edit", action: #selector(editTextFromMenu), to: menu)
    }
    if canPreview {
      addMenuItem("Quick Look", action: #selector(previewFromMenu), to: menu)
    }
    addMenuItem(itemIsPinned ? "Unpin" : "Pin", action: #selector(togglePinFromMenu), to: menu)
    addCollectionMenu(to: menu)
    addCaptureRulesMenu(to: menu)
    menu.addItem(NSMenuItem.separator())
    let open = addMenuItem("Open", action: #selector(openFromMenu), to: menu)
    open.isEnabled = canOpen
    let reveal = addMenuItem("Reveal in Finder", action: #selector(revealFromMenu), to: menu)
    reveal.isEnabled = canReveal
    menu.addItem(NSMenuItem.separator())
    addMenuItem("Delete", action: #selector(deleteFromMenu), to: menu)
    return menu
  }

  private func addCollectionMenu(to menu: NSMenu) {
    let parent = NSMenuItem(title: "Add to Collection", action: nil, keyEquivalent: "")
    let submenu = collectionAssignmentMenu()
    menu.addItem(parent)
    menu.setSubmenu(submenu, for: parent)
  }

  private func collectionAssignmentMenu() -> NSMenu {
    let submenu = NSMenu(title: "Add to Collection")
    submenu.autoenablesItems = false

    for name in availableCollectionNames() {
      let item = NSMenuItem(title: name, action: #selector(assignToCollectionFromMenu(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = name
      if itemCollectionName == name {
        item.state = .on
      }
      submenu.addItem(item)
    }

    submenu.addItem(NSMenuItem.separator())
    let newCollection = NSMenuItem(title: "New Collection...", action: #selector(createCollectionFromMenu), keyEquivalent: "")
    newCollection.target = self
    submenu.addItem(newCollection)

    if itemCollectionName?.clipboardTrimmed.isEmpty == false {
      submenu.addItem(NSMenuItem.separator())
      let remove = NSMenuItem(title: "Remove from Collection", action: #selector(removeFromCollectionFromMenu), keyEquivalent: "")
      remove.target = self
      submenu.addItem(remove)
    }

    return submenu
  }

  private func addCaptureRulesMenu(to menu: NSMenu) {
    let parent = NSMenuItem(title: "Capture Rules", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "Capture Rules")
    submenu.autoenablesItems = false

    let ignoreSource = NSMenuItem(
      title: ignoreSourceTitle(),
      action: #selector(ignoreSourceAppFromMenu),
      keyEquivalent: ""
    )
    ignoreSource.target = self
    ignoreSource.isEnabled = itemSourceAppName != nil || itemSourceAppBundleID != nil
    submenu.addItem(ignoreSource)

    let ignoreKind = NSMenuItem(
      title: "Ignore \(kindLabel(for: itemKind)) Items",
      action: #selector(ignoreKindFromMenu),
      keyEquivalent: ""
    )
    ignoreKind.target = self
    ignoreKind.isEnabled = true
    submenu.addItem(ignoreKind)

    menu.addItem(parent)
    menu.setSubmenu(submenu, for: parent)
  }

  private func ignoreSourceTitle() -> String {
    if let itemSourceAppName {
      return "Ignore \(itemSourceAppName)"
    }
    if let itemSourceAppBundleID {
      return "Ignore \(itemSourceAppBundleID)"
    }
    return "Ignore Source App"
  }

  private static func presentSourceText(_ value: String?) -> String? {
    guard let text = value?.clipboardTrimmed, !text.isEmpty else { return nil }
    return text
  }

  private func availableCollectionNames() -> [String] {
    var names: [String] = []
    var seen = Set<String>()
    for candidate in ClipboardCollectionDefaults.names + collectionNames {
      guard let name = ClipboardCollectionDefaults.normalizedName(candidate) else { continue }
      let key = name.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      names.append(name)
    }
    return names
  }

  @discardableResult
  private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    menu.addItem(item)
    return item
  }

  private var canOpen: Bool {
    switch itemKind {
    case .url, .file, .image, .pdf, .audio:
      return true
    case .text, .richText, .unknown:
      return false
    }
  }

  private var canPreview: Bool {
    switch itemKind {
    case .text, .url, .image, .richText, .file, .pdf, .audio, .unknown:
      return true
    }
  }

  private var canEditText: Bool {
    itemKind == .text
  }

  private var canPlainText: Bool {
    switch itemKind {
    case .url, .image, .richText, .file, .pdf, .audio:
      return true
    case .text, .unknown:
      return false
    }
  }

  private var canReveal: Bool {
    switch itemKind {
    case .file, .image, .pdf, .audio:
      return true
    case .text, .richText, .url, .unknown:
      return false
    }
  }

  private func configureActionRail() {
    actionRail.orientation = .horizontal
    actionRail.alignment = .centerY
    actionRail.spacing = 4
    actionRail.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    actionRail.wantsLayer = true
    actionRail.layer?.cornerRadius = layout.actionRailHeight / 2
    actionRail.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.44).cgColor
    actionRail.layer?.borderWidth = 0.5
    actionRail.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    actionRail.layer?.shadowColor = NSColor.black.cgColor
    actionRail.layer?.shadowOpacity = 0.18
    actionRail.layer?.shadowRadius = 10
    actionRail.layer?.shadowOffset = NSSize(width: 0, height: 4)
    actionRail.translatesAutoresizingMaskIntoConstraints = false
    actionRail.heightAnchor.constraint(equalToConstant: layout.actionRailHeight).isActive = true
    actionRail.setContentHuggingPriority(.required, for: .horizontal)
    actionRail.setContentCompressionResistancePriority(.required, for: .horizontal)

    let specs = fittedActionRailButtonSpecs(from: preferredActionRailButtonSpecs())
    actionRailButtons = specs.map { spec in
      cardActionButton(
        spec.systemName,
        toolTip: spec.toolTip,
        action: spec.action,
        isPrimary: spec.isPrimary
      )
    }

    for button in actionRailButtons {
      actionRail.addArrangedSubview(button)
    }
    let contentWidth = actionRailWidth(for: specs)
    actionRail.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    updateActionRailVisibility()
  }

  private func preferredActionRailButtonSpecs() -> [ActionRailButtonSpec] {
    let pinTitle = itemIsPinned ? "Unpin" : "Pin"
    var specs: [ActionRailButtonSpec] = [
      ActionRailButtonSpec("return", toolTip: "Paste", action: #selector(pasteFromMenu), isPrimary: true),
      ActionRailButtonSpec("doc.on.doc", toolTip: "Copy", action: #selector(copyFromMenu))
    ]

    if canPlainText {
      specs.append(ActionRailButtonSpec("textformat", toolTip: "Paste Plain Text", action: #selector(pastePlainTextFromMenu)))
      specs.append(ActionRailButtonSpec("doc.plaintext", toolTip: "Copy Plain Text", action: #selector(copyPlainTextFromMenu), overflowPriority: 20))
    }

    specs.append(ActionRailButtonSpec(itemIsPinned ? "pin.slash" : "pin", toolTip: pinTitle, action: #selector(togglePinFromMenu), overflowPriority: 30))
    specs.append(ActionRailButtonSpec("plus", toolTip: "Collect", action: #selector(showCollectionMenuFromAction(_:))))

    if canEditText {
      specs.append(ActionRailButtonSpec("pencil", toolTip: "Edit", action: #selector(editTextFromMenu), overflowPriority: 50))
    }
    if canPreview {
      specs.append(ActionRailButtonSpec("eye", toolTip: "Preview", action: #selector(previewFromMenu), overflowPriority: 60))
    }
    if canOpen {
      specs.append(ActionRailButtonSpec("arrow.up.right.square", toolTip: "Open", action: #selector(openFromMenu), overflowPriority: 50))
    }
    if canReveal {
      specs.append(ActionRailButtonSpec("magnifyingglass", toolTip: "Reveal", action: #selector(revealFromMenu), overflowPriority: 40))
    }
    specs.append(ActionRailButtonSpec("trash", toolTip: "Delete", action: #selector(deleteFromMenu), overflowPriority: 10))
    return specs
  }

  private func fittedActionRailButtonSpecs(from specs: [ActionRailButtonSpec]) -> [ActionRailButtonSpec] {
    let maximumWidth = maximumVisibleActionRailWidth
    guard actionRailWidth(for: specs) > maximumWidth else { return specs }

    let moreSpec = ActionRailButtonSpec("ellipsis.circle", toolTip: "More", action: #selector(showMoreActionsFromActionRail(_:)))
    let overflowCandidates = specs.enumerated().compactMap { index, spec -> (index: Int, priority: Int)? in
      guard let priority = spec.overflowPriority else { return nil }
      return (index, priority)
    }.sorted { lhs, rhs in
      lhs.priority == rhs.priority ? lhs.index > rhs.index : lhs.priority < rhs.priority
    }

    var hiddenIndexes = Set<Int>()
    for candidate in overflowCandidates {
      hiddenIndexes.insert(candidate.index)
      let visibleSpecs = specs.enumerated().compactMap { index, spec in
        hiddenIndexes.contains(index) ? nil : spec
      } + [moreSpec]
      if actionRailWidth(for: visibleSpecs) <= maximumWidth {
        return visibleSpecs
      }
    }

    return specs.enumerated().compactMap { index, spec in
      hiddenIndexes.contains(index) ? nil : spec
    } + [moreSpec]
  }

  private func actionRailWidth(for specs: [ActionRailButtonSpec]) -> CGFloat {
    guard !specs.isEmpty else { return 0 }
    let buttonWidth = specs.reduce(CGFloat(0)) { width, spec in
      width + (spec.isPrimary ? layout.primaryActionButtonSize : layout.actionButtonSize)
    }
    return buttonWidth
      + CGFloat(max(0, specs.count - 1)) * actionRail.spacing
      + actionRail.edgeInsets.left
      + actionRail.edgeInsets.right
  }

  private var maximumVisibleActionRailWidth: CGFloat {
    layout.width
      - Metrics.actionRailLeadingMargin
      - Metrics.actionRailBadgeGap
      - headerBadgeSize
  }

  private var headerBadgeSize: CGFloat {
    layout.isCompact ? 36 : 42
  }

  private var stackCornerButtonSize: CGFloat {
    layout.isCompact ? 28 : 30
  }

  private var actionRailHeaderTopInset: CGFloat {
    max(8, (layout.headerHeight - layout.actionRailHeight) / 2)
  }

  private func cardActionButton(
    _ systemName: String,
    toolTip: String,
    action: Selector,
    isPrimary: Bool = false
  ) -> NSButton {
    let button = NSButton(title: "", target: self, action: action)
    let image = NSImage(systemSymbolName: systemName, accessibilityDescription: toolTip)
    image?.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.isBordered = false
    button.wantsLayer = true
    let size = isPrimary ? layout.primaryActionButtonSize : layout.actionButtonSize
    button.layer?.cornerRadius = size / 2
    if isPrimary {
      button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
      button.contentTintColor = .white
    } else if toolTip == "Collect" {
      button.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.88).cgColor
      button.contentTintColor = .white
    } else {
      button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
      button.contentTintColor = toolTip == "Delete"
        ? NSColor.white.withAlphaComponent(0.48)
        : NSColor.white.withAlphaComponent(0.78)
    }
    button.toolTip = toolTip
    button.setAccessibilityLabel(toolTip)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: size).isActive = true
    button.heightAnchor.constraint(equalToConstant: size).isActive = true
    return button
  }

  private func configureStackCornerButton() {
    let toolTip = itemIsStacked ? "Remove from Stack" : "Add to Stack"
    let image = NSImage(systemSymbolName: itemIsStacked ? "checkmark" : "plus", accessibilityDescription: toolTip)
    image?.isTemplate = true
    stackCornerButton.image = image
    stackCornerButton.imagePosition = .imageOnly
    stackCornerButton.imageScaling = .scaleProportionallyDown
    stackCornerButton.isBordered = false
    stackCornerButton.wantsLayer = true
    stackCornerButton.layer?.cornerRadius = stackCornerButtonSize / 2
    stackCornerButton.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.94).cgColor
    stackCornerButton.layer?.borderWidth = 1
    stackCornerButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
    stackCornerButton.layer?.shadowColor = NSColor.black.cgColor
    stackCornerButton.layer?.shadowOpacity = 0.22
    stackCornerButton.layer?.shadowRadius = 7
    stackCornerButton.layer?.shadowOffset = NSSize(width: 0, height: 3)
    stackCornerButton.contentTintColor = .white
    stackCornerButton.toolTip = toolTip
    stackCornerButton.setAccessibilityLabel(toolTip)
    stackCornerButton.target = self
    stackCornerButton.action = #selector(toggleStackFromCornerButton)
    stackCornerButton.translatesAutoresizingMaskIntoConstraints = false
    stackCornerButton.setContentHuggingPriority(.required, for: .horizontal)
    stackCornerButton.setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  private func updateActionRailVisibility() {
    actionRail.isHidden = !isSelected
    headerBadgeView?.isHidden = false
    headerPinView?.isHidden = isSelected
    footerDetailLabel.isHidden = false
    stackCornerButton.isHidden = !(itemIsStacked || isSelected || isHovered || isKeyboardFocused)
    stackCornerButton.alphaValue = itemIsStacked ? 1.0 : 0.94
    for button in actionRailButtons {
      button.alphaValue = 1.0
    }
  }

  @objc private func pasteFromMenu() {
    onPaste(index)
  }

  @objc private func copyFromMenu() {
    onCopy(index)
  }

  @objc private func pastePlainTextFromMenu() {
    onPastePlainText(index)
  }

  @objc private func copyPlainTextFromMenu() {
    onCopyPlainText(index)
  }

  @objc private func showMoreActionsFromActionRail(_ sender: NSButton) {
    contextMenu().popUp(
      positioning: nil,
      at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 4),
      in: sender
    )
  }

  @objc private func toggleStackFromMenu() {
    onToggleStack(index)
  }

  @objc private func toggleStackFromCornerButton() {
    onSelect(index)
    onToggleStack(index)
  }

  @objc private func pasteStackNextFromMenu() {
    onPasteStackNext()
  }

  @objc private func copyStackNextFromMenu() {
    onCopyStackNext()
  }

  @objc private func clearStackFromMenu() {
    onClearStack()
  }

  @objc private func showInClipboardFromMenu() {
    onShowInClipboard(index)
  }

  @objc private func renameFromMenu() {
    onRename(index)
  }

  @objc private func editTextFromMenu() {
    onEditText(index)
  }

  @objc private func previewFromMenu() {
    onPreview(index)
  }

  @objc private func openFromMenu() {
    onOpen(index)
  }

  @objc private func revealFromMenu() {
    onReveal(index)
  }

  @objc private func togglePinFromMenu() {
    onTogglePin(index)
  }

  @objc private func showCollectionMenuFromAction(_ sender: NSButton) {
    let menu = collectionAssignmentMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
  }

  @objc private func assignToCollectionFromMenu(_ sender: NSMenuItem) {
    guard let name = sender.representedObject as? String else { return }
    onAssignCollection(index, name)
  }

  @objc private func createCollectionFromMenu() {
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    input.placeholderString = "Collection name"
    input.stringValue = ""

    let alert = NSAlert()
    alert.messageText = "New Collection"
    alert.informativeText = "Name this collection and add the selected clip to it."
    alert.accessoryView = input
    alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = input

    guard alert.runModal() == .alertFirstButtonReturn,
          let name = ClipboardCollectionDefaults.normalizedName(input.stringValue) else {
      return
    }
    onAssignCollection(index, name)
  }

  @objc private func removeFromCollectionFromMenu() {
    onAssignCollection(index, nil)
  }

  @objc private func ignoreSourceAppFromMenu() {
    onIgnoreSourceApp(index)
  }

  @objc private func ignoreKindFromMenu() {
    onIgnoreKind(index)
  }

  @objc private func deleteFromMenu() {
    onDelete(index)
  }

  private func configure(item: ClipboardItem, thumbnail: NSImage?) {
    #if DEBUG
    debugPreviewSummary = "\(titleText(for: item))|\(previewText(for: item))|\(detailMetricText(for: item))"
    debugPreviewStyle = previewStyle(for: item, thumbnail: thumbnail)
    debugHeaderBadgeSymbol = headerBadgeSymbol(for: item.kind)
    debugHeaderTitle = headerTitle(for: item)
    debugHeaderSubtitle = headerSubtitle(for: item)
    debugHeaderColorHex = Self.debugHex(headerColor(for: item))
    #endif

    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.masksToBounds = false
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.08
    layer?.shadowRadius = 12
    layer?.shadowOffset = NSSize(width: 0, height: 3)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(accessibilityTitle(for: item))
    setAccessibilityHelp(accessibilityHelpText())
    widthAnchor.constraint(equalToConstant: layout.width).isActive = true
    heightAnchor.constraint(equalToConstant: layout.height).isActive = true
    focusRingType = .default

    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = 8
    contentView.layer?.masksToBounds = true
    contentView.layer?.borderWidth = 1
    contentView.layer?.borderColor = Palette.border
    contentView.layer?.backgroundColor = Palette.cardSurface
    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)

    let header = headerView(for: item)
    let body = bodyView(for: item, thumbnail: thumbnail)
    let footer = footerView(for: item)

    let stack = NSStackView(views: [header, body, footer])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentView.topAnchor.constraint(equalTo: topAnchor),
      contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      body.widthAnchor.constraint(equalTo: stack.widthAnchor),
      footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
    ])
    configureStackCornerButton()
    contentView.addSubview(stackCornerButton)
    contentView.addSubview(actionRail)
    let actionRailTrailingConstraint: NSLayoutConstraint
    if let headerBadgeView {
      actionRailTrailingConstraint = actionRail.trailingAnchor.constraint(
        equalTo: headerBadgeView.leadingAnchor,
        constant: -Metrics.actionRailBadgeGap
      )
    } else {
      actionRailTrailingConstraint = actionRail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
    }
    NSLayoutConstraint.activate([
      stackCornerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      stackCornerButton.centerYAnchor.constraint(equalTo: footer.topAnchor),
      stackCornerButton.widthAnchor.constraint(equalToConstant: stackCornerButtonSize),
      stackCornerButton.heightAnchor.constraint(equalToConstant: stackCornerButtonSize),
      actionRailTrailingConstraint,
      actionRail.topAnchor.constraint(equalTo: contentView.topAnchor, constant: actionRailHeaderTopInset)
    ])
    setSelected(false)
  }

  private func headerView(for item: ClipboardItem) -> NSView {
    let header = NSView()
    header.wantsLayer = true
    header.layer?.backgroundColor = headerColor(for: item).cgColor
    header.heightAnchor.constraint(equalToConstant: layout.headerHeight).isActive = true

    let kind = NSTextField(labelWithString: headerTitle(for: item))
    kind.font = .systemFont(ofSize: layout.isCompact ? 15 : 16, weight: .bold)
    kind.textColor = .white
    kind.lineBreakMode = .byTruncatingTail
    kind.maximumNumberOfLines = 1
    kind.toolTip = kind.stringValue

    let source = NSTextField(labelWithString: headerSubtitle(for: item))
    source.font = .systemFont(ofSize: layout.isCompact ? 10 : 11, weight: .regular)
    source.textColor = NSColor.white.withAlphaComponent(0.72)
    source.lineBreakMode = .byTruncatingTail
    source.maximumNumberOfLines = 1
    source.toolTip = source.stringValue

    let titleAndSource = NSStackView(views: [kind, source])
    titleAndSource.orientation = .vertical
    titleAndSource.alignment = .leading
    titleAndSource.spacing = 2
    titleAndSource.translatesAutoresizingMaskIntoConstraints = false

    var labelViews: [NSView] = []
    if let quickPasteBadge = quickPasteBadge() {
      labelViews.append(quickPasteBadge)
    }
    labelViews.append(titleAndSource)
    let labelStack = NSStackView(views: labelViews)
    labelStack.orientation = .horizontal
    labelStack.alignment = .centerY
    labelStack.distribution = .fill
    labelStack.spacing = labelViews.count > 1 ? 9 : 1
    labelStack.translatesAutoresizingMaskIntoConstraints = false

    let badge = iconBadge(for: item)
    headerBadgeView = badge
    let separator = NSView()
    separator.wantsLayer = true
    separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    separator.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(labelStack)
    header.addSubview(badge)
    header.addSubview(separator)
    kind.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    kind.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    source.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    source.setContentHuggingPriority(.defaultLow, for: .horizontal)

    var constraints: [NSLayoutConstraint] = [
      labelStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: layout.inset),
      labelStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      labelStack.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),
      badge.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      badge.topAnchor.constraint(equalTo: header.topAnchor),
      badge.widthAnchor.constraint(equalToConstant: headerBadgeSize),
      badge.heightAnchor.constraint(equalToConstant: headerBadgeSize),
      separator.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: layout.inset),
      separator.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -layout.inset),
      separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
      separator.heightAnchor.constraint(equalToConstant: 1)
    ]

    if item.isPinned {
      let pin = headerIcon("pin.fill", color: NSColor.white.withAlphaComponent(0.88))
      headerPinView = pin
      pin.translatesAutoresizingMaskIntoConstraints = false
      header.addSubview(pin)
      constraints += [
        pin.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -8),
        pin.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        pin.widthAnchor.constraint(equalToConstant: 14),
        pin.heightAnchor.constraint(equalToConstant: 14)
      ]
    }

    NSLayoutConstraint.activate(constraints)
    return header
  }

  private func headerTitle(for item: ClipboardItem) -> String {
    activeCollectionName ?? kindLabel(for: item.kind)
  }

  private func headerSubtitle(for item: ClipboardItem) -> String {
    let relativeDate = Self.relativeDateText(for: item.createdAt)
    guard activeCollectionName != nil else { return relativeDate }
    return "\(kindLabel(for: item.kind)) - \(relativeDate)"
  }

  private func headerColor(for item: ClipboardItem) -> NSColor {
    activeCollectionColor ?? accentColor(for: item.kind)
  }

  private func quickPasteBadge() -> NSTextField? {
    guard index < 9 else { return nil }
    let label = NSTextField(labelWithString: "\(index + 1)")
    label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
    label.textColor = NSColor.white.withAlphaComponent(0.92)
    label.alignment = .center
    label.lineBreakMode = .byClipping
    label.wantsLayer = true
    label.layer?.cornerRadius = 9
    label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    label.layer?.borderWidth = 0.5
    label.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
    label.toolTip = "Press Command-\(index + 1) to paste"
    label.setAccessibilityLabel("Quick paste \(index + 1)")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(equalToConstant: 19).isActive = true
    label.heightAnchor.constraint(equalToConstant: 19).isActive = true
    quickPasteBadgeLabel = label
    return label
  }

  private func bodyView(for item: ClipboardItem, thumbnail: NSImage?) -> NSView {
    let body = NSView()
    body.wantsLayer = true
    body.layer?.backgroundColor = Palette.bodyBackground
    body.heightAnchor.constraint(equalToConstant: layout.bodyHeight).isActive = true

    let content = previewView(for: item, thumbnail: thumbnail)
    body.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
      content.topAnchor.constraint(equalTo: body.topAnchor),
      content.bottomAnchor.constraint(equalTo: body.bottomAnchor)
    ])
    return body
  }

  private func previewView(for item: ClipboardItem, thumbnail: NSImage?) -> NSView {
    if item.kind == .image, let thumbnail {
      return mediaPreviewView(for: item, thumbnail: thumbnail)
    }

    switch item.kind {
    case .url:
      if let thumbnail {
        return linkMediaPreviewView(for: item, thumbnail: thumbnail)
      }
      return linkPreviewView(for: item)
    case .file, .pdf:
      if let thumbnail {
        return mediaPreviewView(for: item, thumbnail: thumbnail)
      }
      return filePreviewView(for: item, thumbnail: thumbnail)
    case .audio:
      return audioPreviewView(for: item)
    case .text, .richText, .image, .unknown:
      return textPreviewView(for: item)
    }
  }

  private func textPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let titleString = titleText(for: item)
    let bodyString = previewBodyText(for: item, title: titleString)
    #if DEBUG
    debugTextPreviewTitle = titleString
    debugTextPreviewBody = bodyString ?? ""
    #endif
    let title = NSTextField(wrappingLabelWithString: titleString)
    title.font = bodyString == nil
      ? .systemFont(ofSize: item.kind == .richText ? 15 : 14, weight: .regular)
      : .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = bodyString == nil ? 5 : 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    var textViews: [NSView] = [title]
    if let bodyString {
      let detail = NSTextField(wrappingLabelWithString: bodyString)
      detail.font = .systemFont(ofSize: item.kind == .richText ? 15 : 14)
      detail.textColor = .secondaryLabelColor
      detail.maximumNumberOfLines = 5
      detail.lineBreakMode = .byTruncatingTail
      detail.toolTip = detail.stringValue
      textViews.append(detail)
    }

    let stack = NSStackView(views: textViews)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = bodyString == nil ? 0 : 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    for view in textViews {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14)
    ])
    return container
  }

  private func linkPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let hero = NSView()
    hero.wantsLayer = true
    hero.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.12).cgColor
    hero.translatesAutoresizingMaskIntoConstraints = false
    hero.heightAnchor.constraint(equalToConstant: 82).isActive = true

    let globe = headerIcon("globe", color: accentColor(for: item.kind))
    globe.translatesAutoresizingMaskIntoConstraints = false
    let host = NSTextField(labelWithString: webHostText(from: item.payload) ?? "Link")
    host.font = .systemFont(ofSize: 12, weight: .semibold)
    host.textColor = accentColor(for: item.kind)
    host.alignment = .center
    host.lineBreakMode = .byTruncatingTail
    host.maximumNumberOfLines = 1
    host.toolTip = host.stringValue

    let heroStack = NSStackView(views: [globe, host])
    heroStack.orientation = .vertical
    heroStack.alignment = .centerX
    heroStack.spacing = 7
    heroStack.translatesAutoresizingMaskIntoConstraints = false
    hero.addSubview(heroStack)

    let title = NSTextField(wrappingLabelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 2
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let address = NSTextField(labelWithString: previewText(for: item))
    address.font = .systemFont(ofSize: 12)
    address.textColor = .secondaryLabelColor
    address.maximumNumberOfLines = 1
    address.lineBreakMode = .byTruncatingMiddle
    address.toolTip = address.stringValue

    let textStack = NSStackView(views: [title, address])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 3
    textStack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(hero)
    container.addSubview(textStack)
    NSLayoutConstraint.activate([
      hero.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hero.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      hero.topAnchor.constraint(equalTo: container.topAnchor),
      heroStack.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
      heroStack.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
      globe.widthAnchor.constraint(equalToConstant: 28),
      globe.heightAnchor.constraint(equalToConstant: 28),
      host.widthAnchor.constraint(lessThanOrEqualTo: hero.widthAnchor, constant: -48),
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      textStack.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 11),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
      title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      address.widthAnchor.constraint(equalTo: textStack.widthAnchor)
    ])
    return container
  }

  private func linkMediaPreviewView(for item: ClipboardItem, thumbnail: NSImage) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let imageView = AspectFillImageView(image: thumbnail)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.heightAnchor.constraint(equalToConstant: 90).isActive = true

    let hostPill = capsuleLabel(webHostText(from: item.payload) ?? "Link", color: NSColor.black.withAlphaComponent(0.56))
    hostPill.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(wrappingLabelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let address = NSTextField(labelWithString: previewText(for: item))
    address.font = .systemFont(ofSize: 12)
    address.textColor = .secondaryLabelColor
    address.maximumNumberOfLines = 1
    address.lineBreakMode = .byTruncatingMiddle
    address.toolTip = address.stringValue

    let textStack = NSStackView(views: [title, address])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 3
    textStack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(imageView)
    container.addSubview(hostPill)
    container.addSubview(textStack)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: container.topAnchor),
      hostPill.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
      hostPill.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -10),
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      textStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
      title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      address.widthAnchor.constraint(equalTo: textStack.widthAnchor)
    ])
    return container
  }

  private func filePreviewView(for item: ClipboardItem, thumbnail: NSImage?) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let iconBox = NSView()
    iconBox.wantsLayer = true
    iconBox.layer?.cornerRadius = 12
    iconBox.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.14).cgColor
    iconBox.translatesAutoresizingMaskIntoConstraints = false

    let extensionPill = capsuleLabel(detailMetricText(for: item), color: accentColor(for: item.kind))
    extensionPill.translatesAutoresizingMaskIntoConstraints = false
    let preview: NSView
    if let thumbnail {
      let imageView = NSImageView(image: thumbnail)
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.wantsLayer = true
      imageView.layer?.cornerRadius = 8
      imageView.layer?.masksToBounds = true
      imageView.translatesAutoresizingMaskIntoConstraints = false
      preview = imageView
    } else {
      let iconName = item.kind == .pdf ? "doc.richtext.fill" : "doc.fill"
      let icon = headerIcon(iconName, color: accentColor(for: item.kind))
      icon.translatesAutoresizingMaskIntoConstraints = false
      preview = icon
    }
    iconBox.addSubview(preview)
    iconBox.addSubview(extensionPill)

    let title = NSTextField(wrappingLabelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 2
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let location = NSTextField(wrappingLabelWithString: previewText(for: item))
    location.font = .systemFont(ofSize: 12)
    location.textColor = .secondaryLabelColor
    location.maximumNumberOfLines = 2
    location.lineBreakMode = .byTruncatingMiddle
    location.toolTip = location.stringValue

    let textStack = NSStackView(views: [title, location])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 5
    textStack.translatesAutoresizingMaskIntoConstraints = false

    let row = NSStackView(views: [iconBox, textStack])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14
    row.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(row)

    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      iconBox.widthAnchor.constraint(equalToConstant: thumbnail == nil ? 72 : 96),
      iconBox.heightAnchor.constraint(equalToConstant: thumbnail == nil ? 84 : 104),
      preview.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
      preview.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor, constant: thumbnail == nil ? -6 : -8),
      preview.widthAnchor.constraint(lessThanOrEqualToConstant: thumbnail == nil ? 32 : 80),
      preview.heightAnchor.constraint(lessThanOrEqualToConstant: thumbnail == nil ? 36 : 72),
      extensionPill.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
      extensionPill.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor, constant: -10),
      title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      location.widthAnchor.constraint(equalTo: textStack.widthAnchor)
    ])
    return container
  }

  private func audioPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.10).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let note = headerIcon("music.note", color: accentColor(for: item.kind))
    note.translatesAutoresizingMaskIntoConstraints = false

    let waveform = NSStackView()
    waveform.orientation = .horizontal
    waveform.alignment = .centerY
    waveform.spacing = 5
    waveform.translatesAutoresizingMaskIntoConstraints = false
    for height in [12, 22, 16, 30, 22, 26, 14] as [CGFloat] {
      let bar = NSView()
      bar.wantsLayer = true
      bar.layer?.cornerRadius = 2.5
      bar.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.55).cgColor
      bar.translatesAutoresizingMaskIntoConstraints = false
      bar.widthAnchor.constraint(equalToConstant: 5).isActive = true
      bar.heightAnchor.constraint(equalToConstant: height).isActive = true
      waveform.addArrangedSubview(bar)
    }

    let title = NSTextField(labelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let detail = NSTextField(labelWithString: previewText(for: item))
    detail.font = .systemFont(ofSize: 12)
    detail.textColor = .secondaryLabelColor
    detail.maximumNumberOfLines = 1
    detail.lineBreakMode = .byTruncatingTail
    detail.toolTip = detail.stringValue

    let labels = NSStackView(views: [title, detail])
    labels.orientation = .vertical
    labels.alignment = .centerX
    labels.spacing = 3
    labels.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(note)
    container.addSubview(waveform)
    container.addSubview(labels)
    NSLayoutConstraint.activate([
      note.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      note.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
      note.widthAnchor.constraint(equalToConstant: 28),
      note.heightAnchor.constraint(equalToConstant: 28),
      waveform.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      waveform.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 8),
      labels.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      labels.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      labels.topAnchor.constraint(equalTo: waveform.bottomAnchor, constant: 10),
      title.widthAnchor.constraint(equalTo: labels.widthAnchor),
      detail.widthAnchor.constraint(equalTo: labels.widthAnchor)
    ])
    return container
  }

  private func mediaPreviewView(for item: ClipboardItem, thumbnail: NSImage) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let imageView = AspectFillImageView(image: thumbnail)
    imageView.translatesAutoresizingMaskIntoConstraints = false

    let overlay = capsuleLabel(mediaMetricText(for: thumbnail), color: NSColor.black.withAlphaComponent(0.60))
    overlay.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(imageView)
    container.addSubview(overlay)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: container.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
      overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
    ])
    return container
  }

  private func capsuleLabel(_ text: String, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    label.textColor = .white
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.wantsLayer = true
    label.layer?.cornerRadius = 8
    label.layer?.backgroundColor = color.cgColor
    label.toolTip = text
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
    label.heightAnchor.constraint(equalToConstant: 18).isActive = true
    return label
  }

  private func previewBodyText(for item: ClipboardItem, title: String) -> String? {
    let preview = previewText(for: item)
    let normalizedTitle = normalized(title)
    if preview == normalizedTitle {
      return nil
    }

    let prefix = normalizedTitle + " "
    if preview.hasPrefix(prefix) {
      let remainder = String(preview.dropFirst(prefix.count)).clipboardTrimmed
      if !remainder.isEmpty {
        return remainder
      }
      return nil
    }

    return preview
  }

  private func mediaMetricText(for image: NSImage) -> String {
    let width = max(1, Int(image.size.width.rounded()))
    let height = max(1, Int(image.size.height.rounded()))
    return "\(width) x \(height)"
  }

  private func previewStyle(for item: ClipboardItem, thumbnail: NSImage?) -> String {
    if item.kind == .image, thumbnail != nil {
      return "media-preview"
    }

    switch item.kind {
    case .url:
      return thumbnail == nil ? "link-preview" : "link-media-preview"
    case .file, .pdf:
      return thumbnail == nil ? "file-preview" : "file-media-preview"
    case .audio:
      return "audio-preview"
    case .richText:
      return "rich-text-preview"
    case .text:
      return "text-preview"
    case .image:
      return "text-fallback-preview"
    case .unknown:
      return "unknown-preview"
    }
  }

  private func footerView(for item: ClipboardItem) -> NSView {
    let footer = NSView()
    footer.wantsLayer = true
    footer.layer?.backgroundColor = Palette.footerBackground
    footer.heightAnchor.constraint(equalToConstant: layout.footerHeight).isActive = true

    let sourceText = footerSourceText(for: item)
    footerSourceLabel.stringValue = sourceText ?? ""
    footerSourceLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    footerSourceLabel.textColor = .secondaryLabelColor
    footerSourceLabel.lineBreakMode = .byTruncatingTail
    footerSourceLabel.maximumNumberOfLines = 1
    footerSourceLabel.toolTip = footerSourceLabel.stringValue
    footerSourceLabel.isHidden = sourceText == nil

    let detailText = detailMetricText(for: item)
    if activeCollectionName == nil,
       let collectionName = item.collectionName?.clipboardTrimmed,
       !collectionName.isEmpty {
      footerDetailLabel.stringValue = "\(collectionName) - \(detailText)"
    } else {
      footerDetailLabel.stringValue = detailText
    }
    footerDetailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    footerDetailLabel.textColor = .tertiaryLabelColor
    footerDetailLabel.alignment = .right
    footerDetailLabel.lineBreakMode = .byTruncatingTail
    footerDetailLabel.maximumNumberOfLines = 1
    footerDetailLabel.toolTip = footerDetailLabel.stringValue

    configureActionRail()

    let divider = NSView()
    divider.wantsLayer = true
    divider.layer?.backgroundColor = Palette.divider
    divider.translatesAutoresizingMaskIntoConstraints = false
    let stack = row([footerSourceLabel, footerDetailLabel])
    stack.distribution = .fill
    stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints = false
    footerSourceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    footerSourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    footerDetailLabel.setContentHuggingPriority(.required, for: .horizontal)
    footerDetailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    footer.addSubview(divider)
    footer.addSubview(stack)
    NSLayoutConstraint.activate([
      divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: layout.inset),
      divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -layout.inset),
      divider.topAnchor.constraint(equalTo: footer.topAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1),
      stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: layout.inset),
      stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -layout.inset),
      stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
    ])
    return footer
  }

  private func dragPreviewImage() -> NSImage {
    guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
      return NSImage(size: bounds.size)
    }
    representation.size = bounds.size
    cacheDisplay(in: bounds, to: representation)

    let image = NSImage(size: bounds.size)
    image.addRepresentation(representation)
    return image
  }

  private func iconBadge(for item: ClipboardItem) -> NSView {
    let badge = NSView()
    badge.wantsLayer = true
    badge.layer?.cornerRadius = 8
    badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
    badge.layer?.borderWidth = 1
    badge.layer?.borderColor = Palette.divider
    badge.translatesAutoresizingMaskIntoConstraints = false
    if let bundleId = item.sourceAppBundleId,
       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
      let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: appURL.path))
      icon.imageScaling = .scaleProportionallyUpOrDown
      icon.translatesAutoresizingMaskIntoConstraints = false
      badge.addSubview(icon)
      NSLayoutConstraint.activate([
        icon.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
        icon.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
        icon.topAnchor.constraint(equalTo: badge.topAnchor, constant: 8),
        icon.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -8)
      ])
    } else {
      let image = NSImage(systemSymbolName: headerBadgeSymbol(for: item.kind), accessibilityDescription: kindLabel(for: item.kind))
        ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: kindLabel(for: item.kind))
        ?? NSImage()
      image.isTemplate = true
      let icon = NSImageView(image: image)
      icon.imageScaling = .scaleProportionallyUpOrDown
      icon.contentTintColor = accentColor(for: item.kind)
      icon.translatesAutoresizingMaskIntoConstraints = false
      badge.addSubview(icon)
      NSLayoutConstraint.activate([
        icon.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 9),
        icon.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -9),
        icon.topAnchor.constraint(equalTo: badge.topAnchor, constant: 9),
        icon.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -9)
      ])
    }
    return badge
  }

  private func separatorLine() -> NSView {
    let divider = NSView()
    divider.wantsLayer = true
    divider.translatesAutoresizingMaskIntoConstraints = false
    divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
    return divider
  }

  private func headerIcon(_ name: String, color: NSColor) -> NSView {
    let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
    view.imageScaling = .scaleProportionallyUpOrDown
    view.contentTintColor = color
    return view
  }

  private func titleText(for item: ClipboardItem) -> String {
    if let customTitle = item.customTitle?.clipboardTrimmed, !customTitle.isEmpty {
      return customTitle
    }

    switch item.kind {
    case .url:
      return linkTitle(for: item)
    case .file:
      return fileTitle(for: item, fallback: "File")
    case .pdf:
      return fileTitle(for: item, fallback: "PDF document")
    case .audio:
      return audioTitle(for: item)
    case .image:
      return imageTitle(for: item)
    default:
      break
    }

    let candidate = firstUsefulLine(item.displayText).isEmpty ? firstUsefulLine(item.payload) : firstUsefulLine(item.displayText)
    if candidate.isEmpty || looksInternal(candidate) {
      return "Copied \(kindLabel(for: item.kind).lowercased())"
    }
    return candidate
  }

  private func previewText(for item: ClipboardItem) -> String {
    switch item.kind {
    case .url:
      if let address = webAddressText(from: item.payload) {
        return address
      }
      let text = normalized(item.payload)
      return text.isEmpty ? "No preview available" : text
    case .file:
      return fileLocationText(from: item.payload, fallback: "Local file")
    case .pdf:
      if let ocrText = item.ocrText?.clipboardTrimmed, !ocrText.isEmpty {
        return normalized(ocrText)
      }
      return fileLocationText(from: item.payload, fallback: "PDF document")
    case .audio:
      return "Sound clip"
    case .richText:
      let text = normalized(item.displayText)
      return text.isEmpty ? "No preview available" : text
    case .image:
      if let ocrText = item.ocrText?.clipboardTrimmed, !ocrText.isEmpty {
        return normalized(ocrText)
      }
      return "Image clip"
    default:
      let text = item.payload.clipboardTrimmed.isEmpty ? item.displayText : item.payload
      let normalizedText = normalized(text)
      return normalizedText.isEmpty ? "No preview available" : normalizedText
    }
  }

  private func detailMetricText(for item: ClipboardItem) -> String {
    switch item.kind {
    case .text:
      let count = item.payload.count
      return "\(count) \(count == 1 ? "character" : "characters")"
    case .richText:
      let count = item.displayText.count
      return "\(count) \(count == 1 ? "character" : "characters")"
    case .url:
      return webHostText(from: item.payload) ?? "Link"
    case .file:
      return fileKindText(from: item.payload, fallback: "File")
    case .pdf:
      return "PDF"
    case .audio:
      return "Audio"
    case .image:
      if item.ocrText?.clipboardTrimmed.isEmpty == false {
        return "OCR text"
      }
      let path = item.imagePath?.clipboardTrimmed.isEmpty == false ? item.imagePath! : item.payload
      return fileKindText(from: path, fallback: "Image")
    case .unknown:
      return metadataText(for: item)
    }
  }

  private func footerSourceText(for item: ClipboardItem) -> String? {
    let source = item.sourceApp?.clipboardTrimmed
    let usage = usageText(for: item.useCount)
    if let source, !source.isEmpty, let usage {
      return "\(source) - \(usage)"
    }
    if let source, !source.isEmpty {
      return source
    }
    return usage
  }

  private func usageText(for useCount: Int) -> String? {
    guard useCount > 0 else { return nil }
    return useCount == 1 ? "Used once" : "Used \(useCount) times"
  }

  private func linkTitle(for item: ClipboardItem) -> String {
    let display = firstUsefulLine(item.displayText)
    let payload = firstUsefulLine(item.payload)
    if !display.isEmpty,
       display != payload,
       !looksInternal(display),
       !looksGenericLink(display),
       !looksLikeWebAddress(display) {
      return display
    }
    return webHostText(from: item.payload) ?? "Link"
  }

  private func fileTitle(for item: ClipboardItem, fallback: String) -> String {
    let paths = FilePayload.paths(from: item.payload)
    if item.kind == .file, paths.count > 1 {
      return "\(paths.count) files"
    }

    if let name = fileName(from: item.payload), !name.isEmpty, !looksInternal(name) {
      return name
    }

    let display = firstUsefulLine(item.displayText)
    if !display.isEmpty, !looksInternal(display), !looksGenericFileTitle(display) {
      return display
    }

    return fallback
  }

  private func imageTitle(for item: ClipboardItem) -> String {
    let display = firstUsefulLine(item.displayText)
    if !display.isEmpty, !looksInternal(display), display.lowercased() != "image" {
      return display
    }

    let ocr = firstUsefulLine(item.ocrText ?? "")
    if !ocr.isEmpty, !looksInternal(ocr) {
      return ocr
    }

    return "Image"
  }

  private func audioTitle(for item: ClipboardItem) -> String {
    let display = firstUsefulLine(item.displayText)
    if !display.isEmpty, !looksInternal(display), display.lowercased() != "audio" {
      return display
    }
    return "Audio"
  }

  private func webComponents(from value: String) -> URLComponents? {
    let trimmed = value.clipboardTrimmed
    guard !trimmed.isEmpty else { return nil }
    if let components = URLComponents(string: trimmed), components.host?.isEmpty == false {
      return components
    }
    if !trimmed.contains("://"),
       let components = URLComponents(string: "https://\(trimmed)"),
       components.host?.isEmpty == false {
      return components
    }
    return nil
  }

  private func webHostText(from value: String) -> String? {
    guard let host = webComponents(from: value)?.host?.clipboardTrimmed, !host.isEmpty else { return nil }
    return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  private func webAddressText(from value: String) -> String? {
    guard let components = webComponents(from: value),
          let host = webHostText(from: value) else {
      return nil
    }

    var address = host
    let path = components.path.clipboardTrimmed
    if !path.isEmpty, path != "/" {
      address += path
    }
    return address
  }

  private func fileURL(from value: String) -> URL? {
    FilePayload.urls(from: value).first
  }

  private func fileName(from value: String) -> String? {
    guard let url = fileURL(from: value) else { return nil }
    let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    return name.clipboardTrimmed.isEmpty ? nil : name
  }

  private func fileLocationText(from value: String, fallback: String) -> String {
    let urls = FilePayload.urls(from: value)
    guard let url = urls.first else { return fallback }
    if urls.count > 1 {
      let parents = Set(urls.map { $0.deletingLastPathComponent().path }.filter { !$0.isEmpty })
      if parents.count == 1, let parent = parents.first {
        return shortenedPath(parent)
      }
      return "Multiple locations"
    }
    let parentPath = url.deletingLastPathComponent().path
    if parentPath.isEmpty {
      return fallback
    }
    return shortenedPath(parentPath)
  }

  private func fileKindText(from value: String, fallback: String) -> String {
    let paths = FilePayload.paths(from: value)
    if paths.count > 1 {
      return "\(paths.count) files"
    }
    guard let fileExtension = fileURL(from: value)?.pathExtension.clipboardTrimmed,
          !fileExtension.isEmpty else {
      return fallback
    }
    return fileExtension.uppercased()
  }

  private func shortenedPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home {
      return "~"
    }
    if path.hasPrefix(home + "/") {
      return "~" + String(path.dropFirst(home.count))
    }
    return path
  }

  private func accentColor(for kind: ClipboardItemKind) -> NSColor {
    switch kind {
    case .url:
      return NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.98, alpha: 1)
    case .text:
      return NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1)
    case .image:
      return NSColor(calibratedRed: 1.00, green: 0.22, blue: 0.25, alpha: 1)
    case .richText:
      return NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.48, alpha: 1)
    case .file:
      return NSColor(calibratedRed: 0.11, green: 0.68, blue: 0.36, alpha: 1)
    case .pdf:
      return NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.88, alpha: 1)
    case .audio:
      return NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1)
    case .unknown:
      return .systemGray
    }
  }

  private func headerBadgeSymbol(for kind: ClipboardItemKind) -> String {
    switch kind {
    case .url: return "link"
    case .text: return "text.alignleft"
    case .image: return "photo"
    case .richText: return "doc.richtext"
    case .file: return "doc"
    case .pdf: return "doc.text.fill"
    case .audio: return "music.note"
    case .unknown: return "questionmark"
    }
  }

  private func metadataText(for item: ClipboardItem) -> String {
    let time = Self.relativeDateText(for: item.createdAt)
    guard item.useCount > 0 else { return time }
    return "\(time) - Used \(item.useCount)"
  }

  private func firstUsefulLine(_ value: String) -> String {
    for line in value.components(separatedBy: .newlines) {
      let text = normalized(line)
      if !text.isEmpty {
        return text
      }
    }
    return ""
  }

  private func normalized(_ value: String) -> String {
    value.split { $0.isWhitespace }.joined(separator: " ")
  }

  private func looksInternal(_ value: String) -> Bool {
    let lower = value.lowercased()
    return lower.hasPrefix("clipbored-flow-test-") || lower.hasPrefix("internal copy ")
  }

  private func looksGenericLink(_ value: String) -> Bool {
    let lower = value.lowercased()
    return lower == "link" || lower == "url"
  }

  private func looksGenericFileTitle(_ value: String) -> Bool {
    let lower = value.lowercased()
    return lower == "file" || lower == "pdf" || lower == "image"
  }

  private func looksLikeWebAddress(_ value: String) -> Bool {
    let lower = value.lowercased()
    return lower.contains("://") || lower.hasPrefix("www.")
  }

  private func accessibilityTitle(for item: ClipboardItem) -> String {
    let summary = titleText(for: item)
    return "\(kindLabel(for: item.kind)): \(summary)"
  }

  private func accessibilityHelpText() -> String {
    "Press Return to paste. Press Space for Quick Look."
  }

  private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .top
    stack.spacing = 6
    return stack
  }

  private func kindLabel(for kind: ClipboardItemKind) -> String {
    switch kind {
    case .image: return "Image"
    case .url: return "Link"
    case .text: return "Text"
    case .richText: return "Rich Text"
    case .file: return "File"
    case .unknown: return "Unknown"
    case .pdf: return "PDF"
    case .audio: return "Audio"
    }
  }

  private static func relativeDateText(for date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "Just now" }
    if seconds < 3600 {
      let minutes = seconds / 60
      return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
    }
    if seconds < 86400 {
      let hours = seconds / 3600
      return "\(hours) \(hours == 1 ? "hour" : "hours") ago"
    }
    if seconds < 604800 {
      let days = seconds / 86400
      return "\(days) \(days == 1 ? "day" : "days") ago"
    }
    let weeks = seconds / 604800
    return "\(weeks) \(weeks == 1 ? "week" : "weeks") ago"
  }
}
