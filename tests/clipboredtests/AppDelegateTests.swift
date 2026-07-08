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
        "New Collection",
        "Stack Capture",
        settingsTitle,
        "-",
        "Pause Capture",
        "Pause for 5 Minutes",
        "Pause for 30 Minutes",
        "Pause for 1 Hour",
        "-",
        "Quit ClipBored"
      ]
    )

    let showClipboard = menu.items.first { $0.title == "Show Clipboard" }
    XCTAssertEqual(showClipboard?.keyEquivalent, "v")
    XCTAssertTrue(showClipboard?.keyEquivalentModifierMask.contains(.command) == true)
    XCTAssertTrue(showClipboard?.keyEquivalentModifierMask.contains(.option) == true)

    XCTAssertNil(menu.items.first { $0.title == "New Text Clip" })

    let newCollection = menu.items.first { $0.title == "New Collection" }
    XCTAssertEqual(newCollection?.keyEquivalent, "n")
    XCTAssertTrue(newCollection?.keyEquivalentModifierMask.contains(.command) == true)
    XCTAssertTrue(newCollection?.keyEquivalentModifierMask.contains(.shift) == true)

    let stackCapture = menu.items.first { $0.title == "Stack Capture" }
    XCTAssertEqual(stackCapture?.keyEquivalent, "c")
    XCTAssertTrue(stackCapture?.keyEquivalentModifierMask.contains(.command) == true)
    XCTAssertTrue(stackCapture?.keyEquivalentModifierMask.contains(.shift) == true)

    let settings = menu.items.first { $0.title == settingsTitle }
    XCTAssertEqual(settings?.keyEquivalent, ",")
    XCTAssertTrue(settings?.keyEquivalentModifierMask.contains(.command) == true)

    let pauseCapture = menu.items.first { $0.title == "Pause Capture" }
    XCTAssertEqual(pauseCapture?.keyEquivalent, "t")
    XCTAssertTrue(pauseCapture?.keyEquivalentModifierMask.contains(.command) == true)
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
    let resumeCapture = menu.items.first { $0.title == "Resume Capture" }
    XCTAssertEqual(resumeCapture?.state, .on)
    XCTAssertEqual(resumeCapture?.keyEquivalent, "t")
    XCTAssertTrue(resumeCapture?.keyEquivalentModifierMask.contains(.command) == true)
    XCTAssertNil(menu.items.first { $0.title == "Pause Capture" })
    XCTAssertNil(menu.items.first { $0.title == "Pause for 5 Minutes" })
  }

  func testStatusMenuPresentationShowsTimedPauseRemainingBeforeOlderStatuses() {
    let now = Date(timeIntervalSince1970: 1_000)
    let presentation = AppDelegate.statusMenuPresentation(
      historyCount: 12,
      isCapturePaused: true,
      pauseCaptureUntil: now.addingTimeInterval(5 * 60),
      now: now,
      captureStatus: "Captured text from Safari.",
      pasteStatus: "",
      shortcutStatus: "",
      accessibilityStatus: "",
      launchAtLoginStatus: ""
    )

    XCTAssertEqual(presentation.summary, "Capture Paused - 12 clips")
    XCTAssertEqual(presentation.detail, "Capture is paused for 5 more minutes.")
  }

  func testCapturePauseExpiryOnlyAppliesToExpiredTimedPauses() {
    let now = Date(timeIntervalSince1970: 1_000)

    XCTAssertTrue(AppDelegate.shouldResumeExpiredCapturePause(
      isCapturePaused: true,
      pauseCaptureUntil: now,
      now: now
    ))
    XCTAssertFalse(AppDelegate.shouldResumeExpiredCapturePause(
      isCapturePaused: true,
      pauseCaptureUntil: now.addingTimeInterval(1),
      now: now
    ))
    XCTAssertFalse(AppDelegate.shouldResumeExpiredCapturePause(
      isCapturePaused: false,
      pauseCaptureUntil: now.addingTimeInterval(-1),
      now: now
    ))
    XCTAssertFalse(AppDelegate.shouldResumeExpiredCapturePause(
      isCapturePaused: true,
      pauseCaptureUntil: nil,
      now: now
    ))
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
