import XCTest
@testable import ClipBored

final class SettingsModelTests: XCTestCase {
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
}
