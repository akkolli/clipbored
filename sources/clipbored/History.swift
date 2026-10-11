import AppKit
import CommonCrypto
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import SQLite3
import Security

// MARK: - HistoryStore

final class HistoryStore {
  var items: [Clip] = [] { didSet { notifyItemsChanged() } }

  let settings: Preferences
  let cacheService: MediaCache
  let encryptionService: HistoryEncryption
  let dataQueue = DispatchQueue(label: "clipboard.store.persistence", qos: .utility)
  let baseURL: URL
  let historyURL: URL
  let dbURL: URL
  var db: OpaquePointer?
  private var itemObservers: [([Clip]) -> Void] = []

  init(
    settings: Preferences, cacheService: MediaCache, baseURL: URL? = nil,
    encryptionService: HistoryEncryption = HistoryEncryption()
  ) {
    self.settings = settings
    self.cacheService = cacheService
    self.encryptionService = encryptionService
    self.baseURL = baseURL ?? HistoryStore.storageDirectory()
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

  deinit { if let db { sqlite3_close(db) } }

  static func storageDirectory() -> URL {
    if let pointer = getenv(Configuration.storageDirectoryOverrideEnvironmentKey), pointer.pointee != 0 {
      let base = URL(fileURLWithPath: String(cString: pointer), isDirectory: true).standardizedFileURL
      try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
      return base
    }

    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let base = appSupport.appendingPathComponent(Configuration.storageName, isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
    return base
  }

  @discardableResult func upsert(_ incoming: Clip) -> Clip {
    guard settings.pruneDuplicates, let index = items.firstIndex(where: { $0.payloadHash == incoming.payloadHash })
    else { return insertNewItem(incoming) }
    return updateExistingItem(incoming, at: index)
  }

  func markUsed(_ id: UUID) {
    mutate(id, promote: true) {
      $0.lastUsedAt = Date()
      $0.useCount += 1
    }
  }

  func togglePin(_ id: UUID) { mutate(id, retention: true) { $0.isPinned.toggle() } }

  func setCollection(_ id: UUID, name: String?) {
    mutate(id, retention: true) { $0.collectionName = Pinboards.normalizedName(name) }
  }

  func setCustomTitle(_ id: UUID, title: String?) { mutate(id) { $0.customTitle = Clip.normalizedCustomTitle(title) } }

  @discardableResult func updateText(_ id: UUID, text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return mutate(id, kinds: [.text, .code]) {
      $0.displayText = text
      $0.payload = text
      $0.payloadHash = hashString(text)
      $0.ocrText = nil
    }
  }

  @discardableResult func updateImage(_ id: UUID, imagePath: String, thumbnailPath: String, payloadHash: String) -> Bool
  {
    guard !imagePath.clipboardTrimmed.isEmpty, !thumbnailPath.clipboardTrimmed.isEmpty,
      !payloadHash.clipboardTrimmed.isEmpty
    else { return false }
    return mutate(id, kinds: [.image], purgeCache: true) {
      $0.payload = imagePath
      $0.imagePath = imagePath
      $0.thumbnailPath = thumbnailPath
      $0.payloadHash = payloadHash
    }
  }

  @discardableResult func updateImageText(_ id: UUID, ocrText: String) -> Bool {
    guard let text = ImageTextExtractor.normalizedRecognizedText(ocrText) else { return false }
    return mutate(id, kinds: [.image]) { $0.ocrText = text }
  }

  // Publish each clip update as a complete value; observers never see a title,
  // payload or metadata field from the middle of an update.
  @discardableResult private func mutate(
    _ id: UUID, kinds: [ClipKind] = [], promote: Bool = false, retention: Bool = false, purgeCache: Bool = false,
    _ update: (inout Clip) -> Void
  ) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == id }), kinds.isEmpty || kinds.contains(items[index].kind)
    else { return false }
    var item = items[index]
    update(&item)
    var next = items
    next[index] = item
    if promote { next.insert(next.remove(at: index), at: 0) }
    items = next
    if retention { normalizeHistoryLength() }
    if items.contains(where: { $0.id == id }) { persistAsync(.upsert(item), purgeCache: purgeCache) }
    return true
  }

  @discardableResult func remove(_ id: UUID, purgeManagedCache: Bool = true) -> HistoryRemoval? {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
    let removed = items.remove(at: index)
    if purgeManagedCache { purgeManagedCacheReferences(for: [removed]) }
    persistAsync(.delete(id))
    return HistoryRemoval(item: removed, index: index)
  }

  func restore(_ removals: [HistoryRemoval]) {
    guard !removals.isEmpty else { return }

    var restoredItems: [Clip] = []
    for removal in removals.sorted(by: { $0.index < $1.index }) {
      guard !items.contains(where: { $0.id == removal.item.id }) else { continue }
      let insertionIndex = max(0, min(removal.index, items.count))
      items.insert(removal.item, at: insertionIndex)
      restoredItems.append(removal.item)
    }

    guard !restoredItems.isEmpty else { return }
    normalizeHistoryLength()
    let retainedIDs = Set(items.map(\.id))
    let retainedRestoredItems = restoredItems.filter { retainedIDs.contains($0.id) }
    persistAsync(.upsertMany(retainedRestoredItems))
  }

  func removeAll() {
    purgeManagedCacheReferences(for: items)
    items.removeAll()
    persistAsync(.deleteAll)
  }

  func updateHistoryLimit(_ newLimit: Int) {
    if settings.maxHistoryItems != newLimit { settings.maxHistoryItems = newLimit }
    normalizeHistoryLength()
  }

  func observeItems(_ observer: @escaping ([Clip]) -> Void) {
    itemObservers.append(observer)
    observer(items)
  }

  func flushPersistenceForTesting() { dataQueue.sync {} }

  private func notifyItemsChanged() { for observer in itemObservers { observer(items) } }

  func hashString(_ value: String) -> String { hashData(Data(value.utf8)) }

  func hashData(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in _ = CC_SHA256(bytes.baseAddress, CC_LONG(bytes.count), &digest) }
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

  private func hexDigit(_ value: UInt8) -> UInt8 { value < 10 ? value + 48 : value + 87 }
}

