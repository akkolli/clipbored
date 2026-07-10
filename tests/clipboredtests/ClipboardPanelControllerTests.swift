import AppKit
import Carbon
import XCTest
@testable import ClipBored

final class ClipboardPanelControllerTests: XCTestCase {
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

  func testOpenScreenSelectionPrefersExplicitThenPointerScreen() {
    XCTAssertEqual(
      ClipboardPanelController.selectedOpenScreen(
        explicit: "status-item-screen",
        preferred: nil,
        pointer: "pointer-screen",
        fallback: "fallback-screen"
      ),
      "status-item-screen"
    )
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

  func testPanelCollectionBehaviorStaysLocalToActiveSpaceAndSupportsFullscreen() {
    let behavior = ClipboardPanelController.panelCollectionBehavior

    XCTAssertTrue(behavior.contains(.moveToActiveSpace))
    XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    XCTAssertTrue(behavior.contains(.transient))
    XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
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

  func testContentBottomInsetHandlesBottomAndSideDock() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let inset = ClipboardPanelController.contentBottomInset(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(inset, 20)
    XCTAssertEqual(
      ClipboardPanelController.contentBottomInset(
        forScreenFrame: screenFrame,
        visibleFrame: CGRect(x: 80, y: 0, width: 1432, height: 957)
      ),
      18
    )
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
    assertShortcutMappings([
      (18, .command, 0), (19, .command, 1), (20, .command, 2),
      (21, .command, 3), (23, .command, 4), (22, .command, 5),
      (26, .command, 6), (28, .command, 7), (25, .command, 8)
    ], using: ClipboardPanelController.quickPasteIndex)
  }

  func testShiftCommandNumberShortcutsMapToPlainTextQuickPasteSlots() {
    assertShortcutMappings([
      (18, [.command, .shift], 0),
      (25, [.command, .shift], 8),
      (18, .command, nil),
      (18, [.command, .option, .shift], nil)
    ], using: ClipboardPanelController.quickPastePlainTextIndex)
  }

  func testCommandOptionNumberShortcutsMapToCollections() {
    assertShortcutMappings([
      (18, [.command, .option], .mostRecent),
      (19, [.command, .option], .mostUsed),
      (20, [.command, .option], .text),
      (21, [.command, .option], .links),
      (23, [.command, .option], .images),
      (22, [.command, .option], .files),
      (26, [.command, .option], .pinned),
      (28, [.command, .option], .audio),
      (25, [.command, .option], .colors),
      (29, [.command, .option], .code),
      (18, [], nil),
      (18, .command, nil),
      (29, .command, nil)
    ], using: ClipboardPanelController.collectionShortcutMode)
  }

  func testSearchFieldSpacePreviewShortcutRequiresEmptySearchAndNoModifiers() {
    XCTAssertTrue(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: [], searchText: ""))
    XCTAssertTrue(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: [], searchText: "   "))
    XCTAssertFalse(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: [], searchText: "release note"))
    XCTAssertFalse(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 49, modifiers: .command, searchText: ""))
    XCTAssertFalse(ClipboardPanelController.searchFieldPreviewShortcut(forKeyCode: 36, modifiers: [], searchText: ""))
  }

  func testNavigationShortcutsMapToShelfMovement() {
    assertShortcutMappings([
      (115, [], .first), (119, [], .last), (124, [], .next),
      (121, [], .pageNext), (116, [], .pagePrevious), (123, [], .previous),
      (126, .command, .first), (125, .command, .last),
      (124, .command, nil), (126, [], nil), (125, [], nil),
      (121, .shift, nil), (35, [], nil)
    ], using: ClipboardPanelController.navigationShortcutAction)
  }

  func testSelectionShortcutsMapToRangeAndSelectAllActions() {
    assertShortcutMappings([
      (0, .command, .selectAll),
      (115, .shift, .extendFirst), (119, .shift, .extendLast),
      (124, .shift, .extendNext), (121, .shift, .extendPageNext),
      (116, .shift, .extendPagePrevious), (123, .shift, .extendPrevious),
      (0, [], nil), (0, [.command, .shift], nil),
      (124, [], nil), (124, [.command, .shift], nil)
    ], using: ClipboardPanelController.selectionShortcutAction)
  }

  func testCommandActionShortcutsMapToSelectedClipActions() {
    assertShortcutMappings([
      (8, .command, .copy), (14, .command, .edit), (3, .command, .focusSearch),
      (45, .command, nil), (5, .command, .showInClipboard),
      (16, .command, .preview), (31, .command, .open), (15, .command, .rename),
      (17, .command, .toggleCapturePause), (6, .command, .undoDelete),
      (123, .command, .previousCollection), (124, .command, .nextCollection),
      (8, [], nil), (8, [.command, .shift], nil), (9, .command, nil)
    ], using: ClipboardPanelController.commandShortcutAction)
  }

  func testSettingsShortcutMatchesOnlyItsExactLocalBinding() {
    let binding = AppConfiguration.defaultSettingsShortcut

    XCTAssertTrue(
      ClipboardPanelController.matchesShortcut(
        keyCode: UInt16(kVK_ANSI_Comma),
        modifiers: .command,
        binding: binding
      )
    )
    XCTAssertFalse(
      ClipboardPanelController.matchesShortcut(
        keyCode: UInt16(kVK_ANSI_Comma),
        modifiers: [.command, .shift],
        binding: binding
      )
    )
    XCTAssertFalse(
      ClipboardPanelController.matchesShortcut(
        keyCode: UInt16(kVK_ANSI_Period),
        modifiers: .command,
        binding: binding
      )
    )
  }

  func testModifiedShortcutsMapToPanelActions() {
    assertShortcutMappings([
      (36, .shift, .pastePlainText),
      (1, [.command, .shift], .toggleStack),
      (8, [.command, .shift], .toggleStackCapture),
      (9, [.command, .shift], .pastePlainText),
      (45, [.command, .shift], .newCollection),
      (36, [.command, .shift], .pasteStackNext),
      (36, [], nil), (8, .shift, nil), (8, .command, nil),
      (8, [.command, .option, .shift], nil), (31, [.command, .shift], nil)
    ], using: ClipboardPanelController.modifiedShortcutAction)
  }

  private func assertShortcutMappings<Value: Equatable>(
    _ cases: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, expected: Value?)],
    using mapping: (UInt16, NSEvent.ModifierFlags) -> Value?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for testCase in cases {
      XCTAssertEqual(
        mapping(testCase.keyCode, testCase.modifiers),
        testCase.expected,
        "keyCode \(testCase.keyCode), modifiers \(testCase.modifiers.rawValue)",
        file: file,
        line: line
      )
    }
  }
}
