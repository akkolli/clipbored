import Foundation
import XCTest
@testable import ClipBored

final class ClipboardCloudSyncServiceTests: XCTestCase {
  private var tempRoot: URL!
  private var defaultsSuites: [String] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipbored-cloud-sync-tests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    for suite in defaultsSuites {
      UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
    if let tempRoot {
      try? FileManager.default.removeItem(at: tempRoot)
    }
    defaultsSuites = []
    tempRoot = nil
    try super.tearDownWithError()
  }

  func testUnavailableContainerReportsStatusAndThrows() {
    let service = ClipboardCloudSyncService(containerProvider: { nil })

    let status = service.status()

    XCTAssertFalse(status.isAvailable)
    XCTAssertNil(status.archiveURL)
    XCTAssertTrue(status.message.contains("iCloud Sync is unavailable"))
    XCTAssertThrowsError(try service.syncArchiveURL()) { error in
      XCTAssertEqual(error as? ClipboardCloudSyncError, .unavailable)
    }
  }

  func testPushWritesArchiveToPrivateDocumentsFolder() throws {
    let environment = try makeStoreEnvironment(named: "source")
    environment.store.upsert(makeItem("cloud note", created: Date(timeIntervalSince1970: 10)))
    environment.store.flushPersistenceForTesting()

    let cloudRoot = tempRoot.appendingPathComponent("cloud", isDirectory: true)
    let service = ClipboardCloudSyncService(containerProvider: { cloudRoot })

    let summary = try service.push(store: environment.store)
    let archiveURL = try service.syncArchiveURL()
    let status = service.status()

    XCTAssertEqual(summary.itemCount, 1)
    XCTAssertEqual(
      archiveURL,
      cloudRoot
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent(AppConfiguration.appName, isDirectory: true)
        .appendingPathComponent(ClipboardCloudSyncService.archiveFileName)
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
    XCTAssertEqual(try posixPermissions(archiveURL), 0o600)
    XCTAssertTrue(status.isAvailable)
    XCTAssertEqual(status.archiveURL, archiveURL)
    XCTAssertNotNil(status.lastModifiedAt)
  }

  func testPullImportsExistingCloudArchiveIntoAnotherStore() throws {
    let source = try makeStoreEnvironment(named: "source")
    let sourceItem = makeItem("shared through icloud", created: Date(timeIntervalSince1970: 20))
    source.store.upsert(sourceItem)
    source.store.flushPersistenceForTesting()

    let cloudRoot = tempRoot.appendingPathComponent("cloud", isDirectory: true)
    let service = ClipboardCloudSyncService(containerProvider: { cloudRoot })
    try service.push(store: source.store)

    let destination = try makeStoreEnvironment(named: "destination")
    let summary = try service.pull(store: destination.store)
    destination.store.flushPersistenceForTesting()

    XCTAssertEqual(summary.itemCount, 1)
    XCTAssertEqual(destination.store.items.count, 1)
    XCTAssertEqual(destination.store.items.first?.id, sourceItem.id)
    XCTAssertEqual(destination.store.items.first?.payload, "shared through icloud")
  }

  func testPullWithoutRemoteArchiveThrowsNoRemoteArchive() throws {
    let destination = try makeStoreEnvironment(named: "destination")
    let cloudRoot = tempRoot.appendingPathComponent("empty-cloud", isDirectory: true)
    let service = ClipboardCloudSyncService(containerProvider: { cloudRoot })

    XCTAssertThrowsError(try service.pull(store: destination.store)) { error in
      guard case ClipboardCloudSyncError.noRemoteArchive(let url) = error else {
        return XCTFail("Expected noRemoteArchive, got \(error)")
      }
      XCTAssertEqual(url.lastPathComponent, ClipboardCloudSyncService.archiveFileName)
    }
  }

  private func makeStoreEnvironment(named name: String) throws -> (settings: SettingsModel, store: ClipboardStore) {
    let suiteName = "com.clipbored.cloudsync.\(name).\(UUID().uuidString)"
    defaultsSuites.append(suiteName)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let settings = SettingsModel(defaults: defaults)
    settings.maxHistoryItems = 50
    settings.historyRetention = .forever
    let baseURL = tempRoot.appendingPathComponent(name, isDirectory: true)
    let encryptionService = ClipboardEncryptionService(keyProvider: { nil })
    let cacheService = ClipboardCacheService(baseURL: baseURL, encryptionService: encryptionService)
    let store = ClipboardStore(
      settings: settings,
      cacheService: cacheService,
      baseURL: baseURL,
      encryptionService: encryptionService
    )
    return (settings, store)
  }

  private func makeItem(_ payload: String, created: Date) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: payload,
      payload: payload,
      payloadHash: String(payload.hashValue),
      createdAt: created,
      lastUsedAt: created,
      useCount: 1,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false
    )
  }

  private func posixPermissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int)
  }
}