// MARK: - HistoryStore — Mutations

extension HistoryStore {
  func purgeManagedCacheReferences(for removals: [HistoryRemoval]) {
    purgeManagedCacheReferences(for: removals.map(\.item))
  }

  func insertNewItem(_ incoming: Clip) -> Clip {
    items.insert(incoming, at: 0)
    normalizeHistoryLength()
    if let retained = items.first(where: { $0.id == incoming.id }) {
      persistAsync(.upsert(retained), purgeCache: retained.imagePath != nil)
      return retained
    }
    return incoming
  }

  func updateExistingItem(_ incoming: Clip, at index: Int) -> Clip {
    let keepImage = settings.keepFirstImage && incoming.kind == .image
    var existing = items.remove(at: index)
    if keepImage {
      cacheService.removeCachedReferences(incoming)
    } else {
      if existing.kind.hasManagedCacheReference { cacheService.removeCachedReferences(existing) }
      existing.payload = incoming.payload
      existing.payloadHash = incoming.payloadHash
      existing.kind = incoming.kind
      existing.imagePath = [.image, .url].contains(incoming.kind) ? incoming.imagePath : nil
      existing.thumbnailPath = [.image, .url].contains(incoming.kind) ? incoming.thumbnailPath : nil
      existing.ocrText = incoming.ocrText
    }
    existing.createdAt = Date()
    existing.lastUsedAt = Date()
    existing.useCount += 1
    if !incoming.displayText.isEmpty { existing.displayText = incoming.displayText }
    existing.sourceApp = incoming.sourceApp
    existing.sourceAppBundleId = incoming.sourceAppBundleId
    existing.sourceDeviceName = incoming.sourceDeviceName
    existing.collectionName = incoming.collectionName ?? existing.collectionName
    existing.customTitle = incoming.customTitle ?? existing.customTitle

    items.insert(existing, at: 0)
    normalizeHistoryLength()
    if let retained = items.first(where: { $0.id == existing.id }) {
      persistAsync(.upsert(retained), purgeCache: keepImage ? retained.kind == .image : retained.imagePath != nil)
      return retained
    }
    return existing
  }

