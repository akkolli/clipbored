import AppKit

final class ClipboardPanelView: NSVisualEffectView, NSSearchFieldDelegate {
  private enum Metrics {
    static let cardRailHeight: CGFloat = 266
    static let cardWidth: CGFloat = 320
    static let cardHeight: CGFloat = 244
    static let cardSpacing: CGFloat = 16
    static let cardStackInset: CGFloat = 10
    static let actionButtonSize: CGFloat = 30
    static let panelTopInset: CGFloat = 12
    static let panelSideInset: CGFloat = 22
    static let actionBarHorizontalPadding: CGFloat = 10
    static let panelStatusBarHeight: CGFloat = 24
    static let minimumBottomInset: CGFloat = 20
    static let panelCornerRadius: CGFloat = 0
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
  private let collectionScrollView = NSScrollView()
  private let collectionStack = NSStackView()
  private let addCollectionButton = NSButton()
  private let itemsStack = NSStackView()
  private let scrollView = NSScrollView()
  private let statusLabel = NSTextField(labelWithString: "")
  private let statusResultCountLabel = NSTextField(labelWithString: "")
  private let statusIndicator = NSView()
  private var emptyStateText: (title: String, detail: String)?
  private var mainStack: NSStackView?
  private var bottomSafeInset = Metrics.minimumBottomInset
  private var currentStatusTone: StatusTone = .ready
  private var cardViews: [ClipboardItemCardView] = []
  private var collectionButtons: [ClipboardSortMode: CollectionChipView] = [:]
  private var customCollectionButtons: [String: CollectionChipView] = [:]
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

