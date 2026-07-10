import AppKit
import XCTest
@testable import ClipBored

final class OnboardingWindowControllerTests: XCTestCase {
  func testPasteStyleShortcutUsesShiftCommandV() {
    let shortcut = OnboardingWindowController.pasteStyleOpenShortcut

    XCTAssertEqual(shortcut.key, "v")
    XCTAssertTrue(shortcut.has(.command))
    XCTAssertTrue(shortcut.has(.shift))
    XCTAssertFalse(shortcut.has(.option))
    XCTAssertFalse(shortcut.has(.control))
  }

  func testFreshDefaultShortcutStartsWithPasteStyleChoice() {
    let choice = OnboardingWindowController.initialShortcutChoice(
      for: AppConfiguration.defaultOpenShortcut,
      onboardingCompleted: false
    )

    XCTAssertEqual(choice, .pasteStyle)
  }

  func testCompletedDefaultShortcutKeepsClipBoredDefaultChoice() {
    let choice = OnboardingWindowController.initialShortcutChoice(
      for: AppConfiguration.defaultOpenShortcut,
      onboardingCompleted: true
    )

    XCTAssertEqual(choice, .clipBoredDefault)
  }

  func testPresentationChoiceKeepsAVisibleEntryPoint() {
    let presentation = OnboardingWindowController.normalizedPresentation(
      showMenuBarIcon: false,
      showDockIcon: false
    )

    XCTAssertTrue(presentation.showMenuBarIcon)
    XCTAssertFalse(presentation.showDockIcon)
  }

  func testPresentationChoicePreservesExplicitDockOnlySetup() {
    let presentation = OnboardingWindowController.normalizedPresentation(
      showMenuBarIcon: false,
      showDockIcon: true
    )

    XCTAssertFalse(presentation.showMenuBarIcon)
    XCTAssertTrue(presentation.showDockIcon)
  }

}