  func purgeManagedCacheReferences(for items: [Clip]) {
    for item in items where item.kind.hasManagedCacheReference { cacheService.removeCachedReferences(item) }
  }
}

// MARK: - HistoryStore — Retention

extension HistoryStore {
  func normalizeHistoryLength() {
    let plan = retentionPlan(for: items)
    let kept = plan.kept
    let overflow = plan.overflow

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

  func retentionPlan(for sourceItems: [Clip]) -> (kept: [Clip], overflow: [Clip]) {
    var pinnedCount = 0
    var unpinnedCount = 0
    var kept: [Clip] = []
    var overflow: [Clip] = []
    let retentionCutoff = settings.historyRetention.cutoffDate()

    kept.reserveCapacity(sourceItems.count)
    for item in sourceItems {
      if item.isPinned {
        if pinnedCount < Configuration.maxPinnedItems {
          pinnedCount += 1
          kept.append(item)
        } else if isCollectionRetained(item) {
          kept.append(item)
        } else {
          overflow.append(item)
        }
      } else if isCollectionRetained(item) {
        kept.append(item)
      } else if isExpiredByRetention(item, cutoff: retentionCutoff) {
        overflow.append(item)
      } else if unpinnedCount < settings.maxHistoryItems {
        unpinnedCount += 1
        kept.append(item)
      } else {
        overflow.append(item)
      }
    }

    return (kept, overflow)
  }

  func historySort(_ lhs: Clip, _ rhs: Clip) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
    if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private func isCollectionRetained(_ item: Clip) -> Bool { Pinboards.normalizedName(item.collectionName) != nil }

  private func isExpiredByRetention(_ item: Clip, cutoff: Date?) -> Bool {
    guard let cutoff else { return false }
    return item.createdAt < cutoff
  }
}

// MARK: - HistoryStore — Archives

extension HistoryStore {
  @discardableResult func exportArchive(to url: URL) throws -> ArchiveSummary {
    dataQueue.sync {}
    let collections = settings.customCollectionNames.map { name in
      ArchivePinboard(name: name, colorHex: settings.collectionColorHex(forCollectionNamed: name))
    }
    return try HistoryArchive().exportArchive(
      items: items, to: url, cacheService: cacheService, collections: collections)
  }

  @discardableResult func exportCollection(named name: String, to url: URL) throws -> ArchiveSummary {
    guard let normalizedName = Pinboards.normalizedName(name) else {
      return try HistoryArchive().exportArchive(items: [], to: url, cacheService: cacheService)
    }
    dataQueue.sync {}
    let collectionItems = items.filter { $0.collectionName?.caseInsensitiveCompare(normalizedName) == .orderedSame }
    let collection = ArchivePinboard(
      name: normalizedName, colorHex: settings.collectionColorHex(forCollectionNamed: normalizedName))
    return try HistoryArchive().exportArchive(
      items: collectionItems, to: url, cacheService: cacheService, collections: [collection])
  }

  @discardableResult func importArchive(from url: URL) throws -> ArchiveSummary {
    dataQueue.sync {}
    let archiveImport = try HistoryArchive().importArchive(from: url, cacheService: cacheService)
    for collection in archiveImport.collections {
      settings.ensureCollection(named: collection.name, colorHex: collection.colorHex)
    }
    for item in archiveImport.items {
      if let collectionName = item.collectionName { settings.ensureCollection(named: collectionName) }
    }
    guard saveImportedItems(archiveImport.items) else { throw HistoryArchiveError.persistenceFailed }
    return archiveImport.summary
  }

