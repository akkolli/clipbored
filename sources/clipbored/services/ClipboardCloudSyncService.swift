import Foundation

struct ClipboardCloudSyncStatus: Equatable {
  let isAvailable: Bool
  let archiveURL: URL?
  let lastModifiedAt: Date?
  let message: String
}

protocol ClipboardCloudSyncServicing {
  func syncArchiveURL() throws -> URL
  func status() -> ClipboardCloudSyncStatus
  @discardableResult
  func push(store: ClipboardStore) throws -> ClipboardArchiveSummary
  @discardableResult
  func pull(store: ClipboardStore) throws -> ClipboardArchiveSummary
}

enum ClipboardCloudSyncError: LocalizedError, Equatable {
  case unavailable
  case noRemoteArchive(URL)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "iCloud Sync is unavailable. Sign ClipBored with an iCloud container entitlement and make sure iCloud Drive is enabled."
    case .noRemoteArchive:
      return "No ClipBored iCloud archive has been created yet."
    }
  }
}

final class ClipboardCloudSyncService: ClipboardCloudSyncServicing {
  static let archiveFileName = "ClipBored.\(ClipboardArchiveService.fileExtension)"

  private let fileManager: FileManager
  private let containerProvider: () -> URL?

  init(
    fileManager: FileManager = .default,
    containerProvider: @escaping () -> URL? = {
      FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }
  ) {
    self.fileManager = fileManager
    self.containerProvider = containerProvider
  }

  func syncArchiveURL() throws -> URL {
    guard let containerURL = containerProvider() else {
      throw ClipboardCloudSyncError.unavailable
    }

    let directory = containerURL
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent(AppConfiguration.appName, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    return directory.appendingPathComponent(Self.archiveFileName)
  }

  func status() -> ClipboardCloudSyncStatus {
    do {
      let url = try syncArchiveURL()
      let attributes = try? fileManager.attributesOfItem(atPath: url.path)
      let lastModifiedAt = attributes?[.modificationDate] as? Date
      let message: String
      if lastModifiedAt != nil {
        message = "iCloud Sync is ready."
      } else {
        message = "iCloud Sync is ready. No remote archive yet."
      }
      return ClipboardCloudSyncStatus(
        isAvailable: true,
        archiveURL: url,
        lastModifiedAt: lastModifiedAt,
        message: message
      )
    } catch {
      return ClipboardCloudSyncStatus(
        isAvailable: false,
        archiveURL: nil,
        lastModifiedAt: nil,
        message: error.localizedDescription
      )
    }
  }

  @discardableResult
  func push(store: ClipboardStore) throws -> ClipboardArchiveSummary {
    let url = try syncArchiveURL()
    return try store.exportArchive(to: url)
  }

  @discardableResult
  func pull(store: ClipboardStore) throws -> ClipboardArchiveSummary {
    let url = try syncArchiveURL()
    guard fileManager.fileExists(atPath: url.path) else {
      throw ClipboardCloudSyncError.noRemoteArchive(url)
    }

    startDownloadingIfNeeded(url)
    return try store.importArchive(from: url)
  }

  private func startDownloadingIfNeeded(_ url: URL) {
    let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
    guard values?.isUbiquitousItem == true else { return }
    try? fileManager.startDownloadingUbiquitousItem(at: url)
  }
}
