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
}
