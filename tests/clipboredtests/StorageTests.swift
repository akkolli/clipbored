import AppKit
import CryptoKit
import SQLite3
import XCTest

@testable import ClipBored

class ClipBoredTestCase: XCTestCase {
  func makeDefaults() -> UserDefaults {
    let name = "com.clipbored.tests.\(UUID().uuidString)"
    addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    return UserDefaults(suiteName: name)!
  }

  func tempDirectory(file: StaticString = #filePath, line: UInt = #line) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipbored-tests-\(UUID().uuidString)")
    XCTAssertNoThrow(
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true), file: file, line: line)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  func plaintextEncryption() -> HistoryEncryption { HistoryEncryption(keyProvider: { nil }) }
  func makeHistory() -> (
    defaults: UserDefaults, settings: Preferences, cacheService: MediaCache, store: HistoryStore, baseURL: URL
  ) {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.maxHistoryItems = 50
    preferences.historyRetention = .forever
    let directory = tempDirectory()
    let encryption = plaintextEncryption()
    let cache = MediaCache(baseURL: directory, encryptionService: encryption)
    let store = HistoryStore(
      settings: preferences, cacheService: cache, baseURL: directory, encryptionService: encryption)
    return (defaults, preferences, cache, store, directory)
  }

  func cipher(byte: UInt8 = 7) -> HistoryEncryption {
    HistoryEncryption(keyProvider: { SymmetricKey(data: Data(repeating: byte, count: 32)) })
  }

  func makeImage(color: NSColor = .systemBlue, width: CGFloat = 24, height: CGFloat = 24) -> NSImage {
    NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
      color.setFill()
      rect.fill()
      NSColor.systemOrange.setFill()
      NSRect(x: width * 0.55, y: height * 0.15, width: width * 0.3, height: height * 0.7).fill()
      return true
    }
  }

  func cachedImage(using cache: MediaCache, width: CGFloat = 24, height: CGFloat = 24) throws -> Clip {
    let id = UUID()
    let paths = try XCTUnwrap(cache.cacheImage(makeImage(width: width, height: height), id: id))
    return clip(
      paths.full, kind: .image, title: "Image", at: time(100), app: "Preview", pinned: true, image: paths.full,
      thumbnail: paths.thumb, bundle: "com.apple.Preview", ocr: "existing text", collection: "Work",
      customTitle: "Screenshot", device: "Mac", id: id)
  }
  func posixPermissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int) & 0o777
  }
  @nonobjc func tempFile(contents: String) throws -> URL { try tempFile(contents: Data(contents.utf8)) }
  @nonobjc func tempFile(contents: Data) throws -> URL {
    let url = tempDirectory().appendingPathComponent("payload.txt")
    try contents.write(to: url)
    return url
  }
  func assertPrivate(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertEqual(try posixPermissions(url), 0o600, file: file, line: line)
    XCTAssertEqual(try posixPermissions(url.deletingLastPathComponent()), 0o700, file: file, line: line)
  }
  func imageFiles(in baseURL: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: baseURL.appendingPathComponent("images"), includingPropertiesForKeys: nil)
  }

  func eventually(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(1)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    XCTAssertTrue(condition(), file: file, line: line)
  }
  func drainMainQueue() {
    let done = expectation(description: "Pending UI callbacks completed")
    DispatchQueue.main.async { done.fulfill() }
    wait(for: [done], timeout: 1)
  }
  func clipboardText(
    _ text: String, url: String? = nil, rtf: Data? = nil, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(clipboard.string(forType: .string), text, file: file, line: line)
    XCTAssertEqual(clipboard.string(forType: .URL), url, file: file, line: line)
    XCTAssertEqual(clipboard.data(forType: .rtf), rtf, file: file, line: line)
  }
  var clipboard: NSPasteboard { .general }
  func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
  func fileURL(_ path: String) -> URL { URL(fileURLWithPath: path) }
}

func clip(
  _ payload: String, kind: ClipKind = .text, title: String? = nil, hash: String? = nil, at: Date = Date(),
  count: Int = 0, app: String? = nil, pinned: Bool = false, image: String? = nil, thumbnail: String? = nil,
  bundle: String? = nil, ocr: String? = nil, collection: String? = nil, customTitle: String? = nil,
  device: String? = nil, id: UUID = UUID()
) -> Clip {
  Clip(
    id: id, kind: kind, displayText: title ?? payload, payload: payload, payloadHash: hash ?? payload, createdAt: at,
    lastUsedAt: at, useCount: count, sourceApp: app, imagePath: image, thumbnailPath: thumbnail, isPinned: pinned,
    sourceAppBundleId: bundle, ocrText: ocr, collectionName: collection, customTitle: customTitle,
    sourceDeviceName: device)
}

