import AppKit
import XCTest
@testable import ClipBored

final class SettingsPresentationTests: XCTestCase {
  func testPasteAndDataStatusColors() {
    let pasteCases: [(String, NSColor)] = [
      ("", .secondaryLabelColor),
      ("Pasted", .systemGreen),
      ("Copied. Grant Accessibility access to paste automatically.", .systemOrange),
      ("Could not write item to clipboard.", .systemRed)
    ]
    for (message, color) in pasteCases {
      XCTAssertEqual(SettingsWindowController.pasteStatusPresentation(storedStatus: message).textColor, color)
    }

    let dataCases: [(String, NSColor)] = [
      ("", .secondaryLabelColor),
      ("Exported 3 clips.", .systemGreen),
      ("Imported 3 clips. Skipped 1 clip.", .systemOrange),
      ("The archive couldn't be opened.", .systemRed)
    ]
    for (message, color) in dataCases {
      XCTAssertEqual(SettingsWindowController.dataStatusPresentation(storedStatus: message).textColor, color)
    }
  }

  func testCaptureStatusColors() {
    let cases: [(String, NSColor)] = [
      ("", .secondaryLabelColor),
      ("Captured text from Safari.", .systemGreen),
      ("Skipped: Audio items are ignored.", .systemOrange),
      ("At least one content type must stay enabled.", .systemOrange),
      ("Error: Clipboard read failed.", .systemRed)
    ]
    for (message, color) in cases {
      XCTAssertEqual(SettingsWindowController.captureStatusPresentation(storedStatus: message).textColor, color)
    }
  }

  func testShortcutPermissionAndLifecycleStatusColors() {
    XCTAssertEqual(
      SettingsWindowController.shortcutStatusPresentation(storedStatus: "").textColor,
      .systemGreen
    )
    XCTAssertEqual(
      SettingsWindowController.shortcutStatusPresentation(storedStatus: "Unsupported shortcut").textColor,
      .systemRed
    )
    XCTAssertEqual(
      SettingsWindowController.accessibilityPermissionStatusPresentation(
        storedStatus: "",
        isTrusted: true
      ).textColor,
      .systemGreen
    )
    XCTAssertEqual(
      SettingsWindowController.accessibilityPermissionStatusPresentation(
        storedStatus: "Permission not granted",
        isTrusted: true
      ).textColor,
      .systemOrange
    )
    XCTAssertEqual(
      SettingsWindowController.launchAtLoginStatusPresentation(storedStatus: "Service unavailable").textColor,
      .systemRed
    )
  }

  func testCloudSyncStatusPrecedence() {
    let ready = ClipboardCloudSyncStatus(
      isAvailable: true,
      archiveURL: nil,
      lastModifiedAt: nil,
      message: "iCloud is ready."
    )
    let unavailable = ClipboardCloudSyncStatus(
      isAvailable: false,
      archiveURL: nil,
      lastModifiedAt: nil,
      message: "iCloud is unavailable."
    )

    XCTAssertEqual(
      SettingsWindowController.cloudSyncStatusPresentation(
        storedStatus: "",
        isSyncEnabled: false,
        cloudStatus: ready
      ).message,
      "iCloud Sync is off."
    )
    XCTAssertEqual(
      SettingsWindowController.cloudSyncStatusPresentation(
        storedStatus: "",
        isSyncEnabled: true,
        cloudStatus: unavailable
      ).textColor,
      .systemOrange
    )
    XCTAssertEqual(
      SettingsWindowController.cloudSyncStatusPresentation(
        storedStatus: "Synced 3 clips.",
        isSyncEnabled: true,
        cloudStatus: ready
      ).textColor,
      .systemGreen
    )
    XCTAssertEqual(
      SettingsWindowController.cloudSyncStatusPresentation(
        storedStatus: "iCloud Sync failed.",
        isSyncEnabled: true,
        cloudStatus: ready
      ).textColor,
      .systemRed
    )
  }
}