  private func saveImportedItems(_ importedItems: [Clip]) -> Bool {
    guard !importedItems.isEmpty else { return true }

    var mergedByID: [UUID: Clip] = [:]
    mergedByID.reserveCapacity(items.count + importedItems.count)
    for item in items { mergedByID[item.id] = item }
    for item in importedItems { mergedByID[item.id] = item }

    let merged = mergedByID.values.sorted(by: historySort)
    let plan = retentionPlan(for: merged)
    guard saveAll(plan.kept) else { return false }

    items = plan.kept
    if !plan.overflow.isEmpty {
      purgeManagedCacheReferences(for: plan.overflow)
      cacheService.purgeIfNeeded(maxBytes: settings.imageCacheMaxBytes)
    }
    hardenStoragePermissions()
    return true
  }
}

// MARK: - Clip row schema

// This is the sole SQL column order. Typed key paths drive reads and writes;
// identity stays public and all content strings pass through encryption.
private enum ClipRow {
  enum Field {
    case id, kind
    case text(WritableKeyPath<Clip, String>)
    case optionalText(WritableKeyPath<Clip, String?>, migrated: Bool = false)
    case date(WritableKeyPath<Clip, Date>)
    case integer(WritableKeyPath<Clip, Int>)
    case boolean(WritableKeyPath<Clip, Bool>)
    var declaration: String {
      switch self {
      case .id: return "TEXT PRIMARY KEY NOT NULL"
      case .kind: return "INTEGER NOT NULL"
      case .text: return "TEXT NOT NULL"
      case .optionalText: return "TEXT"
      case .date: return "REAL NOT NULL"
      case .integer, .boolean: return "INTEGER NOT NULL DEFAULT 0"
      }
    }
  }
  static let columns: [(name: String, field: Field)] = [
    ("id", .id), ("kind", .kind), ("display_text", .text(\.displayText)), ("payload", .text(\.payload)),
    ("payload_hash", .text(\.payloadHash)), ("created_at", .date(\.createdAt)), ("last_used_at", .date(\.lastUsedAt)),
    ("use_count", .integer(\.useCount)), ("source_app", .optionalText(\.sourceApp)),
    ("source_app_bundle_id", .optionalText(\.sourceAppBundleId)), ("image_path", .optionalText(\.imagePath)),
    ("thumbnail_path", .optionalText(\.thumbnailPath)), ("is_pinned", .boolean(\.isPinned)),
    ("ocr_text", .optionalText(\.ocrText)), ("collection_name", .optionalText(\.collectionName, migrated: true)),
    ("custom_title", .optionalText(\.customTitle, migrated: true)),
    ("source_device_name", .optionalText(\.sourceDeviceName, migrated: true)),
  ]
  static let names = columns.map(\.name).joined(separator: ", ")
  static let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
}

// MARK: - HistoryStore — Database

extension HistoryStore {
  func openDatabase() { if sqlite3_open(dbURL.path, &db) != SQLITE_OK { db = nil } }

  func configureDatabase() {
    _ = execute("PRAGMA secure_delete = ON;")
    _ = execute("PRAGMA journal_mode = DELETE;")
  }

  func hardenStoragePermissions() {
    try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseURL.path)
    if FileManager.default.fileExists(atPath: dbURL.path) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbURL.path)
    }
    if FileManager.default.fileExists(atPath: historyURL.path) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }
  }

  func createSchema() {
    if db == nil { return }
    let definitions = ClipRow.columns.map { "\($0.name) \($0.field.declaration)" }.joined(separator: ", ")
    _ = execute("CREATE TABLE IF NOT EXISTS clipboard_items (\(definitions));")
    for column in ClipRow.columns {
      if case .optionalText(_, migrated: true) = column.field {
        _ = execute("ALTER TABLE clipboard_items ADD COLUMN \(column.name) TEXT;")
      }
    }
    for (name, expression) in [
      ("created_at", "created_at DESC"), ("last_used_at", "last_used_at DESC"), ("use_count", "use_count DESC"),
      ("kind", "kind"), ("hash", "payload_hash"), ("collection_name", "collection_name"),
    ] { _ = execute("CREATE INDEX IF NOT EXISTS idx_\(name) ON clipboard_items (\(expression));") }
  }

  func isDatabaseEmpty() -> Bool {
    guard let db else { return true }
    let query = "SELECT COUNT(*) FROM clipboard_items;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return true }
    guard sqlite3_step(statement) == SQLITE_ROW else { return true }
    let count = sqlite3_column_int64(statement, 0)
    return count == 0
  }

  @discardableResult func execute(_ sql: String) -> Bool {
    guard let db else { return false }
    return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
  }

  func vacuumDatabase() { _ = execute("VACUUM;") }
}

