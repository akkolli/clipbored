import AppKit
import XCTest
@testable import ClipBored

final class ClipboardPanelControllerTests: XCTestCase {
  private var tempURLs: [URL] = []
  private var defaultsSuites: [String] = []

  override func tearDown() {
    for url in tempURLs {
      try? FileManager.default.removeItem(at: url)
    }
    tempURLs.removeAll()
    for suite in defaultsSuites {
      UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
    defaultsSuites.removeAll()
    super.tearDown()
  }

  func testPanelFrameUsesRightSideShelfByDefault() {
    let screenFrame = CGRect(x: -1200, y: -200, width: 1200, height: 800)
    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: screenFrame)

    XCTAssertEqual(frames.shown.maxX, screenFrame.maxX)
    XCTAssertEqual(frames.shown.width, 336)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, screenFrame.maxY)
    XCTAssertEqual(frames.hidden.minX, screenFrame.maxX + 1)
    XCTAssertEqual(frames.hidden.minY, frames.shown.minY)
  }

  func testOpenScreenSelectionUsesStatusClickScreenWhenProvided() {
    XCTAssertEqual(
      ClipboardPanelController.selectedOpenScreen(
        explicit: "status-item-screen",
        preferred: nil,
        pointer: "pointer-screen",
        fallback: "fallback-screen"
      ),
      "status-item-screen"
    )
  }

  func testOpenScreenSelectionFallsBackToPointerForGlobalShortcut() {
    XCTAssertEqual(
      ClipboardPanelController.selectedOpenScreen(
        explicit: Optional<String>.none,
        preferred: nil,
        pointer: "pointer-screen",
        fallback: "fallback-screen"
      ),
      "pointer-screen"
    )
  }

  func testReflowScreenSelectionKeepsCurrentPanelScreenAheadOfPointer() {
    XCTAssertEqual(
      ClipboardPanelController.selectedReflowScreen(
        currentPanel: "current-panel-screen",
        lastKnown: "last-known-screen",
        preferred: nil,
        pointer: "pointer-screen",
        fallback: "fallback-screen"
      ),
      "current-panel-screen"
    )
    XCTAssertEqual(
      ClipboardPanelController.selectedReflowScreen(
        currentPanel: Optional<String>.none,
        lastKnown: "last-known-screen",
        preferred: nil,
        pointer: "pointer-screen",
        fallback: "fallback-screen"
      ),
      "last-known-screen"
    )
  }

  func testPanelFrameUsesVisibleFrameAroundDock() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 80, y: 0, width: 1432, height: 957)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.maxX, visibleFrame.maxX)
    XCTAssertEqual(frames.shown.minX, visibleFrame.maxX - 336)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.width, 336)
  }

  func testPanelFrameUsesAvailableHeightWhenBottomDockIsVisible() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.maxX, visibleFrame.maxX)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.width, 336)
    XCTAssertEqual(frames.hidden.minX, visibleFrame.maxX + 1)
  }

  func testPanelFrameTouchesScreenBottomWhenBottomDockIsAutoHidden() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 4, width: 1512, height: 953)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.maxX, visibleFrame.maxX)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.width, 336)
    XCTAssertEqual(frames.hidden.minX, visibleFrame.maxX + 1)
  }

  func testPanelFrameKeepsSideShelfWidthOnTallDisplays() {
    let screenFrame = CGRect(x: 0, y: 0, width: 3008, height: 2000)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: screenFrame)

    XCTAssertEqual(frames.shown.width, 336)
    XCTAssertEqual(frames.shown.height, 2000)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxX, screenFrame.maxX)
  }

  func testPanelFrameFitsTinyVisibleFrameWithoutOverflowing() {
    let screenFrame = CGRect(x: 0, y: 0, width: 640, height: 320)
    let visibleFrame = CGRect(x: 0, y: 48, width: 640, height: 220)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.width, 320)
    XCTAssertLessThanOrEqual(frames.shown.width, visibleFrame.width)
    XCTAssertEqual(frames.hidden.minX, screenFrame.maxX + 1)
  }

  func testPanelFrameIgnoresLegacyPreferredResizableHeight() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let frames = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      preferredHeight: 600
    )

    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.height, 957)
    XCTAssertEqual(frames.hidden.minX, visibleFrame.maxX + 1)
  }

  func testPanelFrameLegacyPreferredHeightDoesNotAffectSideShelf() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    let tooTall = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      preferredHeight: 900
    )
    let tooShort = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      preferredHeight: 120
    )

    XCTAssertEqual(tooTall.shown.height, 982)
    XCTAssertEqual(tooShort.shown.height, 982)
    XCTAssertEqual(tooTall.shown.width, 336)
    XCTAssertEqual(tooShort.shown.width, 336)
  }

  func testPanelFrameLegacyPreferredHeightDoesNotOverflowTinyVisibleFrame() {
    let screenFrame = CGRect(x: 0, y: 0, width: 640, height: 320)
    let visibleFrame = CGRect(x: 0, y: 48, width: 640, height: 220)

    let frames = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      preferredHeight: 620
    )

    XCTAssertEqual(frames.shown.height, 268)
    XCTAssertEqual(frames.shown.width, 320)
    XCTAssertLessThanOrEqual(frames.shown.height, visibleFrame.maxY - screenFrame.minY)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
  }

  func testPanelFramePlanningIsDeterministicAcrossRepeatedToggles() {
    let screenFrame = CGRect(x: -1512, y: -120, width: 1512, height: 982)
    let visibleFrame = CGRect(x: -1512, y: -24, width: 1512, height: 861)
    let first = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    for _ in 0..<50 {
      let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
      XCTAssertEqual(frames.shown, first.shown)
      XCTAssertEqual(frames.hidden, first.hidden)
      XCTAssertEqual(frames.hidden.minX, frames.shown.maxX + 1)
    }
  }

  func testPanelAnimationProfileStaysShortForSixtyFpsFeel() {
    let profile = ClipboardPanelController.animationProfile

    XCTAssertEqual(profile.showDuration, 0.22)
    XCTAssertEqual(profile.hideDuration, 0.16)
    XCTAssertEqual(profile.reflowDuration, 0.18)
    XCTAssertLessThanOrEqual(profile.showDuration * 60, 14)
    XCTAssertLessThanOrEqual(profile.hideDuration * 60, 10)
    XCTAssertLessThanOrEqual(profile.reflowDuration * 60, 11)
    XCTAssertEqual(profile.easing, .easeInEaseOut)
  }

  func testPanelCollectionBehaviorStaysLocalToActiveSpaceAndSupportsFullscreen() {
    let behavior = ClipboardPanelController.panelCollectionBehavior

    XCTAssertTrue(behavior.contains(.moveToActiveSpace))
    XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    XCTAssertTrue(behavior.contains(.transient))
    XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
  }

  func testShowingPanelClearsAndCollapsesStaleSearchState() throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let (controller, _) = makeController(preferredScreen: screen)

    controller.debugSetSearchFieldText("stale query")
    drainMainQueue()
    XCTAssertEqual(controller.debugSearchFieldText, "stale query")
    XCTAssertEqual(controller.debugSearchFieldWidth, 164, accuracy: 0.5)
    XCTAssertEqual(controller.debugSearchFieldPlaceholderText, "Search clips")
    XCTAssertTrue(controller.debugSearchFieldIsVisible)
    XCTAssertFalse(controller.debugSearchIconButtonIsVisible)

    controller.show(preferredScreen: screen)
    defer { controller.hide(immediate: true) }
    drainMainQueue()

    XCTAssertEqual(controller.debugSearchFieldText, "")
    XCTAssertEqual(controller.debugSearchFieldWidth, 30, accuracy: 1)
    XCTAssertEqual(controller.debugSearchFieldPlaceholderText, "")
    XCTAssertFalse(controller.debugSearchFieldIsVisible)
    XCTAssertTrue(controller.debugSearchIconButtonIsVisible)
    XCTAssertFalse(controller.debugIsSearchFieldEditing)
  }

  func testReflowPlanKeepsOpenPanelOnRightSideWhenBottomDockIsVisible() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 112, width: 1512, height: 845)

    let plan = ClipboardPanelController.reflowPlan(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(plan.frame.maxX, visibleFrame.maxX)
    XCTAssertEqual(plan.frame.minY, screenFrame.minY)
    XCTAssertEqual(plan.frame.maxY, visibleFrame.maxY)
    XCTAssertEqual(plan.frame.width, 336)
    XCTAssertEqual(plan.bottomSafeInset, 20)
  }

  func testReflowPlanTouchesScreenBottomWhenBottomDockIsAutoHidden() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 4, width: 1512, height: 953)

    let plan = ClipboardPanelController.reflowPlan(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(plan.frame.maxX, visibleFrame.maxX)
    XCTAssertEqual(plan.frame.minY, screenFrame.minY)
    XCTAssertEqual(plan.frame.maxY, visibleFrame.maxY)
    XCTAssertEqual(plan.frame.width, 336)
    XCTAssertEqual(plan.bottomSafeInset, 18)
  }

  func testReflowPlanIgnoresLegacyPreferredResizableHeight() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let plan = ClipboardPanelController.reflowPlan(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      preferredHeight: 600
    )

    XCTAssertEqual(plan.frame.minY, screenFrame.minY)
    XCTAssertEqual(plan.frame.height, 957)
    XCTAssertEqual(plan.frame.width, 336)
    XCTAssertEqual(plan.bottomSafeInset, 20)
  }

  func testReflowPlanTracksSideDockVisibleFrameWithoutBottomInsetInflation() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 86, y: 0, width: 1426, height: 957)

    let plan = ClipboardPanelController.reflowPlan(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(plan.frame.maxX, visibleFrame.maxX)
    XCTAssertEqual(plan.frame.minX, visibleFrame.maxX - 336)
    XCTAssertEqual(plan.frame.minY, screenFrame.minY)
    XCTAssertEqual(plan.frame.height, 957)
    XCTAssertEqual(plan.bottomSafeInset, 18)
  }

  func testPanelFrameUsesConfiguredRightSideShelf() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let frames = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      side: .right
    )

    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.maxX, visibleFrame.maxX)
    XCTAssertEqual(frames.shown.width, 336)
    XCTAssertEqual(frames.hidden.minY, frames.shown.minY)
    XCTAssertEqual(frames.hidden.minX, screenFrame.maxX + 1)
  }

  func testPanelFrameUsesConfiguredLeftSideShelf() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 80, y: 0, width: 1432, height: 957)

    let frames = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: visibleFrame,
      side: .left
    )

    XCTAssertEqual(frames.shown.minX, visibleFrame.minX)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, visibleFrame.maxY)
    XCTAssertEqual(frames.shown.width, 336)
    XCTAssertEqual(frames.hidden.maxX, visibleFrame.minX - 1)
    XCTAssertEqual(frames.hidden.minY, frames.shown.minY)
  }

  func testPanelFrameUsesFullScreenHeightWhenVisibleFrameMatchesScreen() {
    let screenFrame = CGRect(x: -1512, y: -120, width: 1512, height: 982)

    let frames = ClipboardPanelController.panelFrames(
      forScreenFrame: screenFrame,
      visibleFrame: screenFrame,
      side: .right
    )

    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.maxY, screenFrame.maxY)
    XCTAssertEqual(frames.shown.maxX, screenFrame.maxX)
    XCTAssertEqual(frames.shown.width, 336)
  }

  func testContentBottomInsetReservesBottomDockSpace() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let inset = ClipboardPanelController.contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(inset, 20)
  }

  func testContentBottomInsetUsesMinimumWhenDockIsNotAtBottom() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 80, y: 0, width: 1432, height: 957)

    let inset = ClipboardPanelController.contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(inset, 18)
  }

  func testPanelSharingTypeHidesWindowFromScreenCaptureWhenEnabled() {
    XCTAssertEqual(ClipboardPanelController.panelSharingType(hideFromScreenCapture: false), .readOnly)
    XCTAssertEqual(ClipboardPanelController.panelSharingType(hideFromScreenCapture: true), .none)
  }

  func testLinkPreviewFrameSitsAboveBottomShelfWhenSpaceAllows() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
    let shelfFrame = NSRect(x: 0, y: 0, width: 1512, height: 408)

    let frame = LinkPreviewWindowController.previewFrame(parentFrame: shelfFrame, visibleFrame: visibleFrame)

    XCTAssertGreaterThanOrEqual(frame.minY, shelfFrame.maxY + 14)
    XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 24)
    XCTAssertEqual(frame.width, 1088)
    XCTAssertEqual(frame.height, 536)
    XCTAssertEqual(frame.midX, shelfFrame.midX, accuracy: 0.5)
  }

  func testCommandNumberShortcutsMapToQuickPasteSlots() {
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 18, modifiers: .command), 0)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 19, modifiers: .command), 1)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 20, modifiers: .command), 2)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 21, modifiers: .command), 3)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 23, modifiers: .command), 4)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 22, modifiers: .command), 5)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 26, modifiers: .command), 6)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 28, modifiers: .command), 7)
    XCTAssertEqual(ClipboardPanelController.quickPasteIndex(forKeyCode: 25, modifiers: .command), 8)
  }

  func testShiftCommandNumberShortcutsMapToPlainTextQuickPasteSlots() {
    XCTAssertEqual(ClipboardPanelController.quickPastePlainTextIndex(forKeyCode: 18, modifiers: [.command, .shift]), 0)
    XCTAssertEqual(ClipboardPanelController.quickPastePlainTextIndex(forKeyCode: 25, modifiers: [.command, .shift]), 8)
    XCTAssertNil(ClipboardPanelController.quickPastePlainTextIndex(forKeyCode: 18, modifiers: .command))
    XCTAssertNil(ClipboardPanelController.quickPastePlainTextIndex(forKeyCode: 18, modifiers: [.command, .option, .shift]))
  }

  func testCommandOptionNumberShortcutsMapToCollections() {
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 18, modifiers: [.command, .option]), .mostRecent)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 19, modifiers: [.command, .option]), .mostUsed)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 20, modifiers: [.command, .option]), .text)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 21, modifiers: [.command, .option]), .links)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 23, modifiers: [.command, .option]), .images)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 22, modifiers: [.command, .option]), .files)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 26, modifiers: [.command, .option]), .pinned)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 28, modifiers: [.command, .option]), .audio)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 25, modifiers: [.command, .option]), .colors)
    XCTAssertEqual(ClipboardPanelController.collectionShortcutMode(forKeyCode: 29, modifiers: [.command, .option]), .code)
  }

  func testCollectionShortcutsRequireCommandOptionSoQuickPasteKeepsCommandNumbers() {
    XCTAssertNil(ClipboardPanelController.collectionShortcutMode(forKeyCode: 18, modifiers: []))
    XCTAssertNil(ClipboardPanelController.collectionShortcutMode(forKeyCode: 18, modifiers: .command))
    XCTAssertNil(ClipboardPanelController.collectionShortcutMode(forKeyCode: 29, modifiers: .command))
  }

  func testSearchFieldSpacePreviewShortcutRequiresEmptySearchAndNoModifiers() {
    XCTAssertTrue(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: [], searchText: ""))
    XCTAssertTrue(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: [], searchText: "   "))
    XCTAssertFalse(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: [], searchText: "release note"))
    XCTAssertFalse(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: .command, searchText: ""))
    XCTAssertFalse(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 36, modifiers: [], searchText: ""))
  }

  func testNavigationShortcutsMapToShelfMovement() {
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 115, modifiers: []), .first)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 119, modifiers: []), .last)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 124, modifiers: []), .next)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 121, modifiers: []), .pageNext)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 116, modifiers: []), .pagePrevious)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 123, modifiers: []), .previous)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 126, modifiers: .command), .first)
    XCTAssertEqual(ClipboardPanelController.navigationShortcutAction(forKeyCode: 125, modifiers: .command), .last)
  }

  func testNavigationShortcutsRejectUnsupportedModifiers() {
    XCTAssertNil(ClipboardPanelController.navigationShortcutAction(forKeyCode: 124, modifiers: .command))
    XCTAssertNil(ClipboardPanelController.navigationShortcutAction(forKeyCode: 126, modifiers: []))
    XCTAssertNil(ClipboardPanelController.navigationShortcutAction(forKeyCode: 125, modifiers: []))
    XCTAssertNil(ClipboardPanelController.navigationShortcutAction(forKeyCode: 121, modifiers: .shift))
    XCTAssertNil(ClipboardPanelController.navigationShortcutAction(forKeyCode: 35, modifiers: []))
  }

  func testSelectionShortcutsMapToRangeAndSelectAllActions() {
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 0, modifiers: .command), .selectAll)
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 115, modifiers: .shift), .extendFirst)
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 119, modifiers: .shift), .extendLast)
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 124, modifiers: .shift), .extendNext)
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 121, modifiers: .shift), .extendPageNext)
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 116, modifiers: .shift), .extendPagePrevious)
    XCTAssertEqual(ClipboardPanelController.selectionShortcutAction(forKeyCode: 123, modifiers: .shift), .extendPrevious)
  }

  func testSelectionShortcutsRequireExactModifierSets() {
    XCTAssertNil(ClipboardPanelController.selectionShortcutAction(forKeyCode: 0, modifiers: []))
    XCTAssertNil(ClipboardPanelController.selectionShortcutAction(forKeyCode: 0, modifiers: [.command, .shift]))
    XCTAssertNil(ClipboardPanelController.selectionShortcutAction(forKeyCode: 124, modifiers: []))
    XCTAssertNil(ClipboardPanelController.selectionShortcutAction(forKeyCode: 124, modifiers: [.command, .shift]))
  }

  func testCommandActionShortcutsMapToSelectedClipActions() {
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 8, modifiers: .command), .copy)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 14, modifiers: .command), .edit)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 3, modifiers: .command), .focusSearch)
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 45, modifiers: .command))
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 5, modifiers: .command), .showInClipboard)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 16, modifiers: .command), .preview)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 31, modifiers: .command), .open)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 15, modifiers: .command), .rename)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 17, modifiers: .command), .toggleCapturePause)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 6, modifiers: .command), .undoDelete)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 123, modifiers: .command), .previousCollection)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 124, modifiers: .command), .nextCollection)
  }

  func testCommandActionShortcutsRequireCommandOnlySoSearchTypingIsUntouched() {
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 8, modifiers: []))
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 8, modifiers: [.command, .shift]))
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 9, modifiers: .command))
  }

  func testModifiedShortcutsMapToPanelActions() {
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 36, modifiers: .shift), .pastePlainText)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 1, modifiers: [.command, .shift]), .toggleStack)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: [.command, .shift]), .toggleStackCapture)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 9, modifiers: [.command, .shift]), .pastePlainText)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 45, modifiers: [.command, .shift]), .newCollection)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 36, modifiers: [.command, .shift]), .pasteStackNext)
  }

  func testModifiedShortcutsRequireCommandShiftOnly() {
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 36, modifiers: []))
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: .shift))
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: .command))
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: [.command, .option, .shift]))
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 31, modifiers: [.command, .shift]))
  }

  private func makeController(preferredScreen: NSScreen) -> (ClipboardPanelController, ClipboardStore) {
    let settings = makeSettings()
    let encryptionService = ClipboardEncryptionService(keyProvider: { nil })
    let cacheService = ClipboardCacheService(
      baseURL: makeTempDirectory(),
      encryptionService: encryptionService
    )
    let store = ClipboardStore(
      settings: settings,
      cacheService: cacheService,
      baseURL: makeTempDirectory(),
      encryptionService: encryptionService
    )
    let controller = ClipboardPanelController(
      store: store,
      settings: settings,
      cacheService: cacheService,
      preferredScreen: { preferredScreen }
    )
    return (controller, store)
  }

  private func makeSettings() -> SettingsModel {
    let suite = "com.clipbored.controllertest.\(UUID().uuidString)"
    defaultsSuites.append(suite)
    let defaults = UserDefaults(suiteName: suite)!
    let settings = SettingsModel(defaults: defaults)
    settings.maxHistoryItems = 10
    settings.historyRetention = .forever
    settings.pruneDuplicates = false
    return settings
  }

  private func makeTempDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipbored-controllertest")
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    tempURLs.append(directory)
    return directory
  }

  private func drainMainQueue() {
    for _ in 0..<24 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }
}