func time(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

let mediaCases: [(kind: ClipKind, type: NSPasteboard.PasteboardType, ext: String, data: Data)] = [
  (.pdf, .pdf, "pdf", Data("%PDF-1.4\nClipBored\n%%EOF".utf8)),
  (.audio, .sound, "sound", Data([0, 1, 2, 3, 5, 8, 13])),
  (.video, VideoPayload.pasteboardTypes[0], "mp4", Data([0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50])),
  (.richText, .rtf, "rtf", Data("{\\rtf1\\ansi \\b Styled \\b0 clipboard text}".utf8)),
]

class HistoryTestCase: ClipBoredTestCase {
  lazy var resources = makeHistory()
  var defaults: UserDefaults { resources.defaults }
  var settings: Preferences { resources.settings }
  var store: HistoryStore { resources.store }
  var cache: MediaCache { resources.cacheService }
  var baseURL: URL { resources.baseURL }
  func resetHistory() { resources = makeHistory() }
  func makeStore(encryptionService: HistoryEncryption? = nil) -> HistoryStore {
    HistoryStore(
      settings: settings, cacheService: cache, baseURL: baseURL,
      encryptionService: encryptionService ?? plaintextEncryption())
  }
  func reload(_ original: HistoryStore) -> HistoryStore {
    original.flushPersistenceForTesting()
    let restored = HistoryStore(
      settings: original.settings, cacheService: original.cacheService, baseURL: original.baseURL,
      encryptionService: plaintextEncryption())
    restored.flushPersistenceForTesting()
    return restored
  }
  func flush() {
    store.flushPersistenceForTesting()
    cache.flushForTesting()
  }
  var persisted: [Clip] { reload(store).items }
  func databaseText() throws -> String {
    String(decoding: try Data(contentsOf: baseURL.appendingPathComponent("history.sqlite")), as: UTF8.self)
  }
}

final class HistoryTests: HistoryTestCase {
  func testArchivesPreserveSidecarsMetadataAndBoardMembership() throws {
    let image = try cachedImage(using: cache)
    let pdf = clip(
      try XCTUnwrap(cache.cachePDF(Data("%PDF backup".utf8), id: UUID())), kind: .pdf, hash: "pdf", at: time(100),
      device: "Mac")
    let note = clip("note", at: time(100), collection: "Read Later", customTitle: "Migration", device: "Studio Mac")
    [note, image, pdf].forEach { store.upsert($0) }
    flush()
    let url = baseURL.appendingPathComponent("backup.clipboredarchive")
    let summary = try store.exportArchive(to: url)
    XCTAssertEqual([summary.itemCount, summary.sidecarCount], [3, 3])
    XCTAssertEqual(try posixPermissions(url), 0o600)
    let destination = makeHistory()
    destination.store.upsert(clip("destination", hash: "destination", at: time(200), device: "Mac"))
    let imported = try destination.store.importArchive(from: url)
    XCTAssertEqual([imported.itemCount, imported.sidecarCount], [3, 3])
    for original in [note, image, pdf] {
      var expected = original
      let actual = try XCTUnwrap(destination.store.items.first { $0.id == original.id })
      for key in [\Clip.imagePath, \Clip.thumbnailPath] {
        if let source = original[keyPath: key] {
          let path = try XCTUnwrap(actual[keyPath: key])
          XCTAssertTrue(path.hasPrefix(destination.baseURL.path))
          XCTAssertEqual(destination.cacheService.data(for: path), cache.data(for: source))
          expected[keyPath: key] = path
        }
      }
      if original.kind == .pdf {
        XCTAssertTrue(actual.payload.hasPrefix(destination.baseURL.path))
        XCTAssertEqual(destination.cacheService.data(for: actual.payload), cache.data(for: original.payload))
        expected.payload = actual.payload
      }
      if original.kind == .image { expected.payload = actual.payload }
      XCTAssertEqual(actual, expected)
    }
    let reloaded = reload(destination.store)
    XCTAssertEqual(reloaded.items, destination.store.items)
    XCTAssertEqual(reloaded.items.count, 4)
    for populated in [false, true] {
      resetHistory()
      settings.ensureCollection(named: "Work", colorHex: "#3366FF")
      if populated {
        [clip("member", collection: "Work"), clip("outside", hash: "outside")].forEach { store.upsert($0) }
      }
      flush()
      let url = baseURL.appendingPathComponent("board.clipboredarchive")
      XCTAssertEqual(try store.exportCollection(named: "Work", to: url).itemCount, populated ? 1 : 0)
      let destination = makeHistory()
      XCTAssertEqual(try destination.store.importArchive(from: url).itemCount, populated ? 1 : 0)
      XCTAssertEqual(destination.store.items.map(\.payload), populated ? ["member"] : [])
      XCTAssertEqual(destination.settings.customCollectionNames, ["Work"])
      XCTAssertEqual(destination.settings.collectionColorHex(forCollectionNamed: "Work"), "#3366FF")
    }
  }

  func testAttachmentReplacementAndUndoRespectMediaOwnership() throws {
    for (image, keep) in [(false, false), (true, false), (true, true)] {
      resetHistory()
      settings.keepFirstImage = keep
      let old =
        image
        ? try cachedImage(using: cache) : clip(try XCTUnwrap(cache.cachePDF(Data("old".utf8), id: UUID())), kind: .pdf)
      let replacement =
        image
        ? (keep ? try cachedImage(using: cache) : clip("Replacement", app: "Notes"))
        : clip(try XCTUnwrap(cache.cachePDF(Data("new".utf8), id: UUID())), kind: .pdf)
      var duplicate = replacement
      duplicate.payloadHash = old.payloadHash
      [old, duplicate].forEach { store.upsert($0) }
      flush()
      let actual = try XCTUnwrap(persisted.first)
      let expected = keep ? old : replacement
      XCTAssertEqual(store.items.count, 1)
      XCTAssertEqual(actual.payload, expected.payload)
      for path in [old.payload, old.thumbnailPath].compactMap({ $0 }) { XCTAssertEqual(exists(path), keep) }
      let discarded = keep ? duplicate : old
      for path in [discarded.payload, discarded.thumbnailPath].compactMap({ $0 }) { XCTAssertFalse(exists(path)) }
      XCTAssertEqual(actual.ocrText, expected.ocrText)
      XCTAssertEqual(actual.imagePath, expected.imagePath)
      if !image { XCTAssertEqual(cache.data(for: replacement.payload), Data("new".utf8)) }
    }
    resetHistory()
    let image = try cachedImage(using: cache)
    store.upsert(image)
    flush()
    let removal = try XCTUnwrap(store.remove(image.id, purgeManagedCache: false))
    flush()
    XCTAssertTrue(store.items.isEmpty)
    for path in [image.payload, image.thumbnailPath!] { XCTAssertTrue(exists(path)) }
    store.restore([removal])
    XCTAssertEqual(try XCTUnwrap(persisted.first), image)
    _ = store.remove(image.id)
    flush()
    for path in [image.payload, image.thumbnailPath!] { XCTAssertFalse(exists(path)) }
  }

  func testLegacyJSONMigratesMissingDeviceMetadataToSQLite() throws {
    let id = UUID()
    let record: [String: Any] = [
      "id": id.uuidString, "kind": 0, "displayText": "Legacy", "payload": "legacy", "payloadHash": "legacy-hash",
      "createdAt": "2026-06-27T12:00:00Z", "lastUsedAt": "2026-06-27T12:01:00Z", "useCount": 3,
    ]
    try JSONSerialization.data(withJSONObject: [record]).write(to: baseURL.appendingPathComponent("history.json"))
    let migrated = makeStore()
    migrated.flushPersistenceForTesting()
    XCTAssertEqual(migrated.items.first?.id, id)
    XCTAssertEqual(migrated.items.first?.payload, "legacy")
    XCTAssertEqual(migrated.items.first?.useCount, 3)
    XCTAssertEqual(migrated.items.first?.sourceDeviceName, Clip.localDeviceName)
    XCTAssertEqual(reload(migrated).items.first?.sourceDeviceName, Clip.localDeviceName)
  }

  func testDuplicateUsageLabelsAndTextEditsPersistMetadata() throws {
    let old = time(Date().timeIntervalSince1970.rounded(.down) - 172800)
    for (payload, date) in [("one", old), ("two", old.addingTimeInterval(-10)), ("three", old.addingTimeInterval(-20))]
    { store.upsert(clip(payload, hash: payload, at: date, count: 1)) }
    store.upsert(clip("one", title: "Updated", hash: "one", at: old, count: 1))
    let first = try XCTUnwrap(store.items.first)
    XCTAssertGreaterThan(first.createdAt, old)
    XCTAssertEqual(store.items.map(\.payload), ["one", "three", "two"])
    store.markUsed(first.id)
    store.togglePin(first.id)
    let restored = try XCTUnwrap(persisted.first)
    XCTAssertEqual(restored.useCount, 3)
    XCTAssertTrue(restored.isPinned)
    XCTAssertEqual(restored.displayText, "Updated")
    settings.historyRetention = .oneDay
    store.normalizeHistoryLength()
    XCTAssertEqual(store.items.map(\.payload), ["one"])
    resetHistory()
    var item = clip("alpha", at: time(100), device: "Mac")
    store.upsert(item)
    store.setCollection(item.id, name: "  Client   Work  ")
    store.setCustomTitle(item.id, title: "  Launch   Brief  ")
    XCTAssertEqual(persisted.first?.collectionName, "Client Work")
    XCTAssertEqual(persisted.first?.customTitle, "Launch Brief")
    store.setCollection(item.id, name: nil)
    store.setCustomTitle(item.id, title: "   ")
    XCTAssertEqual(persisted.first!, item)
    resetHistory()
    item = clip(
      "alpha", at: time(100), count: 4, app: "Notes", pinned: true, collection: "Important", device: "Studio Mac")
    store.upsert(item)
    store.observeItems { XCTAssertEqual($0.first?.payload, $0.first?.displayText) }
    XCTAssertTrue(store.updateText(item.id, text: "Edited"))
    item.payload = "Edited"
    item.displayText = "Edited"
    item.payloadHash = store.hashString("Edited")
    XCTAssertEqual(try XCTUnwrap(persisted.first), item)
    let pdf = clip("/tmp/report.pdf", kind: .pdf, hash: "pdf")
    store.upsert(pdf)
    XCTAssertFalse(store.updateText(pdf.id, text: "Edited"))
    XCTAssertEqual(try XCTUnwrap(store.items.first { $0.id == pdf.id }), pdf)
  }

  func testRetentionAndOverflowPreserveProtectedHistory() throws {
    for index in 0...50 { store.upsert(clip("item-\(index)", hash: "\(index)", at: time(Double(index)))) }
    XCTAssertEqual(persisted.map(\.payload), (1...50).reversed().map { "item-\($0)" })
    for pin in [false, true] {
      resetHistory()
      let saved = clip("saved", at: time(0), pinned: pin, collection: pin ? nil : "Work")
      store.upsert(saved)
      for index in 0..<60 { store.upsert(clip("\(index)", hash: "\(index)", at: time(Double(index + 1)))) }
      XCTAssertEqual(persisted.count, 51)
      XCTAssertTrue(
        persisted.contains { $0.id == saved.id && $0.isPinned == pin && $0.collectionName == saved.collectionName })
      if pin { store.togglePin(saved.id) } else { store.setCollection(saved.id, name: nil) }
      XCTAssertEqual(persisted.count, 50)
      XCTAssertFalse(persisted.contains { $0.id == saved.id })
    }
    resetHistory()
    settings.historyRetention = .oneDay
    let old = time(Date().timeIntervalSince1970.rounded(.down) - 172800)
    let survivors = [
      clip("pinned", hash: "pinned", at: old, pinned: true, device: "Mac"),
      clip("board", hash: "board", at: old, collection: "Work", device: "Mac"),
      clip("recent", hash: "recent", at: time(Date().timeIntervalSince1970.rounded(.down)), device: "Mac"),
    ]
    ([clip("expired", at: old)] + survivors).forEach { store.upsert($0) }
    XCTAssertEqual(Set(persisted.map(\.payload)), Set(survivors.map(\.payload)))
    for item in survivors { XCTAssertEqual(persisted.first { $0.id == item.id }, item) }
  }

  func testPrivateStorageAndEnvironmentOverride() throws {
    store.upsert(clip("private"))
    flush()
    try assertPrivate(baseURL.appendingPathComponent("history.sqlite"))
    var lockedDB: OpaquePointer?
    XCTAssertEqual(sqlite3_open(baseURL.appendingPathComponent("history.sqlite").path, &lockedDB), SQLITE_OK)
    defer { sqlite3_close(lockedDB) }
    XCTAssertEqual(sqlite3_exec(lockedDB, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil), SQLITE_OK)
    XCTAssertFalse(store.saveAll([clip("blocked")]))
    XCTAssertEqual(sqlite3_exec(lockedDB, "ROLLBACK;", nil, nil, nil), SQLITE_OK)
    XCTAssertEqual(persisted.map(\.payload), ["private"])
    let override = baseURL.appendingPathComponent("Override")
    let key = Configuration.storageDirectoryOverrideEnvironmentKey
    let previous = getenv(key).map { String(cString: $0) }
    setenv(key, override.path, 1)
    defer { if let previous { setenv(key, previous, 1) } else { unsetenv(key) } }
    XCTAssertEqual(HistoryStore.storageDirectory().path, override.standardizedFileURL.path)
    XCTAssertEqual(try posixPermissions(override), 0o700)
  }

  func testEncryptionMigrationAndClearProtectAndCompactStorage() throws {
    var resets = 0
    let encryption = HistoryEncryption(
      keyProvider: { SymmetricKey(data: Data(repeating: 7, count: 32)) }, resetProvider: { resets += 1 })
    let encrypted = makeStore(encryptionService: encryption)
    for index in 0..<60 {
      encrypted.upsert(clip(String(repeating: "compaction payload ", count: 400) + "\(index)", hash: "\(index)"))
    }
    encrypted.flushPersistenceForTesting()
    let url = baseURL.appendingPathComponent("history.sqlite")
    let before = try Data(contentsOf: url).count
    XCTAssertGreaterThan(before, 200000)
    _ = encrypted.remove(encrypted.items[0].id)
    encrypted.flushPersistenceForTesting()
    XCTAssertEqual(resets, 0)
    encrypted.removeAll()
    encrypted.flushPersistenceForTesting()
    XCTAssertEqual(resets, 1)
    XCTAssertLessThan(try Data(contentsOf: url).count, before / 2)
    XCTAssertEqual(try posixPermissions(url), 0o600)
    let restored = makeStore(encryptionService: encryption)
    restored.flushPersistenceForTesting()
    XCTAssertTrue(restored.items.isEmpty)
    for legacy in [false, true] {
      resetHistory()
      let encryption = cipher()
      let original = makeStore(encryptionService: legacy ? plaintextEncryption() : encryption)
      let item = clip(
        "Payload secret", title: "Displayed secret", hash: "Hash secret", at: time(100), app: "Secret app",
        bundle: "com.example.secret", ocr: "OCR secret", collection: "Collection secret", customTitle: "Custom secret",
        device: "Device secret")
      original.upsert(item)
      original.flushPersistenceForTesting()
      if legacy { XCTAssertTrue(try databaseText().contains(item.payload)) }
      let restored = makeStore(encryptionService: encryption)
      restored.flushPersistenceForTesting()
      XCTAssertEqual(try XCTUnwrap(restored.items.first), item)
      let raw = try databaseText()
      XCTAssertTrue(raw.contains(HistoryEncryption.marker))
      for secret in [
        item.payload, item.displayText, item.payloadHash, item.sourceApp!, item.sourceAppBundleId!, item.ocrText!,
        item.collectionName!, item.customTitle!, item.sourceDeviceName!,
      ] { XCTAssertFalse(raw.contains(secret)) }
    }
  }

}

final class MediaCacheTests: ClipBoredTestCase {
  lazy var baseURL = tempDirectory()
  lazy var cache = MediaCache(baseURL: baseURL, encryptionService: cipher())
  override func tearDown() {
    cache.clearTemporaryPreviews(wait: true)
    super.tearDown()
  }

  private func resetCache() {
    cache.clearTemporaryPreviews(wait: true)
    baseURL = tempDirectory()
    cache = MediaCache(baseURL: baseURL, encryptionService: cipher())
  }

  func testEncryptedMediaPreviewsAndLegacyReferencesRespectOwnership() throws {
    let images = try (0..<2).map { _ in try cachedImage(using: cache) }
    for image in images {
      for path in [image.payload, image.thumbnailPath!] {
        let raw = try Data(contentsOf: fileURL(path))
        XCTAssertTrue(HistoryEncryption.isProtected(raw))
        XCTAssertNil(NSImage(data: raw))
        XCTAssertNotNil(cache.image(for: path))
        XCTAssertEqual(try posixPermissions(fileURL(path)), 0o600)
      }
    }
    cache.purgeIfNeeded(maxBytes: 1)
    cache.flushForTesting()
    XCTAssertEqual(
      Set(try imageFiles(in: baseURL).map(\.lastPathComponent)),
      Set(images.map { fileURL($0.payload).lastPathComponent }))
    let pdf = try XCTUnwrap(cache.cachePDF(Data("%PDF preview".utf8), id: UUID()))
    let preview = try XCTUnwrap(cache.temporaryReadableURL(for: clip(pdf, kind: .pdf)))
    cache.clearCache()
    cache.flushForTesting()
    XCTAssertFalse(exists(preview.path))
    XCTAssertTrue(exists(pdf))
    for image in images { XCTAssertNotNil(cache.previewThumbnail(for: image)) }
    resetCache()
    for media in mediaCases {
      let path = try XCTUnwrap(cache.cacheAttachmentData(media.data, id: UUID(), fileExtension: media.ext))
      XCTAssertTrue(HistoryEncryption.isProtected(try Data(contentsOf: fileURL(path))))
      XCTAssertEqual(cache.data(for: path), media.data)
      XCTAssertEqual(try posixPermissions(fileURL(path)), 0o600)
      let preview = try XCTUnwrap(cache.temporaryReadableURL(for: clip(path, kind: media.kind)))
      XCTAssertEqual(try Data(contentsOf: preview), media.data)
      XCTAssertEqual(preview.pathExtension, media.ext)
      try assertPrivate(preview)
      cache.clearTemporaryPreviews(wait: true)
      XCTAssertFalse(exists(preview.path))
    }
    resetCache()
    let legacy = baseURL.appendingPathComponent("attachments/legacy.pdf")
    let data = Data("%PDF legacy".utf8)
    try data.write(to: legacy)
    XCTAssertEqual(cache.data(for: legacy.path), data)
    XCTAssertTrue(HistoryEncryption.isProtected(try Data(contentsOf: legacy)))
    let original = try tempFile(contents: "original")
    let thumbnail = original.deletingLastPathComponent().appendingPathComponent("preview.png")
    try Data("preview".utf8).write(to: thumbnail)
    let alias = baseURL.appendingPathComponent("images/escape")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original.deletingLastPathComponent())
    cache.removeCachedReferences(
      clip(
        original.path, kind: .image, image: original.path, thumbnail: alias.appendingPathComponent("preview.png").path))
    cache.flushForTesting()
    XCTAssertEqual(try String(contentsOf: original), "original")
    XCTAssertEqual(try String(contentsOf: thumbnail), "preview")
  }

  func testNativeAndPrivatePreviewsCoalesceAndPreserveRepresentations() throws {
    let imageURL = try tempFile(contents: XCTUnwrap(makeImage(color: .systemOrange).pngData()))
    XCTAssertNotNil(cache.previewThumbnail(for: clip(imageURL.path, kind: .file)))
    let pdf = try XCTUnwrap(cache.cachePDF(makePDFData(), id: UUID()))
    XCTAssertNotNil(cache.previewThumbnail(for: clip(pdf, kind: .pdf)))
    let video = mediaCases.first { $0.kind == .video }!
    var requests: [URL] = []
    let videoCache = MediaCache(
      baseURL: baseURL, encryptionService: cipher(),
      videoThumbnailProvider: { url in
        requests.append(url)
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertEqual(try? Data(contentsOf: url), video.data)
        return self.makeImage(color: .systemIndigo)
      })
    let path = try XCTUnwrap(videoCache.cacheAttachmentData(video.data, id: UUID(), fileExtension: "mp4"))
    let item = clip(path, kind: .video)
    for _ in 0..<2 { XCTAssertNotNil(videoCache.previewThumbnail(for: item)) }
    XCTAssertEqual(requests.count, 1)
    XCTAssertFalse(exists(try XCTUnwrap(requests.first).path))
    resetCache()
    let original = try tempFile(contents: "Report")
    XCTAssertEqual(
      cache.temporaryPreviewURL(for: clip(original.path, kind: .file))?.standardizedFileURL,
      original.standardizedFileURL)
    for item in [clip("Quick Look text"), clip("https://example.com/releases", kind: .url)] {
      let preview = try XCTUnwrap(cache.temporaryPreviewURL(for: item))
      try assertPrivate(preview)
      if item.kind == .text {
        XCTAssertEqual(preview.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: preview), item.payload)
      } else {
        XCTAssertEqual(preview.pathExtension, "webloc")
        let plist = try XCTUnwrap(
          PropertyListSerialization.propertyList(from: Data(contentsOf: preview), format: nil) as? [String: String])
        XCTAssertEqual(plist["URL"], item.payload)
      }
    }
  }

  private func makePDFData() throws -> Data {
    let data = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
    var box = CGRect(x: 0, y: 0, width: 160, height: 120)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.systemOrange.cgColor)
    context.fill(box)
    context.endPDFPage()
    context.closePDF()
    return data as Data
  }
}

