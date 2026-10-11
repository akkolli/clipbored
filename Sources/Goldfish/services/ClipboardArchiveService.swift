import Foundation

typealias ArchiveWrite = (_ write: () throws -> Void) throws -> Void

struct ClipboardArchiveSummary: Equatable {
  let itemCount: Int
  let sidecarCount: Int
  let skippedItemCount: Int
  let skippedSidecarCount: Int
}

struct ClipboardArchiveImport {
  let items: [ClipboardItem]
  let collections: [ClipboardArchiveCollection]
  let summary: ClipboardArchiveSummary
  let createdPaths: [String]
}

struct ClipboardArchiveCollection: Codable, Equatable {
  let name: String
  let colorHex: String?
  let icon: String?
}

enum ClipboardArchiveError: LocalizedError {
  case unsupportedVersion(Int)
  case invalidArchive
  case attachmentWriteFailed
  case archiveTooLarge(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version): return "This Goldfish archive uses unsupported format version \(version)."
    case .invalidArchive: return "The selected file is not a valid Goldfish archive."
    case .attachmentWriteFailed: return "Goldfish could not save the archive attachments. Existing clips have not been replaced."
    case .archiveTooLarge(let maxBytes):
      let limit = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
      return "This Goldfish archive exceeds the \(limit) safety limit."
    }
  }
}

