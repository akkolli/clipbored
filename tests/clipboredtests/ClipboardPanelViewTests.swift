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
    let previewProbe: PreviewProbe
  }

  private final class PreviewProbe {
    var requestCount = 0
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

  func testSearchFieldExpandsWhileFocusedEvenWhenEmptyAndCollapsesWhenIdle() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Search focus polish", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "")

    fixture.view.focusSearchField()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchControlHeight, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchIconButtonHeight, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "Search clips")

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchControlHeight, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchIconButtonHeight, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertFalse(fixture.view.debugSearchFieldIsVisible)
    XCTAssertTrue(fixture.view.debugSearchIconButtonIsVisible)
  }

  func testSearchFieldCollapsesWhenClearedWhileIdle() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Idle search collapse", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("idle")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "Search clips")

    fixture.view.debugSetSearchFieldText("")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertFalse(fixture.view.debugSearchFieldIsVisible)
    XCTAssertTrue(fixture.view.debugSearchIconButtonIsVisible)
  }

  func testWhitespaceOnlySearchTextKeepsFieldExpandedUntilCleared() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Whitespace search presentation", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertFalse(fixture.view.debugSearchFieldIsVisible)
    XCTAssertTrue(fixture.view.debugSearchIconButtonIsVisible)

    fixture.view.debugSetSearchFieldText("   ")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "   ")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "Search clips")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Whitespace search presentation"])

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "   ")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)

    XCTAssertTrue(fixture.view.clearSearchForKeyboardCancel())
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertTrue(fixture.view.debugSearchFieldIsVisible)
    XCTAssertFalse(fixture.view.debugSearchIconButtonIsVisible)

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertFalse(fixture.view.debugSearchFieldIsVisible)
    XCTAssertTrue(fixture.view.debugSearchIconButtonIsVisible)
  }

  func testPrepareForShowClearsSearchAndLeavesFieldCollapsedUntilTyping() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Quantum launch note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Alpha planning note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("alpha")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Alpha planning note"])

    fixture.view.prepareForShow()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertFalse(fixture.view.debugSearchFieldIsVisible)
    XCTAssertTrue(fixture.view.debugSearchIconButtonIsVisible)
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Alpha planning note", "Quantum launch note"])

    XCTAssertTrue(fixture.window.makeFirstResponder(fixture.view))
    fixture.view.debugTypeFocusedResponder("q", keyCode: 12)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "q")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertTrue(fixture.view.debugSearchFieldIsVisible)
    XCTAssertFalse(fixture.view.debugSearchIconButtonIsVisible)
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum launch note"])
  }

  func testCommandFStyleSearchActionKeepsFocusInSearchField() {
    let (window, view) = makePanelWithPanelView()
    view.debugSuppressSearchFilterMenuPresentation()

    window.makeFirstResponder(view)
    XCTAssertFalse(view.focusSearchOrShowFilters())
    XCTAssertTrue(view.isSearchFieldEditing)
    XCTAssertEqual(view.debugSearchFilterMenuPresentationCount, 0)

    XCTAssertFalse(view.focusSearchOrShowFilters())

    XCTAssertEqual(view.debugSearchFilterMenuPresentationCount, 0)
    XCTAssertTrue(view.isSearchFieldEditing)
  }

  func testPlainTextEditorsOptIntoWritingToolsWhenRuntimeSupportsIt() {
    let textView = ClipboardPanelView.makePlainTextEditor(initialText: "Rewrite this launch note")

    XCTAssertEqual(textView.string, "Rewrite this launch note")
    XCTAssertFalse(textView.isRichText)
    XCTAssertFalse(textView.importsGraphics)
    XCTAssertTrue(textView.allowsUndo)
    XCTAssertTrue(textView.isAutomaticSpellingCorrectionEnabled)
    XCTAssertTrue(textView.isAutomaticTextReplacementEnabled)

    if textView.responds(to: NSSelectorFromString("setWritingToolsBehavior:")) {
      XCTAssertEqual(textView.value(forKey: "writingToolsBehavior") as? Int, 1)
    }
    if textView.responds(to: NSSelectorFromString("setAllowedWritingToolsResultOptions:")) {
      XCTAssertEqual(textView.value(forKey: "allowedWritingToolsResultOptions") as? Int, 1)
    }
  }

  func testShelfChromeKeepsSearchAboveSideIconCategoryRail() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Compact shelf chrome", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugShelfChromeRowCount, 1)
    XCTAssertFalse(fixture.view.debugShelfChromeContainsSearchAndCollections)
    XCTAssertTrue(fixture.view.debugShelfChromeContainsSearchAndActions)
    XCTAssertTrue(fixture.view.debugCollectionRailIsBesideCardRail)
    XCTAssertTrue(fixture.view.debugSearchFieldSharesAnimatedContainerWithIcon)
    XCTAssertEqual(fixture.view.debugSearchAnimationDuration, 0.14, accuracy: 0.01)
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertFalse(fixture.view.debugSearchFieldIsVisible)
    XCTAssertTrue(fixture.view.debugSearchIconButtonIsVisible)
    XCTAssertEqual(fixture.view.debugCollectionStackOrientation, .vertical)
    XCTAssertEqual(fixture.view.debugCollectionRailVisibleWidth, 36, accuracy: 0.5)
    XCTAssertGreaterThan(fixture.view.debugCollectionRailContentTopInset, 0)
    XCTAssertEqual(
      fixture.view.debugCollectionRailContentFrameInPanel.midY,
      fixture.view.debugCollectionRailFrameInPanel.midY,
      accuracy: 1
    )
    XCTAssertEqual(
      fixture.view.debugCollectionRailFrameInPanel.midX,
      fixture.view.debugSelectedCardFrameInPanel.minX / 2,
      accuracy: 2
    )
    XCTAssertLessThan(fixture.view.debugCollectionRailFrameInPanel.midX, fixture.view.bounds.midX)
    XCTAssertFalse(fixture.view.debugStatusBarIsVisible)
    XCTAssertEqual(fixture.view.debugUtilityToolbarGroupBackgroundAlpha, 0, accuracy: 0.01)
    XCTAssertEqual(fixture.view.debugUtilityToolbarGroupCornerRadius, 14, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugToolbarButtonBackgroundAlphas.count, 2)
    fixture.view.debugToolbarButtonBackgroundAlphas.forEach { alpha in
      XCTAssertEqual(alpha, 0.08, accuracy: 0.01)
    }
    XCTAssertEqual(fixture.view.debugToolbarButtonBorderWidths, [0.5, 0.5])

    fixture.view.debugSetSearchFieldText("type:text")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "Search clips")
    XCTAssertTrue(fixture.view.debugSearchFieldIsVisible)
    XCTAssertFalse(fixture.view.debugSearchIconButtonIsVisible)
  }

  func testCollectionRailStaysOnSideAcrossSelection() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Centered text category", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com/centered", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .image, text: "centered-image", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    assertCollectionRailIsSideIconRail(in: fixture)

    fixture.view.debugMouseDownCollectionChip(.text)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    assertCollectionRailIsSideIconRail(in: fixture)
  }

  func testHoveringCategoryPreviewsThenRestoresOriginalCategoryWhenLeavingRail() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Plain text clip", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com/preview", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .image, text: "preview-image", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(Set(fixture.viewModel.visibleItems.map(\.kind)), Set([.text, .url, .image]))

    fixture.view.debugHoverCollectionChip(.links)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Links")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.kind), [.url])

    fixture.view.debugUnhoverCollectionChip(.links)
    fixture.view.debugHoverCollectionChip(.text)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Text")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.kind), [.text])

    fixture.view.debugUnhoverCollectionChip(.text)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(Set(fixture.viewModel.visibleItems.map(\.kind)), Set([.text, .url, .image]))
  }

  func testClickingHoveredCategoryCommitsPreviewAfterMouseLeaves() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Commit text clip", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com/commit", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .image, text: "commit-image", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugHoverCollectionChip(.images)
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Images")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.kind), [.image])

    fixture.view.debugMouseDownCollectionChip(.images)
    fixture.view.debugUnhoverCollectionChip(.images)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Images")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.kind), [.image])
  }

  func testSideShelfKeepsCardRailTuckedUnderToolbar() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 640), display: true)
    fixture.store.upsert(makeTextItem("Tall shelf top spacing", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertLessThanOrEqual(fixture.view.debugCardRailTopGap, 96)
  }

  func testSideShelfUsesRowsAndExpandsSelection() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)
    fixture.store.upsert(makeTextItem("Side first compact row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Side second compact row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Side third compact row", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugPanelLayout, ClipboardPanelLayout.vertical.title)
    XCTAssertEqual(fixture.view.debugItemsStackOrientation, .vertical)
    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-row", "vertical-row"])
    XCTAssertGreaterThan(fixture.view.debugCardSizes[0].width, fixture.view.debugCardSizes[0].height)
    XCTAssertLessThanOrEqual(
      fixture.view.debugCollectionRailFrameInPanel.maxX + 8,
      fixture.view.debugSelectedCardFrameInPanel.minX + 0.5
    )
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes[0].height, 72)
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes[2].height, 72)

    XCTAssertTrue(fixture.view.debugFocusCard(at: 1))
    RunLoop.main.run(until: Date().addingTimeInterval(fixture.view.debugCardExpansionAnimationDuration + 0.04))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-focus", "vertical-row"])
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes[0].height, 72)
    XCTAssertGreaterThanOrEqual(fixture.view.debugCardSizes[1].height, 200)
  }

  func testVerticalShelfUsesRowsAndExpandsSelection() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 380, height: 760), display: true)
    fixture.store.upsert(makeTextItem("Vertical first compact row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Vertical second compact row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Vertical third compact row", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-row", "vertical-row"])
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes[0].height, 72)
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes[1].height, 72)
    XCTAssertGreaterThan(fixture.view.debugCardSizes[1].width, fixture.view.debugCardSizes[1].height)
    XCTAssertEqual(fixture.view.debugCardSizes[2].height, 56, accuracy: 0.5)

    XCTAssertTrue(fixture.view.debugFocusCard(at: 1))
    RunLoop.main.run(until: Date().addingTimeInterval(fixture.view.debugCardExpansionAnimationDuration + 0.04))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-focus", "vertical-row"])
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes[0].height, 72)
    XCTAssertEqual(fixture.view.debugCardSizes[1].height, 220, accuracy: 0.5)
  }

  func testSideShelfAnimatesCardExpansionWhenSelectionMoves() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)
    fixture.store.upsert(makeTextItem("Animation first compact row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Animation second compact row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Animation third compact row", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-row", "vertical-row"])
    let layoutChangeCount = fixture.view.debugAnimatedCardLayoutChangeCount
    let presentationChangeCounts = fixture.view.debugCardAnimatedPresentationChangeCounts
    XCTAssertEqual(fixture.view.debugCardExpansionAnimationDuration, 0.36, accuracy: 0.01)

    XCTAssertTrue(fixture.view.debugFocusCard(at: 1))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-focus", "vertical-row"])
    XCTAssertGreaterThan(fixture.view.debugAnimatedCardLayoutChangeCount, layoutChangeCount)
    XCTAssertGreaterThan(fixture.view.debugCardAnimatedPresentationChangeCounts[1], presentationChangeCounts[1])
    XCTAssertGreaterThan(fixture.view.debugCardAnimatedPresentationChangeCounts[2], presentationChangeCounts[2])
  }

  func testHoverExpansionKeepsHeaderStableAndRollsDetailBelowIt() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)
    fixture.store.upsert(makeTextItem("Stable header first row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Stable header second row", store: fixture.store))
    fixture.store.upsert(makeTextItem("Stable header third row", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let headerBefore = fixture.view.debugCardHeaderFramesInPanel[1]
    let detailBefore = fixture.view.debugCardExpandedDetailFramesInPanel[1]
    let cornerRadiusBefore = fixture.view.debugCardContentCornerRadii[1]
    let followingSlotClosedY = fixture.view.debugCardSlotPresentationFramesInPanel[2].minY
    let layoutChangeCount = fixture.view.debugAnimatedCardLayoutChangeCount

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-row", "vertical-row"])
    XCTAssertEqual(detailBefore.height, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCardContentBackgroundAlphas[1], 0, accuracy: 0.01)

    fixture.view.debugHoverCard(at: 1)
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    let detailDuringAnimation = fixture.view.debugCardExpandedDetailPresentationHeights[1]
    XCTAssertGreaterThan(detailDuringAnimation, detailBefore.height + 4)
    XCTAssertLessThan(detailDuringAnimation, 220)

    RunLoop.main.run(until: Date().addingTimeInterval(fixture.view.debugCardExpansionAnimationDuration + 0.04))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let headerAfter = fixture.view.debugCardHeaderFramesInPanel[1]
    let detailAfter = fixture.view.debugCardExpandedDetailFramesInPanel[1]
    let cornerRadiusAfter = fixture.view.debugCardContentCornerRadii[1]
    let followingSlotExpandedY = fixture.view.debugCardSlotPresentationFramesInPanel[2].minY

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-focus", "vertical-row"])
    XCTAssertGreaterThan(fixture.view.debugAnimatedCardLayoutChangeCount, layoutChangeCount)
    XCTAssertEqual(headerAfter.minX, headerBefore.minX, accuracy: 0.5)
    XCTAssertEqual(headerAfter.minY, headerBefore.minY, accuracy: 0.5)
    XCTAssertEqual(headerAfter.width, headerBefore.width, accuracy: 0.5)
    XCTAssertEqual(headerAfter.height, headerBefore.height, accuracy: 0.5)
    XCTAssertEqual(cornerRadiusAfter, cornerRadiusBefore, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCardContentBackgroundAlphas[1], 0, accuracy: 0.01)
    XCTAssertGreaterThan(detailAfter.height, detailBefore.height + 120)
    XCTAssertTrue(
      abs(detailAfter.maxY - headerAfter.minY) <= 1
        || abs(detailAfter.minY - headerAfter.maxY) <= 1
    )
    XCTAssertGreaterThan(abs(followingSlotExpandedY - followingSlotClosedY), 100)

    let layoutChangeCountAfterHover = fixture.view.debugAnimatedCardLayoutChangeCount
    let detailExpandedHeight = detailAfter.height
    fixture.view.debugUnhoverCard(at: 1)
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    let detailDuringClose = fixture.view.debugCardExpandedDetailPresentationHeights[1]
    let followingSlotDuringCloseY = fixture.view.debugCardSlotPresentationFramesInPanel[2].minY
    XCTAssertGreaterThan(detailDuringClose, 4)
    XCTAssertLessThan(detailDuringClose, detailExpandedHeight - 4)
    XCTAssertGreaterThan(
      followingSlotDuringCloseY,
      min(followingSlotClosedY, followingSlotExpandedY) + 4
    )
    XCTAssertLessThan(
      followingSlotDuringCloseY,
      max(followingSlotClosedY, followingSlotExpandedY) - 4
    )

    RunLoop.main.run(until: Date().addingTimeInterval(fixture.view.debugCardExpansionAnimationDuration + 0.04))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [])
    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-row", "vertical-row"])
    XCTAssertGreaterThan(fixture.view.debugAnimatedCardLayoutChangeCount, layoutChangeCountAfterHover)
    XCTAssertEqual(fixture.view.debugCardExpandedDetailFramesInPanel[1].height, 0, accuracy: 0.5)
  }

  func testHoverDuringCollapseUsesVisualCardUnderMouseInsteadOfCollapsedTargetSlot() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)
    for index in 0..<8 {
      fixture.store.upsert(makeTextItem("Visual hover row \(index)", store: fixture.store))
    }
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugHoverCard(at: 1)
    RunLoop.main.run(until: Date().addingTimeInterval(fixture.view.debugCardExpansionAnimationDuration + 0.04))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [1])

    fixture.view.debugUnhoverCard(at: 1)
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    let visualRowFrame = fixture.view.debugCardSlotPresentationFramesInPanel[2]
    let visualRowPoint = NSPoint(x: visualRowFrame.midX, y: visualRowFrame.midY)

    fixture.view.debugHoverCard(at: 6, mouseLocationInPanel: visualRowPoint)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [2])
    XCTAssertEqual(fixture.viewModel.selectedIndex, 2)
  }

  func testToolbarControlsExposeVoiceOverActionHints() {
    let fixture = makePanelFixture()

    XCTAssertEqual(
      fixture.view.debugSearchFieldAccessibilityHelp,
      "Type to search clipboard history. Use the side category icons to filter results."
    )
    XCTAssertEqual(
      fixture.view.debugSearchFilterButtonAccessibilityHelp,
      ""
    )
    XCTAssertEqual(
      fixture.view.debugAddCollectionButtonAccessibilityHelp,
      "Create a new Pinboard collection. Keyboard shortcut: Shift-Command-N."
    )
    XCTAssertEqual(
      fixture.view.debugToolbarButtonAccessibilityLabels,
      ["Clear History", "Settings"]
    )
    XCTAssertEqual(
      fixture.view.debugToolbarButtonAccessibilityHelps,
      [
        "Clear history.",
        "Open ClipBored settings. Keyboard shortcut: Command-Comma."
      ]
    )

    fixture.view.debugToggleCompactMode()
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugCompactModeButtonAccessibilityValue, "")
    XCTAssertEqual(
      fixture.view.debugToolbarButtonAccessibilityHelps,
      [
        "Clear history.",
        "Open ClipBored settings. Keyboard shortcut: Command-Comma."
      ]
    )
  }

  func testSearchFilterMenuInsertsStructuredTokens() {
    let fixture = makePanelFixture()
    var image = makeItem(kind: .image, displayText: "Safari screenshot", payload: "/tmp/safari-screenshot.png", store: fixture.store)
    image.sourceApp = "Safari"
    image.sourceDeviceName = "MacBook Pro"
    image.collectionName = "Client Work"
    var text = makeTextItem("Notes follow-up", store: fixture.store)
    text.sourceApp = "Notes"
    fixture.store.upsert(image)
    fixture.store.upsert(text)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugSearchFilterMenuTitles,
      ["Type", "Date", "Pinned Items", "Copied From", "Device", "Pinboard"]
    )
    XCTAssertEqual(
      fixture.view.debugSearchFilterSubmenuTitles(named: "Type"),
      ["Text", "Rich Text", "Links", "Images", "Files", "PDFs", "Audio", "Videos", "Colors", "Code"]
    )
    XCTAssertTrue(fixture.view.debugSearchFilterSubmenuTitles(named: "Copied From").contains("Safari"))
    XCTAssertTrue(fixture.view.debugSearchFilterSubmenuTitles(named: "Device").contains("MacBook Pro"))
    XCTAssertEqual(fixture.view.debugSearchFilterSubmenuTitles(named: "Pinboard"), ["Client Work"])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Images", inSubmenu: "Type")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "type:image")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["/tmp/safari-screenshot.png"])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Safari", inSubmenu: "Copied From")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "type:image app:\"Safari\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["/tmp/safari-screenshot.png"])

    fixture.view.debugSetSearchFieldText("")
    fixture.view.debugPerformSearchFilterMenuItem(titled: "Client Work", inSubmenu: "Pinboard")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "pinboard:\"Client Work\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["/tmp/safari-screenshot.png"])
  }

  func testSearchFilterMenuDateTokensUseLocalCalendarDay() {
    let fixture = makePanelFixture()
    let lateLocalEvening = localDate("2026-07-04", hour: 23, minute: 30)

    XCTAssertEqual(
      fixture.view.debugSearchFilterSubmenuTokens(named: "Date", now: lateLocalEvening),
      [
        "date:2026-07-04",
        "after:2026-06-28",
        "before:2026-07-04"
      ]
    )
  }

  func testSearchFilterMenuDatePresetReplacesExistingDateRange() {
    let fixture = makePanelFixture()
    var today = makeTextItem("Today launch note", store: fixture.store)
    today.createdAt = localDate("2026-07-04", hour: 12)
    today.lastUsedAt = today.createdAt
    var yesterday = makeTextItem("Yesterday launch note", store: fixture.store)
    yesterday.createdAt = localDate("2026-07-03", hour: 12)
    yesterday.lastUsedAt = yesterday.createdAt
    fixture.store.upsert(today)
    fixture.store.upsert(yesterday)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("launch before:2026-07-04 after:2026-06-28")
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Yesterday launch note"])

    fixture.view.debugApplySearchFilterToken("date:2026-07-04")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "launch date:2026-07-04")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Today launch note"])
  }

  func testSearchFilterMenuPinnedPresetReplacesExistingPinnedState() {
    let fixture = makePanelFixture()
    var pinned = makeTextItem("Pinned launch note", store: fixture.store)
    pinned.isPinned = true
    pinned.createdAt = Date(timeIntervalSince1970: 200)
    pinned.lastUsedAt = pinned.createdAt
    var unpinned = makeTextItem("Unpinned launch note", store: fixture.store)
    unpinned.createdAt = Date(timeIntervalSince1970: 100)
    unpinned.lastUsedAt = unpinned.createdAt
    fixture.store.upsert(pinned)
    fixture.store.upsert(unpinned)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("launch pin:off")
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Unpinned launch note"])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Pinned Items")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "launch pinned:on")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Pinned launch note"])
  }

  func testSearchFilterMenuTypePresetReplacesExistingTypeFilter() {
    let fixture = makePanelFixture()
    var text = makeTextItem("Launch note", store: fixture.store)
    text.createdAt = Date(timeIntervalSince1970: 100)
    text.lastUsedAt = text.createdAt
    var image = makeItem(kind: .image, displayText: "Launch screenshot", payload: "/tmp/launch.png", store: fixture.store)
    image.createdAt = Date(timeIntervalSince1970: 200)
    image.lastUsedAt = image.createdAt
    fixture.store.upsert(text)
    fixture.store.upsert(image)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("launch kind:image")
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["/tmp/launch.png"])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Text", inSubmenu: "Type")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "launch type:text")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Launch note"])
  }

  func testSearchFilterMenuTreatsExistingFiltersAsWholeTokens() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Safari research clip", store: fixture.store)
    item.sourceApp = "Safari"
    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("app:SafariResearch")
    drainMainQueue()

    XCTAssertTrue(fixture.viewModel.visibleItems.isEmpty)

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Safari", inSubmenu: "Copied From")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "app:SafariResearch app:\"Safari\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Safari research clip"])
  }

  func testSearchFilterMenuUsesExactSourceAppValues() {
    let fixture = makePanelFixture()
    var safari = makeTextItem("Safari clip", store: fixture.store)
    safari.sourceApp = "Safari"
    var preview = makeTextItem("Technology preview clip", store: fixture.store)
    preview.sourceApp = "Safari Technology Preview"
    fixture.store.upsert(safari)
    fixture.store.upsert(preview)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Safari", inSubmenu: "Copied From")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "app:\"Safari\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Safari clip"])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Safari", inSubmenu: "Copied From")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "app:\"Safari\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Safari clip"])
  }

  func testSearchFilterMenuUpgradesMatchingFuzzySourceFilterToExactValue() {
    let fixture = makePanelFixture()
    var safari = makeTextItem("Safari clip", store: fixture.store)
    safari.sourceApp = "Safari"
    var preview = makeTextItem("Technology preview clip", store: fixture.store)
    preview.sourceApp = "Safari Technology Preview"
    fixture.store.upsert(safari)
    fixture.store.upsert(preview)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("app:Safari")
    drainMainQueue()

    XCTAssertEqual(Set(fixture.viewModel.visibleItems.map(\.payload)), ["Safari clip", "Technology preview clip"])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Safari", inSubmenu: "Copied From")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "app:\"Safari\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Safari clip"])
  }

  func testSearchFilterMenuPreservesQuotesInStructuredValues() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Quoted pinboard clip", store: fixture.store)
    item.collectionName = "Client \"VIP\""
    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFilterSubmenuTitles(named: "Pinboard"), ["Client \"VIP\""])

    fixture.view.debugPerformSearchFilterMenuItem(titled: "Client \"VIP\"", inSubmenu: "Pinboard")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "pinboard:\"Client \\\"VIP\\\"\"")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quoted pinboard clip"])
  }

  func testSearchFilterMenuPreservesInvalidStructuredLookingText() {
    let fixture = makePanelFixture()

    fixture.view.debugSetSearchFieldText("launch before:lunch kind:maybe pinned:maybe")
    fixture.view.debugApplySearchFilterToken("date:2026-07-04")
    drainMainQueue()

    XCTAssertEqual(
      fixture.view.debugSearchFieldText,
      "launch before:lunch kind:maybe pinned:maybe date:2026-07-04"
    )

    fixture.view.debugApplySearchFilterToken("type:text")
    drainMainQueue()

    XCTAssertEqual(
      fixture.view.debugSearchFieldText,
      "launch before:lunch kind:maybe pinned:maybe date:2026-07-04 type:text"
    )

    fixture.view.debugApplySearchFilterToken("pinned:on")
    drainMainQueue()

    XCTAssertEqual(
      fixture.view.debugSearchFieldText,
      "launch before:lunch kind:maybe pinned:maybe date:2026-07-04 type:text pinned:on"
    )
  }

  func testActiveVerticalCardAvoidsRectangularShadowChrome() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Neighbor card chrome", store: fixture.store))
    fixture.store.upsert(makeTextItem("Active card chrome", store: fixture.store))
    drainMainQueue()
    fixture.viewModel.selectItem(at: 0)
    fixture.view.debugHoverCard(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertGreaterThanOrEqual(
      fixture.view.debugDocumentViewFrame.height,
      fixture.view.debugCardRailVisibleRect.height - 1
    )
    XCTAssertEqual(fixture.view.debugFirstCardShadowOpacity, 0, accuracy: 0.01)
    XCTAssertEqual(fixture.view.debugFirstCardShadowRadius, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugFirstCardLayerTranslationY, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugFirstCardSlotTopOffset, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSecondCardSlotTopOffset, 0, accuracy: 0.5)
    XCTAssertGreaterThan(fixture.view.debugFirstCardSlotZPosition, fixture.view.debugSecondCardSlotZPosition)
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
    XCTAssertGreaterThanOrEqual(
      fixture.view.debugDocumentViewFrame.height,
      fixture.view.debugCardRailVisibleRect.height - 1
    )
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["text-preview"])
    XCTAssertEqual(fixture.view.debugCardRailOverflowFadeVisibility, [false, false])
  }

  func testSingleLineTextCardsDoNotDuplicateTitleInBody() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Client follow-up note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardTextPreviewTitles, ["Client follow-up note"])
    XCTAssertEqual(fixture.view.debugCardTextPreviewBodies, [""])
    XCTAssertEqual(fixture.view.debugCardTextPreviewChromes, ["paper-preview"])
    XCTAssertEqual(fixture.view.debugCardTextPreviewAccentHexes, ["#F8B200"])
    XCTAssertEqual(fixture.view.debugCardTextPreviewFadePlacements, ["none"])
  }

  func testMultiLineTextCardsShowRemainderBelowTitle() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Address:\n399 The Embarcadero\nSan Francisco", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardTextPreviewTitles, ["Address:"])
    XCTAssertEqual(fixture.view.debugCardTextPreviewBodies, ["399 The Embarcadero San Francisco"])
    XCTAssertEqual(fixture.view.debugCardTextPreviewChromes, ["paper-preview"])
    XCTAssertEqual(fixture.view.debugCardTextPreviewFadePlacements, ["bottom"])
  }

  func testCompactRowsFitSideShelf() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 520), display: true)
    fixture.store.upsert(makeTextItem("Compact first", store: fixture.store))
    fixture.store.upsert(makeTextItem("Compact second", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugVisibleCardCount, 2)
    XCTAssertEqual(fixture.view.debugCardSizes.count, 2)
    XCTAssertEqual(fixture.view.debugCardPresentations, ["vertical-row", "vertical-row"])
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes.first?.width ?? 0, 280)
    XCTAssertLessThanOrEqual(
      fixture.view.debugCardSizes.first?.width ?? 0,
      fixture.view.debugCardRailVisibleRect.width
    )
    XCTAssertEqual(fixture.view.debugCardSizes.first?.height ?? 0, 56, accuracy: 0.5)
    XCTAssertEqual(
      fixture.view.debugCardSizes.last?.width ?? 0,
      fixture.view.debugCardSizes.first?.width ?? 0,
      accuracy: 0.5
    )
    XCTAssertEqual(fixture.view.debugCardSizes.last?.height ?? 0, 56, accuracy: 0.5)
    XCTAssertLessThanOrEqual(
      fixture.view.debugDocumentViewFrame.width,
      fixture.view.debugCardRailVisibleRect.width + 1
    )
  }

  func testCompactRowsShowCharacterMetricWithoutEllipsisOrOverflow() throws {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 520), display: true)
    fixture.store.upsert(makeTextItem(String(repeating: "a", count: 1_234), store: fixture.store))
    fixture.store.upsert(makeTextItem("Newest expanded row", store: fixture.store))
    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(2), ["vertical-row", "vertical-row"])
    let metricIndex = try XCTUnwrap(fixture.view.debugCardCompactMetricTexts.firstIndex(of: "1.2k chars"))
    XCTAssertEqual(fixture.view.debugCardPresentations[metricIndex], "vertical-row")
    XCTAssertFalse(fixture.view.debugCardCompactMetricHiddenStates[metricIndex])
    assertCompactMetricFitsWithoutEllipsisOrOverflow(in: fixture, at: metricIndex)
  }

  func testCompactRowsShowFileSizeMetricWhenBackingFileExists() throws {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 520), display: true)
    let fileURL = makeTempDirectory().appendingPathComponent("payload.bin")
    try Data(repeating: 0x7A, count: 2_048).write(to: fileURL)
    fixture.store.upsert(makeItem(kind: .file, displayText: "payload.bin", payload: fileURL.path, store: fixture.store))
    fixture.store.upsert(makeTextItem("Newest expanded row", store: fixture.store))
    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(2), ["vertical-row", "vertical-row"])
    let metricIndex = try XCTUnwrap(fixture.view.debugCardCompactMetricTexts.firstIndex(of: "2 KB"))
    XCTAssertEqual(fixture.view.debugCardPresentations[metricIndex], "vertical-row")
    XCTAssertFalse(fixture.view.debugCardCompactMetricHiddenStates[metricIndex])
    assertCompactMetricFitsWithoutEllipsisOrOverflow(in: fixture, at: metricIndex)
  }

  func testCompactModeToggleIsRemovedAndSideShelfStaysCompact() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Wide shelf compact mode", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCompactModeButtonAccessibilityValue, "")
    XCTAssertEqual(fixture.view.debugCardPresentations, ["vertical-row"])
    XCTAssertEqual(fixture.view.debugCardSizes.first?.width ?? 0, 264, accuracy: 0.5)

    fixture.view.debugToggleCompactMode()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.settings.compactMode)
    XCTAssertEqual(fixture.view.debugStatusText, "Compact Mode was removed")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")
    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCompactModeButtonAccessibilityValue, "")
    XCTAssertEqual(fixture.view.debugCardPresentations, ["vertical-row"])
    XCTAssertEqual(fixture.view.debugCardSizes.first?.width ?? 0, 264, accuracy: 0.5)
  }

  func testTallSideShelfUsesPasteStyleFocusedCard() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 640), display: true)
    fixture.store.upsert(makeTextItem("Expanded shelf preview", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCardPresentations, ["vertical-row"])
    XCTAssertLessThanOrEqual(
      fixture.view.debugCardSizes.first?.width ?? 0,
      fixture.view.debugCardRailVisibleRect.width
    )
    XCTAssertEqual(fixture.view.debugCardSizes.first?.height ?? 0, 56, accuracy: 0.5)
    XCTAssertGreaterThanOrEqual(fixture.view.debugDocumentViewFrame.height, 72)
  }

  func testVerticalPanelLayoutStacksCardsAndScrollsVertically() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 520, height: 900), display: true)
    for index in 0..<12 {
      fixture.store.upsert(makeTextItem("Vertical shelf clip \(index)", store: fixture.store))
    }
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugPanelLayout, ClipboardPanelLayout.vertical.title)
    XCTAssertEqual(fixture.view.debugItemsStackOrientation, .vertical)
    XCTAssertTrue(fixture.view.debugResizeHandleIsHidden)
    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertGreaterThan(fixture.view.debugDocumentViewFrame.height, fixture.view.debugCardRailVisibleRect.height)
    XCTAssertLessThanOrEqual(fixture.view.debugDocumentViewFrame.width, fixture.view.debugCardRailVisibleRect.width + 1)
  }

  func testVerticalShelfSwitchesFromWidePanelWithoutKeepingWideCategoryRail() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Vertical switch note", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com/vertical", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .image, text: "vertical-image", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugPanelLayout, ClipboardPanelLayout.vertical.title)
    XCTAssertEqual(fixture.view.bounds.width, 336, accuracy: 1)
    XCTAssertEqual(fixture.view.debugCollectionRailVisibleWidth, 36, accuracy: 0.5)
    XCTAssertLessThanOrEqual(fixture.view.debugCardSizes.first?.width ?? 0, 280)
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

  func testCardFooterHidesMissingSourceInsteadOfShowingUnknown() {
    let fixture = makePanelFixture()
    var item = makeTextItem("No source noise", store: fixture.store)
    item.sourceApp = nil

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFirstCardFooterSourceIsHidden)
    XCTAssertEqual(fixture.view.debugFirstCardFooterSourceText, "")
    XCTAssertEqual(fixture.view.debugFirstCardFooterDetailText, "15 characters")
  }

  func testCardFooterShowsSourceAndUsageWhenUsed() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Frequently pasted", store: fixture.store)
    item.useCount = 3

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugFirstCardFooterSourceIsHidden)
    XCTAssertEqual(fixture.view.debugFirstCardFooterSourceText, "Ghostty - Used 3 times")
  }

  func testCardFooterShowsRemoteDeviceContextWhenAvailable() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Copied on another Mac", store: fixture.store)
    item.sourceApp = "Safari"
    item.sourceDeviceName = "Studio Mac"
    item.useCount = 1

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugFirstCardFooterSourceIsHidden)
    XCTAssertEqual(fixture.view.debugFirstCardFooterSourceText, "Safari on Studio Mac - Used once")
  }

  func testCardFooterShowsRemoteDeviceWithoutSourceApp() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Device-only clip", store: fixture.store)
    item.sourceApp = nil
    item.sourceDeviceName = "MacBook Pro"

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugFirstCardFooterSourceIsHidden)
    XCTAssertEqual(fixture.view.debugFirstCardFooterSourceText, "MacBook Pro")
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

  func testValidationStatusMessagesUseWarningTone() {
    let fixture = makePanelFixture()

    fixture.viewModel.addVisibleItemsToStack()
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "No visible clips to stack")
    XCTAssertEqual(fixture.view.debugStatusTone, "warning")

    fixture.viewModel.createTextClip("   ")
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "Text clip cannot be empty")
    XCTAssertEqual(fixture.view.debugStatusTone, "warning")

    fixture.store.upsert(makeTextItem("Stack warning note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.addSelectedItemsToStack()
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "Added 1 selected clip to Stack")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")

    fixture.viewModel.addSelectedItemsToStack()
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugStatusText, "Selected clips are already in Stack")
    XCTAssertEqual(fixture.view.debugStatusTone, "warning")
  }

  func testPanelShellUsesTransparentLiquidGlassSurface() {
    let (_, view) = makePanelWithPanelView()
    drainMainQueue()
    view.layoutSubtreeIfNeeded()

    XCTAssertEqual(view.debugPanelMaterial, .hudWindow)
    XCTAssertEqual(view.debugPanelCornerRadius, 22)
    XCTAssertGreaterThan(view.debugPanelSurfaceAlpha, 0.10)
    XCTAssertLessThan(view.debugPanelSurfaceAlpha, 0.25)
    XCTAssertGreaterThan(view.debugPanelBorderAlpha, 0.30)
  }

  func testWritesPasteStyleVisualSnapshotWhenRequested() throws {
    guard ProcessInfo.processInfo.environment["CLIPBORED_WRITE_VISUAL_SNAPSHOT"] == "1" else {
      throw XCTSkip("Set CLIPBORED_WRITE_VISUAL_SNAPSHOT=1 to write a visual panel snapshot.")
    }

    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)

    var code = makeItem(
      kind: .code,
      displayText: "Swift Formatter",
      payload: "func paste(_ item: ClipboardItem) {\n  clipboard.write(item)\n}",
      store: fixture.store
    )
    code.sourceApp = "Xcode"
    var color = makeItem(kind: .color, displayText: "#0A84FF", payload: "#0A84FF", store: fixture.store)
    color.sourceApp = "Sketch"
    var audio = makeItem(kind: .audio, displayText: "Tame Impala", payload: "/tmp/tame-impala.sound", store: fixture.store)
    audio.sourceApp = "Music"
    let image = makeCachedImageItem(store: fixture.store, cacheService: fixture.cacheService)
    var text = makeTextItem("Address:\n399 The Embarcadero\nSan Francisco, CA 94105\nUnited States", store: fixture.store)
    text.sourceApp = "Mail"
    let linkID = UUID()
    let linkPaths = try XCTUnwrap(fixture.cacheService.cacheImage(sampleImage(), id: linkID))
    let link = ClipboardItem(
      id: linkID,
      kind: .url,
      displayText: "OMA's office furniture line",
      payload: "https://kvellhome.com/lookbook",
      payloadHash: fixture.store.hashString("https://kvellhome.com/lookbook"),
      createdAt: Date(timeIntervalSinceNow: -180),
      lastUsedAt: Date(timeIntervalSinceNow: -180),
      useCount: 0,
      sourceApp: "Safari",
      imagePath: linkPaths.full,
      thumbnailPath: linkPaths.thumb
    )

    for item in [code, color, audio, image, text, link].reversed() {
      fixture.store.upsert(item)
    }
    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.view.displayIfNeeded()

    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLIPBORED_VISUAL_SNAPSHOT_PATH"] ?? "build/visual-snapshots/paste-style-panel.png")
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writeSnapshot(of: fixture.view, to: output)
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

  func testFocusedCardKeepsKeyboardFocusWhenVisibleItemsReloadAboveIt() {
    let fixture = makePanelFixture()
    var existing = makeTextItem("Keep keyboard focus", store: fixture.store)
    existing.createdAt = Date(timeIntervalSince1970: 100)
    existing.lastUsedAt = existing.createdAt
    fixture.store.upsert(existing)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [0])
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Keep keyboard focus")

    var newer = makeTextItem("Newer clip above focus", store: fixture.store)
    newer.createdAt = Date(timeIntervalSince1970: 200)
    newer.lastUsedAt = newer.createdAt
    fixture.store.upsert(newer)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Newer clip above focus", "Keep keyboard focus"])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugActiveCardIndexes, [1])
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Keep keyboard focus")
  }

  func testHoveringAnotherCardBecomesLatestSingleSelectionForArrowNavigation() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Oldest hover note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Middle hover note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Newest hover note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Newest hover note")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [0])

    fixture.viewModel.selectAllVisibleItems()
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0, 1, 2])

    fixture.view.debugHoverCard(at: 2)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Oldest hover note")
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugActiveCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-row", "vertical-focus"])
    XCTAssertEqual(fixture.view.debugCardSelectionInputSource, "mouse")
    XCTAssertEqual(fixture.view.debugCardVisibleActionLabels(at: 2), [])

    fixture.view.debugPressFocusedResponderKeyCode(123)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Middle hover note")
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugActiveCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [])
    XCTAssertEqual(fixture.view.debugCardPresentations.prefix(3), ["vertical-row", "vertical-focus", "vertical-row"])
    XCTAssertEqual(fixture.view.debugCardSelectionInputSource, "keyboard")
    XCTAssertEqual(fixture.view.debugCardVisibleActionLabels(at: 2), [])

    fixture.view.debugRefreshHoverCardWithoutMouseMovement(at: 2)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Middle hover note")
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [])
    XCTAssertEqual(fixture.view.debugCardSelectionInputSource, "keyboard")

    fixture.view.debugHoverCard(at: 2)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Oldest hover note")
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugHoveredCardIndexes, [2])
    XCTAssertEqual(fixture.view.debugCardSelectionInputSource, "mouse")
  }

  func testCollectionRailUsesIconOnlySideItemsAndTracksSelection() {
    let fixture = makePanelFixture()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCollectionTitles, ["Clipboard"])
    XCTAssertEqual(fixture.view.debugCollectionLeadingSymbols, ["doc.on.clipboard"])
    XCTAssertEqual(fixture.view.debugCollectionChipWidths.count, 1)
    XCTAssertEqual(fixture.view.debugCollectionChipWidths.first ?? 0, 34, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCollectionChipLabelHiddenStates, [true])
    XCTAssertEqual(fixture.view.debugCollectionChipCountLabelHiddenStates, [true])
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")

    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCollectionTitles, ["Clipboard", "Frequent", "Links"])
    XCTAssertEqual(fixture.view.debugCollectionChipLabelHiddenStates, [true, true, true])
    XCTAssertEqual(fixture.view.debugCollectionChipCountLabelHiddenStates, [true, true, true])
    XCTAssertEqual(fixture.view.debugCategoryMenuTitles, [])

    fixture.view.debugMouseDownCollectionChip(.links)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Links")
  }

  func testMouseSelectingCollectionChipMovesFocusAndLeavesSingleSelection() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostRecent))
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Clipboard"])
    XCTAssertEqual(fixture.view.debugSelectedSortCollectionTitles, ["Clipboard"])

    fixture.view.debugMouseDownCollectionChip(.links)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Links")
    XCTAssertEqual(fixture.view.debugSelectedSortCollectionTitles, ["Links"])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Links"])
  }

  func testCommandClickingCategoryChipsCombinesFilters() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Text category note", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com/category", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .image, text: "image payload", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugCommandMouseDownCollectionChip(.text)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedSortCollectionTitles, ["Text"])
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Text category note"])

    fixture.view.debugCommandMouseDownCollectionChip(.links)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedSortCollectionTitles, ["Text", "Links"])
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["https://example.com/category", "Text category note"])
  }

  func testCollectionRailChipsAreKeyboardFocusableAndVoiceOverDescriptive() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugCollectionChipAcceptsFirstResponder,
      Array(repeating: true, count: fixture.view.debugCollectionTitles.count)
    )
    XCTAssertEqual(
      fixture.view.debugCollectionCountLabelHiddenStates,
      Array(repeating: true, count: fixture.view.debugCollectionTitles.count)
    )
    XCTAssertEqual(fixture.view.debugCollectionChipAccessibilityLabels.first, "Clipboard, selected, 1 clip")
    XCTAssertEqual(
      fixture.view.debugCollectionChipAccessibilityHelps.first,
      "Press Return or Space to show Clipboard. Use Up/Down to move between categories, Left/Right to move between clips, and Home/End to move between categories."
    )

    XCTAssertEqual(fixture.view.debugCategoryMenuTitles, [])
    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostUsed))
    fixture.view.debugPressFocusedResponderWithSpace()
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Frequent")
    XCTAssertTrue(fixture.view.debugCollectionChipAccessibilityLabels.contains("Frequent, selected, 1 clip"))
    XCTAssertTrue(
      fixture.view.debugCollectionChipAccessibilityHelps.contains(
        "Press Return or Space to show Frequent. Use Up/Down to move between categories, Left/Right to move between clips, and Home/End to move between categories."
      )
    )

    fixture.view.debugMouseDownCollectionChip(.links)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Links")
  }

  func testCollectionRailChipArrowsMoveCardSelectionInsteadOfChangingCategories() {
    let fixture = makePanelFixture()
    var clientItem = makeTextItem("Client collection item", store: fixture.store)
    clientItem.collectionName = "Client Work"
    fixture.store.upsert(clientItem)
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com", store: fixture.store))
    fixture.store.upsert(makeItem(kind: .image, text: "image payload", store: fixture.store))
    fixture.store.upsert(makeTextItem("Stack queue item", store: fixture.store))
    drainMainQueue()

    fixture.viewModel.selectItem(at: 0)
    fixture.viewModel.toggleSelectedStackMembership()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostRecent))
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(fixture.viewModel.selectedIndex, 0)

    fixture.view.debugPressFocusedResponderKeyCode(124)
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(fixture.viewModel.selectedIndex, 1)
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, [])

    fixture.view.debugPressFocusedResponderKeyCode(123)
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(fixture.viewModel.selectedIndex, 0)
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0])
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [0])

    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostRecent))
    fixture.view.debugPressFocusedResponderKeyCode(119)
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Stack")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Stack"])

    fixture.view.debugPressFocusedResponderKeyCode(115)
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Clipboard"])
  }

  func testTypingFromFocusedCollectionChipStartsSearch() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Alpha note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Quantum reference", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostRecent))
    fixture.view.debugTypeFocusedResponder("q", keyCode: 12)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "q")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum reference"])
  }

  func testTypingFromFocusedCollectionChipAppendsSearchTokenBoundary() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Alpha note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Quantum reference", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.view.debugSetSearchFieldText("type:text")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostRecent))
    fixture.view.debugTypeFocusedResponder("q", keyCode: 12)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "type:text q")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum reference"])
  }

  func testKeyboardCancelClearsSearchFromFocusedCollectionChip() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Alpha note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Quantum reference", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.view.debugSetSearchFieldText("quantum")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum reference"])
    XCTAssertTrue(fixture.view.debugFocusCollectionChip(.mostRecent))

    XCTAssertTrue(fixture.view.clearSearchForKeyboardCancel())
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum reference", "Alpha note"])
  }

  func testCollectionRailAddButtonCreatesEmptyCollection() {
    let fixture = makePanelFixture()

    XCTAssertTrue(fixture.view.debugCollectionRailContainsAddButton)
    XCTAssertTrue(fixture.view.debugAddCollectionButtonIsEnabled)

    fixture.view.debugSetCollectionNameProvider { "  Research   Stack  " }
    fixture.view.debugPressAddCollectionButton()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Created Research Stack")
    XCTAssertEqual(fixture.view.debugCustomCollectionTitles, ["Research Stack"])
    XCTAssertEqual(fixture.view.debugCustomCollectionCounts, [0])
    XCTAssertEqual(fixture.view.debugCustomCollectionCountLabelHiddenStates, [true])
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Research Stack")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Research Stack"])
    XCTAssertEqual(fixture.view.debugVisibleCardCount, 0)
    XCTAssertEqual(fixture.view.debugEmptyStateText?.title, "No clips in Research Stack")
    XCTAssertEqual(fixture.view.debugEmptyStateText?.detail, "Drag clips here or use Collect to add them.")
  }

  func testToolbarDoesNotExposeNewTextClipControl() {
    let fixture = makePanelFixture()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugToolbarButtonAccessibilityLabels.contains("New text clip"))
    XCTAssertEqual(fixture.view.debugToolbarButtonAccessibilityLabels, ["Clear History", "Settings"])
  }

  func testClearHistoryMenuClearsRecentRangesAndAllTime() {
    let fixture = makePanelFixture()
    var older = makeTextItem("Older than a day", store: fixture.store)
    older.createdAt = Date().addingTimeInterval(-90_000)
    older.lastUsedAt = older.createdAt
    var recent = makeTextItem("Recent clip", store: fixture.store)
    recent.createdAt = Date().addingTimeInterval(-3_600)
    recent.lastUsedAt = recent.createdAt
    fixture.store.upsert(older)
    fixture.store.upsert(recent)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugClearHistoryMenuTitles, ["Past Hour", "Past Day", "All Time"])

    fixture.view.debugPerformClearHistoryMenuItem(titled: "Past Day")
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Older than a day"])
    XCTAssertEqual(fixture.view.debugStatusText, "Cleared 1 clip")

    fixture.view.debugPerformClearHistoryMenuItem(titled: "All Time")
    drainMainQueue()

    XCTAssertTrue(fixture.viewModel.visibleItems.isEmpty)
    XCTAssertEqual(fixture.view.debugStatusText, "Cleared 1 clip")
  }

  func testCollectionFilteredCardsUseStoredCollectionHeaderColor() {
    let fixture = makePanelFixture()
    fixture.viewModel.createCollection(named: "Research Stack", colorHex: "#0A9EB8")
    var item = makeTextItem("Collect this note", store: fixture.store)
    item.collectionName = "Research Stack"
    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Collect this note"])
    XCTAssertEqual(fixture.view.debugFirstCardHeaderTitle, "Research Stack")
    XCTAssertEqual(fixture.view.debugFirstCardHeaderSubtitle, "Text - Just now")
    XCTAssertEqual(fixture.view.debugFirstCardHeaderColorHex, "#0A9EB8")
    XCTAssertEqual(fixture.view.debugCustomCollectionColorHexes["Research Stack"], "#0A9EB8")
    XCTAssertEqual(fixture.view.debugFirstCardFooterDetailText, "17 characters")
  }

  func testCardHeaderUsesPasteStyleRelativeAgeText() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Readable age", store: fixture.store)
    item.createdAt = Date().addingTimeInterval(-3 * 60)

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugFirstCardHeaderTitle, "Text")
    XCTAssertEqual(fixture.view.debugFirstCardHeaderSubtitle, "3 minutes ago")

    fixture.viewModel.createCollection(named: "Age Stack", colorHex: "#FF3B30", selectAfterCreate: false)
    fixture.viewModel.assignSelected(to: "Age Stack")
    fixture.viewModel.selectCollection(named: "Age Stack")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugFirstCardHeaderSubtitle, "Text - 3 minutes ago")
  }

  func testCollectionChipsExposeManagementMenuActions() {
    let fixture = makePanelFixture()
    fixture.viewModel.createCollection(named: "Research Stack", colorHex: "#0A9EB8")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugCustomCollectionMenuTitles(named: "Research Stack"),
      ["Edit Collection...", "Export Pinboard...", "-", "Delete Collection"]
    )
    XCTAssertEqual(
      fixture.view.debugCustomCollectionAccessibilityHelp(named: "Research Stack"),
      "Press Return or Space to show Research Stack. Use Up/Down to move between categories, Left/Right to move between clips, and Home/End to move between categories. Open the context menu to edit, export, or delete this Pinboard."
    )
  }

  func testCollectionChipManagementRenamesAndDeletesCollections() {
    let fixture = makePanelFixture()
    fixture.viewModel.createCollection(named: "Research Stack", colorHex: "#0A9EB8")
    var item = makeTextItem("Collect this note", store: fixture.store)
    item.collectionName = "Research Stack"
    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCustomCollectionChip(named: "Research Stack"))
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Research Stack"])

    fixture.view.debugEditCollection(named: "Research Stack", to: "Product Research", colorHex: "#3366FF")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCustomCollectionTitles, ["Product Research"])
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Product Research")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Product Research"])
    XCTAssertEqual(fixture.view.debugFirstCardHeaderTitle, "Product Research")
    XCTAssertEqual(fixture.view.debugFirstCardHeaderColorHex, "#3366FF")

    fixture.view.debugDeleteCollection(named: "Product Research")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCustomCollectionTitles, [])
    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Clipboard")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCollectionTitles, ["Clipboard"])
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), [])
    XCTAssertEqual(fixture.store.items.map(\.payload), [])
  }

  func testSelectedCardActionsRespectSelectedKind() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Plain text", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionRailWidth, 0)
    XCTAssertFalse(fixture.view.debugFirstCardFooterDetailIsHidden)
    XCTAssertFalse(fixture.view.debugFirstCardHeaderBadgeIsHidden)
    XCTAssertEqual(fixture.view.debugCardPresentations, ["vertical-focus"])
    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Edit", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )

    fixture.store.upsert(makeItem(kind: .file, text: "/tmp/report.txt", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.selectFirstItem()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.visibleItems.first?.kind, .file)
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionRailWidth, 0)
    XCTAssertFalse(fixture.view.debugFirstCardFooterDetailIsHidden)
    XCTAssertFalse(fixture.view.debugFirstCardHeaderBadgeIsHidden)
    XCTAssertEqual(fixture.view.debugCardPresentations.first, "vertical-focus")
    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Paste Plain Text", "Copy Plain Text", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
  }

  func testLargeCollectionReloadKeepsHiddenCardActionsLazy() {
    let fixture = makePanelFixture()
    fixture.settings.maxHistoryItems = 60
    fixture.settings.ensureCollection(named: "Client Work")

    fixture.view.beginOpeningTransition()
    for index in 0..<30 {
      var item = makeTextItem("Client clip \(index)", store: fixture.store)
      item.collectionName = "Client Work"
      fixture.store.upsert(item)
    }
    drainMainQueue()
    fixture.view.finishOpeningTransition()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardItemCount, 30)
    XCTAssertLessThan(fixture.view.debugCardSlotCount, 30)
    XCTAssertGreaterThan(fixture.view.debugCardSlotCount, 0)
    XCTAssertLessThan(fixture.view.debugVisibleCardCount, 30)
    XCTAssertGreaterThan(fixture.view.debugVisibleCardCount, 0)
    XCTAssertEqual(fixture.view.debugConstructedActionButtonCount, 0)

    fixture.viewModel.selectCollection(named: "Client Work")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.count, 30)
    XCTAssertEqual(fixture.view.debugCardItemCount, 30)
    XCTAssertLessThan(fixture.view.debugCardSlotCount, 30)
    XCTAssertGreaterThan(fixture.view.debugCardSlotCount, 0)
    XCTAssertLessThan(fixture.view.debugVisibleCardCount, 30)
    XCTAssertGreaterThan(fixture.view.debugVisibleCardCount, 0)
    XCTAssertLessThan(fixture.view.debugLastSynchronousCardRenderCount, 30)
    XCTAssertGreaterThan(fixture.view.debugLastSynchronousCardRenderCount, 0)
    XCTAssertEqual(fixture.view.debugConstructedActionButtonCount, 0)
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])

    fixture.view.debugScrollCardRailVertically(deltaY: -10_000)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertGreaterThan(fixture.view.debugCardRailVisibleRect.minY, 0)
    XCTAssertEqual(fixture.view.debugCardItemCount, 30)
    XCTAssertLessThan(fixture.view.debugCardSlotCount, 30)
    XCTAssertLessThan(fixture.view.debugVisibleCardCount, 30)

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertEqual(fixture.view.debugConstructedActionButtonCount, 0)
  }

  func testCompactFileCardActionsFitInsideShelfWithOverflowMenu() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
    fixture.store.upsert(makeItem(kind: .file, text: "/tmp/report.txt", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    RunLoop.main.run(until: Date().addingTimeInterval(fixture.view.debugCardExpansionAnimationDuration + 0.04))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionRailWidth, 0)
    XCTAssertEqual(fixture.view.debugCardPresentations, ["vertical-focus"])
    XCTAssertFalse(fixture.view.debugFirstCardHeaderBadgeIsHidden)
    XCTAssertEqual(fixture.view.debugCardSizes.first?.width ?? 0, 264, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCardSizes.first?.height ?? 0, 220, accuracy: 0.5)
    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Paste Plain Text", "Copy Plain Text", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
  }

  func testCardsAreKeyboardFocusableAndReturnPastesFocusedCard() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Older text card", store: fixture.store))
    fixture.store.upsert(makeTextItem("Newest text card", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAcceptsFirstResponder, [true, true])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 1))
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Older text card")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])
    XCTAssertEqual(fixture.view.debugCardBorderWidths[1], 0.8, accuracy: 0.01)
    XCTAssertEqual(fixture.view.debugCardAccessibilityValues[1], "Selected")
    XCTAssertEqual(fixture.view.debugCardAccessibilityHelps[1], "Press Return to paste. Space opens Quick Look. Command-R renames; Command-E edits text. Delete removes selected clips; Command-Z restores them.")

    fixture.view.debugPressFocusedResponderWithReturn()
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Copied")
  }

  func testFocusedCardCommandShortcutsOpenRenameAndEditFlows() {
    let fixture = makePanelFixture()
    fixture.view.debugSuppressClipEditDialogs()
    fixture.store.upsert(makeTextItem("Shortcut editable text", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    fixture.view.debugPressFocusedResponderKeyCode(15, modifiers: .command)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugRenameClipRequestCount, 1)
    XCTAssertEqual(fixture.view.debugEditClipRequestCount, 0)
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Shortcut editable text")

    fixture.view.debugPressFocusedResponderKeyCode(14, modifiers: .command)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugRenameClipRequestCount, 1)
    XCTAssertEqual(fixture.view.debugEditClipRequestCount, 1)
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Shortcut editable text")
  }

  func testFocusedNonTextCardIgnoresCommandEditShortcut() {
    let fixture = makePanelFixture()
    fixture.view.debugSuppressClipEditDialogs()
    fixture.store.upsert(makeItem(kind: .file, text: "/tmp/report.txt", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    fixture.view.debugPressFocusedResponderKeyCode(14, modifiers: .command)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugEditClipRequestCount, 0)
    XCTAssertEqual(fixture.view.debugRenameClipRequestCount, 0)
  }

  func testFocusedCardDeleteRemovesSelectionAndCommandZRestoresIt() {
    let fixture = makePanelFixture()
    var oldest = makeTextItem("Oldest focused delete", store: fixture.store)
    oldest.createdAt = Date(timeIntervalSince1970: 100)
    oldest.lastUsedAt = oldest.createdAt
    var middle = makeTextItem("Middle focused delete", store: fixture.store)
    middle.createdAt = Date(timeIntervalSince1970: 200)
    middle.lastUsedAt = middle.createdAt
    var newest = makeTextItem("Newest focused delete", store: fixture.store)
    newest.createdAt = Date(timeIntervalSince1970: 300)
    newest.lastUsedAt = newest.createdAt
    fixture.store.upsert(oldest)
    fixture.store.upsert(middle)
    fixture.store.upsert(newest)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.selectItem(at: 0)
    fixture.viewModel.selectItem(at: 2, mode: .toggle)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0, 2])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    fixture.view.debugPressFocusedResponderKeyCode(51)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Middle focused delete"])
    XCTAssertEqual(fixture.viewModel.statusMessage, "Deleted 2 clips")
    XCTAssertEqual(fixture.view.debugStatusText, "Deleted 2 clips")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0])

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    fixture.view.debugPressFocusedResponderKeyCode(6, modifiers: .command)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.viewModel.visibleItems.map(\.payload),
      ["Newest focused delete", "Middle focused delete", "Oldest focused delete"]
    )
    XCTAssertEqual(fixture.viewModel.statusMessage, "Restored 2 clips")
    XCTAssertEqual(fixture.view.debugStatusText, "Restored 2 clips")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0, 2])
  }

  func testFocusedCardCopyAndPlainTextPasteShortcutsUseSelection() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Focused shortcut payload", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    fixture.view.debugPressFocusedResponderKeyCode(8, modifiers: .command)
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Copied")
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Focused shortcut payload")

    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    fixture.view.debugPressFocusedResponderKeyCode(36, modifiers: .shift)
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Copied Plain Text")

    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    fixture.view.debugPressFocusedResponderKeyCode(9, modifiers: [.command, .shift])
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.statusMessage, "Copied Plain Text")
  }

  func testFocusedCardCommandPreviewOpenAndShowInClipboardShortcuts() {
    let fixture = makePanelFixture()
    fixture.view.debugSuppressClipOpenActions()
    let url = makeItem(kind: .url, displayText: "Release notes", payload: "https://example.com/releases", store: fixture.store)
    var note = makeTextItem("Filtered release note", store: fixture.store)
    note.createdAt = Date(timeIntervalSince1970: 100)
    note.lastUsedAt = note.createdAt
    fixture.store.upsert(note)
    fixture.store.upsert(url)
    fixture.view.debugSetSearchFieldText("release")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["https://example.com/releases", "Filtered release note"])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    fixture.view.debugPressFocusedResponderKeyCode(16, modifiers: .command)
    drainMainQueue()

    XCTAssertEqual(fixture.previewProbe.requestCount, 1)

    fixture.view.debugPressFocusedResponderKeyCode(31, modifiers: .command)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugOpenClipRequestCount, 1)
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "https://example.com/releases")

    fixture.view.debugPressFocusedResponderKeyCode(5, modifiers: .command)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugShowInClipboardRequestCount, 1)
    XCTAssertEqual(fixture.viewModel.statusMessage, "Showing in Clipboard")
    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "https://example.com/releases")
  }

  func testFocusedTextCardSpaceOpensQuickLookInsteadOfPasting() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Preview this text without pasting", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()

    fixture.view.debugPressFocusedResponderWithSpace()
    drainMainQueue()

    XCTAssertEqual(fixture.previewProbe.requestCount, 1)
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Preview this text without pasting")
    XCTAssertEqual(fixture.viewModel.statusMessage, "")
  }

  func testTypingFromFocusedCardStartsSearch() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Alpha note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Quantum card", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    fixture.view.debugTypeFocusedResponder("q", keyCode: 12)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "q")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum card"])
  }

  func testTypingFromFocusedCardAppendsSearchTokenBoundary() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Alpha note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Quantum card", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.view.debugSetSearchFieldText("type:text")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    fixture.view.debugTypeFocusedResponder("q", keyCode: 12)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "type:text q")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum card"])
  }

  func testKeyboardCancelClearsSearchFromFocusedCard() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Alpha note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Quantum card", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.view.debugSetSearchFieldText("quantum")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum card"])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    XCTAssertTrue(fixture.view.clearSearchForKeyboardCancel())
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Quantum card", "Alpha note"])
    XCTAssertFalse(fixture.view.clearSearchForKeyboardCancel())
  }

  func testKeyboardCancelClearsWhitespaceOnlySearchBeforeClosing() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Whitespace search note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("   ")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "   ")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Whitespace search note"])

    XCTAssertTrue(fixture.view.clearSearchForKeyboardCancel())
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.isSearchFieldEditing)
    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Whitespace search note"])
    XCTAssertFalse(fixture.view.clearSearchForKeyboardCancel())
  }

  func testFocusedPreviewableCardSpaceOpensQuickLook() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeItem(kind: .url, text: "https://example.com/read", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugCardAccessibilityHelps.first, "Press Return to paste. Space opens Quick Look. Command-R renames; Command-E edits text. Delete removes selected clips; Command-Z restores them.")

    fixture.view.debugPressFocusedResponderWithSpace()
    drainMainQueue()

    XCTAssertEqual(fixture.previewProbe.requestCount, 1)
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "https://example.com/read")
  }

  func testFocusedCardsSupportShelfNavigationKeys() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 760), display: true)

    for index in 0..<8 {
      fixture.store.upsert(makeTextItem("Keyboard navigation item \(index)", store: fixture.store))
      drainMainQueue()
    }
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.viewModel.selectFirstItem()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let pageStep = fixture.view.debugVisibleCardPageStep
    XCTAssertGreaterThan(pageStep, 1)
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))

    fixture.view.debugPressFocusedResponderKeyCode(124)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, 1)
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])

    fixture.view.debugPressFocusedResponderKeyCode(121)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, min(7, 1 + pageStep))
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [fixture.viewModel.selectedIndex])

    fixture.view.debugPressFocusedResponderKeyCode(119)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, 7)
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [7])

    fixture.view.debugPressFocusedResponderKeyCode(116)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, max(0, 7 - pageStep))
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [fixture.viewModel.selectedIndex])

    fixture.view.debugPressFocusedResponderKeyCode(115)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, 0)
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [0])

    fixture.view.debugPressFocusedResponderKeyCode(123)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, 0)
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [0])

    fixture.view.debugPressFocusedResponderKeyCode(124, modifiers: .shift)
    drainMainQueue()
    XCTAssertEqual(fixture.viewModel.selectedIndex, 1)
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0, 1])
    XCTAssertEqual(fixture.view.debugActiveCardIndexes, [1])

    fixture.view.debugPressFocusedResponderKeyCode(0, modifiers: .command)
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, Array(0..<8))
    XCTAssertEqual(fixture.view.debugResultCountText, "8 selected of 8 clips")
    XCTAssertEqual(fixture.view.debugKeyboardFocusedCardIndexes, [1])
  }

  func testCardHeaderUsesKindSymbolBadgeWhenSourceIconIsUnavailable() {
    let fixture = makePanelFixture()
    var item = makeItem(kind: .url, text: "https://example.com", store: fixture.store)
    item.sourceApp = nil
    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardHeaderBadgeSymbols, ["link"])
    XCTAssertEqual(fixture.view.debugCardHeaderBadgeTexts, [""])
    XCTAssertTrue(fixture.view.debugFirstCardHeaderMaskedCorners.contains(.layerMinXMaxYCorner))
    XCTAssertTrue(fixture.view.debugFirstCardHeaderMaskedCorners.contains(.layerMaxXMaxYCorner))
    XCTAssertFalse(fixture.view.debugFirstCardHeaderMaskedCorners.contains(.layerMinXMinYCorner))
    XCTAssertFalse(fixture.view.debugFirstCardHeaderMaskedCorners.contains(.layerMaxXMinYCorner))
    XCTAssertTrue(fixture.view.debugFirstCardHeaderBadgeMaskedCorners.contains(.layerMinXMinYCorner))
    XCTAssertTrue(fixture.view.debugFirstCardHeaderBadgeMaskedCorners.contains(.layerMinXMaxYCorner))
    XCTAssertTrue(fixture.view.debugFirstCardHeaderBadgeMaskedCorners.contains(.layerMaxXMaxYCorner))
    XCTAssertFalse(fixture.view.debugFirstCardHeaderBadgeMaskedCorners.contains(.layerMaxXMinYCorner))
    XCTAssertGreaterThanOrEqual(
      fixture.view.debugFirstCardHeaderBadgeContentFrame.width,
      fixture.view.debugFirstCardHeaderBadgeFrame.width * 0.70
    )
  }

  func testCardHeaderSourceAppIconFillsBadgeTile() throws {
    let fixture = makePanelFixture()
    var item = makeTextItem("Copied from Finder", store: fixture.store)
    item.sourceApp = "Finder"
    item.sourceAppBundleId = "com.apple.finder"
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") != nil else {
      throw XCTSkip("Finder app icon is unavailable in this environment.")
    }

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let badgeFrame = fixture.view.debugFirstCardHeaderBadgeFrame
    let contentFrame = fixture.view.debugFirstCardHeaderBadgeContentFrame
    XCTAssertEqual(fixture.view.debugCardHeaderBadgeTexts, [""])
    XCTAssertLessThan(contentFrame.minX, badgeFrame.minX)
    XCTAssertLessThan(contentFrame.minY, badgeFrame.minY)
    XCTAssertGreaterThan(contentFrame.maxX, badgeFrame.maxX)
    XCTAssertGreaterThan(contentFrame.maxY, badgeFrame.maxY)
    XCTAssertEqual(contentFrame.midX, badgeFrame.midX, accuracy: 0.5)
    XCTAssertEqual(contentFrame.midY, badgeFrame.midY, accuracy: 0.5)
  }

  func testCardHeaderUsesSourceMonogramWhenAppIconIsUnavailable() {
    let fixture = makePanelFixture()
    var item = makeTextItem("Copied from a named app", store: fixture.store)
    item.sourceApp = "Arc Browser"

    fixture.store.upsert(item)
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugCardHeaderBadgeTexts, ["AB"])
  }

  func testCollectionRailShowsLiveCounts() {
    let fixture = makePanelFixture()
    var pinned = makeTextItem("Pinned note", store: fixture.store)
    pinned.isPinned = true
    let rich = makeItem(kind: .richText, text: "Rich note", store: fixture.store)
    let link = makeItem(kind: .url, text: "https://example.com/releases", store: fixture.store)
    let image = makeItem(kind: .image, text: "image payload", store: fixture.store)
    let color = makeItem(kind: .color, displayText: "#0A84FF", payload: "#0A84FF", store: fixture.store)
    let audio = makeItem(kind: .audio, text: "audio payload", store: fixture.store)
    let video = makeItem(kind: .video, text: "/tmp/movie.mp4", store: fixture.store)
    let file = makeItem(kind: .file, text: "/tmp/report.pdf", store: fixture.store)
    let code = makeItem(
      kind: .code,
      displayText: "Swift Snippet",
      payload: "func greet(name: String) -> String {\n  return \"Hi \\(name)\"\n}",
      store: fixture.store
    )

    [pinned, rich, link, image, color, audio, video, file, code].forEach {
      fixture.store.upsert($0)
      drainMainQueue()
    }

    XCTAssertEqual(fixture.viewModel.visibleItems.count, 9)
    XCTAssertEqual(ClipboardSortMode.allCases.map { fixture.viewModel.collectionCount(for: $0) }, [9, 9, 3, 1, 1, 1, 1, 1, 1, 1, 1])
    let countSummary = fixture.viewModel.collectionCountSummary()
    XCTAssertEqual(ClipboardSortMode.allCases.map { countSummary.count(for: $0) }, [9, 9, 3, 1, 1, 1, 1, 1, 1, 1, 1])
    XCTAssertEqual(fixture.view.debugCollectionCounts, [9, 9, 3, 1, 1, 1, 1, 1, 1, 1, 1])
    XCTAssertEqual(fixture.view.debugCollectionCountLabelHiddenStates, Array(repeating: true, count: 11))
    XCTAssertEqual(fixture.view.debugCategoryMenuTitles, [])
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
    XCTAssertEqual(fixture.view.debugCustomCollectionCountLabelHiddenStates, [true, true, true])
    let countSummary = fixture.viewModel.collectionCountSummary()
    XCTAssertEqual(["Useful Links", "Important Notes", "Client Work"].map { countSummary.count(named: $0) }, [1, 1, 1])

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
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
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

    XCTAssertEqual(fixture.view.debugCollectionRailVisibleWidth, 36, accuracy: 0.5)
    XCTAssertFalse(fixture.view.debugCollectionRailHasHorizontalScroller)
    XCTAssertGreaterThan(fixture.view.debugCollectionRailHeight, 300)
    XCTAssertGreaterThan(
      fixture.view.debugCollectionRailVisibleRect.height,
      1
    )
    XCTAssertTrue(fixture.view.debugCustomCollectionTitles.contains("Client Work"))
    XCTAssertTrue(fixture.view.debugCustomCollectionTitles.contains("Product References"))

    XCTAssertEqual(fixture.view.debugCollectionRailVisibleRect.minY, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCollectionRailOverflowFadeWidth, 44, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCollectionRailOverflowFadeVisibility, [false, false])
    fixture.view.debugScrollCollectionRailVertically(deltaY: -220)
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertGreaterThanOrEqual(fixture.view.debugCollectionRailVisibleRect.minY, 0)
    XCTAssertEqual(fixture.view.debugCollectionRailOverflowFadeVisibility, [false, false])

    fixture.view.debugScrollCollectionRailVertically(deltaY: 10_000)
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCollectionRailVisibleRect.minY, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCollectionRailOverflowFadeVisibility, [false, false])
  }

  func testSelectionScrollsCardRailToKeepSelectedCardVisible() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 520), display: true)

    for index in 0..<8 {
      fixture.store.upsert(makeTextItem("Scrollable clipboard item \(index)", store: fixture.store))
      drainMainQueue()
    }
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.selectFirstItem()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(fixture.view.debugCardRailVisibleRect.minY, 1)

    fixture.viewModel.selectItem(at: fixture.viewModel.visibleItems.count - 1)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let visibleRect = fixture.view.debugCardRailVisibleRect
    let selectedFrame = fixture.view.debugSelectedCardFrameInDocument
    XCTAssertGreaterThan(visibleRect.minY, 0)
    XCTAssertLessThanOrEqual(selectedFrame.minY, visibleRect.maxY)
    XCTAssertGreaterThanOrEqual(visibleRect.maxY + 1, selectedFrame.maxY)

    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertLessThanOrEqual(fixture.view.debugCardRailVisibleRect.minY, 1)
  }

  func testVerticalWheelPansSideCardListAndClamps() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 336, height: 520), display: true)

    for index in 0..<8 {
      fixture.store.upsert(makeTextItem("Wheel scroll item \(index)", store: fixture.store))
      drainMainQueue()
    }
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertGreaterThan(
      fixture.view.debugCardRailDocumentHeight,
      fixture.view.debugCardRailVisibleRect.height + 1
    )
    XCTAssertEqual(fixture.view.debugCardRailVisibleRect.minY, 0, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCardRailOverflowFadeWidth, 26, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugCardRailOverflowFadeVisibility, [false, false])

    fixture.view.debugScrollCardRailVertically(deltaY: -60)
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertGreaterThan(fixture.view.debugCardRailVisibleRect.minY, 0)
    XCTAssertEqual(fixture.view.debugCardRailOverflowFadeVisibility, [false, false])

    fixture.view.debugScrollCardRailVertically(deltaY: -10_000)
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    let maxOffset = fixture.view.debugCardRailDocumentHeight - fixture.view.debugCardRailVisibleRect.height
    XCTAssertEqual(fixture.view.debugCardRailVisibleRect.minY, maxOffset, accuracy: 1)
    XCTAssertEqual(fixture.view.debugCardRailOverflowFadeVisibility, [false, false])

    fixture.view.debugScrollCardRailVertically(deltaY: 10_000)
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardRailVisibleRect.minY, 0, accuracy: 1)
    XCTAssertEqual(fixture.view.debugCardRailOverflowFadeVisibility, [false, false])
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

  func testEmptySearchResultsUseSearchSpecificStatusCopy() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Only text exists", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("missing")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugVisibleCardCount, 0)
    XCTAssertEqual(fixture.view.debugEmptyStateText?.title, "No matching clips")
    XCTAssertEqual(fixture.view.debugEmptyStateText?.detail, "Try a broader search or switch filters.")
    XCTAssertEqual(fixture.view.debugResultCountText, "0 clips matching")
    XCTAssertEqual(fixture.view.debugStatusText, "No clips match this search")
    XCTAssertEqual(fixture.view.debugStatusTone, "neutral")
  }

  func testPinnedEmptyStatePointsToPinAction() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Only text exists", store: fixture.store))
    drainMainQueue()

    fixture.viewModel.sortMode = .pinned
    drainMainQueue()

    XCTAssertEqual(fixture.view.debugEmptyStateText?.title, "No pinned clips")
    XCTAssertEqual(fixture.view.debugEmptyStateText?.detail, "Use the Pin action on a card to keep important clips here.")
  }

  func testCardsExposeContextMenuActions() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Context menu text", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Edit", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
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

  func testCaptureRuleActionsUseWarningStatusTone() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Capture rule status tone", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugPerformFirstCardCaptureRuleMenuItem(titled: "Ignore Ghostty")
    drainMainQueue()

    XCTAssertTrue(fixture.settings.ignoredApps.contains("Ghostty"))
    XCTAssertEqual(fixture.view.debugStatusText, "Ignored Ghostty for future captures")
    XCTAssertEqual(fixture.view.debugStatusTone, "warning")

    fixture.view.debugPerformFirstCardCaptureRuleMenuItem(titled: "Ignore Text Items")
    drainMainQueue()

    XCTAssertTrue(fixture.settings.ignoredItemKindsRaw.contains(ClipboardItemKind.text.rawValue))
    XCTAssertEqual(fixture.view.debugStatusText, "Ignored Text items for future captures")
    XCTAssertEqual(fixture.view.debugStatusTone, "warning")
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
      ["Paste", "Copy", "Show in Clipboard", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Edit", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )

    fixture.view.debugShowFirstCardInClipboard()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Meeting note", "Release needle"])
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Release needle")
  }

  func testShowInClipboardCollapsesClearedUISearchFieldWhenIdle() {
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
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("release")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Release needle"])
    XCTAssertEqual(fixture.view.debugSearchFieldText, "release")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugShowFirstCardInClipboard()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Meeting note", "Release needle"])
    XCTAssertEqual(fixture.viewModel.selectedItem?.payload, "Release needle")
  }

  func testModelSideSearchClearSynchronizesSearchFieldPresentation() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Launch note", store: fixture.store))
    fixture.store.upsert(makeTextItem("Meeting note", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.view.debugSetSearchFieldText("launch")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "launch")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Launch note"])

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    fixture.viewModel.clearSearch()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSearchFieldText, "")
    XCTAssertEqual(fixture.view.debugSearchFieldWidth, 30, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugSearchFieldPlaceholderText, "")
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["Meeting note", "Launch note"])
  }

  func testPreviewableCardsExposeQuickLookContextMenuAction() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeItem(kind: .file, text: "/tmp/report.txt", store: fixture.store))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Paste Plain Text", "Copy Plain Text", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
    XCTAssertEqual(
      fixture.view.debugFirstCardCaptureRuleMenuTitles,
      ["Ignore Ghostty", "Ignore File Items"]
    )
  }

  func testImageCardsExposeImageQuickActions() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeCachedImageItem(store: fixture.store, cacheService: fixture.cacheService))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(
      fixture.view.debugFirstCardMenuTitles,
      ["Paste", "Copy", "Paste Plain Text", "Copy Plain Text", "Rename...", "Add to Stack", "Add Visible Clips to Stack", "Rotate Image", "Extract Text", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
  }

  func testMultiSelectedCardsExposeBatchActionsAndSelectionCount() {
    let fixture = makePanelFixture()
    var oldest = makeTextItem("Oldest multi-select note", store: fixture.store)
    oldest.createdAt = Date(timeIntervalSince1970: 100)
    oldest.lastUsedAt = oldest.createdAt
    var middle = makeTextItem("Middle multi-select note", store: fixture.store)
    middle.createdAt = Date(timeIntervalSince1970: 200)
    middle.lastUsedAt = middle.createdAt
    var newest = makeTextItem("Newest multi-select note", store: fixture.store)
    newest.createdAt = Date(timeIntervalSince1970: 300)
    newest.lastUsedAt = newest.createdAt
    fixture.store.upsert(oldest)
    fixture.store.upsert(middle)
    fixture.store.upsert(newest)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.selectItem(at: 0)
    fixture.viewModel.selectItem(at: 2, mode: .toggle)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCardIndexes, [0, 2])
    XCTAssertEqual(fixture.view.debugActiveCardIndexes, [])
    XCTAssertEqual(fixture.view.debugCardAccessibilityValues, ["Selected", "Not selected", "Selected"])
    XCTAssertEqual(fixture.view.debugResultCountText, "2 selected of 3 clips")
    XCTAssertTrue(fixture.view.debugFirstCardMenuTitles.contains("Paste Selection"))
    XCTAssertTrue(fixture.view.debugFirstCardMenuTitles.contains("Copy Selection"))
    XCTAssertTrue(fixture.view.debugFirstCardMenuTitles.contains("Paste Selection as Text"))
    XCTAssertTrue(fixture.view.debugFirstCardMenuTitles.contains("Copy Selection as Text"))
    XCTAssertTrue(fixture.view.debugFirstCardMenuTitles.contains("Add Selection to Stack"))

    fixture.view.debugPerformFirstCardMenuItem(titled: "Add Selection to Stack")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugStatusText, "Added 2 selected clips to Stack")
    XCTAssertEqual(fixture.view.debugStackChipCount, 2)
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
      ["Paste", "Copy", "Rename...", "Remove from Stack", "Add Visible Clips to Stack", "Paste Stack Next", "Copy Stack Next", "Paste Stack as Text", "Copy Stack as Text", "Clear Stack", "Edit", "Quick Look", "Pin", "Add to Collection", "Capture Rules", "-", "Open", "Reveal in Finder", "-", "Delete"]
    )
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertEqual(fixture.view.debugStackCornerLabels, ["Remove from Stack"])
  }

  func testStackCornerButtonTogglesAndPersistsForQueuedCards() {
    let fixture = makePanelFixture()
    fixture.store.upsert(makeTextItem("Older stack item", store: fixture.store))
    fixture.store.upsert(makeTextItem("Newest stack item", store: fixture.store))
    drainMainQueue()
    fixture.viewModel.selectItem(at: 0)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugStackCornerLabels, ["Add to Stack", "Add to Stack"])
    XCTAssertEqual(fixture.view.debugStackCornerHiddenStates, [true, true])
    XCTAssertFalse(fixture.view.debugFirstCardVisibleActionLabels.contains("Add to Stack"))
    let cardIdentifiersBeforeStackToggle = fixture.view.debugCardObjectIdentifiers

    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugStackCornerHiddenStates, [true, true])
    XCTAssertGreaterThan(fixture.view.debugFirstCardStackCornerFrame.maxX, 220)

    fixture.viewModel.toggleSelectedStackMembership()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugStatusText, "Added to Stack")
    XCTAssertEqual(fixture.view.debugCardObjectIdentifiers, cardIdentifiersBeforeStackToggle)
    XCTAssertEqual(fixture.view.debugStackCornerLabels, ["Remove from Stack", "Add to Stack"])
    XCTAssertEqual(fixture.view.debugStackCornerHiddenStates, [true, true])
    XCTAssertTrue(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStackChipCount, 1)

    fixture.viewModel.selectItem(at: 1)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugStackCornerHiddenStates, [true, true])
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
    XCTAssertEqual(fixture.view.debugSelectedSortCollectionTitles, ["Clipboard"])

    fixture.view.debugPressStackChip()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Stack")
    XCTAssertTrue(fixture.view.debugStackChipIsSelected)
    XCTAssertEqual(fixture.view.debugSelectedSortCollectionTitles, [])
    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.payload), ["First stack chip item", "Second stack chip item"])

    fixture.viewModel.clearStack()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStackChipCount, 0)
  }

  func testStackCaptureModeShowsEmptyActiveStackChip() {
    let fixture = makePanelFixture()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.view.debugStackChipIsVisible)

    fixture.viewModel.toggleStackCaptureMode()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStackChipCount, 0)
    XCTAssertEqual(fixture.view.debugStackChipMenuTitles.first, "Stop Stack Capture")
    XCTAssertEqual(fixture.view.debugStatusText, "Stack capture is on")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")

    fixture.view.debugPressStackChip()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugSelectedCollectionTitle, "Stack")
    XCTAssertTrue(fixture.view.debugStackChipIsSelected)
    XCTAssertEqual(fixture.view.debugEmptyStateText?.title, "Stack capture is on")
    XCTAssertEqual(fixture.view.debugEmptyStateText?.detail, "Copied items will appear here in order.")

    fixture.view.debugToggleStackCaptureFromStackChip()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(fixture.viewModel.isStackCaptureEnabled)
    XCTAssertFalse(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStatusText, "Stack capture is off")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")
  }

  func testStackChipMenuAddsVisibleShelfToQueue() {
    let fixture = makePanelFixture()
    var older = makeTextItem("Older batch stack item", store: fixture.store)
    older.createdAt = Date(timeIntervalSince1970: 100)
    older.lastUsedAt = older.createdAt
    var middle = makeTextItem("Middle batch stack item", store: fixture.store)
    middle.createdAt = Date(timeIntervalSince1970: 200)
    middle.lastUsedAt = middle.createdAt
    var newest = makeTextItem("Newest batch stack item", store: fixture.store)
    newest.createdAt = Date(timeIntervalSince1970: 300)
    newest.lastUsedAt = newest.createdAt
    fixture.store.upsert(older)
    fixture.store.upsert(middle)
    fixture.store.upsert(newest)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    fixture.viewModel.selectItem(at: 0)
    fixture.viewModel.toggleSelectedStackMembership()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugStackChipIsVisible)
    XCTAssertEqual(fixture.view.debugStackChipCount, 1)
    XCTAssertEqual(
      fixture.view.debugStackChipMenuTitles,
      ["Start Stack Capture", "-", "Add Visible Clips to Stack", "Paste Stack Next", "Copy Stack Next", "Paste Stack as Text", "Copy Stack as Text", "Clear Stack"]
    )
    XCTAssertEqual(
      fixture.view.debugStackChipAccessibilityHelp,
      "Press Return or Space to show Stack. Use Up/Down to move between categories, Left/Right to move between clips, and Home/End to move between categories. Open the context menu for Stack capture and Stack paste actions."
    )

    fixture.view.debugAddVisibleClipsToStackFromStackChip()
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugStackChipCount, 3)
    XCTAssertEqual(fixture.view.debugStatusText, "Added 2 clips to Stack")

    fixture.view.debugPressStackChip()
    drainMainQueue()

    XCTAssertEqual(
      fixture.viewModel.visibleItems.map(\.payload),
      ["Newest batch stack item", "Middle batch stack item", "Older batch stack item"]
    )
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
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["link-site-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewChrome, "browser-card")
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewHostText, "example.com")
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewMonogram, "EC")
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewAccentHex, "#008FFB")
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewHeroHeight, 78, accuracy: 0.5)
  }

  func testPlainURLCardsDeriveReadableTitleFromPath() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .url,
      displayText: "https://www.example.com/articles/weekly-design-review?utm_source=copy",
      payload: "https://www.example.com/articles/weekly-design-review?utm_source=copy",
      store: fixture.store
    )

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Link: Weekly Design Review"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Weekly Design Review|example.com/articles/weekly-design-review|example.com"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["link-site-preview"])
  }

  func testCompactLinkCardUsesCondensedBrowserPreview() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
    let item = makeItem(
      kind: .url,
      displayText: "Weekly Design Review",
      payload: "https://www.example.com/articles/weekly-design-review",
      store: fixture.store
    )

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["link-site-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewChrome, "browser-card")
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewHostText, "example.com")
    XCTAssertEqual(fixture.view.debugFirstCardLinkPreviewHeroHeight, 78, accuracy: 0.5)
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
    XCTAssertEqual(fixture.view.debugFirstCardLinkMediaPreviewChrome, "thumbnail-card")
    XCTAssertEqual(fixture.view.debugFirstCardLinkMediaPreviewHostText, "example.com")
    XCTAssertEqual(fixture.view.debugFirstCardLinkMediaPreviewImageHeight, 80, accuracy: 0.5)
  }

  func testTallSideShelfKeepsLinkMediaCardCompact() throws {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 640), display: true)
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

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["link-media-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardLinkMediaPreviewChrome, "thumbnail-card")
    XCTAssertEqual(fixture.view.debugFirstCardLinkMediaPreviewImageHeight, 80, accuracy: 0.5)
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
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewChrome, "document-cover")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewExtensionText, "PDF")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewLocationPlacement, "below-cover")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewCoverSize, NSSize(width: 104, height: 74))
  }

  func testCompactFileCardsUseCondensedDocumentCover() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Desktop")
      .appendingPathComponent("Summary.txt")
    let item = makeItem(kind: .file, displayText: "File", payload: fileURL.path, store: fixture.store)

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["file-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewChrome, "document-cover")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewExtensionText, "TXT")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewCoverSize, NSSize(width: 104, height: 74))
  }

  func testRenamedClipsUseCustomTitleInCardsAndSearch() {
    let fixture = makePanelFixture()
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Documents")
      .appendingPathComponent("Project Plan.pdf")
    let item = makeItem(kind: .file, displayText: "File", payload: fileURL.path, store: fixture.store)

    fixture.store.upsert(item)
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(fixture.view.debugFirstCardMenuTitles.contains("Rename..."))
    fixture.view.debugRenameFirstCard(to: "  Client   Launch  Brief  ")
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["File: Client Launch Brief"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Client Launch Brief|~/Documents|PDF"])
    XCTAssertEqual(fixture.view.debugStatusText, "Renamed clip")
    XCTAssertEqual(fixture.view.debugStatusTone, "action")

    fixture.viewModel.searchText = "launch"
    drainMainQueue()

    XCTAssertEqual(fixture.viewModel.visibleItems.map(\.id), [item.id])
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
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["multi-file-preview"])
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
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewChrome, "document-cover")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewExtensionText, "PDF")
    XCTAssertEqual(fixture.view.debugFirstCardFilePreviewLocationPlacement, "below-cover")

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
    XCTAssertEqual(fixture.view.debugFirstCardMediaMetricText, "360 x 280")
    XCTAssertEqual(fixture.view.debugFirstCardMediaMetricPlacement, "bottom-center")
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
    XCTAssertEqual(fixture.view.debugFirstCardAudioPreviewChrome, "album-card")
    XCTAssertEqual(fixture.view.debugFirstCardAudioArtworkSize, 62, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugFirstCardAudioLabelPlacement, "below-artwork")
  }

  func testCompactAudioCardsUseCondensedAlbumArtwork() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
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

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["audio-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardAudioPreviewChrome, "album-card")
    XCTAssertEqual(fixture.view.debugFirstCardAudioArtworkSize, 62, accuracy: 0.5)
  }

  func testVideoCardsUseFilmPreview() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .video,
      displayText: "Video (24 KB)",
      payload: "/tmp/clipbored-video.mp4",
      store: fixture.store
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .videos
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Video: Video (24 KB)"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Video (24 KB)|Video clip|MP4"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["video-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardVideoPreviewChrome, "player-card")
    XCTAssertEqual(fixture.view.debugFirstCardVideoFrameHeight, 82, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugFirstCardVideoFormatPlacement, "bottom-center")
  }

  func testCompactVideoCardsUseCondensedPlayerPreview() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
    let item = makeItem(
      kind: .video,
      displayText: "Video (24 KB)",
      payload: "/tmp/clipbored-video.mp4",
      store: fixture.store
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .videos
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardDensity, "compact")
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["video-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardVideoPreviewChrome, "player-card")
    XCTAssertEqual(fixture.view.debugFirstCardVideoFrameHeight, 82, accuracy: 0.5)
    XCTAssertEqual(fixture.view.debugFirstCardVideoFormatPlacement, "bottom-center")
  }

  func testVideoCardsUseMediaPreviewWhenThumbnailExists() throws {
    let cacheService = ClipboardCacheService(
      baseURL: makeTempDirectory(),
      encryptionService: ClipboardEncryptionService(keyProvider: { nil }),
      videoThumbnailProvider: { _ in self.sampleImage() }
    )
    let fixture = makePanelFixture(cacheService: cacheService)
    let id = UUID()
    let path = try XCTUnwrap(cacheService.cacheVideo(Data([0, 1, 2, 3]), id: id, fileExtension: "mp4"))
    let item = ClipboardItem(
      id: id,
      kind: .video,
      displayText: "Video (24 KB)",
      payload: path,
      payloadHash: fixture.store.hashString("video-thumbnail"),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: "QuickTime Player",
      imagePath: nil,
      thumbnailPath: nil
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .videos
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Video: Video (24 KB)"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["Video (24 KB)|Video clip|MP4"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["video-media-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardVideoPreviewChrome, "thumbnail-player")
    XCTAssertEqual(fixture.view.debugFirstCardVideoFormatPlacement, "bottom-center")
  }

  func testColorCardsUseSwatchPreview() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .color,
      displayText: "#0A84FF",
      payload: "#0A84FF",
      store: fixture.store
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .colors
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Color: #0A84FF"])
    XCTAssertEqual(fixture.view.debugCardPreviewSummaries, ["#0A84FF|RGB 10 132 255|Color"])
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["color-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewChrome, "paint-chip")
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewHexText, "#0A84FF")
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewSwatchPlacement, "top")
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewChipSize, NSSize(width: 196, height: 98))
  }

  func testCompactColorCardsUseCondensedPaintChipPreview() {
    let fixture = makePanelFixture()
    fixture.window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 520), display: true)
    let item = makeItem(
      kind: .color,
      displayText: "#FF3B30",
      payload: "#FF3B30",
      store: fixture.store
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .colors
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["color-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewChrome, "paint-chip")
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewHexText, "#FF3B30")
    XCTAssertEqual(fixture.view.debugFirstCardColorPreviewChipSize, NSSize(width: 196, height: 98))
  }

  func testCodeCardsUseMonospaceSnippetPreview() {
    let fixture = makePanelFixture()
    let item = makeItem(
      kind: .code,
      displayText: "Swift Snippet",
      payload: "func greet(name: String) -> String {\n  return \"Hi \\(name)\"\n}",
      store: fixture.store
    )

    fixture.store.upsert(item)
    fixture.viewModel.sortMode = .code
    drainMainQueue()
    fixture.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(fixture.view.debugCardAccessibilityLabels, ["Code: Swift Snippet"])
    XCTAssertEqual(
      fixture.view.debugCardPreviewSummaries,
      ["Swift Snippet|func greet(name: String) -> String { return \"Hi \\(name)\" }|Swift"]
    )
    XCTAssertEqual(fixture.view.debugCardPreviewStyles, ["code-preview"])
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
    XCTAssertTrue(fixture.view.debugFocusCard(at: 0))
    drainMainQueue()
    XCTAssertEqual(fixture.view.debugFirstCardVisibleActionLabels, [])
  }

  private func assertCollectionRailIsSideIconRail(in fixture: PanelFixture, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(fixture.view.debugCollectionRailVisibleWidth, 36, accuracy: 0.5, file: file, line: line)
    XCTAssertGreaterThan(fixture.view.debugCollectionRailContentTopInset, 0, file: file, line: line)
    XCTAssertEqual(
      fixture.view.debugCollectionRailContentFrameInPanel.midY,
      fixture.view.debugCollectionRailFrameInPanel.midY,
      accuracy: 1,
      file: file,
      line: line
    )
    XCTAssertEqual(fixture.view.debugCollectionStackOrientation, .vertical, file: file, line: line)
    XCTAssertLessThan(
      fixture.view.debugCollectionRailFrameInPanel.midX,
      fixture.view.bounds.midX,
      file: file,
      line: line
    )
  }

  private func assertCompactMetricFitsWithoutEllipsisOrOverflow(
    in fixture: PanelFixture,
    at index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let metricTexts = fixture.view.debugCardCompactMetricTexts
    let metricFrames = fixture.view.debugCardCompactMetricFramesInPanel
    let fittingWidths = fixture.view.debugCardCompactMetricFittingWidths
    let headerFrames = fixture.view.debugCardHeaderFramesInPanel
    guard metricTexts.indices.contains(index),
          metricFrames.indices.contains(index),
          fittingWidths.indices.contains(index),
          headerFrames.indices.contains(index) else {
      XCTFail("Expected compact metric debug data at index \(index)", file: file, line: line)
      return
    }

    let metricText = metricTexts[index]
    let metricFrame = metricFrames[index]
    let fittingWidth = fittingWidths[index]
    let headerFrame = headerFrames[index]

    XCTAssertFalse(metricText.contains("…"), file: file, line: line)
    XCTAssertFalse(metricText.contains("..."), file: file, line: line)
    XCTAssertGreaterThan(metricFrame.width, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(metricFrame.width + 0.5, fittingWidth, file: file, line: line)
    XCTAssertGreaterThanOrEqual(metricFrame.minX, headerFrame.minX - 0.5, file: file, line: line)
    XCTAssertLessThanOrEqual(metricFrame.maxX, headerFrame.maxX + 0.5, file: file, line: line)
  }

  private func makePanelWithPanelView() -> (NSWindow, ClipboardPanelView) {
    let fixture = makePanelFixture()
    return (fixture.window, fixture.view)
  }

  private func makePanelFixture(cacheService: ClipboardCacheService? = nil) -> PanelFixture {
    let settings = makeSettings()
    let cacheService = cacheService ?? ClipboardCacheService(
      baseURL: makeTempDirectory(),
      encryptionService: ClipboardEncryptionService(keyProvider: { nil })
    )
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    let previewProbe = PreviewProbe()

    let view = ClipboardPanelView(
      viewModel: viewModel,
      onClose: {},
      onSettings: {},
      onPreview: { previewProbe.requestCount += 1 }
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
      cacheService: cacheService,
      previewProbe: previewProbe
    )
  }

  private func makeSettings() -> SettingsModel {
    let settings = SettingsModel(defaults: UserDefaults(suiteName: "com.clipbored.viewtest.\(UUID().uuidString)")!)
    settings.maxHistoryItems = 10
    settings.historyRetention = .forever
    settings.pruneDuplicates = false
    return settings
  }

  private func makeStore(settings: SettingsModel, cacheService: ClipboardCacheService) -> ClipboardStore {
    ClipboardStore(
      settings: settings,
      cacheService: cacheService,
      baseURL: makeTempDirectory(),
      encryptionService: ClipboardEncryptionService(keyProvider: { nil })
    )
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

  private func localDate(_ value: String, hour: Int = 12, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .autoupdatingCurrent
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    let date = formatter.date(from: value)!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
  }

  private func writeSnapshot(of view: NSView, to url: URL) throws {
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: url)
  }

  private func drainMainQueue() {
    for _ in 0..<20 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }
}