final class ArchiveSyncTests: HistoryTestCase {
  func testCloudAvailabilityMissingArchiveAndPrivateRoundTrip() throws {
    let unavailable = ArchiveSync(containerProvider: { nil })
    let unavailableStatus = unavailable.status()
    XCTAssertFalse(unavailableStatus.isAvailable)
    XCTAssertNil(unavailableStatus.archiveURL)
    XCTAssertTrue(unavailableStatus.message.contains("iCloud Sync is unavailable"))
    XCTAssertThrowsError(try unavailable.syncArchiveURL()) { XCTAssertEqual($0 as? ArchiveSyncError, .unavailable) }
    let item = clip("shared through icloud", at: time(20), device: "Mac")
    store.upsert(item)
    let root = tempDirectory()
    let service = ArchiveSync(containerProvider: { root })
    let url = try service.syncArchiveURL()
    XCTAssertThrowsError(try service.pull(store: makeHistory().store)) {
      XCTAssertEqual($0 as? ArchiveSyncError, .noRemoteArchive(url))
    }
    XCTAssertEqual(try service.push(store: store).itemCount, 1)
    XCTAssertEqual(
      url, root.appendingPathComponent("Documents/\(Configuration.storageName)/\(ArchiveSync.archiveFileName)"))
    XCTAssertEqual(try posixPermissions(url), 0o600)
    let status = service.status()
    XCTAssertTrue(status.isAvailable)
    XCTAssertEqual(status.archiveURL, url)
    XCTAssertNotNil(status.lastModifiedAt)
    let destination = makeHistory()
    XCTAssertEqual(try service.pull(store: destination.store).itemCount, 1)
    destination.store.flushPersistenceForTesting()
    XCTAssertEqual(try XCTUnwrap(destination.store.items.first), item)

  }

}