// MARK: - HistoryStore — Loading

extension HistoryStore {
  func load() { loadFromDatabase() }

  private func loadFromDatabase() {
    guard let db else { return }
    let query = "SELECT \(ClipRow.names) FROM clipboard_items ORDER BY created_at DESC, last_used_at DESC;"

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }

    var canEncryptCache: Bool?
    func canEncryptForMigration() -> Bool {
      if let canEncryptCache { return canEncryptCache }
      let canEncrypt = encryptionService.isAvailable
      canEncryptCache = canEncrypt
      return canEncrypt
    }

    var loaded: [Clip] = []
    var needsEncryptionMigration = false
    var hadDecodeFailure = false
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = sqlite3_column_text(statement, 0),
        let kindValue = Int(exactly: sqlite3_column_int(statement, 1)), let kind = ClipKind(rawValue: kindValue)
      else { continue }

      let id = UUID(uuidString: String(cString: idText)) ?? UUID()

      func stringValue(_ index: Int32) -> (value: String?, migrationNeeded: Bool, decodeFailed: Bool) {
        guard let raw = sqlite3_column_text(statement, index) else { return (nil, false, false) }
        let value = String(cString: raw)
        if HistoryEncryption.isProtected(value) {
          guard let decoded = encryptionService.unprotect(value) else { return (nil, false, true) }
          return (decoded, decoded == value && canEncryptForMigration(), false)
        }
        return (value, canEncryptForMigration(), false)
      }

      var item = Clip(
        id: id, kind: kind, displayText: "", payload: "", payloadHash: "", createdAt: .distantPast,
        lastUsedAt: .distantPast, useCount: 0, sourceDeviceName: nil)
      var valid = true
      // Visit every text field even if a required one fails, so unreadable
      // optional content can never be overwritten during encryption migration.
      for (offset, column) in ClipRow.columns.enumerated() {
        let index = Int32(offset)
        switch column.field {
        case .id, .kind: break
        case .text, .optionalText:
          let field = stringValue(index)
          needsEncryptionMigration = needsEncryptionMigration || field.migrationNeeded
          hadDecodeFailure = hadDecodeFailure || field.decodeFailed
          if case .text(let key) = column.field {
            if let value = field.value { item[keyPath: key] = value } else { valid = false }
          } else if case .optionalText(let key, _) = column.field {
            item[keyPath: key] = field.value
          }
        case .date(let key): item[keyPath: key] = Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
        case .integer(let key): item[keyPath: key] = Int(sqlite3_column_int(statement, index))
        case .boolean(let key): item[keyPath: key] = sqlite3_column_int(statement, index) != 0
        }
      }
      item.customTitle = Clip.normalizedCustomTitle(item.customTitle)
      item.sourceDeviceName = Clip.normalizedDeviceName(item.sourceDeviceName ?? Clip.localDeviceName)
      if valid { loaded.append(item) }
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
}

// MARK: - HistoryStore — Migration

extension HistoryStore {
  func migrateLegacyJSONIfNeeded() {
    guard isDatabaseEmpty(), let data = try? Data(contentsOf: historyURL), !data.isEmpty else { return }

    if let decoded = decodeLegacyJSONItems(from: data) {
      items = decoded
      normalizeHistoryLength()
      if saveAll(items) {
        try? FileManager.default.removeItem(at: historyURL)
        hardenStoragePermissions()
      }
    }
  }

  private func decodeLegacyJSONItems(from data: Data) -> [Clip]? {
    guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

    var items: [Clip] = []
    items.reserveCapacity(rows.count)
    for row in rows { if let item = decodeLegacyJSONItem(row) { items.append(item) } }
    return items
  }

