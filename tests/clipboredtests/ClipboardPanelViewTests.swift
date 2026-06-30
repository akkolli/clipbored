import AppKit
import XCTest
@testable import ClipBored

final class ClipboardPanelViewTests: XCTestCase {
  private var tempURLs: [URL] = []

  private struct PanelFixture {
    let window: NSWindow
    let view: ClipboardPanelView
    let viewModel: ClipboardPanelViewModel
    let settings: SettingsModel
    let store: ClipboardStore
    let cacheService: ClipboardCacheService
  }

  override func tearDown() {
    tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    tempURLs.removeAll()
    super.tearDown()
  }

  func testSearchFieldEditingWhenSearchFieldIsFirstResponder() {
    let (window, view) = makePanelWithPanelView()

    window.makeFirstResponder(view)
    XCTAssertFalse(view.isSearchFieldEditing)

    view.focusSearchField()
    XCTAssertTrue(view.isSearchFieldEditing)
  }

  func testSearchFieldEditingWhenFieldEditorIsFirstResponder() {
    let (window, view) = makePanelWithPanelView()

    view.focusSearchField()
    guard let editor = window.fieldEditor(false, for: nil) else {
      return XCTFail("Expected a search field editor")
    }
    window.makeFirstResponder(editor)

    XCTAssertTrue(view.isSearchFieldEditing)
  }