final class HistoryEncryptionTests: ClipBoredTestCase {
  func testStringsAndBinaryEncryptionRejectWrongKeys() throws {
    let service = cipher()
    for value in ["secret clipboard value", "plain clipboard value", HistoryEncryption.marker + "user text"] {
      let protected = try XCTUnwrap(service.protect(value))
      XCTAssertTrue(HistoryEncryption.isProtected(protected))
      XCTAssertFalse(protected.contains(value))
      XCTAssertEqual(service.unprotect(protected), value)
      XCTAssertEqual(service.unprotect(value), value)
      XCTAssertNil(cipher(byte: 9).unprotect(protected))
    }
    let data = Data(0..<128)
    let protected = service.protectData(data)
    XCTAssertTrue(HistoryEncryption.isProtected(protected))
    XCTAssertNotEqual(protected, data)
    XCTAssertEqual(service.unprotectData(protected), data)
    XCTAssertNil(cipher(byte: 9).unprotectData(protected))
  }
  func testUnavailableKeyAndTestEnvironmentBypass() {
    let service = plaintextEncryption()
    XCTAssertEqual(service.protect("only in memory"), "only in memory")
    XCTAssertEqual(service.protectData(Data("only in memory".utf8)), Data("only in memory".utf8))
    let app = "/Applications/ClipBored.app/Contents/MacOS/ClipBored"
    for (environment, arguments, expected) in [
      (["XCTestConfigurationFilePath": "/tmp/tests"], [app], true), (["CLIPBORED_DISABLE_KEYCHAIN": "1"], [app], true),
      ([:], ["/tmp/ClipBoredPackageTests.xctest/Contents/MacOS/ClipBoredPackageTests"], true), ([:], [app], false),
    ] {
      XCTAssertEqual(
        HistoryEncryption.shouldBypassSystemKeychain(environment: environment, arguments: arguments), expected)
    }
  }
}

