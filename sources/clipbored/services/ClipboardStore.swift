import AppKit
import Darwin
import Foundation
import CommonCrypto
import SQLite3

final class ClipboardStore {
  private(set) var items: [ClipboardItem] = [] {
    didSet { notifyItemsChanged() }
  }

  private let settings: SettingsModel
  private let cacheService: ClipboardCacheService
  private let encryptionService: ClipboardEncryptionService
  private let dataQueue = DispatchQueue(label: "clipboard.store.persistence", qos: .utility)
  private let baseURL: URL
  private let historyURL: URL
  private let dbURL: URL
  private var db: OpaquePointer?
  private var itemObservers: [([ClipboardItem]) -> Void] = []

  init(
    settings: SettingsModel,
    cacheService: ClipboardCacheService,
    baseURL: URL? = nil,
    encryptionService: ClipboardEncryptionService = ClipboardEncryptionService()
  ) {
    self.settings = settings
    self.cacheService = cacheService
    self.encryptionService = encryptionService
    self.baseURL = baseURL ?? ClipboardStore.storageDirectory()
    dbURL = self.baseURL.appendingPathComponent("history.sqlite")
    historyURL = self.baseURL.appendingPathComponent("history.json")
    settings.sanitizeLimits()
    hardenStoragePermissions()
    openDatabase()
    configureDatabase()
    createSchema()
    hardenStoragePermissions()
    migrateLegacyJSONIfNeeded()
    load()
  }

  deinit {
    if let db {
      sqlite3_close(db)
    }
  }

  static func storageDirectory() -> URL {
    if let pointer = getenv(AppConfiguration.storageDirectoryOverrideEnvironmentKey), pointer.pointee != 0 {
      let base = URL(fileURLWithPath: String(cString: pointer), isDirectory: true).standardizedFileURL
      try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
      return base
    }

    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let base = appSupport.appendingPathComponent(AppConfiguration.appName, isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
    return base
  }

  func upsert(_ incoming: ClipboardItem) {
    guard let index = items.firstIndex(where: { settings.pruneDuplicates ? $0.payloadHash == incoming.payloadHash : false }) else {
      insertNewItem(incoming)
      return
    }

    if settings.keepFirstImage, incoming.kind == .image {
      updateExistingKeepImage(incoming, at: index)
      return
    }

    updateExistingItem(incoming, at: index)
  }

  func markUsed(_ id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    var used = items.remove(at: index)
    used.lastUsedAt = Date()
    used.useCount += 1
    items.insert(used, at: 0)
    persistAsync(.upsert(used))
  }

  func togglePin(_ id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].isPinned.toggle()
    let updated = items[index]
    normalizeHistoryLength()
    if items.contains(where: { $0.id == updated.id }) {
      persistAsync(.upsert(updated))
    }
  }

