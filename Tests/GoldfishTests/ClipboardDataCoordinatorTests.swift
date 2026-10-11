import Foundation
import XCTest

@testable import Goldfish

final class ClipboardDataCoordinatorTests: XCTestCase {
  func testQueuedBackupIsCancelledAndArchiveOperationsStaySerialized() {
    let coordinator = ClipboardDataCoordinator()
    coordinator.setBackupEnabled(true)
    let entered = expectation(description: "first archive operation entered")
    let finished = expectation(description: "first archive operation finished")
    let cancelled = expectation(description: "queued backup cancelled")
    let release = DispatchSemaphore(value: 0)
    coordinator.perform({
      entered.fulfill()
      release.wait()
      return 1
    }) { value in
      XCTAssertEqual(value, 1)
      finished.fulfill()
    }
    wait(for: [entered], timeout: 2)
    let operation = coordinator.backupOperation { _ -> Int in
      XCTFail("Disabled queued backup must never start")
      return 2
    }
    coordinator.perform(operation) { result in
      if case .failure(let error) = result {
        XCTAssertEqual(error as? ClipboardCloudSyncError, .cancelled)
      } else {
        XCTFail("Expected cancellation")
      }
      cancelled.fulfill()
    }
    coordinator.setBackupEnabled(false)
    coordinator.setBackupEnabled(true)
    release.signal()
    wait(for: [finished, cancelled], timeout: 2, enforceOrder: true)
  }

  func testDisablingBackupBeforePublicationKeepsPreviousArchive() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Goldfish.Backup.\(UUID())")
    let suite = "Goldfish.Backup.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
    let settings = SettingsModel(defaults: defaults)
    let encryption = ClipboardEncryptionService(keyProvider: { nil })
    let cache = ClipboardCacheService(baseURL: root.appendingPathComponent("local"), encryptionService: encryption)
    let store = ClipboardStore(
      settings: settings, cacheService: cache, baseURL: root.appendingPathComponent("local"), encryptionService: encryption)
    let cloud = ClipboardCloudSyncService(containerProvider: { root.appendingPathComponent("cloud") })
    let archive = try cloud.syncArchiveURL()
    let original = Data("previous backup".utf8)
    try original.write(to: archive)
    let coordinator = ClipboardDataCoordinator()
    coordinator.setBackupEnabled(true)
    let operation = coordinator.backupOperation { write in
      coordinator.setBackupEnabled(false)
      return try cloud.push(store: store, write: write)
    }
    if case .failure(let error) = operation() {
      XCTAssertEqual(error as? ClipboardCloudSyncError, .cancelled)
    } else {
      XCTFail("Expected cancellation before publishing")
    }
    XCTAssertEqual(try Data(contentsOf: archive), original)
  }

  func testShelfActionsPreserveLegacyModesAndChangeFiltersAtomically() {
    for mode in ClipboardSortMode.allCases {
      var state = ClipboardShelfState(sortMode: mode)
      state.apply(.search("query"))
      state.apply(.content(.images))
      state.apply(.collection("  My   board  "))
      XCTAssertEqual(state.sortMode.rawValue, mode.rawValue)
      XCTAssertEqual(state.collectionName, "My board")
      state.apply(.reset)
      XCTAssertEqual(state.query, "query")
      XCTAssertNil(state.collectionName)
      XCTAssertNil(state.contentFilter)
      XCTAssertEqual(state.sortMode, .mostRecent)
      state.apply(.showAll)
      XCTAssertEqual(state.query, "")
    }
  }
}