final class CaptureTests: CaptureTestCase {
  func testCapturePriorityAndIgnoredKindsDoNotCacheRejectedContent() throws {
    for ignored in [false, true] {
      settings.ignoredItemKindsRaw = ignored ? [ClipKind.pdf.rawValue] : []
      let expected = clip("first usable")
      var reads: [ClipKind] = []
      var probes: [ClipKind] = []
      func present(_ kind: ClipKind) -> Bool {
        probes.append(kind)
        return true
      }
      func read(_ kind: ClipKind, _ value: Clip? = nil) -> Clip? {
        reads.append(kind)
        return value
      }
      let result = monitor.readInPriorityOrder([
        (.color, { present(.color) }, { read(.color, ignored ? nil : expected) }),
        (.pdf, { present(.pdf) }, { read(.pdf) }), (.richText, { present(.richText) }, { read(.richText) }),
      ])
      XCTAssertEqual(reads, [.color])
      XCTAssertEqual(probes, ignored ? [.pdf] : [])
      if ignored {
        guard case .ignored(.pdf) = result else { return XCTFail("Expected ignored PDF") }
      } else {
        guard case .captured(let item) = result else { return XCTFail("Expected capture") }
        XCTAssertEqual(item.id, expected.id)
      }
    }
    var cases: [(ClipKind, (NSPasteboard) -> Void)] = mediaCases.map { media in
      (media.kind, { XCTAssertTrue($0.setData(media.data, forType: media.type)) })
    }
    cases += [
      (.richText, { XCTAssertTrue($0.setData(Data("<b>Ignored HTML</b>".utf8), forType: .html)) }),
      (.image, { XCTAssertTrue($0.writeObjects([self.makeImage(color: .systemOrange)])) }),
      (.color, { XCTAssertTrue($0.writeObjects([NSColor.systemBlue])) }),
      (
        .code,
        { XCTAssertTrue($0.setString("const title = \"ClipBored\";\nreturn title.toUpperCase();", forType: .string)) }
      ),
    ]
    for (kind, write) in cases {
      resetCapture()
      settings.ignoredItemKindsRaw = [kind.rawValue]
      clipboard.clearContents()
      write(clipboard)
      monitor.pollNowAndWait()
      RunLoop.main.run(until: Date().addingTimeInterval(0.03))
      cache.flushForTesting()
      XCTAssertTrue(store.items.isEmpty, kind.displayName)
      XCTAssertTrue(try imageFiles(in: baseURL).isEmpty)
      XCTAssertTrue(
        try FileManager.default.contentsOfDirectory(atPath: baseURL.appendingPathComponent("attachments").path).isEmpty)
      XCTAssertEqual(
        settings.captureStatusMessage,
        "Skipped: \(kind == .pdf ? "PDF" : kind.displayName.capitalized) items are ignored in capture settings.")
    }
  }