    searchField.placeholderString = "Search text, URLs, source app"
    searchField.setAccessibilityLabel("Search clipboard history")
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(searchFieldChanged)
    searchField.sendsSearchStringImmediately = true
    searchField.sendsWholeSearchString = false
    searchField.isBezeled = true
    searchField.placeholderAttributedString = NSAttributedString(
      string: "Search text, URLs, source app",
      attributes: [
        .foregroundColor: NSColor.tertiaryLabelColor
      ]
    )
    searchField.bezelStyle = .roundedBezel
    searchField.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
    searchField.focusRingType = .none
    searchField.toolTip = "Search clipboard history"
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
    itemsStack.spacing = Metrics.cardSpacing
    itemsStack.edgeInsets = NSEdgeInsets(
      top: Metrics.cardStackInset,
      left: Metrics.cardStackInset,
      bottom: Metrics.cardStackInset,
      right: Metrics.cardStackInset
    )
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
    scrollView.heightAnchor.constraint(equalToConstant: Metrics.cardRailHeight).isActive = true

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
    for view in collectionStack.arrangedSubviews {
      collectionStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    for mode in ClipboardSortMode.allCases {
      let chip = CollectionChipView(title: collectionTitle(for: mode), color: collectionColor(for: mode))
      chip.toolTip = mode.title
      chip.onPress = { [weak self] in
        self?.viewModel.sortMode = mode
      }
      collectionButtons[mode] = chip
      collectionStack.addArrangedSubview(chip)
    }

    for collectionName in viewModel.collectionNames {
      let chip = CollectionChipView(title: collectionName, color: collectionColor(forCollectionNamed: collectionName))
      chip.toolTip = collectionName
      chip.onPress = { [weak self] in
        self?.viewModel.selectCollection(named: collectionName)
      }
      customCollectionButtons[collectionName] = chip
      collectionStack.addArrangedSubview(chip)
    }
    collectionStack.addArrangedSubview(addCollectionButton)
    updateAddCollectionButtonState()
    sizeCollectionDocument()
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
    addCollectionButton.toolTip = "Add selected clip to a new collection"
    addCollectionButton.setAccessibilityLabel("Add selected clip to a new collection")
    addCollectionButton.target = self
    addCollectionButton.action = #selector(addSelectedClipToCollection)
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

  private func collectionColor(forCollectionNamed name: String) -> NSColor {
    switch name {
    case "Useful Links":
      return NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.32, alpha: 1)
    case "Important Notes":
      return NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1)
    case "Code Snippets":
      return NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.95, alpha: 1)
    case "Read Later":
      return NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.34, alpha: 1)
    default:
      return NSColor(calibratedRed: 0.52, green: 0.42, blue: 0.86, alpha: 1)
    }
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
      for (index, item) in items.enumerated() {
        let card = ClipboardItemCardView(
          item: item,
          thumbnail: viewModel.thumbnail(for: item),
          index: index,
          collectionNames: collectionNames,
          isStacked: viewModel.isItemStacked(at: index),
          stackCount: viewModel.stackCount
        )
        card.onSelect = { [weak self] selected in
          self?.viewModel.selectItem(at: selected)
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
    let hasSelectedItem = viewModel.selectedItem != nil
    addCollectionButton.isEnabled = hasSelectedItem
    addCollectionButton.alphaValue = hasSelectedItem ? 1.0 : 0.42
  }

  private func scrollCardIntoView(_ card: NSView) {
    guard scrollView.documentView === itemsStack else { return }
    guard card.window != nil else { return }
    scrollView.layoutSubtreeIfNeeded()
    itemsStack.layoutSubtreeIfNeeded()

    let frame = card.convert(card.bounds, to: itemsStack)
    let paddedFrame = frame.insetBy(dx: -Metrics.cardSpacing, dy: 0)
    itemsStack.scrollToVisible(paddedFrame)
    scrollView.reflectScrolledClipView(scrollView.contentView)
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
    if lower.hasPrefix("copied") || lower.hasPrefix("pasted") || lower.hasPrefix("updated") || lower.hasPrefix("added") || lower.hasPrefix("removed") || lower.hasPrefix("cleared") {
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

  private func emptyStateView() -> NSView {
    let width = max(760, scrollView.contentView.bounds.width)
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.cardRailHeight))
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
    let contentWidth = (count * Metrics.cardWidth)
      + max(0, count - 1) * Metrics.cardSpacing
      + (Metrics.cardStackInset * 2)
    let width = max(scrollView.contentView.bounds.width, contentWidth)
    lastScrollContentWidth = width
    itemsStack.frame = NSRect(x: 0, y: 0, width: width, height: currentListHeight())
    itemsStack.needsLayout = true
    itemsStack.layoutSubtreeIfNeeded()
  }

  private func currentListHeight() -> CGFloat {
    Metrics.cardHeight + (Metrics.cardStackInset * 2)
  }

  private func emptyStateCopy() -> (title: String, detail: String) {
    if !viewModel.searchText.clipboardTrimmed.isEmpty {
      return (
        "No matching clips",
        "Try a broader search or switch filters."
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
      return ("No pinned clips", "New copies appear under Most Recent. Select an item and press P to pin it.")
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

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override func layout() {
    super.layout()
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
        width: max(760, scrollView.contentView.bounds.width),
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

  func setBottomSafeInset(_ inset: CGFloat) {
    bottomSafeInset = max(Metrics.minimumBottomInset, inset)
    mainStack?.edgeInsets = contentInsets()
    needsLayout = true
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

  var debugCardPreviewSummaries: [String] {
    cardViews.map(\.debugPreviewSummary)
  }

  var debugCardPreviewStyles: [String] {
    cardViews.map(\.debugPreviewStyle)
  }

  var debugCardHeaderBadgeSymbols: [String] {
    cardViews.map(\.debugHeaderBadgeSymbol)
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

  var debugFirstCardMenuTitles: [String] {
    cardViews.first?.debugMenuTitles ?? []
  }

  var debugFirstCardCollectionMenuTitles: [String] {
    cardViews.first?.debugCollectionMenuTitles ?? []
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
    collectionButtons.first(where: { $0.value.isSelected })?.value.titleText
  }

  var debugCollectionCounts: [Int] {
    updateCollectionButtons()
    return ClipboardSortMode.allCases.compactMap { collectionButtons[$0]?.count }
  }

  var debugCustomCollectionTitles: [String] {
    viewModel.collectionNames
  }

  var debugCustomCollectionCounts: [Int] {
    updateCollectionButtons()
    return viewModel.collectionNames.compactMap { customCollectionButtons[$0]?.count }
  }

  var debugCollectionRailVisibleWidth: CGFloat {
    collectionScrollView.contentView.bounds.width
  }

  var debugCollectionRailDocumentWidth: CGFloat {
    collectionScrollView.documentView?.frame.width ?? 0
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
    addSelectedClipToCollection()
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
      if searchField.stringValue.clipboardTrimmed.isEmpty {
        onClose()
      } else {
        searchField.stringValue = ""
        updateSearchText()
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

  @objc private func closePanel() {
    onClose()
  }

  @objc private func openSettings() {
    onSettings()
  }

  @objc private func addSelectedClipToCollection() {
    guard viewModel.selectedItem != nil,
          let name = requestCollectionName() else {
      return
    }
    viewModel.assignSelected(to: name)
  }

  private func requestCollectionName() -> String? {
    #if DEBUG
    if let collectionNameProviderForTesting {
      return ClipboardCollectionDefaults.normalizedName(collectionNameProviderForTesting())
    }
    #endif

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    input.placeholderString = "Collection name"
    input.stringValue = ""

    let alert = NSAlert()
    alert.messageText = "New Collection"
    alert.informativeText = "Name this collection and add the selected clip to it."
    alert.accessoryView = input
    alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = input

    guard alert.runModal() == .alertFirstButtonReturn else {
      return nil
    }
    return ClipboardCollectionDefaults.normalizedName(input.stringValue)
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
  var onPress: () -> Void = {}

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
    layer?.cornerRadius = 13
    layer?.borderWidth = 0.6
    layer?.borderColor = NSColor.clear.cgColor
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(titleText)
    heightAnchor.constraint(equalToConstant: 26).isActive = true

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
    setAccessibilityLabel("\(titleText), count: \(count)")
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
    if selected {
      layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.58).cgColor
      layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.34).cgColor
    } else {
      layer?.backgroundColor = NSColor.clear.cgColor
      layer?.borderColor = NSColor.clear.cgColor
    }
  }

  func setCount(_ count: Int) {
    self.count = count
    countLabel.stringValue = count > 999 ? "999+" : "\(count)"
    setAccessibilityLabel("\(titleText), \(count) \(count == 1 ? "clip" : "clips")")
    setAccessibilityValue("\(count)")
    toolTip = "\(titleText), \(count) \(count == 1 ? "clip" : "clips")"
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    onPress()
  }
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
    static let width: CGFloat = 320
    static let height: CGFloat = 244
    static let inset: CGFloat = 16
    static let headerHeight: CGFloat = 56
    static let bodyHeight: CGFloat = 152
    static let footerHeight: CGFloat = 36
    static let actionButtonSize: CGFloat = 24
    static let primaryActionButtonSize: CGFloat = 30
    static let actionRailHeight: CGFloat = 34
    static let dragThreshold: CGFloat = 4
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

  var onSelect: (Int) -> Void = { _ in }
  var onPaste: (Int) -> Void = { _ in }
  var onCopy: (Int) -> Void = { _ in }
  var onPastePlainText: (Int) -> Void = { _ in }
  var onCopyPlainText: (Int) -> Void = { _ in }
  var onToggleStack: (Int) -> Void = { _ in }
  var onPasteStackNext: () -> Void = {}
  var onCopyStackNext: () -> Void = {}
  var onClearStack: () -> Void = {}
  var onEditText: (Int) -> Void = { _ in }
  var onPreview: (Int) -> Void = { _ in }
  var onPasteboardWriters: (Int) -> [NSPasteboardWriting] = { _ in [] }
  var onOpen: (Int) -> Void = { _ in }
  var onReveal: (Int) -> Void = { _ in }
  var onTogglePin: (Int) -> Void = { _ in }
  var onAssignCollection: (Int, String?) -> Void = { _, _ in }
  var onDelete: (Int) -> Void = { _ in }

  private let index: Int
  private let itemKind: ClipboardItemKind
  private let itemIsPinned: Bool
  private let itemIsStacked: Bool
  private let stackCount: Int
  private let itemCollectionName: String?
  private let collectionNames: [String]
  private let contentView = NSView()
  private let footerDetailLabel = NSTextField(labelWithString: "")
  private let actionRail = NSStackView()
  private var actionRailButtons: [NSButton] = []
  private weak var headerBadgeView: NSView?
  private weak var headerPinView: NSView?
  private var isSelected = false
  private var isHovered = false
  private var mouseDownLocation: NSPoint?
  private var trackingAreaRef: NSTrackingArea?

  init(
    item: ClipboardItem,
    thumbnail: NSImage?,
    index: Int,
    collectionNames: [String] = [],
    isStacked: Bool = false,
    stackCount: Int = 0
  ) {
    self.index = index
    self.itemKind = item.kind
    self.itemIsPinned = item.isPinned
    self.itemIsStacked = isStacked
    self.stackCount = stackCount
    self.itemCollectionName = ClipboardCollectionDefaults.normalizedName(item.collectionName)
    self.collectionNames = collectionNames.compactMap { ClipboardCollectionDefaults.normalizedName($0) }
    super.init(frame: .zero)
    configure(item: item, thumbnail: thumbnail)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    contentView.layer?.borderWidth = 1
    contentView.layer?.borderColor = selected ? Palette.selectedBorder : Palette.border
    if selected {
      contentView.layer?.backgroundColor = Palette.selectedSurface
      contentView.layer?.borderColor = Palette.selectedBorder
    } else if isHovered {
      contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
      contentView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
    } else {
      contentView.layer?.backgroundColor = Palette.cardSurface
      contentView.layer?.borderColor = Palette.border
    }
    layer?.shadowOpacity = selected ? 0.16 : (isHovered ? 0.12 : 0.08)
    layer?.shadowRadius = selected ? 16 : 12
    layer?.shadowOffset = NSSize(width: 0, height: selected ? 6 : 4)
    layer?.transform = selected ? CATransform3DMakeTranslation(0, -4, 0) : CATransform3DIdentity
    updateActionRailVisibility()
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
    guard !writers.isEmpty else { return }
    onSelect(index)

    let preview = dragPreviewImage()
    let dragItems = writers.enumerated().map { offset, writer in
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

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    .copy
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
    true
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    onSelect(index)
    return contextMenu()
  }

  #if DEBUG
  private(set) var debugPreviewSummary = ""
  private(set) var debugPreviewStyle = ""
  private(set) var debugHeaderBadgeSymbol = ""

  var debugMenuTitles: [String] {
    contextMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  var debugCollectionMenuTitles: [String] {
    guard let collectionMenu = contextMenu().items.first(where: { $0.title == "Add to Collection" })?.submenu else {
      return []
    }
    return collectionMenu.items.map { $0.isSeparatorItem ? "-" : $0.title }
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

    menu.addItem(parent)
    menu.setSubmenu(submenu, for: parent)
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
    case .url, .image, .richText, .file, .pdf, .audio:
      return true
    case .text, .unknown:
      return false
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
    actionRail.layer?.cornerRadius = Metrics.actionRailHeight / 2
    actionRail.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.44).cgColor
    actionRail.layer?.borderWidth = 0.5
    actionRail.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    actionRail.layer?.shadowColor = NSColor.black.cgColor
    actionRail.layer?.shadowOpacity = 0.18
    actionRail.layer?.shadowRadius = 10
    actionRail.layer?.shadowOffset = NSSize(width: 0, height: 4)
    actionRail.translatesAutoresizingMaskIntoConstraints = false
    actionRail.heightAnchor.constraint(equalToConstant: Metrics.actionRailHeight).isActive = true
    actionRail.setContentHuggingPriority(.required, for: .horizontal)
    actionRail.setContentCompressionResistancePriority(.required, for: .horizontal)

    let pinTitle = itemIsPinned ? "Unpin" : "Pin"
    actionRailButtons = [
      cardActionButton("return", toolTip: "Paste", action: #selector(pasteFromMenu), isPrimary: true),
      cardActionButton("doc.on.doc", toolTip: "Copy", action: #selector(copyFromMenu)),
      cardActionButton(itemIsPinned ? "pin.slash" : "pin", toolTip: pinTitle, action: #selector(togglePinFromMenu))
    ]
    actionRailButtons.append(cardActionButton("square.stack.3d.up", toolTip: itemIsStacked ? "Remove from Stack" : "Add to Stack", action: #selector(toggleStackFromMenu)))
    if canEditText {
      actionRailButtons.append(cardActionButton("pencil", toolTip: "Edit", action: #selector(editTextFromMenu)))
    }
    if canPreview {
      actionRailButtons.append(cardActionButton("eye", toolTip: "Preview", action: #selector(previewFromMenu)))
    }
    if canOpen {
      actionRailButtons.append(cardActionButton("arrow.up.right.square", toolTip: "Open", action: #selector(openFromMenu)))
    }
    if canReveal {
      actionRailButtons.append(cardActionButton("magnifyingglass", toolTip: "Reveal", action: #selector(revealFromMenu)))
    }
    actionRailButtons.append(cardActionButton("trash", toolTip: "Delete", action: #selector(deleteFromMenu)))

    for button in actionRailButtons {
      actionRail.addArrangedSubview(button)
    }
    let buttonCount = CGFloat(actionRailButtons.count)
    let secondaryCount = CGFloat(max(0, actionRailButtons.count - 1))
    let contentWidth = Metrics.primaryActionButtonSize
      + secondaryCount * Metrics.actionButtonSize
      + max(0, buttonCount - 1) * actionRail.spacing
      + actionRail.edgeInsets.left
      + actionRail.edgeInsets.right
    actionRail.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    updateActionRailVisibility()
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
    let size = isPrimary ? Metrics.primaryActionButtonSize : Metrics.actionButtonSize
    button.layer?.cornerRadius = size / 2
    button.layer?.backgroundColor = isPrimary
      ? NSColor.controlAccentColor.cgColor
      : NSColor.white.withAlphaComponent(0.08).cgColor
    button.contentTintColor = isPrimary
      ? .white
      : (toolTip == "Delete" ? NSColor.white.withAlphaComponent(0.48) : NSColor.white.withAlphaComponent(0.78))
    button.toolTip = toolTip
    button.setAccessibilityLabel(toolTip)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: size).isActive = true
    button.heightAnchor.constraint(equalToConstant: size).isActive = true
    return button
  }

  private func updateActionRailVisibility() {
    actionRail.isHidden = !isSelected
    headerBadgeView?.isHidden = isSelected
    headerPinView?.isHidden = isSelected
    footerDetailLabel.isHidden = false
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

  @objc private func toggleStackFromMenu() {
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

  @objc private func deleteFromMenu() {
    onDelete(index)
  }

  private func configure(item: ClipboardItem, thumbnail: NSImage?) {
    #if DEBUG
    debugPreviewSummary = "\(titleText(for: item))|\(previewText(for: item))|\(detailMetricText(for: item))"
    debugPreviewStyle = previewStyle(for: item, thumbnail: thumbnail)
    debugHeaderBadgeSymbol = headerBadgeSymbol(for: item.kind)
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
    setAccessibilityHelp("Selects this clipboard item. Double-click to paste.")
    widthAnchor.constraint(equalToConstant: Metrics.width).isActive = true
    heightAnchor.constraint(equalToConstant: Metrics.height).isActive = true

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
    contentView.addSubview(actionRail)
    NSLayoutConstraint.activate([
      actionRail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      actionRail.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11)
    ])
    setSelected(false)
  }

  private func headerView(for item: ClipboardItem) -> NSView {
    let header = NSView()
    header.wantsLayer = true
    header.layer?.backgroundColor = accentColor(for: item.kind).cgColor
    header.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true

    let kind = NSTextField(labelWithString: kindLabel(for: item.kind))
    kind.font = .systemFont(ofSize: 16, weight: .bold)
    kind.textColor = .white
    kind.lineBreakMode = .byTruncatingTail
    kind.maximumNumberOfLines = 1
    kind.toolTip = kind.stringValue

    let source = NSTextField(labelWithString: Self.relativeDateText(for: item.createdAt))
    source.font = .systemFont(ofSize: 11, weight: .regular)
    source.textColor = NSColor.white.withAlphaComponent(0.72)
    source.lineBreakMode = .byTruncatingTail
    source.maximumNumberOfLines = 1
    source.toolTip = source.stringValue

    let titleAndSource = NSStackView(views: [kind, source])
    titleAndSource.orientation = .vertical
    titleAndSource.alignment = .leading
    titleAndSource.spacing = 2
    titleAndSource.translatesAutoresizingMaskIntoConstraints = false

    let labelStack = NSStackView(views: [titleAndSource])
    labelStack.orientation = .horizontal
    labelStack.alignment = .centerY
    labelStack.distribution = .fill
    labelStack.spacing = 1
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
      labelStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Metrics.inset),
      labelStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      labelStack.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),
      badge.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Metrics.inset),
      badge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      badge.widthAnchor.constraint(equalToConstant: 42),
      badge.heightAnchor.constraint(equalToConstant: 42),
      separator.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Metrics.inset),
      separator.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Metrics.inset),
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

  private func bodyView(for item: ClipboardItem, thumbnail: NSImage?) -> NSView {
    let body = NSView()
    body.wantsLayer = true
    body.layer?.backgroundColor = Palette.bodyBackground
    body.heightAnchor.constraint(equalToConstant: Metrics.bodyHeight).isActive = true

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
    let title = NSTextField(wrappingLabelWithString: titleString)
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = .labelColor
    title.maximumNumberOfLines = 1
    title.lineBreakMode = .byTruncatingTail
    title.toolTip = title.stringValue

    let detail = NSTextField(wrappingLabelWithString: bodyString)
    detail.font = .systemFont(ofSize: item.kind == .richText ? 15 : 14)
    detail.textColor = .secondaryLabelColor
    detail.maximumNumberOfLines = 5
    detail.lineBreakMode = .byTruncatingTail
    detail.toolTip = detail.stringValue

    let stack = NSStackView(views: [title, detail])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    detail.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.inset),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.inset),
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
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.inset),
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
      textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.inset),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.inset),
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
      row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.inset),
      row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.inset),
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
      labels.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.inset),
      labels.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.inset),
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

  private func previewBodyText(for item: ClipboardItem, title: String) -> String {
    let preview = previewText(for: item)
    let normalizedTitle = normalized(title)
    if preview == normalizedTitle {
      return preview
    }

    let prefix = normalizedTitle + " "
    if preview.hasPrefix(prefix) {
      let remainder = String(preview.dropFirst(prefix.count)).clipboardTrimmed
      if !remainder.isEmpty {
        return remainder
      }
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
    footer.heightAnchor.constraint(equalToConstant: Metrics.footerHeight).isActive = true

    let source = NSTextField(labelWithString: sourceText(for: item))
    source.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    source.textColor = .secondaryLabelColor
    source.lineBreakMode = .byTruncatingTail
    source.maximumNumberOfLines = 1
    source.toolTip = source.stringValue

    let detailText = detailMetricText(for: item)
    if let collectionName = item.collectionName?.clipboardTrimmed, !collectionName.isEmpty {
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
    let stack = row([source, footerDetailLabel])
    stack.distribution = .fill
    stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints = false
    source.setContentHuggingPriority(.defaultLow, for: .horizontal)
    source.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    footerDetailLabel.setContentHuggingPriority(.required, for: .horizontal)
    footerDetailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    footer.addSubview(divider)
    footer.addSubview(stack)
    NSLayoutConstraint.activate([
      divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: Metrics.inset),
      divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -Metrics.inset),
      divider.topAnchor.constraint(equalTo: footer.topAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1),
      stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: Metrics.inset),
      stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -Metrics.inset),
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

  private func sourceText(for item: ClipboardItem) -> String {
    item.sourceApp?.clipboardTrimmed.isEmpty == false ? item.sourceApp! : "Unknown"
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
    if seconds < 3600 { return "\(seconds / 60)m ago" }
    if seconds < 86400 { return "\(seconds / 3600)h ago" }
    if seconds < 604800 { return "\(seconds / 86400)d ago" }
    return "\(seconds / 604800)w ago"
  }
}
