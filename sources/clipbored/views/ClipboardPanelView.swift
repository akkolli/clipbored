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
  let activeLift: CGFloat

  static let regular = ClipboardItemCardLayout(
    width: 320,
    height: 244,
    inset: 16,
    headerHeight: 56,
    bodyHeight: 152,
    footerHeight: 36,
    actionButtonSize: 24,
    primaryActionButtonSize: 30,
    actionRailHeight: 34,
    activeLift: 0
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
    actionRailHeight: 32,
    activeLift: 0
  )

  static let expanded = ClipboardItemCardLayout(
    width: 380,
    height: 320,
    inset: 18,
    headerHeight: 58,
    bodyHeight: 218,
    footerHeight: 44,
    actionButtonSize: 26,
    primaryActionButtonSize: 32,
    actionRailHeight: 36,
    activeLift: 0
  )

  var isCompact: Bool {
    height == Self.compact.height
      && inset == Self.compact.inset
      && headerHeight == Self.compact.headerHeight
      && bodyHeight == Self.compact.bodyHeight
      && footerHeight == Self.compact.footerHeight
  }

  func withWidth(_ width: CGFloat) -> ClipboardItemCardLayout {
    ClipboardItemCardLayout(
      width: width,
      height: height,
      inset: inset,
      headerHeight: headerHeight,
      bodyHeight: bodyHeight,
      footerHeight: footerHeight,
      actionButtonSize: actionButtonSize,
      primaryActionButtonSize: primaryActionButtonSize,
      actionRailHeight: actionRailHeight,
      activeLift: activeLift
    )
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
    case .colors: return NSColor(calibratedRed: 0.00, green: 0.65, blue: 0.74, alpha: 1)
    case .audio: return NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1)
    case .files: return NSColor(calibratedRed: 0.11, green: 0.68, blue: 0.36, alpha: 1)
    case .pinned: return NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.48, alpha: 1)
    case .code: return NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.78, alpha: 1)
    case .videos: return NSColor(calibratedRed: 0.43, green: 0.32, blue: 0.94, alpha: 1)
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

private struct ClipboardItemCardReuseFingerprint: Equatable {
  let id: UUID
  let kind: ClipboardItemKind
  let displayText: String
  let payload: String
  let payloadHash: String
  let createdAt: Date
  let lastUsedAt: Date
  let useCount: Int
  let sourceApp: String?
  let imagePath: String?
  let thumbnailPath: String?
  let isPinned: Bool
  let sourceAppBundleID: String?
  let ocrText: String?
  let collectionName: String?
  let customTitle: String?
  let sourceDeviceName: String?
  let layout: ClipboardItemCardLayout
  let collectionNames: [String]
  let canShowInClipboard: Bool
  let activeCollectionName: String?
  let activeCollectionColorHex: String?
  let quickPasteNumber: Int?
}

#if DEBUG
private struct ClipboardSearchFilterPart {
  let raw: String
  let canonical: String
  let canonicalKey: String?
  let keyValueCanonical: String?
  let isExact: Bool
}
#endif

private final class ClipboardPanelSearchField: NSSearchField {
  var onFocusStateChanged: (() -> Void)?
  private(set) var hasKeyboardFocusForPresentation = false

  override func becomeFirstResponder() -> Bool {
    let becameFirstResponder = super.becomeFirstResponder()
    if becameFirstResponder {
      setKeyboardFocusForPresentation(true)
    }
    return becameFirstResponder
  }

  override func resignFirstResponder() -> Bool {
    let resignedFirstResponder = super.resignFirstResponder()
    if resignedFirstResponder {
      setKeyboardFocusForPresentation(false)
    }
    return resignedFirstResponder
  }

  func setKeyboardFocusForPresentation(_ focused: Bool) {
    guard hasKeyboardFocusForPresentation != focused else {
      onFocusStateChanged?()
      return
    }
    hasKeyboardFocusForPresentation = focused
    onFocusStateChanged?()
  }
}

private enum ClipboardCardPresentation: Equatable {
  case expanded
  case horizontalIcon
  case horizontalFocus
  case verticalRow
  case verticalFocus

  var isExpanded: Bool {
    self == .expanded || self == .verticalFocus
  }

  var showsFloatingActions: Bool {
    self == .expanded
  }

  func size(for layout: ClipboardItemCardLayout) -> NSSize {
    switch self {
    case .expanded:
      return NSSize(width: layout.width, height: layout.height + layout.activeLift)
    case .horizontalIcon:
      let side: CGFloat = layout.isCompact ? 56 : 64
      return NSSize(width: side, height: side)
    case .horizontalFocus:
      let width: CGFloat = layout.isCompact ? 224 : 252
      let height: CGFloat = layout.isCompact ? 56 : 64
      return NSSize(width: width, height: height)
    case .verticalRow:
      let height: CGFloat = layout.isCompact ? 56 : 64
      return NSSize(width: layout.width, height: height)
    case .verticalFocus:
      return NSSize(width: layout.width, height: layout.height + layout.activeLift)
    }
  }
}

final class ClipboardPanelView: NSVisualEffectView, NSSearchFieldDelegate {
  private enum Metrics {
    static let actionButtonSize: CGFloat = 28
    static let searchControlSize: CGFloat = 30
    static let panelTopInset: CGFloat = 6
    static let panelSideInset: CGFloat = 12
    static let actionBarHorizontalPadding: CGFloat = 10
    static let panelStatusBarHeight: CGFloat = 24
    static let minimumBottomInset: CGFloat = 20
    static let panelCornerRadius: CGFloat = 22
    static let compactCardThreshold: CGFloat = 760
    static let emptyStateMinimumWidth: CGFloat = 760
    static let collectionRailHeight: CGFloat = 32
    static let collectionRailMaximumWidth: CGFloat = 760
    static let verticalCollectionRailMaximumWidth: CGFloat = 260
    static let collectionSideRailWidth: CGFloat = 36
    static let collectionSideRailItemSize: CGFloat = 34
    static let collectionSideRailGap: CGFloat = 4
    static let collectionRailCardClearance: CGFloat = 8
    static let minimumVerticalCardWidth: CGFloat = 180
    static let expandedSearchWidth: CGFloat = 300
    static let verticalExpandedSearchWidth: CGFloat = 164
    static let expandedCardHeightThreshold: CGFloat = 560
    static let expandedCardWidthThreshold: CGFloat = 980
  }

  fileprivate enum Motion {
    static let contentSwitchDuration: TimeInterval = 0.16
    static let contentSwitchStartAlpha: CGFloat = 0.68
    static let searchFieldResizeDuration: TimeInterval = 0.14
    static let cardLiftDuration: TimeInterval = 0.16
    static let cardExpansionDuration: TimeInterval = 0.36
    static let actionRailDuration: TimeInterval = 0.14

    static var cardExpansionTiming: CAMediaTimingFunction {
      CAMediaTimingFunction(controlPoints: 0.25, 0.10, 0.25, 1.00)
    }
  }

  private enum CardSelectionInputSource {
    case keyboard
    case mouse
  }

  private enum CategoryHoverTarget: Equatable {
    case sortMode(ClipboardSortMode)
    case collection(String)
    case stack
  }

  private enum CardDensity: String {
    case regular
    case compact
    case expanded

    static func fitting(
      width: CGFloat,
      height: CGFloat,
      compactModeEnabled: Bool,
      panelLayout: ClipboardPanelLayout
    ) -> CardDensity {
      if panelLayout == .vertical {
        return .compact
      }
      if compactModeEnabled || (width > 0 && width < Metrics.compactCardThreshold) || (height > 0 && height < 390) {
        return .compact
      }
      if width >= Metrics.expandedCardWidthThreshold && height >= Metrics.expandedCardHeightThreshold {
        return .expanded
      }
      return .regular
    }

    var layout: ClipboardItemCardLayout {
      switch self {
      case .regular: return .regular
      case .compact: return .compact
      case .expanded: return .expanded
      }
    }

    var cardSpacing: CGFloat {
      switch self {
      case .regular: return 16
      case .compact: return 12
      case .expanded: return 18
      }
    }

    var cardStackInset: CGFloat {
      switch self {
      case .regular: return 10
      case .compact: return 8
      case .expanded: return 12
      }
    }

    var cardTopInset: CGFloat {
      cardStackInset
    }

    var cardBottomInset: CGFloat {
      cardStackInset
    }

    var railHeight: CGFloat {
      let itemHeight: CGFloat
      switch self {
      case .compact:
        itemHeight = ClipboardCardPresentation.horizontalFocus.size(for: layout).height
      case .regular:
        itemHeight = ClipboardCardPresentation.horizontalFocus.size(for: layout).height
      case .expanded:
        itemHeight = ClipboardCardPresentation.expanded.size(for: layout).height
      }
      return itemHeight + cardTopInset + cardBottomInset + 2
    }

    var emptyStateMinimumWidth: CGFloat {
      switch self {
      case .regular: return Metrics.emptyStateMinimumWidth
      case .compact: return 420
      case .expanded: return Metrics.emptyStateMinimumWidth
      }
    }
  }

  private enum Palette {
    static let panelBorder = NSColor.white.withAlphaComponent(0.38).cgColor
    static let panelSurface = NSColor.windowBackgroundColor.withAlphaComponent(0.16).cgColor
    static let panelShadow = NSColor.black.withAlphaComponent(0.24).cgColor
  }

  private enum StatusTone: String {
    case ready
    case action
    case warning
    case error
    case neutral
  }

  private let viewModel: ClipboardPanelViewModel
  private let onClose: () -> Void
  private let onSettings: () -> Void
  private let onPreview: () -> Void

  private let searchField = ClipboardPanelSearchField()
  private let searchControlContainer = NSView()
  private let searchIconButton = NSButton()
  private weak var categoryMenuButton: NSButton?
  private weak var clearHistoryButton: NSButton?
  private weak var settingsButton: NSButton?
  private weak var utilityToolbarGroup: NSView?
  private let collectionScrollView = HorizontalRailScrollView(edgeFadeWidth: 44)
  private let collectionDocumentView = CollectionRailDocumentView()
  private let collectionStack = NSStackView()
  private let addCollectionButton = NSButton()
  private let stackChip = CollectionChipView(title: "Stack", color: .systemGreen, symbolName: "square.stack.3d.up.fill", iconOnly: true)
  private let itemsStack = ClipboardItemsDocumentView()
  private let scrollView = HorizontalRailScrollView()
  private let bottomSpacer = NSView()
  private var emptyStateText: (title: String, detail: String)?
  private var mainStack: NSStackView?
  private var bottomSafeInset = Metrics.minimumBottomInset
  private var currentStatusText = ""
  private var currentResultCountText = ""
  private var currentStatusTone: StatusTone = .ready
  private var currentPanelLayout: ClipboardPanelLayout = .vertical
  private var cardDensity: CardDensity = .regular
  private var scrollViewHeightConstraint: NSLayoutConstraint?
  private var searchFieldWidthConstraint: NSLayoutConstraint?
  private var collectionScrollWidthConstraint: NSLayoutConstraint?
  private var collectionRailLeadingConstraint: NSLayoutConstraint?
  private var shelfChromeHeightConstraint: NSLayoutConstraint?
  private var searchControlCenterYConstraint: NSLayoutConstraint?
  private var utilityToolbarCenterYConstraint: NSLayoutConstraint?
  private var collectionScrollCenterYConstraint: NSLayoutConstraint?
  private var collectionAvoidsSearchConstraint: NSLayoutConstraint?
  private var collectionAvoidsActionsConstraint: NSLayoutConstraint?
  private weak var shelfChromeView: NSView?
  private weak var headerStack: NSStackView?
  private weak var contentStack: NSView?
  private var cardViews: [ClipboardItemCardView] = []
  private var cardSlots: [Int: ClipboardItemCardSlotView] = [:]
  private var cardItemCount = 0
  private var configuredSortModes: [ClipboardSortMode] = []
  private var collectionButtons: [ClipboardSortMode: CollectionChipView] = [:]
  private var customCollectionButtons: [String: CollectionChipView] = [:]
  private var collectionChipOrder: [CollectionChipView] = []
  private var configuredCollectionNames: [String] = []
  private var lastScrollViewportSize: NSSize = .zero
  private var cardLayoutAnimationGeneration = 0
  private var resetCollectionScrollPositionOnNextLayout = false
  private var searchFieldPresentationIsExpanded = false
  private var searchFieldPresentationRequested = false
  private var searchFieldCollapsedWhileIdle = false
  private var selectionScrollSuppressionCount = 0
  private var hoveredCardIndex: Int?
  private var hoverSelectionRequiresFreshMouseMovement = false
  private var hoverSelectionKeyboardBarrierLocation: NSPoint?
  private var hoveredCategoryTarget: CategoryHoverTarget?
  private var categoryHoverOriginalSelection: ClipboardCategorySelectionSnapshot?
  private var categoryHoverGeneration = 0
  private var cardSelectionInputSource: CardSelectionInputSource = .mouse
  #if DEBUG
  private var animatedCardLayoutChangeCount = 0
  #endif
  private var defersVisualReloads = false
  private var pendingItemReload = false
  private var pendingCollectionReload = false
  private var cardReloadGeneration = 0
  private var lastSynchronousCardRenderCount = 0
  private weak var activeWritingToolsTextView: NSTextView?

  private struct FocusedCardReloadTarget {
    let itemID: UUID
    let fallbackIndex: Int
  }

  private struct CardRenderContext {
    let items: [ClipboardItem]
    let collectionNames: [String]
    let layout: ClipboardItemCardLayout
    let selectedCollectionName: String?
    let selectedCollectionColor: NSColor?
    let canShowInClipboard: Bool
    let reloadGeneration: Int
  }

  private let initialCardRenderBudget = 12
  private let cardRenderPrefetchBuffer = 3
  private let cardRenderRetentionBuffer = 8
  private var currentCardRenderContext: CardRenderContext?

  #if DEBUG
  private var collectionNameProviderForTesting: (() -> String?)?
  private var textClipProviderForTesting: (() -> String?)?
  private var suppressClipEditDialogsForTesting = false
  private var renameClipRequestCountForTesting = 0
  private var editClipRequestCountForTesting = 0
  private var suppressClipOpenActionsForTesting = false
  private var openClipRequestCountForTesting = 0
  private var showInClipboardRequestCountForTesting = 0
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
    material = .hudWindow
    blendingMode = .behindWindow
    state = .active
    isEmphasized = true
    wantsLayer = true
    layer?.cornerRadius = Metrics.panelCornerRadius
    layer?.masksToBounds = false
    layer?.backgroundColor = Palette.panelSurface
    layer?.borderWidth = 0.8
    layer?.borderColor = Palette.panelBorder
    layer?.shadowColor = Palette.panelShadow
    layer?.shadowOpacity = 0.28
    layer?.shadowRadius = 34
    layer?.shadowOffset = NSSize(width: 0, height: 14)