  func testNativeAttachmentsAndColorCaptureCopyRepresentations() throws {
    let html = (ClipKind.richText, NSPasteboard.PasteboardType.html, "rtf", Data("<b>Styled</b> clipboard text".utf8))
    for media in mediaCases + [html] {
      resetCapture()
      let item = try capture { XCTAssertTrue(clipboard.setData(media.data, forType: media.type)) }
      XCTAssertEqual(item.kind, media.kind)
      let cached = try XCTUnwrap(cache.data(for: item.payload))
      if media.type != .html { XCTAssertEqual(cached, media.data) }
      if media.kind == .richText {
        XCTAssertEqual(NSAttributedString(rtf: cached, documentAttributes: nil)?.string, "Styled clipboard text")
      }
    }
    resetCapture()
    let item = try capture {
      XCTAssertTrue(clipboard.writeObjects([NSColor(deviceRed: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)]))
    }
    XCTAssertEqual(item.kind, .color)
    XCTAssertEqual([item.payload, item.displayText], ["#0A84FF", "#0A84FF"])
    let service = PasteService(cacheService: cache)
    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(ColorPayload.hexString(from: try XCTUnwrap(NSColor(from: clipboard))), "#0A84FF")
    XCTAssertEqual(service.copyPlainText(item), .copiedPlainText)
    XCTAssertEqual(clipboard.string(forType: .string), "#0A84FF")
  }