  private func decodeLegacyJSONItem(_ row: [String: Any]) -> Clip? {
    guard let kindValue = row["kind"] as? Int, let kind = ClipKind(rawValue: kindValue),
      let displayText = row["displayText"] as? String, let payload = row["payload"] as? String,
      let payloadHash = row["payloadHash"] as? String, let createdAt = legacyDate(row["createdAt"]),
      let lastUsedAt = legacyDate(row["lastUsedAt"])
    else { return nil }

    let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    let useCount = row["useCount"] as? Int ?? 0

    return Clip(
      id: id, kind: kind, displayText: displayText, payload: payload, payloadHash: payloadHash, createdAt: createdAt,
      lastUsedAt: lastUsedAt, useCount: useCount, sourceApp: row["sourceApp"] as? String,
      imagePath: row["imagePath"] as? String, thumbnailPath: row["thumbnailPath"] as? String,
      isPinned: row["isPinned"] as? Bool ?? false, sourceAppBundleId: row["sourceAppBundleId"] as? String,
      ocrText: row["ocrText"] as? String, collectionName: row["collectionName"] as? String,
      customTitle: row["customTitle"] as? String,
      sourceDeviceName: row["sourceDeviceName"] as? String ?? Clip.localDeviceName)
  }

  private func legacyDate(_ value: Any?) -> Date? {
    if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
    if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
    guard let string = value as? String else { return nil }

    return legacyISO8601Date(string)
  }

  private func legacyISO8601Date(_ string: String) -> Date? {
    let value = string.replacingOccurrences(of: " ", with: "T")
    return Self.legacyDateFormatters.lazy.compactMap { $0.date(from: value) }.first
  }

  private static let legacyDateFormatters: [ISO8601DateFormatter] = {
    let formats: [ISO8601DateFormatter.Options] = [
      [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
    ]
    return formats.map { options in
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = options
      return formatter
    }
  }()
}

// MARK: - HistoryStore — Persistence

extension HistoryStore {
  func persistAsync(_ mutation: PersistenceMutation, purgeCache: Bool = false) {
    dataQueue.async {
      self.applyPersistence(mutation)
      if purgeCache { self.cacheService.purgeIfNeeded(maxBytes: self.settings.imageCacheMaxBytes) }
    }
  }

  enum PersistenceMutation {
    case upsert(Clip)
    case upsertMany([Clip])
    case delete(UUID)
    case deleteMany([UUID])
    case deleteAll
  }

  private func applyPersistence(_ mutation: PersistenceMutation) {
    switch mutation {
    case .upsert(let item): _ = writeItems([item])
    case .upsertMany(let items): _ = writeItems(items)
    case .delete(let id): deleteItems([id])
    case .deleteMany(let ids): deleteItems(ids)
    case .deleteAll:
      if execute("DELETE FROM clipboard_items;") {
        vacuumDatabase()
        hardenStoragePermissions()
        encryptionService.resetStoredKey()
      }
    }
  }

  @discardableResult func saveAll(_ items: [Clip]) -> Bool { writeItems(items, replacingAll: true) }

  private func writeItems(_ items: [Clip], replacingAll: Bool = false) -> Bool {
    guard let db else { return false }
    guard replacingAll || !items.isEmpty else { return true }
    let insertSQL = "INSERT OR REPLACE INTO clipboard_items (\(ClipRow.names)) VALUES (\(ClipRow.placeholders));"
    return performTransaction {
      if replacingAll && !execute("DELETE FROM clipboard_items;") { return false }
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else { return false }
      for item in items {
        bindItem(item, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return false }
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
      }
      return true
    }
  }

  private func deleteItems(_ ids: [UUID]) {
    guard let db, !ids.isEmpty else { return }
    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
    let query = "DELETE FROM clipboard_items WHERE id IN (\(placeholders));"
    _ = performTransaction {
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return false }
      for (offset, id) in ids.enumerated() { bindText(statement, Int32(offset + 1), id.uuidString) }
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  private func performTransaction(_ operation: () -> Bool) -> Bool {
    guard let db, execute("BEGIN IMMEDIATE TRANSACTION;") else { return false }
    defer { if sqlite3_get_autocommit(db) == 0 { _ = execute("ROLLBACK;") } }
    return operation() && execute("COMMIT;")
  }

  private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    guard let value else {
      sqlite3_bind_null(statement, index)
      return
    }

    let destructor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? = unsafeBitCast(
      -1, to: Optional<@convention(c) (UnsafeMutableRawPointer?) -> Void>.self)
    _ = value.withCString { ptr in sqlite3_bind_text(statement, index, ptr, -1, destructor) }
  }