  func testCapturedTextItemCreatesVisibleCardDocument() {
    let fixture = makePanelFixture()
    let item = makeTextItem("Bruh it said copied text but it does not appear.", store: fixture.store)

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.id), [item.id])
    XCTAssertEqual(fixture.view.debugVisibleCardCount, 1)
    XCTAssertEqual(fixture.view.debugResultCountText, "1 clip")
    XCTAssertTrue(fixture.view.debugDocumentViewIsCardStack)
    XCTAssertGreaterThanOrEqual(fixture.view.debugDocumentViewFrame.width, 292)
    XCTAssertGreaterThanOrEqual(fixture.view.debugDocumentViewFrame.height, 244)
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["text-preview"])
  }

  func testCompactCardsFitTwoItemsOnNarrowDockShelf() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
    fixture.store.upsert(makeTextItem("Compact first", store: fixture.store))
    fixture.store.upsert(makeTextItem("Compact second", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugVisibleCardCount, 2)
    XCTAssertEqual(fixture.view.debugCardSizes.count, 2)
    XCTAssertEqual(fixture.view.debugCardSizes.first?.width ?? 0, 264, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCardSizes.first?.height ?? 0, 220, accuracy: 0.5)
    XCTAssertLessThanOrEqual(
      fixture.view.debugDocumentViewFrame.width,
      fixture.view.debugCardRailVisibleRect.width + 1
    )
  }

  func testCardsShowQuickPasteNumberBadgesForFirstNineItems() {
    let fixture = makePanelFixture()
    for index in 0..<10 {
      fixture.store.upsert(makeTextItem("Quick paste badge \(index)", store: fixture.store))
      drainMainQueue()
    }
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugVisibleCardCount, 10)
    XCTAssertEqual(fixture.view.debugQuickPasteBadgeTexts, ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
  }

  func testFooterShowsCaptureStatusInsteadOfShortcutInstructions() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Footer status item", store: fixture.store))
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "Capture running")
    XCTAssertEqual(fixture.view.debugStatusTone, "ready")
    XCTAssertFalse(fixture.view.debugStatusText.contains("Enter paste"))
  }

  func testEditedTextStatusUsesActionTone() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Editable footer item", store: fixture.store))
    drainMainQueue()

    fixture.viewModel.updateSelectedText(to: "Edited footer item")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "Updated text clip")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")
  }

  func testSkippedCaptureStatusUsesWarningTone() {
    let fixture = makePanelFixture()

    fixture.settings.setCaptureStatus(message: "Skipped: Audio items are ignored in capture settings.")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "Skipped: Audio items are ignored in capture settings.")
    XCTAssertEqual(fixture.view.debugStatusTone, "warning")
  }

  func testPanelShellRendersAsSquareDockedSurface() {
    let (_, view) = makePanelWithPanelView()
    drainMainQueue()
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()

    let rep = try! XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    func alphaAt(_ x: Int, _ y: Int) -> CGFloat {
      rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    XCTAssertEqual(view.debugPanelCornerRadius, 0)
    XCTAssertGreaterThan(alphaAt(8, 8), 0.9)
    XCTAssertGreaterThan(alphaAt(width - 9, 8), 0.9)
    XCTAssertGreaterThan(alphaAt(8, height - 9), 0.9)
    XCTAssertGreaterThan(alphaAt(width - 9, height - 9), 0.9)
  }

  func testOpeningTransitionDefersCardRailReloadUntilAnimationCompletes() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Existing clip", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugVisibleCardCount, 1)

    fixture.view.beginOpeningTransition()
    XCTAssertTrue(fixture.view.debugIsDeferringVisualReloads)
    fixture.store.upsert(makeTextItem("New clip during open", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugVisibleCardCount, 1)
    XCTAssertEqual(fixture.view.debugResultCountText, "2 clips")

    fixture.view.finishOpeningTransition()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugIsDeferringVisualReloads)
    XCTAssertEqual(fixture.view.debugVisibleCardCount, 2)
    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels.first, "Text: New clip during open")
  }

  func testCollectionRailUsesPasteStyleLabelsAndTracksSelection() {
    let fixture = makePanelFixture()

    XCTAssertEqual(
      fixture.view.debugCollectionTitles,
      ["Clipboard", "Frequent", "Text", "Links", "Images", "Audio", "Files", "Pinned"]
    )
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")

    fixture.viewModel.sortMode = .links
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Links")
  }

  func testCollectionRailAddButtonCreatesCollectionForSelectedClip() {
    let fixture = makePanelFixture()

    XCTAssertTrue(fixture.view.debugCollectionRailContainsAddButton)
    XCTAssertFalse(fixture.view.debugAddCollectionButtonIsEnabled)

    fixture.store.upsert(makeTextItem("Collect this note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugAddCollectionButtonIsEnabled)

    fixture.view.debugSetCollectionNameProvider { "  Research   Stack  " }
    fixture.view.debugPressAddCollectionButton()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Added to Research Stack")
    XCTAssertEqual(fixture.view.debugCustomCollectionTitles, ["Research Stack"])
    XCTAssertEqual(fixture.view.debugFirstCardHeaderTitle, "Text")
    XCTAssertEqual(fixture.view.debugFirstCardFooterDetailText, "Research Stack - 17 characters")

    fixture.viewModel.selectCollection(named: "Research Stack")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Collect this note"])
    XCTAssertEqual(fixture.view.debugFirstCardHeaderTitle, "Research Stack")
    XCTAssertEqual(fixture.view.debugFirstCardHeaderSubtitle, "Text - Just now")
    XCTAssertEqual(
      fixture.view.debugFirstCardHeaderColorHex,
      fixture.view.debugCustomCollectionColorHexes["Research Stack"] ?? ""
    )
    XCTAssertEqual(fixture.view.debugFirstCardFooterDetailText, "17 characters")
  }

  func testSelectedCardActionsRespectSelectedKind() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Plain text", store: fixture.store))
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, ["Paste", "Copy", "Pin", "Collect", "Add to Stack", "Edit", "Delete"])
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionRailWidth, 210)
    XCTAssertFalse(fixture.view.debugFirstCardFooterDetailIsHidden)
    XCTAssertTrue(fixture.view.debugFirstCardHeaderBadgeIsHidden)

    fixture.store.upsert(makeItem(kind: .file, text: "/tmp/report.txt", store: fixture.store))
    drainMainQueue()

    fixture.viewModel.selectFirstItem()
    XCTAssertEqual(fixture.viewModel.visibleItems.first?.kind, .file)
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, ["Paste", "Copy", "Pin", "Collect", "Add to Stack", "Preview", "Open", "Reveal", "Delete"])
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionRailWidth, 266)
    XCTAssertFalse(fixture.view.debugFirstCardFooterDetailIsHidden)
    XCTAssertTrue(fixture.view.debugFirstCardHeaderBadgeIsHidden)
  }

  func testCardHeaderUsesKindSymbolBadgeWhenSourceIconIsUnavailable() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com", store: fixture.store))
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugCardHeaderBadgeSymbols, ["link"])
  }

  func testCollectionRailShowsLiveCounts() {
    let fixture = makePanelFixture()
    var pinned = makeTextItem("Pinned note", store: fixture.store)
    pinned.isPinned = true
    let rich = makeItem(kind: .richText, text: "Rich note", store: fixture.store)
    let link = makeItem(kind: .url, text: "https://example.com/releases", store: fixture.store)
    let image = makeItem(kind: .image, text: "image payload", store: fixture.store)
    let audio = makeItem(kind: .audio, text: "audio payload", store: fixture.store)
    let file = makeItem(kind: .file, text: "/tmp/report.pdf", store: fixture.store)

    [pinned, rich, link, image, audio, file].forEach {
      fixture.store.upsert($0)
      drainMainQueue()
    }

    XCTAssertEqual(fixture.viewModel.visibleItems.count, 6)
    XCTAssertEqual(ClipboardSortMode.allCases.map { fixture.viewModel.collectionCount(for: $0) }, [6, 6, 2, 1, 1, 1, 1, 1])
    XCTAssertEqual(fixture.view.debugCollectionCounts, [6, 6, 2, 1, 1, 1, 1, 1])
  }

  func testCollectionRailShowsAssignedCollections() {
    let fixture = makePanelFixture()
    var link = makeItem(kind: .url, text: "https://example.com/read", store: fixture.store)
    link.collectionName = "Useful Links"
    var note = makeTextItem("Meeting note", store: fixture.store)
    note.collectionName = "Important Notes"
    var file = makeItem(kind: .file, text: "/tmp/client-brief.pdf", store: fixture.store)
    file.collectionName = "Client Work"

    fixture.store.upsert(link)
    fixture.store.upsert(note)
    fixture.store.upsert(file)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugCustomCollectionTitles, ["Useful Links", "Important Notes", "Client Work"])
    XCTAssertEqual(fixture.view.debugCustomCollectionCounts, [1, 1, 1])

    fixture.viewModel.selectCollection(named: "Useful Links")
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["https://example.com/read"])
  }

  func testCardsCanDropOntoCollectionChipsToOrganize() {
    let fixture = makePanelFixture()
    var existing = makeTextItem("Existing client note", store: fixture.store)
    existing.collectionName = "Client Work"
    fixture.store.upsert(existing)
    let dropped = makeTextItem("Drop this note", store: fixture.store)
    fixture.store.upsert(dropped)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCustomCollectionTitles, ["Client Work"])
    XCTAssertEqual(fixture.view.debugCustomCollectionDropTargets, ["Client Work"])
    XCTAssertEqual(fixture.viewModel.visibleItems.first?.id, dropped.id)

    fixture.view.debugDropFirstCard(onCollectionNamed: "Client Work")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Added to Client Work")
    XCTAssertEqual(fixture.view.debugCustomCollectionCounts, [2])

    fixture.viewModel.selectCollection(named: "Client Work")
    drainMainQueue()

    XCTAssertEqual(Set(fixture.viewModel.visibleItems.map(\.payload)), ["Existing client note", "Drop this note"])
  }

  func testCollectionRailUsesScrollableDocumentForCrowdedCustomCollections() {
    let fixture = makePanelFixture()
    let names = [
      "Client Work",
      "Research Archive",
      "Launch Planning",
      "Design QA",
      "Product References",
      "Reading Stack",
      "Invoices",
      "Hiring Pipeline"
    ]

    for name in names {
      var item = makeTextItem("Collection item \(name)", store: fixture.store)
      item.collectionName = name
      fixture.store.upsert(item)
    }
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertGreaterThan(fixture.view.debugCollectionRailVisibleWidth, 0)
    XCTAssertGreaterThan(
      fixture.view.debugCollectionRailDocumentWidth,
      fixture.view.debugCollectionRailVisibleWidth + 1
    )
    XCTAssertTrue(fixture.view.debugCustomCollectionTitles.contains("Client Work"))
    XCTAssertTrue(fixture.view.debugCustomCollectionTitles.contains("Product References"))
  }

  func testSelectionScrollsCardRailToKeepSelectedCardVisible() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)

    for index in 0..<8 {
      fixture.store.upsert(makeTextItem("Scrollable clipboard item \(index)", store: fixture.store))
      drainMainQueue()
    }
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.selectFirstItem()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(fixture.view.debugCardRailVisibleRect.minX, 1)

    fixture.viewModel.selectItem(at: fixture.viewModel.visibleItems.count - 1)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let visibleRect = fixture.view.debugCardRailVisibleRect
    let selectedFrame = fixture.view.debugSelectedCardFrameInDocument
    XCTAssertGreaterThan(visibleRect.minX, 0)
    XCTAssertLessThanOrEqual(selectedFrame.minX, visibleRect.maxX)
    XCTAssertGreaterThanOrEqual(visibleRect.maxX + 1, selectedFrame.maxX)

    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertLessThanOrEqual(fixture.view.debugCardRailVisibleRect.minX, 1)
  }

  func testFilteredEmptyStateNamesCurrentCollection() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Only text exists", store: fixture.store))
    drainMainQueue()

    fixture.viewModel.sortMode = .images
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugEmptyStateText?.title, "No images yet")
    XCTAssertEqual(fixture.view.debugEmptyStateText?.detail, "Image clips are saved when the clipboard contains image data.")
  }

  func testCardsExposeContextMenuActions() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Context menu text", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Add to Stack", "Edit", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
    XCTAssertEqual(
      fixture.view.debugFirstCardCollectionMenuTitles,
      ["Useful Links", "Important Notes", "Code Snippets", "Read Later", "-", "New Collection..."]
    )
    XCTAssertEqual(
      fixture.view.debugFirstCardCollectActionMenuTitles,
      ["Useful Links", "Important Notes", "Code Snippets", "Read Later", "-", "New Collection..."]
    )
    XCTAssertEqual(
      fixture.view.debugFirstCardCaptureRuleMenuTitles,
      ["Ignore Ghostty", "Ignore Text Items"]
    )
  }

  func testFilteredCardsExposeShowInClipboardContextMenuAction() {
    let fixture = makePanelFixture()
    var release = makeTextItem("Release needle", store: fixture.store)
    release.createdAt = Date(timeIntervalSince1970: 100)
    release.lastUsedAt = release.createdAt
    var meeting = makeTextItem("Meeting note", store: fixture.store)
    meeting.createdAt = Date(timeIntervalSince1970: 200)
    meeting.lastUsedAt = meeting.createdAt
    fixture.store.upsert(release)
    fixture.store.upsert(meeting)
    drainMainQueue()

    fixture.viewModel.searchText = "release"
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Show in Clipboard", "Add to Stack", "Edit", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )

    fixture.view.debugShowFirstCardInClipboard()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Meeting note", "Release needle"])
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Release needle")
  }

  func testPreviewableCardsExposeQuickLookContextMenuAction() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeItem(kind: .file, text: "/tmp/report.txt", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Paste Plain Text", "Copy Plain Text", "Add to Stack", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
    XCTAssertEqual(
      fixture.view.debugFirstCardCaptureRuleMenuTitles,
      ["Ignore Ghostty", "Ignore File Items"]
    )
  }

  func testStackedCardsExposeStackManagementActions() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Stackable text", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.toggleSelectedStackMembership()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Remove from Stack", "Paste Stack Next", "Copy Stack Next", "Clear Stack", "Edit", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, ["Paste", "Copy", "Pin", "Collect", "Remove from Stack", "Edit", "Delete"])
  }

  func testStackChipAppearsFiltersAndClearsWithStack() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("First stack chip item", store: fixture.store))
    fixture.store.upsert(makeTextItem("Second stack chip item", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugStackChipIsVisible)

    fixture.viewModel.selectItem(at: 1)
    fixture.viewModel.toggleSelectedStackMembership()
    fixture.viewModel.selectItem(at: 0)
    fixture.viewModel.toggleSelectedStackMembership()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStackChipCount, 2)
    XCTAssertFalse(fixture.view.debugStackChipIsSelected)

    fixture.view.debugPressStackChip()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Stack")
    XCTAssertTrue(fixture.view.debugStackChipIsSelected)
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["First stack chip item", "Second stack chip item"])

    fixture.viewModel.clearStack()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStackChipCount, 0)
  }

  func testCollectionMenuOffersExistingCustomCollections() {
    let fixture = makePanelFixture()
    var existing = makeTextItem("Existing client note", store: fixture.store)
    existing.collectionName = "Client Work"
    fixture.store.upsert(existing)
    fixture.store.upsert(makeTextItem("Unsorted card", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardCollectionMenuTitles,
      ["Useful Links", "Important Notes", "Code Snippets", "Read Later", "Client Work", "-", "New Collection..."]
    )
    XCTAssertEqual(
      fixture.view.debugFirstCardCollectActionMenuTitles,
      ["Useful Links", "Important Notes", "Code Snippets", "Read Later", "Client Work", "-", "New Collection..."]
    )
  }

  func testBottomSafeInsetIsAppliedToPanelContent() {
    let fixture = makePanelFixture()

    fixture.view.setBottomSafeInset(108)

    XCTAssertEqual(fixture.view.debugContentInsets.bottom, 108)
  }

  func testInternalLookingTextDoesNotBecomePrimaryCardTitle() {
    let fixture = makePanelFixture()
    let item = makeTextItem("clipbored-flow-test-\(UUID().uuidString)", store: fixture.store)

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Text: Copied text"])
  }

  func testLinkCardsUseReadableTitleAndAddressPreview() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .url,
      displayText: "Release notes",
      payload: "https://www.example.com/releases/v1?utm_source=copy",
      store: fixture.store
    )

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Link: Release notes"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Release notes|example.com/releases/v1|example.com"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["link-preview"])
  }

  func testLinkCardsUseMediaPreviewWhenThumbnailExists() throws {
    let fixture = makePanelFixture()
    let id = UUID()
    let paths = try XCTUnwrap(fixture.cacheService.cacheImage(sampleImage(), id: id))
    let item = ClipboardItem(
      id: id,
      kind: .url,
      displayText: "Lookbook",
      payload: "https://example.com/lookbook",
      payloadHash: fixture.store.hashString("https://example.com/lookbook"),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: "Safari",
      imagePath: paths.full,
      thumbnailPath: paths.thumb
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .links
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Link: Lookbook"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Lookbook|example.com/lookbook|example.com"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["link-media-preview"])
  }

  func testRichTextCardsUseDisplayTextInsteadOfManagedPayloadPath() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .richText,
      displayText: "Styled note",
      payload: "/tmp/clipbored-managed-rich-text.rtf",
      store: fixture.store
    )

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Rich Text: Styled note"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Styled note|Styled note|11 characters"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["rich-text-preview"])
  }

  func testFileCardsUseFilenameLocationAndType() {
    let fixture = makePanelFixture()
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Documents")
      .appendingPathComponent("Project Plan.pdf")
    let item = makeItem(kind: .file, displayText: "File", payload: fileURL.path, store: fixture.store)

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["File: Project Plan.pdf"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Project Plan.pdf|~/Documents|PDF"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["file-preview"])
  }

  func testMultipleFileCardsUseCountAndSharedLocation() throws {
    let fixture = makePanelFixture()
    let directory = makeTempDirectory()
    let firstURL = directory.appendingPathComponent("Brief.pdf")
    let secondURL = directory.appendingPathComponent("Invoice.csv")
    try Data("brief".utf8).write(to: firstURL)
    try Data("invoice".utf8).write(to: secondURL)
    let item = makeItem(
      kind: .file,
      displayText: "2 files",
      payload: FilePayload.payload(from: [firstURL, secondURL]),
      store: fixture.store
    )

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["File: 2 files"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["2 files|\(directory.path)|2 files"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["file-preview"])
  }

  func testExistingFileCardsUseFullBleedMediaPreviewLayout() throws {
    let fixture = makePanelFixture()
    let imageURL = makeTempDirectory().appendingPathComponent("Campaign Reference.png")
    let imageData = try XCTUnwrap(sampleImage().pngData())
    try imageData.write(to: imageURL)
    let item = makeItem(kind: .file, displayText: "File", payload: imageURL.path, store: fixture.store)

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .files
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["File: Campaign Reference.png"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["file-media-preview"])
  }

  func testPdfAndImageCardsUseSpecificPreviewText() {
    let fixture = makePanelFixture()
    let pdfURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Downloads")
      .appendingPathComponent("Reference Guide.pdf")
    let pdf = makeItem(
      kind: .pdf,
      displayText: "PDF",
      payload: pdfURL.path,
      store: fixture.store,
      ocrText: "Quarterly metrics\nSecond page"
    )

    fixture.store.upsert(pdf)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["PDF: Reference Guide.pdf"])
    XCTAssertEqual(
      fixture.view.debugCardPreviewSummaries,
      ["Reference Guide.pdf|Quarterly metrics Second page|PDF"]
    )
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["file-preview"])

    let image = makeItem(
      kind: .image,
      displayText: "Image",
      payload: "",
      store: fixture.store,
      ocrText: "Receipt total $42"
    )
    fixture.store.upsert(image)
    fixture.viewModel.sortMode = .images
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Image: Receipt total $42"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Receipt total $42|Receipt total $42|OCR text"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["text-fallback-preview"])
  }

  func testImageCardsUseMediaPreviewWhenThumbnailExists() {
    let fixture = makePanelFixture()
    let item = makeCachedImageItem(store: fixture.store, cacheService: fixture.cacheService)

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .images
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Image: Campaign portrait"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["media-preview"])
  }

  func testAudioCardsUseSpecificPreviewText() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .audio,
      displayText: "Audio (14 KB)",
      payload: "/tmp/clipbored-audio.sound",
      store: fixture.store
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .audio
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Audio: Audio (14 KB)"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Audio (14 KB)|Sound clip|Audio"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["audio-preview"])
  }

  private func makePanelWithPanelView() -> (NSWindow, ClipboardPanelView) {
    let fixture = makePanelFixture()
    return (fixture.window, fixture.view)
  }

  private func makePanelFixture() -> PanelFixture {
    let settings = makeSettings()
    let cacheService = ClipboardCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)

    let view = ClipboardPanelView(
      viewModel: viewModel,
      onClose: {},
      onSettings: {}
    )

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 520),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    return PanelFixture(
      window: window,
      view: view,
      viewModel: viewModel,
      settings: settings,
      store: store,
      cacheService: cacheService
    )
  }

  private func makeSettings() -> SettingsModel {
    let settings = SettingsModel(defaults: UserDefaults(suiteName: "com.clipbored.viewtest.\(UUID().uuidString)")!)
    settings.maxHistoryItems = 10
    settings.pruneDuplicates = false
    return settings
  }

  private func makeStore(settings: SettingsModel, cacheService: ClipboardCacheService) -> ClipboardStore {
    ClipboardStore(settings: settings, cacheService: cacheService, baseURL: makeTempDirectory())
  }

  private func makeTempDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipbored-viewtest")
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    tempURLs.append(directory)
    return directory
  }

  private func makeTextItem(_ text: String, store: ClipboardStore) -> ClipboardItem {
    makeItem(kind: .text, text: text, store: store)
  }

  private func makeItem(kind: ClipboardItemKind, text: String, store: ClipboardStore) -> ClipboardItem {
    makeItem(kind: kind, displayText: text, payload: text, store: store)
  }

  private func makeItem(
    kind: ClipboardItemKind,
    displayText: String,
    payload: String,
    store: ClipboardStore,
    ocrText: String? = nil
  ) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: kind,
      displayText: displayText,
      payload: payload,
      payloadHash: store.hashString(payload),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: "Ghostty",
      imagePath: nil,
      thumbnailPath: nil,
      ocrText: ocrText
    )
  }

  private func makeCachedImageItem(store: ClipboardStore, cacheService: ClipboardCacheService) -> ClipboardItem {
    let id = UUID()
    let paths = cacheService.cacheImage(sampleImage(), id: id)
    return ClipboardItem(
      id: id,
      kind: .image,
      displayText: "Campaign portrait",
      payload: paths?.full ?? "",
      payloadHash: store.hashString("campaign-portrait"),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: "Photos",
      imagePath: paths?.full,
      thumbnailPath: paths?.thumb,
      ocrText: nil
    )
  }

  private func sampleImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 180, height: 140))
    image.lockFocus()
    NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.20, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 180, height: 140).fill()
    NSColor(calibratedRed: 0.92, green: 0.20, blue: 0.26, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 34, y: 24, width: 82, height: 82)).fill()
    NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.86, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 92, y: 45, width: 58, height: 48), xRadius: 12, yRadius: 12).fill()
    image.unlockFocus()
    return image
  }

  private func drainMainQueue() {
    for _ in 0..<20 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }
}