  func testFilesAndWebContentPrecedenceClassificationAndCopies() throws {
    for (count, fallback) in [(1, false), (2, false), (1, true)] {
      resetCapture()
      let urls = try (0..<count).map { try tempFile(contents: "file \($0)") }
      let payload = FilePayload.payload(from: urls)
      let item = try capture {
        XCTAssertTrue(clipboard.writeObjects(urls.map { $0 as NSURL }))
        if fallback { XCTAssertTrue(clipboard.setString(payload, forType: .string)) }
      }
      XCTAssertEqual(item.kind, .file)
      XCTAssertEqual(item.payload, payload)
      if count == 2 { XCTAssertEqual(item.displayText, "2 files") }
      XCTAssertEqual(PasteService(cacheService: cache).copy(item), .copied)
      let restored = clipboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
      XCTAssertEqual(restored?.map(\.standardizedFileURL), urls.map(\.standardizedFileURL))
    }
    resetCapture()
    let url = "https://example.com/lookbook"
    let item = try capture {
      XCTAssertTrue(clipboard.setString(url, forType: .URL))
      XCTAssertTrue(clipboard.setString("Lookbook", forType: NSPasteboard.PasteboardType("public.url-name")))
      XCTAssertTrue(clipboard.setData(try XCTUnwrap(makeImage(color: .systemTeal).tiffRepresentation), forType: .tiff))
    }
    XCTAssertEqual(item.kind, .url)
    XCTAssertEqual(item.displayText, "Lookbook")
    XCTAssertNotNil(cache.previewThumbnail(for: item))
    resetCapture()
    settings.ignoredItemKindsRaw = [ClipKind.file.rawValue]
    XCTAssertEqual(try capture { XCTAssertTrue(clipboard.writeObjects([NSURL(string: url)!])) }.payload, url)
    let releaseURL = "https://example.com/releases"
    for (payload, kind, title, type, extra) in [
      ("func greet() {\n  return \"Hi\"\n}", ClipKind.code, "Swift Snippet", nil, nil),
      (releaseURL, .url, releaseURL, nil, nil),
      (releaseURL, .url, "Release notes", NSPasteboard.PasteboardType("public.url-name"), "Release notes"),
      (releaseURL, .url, "Read the release notes", .html, "<a href=\"\(releaseURL)\">Read the release notes</a>"),
      ("Review \(releaseURL) before shipping", .text, "Review \(releaseURL) before shipping", nil, nil),
    ] as [(String, ClipKind, String, NSPasteboard.PasteboardType?, String?)] {
      resetCapture()
      let item = try capture {
        if let type, let extra {
          XCTAssertTrue(clipboard.setString(payload, forType: .URL))
          XCTAssertTrue(clipboard.setString(extra, forType: type))
        }
        XCTAssertTrue(clipboard.setString(payload, forType: .string))
      }
      XCTAssertEqual(item.kind, kind)
      XCTAssertEqual(item.payload, payload)
      XCTAssertEqual(item.displayText, title)
    }
  }

  func testOCRCaptureIdentityDuplicatesAndSelfWriteSuppression() throws {
    for enabled in [false, true] {
      resetCapture()
      settings.includeImageTextInSearch = enabled
      var calls = 0
      monitor = CaptureMonitor(
        store: store, cacheService: cache, settings: settings,
        imageTextExtractor: { _ in
          calls += 1
          return "  Receipt total $42\nOrder 1001  "
        })
      let item = try capture { XCTAssertTrue(clipboard.writeObjects([makeImage(color: .systemOrange)])) }
      XCTAssertEqual(item.kind, .image)
      XCTAssertEqual(item.ocrText, enabled ? "Receipt total $42 Order 1001" : nil)
      XCTAssertEqual(calls, enabled ? 1 : 0)
      XCTAssertNotNil(cache.image(for: item.payload))
    }
    resetCapture()
    let text = "Capture \(UUID().uuidString)"
    let existing = clip(text, hash: store.hashString(text), at: time(100))
    store.upsert(existing)
    let item = try capture { XCTAssertTrue(clipboard.setString(text, forType: .string)) }
    XCTAssertEqual(item.id, existing.id)
    monitor.pollNowAndWait()
    XCTAssertEqual(store.items.filter { $0.payload == text }.count, 1)
    resetCapture()
    XCTAssertEqual(PasteService(cacheService: cache).copy(clip("Internal copy")), .copied)
    monitor.pollNowAndWait()
    XCTAssertTrue(store.items.isEmpty)
  }

  func testPollingProfilesAndSensitiveURLValidationBeforeCaching() throws {
    var changes: [Preferences.Change] = []
    settings.observe { changes.append($0) }
    settings.pollProfile = .responsive
    XCTAssertEqual(changes, [.pollProfile])
    for (input, expected) in [(0.03, 0.075), (0.05, 0.075), (0.075, 0.075), (0.25, 0.25)] {
      XCTAssertEqual(monitor.clampedInterval(input), expected)
    }
    for (profile, idle) in [(Configuration.PollProfile.balanced, 0.25), (.battery, 0.5), (.responsive, 0.12)] {
      settings.pollProfile = profile
      monitor.setPaused(false)
      XCTAssertEqual(monitor.scheduledIntervalForTesting, idle)
    }
    resetCapture()
    let url = "https://example.com/?api_key=sk-proj-abcdefghijklmnopqrstuvwxyz1234567890"
    for exclude in [true, false] {
      settings.excludeSensitive = exclude
      clipboard.clearContents()
      XCTAssertTrue(clipboard.setString(url, forType: .URL))
      XCTAssertTrue(clipboard.setString(url, forType: .string))
      XCTAssertTrue(clipboard.setData(try XCTUnwrap(makeImage(color: .systemBlue).pngData()), forType: .png))
      monitor.pollNowAndWait()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      cache.flushForTesting()
      XCTAssertEqual(store.items.count, exclude ? 0 : 1)
      if exclude {
        XCTAssertTrue(try imageFiles(in: baseURL).isEmpty)
        XCTAssertEqual(settings.captureStatusMessage, "Skipped: Copy was ignored because it looks sensitive.")
      } else {
        XCTAssertNotNil(store.items.first?.thumbnailPath)
      }
    }
  }

}