  private func bindItem(_ item: Clip, to statement: OpaquePointer?) {
    for (offset, column) in ClipRow.columns.enumerated() {
      let index = Int32(offset + 1)
      switch column.field {
      case .id: bindText(statement, index, item.id.uuidString)
      case .kind: sqlite3_bind_int(statement, index, Int32(item.kind.rawValue))
      case .text(let key): bindText(statement, index, encryptionService.protect(item[keyPath: key]))
      case .optionalText(let key, _): bindText(statement, index, encryptionService.protect(item[keyPath: key]))
      case .date(let key): sqlite3_bind_double(statement, index, item[keyPath: key].timeIntervalSince1970)
      case .integer(let key): sqlite3_bind_int(statement, index, Int32(item[keyPath: key]))
      case .boolean(let key): sqlite3_bind_int(statement, index, item[keyPath: key] ? 1 : 0)
      }
    }
  }
}

// MARK: - StorageTypes

struct HistoryRemoval {
  let item: Clip
  let index: Int
}

enum HistoryArchiveError: LocalizedError {
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .persistenceFailed: return "Goldfish could not save the imported archive."
    }
  }
}

// MARK: - HistoryEncryption

// Swift marks SecAccessCreate deprecated, but macOS still needs kSecAttrAccess
// here to avoid legacy keychain authorization UI during generic-password creation.
@_silgen_name("SecAccessCreate") private func clipBoredSecAccessCreate(
  _ descriptor: CFString, _ trustedList: CFArray?, _ accessRef: UnsafeMutablePointer<SecAccess?>
) -> OSStatus

final class HistoryEncryption {
  static let marker = "clipbored:v1:"
  private static let markerData = Data(marker.utf8)
  private let keyProvider: () -> SymmetricKey?
  private let resetProvider: () -> Void

  init() {
    if Self.shouldBypassSystemKeychain() {
      keyProvider = { nil }
      resetProvider = {}
    } else {
      keyProvider = { EncryptionKeychain.shared.symmetricKey() }
      resetProvider = { EncryptionKeychain.shared.resetStoredKey() }
    }
  }

  init(keyProvider: @escaping () -> SymmetricKey?, resetProvider: @escaping () -> Void = {}) {
    self.keyProvider = keyProvider
    self.resetProvider = resetProvider
  }

  var isAvailable: Bool { keyProvider() != nil }

  func protect(_ value: String?) -> String? {
    guard let value else { return nil }
    guard let key = keyProvider() else { return value }
    guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: key), let combined = sealed.combined else {
      return value
    }
    return Self.marker + combined.base64EncodedString()
  }

  func unprotect(_ value: String?) -> String? {
    guard let value else { return nil }
    guard Self.isProtected(value) else { return value }
    let encoded = String(value.dropFirst(Self.marker.count))
    guard let data = Data(base64Encoded: encoded), let sealed = try? AES.GCM.SealedBox(combined: data) else {
      return value
    }
    guard let key = keyProvider(), let decrypted = try? AES.GCM.open(sealed, using: key) else { return nil }
    return String(data: decrypted, encoding: .utf8)
  }

  func protectData(_ data: Data) -> Data {
    guard let key = keyProvider() else { return data }
    guard let sealed = try? AES.GCM.seal(data, using: key), let combined = sealed.combined else { return data }
    var output = Self.markerData
    output.append(combined)
    return output
  }

  func unprotectData(_ data: Data) -> Data? {
    guard Self.isProtected(data) else { return data }
    let encrypted = data.dropFirst(Self.markerData.count)
    guard let sealed = try? AES.GCM.SealedBox(combined: encrypted), let key = keyProvider(),
      let decrypted = try? AES.GCM.open(sealed, using: key)
    else { return nil }
    return decrypted
  }

  static func isProtected(_ value: String) -> Bool { value.hasPrefix(marker) }

  static func isProtected(_ data: Data) -> Bool { data.starts(with: markerData) }

  func resetStoredKey() { resetProvider() }

  static func shouldBypassSystemKeychain(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    if environment["CLIPBORED_DISABLE_KEYCHAIN"] == "1" || environment["XCTestConfigurationFilePath"] != nil {
      return true
    }

    return arguments.contains { argument in argument.contains(".xctest") || argument.hasSuffix("/xctest") }
  }
}