    configureSearchIconButton()
    searchField.setAccessibilityLabel("Search clipboard history")
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(searchFieldChanged)
    searchField.onFocusStateChanged = { [weak self] in
      self?.updateSearchFieldPresentation()
    }
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
    searchField.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.68)
    searchField.focusRingType = .none
    searchField.toolTip = "Search clipboard history."
    searchField.setAccessibilityHelp("Type to search clipboard history. Use the side category icons to filter results.")
    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.setContentCompressionResistancePriority(.required, for: .horizontal)
    searchField.setContentHuggingPriority(.required, for: .horizontal)
    configureSearchControlContainer()
    updateSearchFieldPresentation()

    collectionStack.orientation = .vertical
    collectionStack.alignment = .centerX
    collectionStack.distribution = .fill
    collectionStack.spacing = Metrics.collectionSideRailGap
    collectionStack.translatesAutoresizingMaskIntoConstraints = true
    collectionStack.setContentCompressionResistancePriority(.required, for: .vertical)
    collectionStack.setContentHuggingPriority(.required, for: .vertical)
    collectionStack.setAccessibilityLabel("Clipboard collections")

    collectionDocumentView.translatesAutoresizingMaskIntoConstraints = true
    collectionDocumentView.addSubview(collectionStack)
    collectionScrollView.documentView = collectionDocumentView
    collectionScrollView.hasHorizontalScroller = false
    collectionScrollView.hasVerticalScroller = false
    collectionScrollView.autohidesScrollers = true
    collectionScrollView.scrollerStyle = .overlay
    collectionScrollView.drawsBackground = false
    collectionScrollView.borderType = .noBorder
    collectionScrollView.setAccessibilityLabel("Clipboard collections")
    collectionScrollView.setContentCompressionResistancePriority(.required, for: .horizontal)
    collectionScrollView.setContentHuggingPriority(.required, for: .horizontal)
    collectionScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    collectionScrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
    configureAddCollectionButton()
    configureCollectionButtons()

    let clearHistoryButton = iconButton(
      "trash",
      toolTip: "Clear History",
      accessibilityHelp: "Clear history.",
      action: #selector(showToolbarMenu(_:))
    )
    self.clearHistoryButton = clearHistoryButton

    let settingsButton = iconButton(
      "gearshape",
      toolTip: "Settings",
      accessibilityHelp: "Open ClipBored settings. Keyboard shortcut: Command-Comma.",
      action: #selector(openSettings)
    )
    self.settingsButton = settingsButton

    let actionStrip = row([
      clearHistoryButton,
      settingsButton
    ])
    actionStrip.spacing = 6
    actionStrip.setContentCompressionResistancePriority(.required, for: .horizontal)
    let actionGroup = groupedToolbar(actionStrip)
    utilityToolbarGroup = actionGroup

    actionGroup.setContentHuggingPriority(.required, for: .horizontal)
    actionGroup.setContentCompressionResistancePriority(.required, for: .horizontal)

    let shelfChrome = NSView()
    shelfChrome.translatesAutoresizingMaskIntoConstraints = false
    shelfChrome.setContentHuggingPriority(.defaultLow, for: .horizontal)
    shelfChrome.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    shelfChrome.setContentHuggingPriority(.defaultHigh, for: .vertical)
    shelfChrome.setContentCompressionResistancePriority(.required, for: .vertical)
    searchControlContainer.translatesAutoresizingMaskIntoConstraints = false
    actionGroup.translatesAutoresizingMaskIntoConstraints = false
    shelfChrome.addSubview(searchControlContainer)
    shelfChrome.addSubview(actionGroup)
    shelfChromeHeightConstraint = shelfChrome.heightAnchor.constraint(equalToConstant: Metrics.collectionRailHeight)
    searchControlCenterYConstraint = searchControlContainer.centerYAnchor.constraint(equalTo: shelfChrome.centerYAnchor)
    utilityToolbarCenterYConstraint = actionGroup.centerYAnchor.constraint(equalTo: shelfChrome.centerYAnchor)
    NSLayoutConstraint.activate([
      shelfChromeHeightConstraint!,
      searchControlContainer.leadingAnchor.constraint(equalTo: shelfChrome.leadingAnchor),
      searchControlCenterYConstraint!,
      actionGroup.trailingAnchor.constraint(equalTo: shelfChrome.trailingAnchor),
      utilityToolbarCenterYConstraint!,
      searchControlContainer.trailingAnchor.constraint(lessThanOrEqualTo: actionGroup.leadingAnchor, constant: -12)
    ])
    shelfChromeView = shelfChrome

    itemsStack.orientation = .vertical
    itemsStack.usesFlippedCoordinates = true
    itemsStack.alignment = .centerX
    applyCardDensity()
    itemsStack.translatesAutoresizingMaskIntoConstraints = true
    scrollView.documentView = itemsStack
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.setContentHuggingPriority(.required, for: .vertical)
    scrollView.setContentCompressionResistancePriority(.required, for: .vertical)
    scrollView.onVisibleBoundsChanged = { [weak self] in
      self?.renderCardsNearVisibleViewport()
    }
    scrollViewHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: cardDensity.railHeight)
    scrollViewHeightConstraint?.isActive = true

    bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
    bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    let headerStack = NSStackView(views: [shelfChrome])
    headerStack.orientation = .vertical
    headerStack.alignment = .leading
    headerStack.distribution = .fill
    headerStack.spacing = 0
    headerStack.setContentCompressionResistancePriority(.required, for: .vertical)
    self.headerStack = headerStack

    let contentStack = NSView()
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
    contentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    contentStack.setContentHuggingPriority(.defaultLow, for: .vertical)
    contentStack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    contentStack.addSubview(scrollView)
    contentStack.addSubview(collectionScrollView)
    self.contentStack = contentStack

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    collectionScrollView.translatesAutoresizingMaskIntoConstraints = false
    collectionScrollWidthConstraint = collectionScrollView.widthAnchor.constraint(equalToConstant: Metrics.collectionSideRailWidth)
    collectionScrollWidthConstraint?.priority = .required
    collectionRailLeadingConstraint = collectionScrollView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor)

    let mainStack = NSStackView(views: [headerStack, contentStack, bottomSpacer])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.distribution = .fill
    mainStack.detachesHiddenViews = true
    mainStack.spacing = 8
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
      shelfChrome.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
      contentStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -(Metrics.panelSideInset * 2)),
      scrollView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: contentStack.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor),
      collectionRailLeadingConstraint!,
      collectionScrollWidthConstraint!,
      collectionScrollView.topAnchor.constraint(equalTo: contentStack.topAnchor),
      collectionScrollView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor)
    ])

    applyPanelLayout(reloadItems: false)
    updateCollectionButtons()
    updateResultCount()
  }

  private func bindViewModel() {
    viewModel.onVisibleItemsChanged = { [weak self] _ in
      self?.handleVisibleItemsChanged()
    }
    viewModel.onSearchTextChanged = { [weak self] _ in
      self?.syncSearchFieldFromViewModel()
    }
    viewModel.onSelectedIndexChanged = { [weak self] _ in
      self?.updateSelection()
    }
    viewModel.onSelectedItemsChanged = { [weak self] in
      self?.updateSelection()
      self?.updateResultCount()
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
      self?.handleStackChanged()
    }
    viewModel.onCaptureStatusChanged = { [weak self] in
      self?.updateStatus(self?.viewModel.statusMessage ?? "")
    }
    viewModel.onCompactModeChanged = { [weak self] in
      guard let self else { return }
      _ = self.updateCardDensityForCurrentWidth()
    }
    viewModel.onPanelLayoutChanged = { [weak self] in
      self?.applyPanelLayout()
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
    let container = NSView()
    container.wantsLayer = true
    container.translatesAutoresizingMaskIntoConstraints = false
    container.layer?.cornerRadius = Metrics.actionButtonSize / 2
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

  private func configureSearchIconButton() {
    let toolTip = "Search"
    let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: toolTip)
    image?.isTemplate = true
    searchIconButton.image = image
    searchIconButton.imagePosition = .imageOnly
    searchIconButton.imageScaling = .scaleProportionallyDown
    searchIconButton.bezelStyle = .smallSquare
    searchIconButton.isBordered = false
    searchIconButton.wantsLayer = true
    searchIconButton.layer?.cornerRadius = Metrics.searchControlSize / 2
    searchIconButton.layer?.borderWidth = 0.5
    searchIconButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    searchIconButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
    searchIconButton.contentTintColor = .secondaryLabelColor
    searchIconButton.toolTip = toolTip
    searchIconButton.target = self
    searchIconButton.action = #selector(focusSearchFromIcon)
    searchIconButton.setAccessibilityLabel(toolTip)
    searchIconButton.setAccessibilityHelp("Search clipboard history.")
    searchIconButton.translatesAutoresizingMaskIntoConstraints = false
    searchIconButton.widthAnchor.constraint(equalToConstant: Metrics.searchControlSize).isActive = true
    searchIconButton.heightAnchor.constraint(equalToConstant: Metrics.searchControlSize).isActive = true
  }

  private func configureSearchControlContainer() {
    searchControlContainer.translatesAutoresizingMaskIntoConstraints = false
    searchControlContainer.wantsLayer = true
    searchControlContainer.layer?.masksToBounds = true
    searchControlContainer.setContentHuggingPriority(.required, for: .horizontal)
    searchControlContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
    searchFieldWidthConstraint = searchControlContainer.widthAnchor.constraint(equalToConstant: Metrics.searchControlSize)
    searchFieldWidthConstraint?.isActive = true
    searchControlContainer.heightAnchor.constraint(equalToConstant: Metrics.searchControlSize).isActive = true

    searchControlContainer.addSubview(searchField)
    searchControlContainer.addSubview(searchIconButton)
    NSLayoutConstraint.activate([
      searchField.leadingAnchor.constraint(equalTo: searchControlContainer.leadingAnchor),
      searchField.trailingAnchor.constraint(equalTo: searchControlContainer.trailingAnchor),
      searchField.topAnchor.constraint(equalTo: searchControlContainer.topAnchor),
      searchField.bottomAnchor.constraint(equalTo: searchControlContainer.bottomAnchor),
      searchIconButton.leadingAnchor.constraint(equalTo: searchControlContainer.leadingAnchor),
      searchIconButton.topAnchor.constraint(equalTo: searchControlContainer.topAnchor),
      searchIconButton.bottomAnchor.constraint(equalTo: searchControlContainer.bottomAnchor)
    ])
  }

  #if DEBUG
  private func searchFilterMenu(now: Date = Date()) -> NSMenu {
    let menu = NSMenu(title: "Search Filters")
    menu.autoenablesItems = false

    let typeMenu = NSMenu(title: "Type")
    addSearchFilterItem("Text", token: "type:text", to: typeMenu)
    addSearchFilterItem("Rich Text", token: "type:richtext", to: typeMenu)
    addSearchFilterItem("Links", token: "type:link", to: typeMenu)
    addSearchFilterItem("Images", token: "type:image", to: typeMenu)
    addSearchFilterItem("Files", token: "type:file", to: typeMenu)
    addSearchFilterItem("PDFs", token: "type:pdf", to: typeMenu)
    addSearchFilterItem("Audio", token: "type:audio", to: typeMenu)
    addSearchFilterItem("Videos", token: "type:video", to: typeMenu)
    addSearchFilterItem("Colors", token: "type:color", to: typeMenu)
    addSearchFilterItem("Code", token: "type:code", to: typeMenu)
    addSubmenu(typeMenu, titled: "Type", to: menu)

    let dateMenu = NSMenu(title: "Date")
    addSearchFilterItem("Today", token: "date:\(Self.searchFilterDateString(now))", to: dateMenu)
    addSearchFilterItem("Last 7 Days", token: "after:\(Self.searchFilterDateString(Self.searchFilterDate(byAddingDays: -6, to: now)))", to: dateMenu)
    addSearchFilterItem("Before Today", token: "before:\(Self.searchFilterDateString(now))", to: dateMenu)
    addSubmenu(dateMenu, titled: "Date", to: menu)

    addSearchFilterItem("Pinned Items", token: "pinned:on", to: menu)

    if !viewModel.searchFilterSourceAppNames.isEmpty {
      let sourceMenu = NSMenu(title: "Copied From")
      for sourceApp in viewModel.searchFilterSourceAppNames {
        addSearchFilterItem(sourceApp, token: "app:\(Self.quotedSearchFilterValue(sourceApp))", to: sourceMenu)
      }
      addSubmenu(sourceMenu, titled: "Copied From", to: menu)
    }

    if !viewModel.searchFilterDeviceNames.isEmpty {
      let deviceMenu = NSMenu(title: "Device")
      for deviceName in viewModel.searchFilterDeviceNames {
        addSearchFilterItem(deviceName, token: "device:\(Self.quotedSearchFilterValue(deviceName))", to: deviceMenu)
      }
      addSubmenu(deviceMenu, titled: "Device", to: menu)
    }

    if !viewModel.collectionNames.isEmpty {
      let pinboardMenu = NSMenu(title: "Pinboard")
      for collectionName in viewModel.collectionNames {
        addSearchFilterItem(collectionName, token: "pinboard:\(Self.quotedSearchFilterValue(collectionName))", to: pinboardMenu)
      }
      addSubmenu(pinboardMenu, titled: "Pinboard", to: menu)
    }

    return menu
  }

  private func addSubmenu(_ submenu: NSMenu, titled title: String, to menu: NSMenu) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    item.isEnabled = true
    menu.addItem(item)
  }

  private func addSearchFilterItem(_ title: String, token: String, to menu: NSMenu) {
    let item = NSMenuItem(title: title, action: #selector(applySearchFilterFromMenu(_:)), keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    item.representedObject = token
    menu.addItem(item)
  }

  private func applySearchFilterToken(_ token: String) {
    let current = searchField.stringValue.clipboardTrimmed
    let updatedQuery = Self.searchQuery(current, applyingFilterToken: token)
    if searchField.stringValue != updatedQuery {
      searchField.stringValue = updatedQuery
    }
    updateSearchText()
    focusSearchField()
  }

  private static func searchQuery(_ query: String, applyingFilterToken token: String) -> String {
    guard !query.isEmpty else { return token }
    let currentParts = searchFilterParts(from: query)
    let tokenParts = searchFilterParts(from: token)
    guard tokenParts.count == 1, let tokenPart = tokenParts.first else { return query }

    if currentParts.contains(where: { $0.canonical == tokenPart.canonical }) {
      return query
    }

    if tokenPart.isExact,
       let keyValueCanonical = tokenPart.keyValueCanonical,
       let fuzzyIndex = currentParts.firstIndex(where: {
         !$0.isExact && $0.keyValueCanonical == keyValueCanonical
       }) {
      var rawParts = currentParts.map(\.raw)
      rawParts[fuzzyIndex] = token
      return rawParts.joined(separator: " ")
    }

    if let replacementKeys = replacementKeyFamily(for: tokenPart.canonicalKey),
       currentParts.contains(where: { part in
         part.canonicalKey.map { replacementKeys.contains($0) } ?? false
       }) {
      var rawParts: [String] = []
      var insertedReplacement = false
      for part in currentParts {
        guard let canonicalKey = part.canonicalKey,
              replacementKeys.contains(canonicalKey) else {
          rawParts.append(part.raw)
          continue
        }
        if !insertedReplacement {
          rawParts.append(token)
          insertedReplacement = true
        }
      }
      if !insertedReplacement {
        rawParts.append(token)
      }
      return rawParts.joined(separator: " ")
    }

    return "\(query) \(token)"
  }

  private static func replacementKeyFamily(for key: String?) -> Set<String>? {
    guard let key else { return nil }
    let dateKeys: Set<String> = ["after", "before", "date"]
    if dateKeys.contains(key) {
      return dateKeys
    }
    if key == "pinned" {
      return ["pinned"]
    }
    if key == "type" {
      return ["type"]
    }
    return nil
  }

  private static func searchFilterParts(from query: String) -> [ClipboardSearchFilterPart] {
    var parts: [ClipboardSearchFilterPart] = []
    var current = ""
    var quotedBy: Character?
    var isEscaping = false

    func flushCurrent() {
      let part = current.clipboardTrimmed
      if !part.isEmpty {
        parts.append(searchFilterPart(from: part))
      }
      current = ""
    }

    for character in query {
      if isEscaping {
        current.append("\\")
        current.append(character)
        isEscaping = false
        continue
      }

      if character == "\\" && quotedBy != nil {
        isEscaping = true
        continue
      }

      if character == "\"" || character == "'" {
        if quotedBy == character {
          current.append(character)
          quotedBy = nil
          continue
        }
        if quotedBy == nil {
          quotedBy = character
          current.append(character)
          continue
        }
      }

      if character.isWhitespace && quotedBy == nil {
        flushCurrent()
      } else {
        current.append(character)
      }
    }

    if isEscaping {
      current.append("\\")
    }
    flushCurrent()
    return parts
  }

  private static func searchFilterPart(from rawPart: String) -> ClipboardSearchFilterPart {
    guard let delimiter = rawPart.firstIndex(of: ":") else {
      return plainSearchFilterPart(from: rawPart)
    }

    let key = canonicalSearchFilterKey(String(rawPart[..<delimiter]))
    let value = String(rawPart[rawPart.index(after: delimiter)...]).clipboardTrimmed
    if let exactValue = unquotedSearchFilterValue(value) {
      let normalizedValue = normalizedSearchFilterValue(exactValue)
      guard isSupportedSearchFilterPart(canonicalKey: key, normalizedValue: normalizedValue) else {
        return plainSearchFilterPart(from: rawPart)
      }
      return ClipboardSearchFilterPart(
        raw: rawPart,
        canonical: "\(key):=\(normalizedValue)",
        canonicalKey: key,
        keyValueCanonical: "\(key):\(normalizedValue)",
        isExact: true
      )
    }

    let normalizedValue = normalizedSearchFilterValue(value)
    guard isSupportedSearchFilterPart(canonicalKey: key, rawValue: value, normalizedValue: normalizedValue) else {
      return plainSearchFilterPart(from: rawPart)
    }
    return ClipboardSearchFilterPart(
      raw: rawPart,
      canonical: "\(key):~\(normalizedValue)",
      canonicalKey: key,
      keyValueCanonical: "\(key):\(normalizedValue)",
      isExact: false
    )
  }

  private static func plainSearchFilterPart(from rawPart: String) -> ClipboardSearchFilterPart {
    let canonical = normalizedSearchFilterValue(rawPart)
    return ClipboardSearchFilterPart(
      raw: rawPart,
      canonical: canonical,
      canonicalKey: nil,
      keyValueCanonical: nil,
      isExact: false
    )
  }

  private static func isSupportedSearchFilterPart(
    canonicalKey key: String,
    rawValue: String? = nil,
    normalizedValue: String
  ) -> Bool {
    guard !normalizedValue.isEmpty else { return false }
    switch key {
    case "app", "device", "pinboard":
      return true
    case "type":
      let rawValues = rawValue.map(searchFilterStructuredValues) ?? [normalizedValue]
      let values = rawValues
        .map { unquotedSearchFilterValue($0.clipboardTrimmed) ?? $0 }
        .map(normalizedSearchFilterValue)
        .filter { !$0.isEmpty }
      return !values.isEmpty && values.allSatisfy(isSupportedSearchFilterType)
    case "pinned":
      return isSupportedSearchFilterBoolean(normalizedValue)
    case "after", "before", "date":
      return isSupportedSearchFilterDate(normalizedValue)
    default:
      return false
    }
  }

  private static func searchFilterStructuredValues(from value: String) -> [String] {
    var values: [String] = []
    var current = ""
    var quotedBy: Character?
    var isEscaping = false

    func flushCurrent() {
      values.append(current)
      current = ""
    }

    for character in value {
      if isEscaping {
        current.append("\\")
        current.append(character)
        isEscaping = false
        continue
      }

      if character == "\\" && quotedBy != nil {
        isEscaping = true
        continue
      }

      if character == "\"" || character == "'" {
        if quotedBy == character {
          current.append(character)
          quotedBy = nil
          continue
        }
        if quotedBy == nil {
          quotedBy = character
          current.append(character)
          continue
        }
      }

      if character == "," && quotedBy == nil {
        flushCurrent()
      } else {
        current.append(character)
      }
    }

    if isEscaping {
      current.append("\\")
    }
    flushCurrent()
    return values
  }

  private static func isSupportedSearchFilterType(_ value: String) -> Bool {
    switch value {
    case "text", "plain",
         "richtext", "rich-text", "rtf", "html",
         "note", "notes", "writing",
         "code", "snippet", "snippets", "source", "programming", "script", "scripts", "json", "css", "sql",
         "link", "links", "url", "urls", "web",
         "image", "images", "photo", "photos", "picture", "pictures",
         "file", "files", "finder",
         "pdf", "pdfs", "document", "documents",
         "audio", "sound", "music",
         "video", "videos", "movie", "movies", "mp4", "quicktime", "mov",
         "color", "colors", "swatch", "swatches", "hex",
         "unknown", "item":
      return true
    default:
      return false
    }
  }

  private static func isSupportedSearchFilterBoolean(_ value: String) -> Bool {
    switch value {
    case "1", "true", "yes", "y", "on",
         "0", "false", "no", "n", "off":
      return true
    default:
      return false
    }
  }

  private static func isSupportedSearchFilterDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.calendar = searchFilterCalendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = searchFilterCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value) else { return false }
    return formatter.string(from: date) == value
  }

  private static func canonicalSearchFilterKey(_ key: String) -> String {
    switch normalizedSearchFilterValue(key) {
    case "source", "from":
      return "app"
    case "devices", "machine", "computer":
      return "device"
    case "collection", "folder", "list", "pinboards", "board", "boards":
      return "pinboard"
    case "kind":
      return "type"
    case "pin":
      return "pinned"
    case "on":
      return "date"
    case "since":
      return "after"
    case "until":
      return "before"
    default:
      return normalizedSearchFilterValue(key)
    }
  }

  private static func unquotedSearchFilterValue(_ value: String) -> String? {
    guard let first = value.first,
          (first == "\"" || first == "'"),
          value.last == first,
          value.count >= 2 else {
      return nil
    }
    let inner = String(value.dropFirst().dropLast())
    var unescaped = ""
    var isEscaping = false
    for character in inner {
      if isEscaping {
        unescaped.append(character)
        isEscaping = false
      } else if character == "\\" {
        isEscaping = true
      } else {
        unescaped.append(character)
      }
    }
    if isEscaping {
      unescaped.append("\\")
    }
    return unescaped
  }

  private static func normalizedSearchFilterValue(_ value: String) -> String {
    value.clipboardTrimmed
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
  }

  private static func quotedSearchFilterValue(_ value: String) -> String {
    let sanitized = value.clipboardTrimmed
    let escaped = sanitized
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  private static func searchFilterDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    let calendar = searchFilterCalendar
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func searchFilterDate(byAddingDays days: Int, to date: Date) -> Date {
    searchFilterCalendar.date(byAdding: .day, value: days, to: date) ?? date
  }

  private static var searchFilterCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }
  #endif

  private func categoryMenu() -> NSMenu {
    let menu = NSMenu(title: "Categories")
    menu.autoenablesItems = false
    return menu
  }

  private func clearHistoryMenu() -> NSMenu {
    let menu = NSMenu(title: "Clear History")
    menu.autoenablesItems = false
    for (title, seconds) in [("Past Hour", 3600.0), ("Past Day", 86_400.0), ("All Time", -1.0)] {
      let item = NSMenuItem(title: title, action: #selector(performToolbarMenuItem(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = seconds
      menu.addItem(item)
    }
    return menu
  }

  private func configureCollectionButtons() {
    collectionButtons.removeAll()
    customCollectionButtons.removeAll()
    collectionChipOrder.removeAll()
    let visibleSortModes = visibleSortModesForCurrentCounts()
    configuredSortModes = visibleSortModes
    configuredCollectionNames = viewModel.collectionNames
    for view in collectionStack.arrangedSubviews {
      (view as? CollectionChipView)?.clearKeyboardFocus()
      collectionStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    for mode in visibleSortModes {
      let chip = CollectionChipView(
        title: collectionTitle(for: mode),
        color: collectionColor(for: mode),
        symbolName: collectionSymbol(for: mode),
        iconOnly: true
      )
      chip.toolTip = mode.title
      chip.onPress = { [weak self] extending in
        guard let self else { return }
        self.commitCategoryHoverPreview()
        self.collapseSearchFieldIfIdle()
        self.viewModel.selectSortMode(mode, extending: extending)
        self.viewModel.commitCategorySelection()
      }
      chip.onHover = { [weak self] hovered in
        self?.handleCategoryHover(.sortMode(mode), hovered: hovered)
      }
      configureCollectionKeyboardNavigation(for: chip)
      collectionButtons[mode] = chip
      collectionChipOrder.append(chip)
      collectionStack.addArrangedSubview(chip)
    }

    for collectionName in configuredCollectionNames {
      let chip = CollectionChipView(title: collectionName, color: collectionColor(forCollectionNamed: collectionName), iconOnly: true)
      chip.toolTip = collectionName
      chip.onPress = { [weak self] extending in
        guard let self else { return }
        self.commitCategoryHoverPreview()
        self.collapseSearchFieldIfIdle()
        self.viewModel.selectCollection(named: collectionName, extending: extending)
      }
      chip.onHover = { [weak self] hovered in
        self?.handleCategoryHover(.collection(collectionName), hovered: hovered)
      }
      chip.onDropItem = { [weak self] itemID in
        self?.viewModel.assignItem(withID: itemID, to: collectionName)
      }
      chip.onEdit = { [weak self] in
        self?.editCollection(named: collectionName)
      }
      chip.onExport = { [weak self] in
        self?.exportCollection(named: collectionName)
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
    resetCollectionScrollPositionOnNextLayout = true
    sizeCollectionDocument(consumingScrollReset: false)
  }

  private func configureStackChip() {
    stackChip.toolTip = "Queued clips"
    stackChip.onPress = { [weak self] _ in
      guard let self else { return }
      self.commitCategoryHoverPreview()
      self.collapseSearchFieldIfIdle()
      self.viewModel.selectStack()
    }
    stackChip.onHover = { [weak self] hovered in
      self?.handleCategoryHover(.stack, hovered: hovered)
    }
    stackChip.onAddVisibleToStack = { [weak self] in
      self?.viewModel.addVisibleItemsToStack()
    }
    stackChip.onPasteStackNext = { [weak self] in
      self?.viewModel.pasteNextStackItem()
    }
    stackChip.onCopyStackNext = { [weak self] in
      self?.viewModel.copyNextStackItem()
    }
    stackChip.onPasteStackText = { [weak self] in
      self?.viewModel.pasteStackAsText()
    }
    stackChip.onCopyStackText = { [weak self] in
      self?.viewModel.copyStackAsText()
    }
    stackChip.onClearStack = { [weak self] in
      self?.viewModel.clearStack()
    }
    stackChip.onToggleStackCapture = { [weak self] in
      self?.viewModel.toggleStackCaptureMode()
    }
    configureCollectionKeyboardNavigation(for: stackChip)
    stackChip.setStackCaptureActive(viewModel.isStackCaptureEnabled)
    stackChip.toolTip = viewModel.isStackCaptureEnabled ? "Stack capture is on" : "Queued clips"
    if shouldShowStackChip {
      collectionChipOrder.append(stackChip)
      collectionStack.addArrangedSubview(stackChip)
    }
  }

  private func handleCategoryHover(_ target: CategoryHoverTarget, hovered: Bool) {
    if hovered {
      previewCategory(target)
    } else {
      scheduleCategoryHoverRestoreIfNeeded(exiting: target)
    }
  }

  private func previewCategory(_ target: CategoryHoverTarget) {
    if categoryHoverOriginalSelection == nil {
      categoryHoverOriginalSelection = viewModel.categorySelectionSnapshot()
    }
    hoveredCategoryTarget = target
    categoryHoverGeneration += 1
    collapseSearchFieldIfIdle()
    switch target {
    case .sortMode(let mode):
      viewModel.previewSortMode(mode)
    case .collection(let name):
      viewModel.previewCollection(named: name)
    case .stack:
      viewModel.previewStack()
    }
  }

  private func scheduleCategoryHoverRestoreIfNeeded(exiting target: CategoryHoverTarget) {
    guard hoveredCategoryTarget == target else { return }
    hoveredCategoryTarget = nil
    categoryHoverGeneration += 1
    let generation = categoryHoverGeneration
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.categoryHoverGeneration == generation else { return }
      guard self.hoveredCategoryTarget == nil else { return }
      self.restoreCategoryHoverPreviewIfNeeded()
    }
  }

  private func commitCategoryHoverPreview() {
    categoryHoverGeneration += 1
    hoveredCategoryTarget = nil
    categoryHoverOriginalSelection = nil
  }

  private func restoreCategoryHoverPreviewIfNeeded() {
    guard let snapshot = categoryHoverOriginalSelection else { return }
    categoryHoverOriginalSelection = nil
    viewModel.restoreCategorySelection(snapshot)
  }

  private func configureCollectionKeyboardNavigation(for chip: CollectionChipView) {
    chip.onStartSearch = { [weak self] text in
      self?.startSearchFromShelf(text)
    }
    chip.onMoveFocus = { [weak self, weak chip] delta in
      self?.moveCollectionFocus(from: chip, delta: delta)
    }
    chip.onMoveCardSelection = { [weak self] delta in
      self?.moveSelectionFromFocusedCard(delta)
    }
    chip.onSelectFirst = { [weak self] in
      self?.selectCollectionChip(at: 0)
    }
    chip.onSelectLast = { [weak self] in
      guard let self else { return }
      self.selectCollectionChip(at: self.collectionChipOrder.count - 1)
    }
  }

  private func visibleSortModesForCurrentCounts() -> [ClipboardSortMode] {
    ClipboardSortMode.allCases.filter { viewModel.shouldShowCategory(for: $0) }
  }

  private func primarySortModesForCurrentCounts() -> [ClipboardSortMode] {
    let visibleSortModes = visibleSortModesForCurrentCounts()
    var primaryModes: [ClipboardSortMode] = []

    for mode in [ClipboardSortMode.mostRecent, .mostUsed, .text, .links, .images] {
      if visibleSortModes.contains(mode) {
        primaryModes.append(mode)
      }
    }

    for mode in visibleSortModes where viewModel.isSortModeCategorySelected(mode) {
      if !primaryModes.contains(mode) {
        primaryModes.append(mode)
      }
    }

    return primaryModes
  }

  private func overflowSortModesForCurrentCounts() -> [ClipboardSortMode] {
    visibleSortModesForCurrentCounts().filter { !isPrimarySortMode($0) }
  }

  private func isPrimarySortMode(_ mode: ClipboardSortMode) -> Bool {
    primarySortModesForCurrentCounts().contains(mode)
  }

  private func configureAddCollectionButton() {
    let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New collection")
    image?.isTemplate = true
    addCollectionButton.image = image
    addCollectionButton.imagePosition = .imageOnly
    addCollectionButton.imageScaling = .scaleProportionallyDown
    addCollectionButton.isBordered = false
    addCollectionButton.wantsLayer = true
    addCollectionButton.layer?.cornerRadius = Metrics.collectionSideRailItemSize / 2
    addCollectionButton.layer?.borderWidth = 0.5
    addCollectionButton.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
    addCollectionButton.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.18).cgColor
    addCollectionButton.contentTintColor = .tertiaryLabelColor
    addCollectionButton.toolTip = "New collection"
    addCollectionButton.setAccessibilityLabel("New collection")
    addCollectionButton.setAccessibilityHelp("Create a new Pinboard collection. Keyboard shortcut: Shift-Command-N.")
    addCollectionButton.target = self
    addCollectionButton.action = #selector(createCollectionFromToolbar)
    addCollectionButton.translatesAutoresizingMaskIntoConstraints = false
    addCollectionButton.widthAnchor.constraint(equalToConstant: Metrics.collectionSideRailItemSize).isActive = true
    addCollectionButton.heightAnchor.constraint(equalToConstant: Metrics.collectionSideRailItemSize).isActive = true
  }

  private func collectionTitle(for mode: ClipboardSortMode) -> String {
    switch mode {
    case .mostRecent: return "Clipboard"
    case .mostUsed: return "Frequent"
    case .text: return "Text"
    case .links: return "Links"
    case .images: return "Images"
    case .colors: return "Colors"
    case .audio: return "Audio"
    case .files: return "Files"
    case .pinned: return "Pinned"
    case .code: return "Code"
    case .videos: return "Videos"
    }
  }

  private func collectionSymbol(for mode: ClipboardSortMode) -> String {
    switch mode {
    case .mostRecent: return "doc.on.clipboard"
    case .mostUsed: return "chart.bar.fill"
    case .text: return "text.alignleft"
    case .links: return "link"
    case .images: return "photo"
    case .colors: return "paintpalette"
    case .audio: return "music.note"
    case .files: return "doc.fill"
    case .pinned: return "pin.fill"
    case .code: return "chevron.left.forwardslash.chevron.right"
    case .videos: return "film"
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
    itemsStack.edgeInsets = NSEdgeInsets(
      top: cardDensity.cardTopInset,
      left: cardDensity.cardStackInset,
      bottom: cardDensity.cardBottomInset,
      right: cardDensity.cardStackInset
    )
    scrollViewHeightConstraint?.constant = cardDensity.railHeight
  }

  private func currentCardLayout(viewportWidth: CGFloat? = nil) -> ClipboardItemCardLayout {
    let layout = cardDensity.layout
    guard currentPanelLayout == .vertical else { return layout }

    let visibleWidth = viewportWidth ?? scrollView.contentView.bounds.width
    guard visibleWidth > 1 else { return layout }

    let availableCardWidth = floor(visibleWidth - (cardDensity.cardStackInset * 2))
    guard availableCardWidth > 0, availableCardWidth < layout.width else { return layout }

    return layout.withWidth(max(Metrics.minimumVerticalCardWidth, availableCardWidth))
  }

  private var verticalCardLeadingReserve: CGFloat {
    currentPanelLayout == .vertical ? Metrics.collectionSideRailWidth : 0
  }

  private func verticalCardMinXInContent(width cardWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
    let reserve = verticalCardLeadingReserve
    let availableWidth = max(1, viewportWidth - reserve)
    return reserve + max(cardDensity.cardStackInset, floor((availableWidth - cardWidth) / 2))
  }

  private func applyPanelLayout(reloadItems shouldReload: Bool = true) {
    currentPanelLayout = viewModel.panelLayout
    let isVertical = currentPanelLayout == .vertical

    updateShelfChromeLayout(isVertical: isVertical)
    itemsStack.orientation = isVertical ? .vertical : .horizontal
    itemsStack.usesFlippedCoordinates = isVertical
    itemsStack.alignment = isVertical ? .centerX : .bottom
    scrollView.hasHorizontalScroller = !isVertical
    scrollView.hasVerticalScroller = isVertical
    scrollViewHeightConstraint?.isActive = !isVertical
    bottomSpacer.isHidden = isVertical
    scrollView.setContentHuggingPriority(isVertical ? .defaultLow : .required, for: .vertical)
    scrollView.setContentCompressionResistancePriority(isVertical ? .defaultLow : .required, for: .vertical)

    lastScrollViewportSize = .zero
    updateSearchFieldPresentation()
    sizeCollectionDocument(consumingScrollReset: false)
    applyCardDensity()

    if shouldReload {
      let densityChanged = updateCardDensityForCurrentWidth()
      if !densityChanged {
        reloadItems()
      }
      updateSelection()
    }
    needsLayout = true
  }

  private func updateShelfChromeLayout(isVertical: Bool) {
    shelfChromeHeightConstraint?.constant = Metrics.collectionRailHeight
    searchControlCenterYConstraint?.constant = 0
    utilityToolbarCenterYConstraint?.constant = 0
    shelfChromeView?.needsLayout = true
    headerStack?.needsLayout = true
    contentStack?.needsLayout = true
  }

  @discardableResult
  private func updateCardDensityForCurrentWidth() -> Bool {
    let targetDensity = CardDensity.fitting(
      width: bounds.width,
      height: bounds.height,
      compactModeEnabled: viewModel.isCompactModeEnabled,
      panelLayout: currentPanelLayout
    )
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

  private func iconButton(
    _ systemName: String,
    toolTip: String,
    accessibilityHelp: String,
    action: Selector
  ) -> NSButton {
    let button = NSButton(title: "", target: self, action: action)
    let image = NSImage(systemSymbolName: systemName, accessibilityDescription: toolTip)
    image?.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.bezelStyle = .smallSquare
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    button.layer?.borderWidth = 0.5
    button.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    button.layer?.cornerRadius = Metrics.actionButtonSize / 2
    button.toolTip = toolTip
    button.contentTintColor = .secondaryLabelColor
    button.setAccessibilityLabel(toolTip)
    button.setAccessibilityHelp(accessibilityHelp)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: Metrics.actionButtonSize).isActive = true
    button.heightAnchor.constraint(equalToConstant: Metrics.actionButtonSize).isActive = true
    return button
  }

  private func cardReuseFingerprint(
    for item: ClipboardItem,
    index: Int,
    layout: ClipboardItemCardLayout,
    collectionNames: [String],
    selectedCollectionName: String?,
    selectedCollectionColor: NSColor?,
    canShowInClipboard: Bool
  ) -> ClipboardItemCardReuseFingerprint {
    let normalizedItemCollection = ClipboardCollectionDefaults.normalizedName(item.collectionName)
    let normalizedSelectedCollection = ClipboardCollectionDefaults.normalizedName(selectedCollectionName)
    let activeCollectionName = normalizedSelectedCollection == normalizedItemCollection ? normalizedSelectedCollection : nil
    let activeCollectionColorHex = activeCollectionName.map { name in
      ClipboardCollectionVisuals.hexString(
        for: selectedCollectionColor ?? collectionColor(forCollectionNamed: name)
      )
    }
    return ClipboardItemCardReuseFingerprint(
      id: item.id,
      kind: item.kind,
      displayText: item.displayText,
      payload: item.payload,
      payloadHash: item.payloadHash,
      createdAt: item.createdAt,
      lastUsedAt: item.lastUsedAt,
      useCount: item.useCount,
      sourceApp: item.sourceApp,
      imagePath: item.imagePath,
      thumbnailPath: item.thumbnailPath,
      isPinned: item.isPinned,
      sourceAppBundleID: item.sourceAppBundleId,
      ocrText: item.ocrText,
      collectionName: normalizedItemCollection,
      customTitle: item.customTitle,
      sourceDeviceName: item.sourceDeviceName,
      layout: layout,
      collectionNames: collectionNames.compactMap { ClipboardCollectionDefaults.normalizedName($0) },
      canShowInClipboard: canShowInClipboard,
      activeCollectionName: activeCollectionName,
      activeCollectionColorHex: activeCollectionColorHex,
      quickPasteNumber: index < 9 ? index + 1 : nil
    )
  }

  private func reloadItems() {
    cardReloadGeneration += 1
    let reloadGeneration = cardReloadGeneration
    let focusedCardReloadTarget = focusedCardReloadTarget()
    currentCardRenderContext = nil
    cardViews.removeAll()
    cardSlots.removeAll()
    cardItemCount = 0
    lastScrollViewportSize = .zero
    for view in itemsStack.arrangedSubviews {
      itemsStack.removeArrangedSubview(view)
    }
    for view in itemsStack.subviews {
      view.removeFromSuperview()
    }

    let items = viewModel.visibleItems
    let shouldAnimateReload = window != nil && !defersVisualReloads
    if items.isEmpty {
      lastSynchronousCardRenderCount = 0
      emptyStateText = emptyStateCopy()
      scrollView.documentView = emptyStateView()
    } else {
      emptyStateText = nil
      if scrollView.documentView !== itemsStack {
        scrollView.documentView = itemsStack
      }
      let collectionNames = viewModel.collectionNames
      let layout = currentCardLayout()
      let selectedCollectionName = viewModel.selectedCollectionName
      let selectedCollectionColor = selectedCollectionName.map { collectionColor(forCollectionNamed: $0) }
      let canShowInClipboard = viewModel.canShowVisibleItemsInClipboard

      currentCardRenderContext = CardRenderContext(
        items: items,
        collectionNames: collectionNames,
        layout: layout,
        selectedCollectionName: selectedCollectionName,
        selectedCollectionColor: selectedCollectionColor,
        canShowInClipboard: canShowInClipboard,
        reloadGeneration: reloadGeneration
      )
      cardItemCount = items.count
      sizeItemsDocument(itemCount: items.count)

      let synchronousRange = initialCardRenderRange(itemCount: items.count)
      lastSynchronousCardRenderCount = synchronousRange.count
      renderCards(in: synchronousRange, reloadGeneration: reloadGeneration)
    }

    updateSelection()
    restoreFocusedCardIfNeeded(focusedCardReloadTarget)
    updateStatus(viewModel.statusMessage)
    updateResultCount()
    animateContentReloadIfNeeded(shouldAnimateReload)
  }

  private func initialCardRenderRange(itemCount: Int) -> Range<Int> {
    guard itemCount > 0 else { return 0..<0 }
    return 0..<min(itemCount, initialCardRenderBudget)
  }

  private func renderCardsNearVisibleViewport() {
    guard scrollView.documentView === itemsStack,
          currentCardRenderContext != nil,
          cardItemCount > 0 else {
      return
    }
    let visibleRange = visibleCardIndexRange()
    renderCards(in: visibleRange, reloadGeneration: cardReloadGeneration)
    pruneRenderedCards(outside: retainedCardIndexRange(around: visibleRange))
  }

  private func visibleCardIndexRange() -> Range<Int> {
    let itemCount = cardItemCount
    guard itemCount > 0 else { return 0..<0 }

    let visibleBounds = scrollView.contentView.bounds
    let layout = currentCardLayout()
    let spacing = cardDensity.cardSpacing
    let edgeInsets = itemsStack.edgeInsets
    let startPosition: CGFloat
    let endPosition: CGFloat
    let leadingInset: CGFloat

    if currentPanelLayout == .vertical {
      startPosition = visibleBounds.minY
      endPosition = visibleBounds.maxY
      leadingInset = edgeInsets.top
    } else {
      startPosition = visibleBounds.minX
      endPosition = visibleBounds.maxX
      leadingInset = edgeInsets.left
    }

    var firstVisible = itemCount
    var lastVisible = 0
    var cursor = leadingInset
    for index in 0..<itemCount {
      let length = cardSlotPrimaryLength(at: index, layout: layout)
      let itemStart = cursor
      let itemEnd = cursor + length
      if itemEnd >= startPosition && firstVisible == itemCount {
        firstVisible = index
      }
      if itemStart <= endPosition {
        lastVisible = index
      }
      cursor = itemEnd + spacing
      if itemStart > endPosition {
        break
      }
    }

    guard firstVisible < itemCount else { return 0..<min(itemCount, initialCardRenderBudget) }
    let lowerBound = max(0, firstVisible - cardRenderPrefetchBuffer)
    let upperBound = min(itemCount, lastVisible + cardRenderPrefetchBuffer + 1)
    return lowerBound..<max(lowerBound, upperBound)
  }

  private func renderCards(in range: Range<Int>, reloadGeneration: Int) {
    guard let context = currentCardRenderContext,
          context.reloadGeneration == reloadGeneration,
          !range.isEmpty else {
      return
    }

    let clampedRange = max(0, range.lowerBound)..<min(context.items.count, range.upperBound)
    guard !clampedRange.isEmpty else { return }

    for index in clampedRange {
      guard cardSlots[index]?.card == nil else {
        continue
      }

      let item = context.items[index]
      let fingerprint = cardReuseFingerprint(
        for: item,
        index: index,
        layout: context.layout,
        collectionNames: context.collectionNames,
        selectedCollectionName: context.selectedCollectionName,
        selectedCollectionColor: context.selectedCollectionColor,
        canShowInClipboard: context.canShowInClipboard
      )
      let card = ClipboardItemCardView(
        item: item,
        thumbnail: viewModel.thumbnail(for: item),
        index: index,
        reuseFingerprint: fingerprint,
        layout: context.layout,
        collectionNames: context.collectionNames,
        isStacked: viewModel.isItemStacked(at: index),
        stackCount: viewModel.stackCount,
        canShowInClipboard: context.canShowInClipboard,
        selectedCollectionName: context.selectedCollectionName,
        selectedCollectionColor: context.selectedCollectionColor
      )
      let slot = cardSlot(at: index, itemID: item.id, layout: context.layout)
      slot.attachCard(card)
      configureCardCallbacks(card, slot: slot)
      applyCurrentCardState(card, index: index)
    }

    cardViews = renderedCardsInItemOrder()
  }

  private func renderCardIfNeeded(at index: Int) {
    guard index >= 0, index < cardItemCount else { return }
    renderCards(in: index..<(index + 1), reloadGeneration: cardReloadGeneration)
  }

  private func cardView(at index: Int) -> ClipboardItemCardView? {
    cardSlots[index]?.card
  }

  private func cardSlot(
    at index: Int,
    itemID: UUID,
    layout: ClipboardItemCardLayout
  ) -> ClipboardItemCardSlotView {
    if let slot = cardSlots[index] {
      slot.frame = cardSlotFrame(at: index, layout: layout)
      return slot
    }

    let slot = ClipboardItemCardSlotView(itemID: itemID, layout: layout)
    slot.frame = cardSlotFrame(at: index, layout: layout)
    cardSlots[index] = slot
    itemsStack.addSubview(slot)
    return slot
  }

  private func renderedCardsInItemOrder() -> [ClipboardItemCardView] {
    cardSlots.keys.sorted().compactMap { cardSlots[$0]?.card }
  }

  private func retainedCardIndexRange(around renderedRange: Range<Int>) -> Range<Int> {
    let itemCount = cardItemCount
    guard itemCount > 0 else { return 0..<0 }
    let lowerBound = max(0, renderedRange.lowerBound - cardRenderRetentionBuffer)
    let upperBound = min(itemCount, renderedRange.upperBound + cardRenderRetentionBuffer)
    return lowerBound..<max(lowerBound, upperBound)
  }

  private func pruneRenderedCards(outside retainedRange: Range<Int>) {
    guard !cardSlots.isEmpty else { return }
    let activeIndex = viewModel.selectedIndex
    let focusedIndex = focusedRenderedCardIndex()
    let removableIndexes = cardSlots.keys.filter { index in
      !retainedRange.contains(index) && index != activeIndex && index != focusedIndex
    }
    guard !removableIndexes.isEmpty else { return }

    for index in removableIndexes {
      cardSlots.removeValue(forKey: index)?.removeFromSuperview()
    }
    cardViews = renderedCardsInItemOrder()
  }

  private func focusedRenderedCardIndex() -> Int? {
    guard let responder = window?.firstResponder as? NSView else { return nil }
    for (index, slot) in cardSlots {
      guard let card = slot.card else { continue }
      if responder === card || responder.isDescendant(of: card) {
        return index
      }
    }
    return nil
  }

  private func positionRenderedCardSlots(animated: Bool = false) {
    let layout = currentCardLayout()
    guard animated, window != nil else {
      for (index, slot) in cardSlots {
        slot.frame = cardSlotFrame(at: index, layout: layout)
      }
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Motion.cardExpansionDuration
      context.timingFunction = Motion.cardExpansionTiming
      for (index, slot) in cardSlots {
        slot.animator().frame = cardSlotFrame(at: index, layout: layout)
      }
    }
  }

  private func setRenderedCardSlotsToTargetFrames() {
    let layout = currentCardLayout()
    for (index, slot) in cardSlots {
      slot.frame = cardSlotFrame(at: index, layout: layout)
    }
  }

  private func cardSlotFrame(at index: Int, layout: ClipboardItemCardLayout) -> NSRect {
    let edgeInsets = itemsStack.edgeInsets
    let size = cardPresentation(at: index).size(for: layout)
    if currentPanelLayout == .vertical {
      let x = verticalCardMinXInContent(width: size.width, viewportWidth: itemsStack.bounds.width)
      let y = cardSlotOffset(at: index, layout: layout) + edgeInsets.top
      return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    let x = edgeInsets.left + cardSlotOffset(at: index, layout: layout)
    let y = edgeInsets.bottom
    return NSRect(x: x, y: y, width: size.width, height: size.height)
  }

  private func cardPresentation(at index: Int) -> ClipboardCardPresentation {
    if currentPanelLayout == .vertical {
      return index == visuallyExpandedCardIndex ? .verticalFocus : .verticalRow
    }

    guard index == viewModel.selectedIndex else {
      return .horizontalIcon
    }
    if cardDensity == .expanded {
      return .expanded
    }
    return .horizontalFocus
  }

  private var visuallyExpandedCardIndex: Int? {
    if currentPanelLayout == .vertical {
      if let hoveredCardIndex {
        return hoveredCardIndex
      }
      return cardSelectionInputSource == .keyboard ? viewModel.selectedIndex : nil
    }
    return viewModel.selectedIndex
  }

  private func cardSlotPrimaryLength(at index: Int, layout: ClipboardItemCardLayout) -> CGFloat {
    let size = cardPresentation(at: index).size(for: layout)
    return currentPanelLayout == .vertical ? size.height : size.width
  }

  private func cardSlotOffset(at targetIndex: Int, layout: ClipboardItemCardLayout) -> CGFloat {
    guard targetIndex > 0 else { return 0 }
    var offset: CGFloat = 0
    for index in 0..<targetIndex {
      offset += cardSlotPrimaryLength(at: index, layout: layout)
      offset += cardDensity.cardSpacing
    }
    return offset
  }

  private func configureCardCallbacks(_ card: ClipboardItemCardView, slot: ClipboardItemCardSlotView) {
    card.onLiftStateChanged = { [weak slot] lifted in
      slot?.setLifted(lifted)
    }
    card.onSelect = { [weak self] selected, mode in
      if mode == .activate,
         self?.selectionScrollSuppressionCount ?? 0 > 0,
         self?.viewModel.selectedIndex == selected {
        self?.selectionScrollSuppressionCount = 0
        return
      }
      if mode == .activate {
        self?.claimKeyboardCardSelection()
      } else {
        self?.cardSelectionInputSource = .mouse
      }
      if mode != .activate {
        self?.selectionScrollSuppressionCount = 0
      }
      self?.collapseSearchFieldIfIdle()
      self?.viewModel.selectItem(at: selected, mode: mode)
    }
    card.onHover = { [weak self, weak card] selected, mouseLocation in
      guard let self else { return false }
      guard let hoverIndex = self.claimMouseHoverSelection(at: selected, mouseLocation: mouseLocation) else {
        return false
      }
      self.viewModel.selectItem(at: hoverIndex, mode: .hover)
      if !self.isSearchFieldEditing {
        let focusedCard = self.cardView(at: hoverIndex) ?? (hoverIndex == selected ? card : nil)
        if let focusedCard {
          self.window?.makeFirstResponder(focusedCard)
        }
      }
      return hoverIndex == selected
    }
    card.onHoverExit = { [weak self] index in
      self?.handleCardHoverExit(at: index)
    }
    card.onStartSearch = { [weak self] text in
      self?.startSearchFromShelf(text)
    }
    card.onMoveSelection = { [weak self] delta in
      self?.moveSelectionFromFocusedCard(delta)
    }
    card.onExtendSelection = { [weak self] delta in
      self?.extendSelectionFromFocusedCard(delta)
    }
    card.onPageSelection = { [weak self] direction in
      guard let self else { return }
      self.moveSelectionFromFocusedCard(direction * self.visibleCardPageStep)
    }
    card.onPageExtendSelection = { [weak self] direction in
      guard let self else { return }
      self.extendSelectionFromFocusedCard(direction * self.visibleCardPageStep)
    }
    card.onSelectFirst = { [weak self] in
      self?.selectFirstCardFromFocusedCard()
    }
    card.onSelectLast = { [weak self] in
      self?.selectLastCardFromFocusedCard()
    }
    card.onExtendSelectionToFirst = { [weak self] in
      self?.extendSelectionToFirstCardFromFocusedCard()
    }
    card.onExtendSelectionToLast = { [weak self] in
      self?.extendSelectionToLastCardFromFocusedCard()
    }
    card.onSelectAll = { [weak self] in
      self?.viewModel.selectAllVisibleItems()
      self?.focusSelectedCard()
    }
    card.onPaste = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.pasteSelected()
    }
    card.onCopy = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.copySelected()
    }
    card.onPastePlainText = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.pasteSelectedPlainText()
    }
    card.onCopyPlainText = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.copySelectedPlainText()
    }
    card.onPasteSelectionText = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.pasteSelectedItemsAsText()
    }
    card.onCopySelectionText = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.copySelectedItemsAsText()
    }
    card.onAddSelectionToStack = { [weak self] selected in
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.addSelectedItemsToStack()
    }
    card.onToggleStack = { [weak self] selected in
      self?.viewModel.selectItem(at: selected)
      self?.viewModel.toggleSelectedStackMembership()
    }
    card.onAddVisibleToStack = { [weak self] in
      self?.viewModel.addVisibleItemsToStack()
    }
    card.onPasteStackNext = { [weak self] in
      self?.viewModel.pasteNextStackItem()
    }
    card.onCopyStackNext = { [weak self] in
      self?.viewModel.copyNextStackItem()
    }
    card.onPasteStackText = { [weak self] in
      self?.viewModel.pasteStackAsText()
    }
    card.onCopyStackText = { [weak self] in
      self?.viewModel.copyStackAsText()
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
    card.onRotateImage = { [weak self] selected in
      self?.viewModel.selectItem(at: selected)
      self?.viewModel.rotateSelectedImageClockwise()
    }
    card.onExtractImageText = { [weak self] selected in
      self?.viewModel.selectItem(at: selected)
      self?.viewModel.extractTextFromSelectedImage()
    }
    card.onPreview = { [weak self] selected in
      self?.viewModel.selectItem(at: selected)
      self?.onPreview()
    }
    card.onPasteboardWriters = { [weak self] selected in
      self?.viewModel.pasteboardWriters(forItemAt: selected) ?? []
    }
    card.onOpen = { [weak self] selected in
      #if DEBUG
      self?.openClipRequestCountForTesting += 1
      if self?.suppressClipOpenActionsForTesting == true {
        self?.viewModel.selectItem(at: selected)
        return
      }
      #endif
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
      self?.viewModel.selectItem(at: selected, mode: .activate)
      self?.viewModel.deleteSelected()
    }
    card.onUndoDelete = { [weak self] in
      self?.viewModel.undoLastDelete()
    }
  }

  private func focusedCardReloadTarget() -> FocusedCardReloadTarget? {
    guard let responder = window?.firstResponder as? NSView else { return nil }
    for card in cardViews where responder === card || responder.isDescendant(of: card) {
      return FocusedCardReloadTarget(itemID: card.representedItemID, fallbackIndex: card.representedIndex)
    }
    return nil
  }

  private func restoreFocusedCardIfNeeded(_ target: FocusedCardReloadTarget?) {
    guard let target else { return }

    if cardView(at: target.fallbackIndex) == nil {
      renderCardIfNeeded(at: target.fallbackIndex)
    }
    let fallbackCard = cardView(at: target.fallbackIndex)
    let focusedCard = cardViews.first { $0.representedItemID == target.itemID } ?? fallbackCard
    guard let focusedCard else { return }
    window?.makeFirstResponder(focusedCard)
  }

  private func animateContentReloadIfNeeded(_ shouldAnimate: Bool) {
    guard shouldAnimate else { return }
    scrollView.alphaValue = Motion.contentSwitchStartAlpha
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Motion.contentSwitchDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      scrollView.animator().alphaValue = 1.0
    }
  }

  private func handleVisibleItemsChanged() {
    if defersVisualReloads {
      pendingItemReload = true
      if collectionChipsNeedRebuild {
        pendingCollectionReload = true
      }
      updateStatus(viewModel.statusMessage)
      updateResultCount()
      return
    }

    let shouldRestoreCollectionFocus = collectionChipsNeedRebuild && isCollectionChipFocused
    rebuildCollectionChipsIfNeeded()
    reloadItems()
    updateCollectionButtons()
    if shouldRestoreCollectionFocus {
      focusSelectedCollectionChip()
    }
  }

  private func handleCollectionsChanged() {
    if defersVisualReloads {
      pendingCollectionReload = true
      return
    }

    let shouldRestoreCollectionFocus = collectionChipsNeedRebuild && isCollectionChipFocused
    rebuildCollectionChipsIfNeeded()
    updateCollectionButtons()
    if shouldRestoreCollectionFocus {
      focusSelectedCollectionChip()
    }
  }

  private func handleStackChanged() {
    if defersVisualReloads {
      pendingCollectionReload = true
      updateStatus(viewModel.statusMessage)
      updateResultCount()
      return
    }

    let shouldReloadCollections = collectionChipsNeedRebuild || stackChipVisibilityNeedsRebuild
    let shouldRestoreCollectionFocus = shouldReloadCollections && isCollectionChipFocused
    if shouldReloadCollections {
      configureCollectionButtons()
    }
    updateVisibleCardStackState()
    updateSelection()
    updateCollectionButtons()
    updateStatus(viewModel.statusMessage)
    updateResultCount()
    if shouldRestoreCollectionFocus {
      focusSelectedCollectionChip()
    }
  }

  private func flushDeferredVisualReloads() {
    let shouldReloadItems = pendingItemReload
    let shouldReloadCollections = pendingCollectionReload || collectionChipsNeedRebuild
    let shouldRestoreCollectionFocus = shouldReloadCollections && isCollectionChipFocused
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
    if shouldRestoreCollectionFocus {
      focusSelectedCollectionChip()
    }
  }

  private var collectionChipsNeedRebuild: Bool {
    configuredCollectionNames != viewModel.collectionNames
      || configuredSortModes != visibleSortModesForCurrentCounts()
  }

  private var stackChipVisibilityNeedsRebuild: Bool {
    collectionStack.arrangedSubviews.contains(stackChip) != shouldShowStackChip
  }

  private var shouldShowStackChip: Bool {
    viewModel.stackCount > 0 || viewModel.isStackCaptureEnabled
  }

  private func rebuildCollectionChipsIfNeeded() {
    guard collectionChipsNeedRebuild else { return }
    configureCollectionButtons()
  }

  private func updateVisibleCardStackState() {
    for card in cardViews {
      let index = card.representedIndex
      card.setStackState(isStacked: viewModel.isItemStacked(at: index), stackCount: viewModel.stackCount)
    }
  }

  private func applyCurrentCardState(_ card: ClipboardItemCardView, index: Int, animated: Bool = false) {
    let stableHeaderRollout = animated && currentPanelLayout == .vertical
    let isVisuallyExpanded = index == visuallyExpandedCardIndex
    card.setPresentation(
      cardPresentation(at: index),
      animated: animated,
      stableHeaderRollout: stableHeaderRollout
    )
    card.setStackState(isStacked: viewModel.isItemStacked(at: index), stackCount: viewModel.stackCount)
    card.setSelectionState(
      active: isVisuallyExpanded || (currentPanelLayout != .vertical && index == viewModel.selectedIndex),
      selected: viewModel.isItemSelected(at: index),
      selectionCount: viewModel.selectedItemCount
    )
  }

  private func updateSelection() {
    renderCardIfNeeded(at: viewModel.selectedIndex)
    let shouldAnimateLayout = window != nil && cardItemCount > 0

    var activeCard: ClipboardItemCardView?
    for card in cardViews {
      let index = card.representedIndex
      applyCurrentCardState(card, index: index, animated: shouldAnimateLayout)
      if index == viewModel.selectedIndex {
        activeCard = card
      }
    }

    if cardItemCount > 0 {
      sizeItemsDocument(itemCount: cardItemCount, animated: shouldAnimateLayout)
    }

    let shouldSuppressSelectionScroll = selectionScrollSuppressionCount > 0
    if shouldSuppressSelectionScroll {
      selectionScrollSuppressionCount -= 1
    }

    if let activeCard, !shouldSuppressSelectionScroll {
      scrollCardIntoView(activeCard)
    }
    updateAddCollectionButtonState()
  }

  private func updateAddCollectionButtonState() {
    addCollectionButton.isEnabled = true
    addCollectionButton.alphaValue = 1.0
  }

  private func scrollCardIntoView(_ card: ClipboardItemCardView) {
    guard scrollView.documentView === itemsStack else { return }
    guard card.window != nil else { return }
    scrollView.layoutSubtreeIfNeeded()
    itemsStack.layoutSubtreeIfNeeded()

    let frame = cardSlotFrame(at: card.representedIndex, layout: currentCardLayout())
    let paddedFrame = currentPanelLayout == .vertical
      ? frame.insetBy(dx: 0, dy: -cardDensity.cardSpacing)
      : frame.insetBy(dx: -cardDensity.cardSpacing, dy: 0)
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
    collectionChipOrder[targetIndex].onPress(false)

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

  private func focusSelectedCollectionChip() {
    let selectedChip: CollectionChipView?
    if viewModel.isStackFilterSelected {
      selectedChip = stackChip
    } else if let collectionName = viewModel.selectedCollectionName {
      selectedChip = customCollectionButtons[collectionName]
    } else {
      selectedChip = configuredSortModes.compactMap { mode in
        viewModel.isSortModeCategorySelected(mode) ? collectionButtons[mode] : nil
      }.first
        ?? collectionButtons[viewModel.sortMode]
    }
    guard let selectedChip = selectedChip ?? collectionChipOrder.first else { return }
    collectionChipOrder.forEach { $0.clearKeyboardFocus() }
    window?.makeFirstResponder(selectedChip)
    selectedChip.setKeyboardFocusForPresentation(true)
    scrollCollectionChipIntoView(selectedChip)
  }

  private var isCollectionChipFocused: Bool {
    guard let responder = window?.firstResponder as? NSView else { return false }
    return collectionChipOrder.contains { chip in
      responder === chip || responder.isDescendant(of: chip)
    }
  }

  private func scrollCollectionChipIntoView(_ chip: NSView) {
    guard collectionScrollView.documentView === collectionDocumentView else { return }
    guard chip.window != nil else { return }
    collectionScrollView.layoutSubtreeIfNeeded()
    collectionDocumentView.layoutSubtreeIfNeeded()
    collectionStack.layoutSubtreeIfNeeded()

    let frame = chip.convert(chip.bounds, to: collectionDocumentView)
    let paddedFrame = frame.insetBy(dx: -2, dy: -Metrics.collectionSideRailGap)
    collectionDocumentView.scrollToVisible(paddedFrame)
    collectionScrollView.reflectScrolledClipView(collectionScrollView.contentView)
  }

  private func updateStatus(_ message: String) {
    let text: String
    if !message.isEmpty {
      text = message
    } else if !viewModel.captureStatusMessage.isEmpty {
      text = viewModel.captureStatusMessage
    } else if viewModel.visibleItems.isEmpty {
      text = viewModel.searchText.clipboardTrimmed.isEmpty
        ? "Capture is running. Accessibility permission is only needed for automatic paste."
        : "No clips match this search"
    } else {
      text = "Capture running"
    }
    currentStatusText = text
    currentStatusTone = statusTone(for: text)
  }

  private func statusTone(for text: String) -> StatusTone {
    let lower = text.lowercased()
    if lower.hasPrefix("captured") || lower.contains("capture running") || lower.contains("capture is running") || lower.contains("capture resumed") {
      return .ready
    }
    if lower.hasPrefix("error") || lower.contains("failed") || lower.contains("could not") {
      return .error
    }
    if lower.hasPrefix("skipped")
      || lower.contains("ignored")
      || lower.contains("paused")
      || lower.contains("grant accessibility")
      || lower.contains("not granted")
      || lower.contains("at least one")
      || lower.contains("already")
      || lower.contains("cannot be empty")
      || lower.contains("has no text")
      || lower.contains("is empty")
      || lower.contains("no changes")
      || lower.contains("no collections")
      || lower.contains("no selected")
      || lower.contains("no text")
      || lower.contains("no visible")
      || lower.contains("nothing to")
      || lower.contains("unavailable") {
      return .warning
    }
    if lower.hasPrefix("copied") || lower.hasPrefix("pasted") || lower.hasPrefix("updated") || lower.hasPrefix("renamed") || lower.hasPrefix("rotated") || lower.hasPrefix("extracted") || lower.hasPrefix("added") || lower.hasPrefix("created") || lower.hasPrefix("removed") || lower.hasPrefix("deleted") || lower.hasPrefix("restored") || lower.hasPrefix("selected") || lower.hasPrefix("exported") || lower.hasPrefix("cleared") || lower.hasPrefix("showing") || lower.hasPrefix("compact mode ") || lower.hasPrefix("stack capture is ") {
      return .action
    }
    return .neutral
  }

  private func updateResultCount() {
    let count = viewModel.visibleItems.count
    let noun = count == 1 ? "clip" : "clips"
    let text: String
    if viewModel.selectedItemCount > 1 {
      text = "\(viewModel.selectedItemCount) selected of \(count) \(noun)"
    } else if !viewModel.searchText.clipboardTrimmed.isEmpty {
      text = "\(count) \(noun) matching"
    } else {
      text = "\(count) \(noun)"
    }
    currentResultCountText = text
  }

  private func editText(at index: Int) {
    viewModel.selectItem(at: index)
    guard let currentText = viewModel.editableTextForSelected() else { return }
    #if DEBUG
    editClipRequestCountForTesting += 1
    if suppressClipEditDialogsForTesting {
      return
    }
    #endif

    let textView = Self.makePlainTextEditor(initialText: currentText)
    let accessoryView = textEditorAccessoryView(for: textView)

    let alert = NSAlert()
    alert.messageText = "Edit Text"
    alert.accessoryView = accessoryView
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = textView
    activeWritingToolsTextView = textView
    defer {
      if activeWritingToolsTextView === textView {
        activeWritingToolsTextView = nil
      }
    }

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    viewModel.updateSelectedText(to: textView.string)
  }

  func editSelectedClip() {
    editText(at: viewModel.selectedIndex)
  }

  private func renameClip(at index: Int) {
    viewModel.selectItem(at: index)
    guard let currentTitle = viewModel.editableTitleForSelected() else { return }
    #if DEBUG
    renameClipRequestCountForTesting += 1
    if suppressClipEditDialogsForTesting {
      return
    }
    #endif

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

  func renameSelectedClip() {
    renameClip(at: viewModel.selectedIndex)
  }

  private func emptyStateView() -> NSView {
    let width = currentPanelLayout == .vertical
      ? max(1, scrollView.contentView.bounds.width)
      : max(cardDensity.emptyStateMinimumWidth, scrollView.contentView.bounds.width)
    let height = max(cardDensity.railHeight, scrollView.contentView.bounds.height)
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
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

  private func sizeItemsDocument(itemCount: Int, animated: Bool = false) {
    cardLayoutAnimationGeneration += 1
    let animationGeneration = cardLayoutAnimationGeneration
    let viewportSize = scrollView.contentView.bounds.size
    let layout = currentCardLayout(viewportWidth: viewportSize.width)
    let width: CGFloat
    let height: CGFloat
    if currentPanelLayout == .vertical {
      let contentHeight = verticalCardRailContentLength(itemCount: itemCount, layout: layout)
        + (cardDensity.cardStackInset * 2)
      width = max(viewportSize.width, layout.width + (cardDensity.cardStackInset * 2))
      height = max(viewportSize.height, contentHeight)
    } else {
      let contentWidth = horizontalCardRailContentLength(itemCount: itemCount, layout: layout)
        + (cardDensity.cardStackInset * 2)
      width = max(viewportSize.width, contentWidth)
      height = currentListHeight(itemCount: itemCount, layout: layout)
    }
    lastScrollViewportSize = viewportSize
    let targetFrame = NSRect(x: 0, y: 0, width: width, height: height)
    guard animated, window != nil else {
      itemsStack.frame = targetFrame
      positionRenderedCardSlots()
      itemsStack.needsLayout = true
      itemsStack.layoutSubtreeIfNeeded()
      return
    }

    #if DEBUG
    animatedCardLayoutChangeCount += 1
    #endif

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Motion.cardExpansionDuration
      context.timingFunction = Motion.cardExpansionTiming
      itemsStack.animator().frame = targetFrame
      positionRenderedCardSlots(animated: true)
    } completionHandler: { [weak self] in
      guard let self else { return }
      guard self.cardLayoutAnimationGeneration == animationGeneration else { return }
      self.itemsStack.frame = targetFrame
      self.setRenderedCardSlotsToTargetFrames()
      self.itemsStack.needsLayout = true
      self.itemsStack.layoutSubtreeIfNeeded()
    }
  }

  private func currentListHeight(itemCount: Int, layout: ClipboardItemCardLayout) -> CGFloat {
    guard itemCount > 0 else {
      return cardDensity.railHeight
    }
    var contentHeight: CGFloat = 0
    for index in 0..<itemCount {
      contentHeight = max(contentHeight, cardPresentation(at: index).size(for: layout).height)
    }
    return contentHeight + cardDensity.cardTopInset + cardDensity.cardBottomInset
  }

  private func horizontalCardRailContentLength(itemCount: Int, layout: ClipboardItemCardLayout) -> CGFloat {
    guard itemCount > 0 else { return 0 }
    var length: CGFloat = 0
    for index in 0..<itemCount {
      if index > 0 {
        length += cardDensity.cardSpacing
      }
      length += cardPresentation(at: index).size(for: layout).width
    }
    return length
  }

  private func verticalCardRailContentLength(itemCount: Int, layout: ClipboardItemCardLayout) -> CGFloat {
    guard itemCount > 0 else { return 0 }
    var length: CGFloat = 0
    for index in 0..<itemCount {
      if index > 0 {
        length += cardDensity.cardSpacing
      }
      length += cardPresentation(at: index).size(for: layout).height
    }
    return length
  }

  private func emptyStateCopy() -> (title: String, detail: String) {
    if !viewModel.searchText.clipboardTrimmed.isEmpty {
      return (
        "No matching clips",
        "Try a broader search or switch filters."
      )
    }

    if viewModel.isStackFilterSelected {
      return viewModel.isStackCaptureEnabled
        ? ("Stack capture is on", "Copied items will appear here in order.")
        : ("Stack is empty", "Add clips manually or press Shift-Command-C to capture copies into Stack.")
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
    case .colors:
      return ("No colors yet", "Copied color swatches appear here.")
    case .links:
      return ("No links yet", "Links are detected from copied URLs.")
    case .text:
      return ("No text clips yet", "Copied text and rich text appear here.")
    case .code:
      return ("No code snippets yet", "Copied code snippets appear here.")
    case .videos:
      return ("No videos yet", "Copied movie and video clips appear here.")
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
    let counts = viewModel.collectionCountSummary()
    for (mode, chip) in collectionButtons {
      chip.setSelected(viewModel.isSortModeCategorySelected(mode))
      chip.setCount(counts.count(for: mode))
    }
    for (name, chip) in customCollectionButtons {
      chip.setSelected(viewModel.isCollectionCategorySelected(named: name))
      chip.setCount(counts.count(named: name))
    }
    stackChip.setSelected(viewModel.isStackFilterSelected)
    stackChip.setStackCaptureActive(viewModel.isStackCaptureEnabled)
    stackChip.setCount(viewModel.stackCount)
    categoryMenuButton?.isEnabled = !overflowSortModesForCurrentCounts().isEmpty
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

  override func mouseDown(with event: NSEvent) {
    collapseSearchFieldIfIdle()
    window?.makeFirstResponder(self)
    super.mouseDown(with: event)
  }

  override func layout() {
    super.layout()
    _ = updateCardDensityForCurrentWidth()
    updateCollectionRailHorizontalPosition()
    sizeCollectionDocument()

    guard !scrollView.frame.equalTo(.zero) else { return }
    let viewportSize = scrollView.contentView.bounds.size
    if viewportSize == lastScrollViewportSize {
      return
    }
    lastScrollViewportSize = viewportSize

    if cardItemCount == 0 {
      guard let documentView = scrollView.documentView else { return }
      let emptyStateWidth = currentPanelLayout == .vertical
        ? max(1, scrollView.contentView.bounds.width)
        : max(cardDensity.emptyStateMinimumWidth, scrollView.contentView.bounds.width)
      documentView.frame.size = NSSize(
        width: emptyStateWidth,
        height: max(cardDensity.railHeight, scrollView.contentView.bounds.height)
      )
      return
    }

    if let currentCardRenderContext, currentCardRenderContext.layout != currentCardLayout(viewportWidth: viewportSize.width) {
      reloadItems()
      return
    }

    sizeItemsDocument(itemCount: cardItemCount)
    renderCardsNearVisibleViewport()
  }

  private func sizeCollectionDocument(consumingScrollReset: Bool = true) {
    collectionStack.layoutSubtreeIfNeeded()
    let visibleSubviews = collectionStack.arrangedSubviews.filter { !$0.isHidden }
    let rawContentHeight = ceil(
      visibleSubviews.reduce(CGFloat(0)) { partialHeight, view in
        partialHeight + view.fittingSize.height
      }
      + CGFloat(max(0, visibleSubviews.count - 1)) * collectionStack.spacing
    )
    let targetViewportWidth = Metrics.collectionSideRailWidth
    if abs((collectionScrollWidthConstraint?.constant ?? 0) - targetViewportWidth) > 0.5 {
      collectionScrollWidthConstraint?.constant = targetViewportWidth
      shelfChromeView?.layoutSubtreeIfNeeded()
      collectionScrollView.layoutSubtreeIfNeeded()
    }
    let viewportHeight = max(1, collectionScrollView.contentView.bounds.height)
    let contentWidth = targetViewportWidth
    let currentInsets = collectionStack.edgeInsets
    if abs(currentInsets.top) > 0.5
      || abs(currentInsets.left) > 0.5
      || abs(currentInsets.bottom) > 0.5
      || abs(currentInsets.right) > 0.5 {
      collectionStack.edgeInsets = NSEdgeInsetsZero
    }
    let contentHeight = rawContentHeight
    let documentHeight = max(viewportHeight, contentHeight)
    let stackY = max(0, floor((documentHeight - contentHeight) / 2))
    collectionDocumentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: documentHeight)
    collectionStack.frame = NSRect(x: 0, y: stackY, width: contentWidth, height: contentHeight)
    let maxOffset = max(0, documentHeight - viewportHeight)
    let currentOrigin = collectionScrollView.contentView.bounds.origin
    let targetY: CGFloat
    if resetCollectionScrollPositionOnNextLayout {
      targetY = 0
      if consumingScrollReset {
        resetCollectionScrollPositionOnNextLayout = false
      }
    } else {
      targetY = min(max(currentOrigin.y, 0), maxOffset)
    }
    if abs(currentOrigin.y - targetY) > 0.5 || abs(currentOrigin.x) > 0.5 {
      collectionScrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
      collectionScrollView.reflectScrolledClipView(collectionScrollView.contentView)
    }
  }

  private func updateCollectionRailHorizontalPosition() {
    guard currentPanelLayout == .vertical else {
      collectionRailLeadingConstraint?.constant = 0
      return
    }
    guard let contentStack else { return }

    contentStack.layoutSubtreeIfNeeded()
    scrollView.layoutSubtreeIfNeeded()

    let railWidth = Metrics.collectionSideRailWidth
    let viewportWidth = max(1, scrollView.contentView.bounds.width)
    let layout = currentCardLayout(viewportWidth: viewportWidth)
    let cardMinXInContent = verticalCardMinXInContent(width: layout.width, viewportWidth: viewportWidth)
    let contentMinXInPanel = contentStack.convert(contentStack.bounds, to: self).minX
    let cardMinXInPanel = contentMinXInPanel + cardMinXInContent
    let desiredMidXInPanel = cardMinXInPanel / 2
    let centeredLeading = desiredMidXInPanel - contentMinXInPanel - (railWidth / 2)
    let maximumLeadingBeforeCard = cardMinXInContent - railWidth - Metrics.collectionRailCardClearance
    let targetLeading = max(0, min(centeredLeading, maximumLeadingBeforeCard))

    if abs((collectionRailLeadingConstraint?.constant ?? 0) - targetLeading) > 0.5 {
      collectionRailLeadingConstraint?.constant = targetLeading
      contentStack.layoutSubtreeIfNeeded()
      collectionScrollView.layoutSubtreeIfNeeded()
    }
  }

  private func updateSearchFieldPresentation(animated: Bool = true) {
    let hasSearchText = !searchField.stringValue.isEmpty
    let isActive = hasSearchText
      || searchFieldPresentationRequested
      || searchField.hasKeyboardFocusForPresentation
      || (isSearchFieldEditing && !searchFieldCollapsedWhileIdle)
    let expandedWidth: CGFloat = currentPanelLayout == .vertical
      ? Metrics.verticalExpandedSearchWidth
      : Metrics.expandedSearchWidth
    let targetWidth: CGFloat = isActive ? expandedWidth : Metrics.searchControlSize
    let wasActive = searchFieldPresentationIsExpanded
    let widthChanged = searchFieldWidthConstraint.map { abs($0.constant - targetWidth) > 0.5 } ?? false
    let visibilityChanged = wasActive != isActive
      || searchField.isHidden == isActive
      || searchIconButton.isHidden == isActive
    searchFieldPresentationIsExpanded = isActive
    searchField.placeholderAttributedString = NSAttributedString(
      string: isActive ? "Search clips" : "",
      attributes: [
        .foregroundColor: NSColor.tertiaryLabelColor
      ]
    )

    guard animated, window != nil, widthChanged || visibilityChanged else {
      searchFieldWidthConstraint?.constant = targetWidth
      searchField.alphaValue = isActive ? 1 : 0
      searchIconButton.alphaValue = isActive ? 0 : 1
      searchField.isHidden = !isActive
      searchIconButton.isHidden = isActive
      needsLayout = true
      shelfChromeView?.needsLayout = true
      headerStack?.needsLayout = true
      sizeCollectionDocument(consumingScrollReset: false)
      return
    }

    searchField.isHidden = false
    searchIconButton.isHidden = false
    searchField.alphaValue = wasActive ? 1 : 0
    searchIconButton.alphaValue = wasActive ? 0 : 1
    shelfChromeView?.layoutSubtreeIfNeeded()
    headerStack?.layoutSubtreeIfNeeded()
    layoutSubtreeIfNeeded()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Motion.searchFieldResizeDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      searchFieldWidthConstraint?.animator().constant = targetWidth
      searchField.animator().alphaValue = isActive ? 1 : 0
      searchIconButton.animator().alphaValue = isActive ? 0 : 1
      shelfChromeView?.layoutSubtreeIfNeeded()
      headerStack?.layoutSubtreeIfNeeded()
      layoutSubtreeIfNeeded()
    } completionHandler: { [weak self] in
      guard let self, self.searchFieldPresentationIsExpanded == isActive else { return }
      self.searchFieldWidthConstraint?.constant = targetWidth
      self.searchField.alphaValue = isActive ? 1 : 0
      self.searchIconButton.alphaValue = isActive ? 0 : 1
      self.searchField.isHidden = !isActive
      self.searchIconButton.isHidden = isActive
      self.sizeCollectionDocument(consumingScrollReset: false)
    }
  }

  private func collapseSearchFieldIfIdle() {
    guard searchField.stringValue.isEmpty else {
      updateSearchFieldPresentation()
      return
    }
    searchFieldPresentationRequested = false
    searchFieldCollapsedWhileIdle = true
    searchField.setKeyboardFocusForPresentation(false)
    updateSearchFieldPresentation()
  }

  func focusSearchField() {
    searchFieldPresentationRequested = true
    searchFieldCollapsedWhileIdle = false
    searchField.setKeyboardFocusForPresentation(true)
    updateSearchFieldPresentation()
    _ = window?.makeFirstResponder(searchField)
  }

  @discardableResult
  func focusSearchOrShowFilters() -> Bool {
    focusSearchField()
    return false
  }

  @discardableResult
  func clearSearchForKeyboardCancel() -> Bool {
    guard !searchField.stringValue.isEmpty else { return false }
    searchField.stringValue = ""
    updateSearchText()
    focusSearchField()
    return true
  }

  private func startSearchFromShelf(_ text: String) {
    guard !text.isEmpty else { return }
    focusSearchField()
    let current = searchField.stringValue.clipboardTrimmed
    searchField.stringValue = current.isEmpty ? text : "\(current) \(text)"
    updateSearchText()
  }

  func setBottomSafeInset(_ inset: CGFloat) {
    bottomSafeInset = max(Metrics.minimumBottomInset, inset)
    mainStack?.edgeInsets = contentInsets()
    needsLayout = true
  }

  var visibleCardPageStep: Int {
    let layout = currentCardLayout()
    let span = currentPanelLayout == .vertical
      ? layout.height + layout.activeLift + cardDensity.cardSpacing
      : layout.width + cardDensity.cardSpacing
    let visibleExtent = currentPanelLayout == .vertical
      ? scrollView.contentView.bounds.height
      : scrollView.contentView.bounds.width
    guard span > 0 else { return 1 }
    return max(1, Int(floor(visibleExtent / span)))
  }

  func focusSelectedCardForKeyboardNavigation() {
    claimKeyboardCardSelection()
    focusSelectedCard()
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    if let text = shelfSearchText(from: event) {
      startSearchFromShelf(text)
    } else {
      super.keyDown(with: event)
    }
  }

  func prepareForShow() {
    if !searchField.stringValue.isEmpty {
      searchField.stringValue = ""
      updateSearchText()
    }
    collapseSearchFieldIfIdle()
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

  var debugCardSlotCount: Int {
    cardSlots.count
  }

  var debugCardItemCount: Int {
    cardItemCount
  }

  var debugLastSynchronousCardRenderCount: Int {
    lastSynchronousCardRenderCount
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

  var debugPanelMaterial: NSVisualEffectView.Material {
    material
  }

  var debugPanelSurfaceAlpha: CGFloat {
    Self.debugAlpha(layer?.backgroundColor)
  }

  var debugPanelBorderAlpha: CGFloat {
    Self.debugAlpha(layer?.borderColor)
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

  var debugSelectedCardIndexes: [Int] {
    cardViews.enumerated().compactMap { index, card in
      card.debugIsSelected ? index : nil
    }
  }

  var debugActiveCardIndexes: [Int] {
    cardViews.enumerated().compactMap { index, card in
      card.debugIsActiveSelection ? index : nil
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

  var debugCardTextPreviewChromes: [String] {
    cardViews.map(\.debugTextPreviewChrome)
  }

  var debugCardTextPreviewAccentHexes: [String] {
    cardViews.map(\.debugTextPreviewAccentHex)
  }

  var debugCardTextPreviewFadePlacements: [String] {
    cardViews.map(\.debugTextPreviewFadePlacement)
  }

  var debugCardPreviewStyles: [String] {
    cardViews.map(\.debugPreviewStyle)
  }

  var debugCardDensity: String {
    cardDensity.rawValue
  }

  var debugPanelLayout: String {
    currentPanelLayout.title
  }

  var debugResizeHandleIsHidden: Bool {
    true
  }

  var debugItemsStackOrientation: NSUserInterfaceLayoutOrientation {
    itemsStack.orientation
  }

  private var debugToolbarButtons: [NSButton] {
    [categoryMenuButton, clearHistoryButton, settingsButton].compactMap { $0 }
  }

  var debugToolbarButtonAccessibilityLabels: [String] {
    debugToolbarButtons.compactMap { $0.accessibilityLabel() }
  }

  var debugToolbarButtonAccessibilityHelps: [String] {
    debugToolbarButtons.compactMap { $0.accessibilityHelp() }
  }

  var debugUtilityToolbarGroupBackgroundAlpha: CGFloat {
    Self.debugAlpha(utilityToolbarGroup?.layer?.backgroundColor)
  }

  var debugUtilityToolbarGroupCornerRadius: CGFloat {
    utilityToolbarGroup?.layer?.cornerRadius ?? 0
  }

  var debugToolbarButtonBackgroundAlphas: [CGFloat] {
    debugToolbarButtons.map { Self.debugAlpha($0.layer?.backgroundColor) }
  }

  var debugToolbarButtonBorderWidths: [CGFloat] {
    debugToolbarButtons.map { $0.layer?.borderWidth ?? 0 }
  }

  var debugSearchFieldAccessibilityHelp: String {
    searchField.accessibilityHelp() ?? ""
  }

  var debugSearchFilterButtonAccessibilityHelp: String {
    ""
  }

  var debugAddCollectionButtonAccessibilityHelp: String {
    addCollectionButton.accessibilityHelp() ?? ""
  }

  var debugCompactModeButtonAccessibilityValue: String {
    ""
  }

  func debugToggleCompactMode() {
    toggleCompactMode()
  }

  var debugCardSizes: [NSSize] {
    cardViews.map { $0.frame.size }
  }

  var debugCardHeaderFramesInPanel: [NSRect] {
    cardViews.map { card in
      card.convert(card.debugHeaderFrame, to: self)
    }
  }

  var debugFirstCardHeaderMaskedCorners: CACornerMask {
    cardViews.first?.debugHeaderMaskedCorners ?? []
  }

  var debugCardExpandedDetailFramesInPanel: [NSRect] {
    cardViews.map { card in
      card.convert(card.debugExpandedDetailFrame, to: self)
    }
  }

  var debugCardExpandedDetailPresentationHeights: [CGFloat] {
    cardViews.map(\.debugExpandedDetailPresentationHeight)
  }

  var debugCardSlotPresentationFramesInPanel: [NSRect] {
    cardSlots.keys.sorted().compactMap { index in
      guard let slot = cardSlots[index],
            let superview = slot.superview else {
        return nil
      }
      return superview.convert(slot.debugPresentationFrame, to: self)
    }
  }

  var debugCardContentCornerRadii: [CGFloat] {
    cardViews.map(\.debugContentCornerRadius)
  }

  var debugCardContentBackgroundAlphas: [CGFloat] {
    cardViews.map(\.debugContentBackgroundAlpha)
  }

  var debugCardPresentations: [String] {
    cardViews.map(\.debugPresentation)
  }

  var debugCardAnimatedPresentationChangeCounts: [Int] {
    cardViews.map(\.debugAnimatedPresentationChangeCount)
  }

  var debugCardHeaderBadgeSymbols: [String] {
    cardViews.map(\.debugHeaderBadgeSymbol)
  }

  var debugCardHeaderBadgeTexts: [String] {
    cardViews.map(\.debugHeaderBadgeText)
  }

  var debugCardCompactMetricTexts: [String] {
    cardViews.map(\.debugCompactMetricText)
  }

  var debugCardCompactMetricHiddenStates: [Bool] {
    cardViews.map(\.debugCompactMetricIsHidden)
  }

  var debugCardCompactMetricFramesInPanel: [NSRect] {
    cardViews.map { card in
      card.convert(card.debugCompactMetricFrame, to: self)
    }
  }

  var debugCardCompactMetricFittingWidths: [CGFloat] {
    cardViews.map(\.debugCompactMetricFittingWidth)
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

  var debugFirstCardLinkPreviewChrome: String {
    cardViews.first?.debugLinkPreviewChrome ?? ""
  }

  var debugFirstCardLinkPreviewHostText: String {
    cardViews.first?.debugLinkPreviewHostText ?? ""
  }

  var debugFirstCardLinkPreviewMonogram: String {
    cardViews.first?.debugLinkPreviewMonogram ?? ""
  }

  var debugFirstCardLinkPreviewAccentHex: String {
    cardViews.first?.debugLinkPreviewAccentHex ?? ""
  }

  var debugFirstCardLinkPreviewHeroHeight: CGFloat {
    cardViews.first?.debugLinkPreviewHeroHeight ?? 0
  }

  var debugFirstCardLinkMediaPreviewChrome: String {
    cardViews.first?.debugLinkMediaPreviewChrome ?? ""
  }

  var debugFirstCardLinkMediaPreviewImageHeight: CGFloat {
    cardViews.first?.debugLinkMediaPreviewImageHeight ?? 0
  }

  var debugFirstCardLinkMediaPreviewHostText: String {
    cardViews.first?.debugLinkMediaPreviewHostText ?? ""
  }

  var debugFirstCardFilePreviewChrome: String {
    cardViews.first?.debugFilePreviewChrome ?? ""
  }

  var debugFirstCardFilePreviewExtensionText: String {
    cardViews.first?.debugFilePreviewExtensionText ?? ""
  }

  var debugFirstCardFilePreviewLocationPlacement: String {
    cardViews.first?.debugFilePreviewLocationPlacement ?? ""
  }

  var debugFirstCardFilePreviewCoverSize: NSSize {
    cardViews.first?.debugFilePreviewCoverSize ?? .zero
  }

  var debugFirstCardColorPreviewChrome: String {
    cardViews.first?.debugColorPreviewChrome ?? ""
  }

  var debugFirstCardColorPreviewHexText: String {
    cardViews.first?.debugColorPreviewHexText ?? ""
  }

  var debugFirstCardColorPreviewSwatchPlacement: String {
    cardViews.first?.debugColorPreviewSwatchPlacement ?? ""
  }

  var debugFirstCardColorPreviewChipSize: NSSize {
    cardViews.first?.debugColorPreviewChipSize ?? .zero
  }

  var debugFirstCardMediaMetricText: String {
    cardViews.first?.debugMediaMetricText ?? ""
  }

  var debugFirstCardMediaMetricPlacement: String {
    cardViews.first?.debugMediaMetricPlacement ?? ""
  }

  var debugFirstCardAudioPreviewChrome: String {
    cardViews.first?.debugAudioPreviewChrome ?? ""
  }

  var debugFirstCardAudioArtworkSize: CGFloat {
    cardViews.first?.debugAudioArtworkSize ?? 0
  }

  var debugFirstCardAudioLabelPlacement: String {
    cardViews.first?.debugAudioLabelPlacement ?? ""
  }

  var debugFirstCardVideoPreviewChrome: String {
    cardViews.first?.debugVideoPreviewChrome ?? ""
  }

  var debugFirstCardVideoFrameHeight: CGFloat {
    cardViews.first?.debugVideoFrameHeight ?? 0
  }

  var debugFirstCardVideoFormatPlacement: String {
    cardViews.first?.debugVideoFormatPlacement ?? ""
  }

  var debugQuickPasteBadgeTexts: [String] {
    cardViews.compactMap(\.debugQuickPasteBadgeText)
  }

  var debugSelectedCardFrameInDocument: NSRect {
    guard viewModel.selectedIndex >= 0, viewModel.selectedIndex < cardItemCount else {
      return .zero
    }
    renderCardIfNeeded(at: viewModel.selectedIndex)
    guard cardView(at: viewModel.selectedIndex) != nil else { return .zero }
    return cardSlotFrame(at: viewModel.selectedIndex, layout: currentCardLayout())
  }

  var debugSelectedCardFrameInPanel: NSRect {
    guard viewModel.selectedIndex >= 0, viewModel.selectedIndex < cardItemCount else {
      return .zero
    }
    renderCardIfNeeded(at: viewModel.selectedIndex)
    guard cardView(at: viewModel.selectedIndex) != nil else { return .zero }
    return itemsStack.convert(cardSlotFrame(at: viewModel.selectedIndex, layout: currentCardLayout()), to: self)
  }

  var debugSelectedCardVisualTopInset: CGFloat {
    let frame = debugSelectedCardFrameInPanel
    return currentPanelLayout == .vertical ? frame.minY : bounds.maxY - frame.maxY
  }

  var debugCardRailVisibleRect: NSRect {
    scrollView.contentView.bounds
  }

  var debugCardRailTopGap: CGFloat {
    bounds.maxY - scrollView.frame.maxY
  }

  var debugCardRailDocumentWidth: CGFloat {
    scrollView.documentView?.frame.width ?? 0
  }

  var debugCardRailDocumentHeight: CGFloat {
    scrollView.documentView?.frame.height ?? 0
  }

  var debugVisibleCardPageStep: Int {
    visibleCardPageStep
  }

  var debugCardRailOverflowFadeVisibility: [Bool] {
    scrollView.overflowFadeVisibility
  }

  var debugCardRailOverflowFadeWidth: CGFloat {
    scrollView.overflowFadeWidth
  }

  func debugScrollCardRailVertically(deltaY: CGFloat) {
    if currentPanelLayout == .vertical {
      scrollView.scrollVerticallyByVerticalDelta(deltaY)
    } else {
      scrollView.scrollHorizontallyByVerticalDelta(deltaY)
    }
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

  func debugCardVisibleActionLabels(at index: Int) -> [String] {
    cardViews.first { $0.representedIndex == index }?.debugVisibleActionLabels ?? []
  }

  var debugFirstCardVisibleActionRailWidth: CGFloat {
    cardViews.first?.debugVisibleActionRailWidth ?? 0
  }

  var debugConstructedActionButtonCount: Int {
    cardViews.reduce(0) { $0 + $1.debugConstructedActionButtonCount }
  }

  var debugFirstCardShadowOpacity: Float {
    cardViews.first?.debugShadowOpacity ?? 0
  }

  var debugFirstCardShadowRadius: CGFloat {
    cardViews.first?.debugShadowRadius ?? 0
  }

  var debugFirstCardLayerTranslationY: CGFloat {
    cardViews.first?.debugLayerTranslationY ?? 0
  }

  var debugFirstCardSlotTopOffset: CGFloat {
    cardSlots[0]?.debugCardTopOffset ?? 0
  }

  var debugSecondCardSlotTopOffset: CGFloat {
    cardSlots[1]?.debugCardTopOffset ?? 0
  }

  var debugFirstCardSlotZPosition: CGFloat {
    cardSlots[0]?.debugZPosition ?? 0
  }

  var debugSecondCardSlotZPosition: CGFloat {
    cardSlots[1]?.debugZPosition ?? 0
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

  var debugFirstCardHeaderBadgeContentFrame: NSRect {
    cardViews.first?.debugHeaderBadgeContentFrame ?? .zero
  }

  var debugFirstCardHeaderBadgeMaskedCorners: CACornerMask {
    cardViews.first?.debugHeaderBadgeMaskedCorners ?? []
  }

  var debugFirstCardHeaderBadgeCornerRadius: CGFloat {
    cardViews.first?.debugHeaderBadgeCornerRadius ?? 0
  }

  var debugFirstCardHeaderBadgeShadowOpacity: Float {
    cardViews.first?.debugHeaderBadgeShadowOpacity ?? 0
  }

  var debugFirstCardHeaderBadgeShadowRadius: CGFloat {
    cardViews.first?.debugHeaderBadgeShadowRadius ?? 0
  }

  var debugFirstCardHeaderBadgeBorderWidth: CGFloat {
    cardViews.first?.debugHeaderBadgeBorderWidth ?? 0
  }

  var debugStackCornerLabels: [String] {
    cardViews.map(\.debugStackCornerLabel)
  }

  var debugCardObjectIdentifiers: [ObjectIdentifier] {
    cardViews.map(ObjectIdentifier.init)
  }

  var debugHoveredCardIndexes: [Int] {
    cardViews.filter(\.debugIsHovered).map(\.representedIndex)
  }

  var debugCardSelectionInputSource: String {
    switch cardSelectionInputSource {
    case .keyboard:
      return "keyboard"
    case .mouse:
      return "mouse"
    }
  }

  var debugAnimatedCardLayoutChangeCount: Int {
    animatedCardLayoutChangeCount
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

  func debugPerformFirstCardMenuItem(titled title: String) {
    cardViews.first?.debugPerformMenuItem(titled: title)
  }

  func debugPerformFirstCardCaptureRuleMenuItem(titled title: String) {
    cardViews.first?.debugPerformCaptureRuleMenuItem(titled: title)
  }

  var debugResultCountText: String {
    currentResultCountText
  }

  var debugStatusText: String {
    currentStatusText
  }

  var debugStatusBarIsVisible: Bool {
    false
  }

  var debugStatusTone: String {
    currentStatusTone.rawValue
  }

  var debugCollectionTitles: [String] {
    configuredSortModes.compactMap { collectionButtons[$0]?.titleText }
  }

  var debugCollectionLeadingSymbols: [String] {
    configuredSortModes.compactMap { collectionButtons[$0]?.debugLeadingSymbolName }
  }

  var debugCollectionChipWidths: [CGFloat] {
    configuredSortModes.compactMap { collectionButtons[$0]?.debugFrameWidth }
  }

  var debugCollectionChipLabelHiddenStates: [Bool] {
    configuredSortModes.compactMap { collectionButtons[$0]?.debugLabelIsHidden }
  }

  var debugCollectionChipCountLabelHiddenStates: [Bool] {
    configuredSortModes.compactMap { collectionButtons[$0]?.debugCountLabelIsHidden }
  }

  var debugCollectionStackOrientation: NSUserInterfaceLayoutOrientation {
    collectionStack.orientation
  }

  var debugSelectedCollectionTitle: String? {
    if stackChip.isSelected {
      return stackChip.titleText
    }
    if let custom = customCollectionButtons.first(where: { $0.value.isSelected }) {
      return custom.value.titleText
    }
    if let mode = configuredSortModes.first(where: { viewModel.isSortModeCategorySelected($0) }) {
      return collectionButtons[mode]?.titleText ?? collectionTitle(for: mode)
    }
    return nil
  }

  var debugSelectedSortCollectionTitles: [String] {
    configuredSortModes.compactMap { mode in
      viewModel.isSortModeCategorySelected(mode) ? collectionTitle(for: mode) : nil
    }
  }

  var debugCollectionCounts: [Int] {
    updateCollectionButtons()
    return configuredSortModes.compactMap { collectionButtons[$0]?.count }
  }

  var debugCollectionCountLabelHiddenStates: [Bool] {
    updateCollectionButtons()
    return configuredSortModes.compactMap { collectionButtons[$0]?.debugCountLabelIsHidden }
  }

  var debugCollectionChipAccessibilityLabels: [String] {
    updateCollectionButtons()
    return configuredSortModes.compactMap { collectionButtons[$0]?.accessibilityLabel() }
  }

  var debugCollectionChipAccessibilityHelps: [String] {
    updateCollectionButtons()
    return configuredSortModes.compactMap { collectionButtons[$0]?.accessibilityHelp() }
  }

  var debugCollectionChipAcceptsFirstResponder: [Bool] {
    configuredSortModes.compactMap { collectionButtons[$0]?.acceptsFirstResponder }
  }

  var debugKeyboardFocusedCollectionTitles: [String] {
    collectionChipOrder.compactMap { $0.debugIsKeyboardFocused ? $0.titleText : nil }
  }

  func debugFocusCollectionChip(_ mode: ClipboardSortMode) -> Bool {
    guard let chip = collectionButtons[mode] else { return false }
    return window?.makeFirstResponder(chip) ?? false
  }

  func debugFocusCustomCollectionChip(named name: String) -> Bool {
    guard let chip = customCollectionButtons[name] else { return false }
    return window?.makeFirstResponder(chip) ?? false
  }

  func debugFocusCard(at index: Int) -> Bool {
    guard index >= 0, index < cardItemCount else { return false }
    renderCardIfNeeded(at: index)
    guard let card = cardView(at: index) else { return false }
    return window?.makeFirstResponder(card) ?? false
  }

  func debugHoverCard(at index: Int) {
    guard index >= 0, index < cardItemCount else { return }
    renderCardIfNeeded(at: index)
    hoverSelectionRequiresFreshMouseMovement = false
    hoverSelectionKeyboardBarrierLocation = nil
    cardView(at: index)?.debugSetHovered(true)
  }

  func debugHoverCard(at index: Int, mouseLocationInPanel location: NSPoint) {
    guard index >= 0, index < cardItemCount else { return }
    renderCardIfNeeded(at: index)
    hoverSelectionRequiresFreshMouseMovement = false
    hoverSelectionKeyboardBarrierLocation = nil
    cardView(at: index)?.debugSetHovered(true, mouseLocation: convert(location, to: nil))
  }

  func debugUnhoverCard(at index: Int) {
    guard index >= 0, index < cardItemCount else { return }
    renderCardIfNeeded(at: index)
    cardView(at: index)?.debugSetHovered(false)
  }

  func debugRefreshHoverCardWithoutMouseMovement(at index: Int) {
    guard index >= 0, index < cardItemCount else { return }
    renderCardIfNeeded(at: index)
    cardView(at: index)?.debugSetHovered(true)
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

  func debugPressFocusedResponderKeyCode(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
    debugPressFocusedResponder(characters: "", keyCode: keyCode, modifiers: modifiers)
  }

  func debugTypeFocusedResponder(_ characters: String, keyCode: UInt16) {
    debugPressFocusedResponder(characters: characters, keyCode: keyCode)
  }

  func debugSetSearchFieldText(_ text: String) {
    searchField.stringValue = text
    updateSearchText()
  }

  private func debugPressFocusedResponder(
    characters: String,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = []
  ) {
    guard let window,
          let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
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

  var debugStackChipMenuTitles: [String] {
    stackChip.debugMenuTitles
  }

  var debugStackChipAccessibilityHelp: String? {
    updateCollectionButtons()
    return stackChip.accessibilityHelp()
  }

  func debugAddVisibleClipsToStackFromStackChip() {
    stackChip.debugPerformMenuItem(titled: "Add Visible Clips to Stack")
  }

  func debugToggleStackCaptureFromStackChip() {
    let title = viewModel.isStackCaptureEnabled ? "Stop Stack Capture" : "Start Stack Capture"
    stackChip.debugPerformMenuItem(titled: title)
  }

  func debugPressStackChip() {
    stackChip.onPress(false)
  }

  func debugMouseDownCollectionChip(_ mode: ClipboardSortMode) {
    collectionButtons[mode]?.debugMouseDown()
  }

  func debugHoverCollectionChip(_ mode: ClipboardSortMode) {
    collectionButtons[mode]?.debugSetHovered(true)
  }

  func debugUnhoverCollectionChip(_ mode: ClipboardSortMode) {
    collectionButtons[mode]?.debugSetHovered(false)
  }

  func debugCommandMouseDownCollectionChip(_ mode: ClipboardSortMode) {
    collectionButtons[mode]?.debugCommandMouseDown()
  }

  var debugCategoryMenuTitles: [String] {
    categoryMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  func debugPerformCategoryMenuItem(_ mode: ClipboardSortMode, extending: Bool = false) {
    if extending {
      viewModel.selectSortMode(mode, extending: true)
      return
    }
    let menu = categoryMenu()
    guard let item = menu.items.first(where: { $0.representedObject as? Int == mode.rawValue }) else { return }
    _ = item.target?.perform(item.action, with: item)
  }

  var debugClearHistoryMenuTitles: [String] {
    clearHistoryMenu().items.map { $0.title }
  }

  func debugPerformClearHistoryMenuItem(titled title: String) {
    let menu = clearHistoryMenu()
    guard let item = menu.items.first(where: { $0.title == title }) else { return }
    _ = item.target?.perform(item.action, with: item)
  }

  func debugMouseDownCustomCollectionChip(named name: String) {
    customCollectionButtons[name]?.debugMouseDown()
  }

  func debugHoverCustomCollectionChip(named name: String) {
    customCollectionButtons[name]?.debugSetHovered(true)
  }

  func debugUnhoverCustomCollectionChip(named name: String) {
    customCollectionButtons[name]?.debugSetHovered(false)
  }

  func debugCommandMouseDownCustomCollectionChip(named name: String) {
    customCollectionButtons[name]?.debugCommandMouseDown()
  }

  var debugCollectionRailVisibleWidth: CGFloat {
    collectionScrollView.contentView.bounds.width
  }

  var debugCollectionRailFrameInPanel: NSRect {
    collectionScrollView.convert(collectionScrollView.bounds, to: self)
  }

  var debugCollectionRailHasHorizontalScroller: Bool {
    collectionScrollView.hasHorizontalScroller
  }

  var debugCollectionRailHeight: CGFloat {
    collectionScrollView.frame.height
  }

  var debugCollectionRailDocumentWidth: CGFloat {
    collectionScrollView.documentView?.frame.width ?? 0
  }

  var debugCollectionRailDocumentMinX: CGFloat {
    collectionScrollView.documentView?.frame.minX ?? 0
  }

  var debugCollectionRailVisibleRect: NSRect {
    collectionScrollView.contentView.bounds
  }

  var debugCollectionRailContentTopInset: CGFloat {
    collectionStack.frame.minY
  }

  var debugCollectionRailContentFrameInPanel: NSRect {
    collectionStack.convert(collectionStack.bounds, to: self)
  }

  var debugCollectionRailOverflowFadeVisibility: [Bool] {
    collectionScrollView.overflowFadeVisibility
  }

  var debugCollectionRailOverflowFadeWidth: CGFloat {
    collectionScrollView.overflowFadeWidth
  }

  func debugScrollCollectionRailVertically(deltaY: CGFloat) {
    collectionScrollView.scrollVerticallyByVerticalDelta(deltaY)
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

  func debugSetTextClipProvider(_ provider: @escaping () -> String?) {
    textClipProviderForTesting = provider
  }

  func debugSuppressClipEditDialogs(_ suppress: Bool = true) {
    suppressClipEditDialogsForTesting = suppress
  }

  func debugSuppressClipOpenActions(_ suppress: Bool = true) {
    suppressClipOpenActionsForTesting = suppress
  }

  var debugRenameClipRequestCount: Int {
    renameClipRequestCountForTesting
  }

  var debugEditClipRequestCount: Int {
    editClipRequestCountForTesting
  }

  var debugOpenClipRequestCount: Int {
    openClipRequestCountForTesting
  }

  var debugShowInClipboardRequestCount: Int {
    showInClipboardRequestCountForTesting
  }

  func debugPressAddCollectionButton() {
    createCollectionFromToolbar()
  }

  func debugCreateTextClipFromToolbar() {
    createTextClipFromToolbar()
  }

  func debugCustomCollectionMenuTitles(named collectionName: String) -> [String] {
    customCollectionButtons[collectionName]?.debugMenuTitles ?? []
  }

  func debugCustomCollectionAccessibilityHelp(named collectionName: String) -> String? {
    updateCollectionButtons()
    return customCollectionButtons[collectionName]?.accessibilityHelp()
  }

  func debugEditCollection(named collectionName: String, to newName: String, colorHex: String) {
    viewModel.updateCollection(named: collectionName, to: newName, colorHex: colorHex)
    focusSelectedCollectionChip()
  }

  func debugDeleteCollection(named collectionName: String) {
    viewModel.deleteCollection(named: collectionName)
    focusSelectedCollectionChip()
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

  var debugSearchFieldWidth: CGFloat {
    searchFieldWidthConstraint?.constant ?? searchControlContainer.frame.width
  }

  var debugSearchControlHeight: CGFloat {
    searchControlContainer.frame.height
  }

  var debugSearchIconButtonHeight: CGFloat {
    min(searchIconButton.frame.height, searchControlContainer.bounds.height)
  }

  var debugSearchAnimationDuration: TimeInterval {
    Motion.searchFieldResizeDuration
  }

  var debugCardExpansionAnimationDuration: TimeInterval {
    Motion.cardExpansionDuration
  }

  var debugSearchFieldSharesAnimatedContainerWithIcon: Bool {
    searchField.superview === searchControlContainer
      && searchIconButton.superview === searchControlContainer
      && searchControlContainer.superview === shelfChromeView
      && searchField.superview !== shelfChromeView
      && searchIconButton.superview !== shelfChromeView
  }

  var debugSearchFieldPlaceholderText: String {
    searchField.placeholderAttributedString?.string ?? searchField.placeholderString ?? ""
  }

  var debugSearchFieldIsVisible: Bool {
    !searchField.isHidden
  }

  var debugSearchIconButtonIsVisible: Bool {
    !searchIconButton.isHidden
  }

  var debugSearchFilterMenuPresentationCount: Int {
    0
  }

  func debugSuppressSearchFilterMenuPresentation(_ suppress: Bool = true) {
  }

  var debugSearchFilterMenuTitles: [String] {
    searchFilterMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  func debugSearchFilterSubmenuTitles(named title: String) -> [String] {
    searchFilterMenu().items.first { $0.title == title }?.submenu?.items.map {
      $0.isSeparatorItem ? "-" : $0.title
    } ?? []
  }

  func debugSearchFilterSubmenuTokens(named title: String, now: Date) -> [String] {
    searchFilterMenu(now: now).items.first { $0.title == title }?.submenu?.items.compactMap {
      $0.representedObject as? String
    } ?? []
  }

  func debugPerformSearchFilterMenuItem(titled title: String, inSubmenu submenuTitle: String? = nil) {
    let menu = searchFilterMenu()
    let item: NSMenuItem?
    if let submenuTitle {
      item = menu.items.first { $0.title == submenuTitle }?.submenu?.items.first { $0.title == title }
    } else {
      item = menu.items.first { $0.title == title }
    }
    guard let item else { return }
    _ = item.target?.perform(item.action, with: item)
  }

  func debugApplySearchFilterToken(_ token: String) {
    applySearchFilterToken(token)
  }

  var debugShelfChromeRowCount: Int {
    headerStack?.arrangedSubviews.count ?? 0
  }

  var debugShelfChromeContainsSearchAndCollections: Bool {
    guard let shelfChromeView else { return false }
    return searchControlContainer.superview === shelfChromeView
      && collectionScrollView.superview === shelfChromeView
  }

  var debugShelfChromeContainsSearchAndActions: Bool {
    guard let shelfChromeView else { return false }
    return searchControlContainer.superview === shelfChromeView
      && utilityToolbarGroup?.superview === shelfChromeView
      && collectionScrollView.superview !== shelfChromeView
  }

  var debugCollectionRailIsBesideCardRail: Bool {
    collectionScrollView.superview === contentStack && scrollView.superview === contentStack
  }

  func debugDropFirstCard(onCollectionNamed collectionName: String) {
    guard let itemID = cardViews.first?.debugItemID else { return }
    customCollectionButtons[collectionName]?.debugDropItem(itemID)
  }

  private static func debugAlpha(_ cgColor: CGColor?) -> CGFloat {
    guard let cgColor, let color = NSColor(cgColor: cgColor) else { return 0 }
    return (color.usingColorSpace(.deviceRGB) ?? color).alphaComponent
  }

  var debugCustomCollectionDropTargets: [String] {
    viewModel.collectionNames.filter { customCollectionButtons[$0]?.debugAcceptsItemDrops == true }
  }

  #endif

  func controlTextDidChange(_ notification: Notification) {
    guard notification.object as? NSSearchField === searchField else { return }
    updateSearchText()
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    guard notification.object as? NSSearchField === searchField else { return }
    searchFieldPresentationRequested = true
    searchFieldCollapsedWhileIdle = false
    searchField.setKeyboardFocusForPresentation(true)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard notification.object as? NSSearchField === searchField else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isSearchFieldEditing else { return }
      self.searchFieldPresentationRequested = false
      self.searchFieldCollapsedWhileIdle = self.searchField.stringValue.isEmpty
      self.searchField.setKeyboardFocusForPresentation(false)
      self.updateSearchFieldPresentation()
    }
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
      claimKeyboardCardSelection()
      viewModel.moveSelection(-1)
      return true
    case #selector(NSResponder.moveDown(_:)):
      claimKeyboardCardSelection()
      viewModel.moveSelection(1)
      return true
    default:
      return false
    }
  }

  @objc private func searchFieldChanged() {
    updateSearchText()
  }

  #if DEBUG
  @objc private func applySearchFilterFromMenu(_ sender: NSMenuItem) {
    guard let token = sender.representedObject as? String else { return }
    applySearchFilterToken(token)
  }
  #endif

  private func updateSearchText() {
    if !searchField.stringValue.isEmpty {
      searchFieldPresentationRequested = true
      searchFieldCollapsedWhileIdle = false
    } else if !(searchField.hasKeyboardFocusForPresentation && isSearchFieldEditing) {
      searchFieldPresentationRequested = false
      searchFieldCollapsedWhileIdle = true
      if searchField.hasKeyboardFocusForPresentation {
        searchField.setKeyboardFocusForPresentation(false)
      }
    }
    viewModel.searchText = searchField.stringValue
    updateSearchFieldPresentation()
  }

  @objc private func focusSearchFromIcon() {
    focusSearchField()
  }

  private func moveSelectionFromFocusedCard(_ delta: Int) {
    claimKeyboardCardSelection()
    viewModel.moveSelection(delta)
    focusSelectedCard()
  }

  private func extendSelectionFromFocusedCard(_ delta: Int) {
    let count = viewModel.visibleItems.count
    guard count > 0 else { return }
    claimKeyboardCardSelection()
    let target = max(0, min(count - 1, viewModel.selectedIndex + delta))
    viewModel.selectItem(at: target, mode: .range)
    focusSelectedCard()
  }

  private func selectFirstCardFromFocusedCard() {
    claimKeyboardCardSelection()
    viewModel.selectFirstItem()
    focusSelectedCard()
  }

  private func selectLastCardFromFocusedCard() {
    claimKeyboardCardSelection()
    viewModel.selectLastItem()
    focusSelectedCard()
  }

  private func extendSelectionToFirstCardFromFocusedCard() {
    claimKeyboardCardSelection()
    viewModel.selectItem(at: 0, mode: .range)
    focusSelectedCard()
  }

  private func extendSelectionToLastCardFromFocusedCard() {
    claimKeyboardCardSelection()
    viewModel.selectItem(at: viewModel.visibleItems.count - 1, mode: .range)
    focusSelectedCard()
  }

  private func claimKeyboardCardSelection() {
    selectionScrollSuppressionCount = 0
    cardSelectionInputSource = .keyboard
    hoverSelectionRequiresFreshMouseMovement = true
    hoverSelectionKeyboardBarrierLocation = window?.mouseLocationOutsideOfEventStream
    clearCardHoverStates()
  }

  private func claimMouseHoverSelection(at candidateIndex: Int, mouseLocation: NSPoint?) -> Int? {
    if hoverSelectionRequiresFreshMouseMovement {
      guard let location = mouseLocation else { return nil }
      if let barrier = hoverSelectionKeyboardBarrierLocation,
         abs(location.x - barrier.x) < 0.5,
         abs(location.y - barrier.y) < 0.5 {
        return nil
      }
      hoverSelectionRequiresFreshMouseMovement = false
      hoverSelectionKeyboardBarrierLocation = nil
    }

    guard let index = visualHoverIndex(candidateIndex: candidateIndex, mouseLocation: mouseLocation) else {
      return nil
    }
    cardSelectionInputSource = .mouse
    selectionScrollSuppressionCount = 3
    hoveredCardIndex = index
    clearCardHoverStates(except: index)
    if index != candidateIndex {
      cardView(at: index)?.setHoverState(true, notifySelection: false, mouseLocation: mouseLocation)
    }
    return index
  }

  private func visualHoverIndex(candidateIndex: Int, mouseLocation: NSPoint?) -> Int? {
    guard currentPanelLayout == .vertical,
          let mouseLocation else {
      return candidateIndex
    }
    return visualCardIndex(atWindowLocation: mouseLocation)
  }

  private func visualCardIndex(atWindowLocation location: NSPoint) -> Int? {
    let point = convert(location, from: nil)
    let hitSlop: CGFloat = 1
    let hits = cardSlots.compactMap { index, slot -> (index: Int, zPosition: CGFloat)? in
      guard slot.card != nil,
            let frame = visualSlotFrameInPanel(slot),
            frame.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) else {
        return nil
      }
      return (index, slot.visualZPosition)
    }
    return hits.sorted { lhs, rhs in
      if lhs.zPosition == rhs.zPosition {
        return lhs.index < rhs.index
      }
      return lhs.zPosition > rhs.zPosition
    }.first?.index
  }

  private func visualSlotFrameInPanel(_ slot: ClipboardItemCardSlotView) -> NSRect? {
    guard let superview = slot.superview else { return nil }
    return superview.convert(slot.visualFrame, to: self)
  }

  private func clearCardHoverStates(except retainedIndex: Int? = nil) {
    let previousHoveredIndex = hoveredCardIndex
    if previousHoveredIndex != retainedIndex {
      hoveredCardIndex = retainedIndex
    }
    for card in cardViews where card.representedIndex != retainedIndex {
      card.setHoverState(false, notifySelection: false)
    }
  }

  private func handleCardHoverExit(at index: Int) {
    guard hoveredCardIndex == index else { return }
    hoveredCardIndex = nil
    refreshRenderedCardPresentationForHoverChange()
  }

  private func refreshRenderedCardPresentationForHoverChange() {
    guard currentPanelLayout == .vertical, cardItemCount > 0 else { return }
    let shouldAnimate = window != nil
    for card in cardViews {
      applyCurrentCardState(card, index: card.representedIndex, animated: shouldAnimate)
    }
    sizeItemsDocument(itemCount: cardItemCount, animated: shouldAnimate)
    renderCardsNearVisibleViewport()
  }

  private func focusSelectedCard() {
    guard viewModel.selectedIndex >= 0,
          viewModel.selectedIndex < cardItemCount else {
      window?.makeFirstResponder(self)
      return
    }
    renderCardIfNeeded(at: viewModel.selectedIndex)
    guard let card = cardView(at: viewModel.selectedIndex) else {
      window?.makeFirstResponder(self)
      return
    }
    window?.makeFirstResponder(card)
  }

  @objc private func openSettings() {
    onSettings()
  }

  @objc private func showToolbarMenu(_ sender: NSButton) {
    let menu = sender === categoryMenuButton ? categoryMenu() : clearHistoryMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
  }

  @objc private func performToolbarMenuItem(_ sender: NSMenuItem) {
    if let rawValue = sender.representedObject as? Int,
       let mode = ClipboardSortMode(rawValue: rawValue) {
      collapseSearchFieldIfIdle()
      viewModel.selectSortMode(mode)
      return
    }
    let seconds = (sender.representedObject as? NSNumber)?.doubleValue
      ?? (sender.representedObject as? TimeInterval)
    guard let seconds else { return }
    viewModel.clearHistory(since: seconds < 0 ? .distantPast : Date().addingTimeInterval(-seconds))
  }

  @objc private func toggleCompactMode() {
    viewModel.toggleCompactMode()
  }

  func showSelectedInClipboard() {
    showSelectedInClipboard(at: viewModel.selectedIndex)
  }

  private func showSelectedInClipboard(at index: Int) {
    #if DEBUG
    showInClipboardRequestCountForTesting += 1
    #endif
    viewModel.selectItem(at: index)
    viewModel.showSelectedInClipboard()
    syncSearchFieldFromViewModel()
  }

  private func syncSearchFieldFromViewModel() {
    let searchText = viewModel.searchText
    if searchField.stringValue != searchText {
      searchField.stringValue = searchText
    }
    let preservesFocusedEmptySearch = searchField.hasKeyboardFocusForPresentation && isSearchFieldEditing
    let shouldCollapseEmptySearch = searchText.isEmpty && !preservesFocusedEmptySearch
    if searchText.isEmpty {
      if shouldCollapseEmptySearch {
        searchFieldPresentationRequested = false
        searchFieldCollapsedWhileIdle = true
        if searchField.hasKeyboardFocusForPresentation {
          searchField.setKeyboardFocusForPresentation(false)
        }
      }
    } else {
      searchFieldPresentationRequested = true
      searchFieldCollapsedWhileIdle = false
    }
    updateSearchFieldPresentation(animated: !shouldCollapseEmptySearch)
  }

  func createCollection() {
    createCollectionFromToolbar()
  }

  func createTextClip() {
    createTextClipFromToolbar()
  }

  @objc private func createTextClipFromToolbar() {
    guard let text = requestTextClipCreation() else { return }
    guard viewModel.createTextClip(text) != nil else { return }
    syncSearchFieldFromViewModel()
    focusSelectedCard()
  }

  @objc private func createCollectionFromToolbar() {
    guard let request = requestCollectionCreation() else { return }
    viewModel.createCollection(named: request.name, colorHex: request.colorHex, selectAfterCreate: true)
    focusSelectedCollectionChip()
  }

  private func editCollection(named collectionName: String) {
    guard let request = requestCollectionEdit(named: collectionName) else { return }
    viewModel.updateCollection(named: collectionName, to: request.name, colorHex: request.colorHex)
    focusSelectedCollectionChip()
  }

  private func exportCollection(named collectionName: String) {
    let panel = NSSavePanel()
    panel.title = "Export \(collectionName) Pinboard"
    panel.nameFieldStringValue = defaultCollectionArchiveFileName(collectionName)
    configureArchiveFileType(on: panel)

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      _ = try viewModel.exportCollection(named: collectionName, to: url)
    } catch {
      viewModel.reportCollectionExportFailure(error)
    }
  }

  private func deleteCollection(named collectionName: String) {
    let count = viewModel.collectionCount(named: collectionName)
    guard confirmDeleteCollection(named: collectionName, count: count) else { return }
    viewModel.deleteCollection(named: collectionName)
    focusSelectedCollectionChip()
  }

  private func defaultCollectionArchiveFileName(_ collectionName: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    let safeName = collectionName
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "-")
    let name = safeName.isEmpty ? "Pinboard" : safeName
    return "ClipBored-\(name)-\(formatter.string(from: Date())).\(ClipboardArchiveService.fileExtension)"
  }

  private func requestTextClipCreation() -> String? {
    #if DEBUG
    if let textClipProviderForTesting {
      return textClipProviderForTesting()
    }
    #endif

    let textView = Self.makePlainTextEditor()
    let accessoryView = textEditorAccessoryView(for: textView)

    let alert = NSAlert()
    alert.messageText = "New Text Clip"
    alert.accessoryView = accessoryView
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = textView
    activeWritingToolsTextView = textView
    defer {
      if activeWritingToolsTextView === textView {
        activeWritingToolsTextView = nil
      }
    }

    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return textView.string
  }

  static func makePlainTextEditor(initialText: String = "") -> NSTextView {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
    configurePlainTextEditor(textView, initialText: initialText)
    return textView
  }

  static func configurePlainTextEditor(_ textView: NSTextView, initialText: String = "") {
    textView.string = initialText
    textView.font = .systemFont(ofSize: 13)
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.usesAdaptiveColorMappingForDarkAppearance = true
    textView.isAutomaticSpellingCorrectionEnabled = true
    textView.isAutomaticTextReplacementEnabled = true

    if textView.responds(to: NSSelectorFromString("setWritingToolsBehavior:")) {
      textView.setValue(1, forKey: "writingToolsBehavior")
    }
    if textView.responds(to: NSSelectorFromString("setAllowedWritingToolsResultOptions:")) {
      textView.setValue(1, forKey: "allowedWritingToolsResultOptions")
    }
  }

  private func textEditorAccessoryView(for textView: NSTextView) -> NSView {
    let scrollView = NSScrollView(frame: textView.frame)
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder
    scrollView.documentView = textView
    scrollView.widthAnchor.constraint(equalToConstant: 460).isActive = true
    scrollView.heightAnchor.constraint(equalToConstant: 180).isActive = true

    guard Self.supportsWritingTools(textView) else {
      return scrollView
    }

    let writingToolsButton = NSButton(
      title: "Writing Tools",
      target: self,
      action: #selector(showWritingToolsForActiveEditor(_:))
    )
    writingToolsButton.bezelStyle = .rounded
    writingToolsButton.setAccessibilityLabel("Writing Tools")
    writingToolsButton.toolTip = "Open macOS Writing Tools for this text clip."

    let note = NSTextField(labelWithString: "Uses macOS Writing Tools when available.")
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .secondaryLabelColor

    let row = NSStackView(views: [writingToolsButton, note])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let stack = NSStackView(views: [scrollView, row])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.frame = NSRect(x: 0, y: 0, width: 460, height: 218)
    return stack
  }

  static func supportsWritingTools(_ textView: NSTextView) -> Bool {
    textView.responds(to: NSSelectorFromString("showWritingTools:"))
  }

  @objc private func showWritingToolsForActiveEditor(_ sender: NSButton) {
    guard let textView = activeWritingToolsTextView,
          Self.supportsWritingTools(textView)
    else {
      return
    }
    textView.window?.makeFirstResponder(textView)
    NSApp.sendAction(NSSelectorFromString("showWritingTools:"), to: textView, from: sender)
  }

  private func configureArchiveFileType(on panel: NSSavePanel) {
    panel.setValue([ClipboardArchiveService.fileExtension], forKey: "allowedFileTypes")
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
    .rtf,
    .color
  ] + VideoPayload.pasteboardTypes
}

private func shelfSearchText(from event: NSEvent) -> String? {
  let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
  guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return nil }
  guard let characters = event.characters, !characters.isEmpty else { return nil }
  guard characters.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
  return characters
}

private func selectionMode(from modifiers: NSEvent.ModifierFlags) -> ClipboardSelectionMode {
  let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
  if relevantModifiers.contains(.shift) {
    return .range
  }
  if relevantModifiers.contains(.command) {
    return .toggle
  }
  return .replace
}

private enum ClipboardCardDragContext {
  static var itemID: UUID?
}

private final class HorizontalRailScrollView: NSScrollView {
  private let leadingFade = RailEdgeFadeView(edge: .leading)
  private let trailingFade = RailEdgeFadeView(edge: .trailing)
  private let fadeWidth: CGFloat
  var onVisibleBoundsChanged: (() -> Void)?

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }

  init(edgeFadeWidth: CGFloat = 26) {
    self.fadeWidth = edgeFadeWidth
    super.init(frame: .zero)
    configureOverflowFades()
  }

  override init(frame frameRect: NSRect) {
    self.fadeWidth = 26
    super.init(frame: frameRect)
    configureOverflowFades()
  }

  required init?(coder: NSCoder) {
    self.fadeWidth = 26
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
    onVisibleBoundsChanged?()
  }

  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    updateOverflowFades()
    onVisibleBoundsChanged?()
  }

  func scrollHorizontallyByVerticalDelta(_ deltaY: CGFloat) {
    scrollHorizontally(by: -deltaY)
  }

  func scrollVerticallyByVerticalDelta(_ deltaY: CGFloat) {
    scrollVertically(by: -deltaY)
  }

  var overflowFadeVisibility: [Bool] {
    updateOverflowFades()
    return [!leadingFade.isHidden, !trailingFade.isHidden]
  }

  var overflowFadeWidth: CGFloat {
    fadeWidth
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

  private var maxVerticalOffset: CGFloat {
    guard let documentView else { return 0 }
    return max(0, documentView.frame.height - contentView.bounds.height)
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

  private func scrollVertically(by deltaY: CGFloat) {
    let maxOffset = maxVerticalOffset
    guard maxOffset > 0 else { return }
    let origin = contentView.bounds.origin
    let targetY = min(max(origin.y + deltaY, 0), maxOffset)
    guard targetY != origin.y else { return }

    contentView.scroll(to: NSPoint(x: origin.x, y: targetY))
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

private final class ClipboardItemsDocumentView: NSStackView {
  var usesFlippedCoordinates = false {
    didSet {
      guard oldValue != usesFlippedCoordinates else { return }
      needsLayout = true
    }
  }

  override var isFlipped: Bool {
    usesFlippedCoordinates
  }
}

private final class CollectionRailDocumentView: NSView {
  override var isFlipped: Bool {
    true
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

private final class TextPreviewBottomFadeView: NSView {
  private let color: NSColor

  init(color: NSColor) {
    self.color = color
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
    let clear = color.withAlphaComponent(0)
    let solid = color.withAlphaComponent(0.96)
    NSGradient(colors: [clear, solid])?.draw(in: bounds, angle: -90)
  }
}

private final class CollectionChipView: NSView {
  private enum Metrics {
    static let iconOnlySize: CGFloat = 34
  }

  let titleText: String
  private let color: NSColor
  private let symbolName: String?
  private let iconOnly: Bool
  private let dot = NSView()
  private let symbolView = NSImageView()
  private let label: NSTextField
  private let countLabel = NSTextField(labelWithString: "0")
  private(set) var isSelected = false
  private(set) var count = 0
  private var isStackCaptureActive = false
  private var isKeyboardFocused = false
  private var isDropTargeted = false
  private var trackingAreaRef: NSTrackingArea?
  var onPress: (Bool) -> Void = { _ in }
  var onHover: (Bool) -> Void = { _ in }
  var onStartSearch: (String) -> Void = { _ in }
  var onMoveFocus: (Int) -> Void = { _ in }
  var onMoveCardSelection: (Int) -> Void = { _ in }
  var onSelectFirst: () -> Void = {}
  var onSelectLast: () -> Void = {}
  var onDropItem: ((UUID) -> Void)?
  var onAddVisibleToStack: (() -> Void)? { didSet { updateAccessibility() } }
  var onPasteStackNext: (() -> Void)? { didSet { updateAccessibility() } }
  var onCopyStackNext: (() -> Void)? { didSet { updateAccessibility() } }
  var onPasteStackText: (() -> Void)? { didSet { updateAccessibility() } }
  var onCopyStackText: (() -> Void)? { didSet { updateAccessibility() } }
  var onClearStack: (() -> Void)? { didSet { updateAccessibility() } }
  var onToggleStackCapture: (() -> Void)? { didSet { updateAccessibility() } }
  var onEdit: (() -> Void)? { didSet { updateAccessibility() } }
  var onExport: (() -> Void)? { didSet { updateAccessibility() } }
  var onDelete: (() -> Void)? { didSet { updateAccessibility() } }

  init(title: String, color: NSColor, symbolName: String? = nil, iconOnly: Bool = false) {
    self.titleText = title
    self.color = color
    self.symbolName = symbolName
    self.iconOnly = iconOnly
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
    layer?.cornerRadius = 14
    layer?.borderWidth = 0.5
    layer?.borderColor = NSColor.clear.cgColor
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityHelp(accessibilityHelpText())
    heightAnchor.constraint(equalToConstant: iconOnly ? Metrics.iconOnlySize : 28).isActive = true
    if iconOnly {
      widthAnchor.constraint(equalToConstant: Metrics.iconOnlySize).isActive = true
      layer?.cornerRadius = Metrics.iconOnlySize / 2
    }
    registerForDraggedTypes(ClipboardItemDragPasteboard.acceptedTypes)

    dot.wantsLayer = true
    dot.layer?.cornerRadius = iconOnly ? 7 : 4
    dot.layer?.backgroundColor = color.cgColor
    dot.widthAnchor.constraint(equalToConstant: iconOnly ? 14 : 8).isActive = true
    dot.heightAnchor.constraint(equalToConstant: iconOnly ? 14 : 8).isActive = true

    let leadingIndicator: NSView
    if let symbolName {
      let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: titleText)
      image?.isTemplate = true
      symbolView.image = image
      symbolView.imageScaling = .scaleProportionallyUpOrDown
      symbolView.contentTintColor = color.withAlphaComponent(0.86)
      symbolView.widthAnchor.constraint(equalToConstant: iconOnly ? 18 : 13).isActive = true
      symbolView.heightAnchor.constraint(equalToConstant: iconOnly ? 18 : 13).isActive = true
      leadingIndicator = symbolView
    } else {
      leadingIndicator = dot
    }

    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.isHidden = iconOnly
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    label.toolTip = label.stringValue

    countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    countLabel.textColor = .secondaryLabelColor
    countLabel.alignment = .center
    countLabel.lineBreakMode = .byTruncatingTail
    countLabel.wantsLayer = true
    countLabel.layer?.cornerRadius = 8
    countLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor
    countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
    countLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
    countLabel.isHidden = true
    countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let stack = NSStackView(views: iconOnly ? [leadingIndicator] : [leadingIndicator, label, countLabel])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = iconOnly ? 0 : 7
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    if iconOnly {
      NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: centerYAnchor)
      ])
    } else {
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
        stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
        stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        widthAnchor.constraint(greaterThanOrEqualToConstant: symbolName == nil ? 70 : 84),
        widthAnchor.constraint(lessThanOrEqualToConstant: 164)
      ])
    }
    setSelected(false)
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    label.textColor = selected ? .labelColor : .secondaryLabelColor
    countLabel.textColor = selected ? color.withAlphaComponent(0.95) : .tertiaryLabelColor
    countLabel.layer?.backgroundColor = (
      selected
      ? NSColor.windowBackgroundColor.withAlphaComponent(0.55)
      : NSColor.labelColor.withAlphaComponent(0.055)
    ).cgColor
    symbolView.contentTintColor = color.withAlphaComponent(selected ? 0.98 : 0.78)
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
      layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
      layer?.borderColor = color.withAlphaComponent(0.54).cgColor
    } else if isSelected {
      layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.48).cgColor
      layer?.borderColor = color.withAlphaComponent(isKeyboardFocused ? 0.52 : 0.24).cgColor
    } else if isStackCaptureActive {
      layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
      layer?.borderColor = color.withAlphaComponent(isKeyboardFocused ? 0.46 : 0.28).cgColor
    } else if isKeyboardFocused {
      layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.26).cgColor
      layer?.borderColor = color.withAlphaComponent(0.34).cgColor
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

  func setStackCaptureActive(_ active: Bool) {
    isStackCaptureActive = active
    updateChrome()
    updateAccessibility()
  }

  private func updateCountLabelVisibility() {
    countLabel.isHidden = iconOnly || count == 0
  }

  private func updateAccessibility() {
    let noun = count == 1 ? "clip" : "clips"
    let selectedText = isSelected ? "selected, " : ""
    let captureText = isStackCaptureActive ? "capture on, " : ""
    setAccessibilityLabel("\(titleText), \(selectedText)\(captureText)\(count) \(noun)")
    setAccessibilityValue("\(count)")
    setAccessibilityHelp(accessibilityHelpText())
    toolTip = "\(titleText), \(selectedText)\(count) \(noun)"
  }

  private func accessibilityHelpText() -> String {
    var parts = [
      "Press Return or Space to show \(titleText). Use Up/Down to move between categories, Left/Right to move between clips, and Home/End to move between categories."
    ]
    if hasStackMenuActions {
      parts.append("Open the context menu for Stack capture and Stack paste actions.")
    }
    if hasCollectionManagementActions {
      parts.append("Open the context menu to edit, export, or delete this Pinboard.")
    }
    return parts.joined(separator: " ")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func becomeFirstResponder() -> Bool {
    setKeyboardFocusForPresentation(true)
    return true
  }

  override func resignFirstResponder() -> Bool {
    setKeyboardFocusForPresentation(false)
    return true
  }

  func setKeyboardFocusForPresentation(_ focused: Bool) {
    guard isKeyboardFocused != focused else { return }
    isKeyboardFocused = focused
    updateChrome()
  }

  func clearKeyboardFocus() {
    setKeyboardFocusForPresentation(false)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
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
    onHover(true)
  }

  override func mouseExited(with event: NSEvent) {
    onHover(false)
  }

  override func mouseDown(with event: NSEvent) {
    activateFromUserInteraction(extending: event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command))
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 49:
      onPress(false)
    case 125:
      onMoveFocus(1)
    case 126:
      onMoveFocus(-1)
    case 115:
      onSelectFirst()
    case 119:
      onSelectLast()
    case 123:
      onMoveCardSelection(-1)
    case 124:
      onMoveCardSelection(1)
    default:
      if let text = shelfSearchText(from: event) {
        onStartSearch(text)
      } else {
        super.keyDown(with: event)
      }
    }
  }

  override func accessibilityPerformPress() -> Bool {
    activateFromUserInteraction(extending: false)
    return true
  }

  private func activateFromUserInteraction(extending: Bool) {
    window?.makeFirstResponder(self)
    onPress(extending)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard hasContextMenuActions else { return nil }
    return contextMenu()
  }

  private var hasContextMenuActions: Bool {
    hasStackMenuActions || hasCollectionManagementActions
  }

  private var hasStackMenuActions: Bool {
    onAddVisibleToStack != nil
      || onPasteStackNext != nil
      || onCopyStackNext != nil
      || onPasteStackText != nil
      || onCopyStackText != nil
      || onClearStack != nil
      || onToggleStackCapture != nil
  }

  private var hasCollectionManagementActions: Bool {
    onEdit != nil
      || onExport != nil
      || onDelete != nil
  }

  private func contextMenu() -> NSMenu {
    let menu = NSMenu(title: titleText)
    menu.autoenablesItems = false
    if onToggleStackCapture != nil {
      let item = NSMenuItem(title: isStackCaptureActive ? "Stop Stack Capture" : "Start Stack Capture", action: #selector(toggleStackCaptureFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onToggleStackCapture != nil && (
      onAddVisibleToStack != nil
      || onPasteStackNext != nil
      || onCopyStackNext != nil
      || onPasteStackText != nil
      || onCopyStackText != nil
      || onClearStack != nil
    ) {
      menu.addItem(NSMenuItem.separator())
    }
    if onAddVisibleToStack != nil {
      let item = NSMenuItem(title: "Add Visible Clips to Stack", action: #selector(addVisibleToStackFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onPasteStackNext != nil {
      let item = NSMenuItem(title: "Paste Stack Next", action: #selector(pasteStackNextFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onCopyStackNext != nil {
      let item = NSMenuItem(title: "Copy Stack Next", action: #selector(copyStackNextFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onPasteStackText != nil {
      let item = NSMenuItem(title: "Paste Stack as Text", action: #selector(pasteStackTextFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onCopyStackText != nil {
      let item = NSMenuItem(title: "Copy Stack as Text", action: #selector(copyStackTextFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onClearStack != nil {
      let item = NSMenuItem(title: "Clear Stack", action: #selector(clearStackFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if (onEdit != nil || onExport != nil || onDelete != nil) && !menu.items.isEmpty {
      menu.addItem(NSMenuItem.separator())
    }
    if onEdit != nil {
      let item = NSMenuItem(title: "Edit Collection...", action: #selector(editFromMenu), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    if onExport != nil {
      let item = NSMenuItem(title: "Export Pinboard...", action: #selector(exportFromMenu), keyEquivalent: "")
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

  @objc private func addVisibleToStackFromMenu() {
    onAddVisibleToStack?()
  }

  @objc private func pasteStackNextFromMenu() {
    onPasteStackNext?()
  }

  @objc private func copyStackNextFromMenu() {
    onCopyStackNext?()
  }

  @objc private func pasteStackTextFromMenu() {
    onPasteStackText?()
  }

  @objc private func copyStackTextFromMenu() {
    onCopyStackText?()
  }

  @objc private func clearStackFromMenu() {
    onClearStack?()
  }

  @objc private func toggleStackCaptureFromMenu() {
    onToggleStackCapture?()
  }

  @objc private func editFromMenu() {
    onEdit?()
  }

  @objc private func exportFromMenu() {
    onExport?()
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

  var debugLabelIsHidden: Bool {
    label.isHidden
  }

  var debugLeadingSymbolName: String {
    symbolName ?? ""
  }

  var debugFrameWidth: CGFloat {
    frame.width
  }

  func debugDropItem(_ itemID: UUID) {
    onDropItem?(itemID)
  }

  func debugMouseDown() {
    activateFromUserInteraction(extending: false)
  }

  func debugCommandMouseDown() {
    activateFromUserInteraction(extending: true)
  }

  func debugSetHovered(_ hovered: Bool) {
    onHover(hovered)
  }

  var debugMenuTitles: [String] {
    contextMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  func debugPerformMenuItem(titled title: String) {
    guard let item = contextMenu().items.first(where: { $0.title == title }) else { return }
    _ = item.target?.perform(item.action, with: item)
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

private final class HeaderBadgeTileView: NSView {
  private let tileCornerRadius: CGFloat
  private let tileMaskedCorners: CACornerMask

  init(cornerRadius: CGFloat, maskedCorners: CACornerMask) {
    self.tileCornerRadius = cornerRadius
    self.tileMaskedCorners = maskedCorners
    super.init(frame: .zero)
    wantsLayer = true
    applyChrome()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    applyChrome()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyChrome()
  }

  private func applyChrome() {
    wantsLayer = true
    guard let layer else { return }
    layer.masksToBounds = false
    layer.cornerRadius = tileCornerRadius
    layer.maskedCorners = tileMaskedCorners
    layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.74).cgColor
    layer.borderWidth = 1
    layer.borderColor = NSColor.white.withAlphaComponent(0.44).cgColor
    layer.shadowColor = NSColor.black.cgColor
    layer.shadowOpacity = 0.14
    layer.shadowRadius = 8
    layer.shadowOffset = NSSize(width: 0, height: 2)
  }
}

private final class ClipboardItemCardSlotView: NSView {
  fileprivate private(set) var card: ClipboardItemCardView?
  private let itemID: UUID
  private var topConstraint: NSLayoutConstraint?
  private let inactiveTopOffset: CGFloat
  private var isLifted = false

  init(itemID: UUID, layout: ClipboardItemCardLayout) {
    self.itemID = itemID
    inactiveTopOffset = layout.activeLift
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = true
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.zPosition = 0
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool {
    true
  }

  fileprivate var representedItemID: UUID {
    itemID
  }

  func attachCard(_ card: ClipboardItemCardView) {
    guard self.card !== card else { return }
    self.card?.removeFromSuperview()
    topConstraint?.isActive = false
    self.card = card
    card.translatesAutoresizingMaskIntoConstraints = false
    addSubview(card)
    let topConstraint = card.topAnchor.constraint(equalTo: topAnchor, constant: isLifted ? 0 : inactiveTopOffset)
    self.topConstraint = topConstraint
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: leadingAnchor),
      card.trailingAnchor.constraint(equalTo: trailingAnchor),
      topConstraint
    ])
  }

  func setLifted(_ lifted: Bool) {
    guard isLifted != lifted else { return }
    isLifted = lifted
    let targetOffset = lifted ? 0 : inactiveTopOffset
    layer?.zPosition = lifted ? 20 : 10
    if window == nil {
      topConstraint?.constant = targetOffset
      layer?.zPosition = lifted ? 20 : 0
      needsLayout = true
      layoutSubtreeIfNeeded()
      return
    }

    superview?.layoutSubtreeIfNeeded()
    layoutSubtreeIfNeeded()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = ClipboardPanelView.Motion.cardLiftDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      topConstraint?.constant = targetOffset
      superview?.animator().layoutSubtreeIfNeeded()
      animator().layoutSubtreeIfNeeded()
    } completionHandler: { [weak self] in
      guard let self else { return }
      if !lifted {
        self.layer?.zPosition = 0
      }
    }
  }

  fileprivate var visualFrame: NSRect {
    layer?.presentation()?.frame ?? frame
  }

  fileprivate var visualZPosition: CGFloat {
    CGFloat(layer?.presentation()?.zPosition ?? layer?.zPosition ?? 0)
  }

  #if DEBUG
  var debugPresentationFrame: NSRect {
    visualFrame
  }

  var debugCardTopOffset: CGFloat {
    topConstraint?.constant ?? inactiveTopOffset
  }

  var debugZPosition: CGFloat {
    CGFloat(layer?.zPosition ?? 0)
  }

  #endif
}

private final class ClipboardItemCardView: NSView, NSDraggingSource {
  private enum Metrics {
    static let dragThreshold: CGFloat = 4
    static let actionRailBadgeGap: CGFloat = 8
    static let actionRailLeadingMargin: CGFloat = 10
  }
  private enum Palette {
    static let border = NSColor.white.withAlphaComponent(0.42).cgColor
    static let selectedBorder = NSColor.white.withAlphaComponent(0.74).cgColor
    static let cardSurface = NSColor.windowBackgroundColor.withAlphaComponent(0.84).cgColor
    static let selectedSurface = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
    static let bodyBackground = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
    static let footerBackground = NSColor.windowBackgroundColor.withAlphaComponent(0.74).cgColor
    static let divider = NSColor.white.withAlphaComponent(0.14).cgColor
    static let actionRailBackground = NSColor.windowBackgroundColor.withAlphaComponent(0.58).cgColor
    static let actionRailBorder = NSColor.white.withAlphaComponent(0.28).cgColor
    static let secondaryActionBackground = NSColor.labelColor.withAlphaComponent(0.08).cgColor
  }
  private enum CornerMasks {
    static let topOnly: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    static let badgeWithoutBottomRight: CACornerMask = [
      .layerMinXMinYCorner,
      .layerMinXMaxYCorner,
      .layerMaxXMaxYCorner
    ]
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

  var onSelect: (Int, ClipboardSelectionMode) -> Void = { _, _ in }
  var onHover: (Int, NSPoint?) -> Bool = { _, _ in true }
  var onHoverExit: (Int) -> Void = { _ in }
  var onMoveSelection: (Int) -> Void = { _ in }
  var onExtendSelection: (Int) -> Void = { _ in }
  var onPageSelection: (Int) -> Void = { _ in }
  var onPageExtendSelection: (Int) -> Void = { _ in }
  var onSelectFirst: () -> Void = {}
  var onSelectLast: () -> Void = {}
  var onExtendSelectionToFirst: () -> Void = {}
  var onExtendSelectionToLast: () -> Void = {}
  var onSelectAll: () -> Void = {}
  var onPaste: (Int) -> Void = { _ in }
  var onCopy: (Int) -> Void = { _ in }
  var onPastePlainText: (Int) -> Void = { _ in }
  var onCopyPlainText: (Int) -> Void = { _ in }
  var onPasteSelectionText: (Int) -> Void = { _ in }
  var onCopySelectionText: (Int) -> Void = { _ in }
  var onAddSelectionToStack: (Int) -> Void = { _ in }
  var onToggleStack: (Int) -> Void = { _ in }
  var onAddVisibleToStack: () -> Void = {}
  var onPasteStackNext: () -> Void = {}
  var onCopyStackNext: () -> Void = {}
  var onPasteStackText: () -> Void = {}
  var onCopyStackText: () -> Void = {}
  var onClearStack: () -> Void = {}
  var onShowInClipboard: (Int) -> Void = { _ in }
  var onRename: (Int) -> Void = { _ in }
  var onEditText: (Int) -> Void = { _ in }
  var onRotateImage: (Int) -> Void = { _ in }
  var onExtractImageText: (Int) -> Void = { _ in }
  var onPreview: (Int) -> Void = { _ in }
  var onPasteboardWriters: (Int) -> [NSPasteboardWriting] = { _ in [] }
  var onOpen: (Int) -> Void = { _ in }
  var onReveal: (Int) -> Void = { _ in }
  var onTogglePin: (Int) -> Void = { _ in }
  var onAssignCollection: (Int, String?) -> Void = { _, _ in }
  var onIgnoreSourceApp: (Int) -> Void = { _ in }
  var onIgnoreKind: (Int) -> Void = { _ in }
  var onDelete: (Int) -> Void = { _ in }
  var onUndoDelete: () -> Void = {}
  var onStartSearch: (String) -> Void = { _ in }
  var onLiftStateChanged: (Bool) -> Void = { _ in }

  private var index: Int
  private let itemID: UUID
  private let reuseFingerprint: ClipboardItemCardReuseFingerprint
  private let layout: ClipboardItemCardLayout
  private let itemKind: ClipboardItemKind
  private let itemIsPinned: Bool
  private var itemIsStacked: Bool
  private var stackCount: Int
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
  private var actionRailWidthConstraint: NSLayoutConstraint?
  private var actionRailContentWidth: CGFloat = 0
  private var actionRailIsPresented = false
  private weak var headerBadgeView: NSView?
  private weak var headerBadgeContentView: NSView?
  private weak var headerPinView: NSView?
  private weak var quickPasteBadgeLabel: NSTextField?
  private var isActiveSelection = false
  private var isSelected = false
  private var selectedGroupCount = 1
  private var isHovered = false
  private var isKeyboardFocused = false
  private var mouseDownLocation: NSPoint?
  private var trackingAreaRef: NSTrackingArea?
  private var presentation: ClipboardCardPresentation = .expanded
  private var presentationAnimationGeneration = 0
  private var widthConstraint: NSLayoutConstraint?
  private var heightConstraint: NSLayoutConstraint?
  private var expandedDetailHeightConstraint: NSLayoutConstraint?
  private var fullContentConstraints: [NSLayoutConstraint] = []
  private var compactContentConstraints: [NSLayoutConstraint] = []
  private weak var fullContentView: NSView?
  private weak var compactContentView: NSView?
  private weak var compactTextStack: NSView?
  private weak var compactMetricLabel: NSTextField?

  fileprivate var representedItemID: UUID {
    itemID
  }

  fileprivate var representedIndex: Int {
    index
  }

  fileprivate func canReuse(with fingerprint: ClipboardItemCardReuseFingerprint) -> Bool {
    reuseFingerprint == fingerprint
  }

  fileprivate func updateIndex(_ index: Int) {
    self.index = index
    isHovered = false
    mouseDownLocation = nil
    updateActionRailVisibility()
  }

  init(
    item: ClipboardItem,
    thumbnail: NSImage?,
    index: Int,
    reuseFingerprint: ClipboardItemCardReuseFingerprint,
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
    self.reuseFingerprint = reuseFingerprint
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
    setSelectionState(active: selected, selected: selected, selectionCount: selected ? 1 : selectedGroupCount)
  }

  func setSelectionState(active: Bool, selected: Bool, selectionCount: Int) {
    isActiveSelection = active
    isSelected = selected
    selectedGroupCount = max(1, selectionCount)
    let emphasized = active || isKeyboardFocused || isHovered
    animateLayerChanges {
      self.contentView.layer?.borderWidth = emphasized || selected ? 0.8 : 0.6
      self.contentView.layer?.backgroundColor = self.cardSurfaceColor(emphasized: emphasized, selected: selected)
      self.contentView.layer?.borderColor = emphasized || selected ? Palette.selectedBorder : Palette.border
      self.applyCardShadow(emphasized: emphasized)
      self.layer?.transform = CATransform3DIdentity
    }
    onLiftStateChanged(emphasized)
    setAccessibilityValue(selected ? "Selected" : "Not selected")
    updateActionRailVisibility()
  }

  func setStackState(isStacked: Bool, stackCount: Int) {
    guard itemIsStacked != isStacked || self.stackCount != stackCount else { return }
    itemIsStacked = isStacked
    self.stackCount = stackCount
    configureStackCornerButton()
    updateActionRailVisibility()
  }

  func setPresentation(
    _ presentation: ClipboardCardPresentation,
    animated: Bool = false,
    stableHeaderRollout: Bool = false
  ) {
    presentationAnimationGeneration += 1
    let animationGeneration = presentationAnimationGeneration
    let size = presentation.size(for: layout)
    let previousPresentation = self.presentation
    let changed = previousPresentation != presentation
    self.presentation = presentation

    let isExpanded = presentation.isExpanded
    let previousExpanded = previousPresentation.isExpanded
    let shouldAnimate = animated && changed && window != nil
    let detailHeight = isExpanded ? expandedDetailHeight : 0

    if shouldAnimate {
      fullContentView?.alphaValue = previousExpanded ? 1 : 0
      fullContentView?.isHidden = false
      compactContentView?.alphaValue = 1
      compactContentView?.isHidden = false
    }

    compactTextStack?.isHidden = presentation == .horizontalIcon
    compactMetricLabel?.isHidden = presentation != .verticalRow
    let targetCornerRadius = cardCornerRadius(for: presentation, size: size)
    stackCornerButton.isHidden = !presentation.showsFloatingActions || !(itemIsStacked || isKeyboardFocused)

    let applyFinalVisibility = { [weak self] in
      guard let self else { return }
      guard self.presentationAnimationGeneration == animationGeneration else { return }
      self.fullContentView?.isHidden = !isExpanded
      self.fullContentView?.alphaValue = isExpanded ? 1 : 0
      self.compactContentView?.isHidden = false
      self.compactContentView?.alphaValue = 1
      self.widthConstraint?.constant = size.width
      self.heightConstraint?.constant = size.height
      self.expandedDetailHeightConstraint?.constant = detailHeight
      self.contentView.layer?.cornerRadius = targetCornerRadius
      self.contentView.layer?.backgroundColor = self.cardSurfaceColor(
        emphasized: self.isActiveSelection || self.isKeyboardFocused || self.isHovered,
        selected: self.isSelected
      )
      self.applyCardShadow(emphasized: self.isActiveSelection || self.isKeyboardFocused || self.isHovered)
      self.needsLayout = true
      self.layoutSubtreeIfNeeded()
    }

    guard shouldAnimate else {
      widthConstraint?.constant = size.width
      heightConstraint?.constant = size.height
      expandedDetailHeightConstraint?.constant = detailHeight
      applyFinalVisibility()
      if changed {
        updateActionRailVisibility()
        needsLayout = true
      }
      return
    }

    if stableHeaderRollout {
      widthConstraint?.constant = size.width
      fullContentView?.isHidden = false
      fullContentView?.alphaValue = 1
      compactContentView?.alphaValue = 1
      contentView.layer?.cornerRadius = targetCornerRadius
      contentView.layer?.backgroundColor = cardSurfaceColor(
        emphasized: isActiveSelection || isKeyboardFocused || isHovered,
        selected: isSelected
      )
      applyCardShadow(emphasized: isActiveSelection || isKeyboardFocused || isHovered)

      if isExpanded && !previousExpanded {
        heightConstraint?.constant = previousPresentation.size(for: layout).height
        expandedDetailHeightConstraint?.constant = 0
        superview?.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        #if DEBUG
        debugAnimatedPresentationChangeCount += 1
        #endif
        NSAnimationContext.runAnimationGroup { context in
          context.duration = ClipboardPanelView.Motion.cardExpansionDuration
          context.timingFunction = ClipboardPanelView.Motion.cardExpansionTiming
          context.allowsImplicitAnimation = true
          heightConstraint?.animator().constant = size.height
          expandedDetailHeightConstraint?.animator().constant = detailHeight
          superview?.animator().layoutSubtreeIfNeeded()
          animator().layoutSubtreeIfNeeded()
        } completionHandler: {
          applyFinalVisibility()
        }

        if changed {
          updateActionRailVisibility()
          needsLayout = true
        }
        return
      }

      if !isExpanded && previousExpanded {
        heightConstraint?.constant = previousPresentation.size(for: layout).height
        expandedDetailHeightConstraint?.constant = expandedDetailHeight
        superview?.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        #if DEBUG
        debugAnimatedPresentationChangeCount += 1
        #endif
        NSAnimationContext.runAnimationGroup { context in
          context.duration = ClipboardPanelView.Motion.cardExpansionDuration
          context.timingFunction = ClipboardPanelView.Motion.cardExpansionTiming
          context.allowsImplicitAnimation = true
          heightConstraint?.animator().constant = size.height
          expandedDetailHeightConstraint?.animator().constant = detailHeight
          superview?.animator().layoutSubtreeIfNeeded()
          animator().layoutSubtreeIfNeeded()
        } completionHandler: {
          applyFinalVisibility()
        }

        if changed {
          updateActionRailVisibility()
          needsLayout = true
        }
        return
      }

      superview?.layoutSubtreeIfNeeded()
      layoutSubtreeIfNeeded()
      #if DEBUG
      debugAnimatedPresentationChangeCount += 1
      #endif
      NSAnimationContext.runAnimationGroup { context in
        context.duration = ClipboardPanelView.Motion.cardExpansionDuration
        context.timingFunction = ClipboardPanelView.Motion.cardExpansionTiming
        context.allowsImplicitAnimation = true
        heightConstraint?.animator().constant = size.height
        expandedDetailHeightConstraint?.animator().constant = detailHeight
        superview?.animator().layoutSubtreeIfNeeded()
        animator().layoutSubtreeIfNeeded()
      } completionHandler: {
        applyFinalVisibility()
      }

      if changed {
        updateActionRailVisibility()
        needsLayout = true
      }
      return
    }

    superview?.layoutSubtreeIfNeeded()
    layoutSubtreeIfNeeded()
    #if DEBUG
    debugAnimatedPresentationChangeCount += 1
    #endif
    NSAnimationContext.runAnimationGroup { context in
      context.duration = ClipboardPanelView.Motion.cardExpansionDuration
      context.timingFunction = ClipboardPanelView.Motion.cardExpansionTiming
      widthConstraint?.animator().constant = size.width
      heightConstraint?.animator().constant = size.height
      expandedDetailHeightConstraint?.animator().constant = detailHeight
      fullContentView?.animator().alphaValue = isExpanded ? 1 : 0
      compactContentView?.animator().alphaValue = 1
      contentView.layer?.cornerRadius = targetCornerRadius
      superview?.animator().layoutSubtreeIfNeeded()
      animator().layoutSubtreeIfNeeded()
    } completionHandler: {
      applyFinalVisibility()
    }

    if changed {
      updateActionRailVisibility()
      needsLayout = true
    }
  }

  private func animateLayerChanges(_ changes: () -> Void) {
    CATransaction.begin()
    if window == nil {
      CATransaction.setDisableActions(true)
    } else {
      CATransaction.setAnimationDuration(0.16)
      CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
    }
    changes()
    CATransaction.commit()
  }

  private func applyCardShadow(emphasized: Bool) {
    if presentation == .verticalRow || presentation == .verticalFocus {
      layer?.shadowOpacity = 0
      layer?.shadowRadius = 0
      layer?.shadowOffset = .zero
      return
    }
    layer?.shadowOpacity = emphasized ? 0.24 : 0.09
    layer?.shadowRadius = emphasized ? 24 : 12
    layer?.shadowOffset = NSSize(width: 0, height: emphasized ? 12 : 3)
  }

  private func cardSurfaceColor(emphasized: Bool, selected: Bool) -> CGColor {
    if presentation == .verticalRow || presentation == .verticalFocus {
      return NSColor.clear.cgColor
    }
    if emphasized {
      return Palette.selectedSurface
    }
    return selected ? Palette.cardSurface : Palette.cardSurface
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func becomeFirstResponder() -> Bool {
    isKeyboardFocused = true
    onSelect(index, .activate)
    setSelectionState(active: isActiveSelection, selected: isSelected, selectionCount: selectedGroupCount)
    return true
  }

  override func resignFirstResponder() -> Bool {
    isKeyboardFocused = false
    setSelectionState(active: isActiveSelection, selected: isSelected, selectionCount: selectedGroupCount)
    return true
  }

  override func keyDown(with event: NSEvent) {
    let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if relevantModifiers == [.command, .shift] {
      switch event.keyCode {
      case 9, 36, 76:
        onPastePlainText(index)
      default:
        super.keyDown(with: event)
      }
      return
    }
    if relevantModifiers == .command {
      switch event.keyCode {
      case 0:
        onSelectAll()
      case 5:
        onShowInClipboard(index)
      case 6:
        onUndoDelete()
      case 8:
        onCopy(index)
      case 14 where canEditText:
        onEditText(index)
      case 15:
        onRename(index)
      case 16:
        onPreview(index)
      case 31 where canOpen:
        onOpen(index)
      default:
        super.keyDown(with: event)
      }
      return
    }
    if relevantModifiers == .shift {
      switch event.keyCode {
      case 36, 76:
        onPastePlainText(index)
      case 115:
        onExtendSelectionToFirst()
      case 116:
        onPageExtendSelection(-1)
      case 119:
        onExtendSelectionToLast()
      case 121:
        onPageExtendSelection(1)
      case 123:
        onExtendSelection(-1)
      case 124:
        onExtendSelection(1)
      default:
        super.keyDown(with: event)
      }
      return
    }

    switch event.keyCode {
    case 36, 76:
      onPaste(index)
    case 49:
      if canPreview {
        onPreview(index)
      } else {
        onPaste(index)
      }
    case 51, 117:
      onDelete(index)
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
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(tracking)
    trackingAreaRef = tracking
  }

  fileprivate func setHoverState(_ hovered: Bool, notifySelection: Bool, mouseLocation: NSPoint? = nil) {
    let wasHovered = isHovered
    if hovered && notifySelection && !wasHovered {
      guard onHover(index, mouseLocation) else { return }
    }
    isHovered = hovered
    if wasHovered != hovered {
      setSelectionState(active: isActiveSelection, selected: isSelected, selectionCount: selectedGroupCount)
      if !hovered {
        onHoverExit(index)
      }
    }
  }

  override func mouseEntered(with event: NSEvent) {
    setHoverState(true, notifySelection: true, mouseLocation: event.locationInWindow)
  }

  override func mouseMoved(with event: NSEvent) {
    setHoverState(true, notifySelection: true, mouseLocation: event.locationInWindow)
  }

  override func mouseExited(with event: NSEvent) {
    setHoverState(false, notifySelection: false)
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      mouseDownLocation = nil
      onPaste(index)
    } else {
      mouseDownLocation = convert(event.locationInWindow, from: nil)
      onSelect(index, selectionMode(from: event.modifierFlags))
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
    onSelect(index, .activate)
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
    onSelect(index, isSelected ? .activate : .replace)
    return contextMenu()
  }

  #if DEBUG
  private(set) var debugPreviewSummary = ""
  private(set) var debugPreviewStyle = ""
  private(set) var debugAnimatedPresentationChangeCount = 0
  private(set) var debugHeaderBadgeSymbol = ""
  private(set) var debugHeaderBadgeText = ""
  private(set) var debugHeaderTitle = ""
  private(set) var debugHeaderSubtitle = ""
  private(set) var debugHeaderColorHex = ""
  private(set) var debugTextPreviewTitle = ""
  private(set) var debugTextPreviewBody = ""
  private(set) var debugTextPreviewChrome = ""
  private(set) var debugTextPreviewAccentHex = ""
  private(set) var debugTextPreviewFadePlacement = ""
  private(set) var debugLinkPreviewChrome = ""
  private(set) var debugLinkPreviewHostText = ""
  private(set) var debugLinkPreviewMonogram = ""
  private(set) var debugLinkPreviewAccentHex = ""
  private(set) var debugLinkPreviewHeroHeight: CGFloat = 0
  private(set) var debugLinkMediaPreviewChrome = ""
  private(set) var debugLinkMediaPreviewImageHeight: CGFloat = 0
  private(set) var debugLinkMediaPreviewHostText = ""
  private(set) var debugFilePreviewChrome = ""
  private(set) var debugFilePreviewExtensionText = ""
  private(set) var debugFilePreviewLocationPlacement = ""
  private(set) var debugFilePreviewCoverSize = NSSize.zero
  private(set) var debugColorPreviewChrome = ""
  private(set) var debugColorPreviewHexText = ""
  private(set) var debugColorPreviewSwatchPlacement = ""
  private(set) var debugColorPreviewChipSize = NSSize.zero
  private(set) var debugMediaMetricText = ""
  private(set) var debugMediaMetricPlacement = ""
  private(set) var debugAudioPreviewChrome = ""
  private(set) var debugAudioArtworkSize: CGFloat = 0
  private(set) var debugAudioLabelPlacement = ""
  private(set) var debugVideoPreviewChrome = ""
  private(set) var debugVideoFrameHeight: CGFloat = 0
  private(set) var debugVideoFormatPlacement = ""

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
    actionRailIsPresented ? actionRailButtons.map { $0.toolTip ?? "" } : []
  }

  var debugVisibleActionRailWidth: CGFloat {
    actionRailIsPresented ? actionRailContentWidth : 0
  }

  var debugActionRailAlpha: CGFloat {
    actionRail.alphaValue
  }

  var debugConstructedActionButtonCount: Int {
    actionRailButtons.count
  }

  var debugShadowOpacity: Float {
    layer?.shadowOpacity ?? 0
  }

  var debugShadowRadius: CGFloat {
    layer?.shadowRadius ?? 0
  }

  var debugLayerTranslationY: CGFloat {
    layer.map { CGFloat($0.transform.m42) } ?? 0
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

  var debugHeaderBadgeContentFrame: NSRect {
    guard let headerBadgeContentView else { return .zero }
    return headerBadgeContentView.convert(headerBadgeContentView.bounds, to: self)
  }

  var debugCompactMetricText: String {
    compactMetricLabel?.stringValue ?? ""
  }

  var debugCompactMetricIsHidden: Bool {
    compactMetricLabel?.isHidden ?? true
  }

  var debugCompactMetricFrame: NSRect {
    guard let compactMetricLabel else { return .zero }
    return compactMetricLabel.convert(compactMetricLabel.bounds, to: self)
  }

  var debugCompactMetricFittingWidth: CGFloat {
    compactMetricLabel?.fittingSize.width ?? 0
  }

  var debugHeaderBadgeMaskedCorners: CACornerMask {
    headerBadgeView?.layer?.maskedCorners ?? []
  }

  var debugHeaderFrame: NSRect {
    guard let compactContentView else { return .zero }
    return compactContentView.convert(compactContentView.bounds, to: self)
  }

  var debugHeaderMaskedCorners: CACornerMask {
    compactContentView?.layer?.maskedCorners ?? []
  }

  var debugExpandedDetailFrame: NSRect {
    guard let fullContentView else { return .zero }
    return fullContentView.convert(fullContentView.bounds, to: self)
  }

  var debugExpandedDetailPresentationHeight: CGFloat {
    guard let fullContentView else { return 0 }
    return fullContentView.layer?.presentation()?.bounds.height ?? fullContentView.bounds.height
  }

  var debugContentCornerRadius: CGFloat {
    contentView.layer?.cornerRadius ?? 0
  }

  var debugContentBackgroundAlpha: CGFloat {
    guard let backgroundColor = contentView.layer?.backgroundColor,
          let color = NSColor(cgColor: backgroundColor) else {
      return 0
    }
    return (color.usingColorSpace(.deviceRGB) ?? color).alphaComponent
  }

  var debugHeaderBadgeCornerRadius: CGFloat {
    headerBadgeView?.layer?.cornerRadius ?? 0
  }

  var debugHeaderBadgeShadowOpacity: Float {
    headerBadgeView?.layer?.shadowOpacity ?? 0
  }

  var debugHeaderBadgeShadowRadius: CGFloat {
    headerBadgeView?.layer?.shadowRadius ?? 0
  }

  var debugHeaderBadgeBorderWidth: CGFloat {
    headerBadgeView?.layer?.borderWidth ?? 0
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

  func debugPerformMenuItem(titled title: String) {
    guard let item = contextMenu().items.first(where: { $0.title == title }) else { return }
    _ = item.target?.perform(item.action, with: item)
  }

  func debugPerformCaptureRuleMenuItem(titled title: String) {
    guard let rulesMenu = contextMenu().items.first(where: { $0.title == "Capture Rules" })?.submenu,
          let item = rulesMenu.items.first(where: { $0.title == title }) else {
      return
    }
    _ = item.target?.perform(item.action, with: item)
  }

  var debugQuickPasteBadgeText: String? {
    quickPasteBadgeLabel?.stringValue
  }

  var debugIsKeyboardFocused: Bool {
    isKeyboardFocused
  }

  var debugIsSelected: Bool {
    isSelected
  }

  var debugIsActiveSelection: Bool {
    isActiveSelection
  }

  var debugIsHovered: Bool {
    isHovered
  }

  var debugPresentation: String {
    switch presentation {
    case .expanded:
      return "expanded"
    case .horizontalIcon:
      return "horizontal-icon"
    case .horizontalFocus:
      return "horizontal-focus"
    case .verticalRow:
      return "vertical-row"
    case .verticalFocus:
      return "vertical-focus"
    }
  }

  func debugSetHovered(_ hovered: Bool, mouseLocation: NSPoint? = nil) {
    setHoverState(hovered, notifySelection: hovered, mouseLocation: mouseLocation)
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
    addMenuItem(selectedGroupCount > 1 ? "Paste Selection" : "Paste", action: #selector(pasteFromMenu), to: menu)
    addMenuItem(selectedGroupCount > 1 ? "Copy Selection" : "Copy", action: #selector(copyFromMenu), to: menu)
    if canPlainText {
      addMenuItem("Paste Plain Text", action: #selector(pastePlainTextFromMenu), to: menu)
      addMenuItem("Copy Plain Text", action: #selector(copyPlainTextFromMenu), to: menu)
    }
    if selectedGroupCount > 1 {
      addMenuItem("Paste Selection as Text", action: #selector(pasteSelectionTextFromMenu), to: menu)
      addMenuItem("Copy Selection as Text", action: #selector(copySelectionTextFromMenu), to: menu)
      addMenuItem("Add Selection to Stack", action: #selector(addSelectionToStackFromMenu), to: menu)
    }
    if canShowInClipboard {
      addMenuItem("Show in Clipboard", action: #selector(showInClipboardFromMenu), to: menu)
    }
    addMenuItem("Rename...", action: #selector(renameFromMenu), to: menu)
    addMenuItem(itemIsStacked ? "Remove from Stack" : "Add to Stack", action: #selector(toggleStackFromMenu), to: menu)
    addMenuItem("Add Visible Clips to Stack", action: #selector(addVisibleToStackFromMenu), to: menu)
    if stackCount > 0 {
      addMenuItem("Paste Stack Next", action: #selector(pasteStackNextFromMenu), to: menu)
      addMenuItem("Copy Stack Next", action: #selector(copyStackNextFromMenu), to: menu)
      addMenuItem("Paste Stack as Text", action: #selector(pasteStackTextFromMenu), to: menu)
      addMenuItem("Copy Stack as Text", action: #selector(copyStackTextFromMenu), to: menu)
      addMenuItem("Clear Stack", action: #selector(clearStackFromMenu), to: menu)
    }
    if canEditText {
      addMenuItem("Edit", action: #selector(editTextFromMenu), to: menu)
    }
    if canRotateImage {
      addMenuItem("Rotate Image", action: #selector(rotateImageFromMenu), to: menu)
    }
    if canExtractImageText {
      addMenuItem("Extract Text", action: #selector(extractImageTextFromMenu), to: menu)
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

  private static func sourceMonogram(from value: String?) -> String? {
    guard let text = presentSourceText(value) else { return nil }
    let words = text
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .map(\.clipboardTrimmed)
      .filter { !$0.isEmpty }
    let initials = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    return initials.isEmpty ? nil : initials
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
    case .url, .file, .image, .pdf, .audio, .video:
      return true
    case .text, .richText, .unknown, .color, .code:
      return false
    }
  }

  private var canPreview: Bool {
    switch itemKind {
    case .text, .url, .image, .richText, .file, .pdf, .audio, .unknown, .color, .code, .video:
      return true
    }
  }

  private var canEditText: Bool {
    itemKind == .text || itemKind == .code
  }

  private var canRotateImage: Bool {
    itemKind == .image
  }

  private var canExtractImageText: Bool {
    itemKind == .image
  }

  private var canPlainText: Bool {
    switch itemKind {
    case .url, .image, .richText, .file, .pdf, .audio, .color, .video:
      return true
    case .text, .unknown, .code:
      return false
    }
  }

  private var canReveal: Bool {
    switch itemKind {
    case .file, .image, .pdf, .audio, .video:
      return true
    case .text, .richText, .url, .unknown, .color, .code:
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
    actionRail.layer?.backgroundColor = Palette.actionRailBackground
    actionRail.layer?.borderWidth = 0.5
    actionRail.layer?.borderColor = Palette.actionRailBorder
    actionRail.layer?.shadowColor = NSColor.black.cgColor
    actionRail.layer?.shadowOpacity = 0.12
    actionRail.layer?.shadowRadius = 8
    actionRail.layer?.shadowOffset = NSSize(width: 0, height: 3)
    actionRail.translatesAutoresizingMaskIntoConstraints = false
    actionRail.alphaValue = 0
    actionRail.isHidden = true
    actionRail.heightAnchor.constraint(equalToConstant: layout.actionRailHeight).isActive = true
    actionRail.setContentHuggingPriority(.required, for: .horizontal)
    actionRail.setContentCompressionResistancePriority(.required, for: .horizontal)

    actionRailWidthConstraint = actionRail.widthAnchor.constraint(equalToConstant: 0)
    actionRailWidthConstraint?.isActive = true
    updateActionRailVisibility()
  }

  private func ensureActionRailButtons() {
    guard actionRailButtons.isEmpty else { return }

    let specs = fittedActionRailButtonSpecs(from: preferredActionRailButtonSpecs())
    let buttons = specs.map { spec in
      cardActionButton(
        spec.systemName,
        toolTip: spec.toolTip,
        action: spec.action,
        isPrimary: spec.isPrimary
      )
    }

    for button in buttons {
      actionRail.addArrangedSubview(button)
    }
    actionRailButtons = buttons
    let contentWidth = actionRailWidth(for: specs)
    actionRailContentWidth = contentWidth
    if actionRailIsPresented {
      actionRailWidthConstraint?.constant = contentWidth
    }
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
    if canRotateImage {
      specs.append(ActionRailButtonSpec("rotate.right", toolTip: "Rotate Image", action: #selector(rotateImageFromMenu), overflowPriority: 50))
    }
    if canExtractImageText {
      specs.append(ActionRailButtonSpec("text.viewfinder", toolTip: "Extract Text", action: #selector(extractImageTextFromMenu), overflowPriority: 55))
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
    layout.width - (Metrics.actionRailLeadingMargin * 2)
  }

  private var summaryHeaderHeight: CGFloat {
    ClipboardCardPresentation.verticalRow.size(for: layout).height
  }

  private var expandedDetailHeight: CGFloat {
    max(0, layout.height - summaryHeaderHeight)
  }

  private var expandedBodyHeight: CGFloat {
    max(1, expandedDetailHeight - layout.footerHeight)
  }

  private var headerBadgeSize: CGFloat {
    summaryHeaderHeight
  }

  private var verticalHeaderCornerRadius: CGFloat {
    min(layout.width, summaryHeaderHeight) / 3
  }

  private var headerBadgeCornerRadius: CGFloat {
    layout.isCompact ? 13 : 15
  }

  private var headerBadgeIconInset: CGFloat {
    layout.isCompact ? 7 : 8
  }

  private var headerBadgeAppIconBleed: CGFloat {
    layout.isCompact ? 6 : 7
  }

  private var stackCornerButtonSize: CGFloat {
    layout.isCompact ? 28 : 30
  }

  private var actionRailHeaderTopInset: CGFloat {
    max(8, (layout.headerHeight - layout.actionRailHeight) / 2)
  }

  private func cardCornerRadius(for presentation: ClipboardCardPresentation, size: NSSize) -> CGFloat {
    switch presentation {
    case .verticalRow, .verticalFocus:
      return verticalHeaderCornerRadius
    case .horizontalIcon:
      return min(size.width, size.height) / 2
    case .horizontalFocus:
      return min(size.width, size.height) / 3
    case .expanded:
      return 8
    }
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
      button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.92).cgColor
      button.contentTintColor = .white
    } else if toolTip == "Collect" {
      button.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.86).cgColor
      button.contentTintColor = .white
    } else if toolTip == "Delete" {
      button.layer?.backgroundColor = NSColor.clear.cgColor
      button.contentTintColor = NSColor.systemRed.withAlphaComponent(0.78)
    } else {
      button.layer?.backgroundColor = Palette.secondaryActionBackground
      button.contentTintColor = NSColor.labelColor.withAlphaComponent(0.74)
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
    let shouldShowActionRail = presentation.showsFloatingActions && (isHovered || (isActiveSelection && isKeyboardFocused))
    if shouldShowActionRail {
      ensureActionRailButtons()
    }
    let targetWidth = shouldShowActionRail ? actionRailContentWidth : 0
    let visibilityChanged = actionRailIsPresented != shouldShowActionRail
    actionRailIsPresented = shouldShowActionRail
    headerBadgeView?.isHidden = false
    headerPinView?.isHidden = isActiveSelection
    footerDetailLabel.isHidden = false
    stackCornerButton.isHidden = !presentation.showsFloatingActions || !(itemIsStacked || isKeyboardFocused)
    stackCornerButton.alphaValue = itemIsStacked ? 1.0 : 0.94
    for button in actionRailButtons {
      button.alphaValue = 1.0
    }

    guard window != nil, visibilityChanged else {
      actionRailWidthConstraint?.constant = targetWidth
      actionRail.alphaValue = shouldShowActionRail ? 1 : 0
      actionRail.isHidden = !shouldShowActionRail
      return
    }

    if shouldShowActionRail {
      actionRailWidthConstraint?.constant = targetWidth
      actionRail.isHidden = false
      actionRail.alphaValue = max(actionRail.alphaValue, 0.01)
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = ClipboardPanelView.Motion.actionRailDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      actionRail.animator().alphaValue = shouldShowActionRail ? 1 : 0
    } completionHandler: { [weak self] in
      guard let self else { return }
      self.actionRailWidthConstraint?.constant = targetWidth
      self.actionRail.alphaValue = shouldShowActionRail ? 1 : 0
      self.actionRail.isHidden = !shouldShowActionRail
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

  @objc private func pasteSelectionTextFromMenu() {
    onPasteSelectionText(index)
  }

  @objc private func copySelectionTextFromMenu() {
    onCopySelectionText(index)
  }

  @objc private func addSelectionToStackFromMenu() {
    onAddSelectionToStack(index)
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

  @objc private func addVisibleToStackFromMenu() {
    onAddVisibleToStack()
  }

  @objc private func toggleStackFromCornerButton() {
    onSelect(index, .activate)
    onToggleStack(index)
  }

  @objc private func pasteStackNextFromMenu() {
    onPasteStackNext()
  }

  @objc private func copyStackNextFromMenu() {
    onCopyStackNext()
  }

  @objc private func pasteStackTextFromMenu() {
    onPasteStackText()
  }

  @objc private func copyStackTextFromMenu() {
    onCopyStackText()
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

  @objc private func rotateImageFromMenu() {
    onRotateImage(index)
  }

  @objc private func extractImageTextFromMenu() {
    onExtractImageText(index)
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
    widthConstraint = widthAnchor.constraint(equalToConstant: layout.width)
    heightConstraint = heightAnchor.constraint(equalToConstant: layout.height)
    widthConstraint?.isActive = true
    heightConstraint?.isActive = true
    focusRingType = .none

    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = 8
    contentView.layer?.masksToBounds = true
    contentView.layer?.borderWidth = 1
    contentView.layer?.borderColor = Palette.border
    contentView.layer?.backgroundColor = Palette.cardSurface
    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)

    let header = compactSummaryView(for: item)
    let body = bodyView(for: item, thumbnail: thumbnail)
    let footer = footerView(for: item)
    let fullContainer = NSView()
    fullContainer.wantsLayer = true
    fullContainer.layer?.masksToBounds = true
    fullContainer.layer?.backgroundColor = NSColor.clear.cgColor
    fullContainer.translatesAutoresizingMaskIntoConstraints = false
    fullContentView = fullContainer

    let stack = NSStackView(views: [body, footer])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    fullContainer.addSubview(stack)
    contentView.addSubview(header)
    contentView.addSubview(fullContainer)

    header.translatesAutoresizingMaskIntoConstraints = false
    compactContentView = header
    let detailHeightConstraint = fullContainer.heightAnchor.constraint(equalToConstant: expandedDetailHeight)
    expandedDetailHeightConstraint = detailHeightConstraint

    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentView.topAnchor.constraint(equalTo: topAnchor),
      contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    fullContentConstraints = [
      fullContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      fullContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      fullContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
      detailHeightConstraint,
      stack.leadingAnchor.constraint(equalTo: fullContainer.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: fullContainer.trailingAnchor),
      stack.topAnchor.constraint(equalTo: fullContainer.topAnchor),
      body.widthAnchor.constraint(equalTo: stack.widthAnchor),
      footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
    ]
    compactContentConstraints = [
      header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      header.topAnchor.constraint(equalTo: contentView.topAnchor),
      header.heightAnchor.constraint(equalToConstant: summaryHeaderHeight)
    ]
    NSLayoutConstraint.activate(fullContentConstraints)
    NSLayoutConstraint.activate(compactContentConstraints)

    configureStackCornerButton()
    contentView.addSubview(stackCornerButton)
    addSubview(actionRail)
    NSLayoutConstraint.activate([
      stackCornerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      stackCornerButton.centerYAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -layout.footerHeight),
      stackCornerButton.widthAnchor.constraint(equalToConstant: stackCornerButtonSize),
      stackCornerButton.heightAnchor.constraint(equalToConstant: stackCornerButtonSize),
      actionRail.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      actionRail.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 5)
    ])
    setPresentation(.expanded)
    setSelected(false)
  }

  private func compactSummaryView(for item: ClipboardItem) -> NSView {
    let header = NSView()
    header.wantsLayer = true
    header.layer?.backgroundColor = headerColor(for: item).withAlphaComponent(0.96).cgColor
    header.layer?.cornerRadius = verticalHeaderCornerRadius
    header.layer?.maskedCorners = CornerMasks.topOnly
    header.layer?.masksToBounds = true
    header.layer?.zPosition = 2

    let title = NSTextField(labelWithString: headerTitle(for: item))
    title.font = .systemFont(ofSize: layout.isCompact ? 15 : 16, weight: .semibold)
    title.textColor = .white
    title.lineBreakMode = .byTruncatingTail
    title.maximumNumberOfLines = 1
    title.toolTip = title.stringValue

    let subtitle = NSTextField(labelWithString: headerSubtitle(for: item))
    subtitle.font = .systemFont(ofSize: layout.isCompact ? 10 : 11, weight: .regular)
    subtitle.textColor = NSColor.white.withAlphaComponent(0.78)
    subtitle.lineBreakMode = .byTruncatingTail
    subtitle.maximumNumberOfLines = 1
    subtitle.toolTip = subtitle.stringValue

    let titleAndSubtitle = NSStackView(views: [title, subtitle])
    titleAndSubtitle.orientation = .vertical
    titleAndSubtitle.alignment = .leading
    titleAndSubtitle.spacing = 2
    titleAndSubtitle.translatesAutoresizingMaskIntoConstraints = false
    compactTextStack = titleAndSubtitle

    let metricLabel = compactMetricLabel(for: item)
    compactMetricLabel = metricLabel

    var labelViews: [NSView] = []
    if let quickPasteBadge = quickPasteBadge() {
      labelViews.append(quickPasteBadge)
    }
    labelViews.append(titleAndSubtitle)
    labelViews.append(metricLabel)
    let labelStack = NSStackView(views: labelViews)
    labelStack.orientation = .horizontal
    labelStack.alignment = .centerY
    labelStack.distribution = .fill
    labelStack.detachesHiddenViews = true
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
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    title.setContentHuggingPriority(.defaultLow, for: .horizontal)
    subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
    titleAndSubtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
    titleAndSubtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    metricLabel.setContentHuggingPriority(.required, for: .horizontal)
    metricLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

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

  private func compactMetricLabel(for item: ClipboardItem) -> NSTextField {
    let label = NSTextField(labelWithString: compactMetricText(for: item))
    label.font = .monospacedDigitSystemFont(ofSize: layout.isCompact ? 10 : 11, weight: .semibold)
    label.textColor = NSColor.white.withAlphaComponent(0.82)
    label.alignment = .right
    label.lineBreakMode = .byClipping
    label.maximumNumberOfLines = 1
    label.toolTip = detailMetricText(for: item)
    label.isHidden = true
    return label
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
    body.heightAnchor.constraint(equalToConstant: expandedBodyHeight).isActive = true

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
    #if !DEBUG
    return lightweightPreviewView(for: item, thumbnail: thumbnail)
    #else
    if item.kind == .image, let thumbnail {
      return mediaPreviewView(for: item, thumbnail: thumbnail)
    }

    switch item.kind {
    case .url:
      if let thumbnail {
        return linkMediaPreviewView(for: item, thumbnail: thumbnail)
      }
      return linkPreviewView(for: item)
    case .file:
      if let thumbnail {
        return mediaPreviewView(for: item, thumbnail: thumbnail)
      }
      if FilePayload.paths(from: item.payload).count > 1 {
        return multiFilePreviewView(for: item)
      }
      return filePreviewView(for: item)
    case .pdf:
      if let thumbnail {
        return mediaPreviewView(for: item, thumbnail: thumbnail)
      }
      return filePreviewView(for: item)
    case .audio:
      return audioPreviewView(for: item)
    case .video:
      if let thumbnail {
        return videoMediaPreviewView(for: item, thumbnail: thumbnail)
      }
      return videoPreviewView(for: item)
    case .color:
      return colorPreviewView(for: item)
    case .code:
      return codePreviewView(for: item)
    case .text, .richText, .image, .unknown:
      return textPreviewView(for: item)
    }
    #endif
  }

  private func lightweightPreviewView(for item: ClipboardItem, thumbnail: NSImage?) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.055).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(wrappingLabelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: layout.isCompact ? 13 : 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = thumbnail == nil ? 3 : 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let detail = NSTextField(wrappingLabelWithString: previewText(for: item))
    detail.font = .systemFont(ofSize: layout.isCompact ? 11 : 12)
    detail.textColor = .secondaryLabelColor
    detail.maximumNumberOfLines = thumbnail == nil ? 2 : 1
    detail.lineBreakMode = .byTruncatingTail
    detail.toolTip = detail.stringValue

    let textStack = NSStackView(views: [title, detail])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 4
    textStack.translatesAutoresizingMaskIntoConstraints = false

    if let thumbnail {
      let imageView = NSImageView(image: thumbnail)
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.wantsLayer = true
      imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
      imageView.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(imageView)
      container.addSubview(textStack)
      NSLayoutConstraint.activate([
        imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        imageView.topAnchor.constraint(equalTo: container.topAnchor),
        imageView.heightAnchor.constraint(equalToConstant: min(layout.bodyHeight * 0.58, layout.isCompact ? 94 : 112)),
        textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
        textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
        textStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
        textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
        title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        detail.widthAnchor.constraint(equalTo: textStack.widthAnchor)
      ])
    } else {
      let icon = headerIcon(headerBadgeSymbol(for: item.kind), color: accentColor(for: item.kind))
      icon.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(icon)
      container.addSubview(textStack)
      NSLayoutConstraint.activate([
        icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
        icon.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.isCompact ? 16 : 18),
        icon.widthAnchor.constraint(equalToConstant: layout.isCompact ? 30 : 34),
        icon.heightAnchor.constraint(equalToConstant: layout.isCompact ? 30 : 34),
        textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
        textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
        textStack.topAnchor.constraint(equalTo: icon.topAnchor, constant: -1),
        title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        detail.widthAnchor.constraint(equalTo: textStack.widthAnchor)
      ])
    }
    return container
  }

  private func textPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    let accent = accentColor(for: item.kind)
    let paperColor = NSColor.windowBackgroundColor.withAlphaComponent(0.76)
    container.wantsLayer = true
    container.layer?.backgroundColor = accent.withAlphaComponent(0.035).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let titleString = titleText(for: item)
    let bodyString = previewBodyText(for: item, title: titleString)
    #if DEBUG
    debugTextPreviewTitle = titleString
    debugTextPreviewBody = bodyString ?? ""
    debugTextPreviewChrome = "paper-preview"
    debugTextPreviewAccentHex = Self.debugHex(accent)
    debugTextPreviewFadePlacement = bodyString == nil ? "none" : "bottom"
    #endif
    let title = NSTextField(wrappingLabelWithString: titleString)
    title.font = bodyString == nil
      ? .systemFont(ofSize: item.kind == .richText ? 16 : 15, weight: .semibold)
      : .systemFont(ofSize: 13, weight: .bold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = bodyString == nil ? 4 : 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    var textViews: [NSView] = [title]
    if let bodyString {
      let detail = NSTextField(wrappingLabelWithString: bodyString)
      detail.font = .systemFont(ofSize: item.kind == .richText ? 15 : 14)
      detail.textColor = .secondaryLabelColor
      detail.maximumNumberOfLines = layout.isCompact ? 4 : 5
      detail.lineBreakMode = .byTruncatingTail
      detail.toolTip = detail.stringValue
      textViews.append(detail)
    }

    let stack = NSStackView(views: textViews)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = bodyString == nil ? 0 : 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    let paper = NSView()
    paper.wantsLayer = true
    paper.layer?.cornerRadius = layout.isCompact ? 8 : 10
    paper.layer?.backgroundColor = paperColor.cgColor
    paper.layer?.borderWidth = 0.8
    paper.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
    paper.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(paper)
    paper.addSubview(stack)
    let fade = bodyString == nil ? nil : textPreviewBottomFade(color: paperColor)
    if let fade {
      paper.addSubview(fade)
    }
    for view in textViews {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    var constraints = [
      paper.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      paper.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      paper.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.isCompact ? 12 : 14),
      paper.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: layout.isCompact ? -12 : -14),
      stack.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: layout.isCompact ? 12 : 14),
      stack.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: layout.isCompact ? -12 : -14),
      stack.topAnchor.constraint(equalTo: paper.topAnchor, constant: layout.isCompact ? 12 : 14),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: paper.bottomAnchor, constant: layout.isCompact ? -12 : -14)
    ]
    if let fade {
      constraints += [
        fade.leadingAnchor.constraint(equalTo: paper.leadingAnchor),
        fade.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
        fade.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
        fade.heightAnchor.constraint(equalToConstant: layout.isCompact ? 24 : 30)
      ]
    }
    NSLayoutConstraint.activate(constraints)
    return container
  }

  private func textPreviewBottomFade(color: NSColor) -> NSView {
    let fade = TextPreviewBottomFadeView(color: color)
    fade.translatesAutoresizingMaskIntoConstraints = false
    return fade
  }

  private func linkPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.22).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let hostText = webHostText(from: item.payload) ?? "Link"
    let siteColor = linkVisualColor(for: hostText)
    let monogramText = linkMonogram(from: hostText)
    let heroHeight = linkPreviewHeroHeight
    #if DEBUG
    debugLinkPreviewChrome = "browser-card"
    debugLinkPreviewHostText = hostText
    debugLinkPreviewMonogram = monogramText
    debugLinkPreviewAccentHex = Self.debugHex(siteColor)
    debugLinkPreviewHeroHeight = heroHeight
    #endif

    let hero = NSView()
    hero.wantsLayer = true
    hero.layer?.backgroundColor = siteColor.withAlphaComponent(0.09).cgColor
    hero.translatesAutoresizingMaskIntoConstraints = false
    hero.heightAnchor.constraint(equalToConstant: heroHeight).isActive = true

    let browser = NSView()
    browser.wantsLayer = true
    browser.layer?.cornerRadius = 14
    browser.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.74).cgColor
    browser.layer?.borderWidth = 0.8
    browser.layer?.borderColor = NSColor.white.withAlphaComponent(0.78).cgColor
    browser.layer?.shadowColor = NSColor.black.cgColor
    browser.layer?.shadowOpacity = 0.10
    browser.layer?.shadowRadius = 8
    browser.layer?.shadowOffset = NSSize(width: 0, height: 3)
    browser.translatesAutoresizingMaskIntoConstraints = false

    let dotStack = NSStackView(views: [
      browserDot(NSColor.systemRed.withAlphaComponent(0.74)),
      browserDot(NSColor.systemYellow.withAlphaComponent(0.74)),
      browserDot(NSColor.systemGreen.withAlphaComponent(0.74))
    ])
    dotStack.orientation = .horizontal
    dotStack.alignment = .centerY
    dotStack.spacing = 4
    dotStack.translatesAutoresizingMaskIntoConstraints = false

    let addressPill = NSView()
    addressPill.wantsLayer = true
    addressPill.layer?.cornerRadius = 6
    addressPill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    addressPill.translatesAutoresizingMaskIntoConstraints = false

    let host = NSTextField(labelWithString: hostText)
    host.font = .systemFont(ofSize: layout.isCompact ? 8 : 8.5, weight: .medium)
    host.textColor = .secondaryLabelColor
    host.maximumNumberOfLines = 1
    host.lineBreakMode = .byTruncatingMiddle
    host.toolTip = host.stringValue
    host.translatesAutoresizingMaskIntoConstraints = false
    addressPill.addSubview(host)

    let favicon = NSView()
    favicon.wantsLayer = true
    favicon.layer?.cornerRadius = 10
    favicon.layer?.backgroundColor = siteColor.cgColor
    favicon.layer?.shadowColor = NSColor.black.cgColor
    favicon.layer?.shadowOpacity = 0.12
    favicon.layer?.shadowRadius = 5
    favicon.layer?.shadowOffset = NSSize(width: 0, height: 2)
    favicon.translatesAutoresizingMaskIntoConstraints = false

    let monogram = NSTextField(labelWithString: monogramText)
    monogram.font = .systemFont(ofSize: layout.isCompact ? 13 : 15, weight: .heavy)
    monogram.textColor = .white
    monogram.alignment = .center
    monogram.lineBreakMode = .byClipping
    monogram.maximumNumberOfLines = 1
    monogram.translatesAutoresizingMaskIntoConstraints = false
    favicon.addSubview(monogram)

    let lineStack = NSStackView(views: [
      previewLine(color: siteColor.withAlphaComponent(0.44)),
      previewLine(color: NSColor.labelColor.withAlphaComponent(0.14)),
      previewLine(color: NSColor.labelColor.withAlphaComponent(0.09))
    ])
    lineStack.orientation = .vertical
    lineStack.alignment = .leading
    lineStack.spacing = 5
    lineStack.translatesAutoresizingMaskIntoConstraints = false
    for (index, view) in lineStack.arrangedSubviews.enumerated() {
      view.heightAnchor.constraint(equalToConstant: index == 0 ? 7 : 5).isActive = true
    }

    browser.addSubview(dotStack)
    browser.addSubview(addressPill)
    browser.addSubview(favicon)
    browser.addSubview(lineStack)
    hero.addSubview(browser)

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
      browser.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: layout.inset),
      browser.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -layout.inset),
      browser.topAnchor.constraint(equalTo: hero.topAnchor, constant: linkPreviewBrowserInset),
      browser.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -linkPreviewBrowserInset),
      dotStack.leadingAnchor.constraint(equalTo: browser.leadingAnchor, constant: 12),
      dotStack.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),
      addressPill.leadingAnchor.constraint(equalTo: dotStack.trailingAnchor, constant: 10),
      addressPill.trailingAnchor.constraint(equalTo: browser.trailingAnchor, constant: -12),
      addressPill.topAnchor.constraint(equalTo: browser.topAnchor, constant: 9),
      addressPill.heightAnchor.constraint(equalToConstant: 14),
      host.leadingAnchor.constraint(equalTo: addressPill.leadingAnchor, constant: 7),
      host.trailingAnchor.constraint(equalTo: addressPill.trailingAnchor, constant: -7),
      host.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),
      favicon.leadingAnchor.constraint(equalTo: browser.leadingAnchor, constant: 12),
      favicon.topAnchor.constraint(equalTo: addressPill.bottomAnchor, constant: linkPreviewContentGap),
      favicon.widthAnchor.constraint(equalToConstant: linkPreviewFaviconSize),
      favicon.heightAnchor.constraint(equalToConstant: linkPreviewFaviconSize),
      monogram.leadingAnchor.constraint(equalTo: favicon.leadingAnchor, constant: 4),
      monogram.trailingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: -4),
      monogram.centerYAnchor.constraint(equalTo: favicon.centerYAnchor),
      lineStack.leadingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 10),
      lineStack.trailingAnchor.constraint(equalTo: browser.trailingAnchor, constant: -14),
      lineStack.centerYAnchor.constraint(equalTo: favicon.centerYAnchor),
      lineStack.arrangedSubviews[0].widthAnchor.constraint(equalTo: lineStack.widthAnchor),
      lineStack.arrangedSubviews[1].widthAnchor.constraint(equalTo: lineStack.widthAnchor, multiplier: 0.78),
      lineStack.arrangedSubviews[2].widthAnchor.constraint(equalTo: lineStack.widthAnchor, multiplier: 0.54),
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      textStack.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 10),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
      title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      address.widthAnchor.constraint(equalTo: textStack.widthAnchor)
    ])
    return container
  }

  private var linkPreviewHeroHeight: CGFloat {
    if layout == .expanded {
      return 128
    }
    return layout.isCompact ? 78 : 88
  }

  private var linkPreviewBrowserInset: CGFloat {
    layout.isCompact ? 9 : 10
  }

  private var linkPreviewContentGap: CGFloat {
    layout.isCompact ? 7 : 9
  }

  private var linkPreviewFaviconSize: CGFloat {
    if layout == .expanded {
      return 38
    }
    return layout.isCompact ? 28 : 32
  }

  private func browserDot(_ color: NSColor) -> NSView {
    let dot = NSView()
    dot.wantsLayer = true
    dot.layer?.cornerRadius = 3
    dot.layer?.backgroundColor = color.cgColor
    dot.translatesAutoresizingMaskIntoConstraints = false
    dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
    dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
    return dot
  }

  private func previewLine(color: NSColor) -> NSView {
    let line = NSView()
    line.wantsLayer = true
    line.layer?.cornerRadius = 2.5
    line.layer?.backgroundColor = color.cgColor
    line.translatesAutoresizingMaskIntoConstraints = false
    return line
  }

  private func linkMediaPreviewView(for item: ClipboardItem, thumbnail: NSImage) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.22).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let hostText = webHostText(from: item.payload) ?? "Link"
    let imageHeight = linkMediaPreviewImageHeight
    #if DEBUG
    debugLinkMediaPreviewChrome = "thumbnail-card"
    debugLinkMediaPreviewImageHeight = imageHeight
    debugLinkMediaPreviewHostText = hostText
    #endif

    let imageView = AspectFillImageView(image: thumbnail)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.heightAnchor.constraint(equalToConstant: imageHeight).isActive = true

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
    container.addSubview(textStack)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: container.topAnchor),
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      textStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
      title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      address.widthAnchor.constraint(equalTo: textStack.widthAnchor)
    ])
    return container
  }

  private var linkMediaPreviewImageHeight: CGFloat {
    if layout == .expanded {
      return 146
    }
    return layout.isCompact ? 80 : 96
  }

  private func filePreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    let accent = accentColor(for: item.kind)
    let extensionText = detailMetricText(for: item)
    let coverSize = filePreviewCoverSize
    #if DEBUG
    debugFilePreviewChrome = "document-cover"
    debugFilePreviewExtensionText = extensionText
    debugFilePreviewLocationPlacement = "below-cover"
    debugFilePreviewCoverSize = coverSize
    #endif
    container.wantsLayer = true
    container.layer?.backgroundColor = accent.withAlphaComponent(0.045).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let cover = documentCoverPreviewView(for: item, extensionText: extensionText, accent: accent)

    let title = NSTextField(wrappingLabelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: layout.isCompact ? 13 : 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let location = NSTextField(labelWithString: previewText(for: item))
    location.font = .systemFont(ofSize: layout.isCompact ? 11 : 12)
    location.textColor = .secondaryLabelColor
    location.maximumNumberOfLines = 1
    location.lineBreakMode = .byTruncatingMiddle
    location.toolTip = location.stringValue

    let textStack = NSStackView(views: [title, location])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 3
    textStack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(cover)
    container.addSubview(textStack)

    NSLayoutConstraint.activate([
      cover.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      cover.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.isCompact ? 10 : 12),
      cover.widthAnchor.constraint(equalToConstant: coverSize.width),
      cover.heightAnchor.constraint(equalToConstant: coverSize.height),
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      textStack.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: layout.isCompact ? 8 : 10),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
      title.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      location.widthAnchor.constraint(equalTo: textStack.widthAnchor)
    ])
    return container
  }

  private var filePreviewCoverSize: NSSize {
    if layout == .expanded {
      return NSSize(width: 148, height: 126)
    }
    if layout.isCompact {
      return NSSize(width: 104, height: 74)
    }
    return NSSize(width: 118, height: 86)
  }

  private func documentCoverPreviewView(for item: ClipboardItem, extensionText: String, accent: NSColor) -> NSView {
    let cover = NSView()
    cover.wantsLayer = true
    cover.layer?.cornerRadius = layout.isCompact ? 8 : 10
    cover.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.74).cgColor
    cover.layer?.borderWidth = 0.8
    cover.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.14).cgColor
    cover.layer?.shadowColor = NSColor.black.cgColor
    cover.layer?.shadowOpacity = 0.10
    cover.layer?.shadowRadius = 7
    cover.layer?.shadowOffset = NSSize(width: 0, height: 3)
    cover.translatesAutoresizingMaskIntoConstraints = false

    let band = NSView()
    band.wantsLayer = true
    band.layer?.cornerRadius = layout.isCompact ? 4 : 5
    band.layer?.backgroundColor = accent.withAlphaComponent(0.82).cgColor
    band.translatesAutoresizingMaskIntoConstraints = false

    let fold = NSView()
    fold.wantsLayer = true
    fold.layer?.cornerRadius = layout.isCompact ? 4 : 5
    fold.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
    fold.layer?.borderWidth = 0.6
    fold.layer?.borderColor = accent.withAlphaComponent(0.18).cgColor
    fold.translatesAutoresizingMaskIntoConstraints = false

    let iconName = item.kind == .pdf ? "doc.richtext.fill" : "doc.fill"
    let icon = headerIcon(iconName, color: accent)
    icon.translatesAutoresizingMaskIntoConstraints = false

    let lineStack = NSStackView(views: [
      previewLine(color: accent.withAlphaComponent(0.36)),
      previewLine(color: NSColor.labelColor.withAlphaComponent(0.13)),
      previewLine(color: NSColor.labelColor.withAlphaComponent(0.09))
    ])
    lineStack.orientation = .vertical
    lineStack.alignment = .leading
    lineStack.spacing = layout.isCompact ? 4 : 5
    lineStack.translatesAutoresizingMaskIntoConstraints = false
    for (index, line) in lineStack.arrangedSubviews.enumerated() {
      line.heightAnchor.constraint(equalToConstant: index == 0 ? 6 : 5).isActive = true
    }

    let extensionPill = capsuleLabel(extensionText, color: accent)
    extensionPill.translatesAutoresizingMaskIntoConstraints = false

    cover.addSubview(band)
    cover.addSubview(fold)
    cover.addSubview(icon)
    cover.addSubview(lineStack)
    cover.addSubview(extensionPill)

    NSLayoutConstraint.activate([
      band.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: layout.isCompact ? 9 : 10),
      band.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: layout.isCompact ? -9 : -10),
      band.topAnchor.constraint(equalTo: cover.topAnchor, constant: layout.isCompact ? 8 : 9),
      band.heightAnchor.constraint(equalToConstant: layout.isCompact ? 7 : 8),
      fold.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: layout.isCompact ? -8 : -10),
      fold.topAnchor.constraint(equalTo: cover.topAnchor, constant: layout.isCompact ? 20 : 22),
      fold.widthAnchor.constraint(equalToConstant: layout.isCompact ? 18 : 21),
      fold.heightAnchor.constraint(equalToConstant: layout.isCompact ? 18 : 21),
      icon.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: layout.isCompact ? 14 : 16),
      icon.topAnchor.constraint(equalTo: band.bottomAnchor, constant: layout.isCompact ? 13 : 15),
      icon.widthAnchor.constraint(equalToConstant: layout.isCompact ? 26 : 30),
      icon.heightAnchor.constraint(equalToConstant: layout.isCompact ? 29 : 33),
      lineStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: layout.isCompact ? 9 : 11),
      lineStack.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: layout.isCompact ? -13 : -16),
      lineStack.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
      lineStack.arrangedSubviews[0].widthAnchor.constraint(equalTo: lineStack.widthAnchor),
      lineStack.arrangedSubviews[1].widthAnchor.constraint(equalTo: lineStack.widthAnchor, multiplier: 0.78),
      lineStack.arrangedSubviews[2].widthAnchor.constraint(equalTo: lineStack.widthAnchor, multiplier: 0.56),
      extensionPill.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      extensionPill.bottomAnchor.constraint(equalTo: cover.bottomAnchor, constant: layout.isCompact ? -7 : -9),
      extensionPill.widthAnchor.constraint(lessThanOrEqualTo: cover.widthAnchor, constant: -18)
    ])
    return cover
  }

  private func multiFilePreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.08).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let urls = FilePayload.urls(from: item.payload)
    let displayURLs = Array(urls.prefix(3))
    let tileViews = displayURLs.enumerated().map { offset, url in
      miniFileTile(for: url, index: offset, hiddenCount: max(0, urls.count - displayURLs.count))
    }
    let tileStack = NSStackView(views: tileViews)
    tileStack.orientation = .horizontal
    tileStack.alignment = .centerY
    tileStack.spacing = layout.isCompact ? 6 : 8
    tileStack.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(labelWithString: titleText(for: item))
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let location = NSTextField(labelWithString: previewText(for: item))
    location.font = .systemFont(ofSize: 12)
    location.textColor = .secondaryLabelColor
    location.maximumNumberOfLines = 1
    location.lineBreakMode = .byTruncatingMiddle
    location.toolTip = location.stringValue

    let labels = NSStackView(views: [title, location])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 3
    labels.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(tileStack)
    container.addSubview(labels)
    NSLayoutConstraint.activate([
      tileStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      tileStack.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.isCompact ? 14 : 16),
      labels.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      labels.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      labels.topAnchor.constraint(equalTo: tileStack.bottomAnchor, constant: layout.isCompact ? 10 : 12),
      labels.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
      title.widthAnchor.constraint(equalTo: labels.widthAnchor),
      location.widthAnchor.constraint(equalTo: labels.widthAnchor)
    ])
    return container
  }

  private func miniFileTile(for url: URL, index: Int, hiddenCount: Int) -> NSView {
    let tile = NSView()
    tile.wantsLayer = true
    tile.layer?.cornerRadius = 10
    tile.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.64).cgColor
    tile.layer?.borderWidth = 0.8
    tile.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.16).cgColor
    tile.layer?.shadowColor = NSColor.black.cgColor
    tile.layer?.shadowOpacity = 0.08
    tile.layer?.shadowRadius = 5
    tile.layer?.shadowOffset = NSSize(width: 0, height: 2)
    tile.translatesAutoresizingMaskIntoConstraints = false

    let iconName = url.hasDirectoryPath ? "folder.fill" : "doc.fill"
    let icon = headerIcon(iconName, color: accentColor(for: .file))
    icon.translatesAutoresizingMaskIntoConstraints = false

    let extensionText = fileKindText(from: url.path, fallback: url.hasDirectoryPath ? "DIR" : "FILE")
    let extensionPill = capsuleLabel(extensionText, color: accentColor(for: .file))
    extensionPill.translatesAutoresizingMaskIntoConstraints = false

    tile.addSubview(icon)
    tile.addSubview(extensionPill)

    var constraints = [
      tile.widthAnchor.constraint(equalToConstant: layout.isCompact ? 48 : 54),
      tile.heightAnchor.constraint(equalToConstant: layout.isCompact ? 58 : 64),
      icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor, constant: -7),
      icon.widthAnchor.constraint(equalToConstant: layout.isCompact ? 23 : 26),
      icon.heightAnchor.constraint(equalToConstant: layout.isCompact ? 26 : 29),
      extensionPill.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
      extensionPill.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -7),
      extensionPill.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -8)
    ]

    if hiddenCount > 0, index == 2 {
      let morePill = capsuleLabel("+\(hiddenCount)", color: NSColor.black.withAlphaComponent(0.52))
      morePill.translatesAutoresizingMaskIntoConstraints = false
      tile.addSubview(morePill)
      constraints += [
        morePill.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -5),
        morePill.topAnchor.constraint(equalTo: tile.topAnchor, constant: 5),
        morePill.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -10)
      ]
    }

    NSLayoutConstraint.activate(constraints)
    return tile
  }

  private func audioPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    let accent = accentColor(for: item.kind)
    container.wantsLayer = true
    container.layer?.backgroundColor = accent.withAlphaComponent(0.10).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let artworkSize = audioArtworkSize
    #if DEBUG
    debugAudioPreviewChrome = "album-card"
    debugAudioArtworkSize = artworkSize
    debugAudioLabelPlacement = "below-artwork"
    #endif

    let artwork = NSView()
    artwork.wantsLayer = true
    artwork.layer?.cornerRadius = layout.isCompact ? 14 : 16
    artwork.layer?.backgroundColor = accent.cgColor
    artwork.layer?.borderWidth = 1
    artwork.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
    artwork.layer?.shadowColor = NSColor.black.cgColor
    artwork.layer?.shadowOpacity = 0.16
    artwork.layer?.shadowRadius = 10
    artwork.layer?.shadowOffset = NSSize(width: 0, height: 4)
    artwork.translatesAutoresizingMaskIntoConstraints = false

    let disk = NSView()
    disk.wantsLayer = true
    disk.layer?.cornerRadius = artworkSize * 0.28
    disk.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    disk.layer?.borderWidth = 0.8
    disk.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    disk.translatesAutoresizingMaskIntoConstraints = false

    let centerDot = NSView()
    centerDot.wantsLayer = true
    centerDot.layer?.cornerRadius = 4
    centerDot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.46).cgColor
    centerDot.translatesAutoresizingMaskIntoConstraints = false

    let note = headerIcon("music.note", color: .white)
    note.translatesAutoresizingMaskIntoConstraints = false
    artwork.addSubview(disk)
    artwork.addSubview(centerDot)
    artwork.addSubview(note)

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

    container.addSubview(artwork)
    container.addSubview(labels)
    NSLayoutConstraint.activate([
      artwork.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      artwork.topAnchor.constraint(equalTo: container.topAnchor, constant: audioArtworkTopInset),
      artwork.widthAnchor.constraint(equalToConstant: artworkSize),
      artwork.heightAnchor.constraint(equalToConstant: artworkSize),
      disk.centerXAnchor.constraint(equalTo: artwork.centerXAnchor),
      disk.centerYAnchor.constraint(equalTo: artwork.centerYAnchor),
      disk.widthAnchor.constraint(equalToConstant: artworkSize * 0.56),
      disk.heightAnchor.constraint(equalToConstant: artworkSize * 0.56),
      centerDot.centerXAnchor.constraint(equalTo: artwork.centerXAnchor),
      centerDot.centerYAnchor.constraint(equalTo: artwork.centerYAnchor),
      centerDot.widthAnchor.constraint(equalToConstant: 8),
      centerDot.heightAnchor.constraint(equalToConstant: 8),
      note.centerXAnchor.constraint(equalTo: artwork.centerXAnchor, constant: 1),
      note.centerYAnchor.constraint(equalTo: artwork.centerYAnchor, constant: -1),
      note.widthAnchor.constraint(equalToConstant: artworkSize * 0.32),
      note.heightAnchor.constraint(equalToConstant: artworkSize * 0.32),
      labels.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      labels.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      labels.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: audioLabelTopGap),
      title.widthAnchor.constraint(equalTo: labels.widthAnchor),
      detail.widthAnchor.constraint(equalTo: labels.widthAnchor)
    ])
    return container
  }

  private var audioArtworkSize: CGFloat {
    if layout == .expanded {
      return 96
    }
    return layout.isCompact ? 62 : 72
  }

  private var audioArtworkTopInset: CGFloat {
    layout.isCompact ? 14 : 16
  }

  private var audioLabelTopGap: CGFloat {
    layout.isCompact ? 10 : 12
  }

  private func videoPreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    let accent = accentColor(for: item.kind)
    container.wantsLayer = true
    container.layer?.backgroundColor = accent.withAlphaComponent(0.10).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let frameHeight = videoPreviewFrameHeight
    #if DEBUG
    debugVideoPreviewChrome = "player-card"
    debugVideoFrameHeight = frameHeight
    debugVideoFormatPlacement = "bottom-center"
    #endif

    let frame = NSView()
    frame.wantsLayer = true
    frame.layer?.cornerRadius = 14
    frame.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
    frame.layer?.borderWidth = 1
    frame.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    frame.layer?.shadowColor = NSColor.black.cgColor
    frame.layer?.shadowOpacity = 0.12
    frame.layer?.shadowRadius = 8
    frame.layer?.shadowOffset = NSSize(width: 0, height: 3)
    frame.translatesAutoresizingMaskIntoConstraints = false

    let film = headerIcon("film", color: NSColor.white.withAlphaComponent(0.58))
    film.translatesAutoresizingMaskIntoConstraints = false

    let playBadge = NSView()
    playBadge.wantsLayer = true
    playBadge.layer?.cornerRadius = 20
    playBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    playBadge.layer?.borderWidth = 0.8
    playBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
    playBadge.translatesAutoresizingMaskIntoConstraints = false

    let play = headerIcon("play.fill", color: .white)
    play.translatesAutoresizingMaskIntoConstraints = false
    playBadge.addSubview(play)

    frame.addSubview(film)
    frame.addSubview(playBadge)

    let extensionPill = capsuleLabel(VideoPayload.kindText(from: item.payload), color: accent)
    extensionPill.translatesAutoresizingMaskIntoConstraints = false
    frame.addSubview(extensionPill)

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
    labels.alignment = .leading
    labels.spacing = 3
    labels.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(frame)
    container.addSubview(labels)
    NSLayoutConstraint.activate([
      frame.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      frame.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      frame.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.isCompact ? 14 : 16),
      frame.heightAnchor.constraint(equalToConstant: frameHeight),
      film.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 12),
      film.topAnchor.constraint(equalTo: frame.topAnchor, constant: 10),
      film.widthAnchor.constraint(equalToConstant: 22),
      film.heightAnchor.constraint(equalToConstant: 22),
      playBadge.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
      playBadge.centerYAnchor.constraint(equalTo: frame.centerYAnchor, constant: -4),
      playBadge.widthAnchor.constraint(equalToConstant: 40),
      playBadge.heightAnchor.constraint(equalToConstant: 40),
      play.centerXAnchor.constraint(equalTo: playBadge.centerXAnchor, constant: 1),
      play.centerYAnchor.constraint(equalTo: playBadge.centerYAnchor),
      play.widthAnchor.constraint(equalToConstant: 16),
      play.heightAnchor.constraint(equalToConstant: 16),
      extensionPill.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
      extensionPill.bottomAnchor.constraint(equalTo: frame.bottomAnchor, constant: -10),
      labels.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      labels.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      labels.topAnchor.constraint(equalTo: frame.bottomAnchor, constant: 10),
      labels.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
      title.widthAnchor.constraint(equalTo: labels.widthAnchor),
      detail.widthAnchor.constraint(equalTo: labels.widthAnchor)
    ])
    return container
  }

  private var videoPreviewFrameHeight: CGFloat {
    if layout == .expanded {
      return 124
    }
    return layout.isCompact ? 82 : 92
  }

  private func colorPreviewView(for item: ClipboardItem) -> NSView {
    let swatchColor = ColorPayload.color(from: item.payload) ?? accentColor(for: item.kind)
    let hexText = ColorPayload.displayHex(from: item.payload)
    let componentText = ColorPayload.componentSummary(from: item.payload)
    let chipSize = colorPreviewChipSize
    #if DEBUG
    debugColorPreviewChrome = "paint-chip"
    debugColorPreviewHexText = hexText
    debugColorPreviewSwatchPlacement = "top"
    debugColorPreviewChipSize = chipSize
    #endif

    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = swatchColor.withAlphaComponent(0.10).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let shadowHost = NSView()
    shadowHost.wantsLayer = true
    shadowHost.layer?.cornerRadius = layout.isCompact ? 12 : 14
    shadowHost.layer?.shadowColor = NSColor.black.cgColor
    shadowHost.layer?.shadowOpacity = 0.11
    shadowHost.layer?.shadowRadius = 8
    shadowHost.layer?.shadowOffset = NSSize(width: 0, height: 3)
    shadowHost.translatesAutoresizingMaskIntoConstraints = false

    let chip = NSView()
    chip.wantsLayer = true
    chip.layer?.cornerRadius = layout.isCompact ? 12 : 14
    chip.layer?.masksToBounds = true
    chip.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
    chip.layer?.borderWidth = 0.8
    chip.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.14).cgColor
    chip.translatesAutoresizingMaskIntoConstraints = false

    let swatch = NSView()
    swatch.wantsLayer = true
    swatch.layer?.backgroundColor = swatchColor.cgColor
    swatch.translatesAutoresizingMaskIntoConstraints = false

    let hex = NSTextField(labelWithString: hexText)
    hex.font = .monospacedDigitSystemFont(ofSize: colorPreviewHexFontSize, weight: .bold)
    hex.textColor = .labelColor
    hex.alignment = .center
    hex.maximumNumberOfLines = 1
    hex.lineBreakMode = .byTruncatingTail
    hex.toolTip = hex.stringValue

    let components = NSTextField(labelWithString: componentText)
    components.font = .monospacedDigitSystemFont(ofSize: layout.isCompact ? 10 : 11, weight: .semibold)
    components.textColor = .secondaryLabelColor
    components.alignment = .center
    components.maximumNumberOfLines = 1
    components.lineBreakMode = .byTruncatingTail
    components.toolTip = components.stringValue

    let labelStack = NSStackView(views: [hex, components])
    labelStack.orientation = .vertical
    labelStack.alignment = .centerX
    labelStack.spacing = layout.isCompact ? 2 : 3
    labelStack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(shadowHost)
    shadowHost.addSubview(chip)
    chip.addSubview(swatch)
    chip.addSubview(labelStack)
    NSLayoutConstraint.activate([
      shadowHost.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      shadowHost.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      shadowHost.widthAnchor.constraint(equalToConstant: chipSize.width),
      shadowHost.heightAnchor.constraint(equalToConstant: chipSize.height),
      chip.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
      chip.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
      chip.topAnchor.constraint(equalTo: shadowHost.topAnchor),
      chip.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),
      swatch.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
      swatch.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
      swatch.topAnchor.constraint(equalTo: chip.topAnchor),
      swatch.heightAnchor.constraint(equalToConstant: colorPreviewSwatchHeight),
      labelStack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 12),
      labelStack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -12),
      labelStack.topAnchor.constraint(equalTo: swatch.bottomAnchor, constant: layout.isCompact ? 7 : 9),
      labelStack.bottomAnchor.constraint(lessThanOrEqualTo: chip.bottomAnchor, constant: -8),
      hex.widthAnchor.constraint(equalTo: labelStack.widthAnchor),
      components.widthAnchor.constraint(equalTo: labelStack.widthAnchor)
    ])
    return container
  }

  private var colorPreviewChipSize: NSSize {
    if layout == .expanded {
      return NSSize(width: 260, height: 162)
    }
    if layout.isCompact {
      return NSSize(width: 196, height: 98)
    }
    return NSSize(width: 230, height: 112)
  }

  private var colorPreviewSwatchHeight: CGFloat {
    if layout == .expanded {
      return 94
    }
    return layout.isCompact ? 52 : 62
  }

  private var colorPreviewHexFontSize: CGFloat {
    if layout == .expanded {
      return 20
    }
    return layout.isCompact ? 15 : 17
  }

  private func codePreviewView(for item: ClipboardItem) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = accentColor(for: item.kind).withAlphaComponent(0.10).cgColor
    container.translatesAutoresizingMaskIntoConstraints = false

    let editor = NSView()
    editor.wantsLayer = true
    editor.layer?.cornerRadius = 10
    editor.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.66).cgColor
    editor.layer?.borderWidth = 0.8
    editor.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
    editor.translatesAutoresizingMaskIntoConstraints = false

    let language = capsuleLabel(CodeSnippetPayload.languageLabel(from: item.payload), color: accentColor(for: item.kind))
    language.translatesAutoresizingMaskIntoConstraints = false

    let lines = CodeSnippetPayload.previewLines(from: item.payload)
    let lineRows = lines.isEmpty ? ["Code snippet"] : lines
    let rowViews = lineRows.enumerated().map { offset, line in
      codeLineRow(number: offset + 1, text: line)
    }
    let rows = NSStackView(views: rowViews)
    rows.orientation = .vertical
    rows.alignment = .leading
    rows.spacing = 3
    rows.translatesAutoresizingMaskIntoConstraints = false

    editor.addSubview(rows)
    container.addSubview(editor)
    container.addSubview(language)
    for row in rowViews {
      row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
    }

    NSLayoutConstraint.activate([
      editor.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.inset),
      editor.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.inset),
      editor.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.isCompact ? 13 : 16),
      editor.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: layout.isCompact ? -13 : -16),
      rows.leadingAnchor.constraint(equalTo: editor.leadingAnchor, constant: 12),
      rows.trailingAnchor.constraint(equalTo: editor.trailingAnchor, constant: -12),
      rows.topAnchor.constraint(equalTo: editor.topAnchor, constant: 13),
      rows.bottomAnchor.constraint(lessThanOrEqualTo: editor.bottomAnchor, constant: -12),
      language.trailingAnchor.constraint(equalTo: editor.trailingAnchor, constant: -10),
      language.bottomAnchor.constraint(equalTo: editor.bottomAnchor, constant: -9)
    ])
    return container
  }

  private func codeLineRow(number: Int, text: String) -> NSView {
    let numberLabel = NSTextField(labelWithString: "\(number)")
    numberLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    numberLabel.textColor = .tertiaryLabelColor
    numberLabel.alignment = .right
    numberLabel.maximumNumberOfLines = 1
    numberLabel.translatesAutoresizingMaskIntoConstraints = false
    numberLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true

    let codeLabel = NSTextField(labelWithString: text)
    codeLabel.font = .monospacedSystemFont(ofSize: layout.isCompact ? 11 : 12, weight: .regular)
    codeLabel.textColor = .labelColor
    codeLabel.maximumNumberOfLines = 1
    codeLabel.lineBreakMode = .byTruncatingTail
    codeLabel.toolTip = text
    codeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let row = NSStackView(views: [numberLabel, codeLabel])
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    codeLabel.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -28).isActive = true
    return row
  }

  private func mediaPreviewView(for item: ClipboardItem, thumbnail: NSImage) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let imageView = AspectFillImageView(image: thumbnail)
    imageView.translatesAutoresizingMaskIntoConstraints = false

    let metricText = mediaMetricText(for: thumbnail)
    #if DEBUG
    debugMediaMetricText = metricText
    debugMediaMetricPlacement = "bottom-center"
    #endif
    let overlay = capsuleLabel(metricText, color: NSColor.black.withAlphaComponent(0.56))
    overlay.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(imageView)
    container.addSubview(overlay)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: container.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      overlay.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
    ])
    return container
  }

  private func videoMediaPreviewView(for item: ClipboardItem, thumbnail: NSImage) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    #if DEBUG
    debugVideoPreviewChrome = "thumbnail-player"
    debugVideoFrameHeight = layout.bodyHeight
    debugVideoFormatPlacement = "bottom-center"
    #endif

    let imageView = AspectFillImageView(image: thumbnail)
    imageView.translatesAutoresizingMaskIntoConstraints = false

    let playBadge = NSView()
    playBadge.wantsLayer = true
    playBadge.layer?.cornerRadius = 22
    playBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
    playBadge.layer?.borderWidth = 0.8
    playBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
    playBadge.translatesAutoresizingMaskIntoConstraints = false

    let play = headerIcon("play.fill", color: .white)
    play.translatesAutoresizingMaskIntoConstraints = false
    playBadge.addSubview(play)

    let extensionPill = capsuleLabel(VideoPayload.kindText(from: item.payload), color: NSColor.black.withAlphaComponent(0.60))
    extensionPill.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(imageView)
    container.addSubview(playBadge)
    container.addSubview(extensionPill)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: container.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      playBadge.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      playBadge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      playBadge.widthAnchor.constraint(equalToConstant: 44),
      playBadge.heightAnchor.constraint(equalToConstant: 44),
      play.centerXAnchor.constraint(equalTo: playBadge.centerXAnchor, constant: 1),
      play.centerYAnchor.constraint(equalTo: playBadge.centerYAnchor),
      play.widthAnchor.constraint(equalToConstant: 16),
      play.heightAnchor.constraint(equalToConstant: 16),
      extensionPill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      extensionPill.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
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
      return thumbnail == nil ? "link-site-preview" : "link-media-preview"
    case .file:
      if thumbnail != nil {
        return "file-media-preview"
      }
      return FilePayload.paths(from: item.payload).count > 1 ? "multi-file-preview" : "file-preview"
    case .pdf:
      return thumbnail == nil ? "file-preview" : "file-media-preview"
    case .audio:
      return "audio-preview"
    case .video:
      return thumbnail == nil ? "video-preview" : "video-media-preview"
    case .color:
      return "color-preview"
    case .code:
      return "code-preview"
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
    let badge = HeaderBadgeTileView(
      cornerRadius: headerBadgeCornerRadius,
      maskedCorners: CornerMasks.badgeWithoutBottomRight
    )
    badge.translatesAutoresizingMaskIntoConstraints = false
    if let bundleId = item.sourceAppBundleId,
       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
      #if DEBUG
      debugHeaderBadgeText = ""
      #endif
      let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: appURL.path))
      icon.imageScaling = .scaleProportionallyUpOrDown
      icon.translatesAutoresizingMaskIntoConstraints = false
      let iconClipView = NSView()
      iconClipView.wantsLayer = true
      iconClipView.layer?.cornerRadius = headerBadgeCornerRadius
      iconClipView.layer?.maskedCorners = CornerMasks.badgeWithoutBottomRight
      iconClipView.layer?.masksToBounds = true
      iconClipView.translatesAutoresizingMaskIntoConstraints = false
      headerBadgeContentView = icon
      badge.addSubview(iconClipView)
      iconClipView.addSubview(icon)
      let iconBleed = headerBadgeAppIconBleed
      NSLayoutConstraint.activate([
        iconClipView.leadingAnchor.constraint(equalTo: badge.leadingAnchor),
        iconClipView.trailingAnchor.constraint(equalTo: badge.trailingAnchor),
        iconClipView.topAnchor.constraint(equalTo: badge.topAnchor),
        iconClipView.bottomAnchor.constraint(equalTo: badge.bottomAnchor),
        icon.leadingAnchor.constraint(equalTo: iconClipView.leadingAnchor, constant: -iconBleed),
        icon.trailingAnchor.constraint(equalTo: iconClipView.trailingAnchor, constant: iconBleed),
        icon.topAnchor.constraint(equalTo: iconClipView.topAnchor, constant: -iconBleed),
        icon.bottomAnchor.constraint(equalTo: iconClipView.bottomAnchor, constant: iconBleed)
      ])
    } else if let monogram = Self.sourceMonogram(from: itemSourceAppName) {
      #if DEBUG
      debugHeaderBadgeText = monogram
      #endif
      let label = NSTextField(labelWithString: monogram)
      label.font = .systemFont(ofSize: layout.isCompact ? 15 : 17, weight: .heavy)
      label.textColor = accentColor(for: item.kind)
      label.alignment = .center
      label.lineBreakMode = .byClipping
      label.maximumNumberOfLines = 1
      label.setAccessibilityLabel(itemSourceAppName ?? monogram)
      label.translatesAutoresizingMaskIntoConstraints = false
      headerBadgeContentView = label
      badge.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: headerBadgeIconInset),
        label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -headerBadgeIconInset),
        label.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
      ])
    } else {
      #if DEBUG
      debugHeaderBadgeText = ""
      #endif
      let image = NSImage(systemSymbolName: headerBadgeSymbol(for: item.kind), accessibilityDescription: kindLabel(for: item.kind))
        ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: kindLabel(for: item.kind))
        ?? NSImage()
      image.isTemplate = true
      let icon = NSImageView(image: image)
      icon.imageScaling = .scaleProportionallyUpOrDown
      icon.contentTintColor = accentColor(for: item.kind)
      icon.translatesAutoresizingMaskIntoConstraints = false
      headerBadgeContentView = icon
      badge.addSubview(icon)
      let symbolInset = headerBadgeIconInset + 1
      NSLayoutConstraint.activate([
        icon.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: symbolInset),
        icon.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -symbolInset),
        icon.topAnchor.constraint(equalTo: badge.topAnchor, constant: symbolInset),
        icon.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -symbolInset)
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
    case .video:
      return videoTitle(for: item)
    case .image:
      return imageTitle(for: item)
    case .color:
      return ColorPayload.displayHex(from: item.payload)
    case .code:
      return CodeSnippetPayload.title(from: item.payload)
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
    case .video:
      return "Video clip"
    case .color:
      return ColorPayload.componentSummary(from: item.payload)
    case .code:
      return CodeSnippetPayload.previewText(from: item.payload)
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
    case .video:
      return VideoPayload.kindText(from: item.payload)
    case .color:
      return "Color"
    case .code:
      return CodeSnippetPayload.languageLabel(from: item.payload)
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

  private func compactMetricText(for item: ClipboardItem) -> String {
    switch item.kind {
    case .text, .url, .code, .color, .unknown:
      let text = item.payload.clipboardTrimmed.isEmpty ? item.displayText : item.payload
      return compactCharacterMetric(text.count)
    case .richText:
      return compactCharacterMetric(item.displayText.count)
    case .file:
      if let byteCount = fileByteCount(paths: FilePayload.paths(from: item.payload)) {
        return compactByteMetric(byteCount)
      }
      return compactCharacterMetric(item.payload.count)
    case .pdf, .audio, .video:
      if let byteCount = fileByteCount(paths: [item.payload]) {
        return compactByteMetric(byteCount)
      }
      return compactCharacterMetric(item.payload.count)
    case .image:
      let path = item.imagePath?.clipboardTrimmed.isEmpty == false ? item.imagePath! : item.payload
      if let byteCount = fileByteCount(paths: [path]) {
        return compactByteMetric(byteCount)
      }
      return compactCharacterMetric(item.payload.count)
    }
  }

  private func compactCharacterMetric(_ count: Int) -> String {
    if count == 1 {
      return "1 char"
    }
    if count < 1_000 {
      return "\(max(0, count)) chars"
    }
    if count < 1_000_000 {
      return "\(compactDecimal(Double(count) / 1_000))k chars"
    }
    return "\(compactDecimal(Double(count) / 1_000_000))M chars"
  }

  private func compactByteMetric(_ byteCount: Int64) -> String {
    let bytes = max(0, byteCount)
    if bytes < 1_024 {
      return "\(bytes) B"
    }
    if bytes < 1_024 * 1_024 {
      return "\(compactDecimal(Double(bytes) / 1_024)) KB"
    }
    if bytes < 1_024 * 1_024 * 1_024 {
      return "\(compactDecimal(Double(bytes) / (1_024 * 1_024))) MB"
    }
    return "\(compactDecimal(Double(bytes) / (1_024 * 1_024 * 1_024))) GB"
  }

  private func compactDecimal(_ value: Double) -> String {
    if value < 10 {
      let rounded = (value * 10).rounded() / 10
      return rounded == floor(rounded) ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
    return "\(Int(value.rounded()))"
  }

  private func fileByteCount(paths: [String]) -> Int64? {
    let byteCounts = paths.compactMap { path -> Int64? in
      let trimmed = path.clipboardTrimmed
      guard !trimmed.isEmpty else { return nil }
      let url = FilePayload.fileURL(from: trimmed)
      guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else {
        return nil
      }
      return size.int64Value
    }
    guard !byteCounts.isEmpty else { return nil }
    return byteCounts.reduce(0, +)
  }

  private func footerSourceText(for item: ClipboardItem) -> String? {
    let source = item.sourceApp?.clipboardTrimmed
    let device = sourceDeviceText(for: item)
    let usage = usageText(for: item.useCount)

    var parts: [String] = []
    if let source, !source.isEmpty {
      if let device {
        parts.append("\(source) on \(device)")
      } else {
        parts.append(source)
      }
    } else if let device {
      parts.append(device)
    }
    if let usage {
      parts.append(usage)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " - ")
  }

  private func sourceDeviceText(for item: ClipboardItem) -> String? {
    guard let device = ClipboardItem.normalizedDeviceName(item.sourceDeviceName) else { return nil }
    let localDevice = ClipboardItem.localDeviceName
    guard device.caseInsensitiveCompare(localDevice) != .orderedSame else { return nil }
    return device
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
    if let pageTitle = webPageTitleText(from: item.payload) {
      return pageTitle
    }
    if let hostTitle = webHostTitleText(from: item.payload) {
      return hostTitle
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

  private func videoTitle(for item: ClipboardItem) -> String {
    let display = firstUsefulLine(item.displayText)
    if !display.isEmpty, !looksInternal(display), display.lowercased() != "video" {
      return display
    }
    return "Video"
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

  private func webPageTitleText(from value: String) -> String? {
    guard let components = webComponents(from: value) else { return nil }
    let segments = components.path
      .split(separator: "/")
      .map { String($0).removingPercentEncoding ?? String($0) }
      .map { $0.clipboardTrimmed }
      .filter { !$0.isEmpty }

    for segment in segments.reversed() where !isLikelyVersionPathSegment(segment) {
      if let title = humanReadableWebTitle(from: segment) {
        return title
      }
    }
    return nil
  }

  private func webHostTitleText(from value: String) -> String? {
    guard let host = webHostText(from: value) else { return nil }
    let labels = host
      .split(separator: ".")
      .map(String.init)
      .filter { !$0.isEmpty }
    guard let label = labels.first else { return nil }
    return humanReadableWebTitle(from: label)
  }

  private func humanReadableWebTitle(from value: String) -> String? {
    var slug = value.clipboardTrimmed
    guard !slug.isEmpty else { return nil }
    if let dotIndex = slug.lastIndex(of: ".") {
      let extensionText = slug[slug.index(after: dotIndex)...]
      let base = slug[..<dotIndex]
      if !base.isEmpty, (1...6).contains(extensionText.count), extensionText.allSatisfy(\.isLetter) {
        slug = String(base)
      }
    }

    var words: [String] = []
    var current = ""
    for scalar in slug.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        current.unicodeScalars.append(scalar)
      } else if !current.isEmpty {
        words.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      words.append(current)
    }
    words = words.filter { !isLikelyVersionPathSegment($0) }
    guard !words.isEmpty else { return nil }

    let title = words
      .map(formattedWebTitleWord)
      .joined(separator: " ")
      .clipboardTrimmed
    guard !title.isEmpty else { return nil }
    return String(title.prefix(70))
  }

  private func formattedWebTitleWord(_ word: String) -> String {
    let lower = word.lowercased()
    switch lower {
    case "api": return "API"
    case "appkit": return "AppKit"
    case "ios": return "iOS"
    case "macos": return "macOS"
    case "nscolor": return "NSColor"
    case "pdf": return "PDF"
    case "ui": return "UI"
    case "url": return "URL"
    case "wwdc": return "WWDC"
    case "xcode": return "Xcode"
    default:
      if word.count <= 5, word.allSatisfy(\.isUppercase) {
        return word
      }
      return lower.prefix(1).uppercased() + lower.dropFirst()
    }
  }

  private func isLikelyVersionPathSegment(_ value: String) -> Bool {
    var text = value.clipboardTrimmed.lowercased()
    if text.hasPrefix("v"), text.count > 1 {
      text.removeFirst()
    }
    guard !text.isEmpty else { return false }
    return text.allSatisfy { character in
      character.isNumber || character == "." || character == "-" || character == "_"
    }
  }

  private func linkMonogram(from host: String) -> String {
    let words = host
      .split { character in
        character == "." || character == "-" || character == "_"
      }
      .map(String.init)
      .filter { !$0.isEmpty && $0.lowercased() != "www" }
    let letters = words
      .prefix(2)
      .compactMap { $0.first }
      .map { String($0).uppercased() }
      .joined()
    if !letters.isEmpty {
      return letters
    }
    return String(host.prefix(1)).uppercased()
  }

  private func linkVisualColor(for host: String) -> NSColor {
    let palette = [
      NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.98, alpha: 1),
      NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.72, alpha: 1),
      NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.34, alpha: 1),
      NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.88, alpha: 1),
      NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1),
      NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1)
    ]
    var hash: UInt64 = 1_469_598_103_934_665_603
    for scalar in host.lowercased().unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return palette[Int(hash % UInt64(palette.count))]
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
    case .video:
      return NSColor(calibratedRed: 0.43, green: 0.32, blue: 0.94, alpha: 1)
    case .color:
      return NSColor(calibratedRed: 0.00, green: 0.65, blue: 0.74, alpha: 1)
    case .code:
      return NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.78, alpha: 1)
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
    case .video: return "film"
    case .color: return "paintpalette"
    case .code: return "chevron.left.forwardslash.chevron.right"
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
    "Press Return to paste. Space opens Quick Look. Command-R renames; Command-E edits text. Delete removes selected clips; Command-Z restores them."
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
    case .video: return "Video"
    case .color: return "Color"
    case .code: return "Code"
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