final class ClipboardArchiveService {
  static let fileExtension = "clipboredarchive"
  private static let currentFormatVersion = 1

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) { self.fileManager = fileManager }

  func exportArchive(
    items: [ClipboardItem], to url: URL, cacheService: ClipboardCacheService, collections: [ClipboardArchiveCollection] = [],
    write: ArchiveWrite = { try $0() }
  ) throws -> ClipboardArchiveSummary {
    var sidecarCount = 0
    var totalSidecarBytes = 0
    var archivedItems: [ArchiveItem] = []
    archivedItems.reserveCapacity(items.count)
    for item in items {
      let sidecars = archivedSidecars(for: item, cacheService: cacheService)
      totalSidecarBytes += sidecars.reduce(0) { $0 + $1.data.count }
      guard totalSidecarBytes <= AppConfiguration.maxPortableArchiveSidecarBytes else {
        throw ClipboardArchiveError.archiveTooLarge(AppConfiguration.maxPortableArchiveBytes)
      }
      sidecarCount += sidecars.count
      archivedItems.append(ArchiveItem(item: item, sidecars: sidecars))
    }

    let archive = ArchivePayload(
      formatVersion: Self.currentFormatVersion, createdBy: AppConfiguration.appName, exportedAt: Date(), collections: collections,
      items: archivedItems)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(archive)
    guard Self.isArchiveSizeAllowed(data.count) else {
      throw ClipboardArchiveError.archiveTooLarge(AppConfiguration.maxPortableArchiveBytes)
    }
    try write {
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    return ClipboardArchiveSummary(itemCount: items.count, sidecarCount: sidecarCount, skippedItemCount: 0, skippedSidecarCount: 0)
  }

  func importArchive(from url: URL, cacheService: ClipboardCacheService) throws -> ClipboardArchiveImport {
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, !Self.isArchiveSizeAllowed(size) {
      throw ClipboardArchiveError.archiveTooLarge(AppConfiguration.maxPortableArchiveBytes)
    }
    let data = try Data(contentsOf: url)
    guard Self.isArchiveSizeAllowed(data.count) else {
      throw ClipboardArchiveError.archiveTooLarge(AppConfiguration.maxPortableArchiveBytes)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let archive: ArchivePayload
    do { archive = try decoder.decode(ArchivePayload.self, from: data) } catch { throw ClipboardArchiveError.invalidArchive }
    guard archive.formatVersion <= Self.currentFormatVersion else { throw ClipboardArchiveError.unsupportedVersion(archive.formatVersion) }
    guard archive.formatVersion > 0 else { throw ClipboardArchiveError.invalidArchive }

    var importedItems: [ClipboardItem] = []
    var sidecarCount = 0
    var skippedItemCount = 0
    var skippedSidecarCount = 0
    var createdPaths: [String] = []
    var completed = false
    defer { if !completed { cacheService.removeManagedFiles(createdPaths) } }
    importedItems.reserveCapacity(archive.items.count)

    for archivedItem in archive.items {
      guard var item = archivedItem.clipboardItem() else {
        skippedItemCount += 1
        continue
      }

      // Storage identities are local. Never overwrite a live attachment with an
      // imported UUID, or trust absolute paths from a portable archive.
      let storageID = UUID()
      var roles = Set<String>()
      for sidecar in archivedItem.sidecars {
        guard roles.insert(sidecar.role.rawValue).inserted else { throw ClipboardArchiveError.invalidArchive }
        let path: String?
        switch sidecar.role {
        case .image:
          guard item.kind == .image || item.kind == .url else { throw ClipboardArchiveError.invalidArchive }
          path = cacheService.cacheImageSidecarData(sidecar.data, id: storageID)
          item.imagePath = path
          if item.kind == .image { item.payload = path ?? "" }
        case .thumbnail:
          guard item.kind == .image || item.kind == .url else { throw ClipboardArchiveError.invalidArchive }
          path = cacheService.cacheImageSidecarData(sidecar.data, id: storageID, fileNamePrefix: "thumb")
          item.thumbnailPath = path
        case .attachment:
          guard item.kind.usesManagedPayloadAttachment else { throw ClipboardArchiveError.invalidArchive }
          path = cacheService.cacheAttachmentData(sidecar.data, id: storageID, fileExtension: sidecar.fileExtension)
          item.payload = path ?? ""
        }
        guard let path else { throw ClipboardArchiveError.attachmentWriteFailed }
        createdPaths.append(path)
        sidecarCount += 1
      }
      if item.kind == .image || item.kind.usesManagedPayloadAttachment, item.payload.isEmpty {
        skippedItemCount += 1
        skippedSidecarCount += archivedItem.sidecars.count
        cacheService.removeCachedReferences(item)
        continue
      }
      importedItems.append(item)
    }

    let summary = ClipboardArchiveSummary(
      itemCount: importedItems.count, sidecarCount: sidecarCount, skippedItemCount: skippedItemCount,
      skippedSidecarCount: skippedSidecarCount)
    completed = true
    return ClipboardArchiveImport(
      items: importedItems, collections: archive.collections ?? [], summary: summary, createdPaths: createdPaths)
  }

  private func archivedSidecars(for item: ClipboardItem, cacheService: ClipboardCacheService) -> [ArchiveSidecar] {
    var sidecars: [ArchiveSidecar] = []
    var archivedPaths = Set<String>()

    func append(_ role: ArchiveSidecarRole, path: String?, fallbackExtension: String) {
      guard let path, cacheService.isManagedSidecar(path: path), !archivedPaths.contains(path) else { return }
      guard let data = cacheService.data(for: path) else { return }
      archivedPaths.insert(path)
      sidecars.append(ArchiveSidecar(role: role, fileExtension: fileExtension(for: path, fallback: fallbackExtension), data: data))
    }

    switch item.kind {
    case .image:
      append(.image, path: item.imagePath ?? item.payload, fallbackExtension: "png")
      append(.thumbnail, path: item.thumbnailPath, fallbackExtension: "png")

    case .url: append(.thumbnail, path: item.thumbnailPath, fallbackExtension: "png")

    case .pdf: append(.attachment, path: item.payload, fallbackExtension: "pdf")

    case .audio: append(.attachment, path: item.payload, fallbackExtension: "sound")

    case .richText: append(.attachment, path: item.payload, fallbackExtension: "rtf")

    case .video: append(.attachment, path: item.payload, fallbackExtension: VideoPayload.fileExtension(from: item.payload))

    case .text, .file, .unknown, .color, .code: break
    }

    return sidecars
  }

  private func fileExtension(for path: String, fallback: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.clipboardTrimmed
    return ext.isEmpty ? fallback : ext
  }

  static func isArchiveSizeAllowed(_ byteCount: Int) -> Bool { byteCount >= 0 && byteCount <= AppConfiguration.maxPortableArchiveBytes }
}

private struct ArchivePayload: Codable {
  let formatVersion: Int
  let createdBy: String
  let exportedAt: Date
  let collections: [ClipboardArchiveCollection]?
  let items: [ArchiveItem]

  init(formatVersion: Int, createdBy: String, exportedAt: Date, collections: [ClipboardArchiveCollection], items: [ArchiveItem]) {
    self.formatVersion = formatVersion
    self.createdBy = createdBy
    self.exportedAt = exportedAt
    self.collections = collections.isEmpty ? nil : collections
    self.items = items
  }
}

private struct ArchiveItem: Codable {
  let id: UUID
  let kind: Int
  let displayText: String
  let payload: String
  let payloadHash: String
  let createdAt: Date
  let lastUsedAt: Date
  let useCount: Int
  let sourceApp: String?
  let imagePath: String?
  let thumbnailPath: String?
  let isPinned: Bool
  let sourceAppBundleId: String?
  let ocrText: String?
  let collectionName: String?
  let customTitle: String?
  let sourceDeviceName: String?
  let sidecars: [ArchiveSidecar]

  init(item: ClipboardItem, sidecars: [ArchiveSidecar]) {
    id = item.id
    kind = item.kind.rawValue
    displayText = item.displayText
    payload = item.payload
    payloadHash = item.payloadHash
    createdAt = item.createdAt
    lastUsedAt = item.lastUsedAt
    useCount = item.useCount
    sourceApp = item.sourceApp
    imagePath = item.imagePath
    thumbnailPath = item.thumbnailPath
    isPinned = item.isPinned
    sourceAppBundleId = item.sourceAppBundleId
    ocrText = item.ocrText
    collectionName = item.collectionName
    customTitle = item.customTitle
    sourceDeviceName = item.sourceDeviceName
    self.sidecars = sidecars
  }

  func clipboardItem() -> ClipboardItem? {
    guard let kind = ClipboardItemKind(rawValue: kind), (0...Int(Int32.max)).contains(useCount), createdAt.timeIntervalSince1970.isFinite,
      lastUsedAt.timeIntervalSince1970.isFinite, createdAt >= .distantPast, createdAt <= .distantFuture, lastUsedAt >= .distantPast,
      lastUsedAt <= .distantFuture
    else { return nil }
    return ClipboardItem(
      id: id, kind: kind, displayText: displayText, payload: kind == .image || kind.usesManagedPayloadAttachment ? "" : payload,
      payloadHash: payloadHash, createdAt: createdAt, lastUsedAt: lastUsedAt, useCount: useCount, sourceApp: sourceApp, imagePath: nil,
      thumbnailPath: nil, isPinned: isPinned, sourceAppBundleId: sourceAppBundleId, ocrText: ocrText, collectionName: collectionName,
      customTitle: customTitle, sourceDeviceName: sourceDeviceName)
  }
}

private struct ArchiveSidecar: Codable {
  let role: ArchiveSidecarRole
  let fileExtension: String
  let data: Data
}

private enum ArchiveSidecarRole: String, Codable {
  case image
  case thumbnail
  case attachment
}

extension ClipboardItemKind {
  fileprivate var usesManagedPayloadAttachment: Bool {
    switch self {
    case .pdf, .audio, .richText, .video: return true
    case .text, .url, .image, .file, .unknown, .color, .code: return false
    }
  }
}
