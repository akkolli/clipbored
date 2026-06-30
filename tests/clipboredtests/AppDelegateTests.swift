import AppKit
import XCTest
@testable import ClipBored

final class AppDelegateTests: XCTestCase {
  func testPresentationPlanMapsDockPreferenceToActivationPolicy() {
    let dockless = AppDelegate.presentationPlan(
      showMenuBarIcon: true,
      showDockIcon: false,
      changedSurface: nil
    )
    XCTAssertTrue(dockless.showMenuBarIcon)
    XCTAssertFalse(dockless.showDockIcon)
    XCTAssertEqual(dockless.activationPolicy, .accessory)

    let dockVisible = AppDelegate.presentationPlan(
      showMenuBarIcon: true,
      showDockIcon: true,
      changedSurface: nil
    )
    XCTAssertTrue(dockVisible.showMenuBarIcon)
    XCTAssertTrue(dockVisible.showDockIcon)
    XCTAssertEqual(dockVisible.activationPolicy, .regular)
  }

  func testPresentationPlanKeepsOneVisibleEntryPoint() {
    let hidingMenuBar = AppDelegate.presentationPlan(
      showMenuBarIcon: false,
      showDockIcon: false,
      changedSurface: .menuBar
    )
    XCTAssertFalse(hidingMenuBar.showMenuBarIcon)
    XCTAssertTrue(hidingMenuBar.showDockIcon)
    XCTAssertEqual(hidingMenuBar.activationPolicy, .regular)

    let hidingDock = AppDelegate.presentationPlan(
      showMenuBarIcon: false,
      showDockIcon: false,
      changedSurface: .dock
    )
    XCTAssertTrue(hidingDock.showMenuBarIcon)
    XCTAssertFalse(hidingDock.showDockIcon)
    XCTAssertEqual(hidingDock.activationPolicy, .accessory)
  }

  func testStatusItemMenuRoutingSeparatesLeftAndRightClick() {
    XCTAssertFalse(AppDelegate.shouldOpenStatusMenu(eventType: .leftMouseUp, modifierFlags: []))
    XCTAssertTrue(AppDelegate.shouldOpenStatusMenu(eventType: .rightMouseUp, modifierFlags: []))
    XCTAssertTrue(AppDelegate.shouldOpenStatusMenu(eventType: .leftMouseUp, modifierFlags: .control))
    XCTAssertTrue(AppDelegate.shouldOpenStatusMenu(eventType: .otherMouseUp, modifierFlags: []))
    XCTAssertFalse(AppDelegate.shouldOpenStatusMenu(eventType: .leftMouseDragged, modifierFlags: .control))
  }

  func testStatusMenuIncludesStateRowsAndBoundedActions() {
    let settingsTitle = "Settings\u{2026}"
    let presentation = AppDelegate.statusMenuPresentation(
      historyCount: 42,
      isCapturePaused: false,
      captureStatus: "Captured text from Safari.",
      pasteStatus: "",
      shortcutStatus: "",
      accessibilityStatus: "",
      launchAtLoginStatus: ""
    )
    let menu = AppDelegate.makeStatusMenu(
      presentation: presentation,
      isCapturePaused: false,
      openShortcut: AppConfiguration.defaultOpenShortcut,
      settingsShortcut: AppConfiguration.defaultSettingsShortcut,
      target: nil
    )

    XCTAssertEqual(
      menu.items.map { $0.isSeparatorItem ? "-" : $0.title },
      [
        "ClipBored",
        "Capture Running - 42 clips",
        "Captured text from Safari.",
        "-",
        "Show Clipboard",
        settingsTitle,
        "-",
        "Pause Capture",
        "-",
        "Quit ClipBored"
      ]
    )

    let showClipboard = menu.items.first { $0.title == "Show Clipboard" }
    XCTAssertEqual(showClipboard?.keyEquivalent, "v")
    XCTAssertTrue(showClipboard?.keyEquivalentModifierMask.contains(.command) == true)
    XCTAssertTrue(showClipboard?.keyEquivalentModifierMask.contains(.option) == true)

    let settings = menu.items.first { $0.title == settingsTitle }
    XCTAssertEqual(settings?.keyEquivalent, ",")
    XCTAssertTrue(settings?.keyEquivalentModifierMask.contains(.command) == true)
  }

  func testStatusMenuPausedStateTakesPriorityOverOlderCaptureStatus() {
    let presentation = AppDelegate.statusMenuPresentation(
      historyCount: 1,
      isCapturePaused: true,
      captureStatus: "Captured link from Safari.",
      pasteStatus: "Copied",
      shortcutStatus: "",
      accessibilityStatus: "",
      launchAtLoginStatus: ""
    )
    let menu = AppDelegate.makeStatusMenu(
      presentation: presentation,
      isCapturePaused: true,
      openShortcut: AppConfiguration.defaultOpenShortcut,
      settingsShortcut: AppConfiguration.defaultSettingsShortcut,
      target: nil
    )

    XCTAssertEqual(presentation.summary, "Capture Paused - 1 clip")
    XCTAssertEqual(presentation.detail, "Capture is paused.")
    XCTAssertEqual(menu.items.first { $0.title == "Resume Capture" }?.state, .on)
    XCTAssertNil(menu.items.first { $0.title == "Pause Capture" })
  }

  func testStatusMenuPresentationTruncatesLongStatusText() {
    let presentation = AppDelegate.statusMenuPresentation(
      historyCount: 2000,
      isCapturePaused: false,
      captureStatus: "Skipped:\n" + String(repeating: "A very long ignored source application name ", count: 4),
      pasteStatus: "",
      shortcutStatus: "",
      accessibilityStatus: "",
      launchAtLoginStatus: ""
    )

    XCTAssertEqual(presentation.summary, "Capture Running - 2000 clips")
    XCTAssertNotNil(presentation.detail)
    XCTAssertLessThanOrEqual(presentation.detail?.count ?? 0, 68)
    XCTAssertTrue(presentation.detail?.hasSuffix("...") == true)
    XCTAssertFalse(presentation.detail?.contains("\n") == true)
  }
}