  func setCollection(_ id: UUID, name: String?) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].collectionName = ClipboardCollectionDefaults.normalizedName(name)
    persistAsync(.upsert(items[index]))
  }

  func setCustomTitle(_ id: UUID, title: String?) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].customTitle = ClipboardItem.normalizedCustomTitle(title)
    persistAsync(.upsert(items[index]))
  }

  @discardableResult
  func updateText(_ id: UUID, text: String) -> Bool {
    guard !text.isEmpty,
          let index = items.firstIndex(where: { $0.id == id }),
          items[index].kind == .text else {
      return false
    }

    items[index].displayText = text
    items[index].payload = text
    items[index].payloadHash = hashString(text)
    items[index].ocrText = nil
    persistAsync(.upsert(items[index]))
    return true
  }

  func remove(_ id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let removed = items.remove(at: index)
    if removed.kind.hasManagedCacheReference {
      cacheService.removeCachedReferences(removed)
    }
    persistAsync(.delete(id))
  }

  func removeAll() {
    for item in items {
      if item.kind.hasManagedCacheReference {
        cacheService.removeCachedReferences(item)
      }
    }
    items.removeAll()
    persistAsync(.deleteAll)
  }

  func updateHistoryLimit(_ newLimit: Int) {
    if settings.maxHistoryItems != newLimit {
      settings.maxHistoryItems = newLimit
    }
    normalizeHistoryLength()
  }

  func observeItems(_ observer: @escaping ([ClipboardItem]) -> Void) {
    itemObservers.append(observer)
    observer(items)
  }

  func normalizeHistoryLength() {
    var pinnedCount = 0
    var unpinnedCount = 0
    var kept: [ClipboardItem] = []
    var overflow: [ClipboardItem] = []

    kept.reserveCapacity(items.count)
    for item in items {
      if item.isPinned {
        if pinnedCount < AppConfiguration.maxPinnedItems {
          pinnedCount += 1
          kept.append(item)
        } else {
          overflow.append(item)
        }
      } else if unpinnedCount < settings.maxHistoryItems {
        unpinnedCount += 1
        kept.append(item)
      } else {
        overflow.append(item)
      }
    }

    guard !overflow.isEmpty else { return }

    items = kept

    var removedCachedPayload = false
    var idsToDelete: [UUID] = []
    idsToDelete.reserveCapacity(overflow.count)
    for item in overflow {
      idsToDelete.append(item.id)
      if item.kind.hasManagedCacheReference {
        removedCachedPayload = true
        cacheService.removeCachedReferences(item)
      }
    }

    persistAsync(.deleteMany(idsToDelete), purgeCache: removedCachedPayload)
  }

  func flushPersistenceForTesting() {
    dataQueue.sync {}
  }

  private func insertNewItem(_ incoming: ClipboardItem) {
    items.insert(incoming, at: 0)
    normalizeHistoryLength()
    persistAsync(.upsert(incoming), purgeCache: incoming.imagePath != nil)
  }

  private func updateExistingKeepImage(_ incoming: ClipboardItem, at index: Int) {
    cacheService.removeCachedReferences(incoming)
    var existing = items.remove(at: index)
    existing.lastUsedAt = Date()
    existing.useCount += 1
    if !incoming.displayText.isEmpty {
      existing.displayText = incoming.displayText
    }
    existing.sourceApp = incoming.sourceApp
    existing.sourceAppBundleId = incoming.sourceAppBundleId
    existing.customTitle = incoming.customTitle ?? existing.customTitle
    items.insert(existing, at: 0)
    normalizeHistoryLength()
    persistAsync(.upsert(existing), purgeCache: existing.kind == .image)
  }

  private func updateExistingItem(_ incoming: ClipboardItem, at index: Int) {
    var existing = items.remove(at: index)
    let previousCachedItem = existing
    existing.lastUsedAt = Date()
    existing.useCount += 1
    if !incoming.displayText.isEmpty {
      existing.displayText = incoming.displayText
    }
    existing.payload = incoming.payload
    existing.payloadHash = incoming.payloadHash
    existing.kind = incoming.kind
    existing.sourceApp = incoming.sourceApp
    existing.sourceAppBundleId = incoming.sourceAppBundleId
    existing.customTitle = incoming.customTitle ?? existing.customTitle

    if incoming.kind == .image || incoming.kind == .url {
      existing.imagePath = incoming.imagePath
      existing.thumbnailPath = incoming.thumbnailPath
    } else {
      existing.imagePath = nil
      existing.thumbnailPath = nil
    }

    if previousCachedItem.kind.hasManagedCacheReference {
      cacheService.removeCachedReferences(previousCachedItem)
    }

    existing.ocrText = incoming.ocrText

    items.insert(existing, at: 0)
    normalizeHistoryLength()
    persistAsync(.upsert(existing), purgeCache: existing.imagePath != nil)
  }

  private func persistAsync(_ mutation: PersistenceMutation, purgeCache: Bool = false) {
    dataQueue.async {
      self.applyPersistence(mutation)
      if purgeCache {
        self.cacheService.purgeIfNeeded(maxBytes: self.settings.imageCacheMaxBytes)
      }
    }
  }

  private func load() {
    loadFromDatabase()
  }

  private func notifyItemsChanged() {
    for observer in itemObservers {
      observer(items)
    }
  }

  func hashString(_ value: String) -> String {
    hashData(Data(value.utf8))
  }

  func hashData(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
      _ = CC_SHA256(bytes.baseAddress, CC_LONG(bytes.count), &digest)
    }
    return hexString(digest)
  }

  private func hexString(_ bytes: [UInt8]) -> String {
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      output.append(hexDigit(byte >> 4))
      output.append(hexDigit(byte & 0x0f))
    }
    return String(decoding: output, as: UTF8.self)
  }

  private func hexDigit(_ value: UInt8) -> UInt8 {
    value < 10 ? value + 48 : value + 87
  }

  private func openDatabase() {
    if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
      db = nil
    }
  }

  private func configureDatabase() {
    _ = execute("PRAGMA secure_delete = ON;")
    _ = execute("PRAGMA journal_mode = DELETE;")
  }

  private func hardenStoragePermissions() {
    try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseURL.path)
    if FileManager.default.fileExists(atPath: dbURL.path) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbURL.path)
    }
    if FileManager.default.fileExists(atPath: historyURL.path) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }
  }

  private func createSchema() {
    if db == nil { return }
    let createTable = """
      CREATE TABLE IF NOT EXISTS clipboard_items (
        id TEXT PRIMARY KEY NOT NULL,
        kind INTEGER NOT NULL,
        display_text TEXT NOT NULL,
        payload TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        created_at REAL NOT NULL,
        last_used_at REAL NOT NULL,
        use_count INTEGER NOT NULL DEFAULT 0,
        source_app TEXT,
        source_app_bundle_id TEXT,
        image_path TEXT,
        thumbnail_path TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        ocr_text TEXT,
        collection_name TEXT,
        custom_title TEXT
      );
    """

    let createIndexes = """
      CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items (created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_last_used_at ON clipboard_items (last_used_at DESC);
      CREATE INDEX IF NOT EXISTS idx_use_count ON clipboard_items (use_count DESC);
      CREATE INDEX IF NOT EXISTS idx_kind ON clipboard_items (kind);
      CREATE INDEX IF NOT EXISTS idx_hash ON clipboard_items (payload_hash);
      CREATE INDEX IF NOT EXISTS idx_collection_name ON clipboard_items (collection_name);
    """

    _ = execute(createTable)
    _ = execute("ALTER TABLE clipboard_items ADD COLUMN collection_name TEXT;")
    _ = execute("ALTER TABLE clipboard_items ADD COLUMN custom_title TEXT;")
    _ = execute(createIndexes)
  }

  private func migrateLegacyJSONIfNeeded() {
    guard isDatabaseEmpty(), let data = try? Data(contentsOf: historyURL), !data.isEmpty else {
      return
    }

    if let decoded = decodeLegacyJSONItems(from: data) {
      items = decoded
      normalizeHistoryLength()
      if saveAll(items) {
        try? FileManager.default.removeItem(at: historyURL)
        hardenStoragePermissions()
      }
    }
  }

  private func decodeLegacyJSONItems(from data: Data) -> [ClipboardItem]? {
    guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return nil
    }

    var items: [ClipboardItem] = []
    items.reserveCapacity(rows.count)
    for row in rows {
      if let item = decodeLegacyJSONItem(row) {
        items.append(item)
      }
    }
    return items
  }

  private func decodeLegacyJSONItem(_ row: [String: Any]) -> ClipboardItem? {
    guard
      let kindValue = row["kind"] as? Int,
      let kind = ClipboardItemKind(rawValue: kindValue),
      let displayText = row["displayText"] as? String,
      let payload = row["payload"] as? String,
      let payloadHash = row["payloadHash"] as? String,
      let createdAt = legacyDate(row["createdAt"]),
      let lastUsedAt = legacyDate(row["lastUsedAt"])
    else {
      return nil
    }

    let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    let useCount = row["useCount"] as? Int ?? 0

    return ClipboardItem(
      id: id,
      kind: kind,
      displayText: displayText,
      payload: payload,
      payloadHash: payloadHash,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      useCount: useCount,
      sourceApp: row["sourceApp"] as? String,
      imagePath: row["imagePath"] as? String,
      thumbnailPath: row["thumbnailPath"] as? String,
      isPinned: row["isPinned"] as? Bool ?? false,
      sourceAppBundleId: row["sourceAppBundleId"] as? String,
      ocrText: row["ocrText"] as? String,
      collectionName: row["collectionName"] as? String,
      customTitle: row["customTitle"] as? String
    )
  }

  private func legacyDate(_ value: Any?) -> Date? {
    if let seconds = value as? Double {
      return Date(timeIntervalSince1970: seconds)
    }
    if let number = value as? NSNumber {
      return Date(timeIntervalSince1970: number.doubleValue)
    }
    guard let string = value as? String else {
      return nil
    }

    return legacyISO8601Date(string)
  }

  private func legacyISO8601Date(_ string: String) -> Date? {
    string.withCString { pointer -> Date? in
      let byteCount = strlen(pointer)
      guard byteCount >= 20,
            byte(pointer, 4) == 45,
            byte(pointer, 7) == 45,
            byte(pointer, 10) == 84 || byte(pointer, 10) == 32,
            byte(pointer, 13) == 58,
            byte(pointer, 16) == 58,
            let year = decimal(pointer, byteCount, 0, 4),
            let month = decimal(pointer, byteCount, 5, 2),
            let day = decimal(pointer, byteCount, 8, 2),
            let hour = decimal(pointer, byteCount, 11, 2),
            let minute = decimal(pointer, byteCount, 14, 2),
            let second = decimal(pointer, byteCount, 17, 2)
      else {
        return nil
      }

      var cursor = 19
      var fraction = 0.0
      if cursor < byteCount, byte(pointer, cursor) == 46 {
        cursor += 1
        var scale = 0.1
        while cursor < byteCount {
          let digit = byte(pointer, cursor)
          guard digit >= 48, digit <= 57 else { break }
          fraction += Double(digit - 48) * scale
          scale /= 10
          cursor += 1
        }
      }

      var offset = 0
      if cursor < byteCount, byte(pointer, cursor) == 90 {
        offset = 0
      } else if cursor + 5 < byteCount, byte(pointer, cursor) == 43 || byte(pointer, cursor) == 45 {
        let sign = byte(pointer, cursor) == 43 ? 1 : -1
        guard let offsetHour = decimal(pointer, byteCount, cursor + 1, 2),
              let offsetMinute = decimal(pointer, byteCount, cursor + 4, 2)
        else { return nil }
        offset = sign * ((offsetHour * 3600) + (offsetMinute * 60))
      }

      var components = tm()
      components.tm_year = Int32(year - 1900)
      components.tm_mon = Int32(month - 1)
      components.tm_mday = Int32(day)
      components.tm_hour = Int32(hour)
      components.tm_min = Int32(minute)
      components.tm_sec = Int32(second)
      components.tm_isdst = 0

      let epoch = timegm(&components)
      guard epoch >= 0 else { return nil }
      return Date(timeIntervalSince1970: TimeInterval(epoch - time_t(offset)) + fraction)
    }
  }

  private func decimal(_ pointer: UnsafePointer<CChar>, _ byteCount: Int, _ start: Int, _ length: Int) -> Int? {
    guard start + length <= byteCount else { return nil }
    var result = 0
    for index in start..<(start + length) {
      let digit = byte(pointer, index)
      guard digit >= 48, digit <= 57 else { return nil }
      result = (result * 10) + Int(digit - 48)
    }
    return result
  }

  private func byte(_ pointer: UnsafePointer<CChar>, _ index: Int) -> UInt8 {
    UInt8(bitPattern: pointer[index])
  }

  private func isDatabaseEmpty() -> Bool {
    guard let db else { return true }
    let query = "SELECT COUNT(*) FROM clipboard_items;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
      return true
    }
    guard sqlite3_step(statement) == SQLITE_ROW else { return true }
    let count = sqlite3_column_int64(statement, 0)
    return count == 0
  }

  private func loadFromDatabase() {
    guard let db else { return }
    let query = """
      SELECT
        id, kind, display_text, payload, payload_hash, created_at,
        last_used_at, use_count, source_app, source_app_bundle_id,
        image_path, thumbnail_path, is_pinned, ocr_text, collection_name,
        custom_title
      FROM clipboard_items
      ORDER BY created_at DESC, last_used_at DESC
    """

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }

    var canEncryptCache: Bool?
    func canEncryptForMigration() -> Bool {
      if let canEncryptCache {
        return canEncryptCache
      }
      let canEncrypt = encryptionService.isAvailable
      canEncryptCache = canEncrypt
      return canEncrypt
    }

    var loaded: [ClipboardItem] = []
    var needsEncryptionMigration = false
    var hadDecodeFailure = false
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let idText = sqlite3_column_text(statement, 0),
        let kindValue = Int(exactly: sqlite3_column_int(statement, 1)),
        let kind = ClipboardItemKind(rawValue: kindValue)
      else {
        continue
      }

      let id = UUID(uuidString: String(cString: idText)) ?? UUID()

      func stringValue(_ index: Int32) -> (value: String?, migrationNeeded: Bool, decodeFailed: Bool) {
        guard let raw = sqlite3_column_text(statement, index) else {
          return (nil, false, false)
        }
        let value = String(cString: raw)
        if ClipboardEncryptionService.isProtected(value) {
          guard let decoded = encryptionService.unprotect(value) else {
            return (nil, false, true)
          }
          return (decoded, decoded == value && canEncryptForMigration(), false)
        }
        return (value, canEncryptForMigration(), false)
      }

      let displayTextValue = stringValue(2)
      let payloadValue = stringValue(3)
      let payloadHashValue = stringValue(4)
      guard
        let displayText = displayTextValue.value,
        let payload = payloadValue.value,
        let payloadHash = payloadHashValue.value
      else {
        hadDecodeFailure = hadDecodeFailure
          || displayTextValue.decodeFailed
          || payloadValue.decodeFailed
          || payloadHashValue.decodeFailed
        continue
      }
      needsEncryptionMigration = needsEncryptionMigration
        || displayTextValue.migrationNeeded
        || payloadValue.migrationNeeded
        || payloadHashValue.migrationNeeded
      hadDecodeFailure = hadDecodeFailure
        || displayTextValue.decodeFailed
        || payloadValue.decodeFailed
        || payloadHashValue.decodeFailed

      let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
      let lastUsedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
      let useCount = Int(sqlite3_column_int(statement, 7))
      let sourceAppValue = stringValue(8)
      let sourceAppBundleIdValue = stringValue(9)
      let imagePathValue = stringValue(10)
      let thumbnailPathValue = stringValue(11)
      let isPinned = sqlite3_column_int(statement, 12) != 0
      let ocrTextValue = stringValue(13)
      let collectionNameValue = stringValue(14)
      let customTitleValue = stringValue(15)

      needsEncryptionMigration = needsEncryptionMigration
        || sourceAppValue.migrationNeeded
        || sourceAppBundleIdValue.migrationNeeded
        || imagePathValue.migrationNeeded
        || thumbnailPathValue.migrationNeeded
        || ocrTextValue.migrationNeeded
        || collectionNameValue.migrationNeeded
        || customTitleValue.migrationNeeded
      hadDecodeFailure = hadDecodeFailure
        || sourceAppValue.decodeFailed
        || sourceAppBundleIdValue.decodeFailed
        || imagePathValue.decodeFailed
        || thumbnailPathValue.decodeFailed
        || ocrTextValue.decodeFailed
        || collectionNameValue.decodeFailed
        || customTitleValue.decodeFailed

      loaded.append(
        ClipboardItem(
          id: id,
          kind: kind,
          displayText: displayText,
          payload: payload,
          payloadHash: payloadHash,
          createdAt: createdAt,
          lastUsedAt: lastUsedAt,
          useCount: useCount,
          sourceApp: sourceAppValue.value,
          imagePath: imagePathValue.value,
          thumbnailPath: thumbnailPathValue.value,
          isPinned: isPinned,
          sourceAppBundleId: sourceAppBundleIdValue.value,
          ocrText: ocrTextValue.value,
          collectionName: collectionNameValue.value,
          customTitle: customTitleValue.value
        )
      )
    }

    sqlite3_finalize(statement)
    statement = nil

    items = loaded
    normalizeHistoryLength()
    cacheService.encryptCachedReferencesIfNeeded(for: items)
    if needsEncryptionMigration, !hadDecodeFailure, saveAll(items) {
      vacuumDatabase()
      hardenStoragePermissions()
    }
  }

  private enum PersistenceMutation {
    case upsert(ClipboardItem)
    case delete(UUID)
    case deleteMany([UUID])
    case deleteAll
  }

  private func applyPersistence(_ mutation: PersistenceMutation) {
    guard let db else { return }
    DiagnosticsService.shared.incrementDatabaseMutation()
    let insertSQL = """
      INSERT OR REPLACE INTO clipboard_items (
        id, kind, display_text, payload, payload_hash,
        created_at, last_used_at, use_count, source_app,
        source_app_bundle_id, image_path, thumbnail_path, is_pinned, ocr_text,
        collection_name, custom_title
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """

    switch mutation {
    case .upsert(let item):
      var statement: OpaquePointer?
      var shouldRollback = false
      defer {
        if let statement {
          sqlite3_finalize(statement)
        }
        if shouldRollback {
          _ = execute("ROLLBACK;")
        }
      }

      guard execute("BEGIN IMMEDIATE TRANSACTION;") else { return }
      guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
        shouldRollback = true
        return
      }

      bindItem(item, to: statement)

      let stepResult = sqlite3_step(statement)
      if stepResult != SQLITE_DONE {
        shouldRollback = true
        return
      }

      if !execute("COMMIT;") {
        shouldRollback = true
      }

    case .delete(let id):
      guard execute("BEGIN IMMEDIATE TRANSACTION;") else { return }
      let query = "DELETE FROM clipboard_items WHERE id = ?;"
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
        _ = execute("ROLLBACK;")
        return
      }
      bindText(statement, 1, id.uuidString)

      let stepResult = sqlite3_step(statement)
      sqlite3_finalize(statement)
      if stepResult != SQLITE_DONE {
        _ = execute("ROLLBACK;")
        return
      }
      _ = execute("COMMIT;")

    case .deleteMany(let ids):
      guard !ids.isEmpty else { return }
      var placeholders = "?"
      if ids.count > 1 {
        for _ in 1..<ids.count {
          placeholders += ",?"
        }
      }
      let query = "DELETE FROM clipboard_items WHERE id IN (\(placeholders));"
      var statement: OpaquePointer?
      guard execute("BEGIN IMMEDIATE TRANSACTION;") else { return }
      guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
        _ = execute("ROLLBACK;")
        return
      }

      for (offset, id) in ids.enumerated() {
        bindText(statement, Int32(offset + 1), id.uuidString)
      }

      let stepResult = sqlite3_step(statement)
      sqlite3_finalize(statement)
      if stepResult != SQLITE_DONE {
        _ = execute("ROLLBACK;")
        return
      }

      _ = execute("COMMIT;")

    case .deleteAll:
      if execute("DELETE FROM clipboard_items;") {
        vacuumDatabase()
        hardenStoragePermissions()
        encryptionService.resetStoredKey()
      }
    }
  }

  @discardableResult
  private func saveAll(_ items: [ClipboardItem]) -> Bool {
    guard let db else { return false }
    let deleteSQL = "DELETE FROM clipboard_items;"
    let insertSQL = """
      INSERT OR REPLACE INTO clipboard_items (
        id, kind, display_text, payload, payload_hash,
        created_at, last_used_at, use_count, source_app,
        source_app_bundle_id, image_path, thumbnail_path, is_pinned, ocr_text,
        collection_name, custom_title
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """

    guard execute("BEGIN IMMEDIATE TRANSACTION;") else {
      return false
    }

    defer {
      if sqlite3_get_autocommit(db) == 0 {
        _ = execute("ROLLBACK;")
      }
    }

    guard execute(deleteSQL) else {
      _ = execute("ROLLBACK;")
      return false
    }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
      _ = execute("ROLLBACK;")
      return false
    }

    for item in items {
      bindItem(item, to: statement)

      let stepResult = sqlite3_step(statement)
      if stepResult != SQLITE_DONE {
        _ = execute("ROLLBACK;")
        return false
      }

      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
    }

    if !execute("COMMIT;") {
      _ = execute("ROLLBACK;")
      return false
    }
    return true
  }

  @discardableResult
  private func execute(_ sql: String) -> Bool {
    guard let db else { return false }
    return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
  }

  private func vacuumDatabase() {
    _ = execute("VACUUM;")
  }

  private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    guard let value else {
      sqlite3_bind_null(statement, index)
      return
    }

    let destructor: Optional<@convention(c) (UnsafeMutableRawPointer?) -> ()> = unsafeBitCast(-1, to: Optional<@convention(c) (UnsafeMutableRawPointer?) -> ()>.self)
    _ = value.withCString { ptr in
      sqlite3_bind_text(statement, index, ptr, -1, destructor)
    }
  }

  private func bindItem(_ item: ClipboardItem, to statement: OpaquePointer?) {
    bindText(statement, 1, item.id.uuidString)
    sqlite3_bind_int(statement, 2, Int32(item.kind.rawValue))
    bindText(statement, 3, encryptionService.protect(item.displayText))
    bindText(statement, 4, encryptionService.protect(item.payload))
    bindText(statement, 5, encryptionService.protect(item.payloadHash))
    sqlite3_bind_double(statement, 6, item.createdAt.timeIntervalSince1970)
    sqlite3_bind_double(statement, 7, item.lastUsedAt.timeIntervalSince1970)
    sqlite3_bind_int(statement, 8, Int32(item.useCount))
    bindText(statement, 9, encryptionService.protect(item.sourceApp))
    bindText(statement, 10, encryptionService.protect(item.sourceAppBundleId))
    bindText(statement, 11, encryptionService.protect(item.imagePath))
    bindText(statement, 12, encryptionService.protect(item.thumbnailPath))
    sqlite3_bind_int(statement, 13, item.isPinned ? 1 : 0)
    bindText(statement, 14, encryptionService.protect(item.ocrText))
    bindText(statement, 15, encryptionService.protect(item.collectionName))
    bindText(statement, 16, encryptionService.protect(item.customTitle))
  }
}