final class PasteTests: ClipBoredTestCase {
  lazy var cache = MediaCache(baseURL: tempDirectory(), encryptionService: cipher())
  lazy var service = PasteService(cacheService: cache)

  func testPasteActivationAndSingleBatchPlainRichRepresentations() throws {
    XCTAssertEqual(service.paste(clip("No target"), targetApp: nil), .copied)
    let target = NSRunningApplication.current
    for (trusted, activates, plain, expected) in [
      (true, true, false, PasteService.PasteActionResult.pasted), (true, true, true, .pastedPlainText),
      (true, false, false, .copied), (false, true, false, .copiedNeedsPermission),
    ] {
      var activated: pid_t?
      var scheduled = false
      let service = PasteService(
        cacheService: cache, accessibilityPermissionProvider: { trusted },
        targetActivator: {
          activated = $0.processIdentifier
          return activates
        }, keyboardPasteScheduler: { _ in scheduled = true })
      let item = clip("https://apple.com", kind: .url, title: "Apple")
      XCTAssertEqual(
        plain ? service.pastePlainText(item, targetApp: target) : service.paste(item, targetApp: target), expected)
      XCTAssertEqual(activated, trusted ? target.processIdentifier : nil)
      XCTAssertEqual(scheduled, trusted && activates)
      clipboardText(item.payload, url: plain ? nil : item.payload)
    }
    let link = clip("https://apple.com", kind: .url, title: "Apple")
    for item in [clip("Hello"), clip("func greet() {}", kind: .code), link] {
      for plain in [false, true] {
        XCTAssertEqual(plain ? service.copyPlainText(item) : service.copy(item), plain ? .copiedPlainText : .copied)
        clipboardText(item.payload, url: item.kind == .url && !plain ? item.payload : nil)
      }
    }
    XCTAssertEqual(service.copy([link, clip("Batch note")]), .copied)
    let items = try XCTUnwrap(clipboard.pasteboardItems)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].string(forType: .URL), link.payload)
    XCTAssertEqual(items[0].string(forType: NSPasteboard.PasteboardType("public.url-name")), "Apple")
    XCTAssertEqual(items[1].string(forType: .string), "Batch note")
    let data = mediaCases.last!.data
    let path = try XCTUnwrap(cache.cacheAttachmentData(data, id: UUID(), fileExtension: "rtf"))
    let item = clip(path, kind: .richText, title: "Styled clipboard text")
    for plain in [false, true] {
      XCTAssertEqual(plain ? service.copyPlainText(item) : service.copy(item), plain ? .copiedPlainText : .copied)
      clipboardText(item.displayText, rtf: plain ? nil : data)
    }
    for item in [
      clip("Legacy text", kind: .richText),
      clip(tempDirectory().appendingPathComponent("missing.rtf").path, kind: .richText, title: "Readable text"),
    ] {
      XCTAssertEqual(service.copy(item), .copied)
      clipboardText(item.displayText)
    }
  }

  func testAttachmentCopiesAndFailedClipboardTransactions() throws {
    for media in mediaCases where media.kind != .richText {
      let path = try XCTUnwrap(cache.cacheAttachmentData(media.data, id: UUID(), fileExtension: media.ext))
      let item = clip(path, kind: media.kind, title: media.kind.displayName.capitalized)
      XCTAssertEqual(service.copy(item), .copied)
      XCTAssertEqual(clipboard.data(forType: media.type), media.data)
      if media.kind == .video {
        XCTAssertEqual(service.copyPlainText(item), .copiedPlainText)
        XCTAssertEqual(clipboard.string(forType: .string), "Video")
      }
    }
    let pdf = try tempFile(contents: mediaCases[0].data)
    XCTAssertEqual(service.copy(clip(pdf.path, kind: .pdf)), .copied)
    XCTAssertEqual(clipboard.data(forType: .pdf), mediaCases[0].data)
    let missing = clip(tempDirectory().appendingPathComponent("missing").path, kind: .file)
    for items in [[missing], [clip("Writable"), missing], [clip("")]] {
      clipboard.clearContents()
      XCTAssertTrue(clipboard.setString("keep me", forType: .string))
      XCTAssertEqual(
        items.count == 1 ? service.copy(items[0]) : service.copy(items),
        .failed(items.count == 1 ? "Could not write item to clipboard." : "Could not write items to clipboard."))
      XCTAssertEqual(clipboard.string(forType: .string), "keep me")
    }
  }

}

class CaptureTestCase: HistoryTestCase {
  lazy var monitor = CaptureMonitor(store: store, cacheService: cache, settings: settings)
  override func setUp() {
    super.setUp()
    _ = monitor
  }
  override func tearDown() {
    monitor.stop()
    super.tearDown()
  }
  func resetCapture() {
    monitor.stop()
    resetHistory()
    monitor = CaptureMonitor(store: store, cacheService: cache, settings: settings)
  }
  func capture(_ write: () throws -> Void) throws -> Clip {
    let captured = expectation(description: "Stored capture callback")
    var result: Clip?
    monitor.onCapturedItem = {
      result = $0
      captured.fulfill()
    }
    clipboard.clearContents()
    try write()
    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1)
    return try XCTUnwrap(result)
  }
}