private enum EncryptionKeychain { static let shared = KeychainBackedKeyProvider() }

private final class KeychainBackedKeyProvider {
  private let queue = DispatchQueue(label: "clipboard.encryption-keychain")
  private let keychainTimeout: TimeInterval = 0.35
  private var cachedKey: SymmetricKey?

  func symmetricKey() -> SymmetricKey? {
    queue.sync {
      if let cachedKey { return cachedKey }
      if let fallback = readFallbackKeyData() {
        let key = SymmetricKey(data: fallback)
        cachedKey = key
        return key
      }
      if let existing = readKeyData() {
        let key = SymmetricKey(data: existing)
        cachedKey = key
        return key
      }
      let generated = SymmetricKey(size: .bits256)
      let data = generated.withUnsafeBytes { Data($0) }
      if let stored = saveKeyData(data) {
        let key = SymmetricKey(data: stored)
        cachedKey = key
        return key
      }
      guard let fallback = loadOrCreateFallbackKeyData() else { return nil }
      let fallbackKey = SymmetricKey(data: fallback)
      cachedKey = fallbackKey
      return fallbackKey
    }
  }

  func resetStoredKey() {
    queue.sync {
      cachedKey = nil
      _ = deleteKeyData()
      deleteFallbackKeyData()
    }
  }

  private func readKeyData() -> Data? {
    runKeychainOperation {
      var query = self.baseQuery()
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      query[kSecUseAuthenticationContext as String] = self.nonInteractiveContext()

      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      guard status == errSecSuccess else { return nil }
      return result as? Data
    }
  }

  private func saveKeyData(_ data: Data) -> Data? {
    runKeychainOperation {
      var query = self.baseQuery()
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      query[kSecUseAuthenticationContext as String] = self.nonInteractiveContext()
      if let access = self.keychainAccess() { query[kSecAttrAccess as String] = access }

      let status = SecItemAdd(query as CFDictionary, nil)
      switch status {
      case errSecSuccess: return data
      case errSecDuplicateItem: return self.readKeyData()
      default: return nil
      }
    }
  }

  private func runKeychainOperation<T>(_ operation: @escaping () -> T?) -> T? {
    let lock = NSLock()
    var result: T?
    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .utility).async {
      let value = operation()
      lock.lock()
      result = value
      lock.unlock()
      semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + keychainTimeout) == .success else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return result
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.local.clipbored.encryption",
      kSecAttrAccount as String: "history-v1",
    ]
  }

  private func nonInteractiveContext() -> LAContext {
    let context = LAContext()
    context.interactionNotAllowed = true
    return context
  }

  private func keychainAccess() -> SecAccess? {
    var access: SecAccess?
    let status = clipBoredSecAccessCreate("Goldfish encryption key" as CFString, nil, &access)
    guard status == errSecSuccess else { return nil }
    return access
  }

  private func loadOrCreateFallbackKeyData() -> Data? {
    if let existing = readFallbackKeyData() { return existing }
    let generated = SymmetricKey(size: .bits256)
    let data = generated.withUnsafeBytes { Data($0) }
    guard saveFallbackKeyData(data) else { return nil }
    return data
  }

  private func readFallbackKeyData() -> Data? {
    let url = fallbackKeyURL()
    guard let data = try? Data(contentsOf: url), data.count == 32 else { return nil }
    return data
  }

  private func saveFallbackKeyData(_ data: Data) -> Bool {
    let url = fallbackKeyURL()
    let directory = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try data.write(to: url, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      return true
    } catch { return false }
  }

  private func deleteKeyData() -> Bool {
    runKeychainOperation {
      let status = SecItemDelete(self.baseQuery() as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound
    } ?? false
  }

  private func deleteFallbackKeyData() { try? FileManager.default.removeItem(at: fallbackKeyURL()) }

  private func fallbackKeyURL() -> URL {
    let base = HistoryStore.storageDirectory()
    return base.appendingPathComponent("history-encryption.key")
  }
}
