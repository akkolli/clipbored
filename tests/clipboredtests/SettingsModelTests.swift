import XCTest
@testable import ClipBored

final class SettingsModelTests: XCTestCase {
  func testFreshProfileRequiresOnboardingUntilCompleted() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    XCTAssertFalse(settings.onboardingCompleted)
    XCTAssertFalse(defaults.bool(forKey: SettingsModel.Keys.onboardingCompleted))

    settings.markOnboardingCompleted()

    XCTAssertTrue(settings.onboardingCompleted)
    XCTAssertTrue(defaults.bool(forKey: SettingsModel.Keys.onboardingCompleted))
    XCTAssertEqual(changes, [.other])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertTrue(restored.onboardingCompleted)
  }

  func testLegacyProfileDoesNotShowOnboardingAfterUpgrade() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    defaults.set(AppConfiguration.defaultHistoryLength, forKey: SettingsModel.Keys.maxHistoryItems)

    let settings = SettingsModel(defaults: defaults)

    XCTAssertTrue(settings.onboardingCompleted)
    XCTAssertTrue(defaults.bool(forKey: SettingsModel.Keys.onboardingCompleted))
  }

  func testShowDockIconPersistsAndNotifies() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    XCTAssertFalse(settings.showDockIcon)

    settings.showDockIcon = true

    XCTAssertTrue(defaults.bool(forKey: SettingsModel.Keys.showDockIcon))
    XCTAssertEqual(changes.count, 1)
    guard case .showDockIcon = changes.first else {
      return XCTFail("Expected showDockIcon change notification")
    }

    let restored = SettingsModel(defaults: defaults)
    XCTAssertTrue(restored.showDockIcon)
  }

  func testHideFromScreenCapturePersistsAndNotifies() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    XCTAssertFalse(settings.hideFromScreenCapture)

    settings.hideFromScreenCapture = true

    XCTAssertTrue(defaults.bool(forKey: SettingsModel.Keys.hideFromScreenCapture))
    XCTAssertEqual(changes, [.hideFromScreenCapture])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertTrue(restored.hideFromScreenCapture)
  }

  func testPanelSidePersistsAndNotifies() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    XCTAssertEqual(settings.panelSide, .right)

    settings.panelSide = .left

    XCTAssertEqual(defaults.integer(forKey: SettingsModel.Keys.panelSide), ClipboardPanelSide.left.rawValue)
    XCTAssertEqual(changes, [.panelSide])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.panelSide, .left)
  }

  func testImageCacheMinimumAllowsTwoMegabytes() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let twoMegabytes = Int64(2 * 1024 * 1024)
    defaults.set(twoMegabytes, forKey: SettingsModel.Keys.imageCacheMaxBytes)

    let settings = SettingsModel(defaults: defaults)

    XCTAssertEqual(AppConfiguration.minCacheMaxBytes, twoMegabytes)
    XCTAssertEqual(settings.imageCacheMaxBytes, twoMegabytes)
  }

  func testICloudSyncPersistsAndNotifies() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    XCTAssertFalse(settings.iCloudSyncEnabled)

    settings.setCloudSyncStatus(message: "Synced 3 clips to iCloud.")
    XCTAssertEqual(settings.cloudSyncStatusMessage, "Synced 3 clips to iCloud.")
    changes.removeAll()

    settings.iCloudSyncEnabled = true

    XCTAssertTrue(defaults.bool(forKey: SettingsModel.Keys.iCloudSyncEnabled))
    XCTAssertEqual(settings.cloudSyncStatusMessage, "")
    XCTAssertEqual(changes, [.cloudSync])

    settings.setCloudSyncStatus(message: "Synced 3 clips to iCloud.")
    changes.removeAll()
    settings.iCloudSyncEnabled = false

    XCTAssertFalse(defaults.bool(forKey: SettingsModel.Keys.iCloudSyncEnabled))
    XCTAssertEqual(settings.cloudSyncStatusMessage, "")
    XCTAssertEqual(changes, [.cloudSync])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertFalse(restored.iCloudSyncEnabled)
  }

  func testPauseCaptureUntilPersistsAndCanBeCleared() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    let pauseUntil = Date(timeIntervalSince1970: 1_234_567)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    settings.pauseCapture = true
    settings.pauseCaptureUntil = pauseUntil

    XCTAssertTrue(defaults.bool(forKey: SettingsModel.Keys.pauseCapture))
    XCTAssertEqual(defaults.double(forKey: SettingsModel.Keys.pauseCaptureUntil), pauseUntil.timeIntervalSince1970)
    XCTAssertEqual(changes, [.pauseCapture, .pauseCapture])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertTrue(restored.pauseCapture)
    XCTAssertEqual(restored.pauseCaptureUntil, pauseUntil)

    restored.pauseCaptureUntil = nil

    XCTAssertNil(defaults.object(forKey: SettingsModel.Keys.pauseCaptureUntil))
  }

  func testIgnoredAppsPersistsAndNotifiesNarrowChange() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    settings.ignoredApps = ["Safari", "Xcode"]

    XCTAssertEqual(defaults.stringArray(forKey: SettingsModel.Keys.ignoredApps), ["Safari", "Xcode"])
    XCTAssertEqual(changes, [.ignoredApps])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.ignoredApps, ["Safari", "Xcode"])
  }

  func testCommonControlSettingsNotifyNarrowChanges() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    settings.defaultSortMode = .links
    settings.includeImageTextInSearch = true
    settings.pruneDuplicates = false
    settings.ignoredItemKindsRaw = [ClipboardItemKind.image.rawValue]
    settings.keepFirstImage = false
    settings.excludeSensitive = true
    settings.clearHistoryOnQuit = true

    XCTAssertEqual(changes, [
      .defaultSortMode,
      .includeImageTextInSearch,
      .pruneDuplicates,
      .ignoredItemKinds,
      .keepFirstImage,
      .excludeSensitive,
      .clearHistoryOnQuit
    ])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.defaultSortMode, .links)
    XCTAssertTrue(restored.includeImageTextInSearch)
    XCTAssertFalse(restored.pruneDuplicates)
    XCTAssertEqual(restored.ignoredItemKindsRaw, [ClipboardItemKind.image.rawValue])
    XCTAssertFalse(restored.keepFirstImage)
    XCTAssertTrue(restored.excludeSensitive)
    XCTAssertTrue(restored.clearHistoryOnQuit)
  }

  func testIgnoredItemKindsCannotDisableEveryVisibleKind() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    let allVisibleKindRawValues = Self.visibleItemKinds.map(\.rawValue)
    let expectedIgnoredKindRawValues = allVisibleKindRawValues.filter {
      $0 != ClipboardItemKind.text.rawValue
    }
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    settings.ignoredItemKindsRaw = allVisibleKindRawValues

    XCTAssertEqual(settings.ignoredItemKindsRaw, expectedIgnoredKindRawValues)
    XCTAssertEqual(
      defaults.object(forKey: SettingsModel.Keys.ignoredItemKinds) as? [Int],
      expectedIgnoredKindRawValues
    )
    XCTAssertEqual(changes, [.ignoredItemKinds])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.ignoredItemKindsRaw, expectedIgnoredKindRawValues)
  }

  func testStoredIgnoredItemKindsCannotDisableEveryVisibleKind() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let allVisibleKindRawValues = Self.visibleItemKinds.map(\.rawValue)
    let expectedIgnoredKindRawValues = allVisibleKindRawValues.filter {
      $0 != ClipboardItemKind.text.rawValue
    }
    defaults.set(allVisibleKindRawValues, forKey: SettingsModel.Keys.ignoredItemKinds)

    let settings = SettingsModel(defaults: defaults)

    XCTAssertEqual(settings.ignoredItemKindsRaw, expectedIgnoredKindRawValues)
    XCTAssertEqual(
      defaults.object(forKey: SettingsModel.Keys.ignoredItemKinds) as? [Int],
      expectedIgnoredKindRawValues
    )
  }

  func testStoredImageCacheLimitIsClampedToSettingsRange() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let zeroDefaults = UserDefaults(suiteName: "\(suiteName).zero")!
    let lowDefaults = UserDefaults(suiteName: "\(suiteName).low")!
    let highDefaults = UserDefaults(suiteName: "\(suiteName).high")!
    defer {
      zeroDefaults.removePersistentDomain(forName: "\(suiteName).zero")
      lowDefaults.removePersistentDomain(forName: "\(suiteName).low")
      highDefaults.removePersistentDomain(forName: "\(suiteName).high")
    }

    zeroDefaults.set(0, forKey: SettingsModel.Keys.imageCacheMaxBytes)
    let zeroSettings = SettingsModel(defaults: zeroDefaults)

    XCTAssertEqual(zeroSettings.imageCacheMaxBytes, AppConfiguration.defaultCacheMaxBytes)
    XCTAssertEqual(Int64(zeroDefaults.integer(forKey: SettingsModel.Keys.imageCacheMaxBytes)), AppConfiguration.defaultCacheMaxBytes)

    lowDefaults.set(1 * 1024 * 1024, forKey: SettingsModel.Keys.imageCacheMaxBytes)
    let lowSettings = SettingsModel(defaults: lowDefaults)

    XCTAssertEqual(lowSettings.imageCacheMaxBytes, AppConfiguration.minCacheMaxBytes)
    XCTAssertEqual(Int64(lowDefaults.integer(forKey: SettingsModel.Keys.imageCacheMaxBytes)), AppConfiguration.minCacheMaxBytes)

    highDefaults.set(2048 * 1024 * 1024, forKey: SettingsModel.Keys.imageCacheMaxBytes)
    let highSettings = SettingsModel(defaults: highDefaults)

    XCTAssertEqual(highSettings.imageCacheMaxBytes, AppConfiguration.maxCacheMaxBytes)
    XCTAssertEqual(Int64(highDefaults.integer(forKey: SettingsModel.Keys.imageCacheMaxBytes)), AppConfiguration.maxCacheMaxBytes)
  }

  func testStoredHistoryLimitIsClampedToSettingsRange() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let zeroDefaults = UserDefaults(suiteName: "\(suiteName).zero")!
    let lowDefaults = UserDefaults(suiteName: "\(suiteName).low")!
    let highDefaults = UserDefaults(suiteName: "\(suiteName).high")!
    defer {
      zeroDefaults.removePersistentDomain(forName: "\(suiteName).zero")
      lowDefaults.removePersistentDomain(forName: "\(suiteName).low")
      highDefaults.removePersistentDomain(forName: "\(suiteName).high")
    }

    zeroDefaults.set(0, forKey: SettingsModel.Keys.maxHistoryItems)
    let zeroSettings = SettingsModel(defaults: zeroDefaults)

    XCTAssertEqual(zeroSettings.maxHistoryItems, AppConfiguration.defaultHistoryLength)
    XCTAssertEqual(zeroDefaults.integer(forKey: SettingsModel.Keys.maxHistoryItems), AppConfiguration.defaultHistoryLength)

    lowDefaults.set(1, forKey: SettingsModel.Keys.maxHistoryItems)
    let lowSettings = SettingsModel(defaults: lowDefaults)

    XCTAssertEqual(lowSettings.maxHistoryItems, AppConfiguration.minHistoryLength)
    XCTAssertEqual(lowDefaults.integer(forKey: SettingsModel.Keys.maxHistoryItems), AppConfiguration.minHistoryLength)

    highDefaults.set(100_000, forKey: SettingsModel.Keys.maxHistoryItems)
    let highSettings = SettingsModel(defaults: highDefaults)

    XCTAssertEqual(highSettings.maxHistoryItems, AppConfiguration.maxHistoryLength)
    XCTAssertEqual(highDefaults.integer(forKey: SettingsModel.Keys.maxHistoryItems), AppConfiguration.maxHistoryLength)
  }

  func testLimitAssignmentsAreClampedAndPersisted() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    settings.maxHistoryItems = 1
    settings.maxHistoryItems = 100_000
    settings.imageCacheMaxBytes = 1
    settings.imageCacheMaxBytes = 2048 * 1024 * 1024

    XCTAssertEqual(settings.maxHistoryItems, AppConfiguration.maxHistoryLength)
    XCTAssertEqual(defaults.integer(forKey: SettingsModel.Keys.maxHistoryItems), AppConfiguration.maxHistoryLength)
    XCTAssertEqual(settings.imageCacheMaxBytes, AppConfiguration.maxCacheMaxBytes)
    XCTAssertEqual(Int64(defaults.integer(forKey: SettingsModel.Keys.imageCacheMaxBytes)), AppConfiguration.maxCacheMaxBytes)
    XCTAssertEqual(changes, [
      .maxHistoryItems,
      .maxHistoryItems,
      .imageCacheMaxBytes,
      .imageCacheMaxBytes
    ])
  }

  func testHistoryRetentionDefaultsToOneMonthAndPersists() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    XCTAssertEqual(settings.historyRetention, .oneMonth)
    XCTAssertEqual(defaults.integer(forKey: SettingsModel.Keys.historyRetention), HistoryRetention.oneMonth.rawValue)

    settings.historyRetention = .oneWeek

    XCTAssertEqual(defaults.integer(forKey: SettingsModel.Keys.historyRetention), HistoryRetention.oneWeek.rawValue)
    XCTAssertEqual(changes, [.historyRetention])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.historyRetention, .oneWeek)
  }

  func testCustomCollectionsPersistWithNormalizedColors() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    var changes: [SettingsModel.Change] = []
    settings.observe { changes.append($0) }

    settings.ensureCollection(named: "  Research   Stack  ", colorHex: "0a9eb8")
    settings.ensureCollection(named: "research stack", colorHex: "#FF3355")
    settings.ensureCollection(named: "Client Work", colorHex: "not-a-color")

    XCTAssertEqual(settings.customCollectionNames, ["Research Stack", "Client Work"])
    XCTAssertEqual(settings.collectionColorHex(forCollectionNamed: "research stack"), "#FF3355")
    XCTAssertNil(settings.collectionColorHex(forCollectionNamed: "Client Work"))
    XCTAssertEqual(changes, [.collections, .collections, .collections])

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.customCollectionNames, ["Research Stack", "Client Work"])
    XCTAssertEqual(restored.collectionColorHex(forCollectionNamed: "Research Stack"), "#FF3355")
  }

  func testCustomCollectionsCanBeUpdatedAndDeleted() {
    let suiteName = "com.clipbored.settingsmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)

    settings.ensureCollection(named: "Research Stack", colorHex: "#0A9EB8")
    settings.ensureCollection(named: "Client Work", colorHex: "#FF3355")

    let updatedName = settings.updateCollection(named: "research stack", to: "Product Research", colorHex: "#3366FF")

    XCTAssertEqual(updatedName, "Product Research")
    XCTAssertEqual(settings.customCollectionNames, ["Product Research", "Client Work"])
    XCTAssertNil(settings.collectionColorHex(forCollectionNamed: "Research Stack"))
    XCTAssertEqual(settings.collectionColorHex(forCollectionNamed: "Product Research"), "#3366FF")

    settings.deleteCollection(named: "client work")

    XCTAssertEqual(settings.customCollectionNames, ["Product Research"])
    XCTAssertNil(settings.collectionColorHex(forCollectionNamed: "Client Work"))

    let restored = SettingsModel(defaults: defaults)
    XCTAssertEqual(restored.customCollectionNames, ["Product Research"])
    XCTAssertEqual(restored.collectionColorHex(forCollectionNamed: "Product Research"), "#3366FF")
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
