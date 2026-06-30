import XCTest
@testable import ClipBored

final class ClipboardPanelControllerTests: XCTestCase {
  func testPanelFrameUsesFullWidthBottomShelf() {
    let screenFrame = CGRect(x: -1200, y: -200, width: 1200, height: 800)
    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: screenFrame)

    XCTAssertEqual(frames.shown.minX, screenFrame.minX)
    XCTAssertEqual(frames.shown.maxX, screenFrame.maxX)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
    XCTAssertEqual(frames.shown.height, 408)
    XCTAssertLessThan(frames.hidden.maxY, screenFrame.minY)
  }

  func testPanelFrameUsesVisibleFrameAroundDock() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 80, y: 0, width: 1432, height: 957)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.minX, visibleFrame.minX)
    XCTAssertEqual(frames.shown.maxX, visibleFrame.maxX)
    XCTAssertEqual(frames.shown.minY, visibleFrame.minY)
    XCTAssertEqual(frames.shown.height, 408)
  }

  func testPanelFrameSitsAboveVisibleBottomDock() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 96, width: 1512, height: 861)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.minX, visibleFrame.minX)
    XCTAssertEqual(frames.shown.maxX, visibleFrame.maxX)
    XCTAssertEqual(frames.shown.minY, visibleFrame.minY)
    XCTAssertEqual(frames.shown.height, 408)
    XCTAssertLessThan(frames.hidden.maxY, visibleFrame.minY)
  }

  func testPanelFrameClampsTallDisplaysToShelfMaximum() {
    let screenFrame = CGRect(x: 0, y: 0, width: 3008, height: 2000)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: screenFrame)

    XCTAssertEqual(frames.shown.width, 3008)
    XCTAssertEqual(frames.shown.height, 430)
    XCTAssertEqual(frames.shown.minY, screenFrame.minY)
  }

  func testPanelFrameFitsTinyVisibleFrameWithoutOverflowing() {
    let screenFrame = CGRect(x: 0, y: 0, width: 640, height: 320)
    let visibleFrame = CGRect(x: 0, y: 48, width: 640, height: 220)

    let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(frames.shown.minY, visibleFrame.minY)
    XCTAssertEqual(frames.shown.height, visibleFrame.height)
    XCTAssertLessThan(frames.hidden.maxY, visibleFrame.minY)
  }

  func testPanelFramePlanningIsDeterministicAcrossRepeatedToggles() {
    let screenFrame = CGRect(x: -1512, y: -120, width: 1512, height: 982)
    let visibleFrame = CGRect(x: -1512, y: -24, width: 1512, height: 861)
    let first = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    for _ in 0..<50 {
      let frames = ClipboardPanelController.panelFrames(forScreenFrame: screenFrame, visibleFrame: visibleFrame)
      XCTAssertEqual(frames.shown, first.shown)
      XCTAssertEqual(frames.hidden, first.hidden)
      XCTAssertEqual(frames.hidden.maxY, frames.shown.minY - 1)
    }
  }

  func testPanelAnimationProfileStaysShortForSixtyFpsFeel() {
    let profile = ClipboardPanelController.animationProfile

    XCTAssertEqual(profile.showDuration, 0.16)
    XCTAssertEqual(profile.hideDuration, 0.12)
    XCTAssertEqual(profile.reflowDuration, 0.10)
    XCTAssertLessThanOrEqual(profile.showDuration * 60, 10)
    XCTAssertLessThanOrEqual(profile.hideDuration * 60, 8)
    XCTAssertLessThanOrEqual(profile.reflowDuration * 60, 6)
    XCTAssertEqual(profile.easing, .easeInEaseOut)
  }

  func testReflowPlanMovesOpenPanelAboveNewBottomDockVisibleFrame() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 112, width: 1512, height: 845)

    let plan = ClipboardPanelController.reflowPlan(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(plan.frame.minX, visibleFrame.minX)
    XCTAssertEqual(plan.frame.maxX, visibleFrame.maxX)
    XCTAssertEqual(plan.frame.minY, visibleFrame.minY)
    XCTAssertEqual(plan.frame.height, 408)
    XCTAssertEqual(plan.bottomSafeInset, 20)
  }

  func testReflowPlanTracksSideDockVisibleWidthWithoutBottomInsetInflation() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 86, y: 0, width: 1426, height: 957)

    let plan = ClipboardPanelController.reflowPlan(forScreenFrame: screenFrame, visibleFrame: visibleFrame)

    XCTAssertEqual(plan.frame.minX, visibleFrame.minX)
    XCTAssertEqual(plan.frame.maxX, visibleFrame.maxX)
    XCTAssertEqual(plan.frame.minY, visibleFrame.minY)
    XCTAssertEqual(plan.frame.height, 408)
    XCTAssertEqual(plan.bottomSafeInset, 18)
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
  }

  func testCollectionShortcutsRequireCommandOptionSoQuickPasteKeepsCommandNumbers() {
    XCTAssertNil(ClipboardPanelController.collectionShortcutMode(forKeyCode: 18, modifiers: []))
    XCTAssertNil(ClipboardPanelController.collectionShortcutMode(forKeyCode: 18, modifiers: .command))
    XCTAssertNil(ClipboardPanelController.collectionShortcutMode(forKeyCode: 29, modifiers: .command))
  }

  func testCommandActionShortcutsMapToSelectedClipActions() {
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 8, modifiers: .command), .copy)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 16, modifiers: .command), .preview)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 31, modifiers: .command), .open)
    XCTAssertEqual(ClipboardPanelController.commandShortcutAction(forKeyCode: 15, modifiers: .command), .reveal)
  }

  func testCommandActionShortcutsRequireCommandOnlySoSearchTypingIsUntouched() {
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 8, modifiers: []))
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 8, modifiers: [.command, .shift]))
    XCTAssertNil(ClipboardPanelController.commandShortcutAction(forKeyCode: 9, modifiers: .command))
  }

  func testModifiedShortcutsMapToPlainTextActions() {
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 1, modifiers: [.command, .shift]), .toggleStack)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: [.command, .shift]), .copyPlainText)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 9, modifiers: [.command, .shift]), .pastePlainText)
    XCTAssertEqual(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 36, modifiers: [.command, .shift]), .pasteStackNext)
  }

  func testModifiedShortcutsRequireCommandShiftOnly() {
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: .command))
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 8, modifiers: [.command, .option, .shift]))
    XCTAssertNil(ClipboardPanelController.modifiedShortcutAction(forKeyCode: 31, modifiers: [.command, .shift]))
  }
}
