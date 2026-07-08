import Foundation

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
}

struct ClipboardArchiveCollection: Codable, Equatable {
  let name: String
  let colorHex: String?
}

enum ClipboardArchiveError: LocalizedError {
  case unsupportedVersion(Int)
  case invalidArchive

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      return "This ClipBored archive uses unsupported format version \(version)."
    case .invalidArchive:
      return "The selected file is not a valid ClipBored archive."
    }
  }
}

final class ClipboardArchiveService {
  static let fileExtension = "clipboredarchive"
  private static let currentFormatVersion = 1

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func exportArchive(
    items: [ClipboardItem],
    to url: URL,
    cacheService: ClipboardCacheService,
    collections: [ClipboardArchiveCollection] = []
  ) throws -> ClipboardArchiveSummary {
    var sidecarCount = 0
    let archivedItems = items.map { item -> ArchiveItem in
      let sidecars = archivedSidecars(for: item, cacheService: cacheService)
      sidecarCount += sidecars.count
      return ArchiveItem(item: item, sidecars: sidecars)
    }

    let archive = ArchivePayload(
      formatVersion: Self.currentFormatVersion,
      createdBy: AppConfiguration.appName,
      exportedAt: Date(),
      collections: collections,
      items: archivedItems
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(archive)
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

    return ClipboardArchiveSummary(
      itemCount: items.count,
      sidecarCount: sidecarCount,
      skippedItemCount: 0,
      skippedSidecarCount: 0
    )
  }

  func importArchive(
    from url: URL,
    cacheService: ClipboardCacheService
  ) throws -> ClipboardArchiveImport {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let archive: ArchivePayload
    do {
      archive = try decoder.decode(ArchivePayload.self, from: data)
    } catch {
      throw ClipboardArchiveError.invalidArchive
    }
    guard archive.formatVersion <= Self.currentFormatVersion else {
      throw ClipboardArchiveError.unsupportedVersion(archive.formatVersion)
    }

    var importedItems: [ClipboardItem] = []
    var sidecarCount = 0
    var skippedItemCount = 0
    var skippedSidecarCount = 0
    importedItems.reserveCapacity(archive.items.count)

    for archivedItem in archive.items {
      guard var item = archivedItem.clipboardItem() else {
        skippedItemCount += 1
        continue
      }

      for sidecar in archivedItem.sidecars {
        switch sidecar.role {
        case .image:
          if let path = cacheService.cacheImageSidecarData(sidecar.data, id: item.id) {
            item.imagePath = path
            if item.kind == .image {
              item.payload = path
            }
            sidecarCount += 1
          } else {
            skippedSidecarCount += 1
          }

        case .thumbnail:
          if let path = cacheService.cacheImageSidecarData(sidecar.data, id: item.id, fileNamePrefix: "thumb") {
            item.thumbnailPath = path
            sidecarCount += 1
          } else {
            skippedSidecarCount += 1
          }

        case .attachment:
          if let path = cacheService.cacheAttachmentData(
            sidecar.data,
            id: item.id,
            fileExtension: sidecar.fileExtension
          ) {
            if item.kind.usesManagedPayloadAttachment {
              item.payload = path
            }
            sidecarCount += 1
          } else {
            skippedSidecarCount += 1
          }
        }
      }

      importedItems.append(item)
    }

    let summary = ClipboardArchiveSummary(
      itemCount: importedItems.count,
      sidecarCount: sidecarCount,
      skippedItemCount: skippedItemCount,
      skippedSidecarCount: skippedSidecarCount
    )
    return ClipboardArchiveImport(
      items: importedItems,
      collections: archive.collections ?? [],
      summary: summary
    )
  }

  private func archivedSidecars(
    for item: ClipboardItem,
    cacheService: ClipboardCacheService
  ) -> [ArchiveSidecar] {
    var sidecars: [ArchiveSidecar] = []
    var archivedPaths = Set<String>()

    func append(_ role: ArchiveSidecarRole, path: String?, fallbackExtension: String) {
      guard let path, !path.clipboardTrimmed.isEmpty, !archivedPaths.contains(path) else { return }
      guard let data = cacheService.data(for: path) else { return }
      archivedPaths.insert(path)
      sidecars.append(
        ArchiveSidecar(
          role: role,
          fileExtension: fileExtension(for: path, fallback: fallbackExtension),
          data: data
        )
      )
    }

    switch item.kind {
    case .image:
      append(.image, path: item.imagePath ?? item.payload, fallbackExtension: "png")
      append(.thumbnail, path: item.thumbnailPath, fallbackExtension: "png")

    case .url:
      append(.thumbnail, path: item.thumbnailPath, fallbackExtension: "png")

    case .pdf:
      append(.attachment, path: item.payload, fallbackExtension: "pdf")

    case .audio:
      append(.attachment, path: item.payload, fallbackExtension: "sound")

    case .richText:
      append(.attachment, path: item.payload, fallbackExtension: "rtf")

    case .video:
      append(.attachment, path: item.payload, fallbackExtension: VideoPayload.fileExtension(from: item.payload))

    case .text, .file, .unknown, .color, .code:
      break
    }

    return sidecars
  }

  private func fileExtension(for path: String, fallback: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.clipboardTrimmed
    return ext.isEmpty ? fallback : ext
  }
}

private struct ArchivePayload: Codable {
  let formatVersion: Int
  let createdBy: String
  let exportedAt: Date
  let collections: [ClipboardArchiveCollection]?
  let items: [ArchiveItem]

  init(
    formatVersion: Int,
    createdBy: String,
    exportedAt: Date,
    collections: [ClipboardArchiveCollection],
    items: [ArchiveItem]
  ) {
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
    guard let kind = ClipboardItemKind(rawValue: kind) else { return nil }
    return ClipboardItem(
      id: id,
      kind: kind,
      displayText: displayText,
      payload: payload,
      payloadHash: payloadHash,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      useCount: useCount,
      sourceApp: sourceApp,
      imagePath: imagePath,
      thumbnailPath: thumbnailPath,
      isPinned: isPinned,
      sourceAppBundleId: sourceAppBundleId,
      ocrText: ocrText,
      collectionName: collectionName,
      customTitle: customTitle,
      sourceDeviceName: sourceDeviceName
    )
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

private extension ClipboardItemKind {
  var usesManagedPayloadAttachment: Bool {
    switch self {
    case .pdf, .audio, .richText, .video:
      return true
    case .text, .url, .image, .file, .unknown, .color, .code:
      return false
    }
  }
}
