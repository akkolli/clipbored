import CryptoKit
import XCTest
import Foundation
import AppKit
@testable import ClipBored

final class ClipboardStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var defaultsSuiteName: String!
  private var cacheService: ClipboardCacheService!
  private var baseURL: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    defaultsSuiteName = "com.clipbored.teststore.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: defaultsSuiteName)
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    baseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboredtests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    cacheService = ClipboardCacheService(baseURL: baseURL, encryptionService: noOpEncryptionService())
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    if let baseURL {
      try? FileManager.default.removeItem(at: baseURL)
    }
    cacheService = nil
    defaults = nil
    baseURL = nil
    try super.tearDownWithError()
  }

  func testUpsertMovesDuplicateToFrontAndPersists() throws {
    let settings = makeSettings(maxHistory: 4)
    let store = makeStore(settings: settings)
    let start = Date()

    store.upsert(makeItem("one", displayText: "One", created: start))
    store.upsert(makeItem("two", displayText: "Two", created: start.addingTimeInterval(-10)))
    store.upsert(makeItem("three", displayText: "Three", created: start.addingTimeInterval(-20)))

    store.upsert(makeItem("one", displayText: "One (updated)", created: start.addingTimeInterval(-30)))
    store.flushPersistenceForTesting()

    XCTAssertEqual(store.items.count, 3)
    XCTAssertEqual(store.items.map(\.payload), ["one", "three", "two"])
    XCTAssertEqual(store.items.first?.useCount, 2)

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertEqual(restored.items.count, 3)
    XCTAssertEqual(restored.items.first?.payload, "one")
    XCTAssertEqual(restored.items.first?.useCount, 2)
  }

  func testHistoryLimitIsEnforcedByOverflowPurge() throws {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)
    let start = Date()

    (0...50).forEach { i in
      store.upsert(makeItem("item-\(i)", displayText: "\(i)", created: start.addingTimeInterval(-Double(i))))
    }
    store.flushPersistenceForTesting()

    XCTAssertEqual(store.items.count, 50)
    XCTAssertEqual(store.items.first?.payload, "item-50")
    XCTAssertEqual(store.items.last?.payload, "item-1")

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertEqual(restored.items.count, 50)
    XCTAssertFalse(restored.items.contains(where: { $0.payload == "item-0" }))
    XCTAssertTrue(restored.items.contains(where: { $0.payload == "item-50" }))
    XCTAssertTrue(restored.items.contains(where: { $0.payload == "item-1" }))
  }

  func testMarkUsedUpdatesStateAndWritesMutationOnlyOnce() {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)

    store.upsert(makeItem("same", displayText: "First", created: Date()))
    store.upsert(makeItem("same", displayText: "First duplicate", created: Date().addingTimeInterval(1)))
    store.flushPersistenceForTesting()

    let first = try! XCTUnwrap(store.items.first)
    let firstID = first.id
    store.markUsed(firstID)
    store.flushPersistenceForTesting()

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertEqual(restored.items.count, 1)
    XCTAssertEqual(restored.items.first?.useCount, 3)
    XCTAssertEqual(restored.items.first?.displayText, "First duplicate")
  }

  func testTogglePinPersistsAcrossReload() {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)

    store.upsert(makeItem("alpha", displayText: "A", created: Date()))
    store.flushPersistenceForTesting()

    let itemID = try! XCTUnwrap(store.items.first?.id)
    store.togglePin(itemID)
    store.flushPersistenceForTesting()

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertEqual(restored.items.first?.isPinned, true)
  }

  func testSetCollectionPersistsAcrossReload() {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)

    store.upsert(makeItem("alpha", displayText: "A", created: Date()))
    store.flushPersistenceForTesting()

    let itemID = try! XCTUnwrap(store.items.first?.id)
    store.setCollection(itemID, name: "  Client   Work  ")
    store.flushPersistenceForTesting()

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertEqual(restored.items.first?.collectionName, "Client Work")

    let restoredID = try! XCTUnwrap(restored.items.first?.id)
    restored.setCollection(restoredID, name: nil)
    restored.flushPersistenceForTesting()

    let cleared = makeStore(settings: settings)
    cleared.flushPersistenceForTesting()
    XCTAssertNil(cleared.items.first?.collectionName)
  }

  func testLegacyJSONHistoryMigratesToSQLite() throws {
    let settings = makeSettings(maxHistory: 50)
    let itemID = UUID()
    let legacyJSON = """
      [
        {
          "id": "\(itemID.uuidString)",
          "kind": 0,
          "displayText": "Legacy Note",
          "payload": "legacy payload",
          "payloadHash": "legacy-hash",
          "createdAt": "2026-06-27T12:00:00Z",
          "lastUsedAt": "2026-06-27T12:01:00Z",
          "useCount": 3,
          "sourceApp": "Notes",
          "imagePath": null,
          "thumbnailPath": null
        }
      ]
      """
    try legacyJSON.data(using: .utf8)!.write(to: baseURL.appendingPathComponent("history.json"))

    let store = makeStore(settings: settings)
    store.flushPersistenceForTesting()

    XCTAssertEqual(store.items.count, 1)
    XCTAssertEqual(store.items.first?.id, itemID)
    XCTAssertEqual(store.items.first?.payload, "legacy payload")
    XCTAssertEqual(store.items.first?.useCount, 3)

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertEqual(restored.items.first?.payload, "legacy payload")
  }

  func testPinnedItemsSurviveNormalHistoryPrune() {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)
    let start = Date()

    store.upsert(makeItem("pinned-old", displayText: "Pinned", created: start.addingTimeInterval(-500)))
    let pinnedID = try! XCTUnwrap(store.items.first?.id)
    store.togglePin(pinnedID)

    (0..<60).forEach { index in
      store.upsert(makeItem("new-\(index)", displayText: "New \(index)", created: start.addingTimeInterval(Double(index))))
    }
    store.flushPersistenceForTesting()

    XCTAssertTrue(store.items.contains(where: { $0.payload == "pinned-old" && $0.isPinned }))
    XCTAssertEqual(store.items.filter { !$0.isPinned }.count, 50)
    XCTAssertEqual(store.items.filter(\.isPinned).count, 1)

    let restored = makeStore(settings: settings)
    restored.flushPersistenceForTesting()
    XCTAssertTrue(restored.items.contains(where: { $0.payload == "pinned-old" && $0.isPinned }))
  }

  func testStorageFilesUsePrivatePermissions() throws {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)

    store.upsert(makeItem("private", displayText: "Private", created: Date()))
    store.flushPersistenceForTesting()

    XCTAssertEqual(try posixPermissions(baseURL), 0o700)
    XCTAssertEqual(try posixPermissions(baseURL.appendingPathComponent("history.sqlite")), 0o600)
  }

  func testStorageDirectoryHonorsEnvironmentOverride() throws {
    let overrideURL = baseURL.appendingPathComponent("OverrideStorage", isDirectory: true)
    setenv(AppConfiguration.storageDirectoryOverrideEnvironmentKey, overrideURL.path, 1)
    defer { unsetenv(AppConfiguration.storageDirectoryOverrideEnvironmentKey) }

    let resolved = ClipboardStore.storageDirectory()

    XCTAssertEqual(resolved.path, overrideURL.standardizedFileURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: overrideURL.path))
    XCTAssertEqual(try posixPermissions(overrideURL), 0o700)
  }

  func testRemoveAllResetsEncryptionKeyAfterClearingDatabase() throws {
    let settings = makeSettings(maxHistory: 50)
    var resetCount = 0
    let keyData = Data(repeating: 7, count: 32)
    let encryptionService = ClipboardEncryptionService(
      keyProvider: { SymmetricKey(data: keyData) },
      resetProvider: { resetCount += 1 }
    )
    let store = makeStore(settings: settings, encryptionService: encryptionService)

    store.upsert(makeItem("first", displayText: "First", created: Date()))
    store.upsert(makeItem("second", displayText: "Second", created: Date()))
    store.flushPersistenceForTesting()

    let firstID = try XCTUnwrap(store.items.first?.id)
    store.remove(firstID)
    store.flushPersistenceForTesting()
    XCTAssertEqual(resetCount, 0)

    store.removeAll()
    store.flushPersistenceForTesting()

    XCTAssertEqual(resetCount, 1)
    XCTAssertTrue(store.items.isEmpty)
    let restored = makeStore(settings: settings, encryptionService: encryptionService)
    restored.flushPersistenceForTesting()
    XCTAssertTrue(restored.items.isEmpty)
  }

  func testRemoveAllCompactsDatabaseFile() throws {
    let settings = makeSettings(maxHistory: 2000)
    settings.pruneDuplicates = false
    let store = makeStore(settings: settings)
    let payload = String(repeating: "clipbored database compaction payload ", count: 180)

    for index in 0..<60 {
      store.upsert(makeItem("\(payload)\(index)", displayText: "Large \(index)", created: Date(timeIntervalSince1970: Double(index))))
    }
    store.flushPersistenceForTesting()

    let dbURL = baseURL.appendingPathComponent("history.sqlite")
    let sizeBeforeClear = try fileSize(dbURL)
    XCTAssertGreaterThan(sizeBeforeClear, 200_000)

    store.removeAll()
    store.flushPersistenceForTesting()

    let sizeAfterClear = try fileSize(dbURL)
    XCTAssertLessThan(sizeAfterClear, sizeBeforeClear / 2)
    XCTAssertEqual(try posixPermissions(dbURL), 0o600)
  }

  func testPersistedTextFieldsAreEncryptedAndReload() throws {
    let settings = makeSettings(maxHistory: 50)
    let encryptionService = fixedEncryptionService()
    let store = makeStore(settings: settings, encryptionService: encryptionService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Displayed secret \(UUID().uuidString)",
      payload: "Payload secret \(UUID().uuidString)",
      payloadHash: "Hash secret \(UUID().uuidString)",
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 1,
      sourceApp: "Secret app \(UUID().uuidString)",
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: "com.example.secret.\(UUID().uuidString)",
      ocrText: "OCR secret \(UUID().uuidString)",
      collectionName: "Collection secret \(UUID().uuidString)"
    )

    store.upsert(item)
    store.flushPersistenceForTesting()

    let rawDatabaseText = try databaseText()
    XCTAssertTrue(rawDatabaseText.contains(ClipboardEncryptionService.marker))
    XCTAssertFalse(rawDatabaseText.contains(item.displayText))
    XCTAssertFalse(rawDatabaseText.contains(item.payload))
    XCTAssertFalse(rawDatabaseText.contains(item.payloadHash))
    XCTAssertFalse(rawDatabaseText.contains(item.sourceApp!))
    XCTAssertFalse(rawDatabaseText.contains(item.sourceAppBundleId!))
    XCTAssertFalse(rawDatabaseText.contains(item.ocrText!))
    XCTAssertFalse(rawDatabaseText.contains(item.collectionName!))

    let restored = makeStore(settings: settings, encryptionService: encryptionService)
    restored.flushPersistenceForTesting()

    XCTAssertEqual(restored.items.first?.displayText, item.displayText)
    XCTAssertEqual(restored.items.first?.payload, item.payload)
    XCTAssertEqual(restored.items.first?.payloadHash, item.payloadHash)
    XCTAssertEqual(restored.items.first?.sourceApp, item.sourceApp)
    XCTAssertEqual(restored.items.first?.sourceAppBundleId, item.sourceAppBundleId)
    XCTAssertEqual(restored.items.first?.ocrText, item.ocrText)
    XCTAssertEqual(restored.items.first?.collectionName, item.collectionName)
  }

  func testPlaintextDatabaseMigratesToEncryptedFieldsOnLoad() throws {
    let settings = makeSettings(maxHistory: 50)
    let plaintextStore = makeStore(settings: settings, encryptionService: noOpEncryptionService())
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Legacy display \(UUID().uuidString)",
      payload: "Legacy payload \(UUID().uuidString)",
      payloadHash: "Legacy hash \(UUID().uuidString)",
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 1,
      sourceApp: "Legacy source \(UUID().uuidString)",
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: "com.example.legacy.\(UUID().uuidString)",
      ocrText: "Legacy OCR \(UUID().uuidString)",
      collectionName: "Legacy collection \(UUID().uuidString)"
    )

    plaintextStore.upsert(item)
    plaintextStore.flushPersistenceForTesting()
    XCTAssertTrue(try databaseText().contains(item.payload))

    let encryptionService = fixedEncryptionService()
    let restored = makeStore(settings: settings, encryptionService: encryptionService)
    restored.flushPersistenceForTesting()

    XCTAssertEqual(restored.items.first?.displayText, item.displayText)
    XCTAssertEqual(restored.items.first?.payload, item.payload)
    XCTAssertEqual(restored.items.first?.payloadHash, item.payloadHash)
    XCTAssertEqual(restored.items.first?.sourceApp, item.sourceApp)
    XCTAssertEqual(restored.items.first?.sourceAppBundleId, item.sourceAppBundleId)
    XCTAssertEqual(restored.items.first?.ocrText, item.ocrText)
    XCTAssertEqual(restored.items.first?.collectionName, item.collectionName)

    let migratedDatabaseText = try databaseText()
    XCTAssertTrue(migratedDatabaseText.contains(ClipboardEncryptionService.marker))
    XCTAssertFalse(migratedDatabaseText.contains(item.displayText))
    XCTAssertFalse(migratedDatabaseText.contains(item.payload))
    XCTAssertFalse(migratedDatabaseText.contains(item.payloadHash))
    XCTAssertFalse(migratedDatabaseText.contains(item.sourceApp!))
    XCTAssertFalse(migratedDatabaseText.contains(item.sourceAppBundleId!))
    XCTAssertFalse(migratedDatabaseText.contains(item.ocrText!))
    XCTAssertFalse(migratedDatabaseText.contains(item.collectionName!))
  }

  func testDuplicatePDFReplacementRemovesOldAttachment() throws {
    let settings = makeSettings(maxHistory: 50)
    let store = makeStore(settings: settings)
    let hash = "same-pdf"
    let oldPath = try XCTUnwrap(cacheService.cachePDF(Data("old".utf8), id: UUID()))
    let newPath = try XCTUnwrap(cacheService.cachePDF(Data("new".utf8), id: UUID()))

    store.upsert(makePDFItem(path: oldPath, hash: hash, created: Date(timeIntervalSince1970: 10)))
    store.upsert(makePDFItem(path: newPath, hash: hash, created: Date(timeIntervalSince1970: 20)))
    store.flushPersistenceForTesting()
    cacheService.flushForTesting()

    XCTAssertEqual(store.items.count, 1)
    XCTAssertEqual(store.items.first?.payload, newPath)
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath))
    XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
  }

  func testDuplicateReplacementClearsStaleImageSearchMetadata() throws {
    let settings = makeSettings(maxHistory: 50)
    settings.keepFirstImage = false
    let store = makeStore(settings: settings)
    let staleImage = try XCTUnwrap(cacheService.cacheImage(makeImage(color: .systemBlue), id: UUID()))
    let hash = "same-content"
    let imageItem = makeImageItem(
      fullPath: staleImage.full,
      thumbPath: staleImage.thumb,
      hash: hash,
      ocrText: "stale search marker",
      created: Date(timeIntervalSince1970: 10)
    )
    let textItem = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Replacement text",
      payload: "Replacement text",
      payloadHash: hash,
      createdAt: Date(timeIntervalSince1970: 20),
      lastUsedAt: Date(timeIntervalSince1970: 20),
      useCount: 1,
      sourceApp: "Notes",
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: "com.apple.Notes",
      ocrText: nil
    )

    store.upsert(imageItem)
    store.upsert(textItem)
    store.flushPersistenceForTesting()
    cacheService.flushForTesting()

    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(store.items.count, 1)
    XCTAssertEqual(item.kind, .text)
    XCTAssertEqual(item.payload, textItem.payload)
    XCTAssertNil(item.imagePath)
    XCTAssertNil(item.thumbnailPath)
    XCTAssertNil(item.ocrText)
    XCTAssertFalse(item.searchableText.contains("stale search marker"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staleImage.full))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staleImage.thumb))
  }

  private func makeSettings(maxHistory: Int) -> SettingsModel {
    let settings = SettingsModel(defaults: defaults)
    settings.maxHistoryItems = maxHistory
    settings.pruneDuplicates = true
    settings.keepFirstImage = true
    return settings
  }

  private func makeStore(settings: SettingsModel) -> ClipboardStore {
    makeStore(settings: settings, encryptionService: noOpEncryptionService())
  }

  private func makeStore(settings: SettingsModel, encryptionService: ClipboardEncryptionService) -> ClipboardStore {
    ClipboardStore(
      settings: settings,
      cacheService: cacheService,
      baseURL: baseURL,
      encryptionService: encryptionService
    )
  }

  private func makeItem(_ payload: String, displayText: String, created: Date) -> ClipboardItem {
    let hash = settingsHash(for: payload)
    return ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: displayText,
      payload: payload,
      payloadHash: hash,
      createdAt: created,
      lastUsedAt: created,
      useCount: 1,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false
    )
  }

  private func makePDFItem(path: String, hash: String, created: Date) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: .pdf,
      displayText: "PDF",
      payload: path,
      payloadHash: hash,
      createdAt: created,
      lastUsedAt: created,
      useCount: 1,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false
    )
  }

  private func makeImageItem(fullPath: String, thumbPath: String, hash: String, ocrText: String?, created: Date) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: .image,
      displayText: "Image",
      payload: fullPath,
      payloadHash: hash,
      createdAt: created,
      lastUsedAt: created,
      useCount: 1,
      sourceApp: "Preview",
      imagePath: fullPath,
      thumbnailPath: thumbPath,
      isPinned: false,
      sourceAppBundleId: "com.apple.Preview",
      ocrText: ocrText
    )
  }

  private func makeImage(color: NSColor) -> NSImage {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }

  private func settingsHash(for payload: String) -> String {
    payload
  }

  private func posixPermissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int) & 0o777
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = try XCTUnwrap(attributes[.size] as? NSNumber)
    return size.int64Value
  }

  private func databaseText() throws -> String {
    let data = try Data(contentsOf: baseURL.appendingPathComponent("history.sqlite"))
    return String(decoding: data, as: UTF8.self)
  }

  private func noOpEncryptionService() -> ClipboardEncryptionService {
    ClipboardEncryptionService(keyProvider: { nil })
  }

  private func fixedEncryptionService(byte: UInt8 = 7) -> ClipboardEncryptionService {
    let keyData = Data(repeating: byte, count: 32)
    return ClipboardEncryptionService(keyProvider: { SymmetricKey(data: keyData) })
  }
}
