import AppKit
import XCTest
@testable import ClipBored

final class SettingsWindowControllerTests: XCTestCase {
  private var tempURLs: [URL] = []
  private var defaultsSuites: [String] = []

  override func tearDown() {
    tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    for suite in defaultsSuites {
      UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
    tempURLs.removeAll()
    defaultsSuites.removeAll()
    super.tearDown()
  }

  func testSettingsWindowIsResizableWithPracticalMinimumSize() {
    let (controller, _) = makeController()

    XCTAssertTrue(controller.debugWindowStyleMask.contains(.resizable))
    XCTAssertEqual(controller.debugWindowMinSize.width, 560, accuracy: 0.5)
    XCTAssertEqual(controller.debugWindowMinSize.height, 440, accuracy: 0.5)
    XCTAssertGreaterThanOrEqual(controller.debugWindowContentSize.width, 600)
    XCTAssertGreaterThanOrEqual(controller.debugWindowContentSize.height, 500)
  }

  func testSettingsTabsUsePinnedScrollableDocuments() {
    let (controller, _) = makeController()
    let metrics = controller.debugSettingsTabLayoutMetrics

    XCTAssertEqual(metrics.map { $0.label }, ["General", "Shortcuts", "Capture", "Privacy", "Performance", "Data"])
    for metric in metrics {
      XCTAssertGreaterThan(metric.viewport.width, 0, metric.label)
      XCTAssertGreaterThan(metric.viewport.height, 0, metric.label)
      XCTAssertEqual(metric.document.width, metric.viewport.width, accuracy: 1, metric.label)
      XCTAssertGreaterThan(metric.document.height, 0, metric.label)
      XCTAssertFalse(metric.hasHorizontalScroller, metric.label)
    }
  }

  func testSettingsTabsUseUnpaddedLabelsWithCustomSelector() {
    let (controller, _) = makeController()

    XCTAssertEqual(controller.debugSettingsTabLayoutMetrics.map { $0.label }, ["General", "Shortcuts", "Capture", "Privacy", "Performance", "Data"])
    XCTAssertEqual(controller.debugRawSettingsTabLabels.last?.clipboardTrimmed, "Data")
    XCTAssertEqual(controller.debugRawSettingsTabLabels.last, "Data")
  }

  func testSettingsTabsKeepContentAnchoredToTopLeadingCorner() {
    let (controller, _) = makeController()
    let metrics = controller.debugSettingsTabContentPlacementMetrics

    XCTAssertEqual(metrics.map { $0.label }, ["General", "Shortcuts", "Capture", "Privacy", "Performance", "Data"])
    for metric in metrics {
      XCTAssertGreaterThan(metric.contentBounds.width, 0, metric.label)
      XCTAssertGreaterThan(metric.contentBounds.height, 0, metric.label)
      XCTAssertLessThanOrEqual(metric.contentBounds.minX, 40, metric.label)
      XCTAssertLessThanOrEqual(metric.contentBounds.minY, 40, metric.label)
      XCTAssertLessThanOrEqual(metric.contentBounds.maxX, metric.document.width + 1, metric.label)
    }
  }

  func testSettingsTabsAvoidHorizontalOverflowAtMinimumWindowSize() {
    let (controller, _) = makeController()
    controller.debugSetWindowContentSize(NSSize(width: 560, height: 440))

    let metrics = controller.debugSettingsTabLayoutAuditMetrics

    XCTAssertEqual(metrics.map { $0.label }, ["General", "Shortcuts", "Capture", "Privacy", "Performance", "Data"])
    for metric in metrics {
      XCTAssertEqual(metric.overflowingViewCount, 0, metric.label)
      XCTAssertEqual(metric.zeroSizedControlCount, 0, metric.label)
    }
  }

  func testSettingsGeneralTabUsesCompactVerticalLayout() {
    let (controller, _) = makeController()
    let metrics = controller.debugSettingsTabContentPlacementMetrics
    let general = try! XCTUnwrap(metrics.first { $0.label == "General" })

    XCTAssertLessThan(general.contentBounds.maxY, 380)
  }

  func testShortcutModifiersExposeHumanAccessibilityNames() {
    let (controller, _) = makeController()

    XCTAssertEqual(
      controller.debugOpenShortcutModifierAccessibilityLabels,
      ["Command modifier", "Option modifier", "Control modifier", "Shift modifier"]
    )
    XCTAssertEqual(
      controller.debugOpenShortcutModifierAccessibilityHelps,
      [
        "Include or remove the Command key from this shortcut.",
        "Include or remove the Option key from this shortcut.",
        "Include or remove the Control key from this shortcut.",
        "Include or remove the Shift key from this shortcut."
      ]
    )
  }

  func testWritesSettingsVisualSnapshotWhenRequested() throws {
    guard ProcessInfo.processInfo.environment["CLIPBORED_WRITE_SETTINGS_SNAPSHOT"] == "1" else {
      throw XCTSkip("Set CLIPBORED_WRITE_SETTINGS_SNAPSHOT=1 to write a Settings snapshot.")
    }

    let (controller, _) = makeController()
    controller.debugSelectSettingsTab(at: 5)
    controller.debugPrepareWindowForSnapshot()
    drainMainQueue()
    let view = try XCTUnwrap(controller.debugSettingsContentView)
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()

    let output = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["CLIPBORED_SETTINGS_SNAPSHOT_PATH"]
        ?? "build/visual-snapshots/settings-data.png"
    )
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: output)
  }

  func testCloudSyncStatusIsCachedAcrossUnrelatedSettingsRefreshes() {
    let cloudSyncService = CloudSyncProbe(
      status: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )
    let (controller, settings) = makeController(cloudSyncService: cloudSyncService)

    XCTAssertEqual(controller.debugCloudSyncStatusText, "iCloud Sync is off.")
    XCTAssertEqual(controller.debugCloudSyncActionButtonsAreEnabled, [false, false, false])
    XCTAssertEqual(cloudSyncService.statusCallCount, 0)

    settings.iCloudSyncEnabled = true
    drainMainQueue()

    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugCloudSyncStatusText, "Probe iCloud ready")
    XCTAssertEqual(controller.debugCloudSyncActionButtonsAreEnabled, [true, true, true])

    settings.maxHistoryItems += 25
    settings.setPasteStatus(message: "Pasted latest clip")
    drainMainQueue()

    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugCloudSyncStatusText, "Probe iCloud ready")

    settings.setCloudSyncStatus(message: "Synced 3 clips and 1 attachment to iCloud.")
    drainMainQueue()

    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugCloudSyncStatusText, "Synced 3 clips and 1 attachment to iCloud.")

    settings.setCloudSyncStatus(message: "")
    drainMainQueue()

    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugCloudSyncStatusText, "Probe iCloud ready")
  }

  func testTurningCloudSyncOffClearsStaleActionStatus() {
    let cloudSyncService = CloudSyncProbe(
      status: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )
    let (controller, settings) = makeController(cloudSyncService: cloudSyncService)
    let initialFullRefreshCount = controller.debugFullRefreshCount

    controller.debugSetICloudSyncEnabled(true)
    drainMainQueue()

    XCTAssertTrue(settings.iCloudSyncEnabled)
    XCTAssertEqual(controller.debugCloudSyncStatusText, "Probe iCloud ready")
    XCTAssertEqual(cloudSyncService.statusCallCount, 1)

    settings.setCloudSyncStatus(message: "Synced 3 clips and 1 attachment to iCloud.")
    drainMainQueue()

    XCTAssertEqual(controller.debugCloudSyncStatusText, "Synced 3 clips and 1 attachment to iCloud.")

    controller.debugSetICloudSyncEnabled(false)
    drainMainQueue()

    XCTAssertFalse(settings.iCloudSyncEnabled)
    XCTAssertEqual(settings.cloudSyncStatusMessage, "")
    XCTAssertEqual(controller.debugCloudSyncStatusText, "iCloud Sync is off.")
    XCTAssertEqual(controller.debugCloudSyncActionButtonsAreEnabled, [false, false, false])
    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testCloudSyncActionsStayDisabledWhenSyncIsUnavailable() {
    let cloudSyncService = CloudSyncProbe(
      status: ClipboardCloudSyncStatus(
        isAvailable: false,
        archiveURL: nil,
        lastModifiedAt: nil,
        message: "Probe iCloud unavailable"
      )
    )
    let (controller, settings) = makeController(cloudSyncService: cloudSyncService)
    let initialFullRefreshCount = controller.debugFullRefreshCount

    XCTAssertEqual(controller.debugCloudSyncActionButtonsAreEnabled, [false, false, false])

    settings.iCloudSyncEnabled = true
    drainMainQueue()

    XCTAssertTrue(settings.iCloudSyncEnabled)
    XCTAssertEqual(controller.debugCloudSyncStatusText, "Probe iCloud unavailable")
    XCTAssertEqual(controller.debugCloudSyncActionButtonsAreEnabled, [false, false, false])
    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testCloudSyncStatusPresentationUsesErrorColorForFailedActionMessages() {
    let failed = SettingsWindowController.cloudSyncStatusPresentation(
      storedStatus: "iCloud Sync failed: No ClipBored iCloud archive has been created yet.",
      isSyncEnabled: true,
      cloudStatus: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )

    XCTAssertEqual(failed.message, "iCloud Sync failed: No ClipBored iCloud archive has been created yet.")
    XCTAssertEqual(failed.textColor, .systemRed)

    let unavailable = SettingsWindowController.cloudSyncStatusPresentation(
      storedStatus: "",
      isSyncEnabled: true,
      cloudStatus: ClipboardCloudSyncStatus(
        isAvailable: false,
        archiveURL: nil,
        lastModifiedAt: nil,
        message: "Probe iCloud unavailable"
      )
    )

    XCTAssertEqual(unavailable.message, "Probe iCloud unavailable")
    XCTAssertEqual(unavailable.textColor, .systemOrange)

    let synced = SettingsWindowController.cloudSyncStatusPresentation(
      storedStatus: "Synced 3 clips and 1 attachment to iCloud.",
      isSyncEnabled: true,
      cloudStatus: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )

    XCTAssertEqual(synced.message, "Synced 3 clips and 1 attachment to iCloud.")
    XCTAssertEqual(synced.textColor, .systemGreen)

    let opened = SettingsWindowController.cloudSyncStatusPresentation(
      storedStatus: "Opened iCloud sync location.",
      isSyncEnabled: true,
      cloudStatus: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )

    XCTAssertEqual(opened.message, "Opened iCloud sync location.")
    XCTAssertEqual(opened.textColor, .systemGreen)

    let restoredWithSkips = SettingsWindowController.cloudSyncStatusPresentation(
      storedStatus: "Restored 3 clips and 1 attachment from iCloud. Skipped 1 clip and 0 attachments.",
      isSyncEnabled: true,
      cloudStatus: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )

    XCTAssertEqual(
      restoredWithSkips.message,
      "Restored 3 clips and 1 attachment from iCloud. Skipped 1 clip and 0 attachments."
    )
    XCTAssertEqual(restoredWithSkips.textColor, .systemOrange)

    let off = SettingsWindowController.cloudSyncStatusPresentation(
      storedStatus: "",
      isSyncEnabled: false,
      cloudStatus: nil
    )

    XCTAssertEqual(off.message, "iCloud Sync is off.")
    XCTAssertEqual(off.textColor, .secondaryLabelColor)
  }

  func testExternalCloudSyncDisableShowsOffStateInsteadOfStaleStatus() {
    let cloudSyncService = CloudSyncProbe(
      status: ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: makeTempDirectory().appendingPathComponent("ClipBored.clipboredarchive"),
        lastModifiedAt: nil,
        message: "Probe iCloud ready"
      )
    )
    let (controller, settings) = makeController(cloudSyncService: cloudSyncService)
    let initialFullRefreshCount = controller.debugFullRefreshCount

    settings.iCloudSyncEnabled = true
    drainMainQueue()

    XCTAssertEqual(controller.debugCloudSyncStatusText, "Probe iCloud ready")
    XCTAssertEqual(cloudSyncService.statusCallCount, 1)

    settings.setCloudSyncStatus(message: "Synced 3 clips and 1 attachment to iCloud.")
    drainMainQueue()

    XCTAssertEqual(controller.debugCloudSyncStatusText, "Synced 3 clips and 1 attachment to iCloud.")

    settings.iCloudSyncEnabled = false
    drainMainQueue()

    XCTAssertEqual(settings.cloudSyncStatusMessage, "")
    XCTAssertEqual(controller.debugCloudSyncStatusText, "iCloud Sync is off.")
    XCTAssertEqual(cloudSyncService.statusCallCount, 1)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testIgnoredAppsEditorPreservesDraftTextWhileFocused() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount
    settings.ignoredApps = ["Safari", "Xcode"]
    drainMainQueue()

    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari, Xcode")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertGreaterThan(controller.debugIgnoredAppsRefreshCount, 0)

    XCTAssertTrue(controller.debugFocusIgnoredAppsEditor())
    XCTAssertTrue(controller.debugIgnoredAppsEditorIsFocused)

    let focusedFullRefreshCount = controller.debugFullRefreshCount
    let focusedIgnoredAppsRefreshCount = controller.debugIgnoredAppsRefreshCount
    controller.debugSetIgnoredAppsText("Safari,\nXcode, Terminal, ")
    drainMainQueue()

    XCTAssertEqual(settings.ignoredApps, ["Safari", "Xcode"])
    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari,\nXcode, Terminal, ")
    XCTAssertEqual(controller.debugFullRefreshCount, focusedFullRefreshCount)
    XCTAssertEqual(controller.debugIgnoredAppsRefreshCount, focusedIgnoredAppsRefreshCount)

    settings.maxHistoryItems += 25
    settings.setPasteStatus(message: "Pasted latest clip")
    drainMainQueue()

    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari,\nXcode, Terminal, ")

    controller.debugEndIgnoredAppsEditing()
    drainMainQueue()

    XCTAssertEqual(settings.ignoredApps, ["Safari", "Xcode", "Terminal"])
    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari, Xcode, Terminal")
  }

  func testFocusedIgnoredAppsEditorWithoutDraftDoesNotOverwriteExternalChanges() {
    let (controller, settings) = makeController()
    settings.ignoredApps = ["Safari"]
    drainMainQueue()
    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari")

    XCTAssertTrue(controller.debugFocusIgnoredAppsEditor())

    settings.ignoredApps = ["Xcode", "Terminal"]
    drainMainQueue()

    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari")
    XCTAssertEqual(settings.ignoredApps, ["Xcode", "Terminal"])

    controller.debugEndIgnoredAppsEditing()
    drainMainQueue()

    XCTAssertEqual(controller.debugIgnoredAppsText, "Xcode, Terminal")
    XCTAssertEqual(settings.ignoredApps, ["Xcode", "Terminal"])
  }

  func testClosingSettingsWindowCommitsFocusedIgnoredAppsDraft() {
    let (controller, settings) = makeController()
    settings.ignoredApps = ["Safari"]
    drainMainQueue()

    XCTAssertTrue(controller.debugFocusIgnoredAppsEditor())
    controller.debugSetIgnoredAppsText("Safari, Xcode, Terminal")
    drainMainQueue()

    XCTAssertEqual(settings.ignoredApps, ["Safari"])
    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari, Xcode, Terminal")

    controller.debugCloseWindow()
    drainMainQueue()

    XCTAssertEqual(settings.ignoredApps, ["Safari", "Xcode", "Terminal"])
    XCTAssertEqual(controller.debugIgnoredAppsText, "Safari, Xcode, Terminal")
  }

  func testNarrowSettingsChangesAvoidFullWindowRefresh() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    settings.maxHistoryItems = 75
    drainMainQueue()

    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertEqual(controller.debugHistoryText, "History length: 75")

    settings.imageCacheMaxBytes = 128 * 1024 * 1024
    drainMainQueue()

    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertEqual(controller.debugCacheStatusText, "Current cache cap: 128 MB")

    settings.setPasteStatus(message: "Pasted latest clip")
    drainMainQueue()

    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertEqual(controller.debugPasteStatusText, "Pasted latest clip")
  }

  func testLimitControlsRefreshToClampedStoredValues() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount
    let minCacheMegabytes = Int(AppConfiguration.minCacheMaxBytes / 1024 / 1024)
    let maxCacheMegabytes = Int(AppConfiguration.maxCacheMaxBytes / 1024 / 1024)

    controller.debugSetHistoryStepperValue(AppConfiguration.minHistoryLength - 25)
    drainMainQueue()

    XCTAssertEqual(settings.maxHistoryItems, AppConfiguration.minHistoryLength)
    XCTAssertEqual(controller.debugHistoryText, "History length: \(AppConfiguration.minHistoryLength)")
    XCTAssertEqual(controller.debugHistoryStepperValue, AppConfiguration.minHistoryLength)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetHistoryStepperValue(AppConfiguration.maxHistoryLength + 25)
    drainMainQueue()

    XCTAssertEqual(settings.maxHistoryItems, AppConfiguration.maxHistoryLength)
    XCTAssertEqual(controller.debugHistoryText, "History length: \(AppConfiguration.maxHistoryLength)")
    XCTAssertEqual(controller.debugHistoryStepperValue, AppConfiguration.maxHistoryLength)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetCacheSliderMegabytes(minCacheMegabytes - 2)
    drainMainQueue()

    XCTAssertEqual(settings.imageCacheMaxBytes, AppConfiguration.minCacheMaxBytes)
    XCTAssertEqual(controller.debugCacheStatusText, "Current cache cap: \(minCacheMegabytes) MB")
    XCTAssertEqual(controller.debugCacheSliderMegabytes, minCacheMegabytes)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetCacheSliderMegabytes(maxCacheMegabytes + 128)
    drainMainQueue()

    XCTAssertEqual(settings.imageCacheMaxBytes, AppConfiguration.maxCacheMaxBytes)
    XCTAssertEqual(controller.debugCacheStatusText, "Current cache cap: \(maxCacheMegabytes) MB")
    XCTAssertEqual(controller.debugCacheSliderMegabytes, maxCacheMegabytes)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testStatusLabelsWrapLongMessagesInsteadOfTruncating() {
    let (controller, settings) = makeController()
    let longMessage = "Copied 12 selected clips as Text. Grant Accessibility access in System Settings to paste automatically into the previous application."

    settings.setPasteStatus(message: longMessage)
    drainMainQueue()

    XCTAssertEqual(controller.debugPasteStatusText, longMessage)
    XCTAssertTrue(controller.debugStatusLabelsAllowWrapping)
  }

  func testPasteStatusPresentationUsesSuccessWarningAndErrorColors() {
    let idle = SettingsWindowController.pasteStatusPresentation(storedStatus: "")

    XCTAssertEqual(idle.message, "No paste action yet.")
    XCTAssertEqual(idle.textColor, .secondaryLabelColor)

    let pasted = SettingsWindowController.pasteStatusPresentation(storedStatus: "Pasted")

    XCTAssertEqual(pasted.message, "Pasted")
    XCTAssertEqual(pasted.textColor, .systemGreen)

    let copiedNeedsPermission = SettingsWindowController.pasteStatusPresentation(
      storedStatus: "Copied. Grant Accessibility access to paste automatically."
    )

    XCTAssertEqual(copiedNeedsPermission.message, "Copied. Grant Accessibility access to paste automatically.")
    XCTAssertEqual(copiedNeedsPermission.textColor, .systemOrange)

    let failed = SettingsWindowController.pasteStatusPresentation(
      storedStatus: "Could not write item to clipboard."
    )

    XCTAssertEqual(failed.message, "Could not write item to clipboard.")
    XCTAssertEqual(failed.textColor, .systemRed)
  }

  func testDataStatusPresentationUsesSuccessWarningAndErrorColors() {
    let idle = SettingsWindowController.dataStatusPresentation(storedStatus: "")

    XCTAssertEqual(idle.message, "")
    XCTAssertEqual(idle.textColor, .secondaryLabelColor)

    let exported = SettingsWindowController.dataStatusPresentation(
      storedStatus: "Exported 3 clips and 1 attachments."
    )

    XCTAssertEqual(exported.message, "Exported 3 clips and 1 attachments.")
    XCTAssertEqual(exported.textColor, .systemGreen)

    let cleared = SettingsWindowController.dataStatusPresentation(
      storedStatus: "Cleared thumbnail cache."
    )

    XCTAssertEqual(cleared.message, "Cleared thumbnail cache.")
    XCTAssertEqual(cleared.textColor, .systemGreen)

    let partialImport = SettingsWindowController.dataStatusPresentation(
      storedStatus: "Imported 3 clips and 1 attachments. Skipped 1 clips and 0 attachments."
    )

    XCTAssertEqual(
      partialImport.message,
      "Imported 3 clips and 1 attachments. Skipped 1 clips and 0 attachments."
    )
    XCTAssertEqual(partialImport.textColor, .systemOrange)

    let failed = SettingsWindowController.dataStatusPresentation(
      storedStatus: "The archive couldn't be opened."
    )

    XCTAssertEqual(failed.message, "The archive couldn't be opened.")
    XCTAssertEqual(failed.textColor, .systemRed)
  }

  func testDestructiveDataActionsShowSuccessStatus() {
    let fixture = makeControllerFixture()
    fixture.store.upsert(makeItem("saved clip", displayText: "Saved Clip", created: Date()))

    XCTAssertEqual(fixture.store.items.count, 1)
    XCTAssertEqual(fixture.controller.debugDataStatusText, "")
    XCTAssertEqual(fixture.controller.debugDataStatusSectionTitle, "Data")

    fixture.controller.debugSetDestructiveActionConfirmation(true)
    fixture.controller.debugClearClipboardHistory()

    XCTAssertTrue(fixture.store.items.isEmpty)
    XCTAssertEqual(fixture.controller.debugDataStatusText, "Cleared clipboard history.")
    XCTAssertEqual(fixture.controller.debugDataStatusColor, .systemGreen)

    fixture.controller.debugClearThumbnailCache()

    XCTAssertEqual(fixture.controller.debugDataStatusText, "Cleared thumbnail cache.")
    XCTAssertEqual(fixture.controller.debugDataStatusColor, .systemGreen)
  }

  func testCaptureStatusPresentationUsesReadyWarningAndErrorColors() {
    let idle = SettingsWindowController.captureStatusPresentation(storedStatus: "")

    XCTAssertEqual(idle.message, "Capture status will appear after the app sees clipboard activity.")
    XCTAssertEqual(idle.textColor, .secondaryLabelColor)

    let captured = SettingsWindowController.captureStatusPresentation(
      storedStatus: "Captured text from Safari."
    )

    XCTAssertEqual(captured.message, "Captured text from Safari.")
    XCTAssertEqual(captured.textColor, .systemGreen)

    let skipped = SettingsWindowController.captureStatusPresentation(
      storedStatus: "Skipped: Audio items are ignored in capture settings."
    )

    XCTAssertEqual(skipped.message, "Skipped: Audio items are ignored in capture settings.")
    XCTAssertEqual(skipped.textColor, .systemOrange)

    let validationWarning = SettingsWindowController.captureStatusPresentation(
      storedStatus: "At least one content type must stay enabled."
    )

    XCTAssertEqual(validationWarning.message, "At least one content type must stay enabled.")
    XCTAssertEqual(validationWarning.textColor, .systemOrange)

    let error = SettingsWindowController.captureStatusPresentation(
      storedStatus: "Error: Clipboard read failed."
    )

    XCTAssertEqual(error.message, "Error: Clipboard read failed.")
    XCTAssertEqual(error.textColor, .systemRed)
  }

  func testAccessibilityPermissionRefreshAvoidsFullWindowRefresh() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    settings.setAccessibilityPermissionStatus(message: "Accessibility permission not granted.")
    drainMainQueue()

    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertEqual(controller.debugAccessibilityStatusText, "Accessibility permission not granted.")

    controller.debugRefreshAccessibilityPermissionStatus()
    drainMainQueue()

    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertFalse(controller.debugAccessibilityStatusText.isEmpty)
  }

  func testStoredAccessibilityWarningUsesWarningColorEvenWhenPermissionIsGranted() {
    let warning = SettingsWindowController.accessibilityPermissionStatusPresentation(
      storedStatus: "Accessibility permission not granted.",
      isTrusted: true
    )

    XCTAssertEqual(warning.message, "Accessibility permission not granted.")
    XCTAssertEqual(warning.textColor, .systemOrange)

    let granted = SettingsWindowController.accessibilityPermissionStatusPresentation(
      storedStatus: "",
      isTrusted: true
    )

    XCTAssertEqual(granted.message, "Granted")
    XCTAssertEqual(granted.textColor, .systemGreen)
  }

  func testCommonControlSettingsAvoidFullWindowRefresh() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    settings.defaultSortMode = .links
    settings.includeImageTextInSearch = true
    settings.pruneDuplicates = false
    settings.ignoredItemKindsRaw = [ClipboardItemKind.image.rawValue]
    settings.keepFirstImage = false
    settings.excludeSensitive = true
    settings.clearHistoryOnQuit = true
    drainMainQueue()

    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
    XCTAssertEqual(controller.debugDefaultSortTitle, ClipboardSortMode.links.title)
    XCTAssertTrue(controller.debugIncludeImageTextIsEnabled)
    XCTAssertFalse(controller.debugPruneDuplicatesIsEnabled)
    XCTAssertFalse(controller.debugAllowedKindIsEnabled(.image))
    XCTAssertTrue(controller.debugAllowedKindIsEnabled(.text))
    XCTAssertFalse(controller.debugKeepFirstImageIsEnabled)
    XCTAssertTrue(controller.debugExcludeSensitiveIsEnabled)
    XCTAssertTrue(controller.debugClearHistoryOnQuitIsEnabled)
  }

  func testAllowedContentTypesKeepAtLeastOneKindEnabled() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount
    let kindsToDisable: [ClipboardItemKind] = [
      .code,
      .url,
      .image,
      .color,
      .audio,
      .video,
      .richText,
      .pdf,
      .file
    ]

    settings.setCaptureStatus(message: "Captured text from Safari.")
    drainMainQueue()
    XCTAssertEqual(controller.debugCaptureStatusColor, .systemGreen)

    for kind in kindsToDisable {
      controller.debugSetAllowedKindEnabled(kind, false)
      drainMainQueue()
      XCTAssertFalse(controller.debugAllowedKindIsEnabled(kind))
    }

    XCTAssertTrue(controller.debugAllowedKindIsEnabled(.text))
    XCTAssertFalse(settings.ignoredItemKindsRaw.contains(ClipboardItemKind.text.rawValue))

    controller.debugSetAllowedKindEnabled(.text, false)
    drainMainQueue()

    XCTAssertTrue(controller.debugAllowedKindIsEnabled(.text))
    XCTAssertFalse(settings.ignoredItemKindsRaw.contains(ClipboardItemKind.text.rawValue))
    XCTAssertEqual(controller.debugCaptureStatusText, "At least one content type must stay enabled.")
    XCTAssertEqual(controller.debugCaptureStatusColor, .systemOrange)

    XCTAssertEqual(settings.captureStatusMessage, "At least one content type must stay enabled.")
    settings.setPasteStatus(message: "Pasted latest clip")
    drainMainQueue()

    XCTAssertEqual(controller.debugCaptureStatusText, "At least one content type must stay enabled.")
    XCTAssertEqual(controller.debugCaptureStatusColor, .systemOrange)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetAllowedKindEnabled(.image, true)
    drainMainQueue()

    XCTAssertTrue(controller.debugAllowedKindIsEnabled(.image))
    XCTAssertEqual(settings.captureStatusMessage, "Allowed content types updated.")
    XCTAssertEqual(controller.debugCaptureStatusText, "Allowed content types updated.")
    XCTAssertEqual(controller.debugCaptureStatusColor, .systemGreen)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testExternalAllowedContentTypeChangesKeepAtLeastOneKindEnabled() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount
    let allVisibleKindRawValues = Self.visibleItemKinds.map(\.rawValue)

    settings.ignoredItemKindsRaw = allVisibleKindRawValues
    drainMainQueue()

    XCTAssertTrue(controller.debugAllowedKindIsEnabled(.text))
    XCTAssertFalse(settings.ignoredItemKindsRaw.contains(ClipboardItemKind.text.rawValue))
    for kind in Self.visibleItemKinds where kind != .text {
      XCTAssertFalse(controller.debugAllowedKindIsEnabled(kind))
    }
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testShortcutEditsAvoidFullWindowRefreshAndRecoverEmptyKey() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    controller.debugCommitOpenShortcutKeyText("k")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "k")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "K")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugCommitOpenShortcutKeyText("space")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "k")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "K")
    XCTAssertEqual(controller.debugShortcutStatusText, "Unsupported shortcut: ⌘⌥SPACE")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugCommitOpenShortcutKeyText("⌘")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "k")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "K")
    XCTAssertEqual(controller.debugShortcutStatusText, "Unsupported shortcut: ⌘")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugCommitOpenShortcutKeyText("")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "k")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "K")
    XCTAssertEqual(controller.debugShortcutStatusText, "Registered")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testShortcutStatusPresentationUsesPositiveAndErrorColors() {
    let registered = SettingsWindowController.shortcutStatusPresentation(storedStatus: "")

    XCTAssertEqual(registered.message, "Registered")
    XCTAssertEqual(registered.textColor, .systemGreen)

    let unsupported = SettingsWindowController.shortcutStatusPresentation(
      storedStatus: "Unsupported shortcut: ⇧V"
    )

    XCTAssertEqual(unsupported.message, "Unsupported shortcut: ⇧V")
    XCTAssertEqual(unsupported.textColor, .systemRed)

    let conflict = SettingsWindowController.shortcutStatusPresentation(
      storedStatus: "Shortcut is already in use: ⌘⇧C"
    )

    XCTAssertEqual(conflict.message, "Shortcut is already in use: ⌘⇧C")
    XCTAssertEqual(conflict.textColor, .systemRed)
  }

  func testShortcutDraftSurvivesExternalShortcutRefreshWhileEditing() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    XCTAssertTrue(controller.debugBeginOpenShortcutKeyEditing())
    controller.debugSetOpenShortcutKeyDraft("z")

    settings.openShortcut = ShortcutBinding(
      key: "j",
      modifierFlags: NSEvent.ModifierFlags.command.rawValue
    )
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "j")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "z")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugEndOpenShortcutKeyEditing()
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "z")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "Z")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testClosingSettingsWindowCommitsShortcutDraft() {
    let (controller, settings) = makeController()
    let initialShortcut = settings.openShortcut

    XCTAssertTrue(controller.debugBeginOpenShortcutKeyEditing())
    controller.debugSetOpenShortcutKeyDraft("b")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut, initialShortcut)
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "b")

    controller.debugCloseWindow()
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "b")
    XCTAssertEqual(settings.openShortcut.modifierFlags, initialShortcut.modifierFlags)
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "B")
  }

  func testShortcutModifierEditsRejectUnsupportedBindingsWithoutSaving() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount
    let initialShortcut = settings.openShortcut

    controller.debugSetOpenShortcutModifiers(command: false, option: false, control: false, shift: false)
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut, initialShortcut)
    XCTAssertEqual(controller.debugOpenShortcutKeyText, initialShortcut.key.uppercased())
    XCTAssertEqual(controller.debugShortcutStatusText, "Unsupported shortcut: V")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetOpenShortcutModifiers(command: false, option: false, control: false, shift: true)
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut, initialShortcut)
    XCTAssertEqual(controller.debugShortcutStatusText, "Unsupported shortcut: ⇧V")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetOpenShortcutModifiers(command: false, option: false, control: true, shift: false)
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, initialShortcut.key)
    XCTAssertEqual(settings.openShortcut.modifierFlags, NSEvent.ModifierFlags.control.rawValue)
    XCTAssertEqual(controller.debugShortcutStatusText, "Registered")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testShortcutKeyFieldExplicitModifiersReplaceExistingModifierState() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    XCTAssertEqual(settings.openShortcut.displayText, "⌘⌥V")

    controller.debugCommitOpenShortcutKeyText("⌘K")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut.key, "k")
    XCTAssertEqual(settings.openShortcut.modifierFlags, NSEvent.ModifierFlags.command.rawValue)
    XCTAssertEqual(settings.openShortcut.displayText, "⌘K")
    XCTAssertEqual(controller.debugOpenShortcutKeyText, "K")
    XCTAssertEqual(controller.debugShortcutStatusText, "Registered")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testShortcutEditsRejectConflictingBindingsWithoutSaving() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    controller.debugCommitOpenShortcutKeyText(",")
    drainMainQueue()
    let commandOptionComma = settings.openShortcut

    controller.debugSetOpenShortcutModifiers(command: true, option: false, control: false, shift: false)
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut, commandOptionComma)
    XCTAssertEqual(controller.debugShortcutStatusText, "Shortcut is already in use: ⌘,")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugCommitOpenShortcutKeyText("space")
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut, commandOptionComma)
    XCTAssertEqual(controller.debugOpenShortcutKeyText, ",")
    XCTAssertEqual(controller.debugShortcutStatusText, "Unsupported shortcut: ⌘⌥SPACE")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugCommitOpenShortcutKeyText("c")
    drainMainQueue()
    let commandOptionC = settings.openShortcut

    controller.debugSetOpenShortcutModifiers(command: true, option: false, control: false, shift: true)
    drainMainQueue()

    XCTAssertEqual(settings.openShortcut, commandOptionC)
    XCTAssertEqual(controller.debugShortcutStatusText, "Shortcut is already in use: ⌘⇧C")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testLaunchAtLoginChangesAvoidFullWindowRefresh() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    settings.launchAtLogin = true
    drainMainQueue()

    XCTAssertTrue(controller.debugLaunchAtLoginIsEnabled)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    settings.setLaunchAtLoginStatus(message: "Launch agent unavailable")
    drainMainQueue()

    XCTAssertEqual(controller.debugLaunchStatusText, "Launch agent unavailable")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetLaunchAtLoginEnabled(false)
    drainMainQueue(iterations: 40)

    XCTAssertFalse(settings.launchAtLogin)
    XCTAssertEqual(settings.launchAtLoginErrorMessage, "")
    XCTAssertFalse(controller.debugLaunchAtLoginIsEnabled)
    XCTAssertEqual(controller.debugLaunchStatusText, "")
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  func testLaunchAtLoginStatusPresentationUsesErrorColorForFailures() {
    let idle = SettingsWindowController.launchAtLoginStatusPresentation(storedStatus: "")

    XCTAssertEqual(idle.message, "")
    XCTAssertEqual(idle.textColor, .secondaryLabelColor)

    let failure = SettingsWindowController.launchAtLoginStatusPresentation(
      storedStatus: "Launch-at-login failed: Service unavailable"
    )

    XCTAssertEqual(failure.message, "Launch-at-login failed: Service unavailable")
    XCTAssertEqual(failure.textColor, .systemRed)
  }

  func testVisibilityControlsKeepOneSurfaceEnabledWithoutFullRefresh() {
    let (controller, settings) = makeController()
    let initialFullRefreshCount = controller.debugFullRefreshCount

    XCTAssertTrue(controller.debugShowMenuBarIconIsEnabled)
    XCTAssertFalse(controller.debugShowDockIconIsEnabled)

    controller.debugSetShowMenuBarIconEnabled(false)

    XCTAssertFalse(settings.showMenuBarIcon)
    XCTAssertTrue(settings.showDockIcon)
    XCTAssertFalse(controller.debugShowMenuBarIconIsEnabled)
    XCTAssertTrue(controller.debugShowDockIconIsEnabled)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    drainMainQueue()

    XCTAssertFalse(controller.debugShowMenuBarIconIsEnabled)
    XCTAssertTrue(controller.debugShowDockIconIsEnabled)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)

    controller.debugSetShowDockIconEnabled(false)

    XCTAssertTrue(settings.showMenuBarIcon)
    XCTAssertFalse(settings.showDockIcon)
    XCTAssertTrue(controller.debugShowMenuBarIconIsEnabled)
    XCTAssertFalse(controller.debugShowDockIconIsEnabled)
    XCTAssertEqual(controller.debugFullRefreshCount, initialFullRefreshCount)
  }

  private struct ControllerFixture {
    let controller: SettingsWindowController
    let settings: SettingsModel
    let store: ClipboardStore
  }

  private func makeControllerFixture(
    cloudSyncService: ClipboardCloudSyncServicing = CloudSyncProbe()
  ) -> ControllerFixture {
    let suiteName = "com.clipbored.settingswindow.\(UUID().uuidString)"
    defaultsSuites.append(suiteName)
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let settings = SettingsModel(defaults: defaults)
    settings.maxHistoryItems = 50
    settings.historyRetention = .forever
    let baseURL = makeTempDirectory()
    let encryptionService = ClipboardEncryptionService(keyProvider: { nil })
    let cacheService = ClipboardCacheService(baseURL: baseURL, encryptionService: encryptionService)
    let store = ClipboardStore(
      settings: settings,
      cacheService: cacheService,
      baseURL: baseURL,
      encryptionService: encryptionService
    )
    let controller = SettingsWindowController(
      settings: settings,
      store: store,
      cacheService: cacheService,
      cloudSyncService: cloudSyncService
    )
    return ControllerFixture(controller: controller, settings: settings, store: store)
  }

  private func makeController(
    cloudSyncService: ClipboardCloudSyncServicing = CloudSyncProbe()
  ) -> (SettingsWindowController, SettingsModel) {
    let fixture = makeControllerFixture(cloudSyncService: cloudSyncService)
    return (fixture.controller, fixture.settings)
  }

  private func makeItem(_ payload: String, displayText: String, created: Date) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: displayText,
      payload: payload,
      payloadHash: payload,
      createdAt: created,
      lastUsedAt: created,
      useCount: 1,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false
    )
  }

  private func makeTempDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipbored-settingswindow-tests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    tempURLs.append(directory)
    return directory
  }

  private func drainMainQueue(iterations: Int = 20) {
    for _ in 0..<iterations {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }

  private static let visibleItemKinds: [ClipboardItemKind] = [
    .text,
    .code,
    .url,
    .image,
    .color,
    .audio,
    .video,
    .richText,
    .pdf,
    .file
  ]
}

private final class CloudSyncProbe: ClipboardCloudSyncServicing {
  var statusCallCount = 0
  private let statusResponse: ClipboardCloudSyncStatus

  init(status: ClipboardCloudSyncStatus = ClipboardCloudSyncStatus(
    isAvailable: false,
    archiveURL: nil,
    lastModifiedAt: nil,
    message: "Probe iCloud unavailable"
  )) {
    statusResponse = status
  }

  func syncArchiveURL() throws -> URL {
    if let archiveURL = statusResponse.archiveURL {
      return archiveURL
    }
    throw ClipboardCloudSyncError.unavailable
  }

  func status() -> ClipboardCloudSyncStatus {
    statusCallCount += 1
    return statusResponse
  }

  func push(store: ClipboardStore) throws -> ClipboardArchiveSummary {
    ClipboardArchiveSummary(itemCount: 0, sidecarCount: 0, skippedItemCount: 0, skippedSidecarCount: 0)
  }

  func pull(store: ClipboardStore) throws -> ClipboardArchiveSummary {
    ClipboardArchiveSummary(itemCount: 0, sidecarCount: 0, skippedItemCount: 0, skippedSidecarCount: 0)
  }
}
