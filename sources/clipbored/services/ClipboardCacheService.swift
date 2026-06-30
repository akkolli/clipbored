import AppKit
import Foundation

final class ClipboardCacheService {
  private let thumbnailCache = NSCache<NSString, NSImage>()
  private let fileManager = FileManager.default
  private let queue = DispatchQueue(label: "clipboard.cache.service", qos: .utility)
  private let imageDirectory: URL
  private let attachmentDirectory: URL
  private let temporaryPreviewDirectory: URL
  private let encryptionService: ClipboardEncryptionService

  init(baseURL: URL? = nil, encryptionService: ClipboardEncryptionService = ClipboardEncryptionService()) {
    let base = baseURL ?? ClipboardStore.storageDirectory()
    imageDirectory = base.appendingPathComponent("images", isDirectory: true)
    attachmentDirectory = base.appendingPathComponent("attachments", isDirectory: true)
    temporaryPreviewDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(AppConfiguration.appName, isDirectory: true)
      .appendingPathComponent("Previews", isDirectory: true)
    self.encryptionService = encryptionService
    thumbnailCache.countLimit = 128
    try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
    hardenDirectory(imageDirectory)
    hardenDirectory(attachmentDirectory)
    clearTemporaryPreviews()
  }

  func cacheImage(_ image: NSImage, id: UUID) -> (full: String, thumb: String)? {
    let fullURL = imageDirectory.appendingPathComponent("\(id.uuidString).png")
    let thumbURL = imageDirectory.appendingPathComponent("thumb-\(id.uuidString).png")

    let boundedFullImage = image.resized(to: .init(width: AppConfiguration.maxFullImagePixelSize, height: AppConfiguration.maxFullImagePixelSize))
    guard let fullData = boundedFullImage.pngData() else { return nil }
    let thumbnail = image.resized(to: .init(width: 320, height: 320))
    guard let thumbData = thumbnail.pngData() else { return nil }

    do {
      try encrypted(fullData).write(to: fullURL, options: .atomic)
      try encrypted(thumbData).write(to: thumbURL, options: .atomic)
      hardenFile(fullURL)
      hardenFile(thumbURL)
      thumbnailCache.setObject(thumbImage(thumbData) ?? image, forKey: thumbURL.path as NSString)
      return (full: fullURL.path, thumb: thumbURL.path)
    } catch {
      return nil
    }
  }

  func cachePDF(_ data: Data, id: UUID) -> String? {
    cacheAttachment(data, id: id, fileExtension: "pdf")
  }

  func cacheAudio(_ data: Data, id: UUID) -> String? {
    cacheAttachment(data, id: id, fileExtension: "sound")
  }

  func cacheRichText(_ data: Data, id: UUID) -> String? {
    cacheAttachment(data, id: id, fileExtension: "rtf")
  }

  private func cacheAttachment(_ data: Data, id: UUID, fileExtension: String) -> String? {
    let url = attachmentDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
    do {
      try encrypted(data).write(to: url, options: .atomic)
      hardenFile(url)
      return url.path
    } catch {
      return nil
    }
  }

  func image(for path: String) -> NSImage? {
    let key = NSString(string: path)
    if let cached = thumbnailCache.object(forKey: key) {
      return cached
    }

    guard let data = data(for: path), let image = NSImage(data: data) else { return nil }
    thumbnailCache.setObject(image, forKey: key)
    return image
  }

  func previewThumbnail(for item: ClipboardItem) -> NSImage? {
    switch item.kind {
    case .url, .image:
      guard let path = item.thumbnailPath else { return nil }
      return image(for: path)

    case .pdf:
      let key = NSString(string: "pdf-preview:\(item.id.uuidString):\(item.payload)")
      if let cached = thumbnailCache.object(forKey: key) {
        return cached
      }

      if let data = data(for: item.payload),
         let image = NSImage(data: data),
         hasDrawableSize(image) {
        let thumbnail = image.resized(to: CGSize(width: 260, height: 132))
        thumbnailCache.setObject(thumbnail, forKey: key)
        return thumbnail
      }
      return filePreviewThumbnail(for: item.payload)

    case .file:
      return filePreviewThumbnail(for: item.payload)

    case .text, .unknown, .audio, .richText:
      return nil
    }
  }

  func data(for path: String) -> Data? {
    let url = URL(fileURLWithPath: path)
    guard let stored = try? Data(contentsOf: url) else {
      return nil
    }

    if ClipboardEncryptionService.isProtected(stored) {
      return encryptionService.unprotectData(stored)
    }

    if isManagedSidecar(path: path), encryptionService.isAvailable {
      try? encrypted(stored).write(to: url, options: .atomic)
      hardenFile(url)
    }
    return stored
  }

  private func filePreviewThumbnail(for path: String) -> NSImage? {
    guard let url = fileURL(from: path), fileManager.fileExists(atPath: url.path) else {
      return nil
    }

    let key = NSString(string: "file-preview:\(url.standardizedFileURL.path)")
    if let cached = thumbnailCache.object(forKey: key) {
      return cached
    }

    let image: NSImage
    if let decoded = NSImage(contentsOf: url), decoded.isValid, hasDrawableSize(decoded) {
      image = decoded.resized(to: CGSize(width: 260, height: 132))
    } else {
      let icon = NSWorkspace.shared.icon(forFile: url.path)
      icon.size = NSSize(width: 96, height: 96)
      image = icon
    }

    thumbnailCache.setObject(image, forKey: key)
    return image
  }

  private func hasDrawableSize(_ image: NSImage) -> Bool {
    image.size.width > 0 && image.size.height > 0
  }

  private func fileURL(from path: String) -> URL? {
    let trimmed = path.clipboardTrimmed
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed) {
      return url
    }
    return URL(fileURLWithPath: trimmed)
  }

  func temporaryReadableURL(for item: ClipboardItem) -> URL? {
    switch item.kind {
    case .image:
      guard let path = item.imagePath, let data = data(for: path) else { return nil }
      return writeTemporaryCopy(data: data, id: item.id, fileExtension: "png")
    case .pdf:
      guard let data = data(for: item.payload) else { return nil }
      return writeTemporaryCopy(data: data, id: item.id, fileExtension: "pdf")
    case .audio:
      guard let data = data(for: item.payload) else { return nil }
      return writeTemporaryCopy(data: data, id: item.id, fileExtension: "sound")
    case .richText:
      guard let data = data(for: item.payload) else { return nil }
      return writeTemporaryCopy(data: data, id: item.id, fileExtension: "rtf")
    default:
      return nil
    }
  }

  func temporaryPreviewURL(for item: ClipboardItem) -> URL? {
    switch item.kind {
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      return urls.first { fileManager.fileExists(atPath: $0.path) }
    case .text, .unknown:
      let text = item.payload.clipboardTrimmed.isEmpty ? item.displayText : item.payload
      guard !text.clipboardTrimmed.isEmpty else { return nil }
      return writeTemporaryCopy(data: Data(text.utf8), id: item.id, fileExtension: "txt")
    case .url:
      guard let data = webLocationData(for: item.payload) else { return nil }
      return writeTemporaryCopy(data: data, id: item.id, fileExtension: "webloc")
    case .image, .pdf, .audio, .richText:
      return temporaryReadableURL(for: item)
    }
  }

  func encryptCachedReferencesIfNeeded(for items: [ClipboardItem]) {
    queue.async { [weak self] in
      guard let self else { return }
      for item in items {
        if let imagePath = item.imagePath {
          _ = self.data(for: imagePath)
        }
        if let thumbnailPath = item.thumbnailPath {
          _ = self.data(for: thumbnailPath)
        }
        if (item.kind == .pdf || item.kind == .audio || item.kind == .richText), self.isManagedAttachment(path: item.payload) {
          _ = self.data(for: item.payload)
        }
      }
    }
  }

  func removeCachedReferences(_ item: ClipboardItem) {
    queue.async { [weak self] in
      guard let self else { return }
      if let path = item.imagePath {
        try? self.fileManager.removeItem(atPath: path)
        self.thumbnailCache.removeObject(forKey: NSString(string: path))
      }
      if let path = item.thumbnailPath {
        try? self.fileManager.removeItem(atPath: path)
        self.thumbnailCache.removeObject(forKey: NSString(string: path))
      }
      if (item.kind == .pdf || item.kind == .audio || item.kind == .richText), self.isManagedAttachment(path: item.payload) {
        try? self.fileManager.removeItem(atPath: item.payload)
      }
    }
  }

  func purgeIfNeeded(maxBytes: Int64) {
    queue.async {
      DiagnosticsService.shared.incrementCachePurge()
      let urls = (try? self.fileManager.contentsOfDirectory(at: self.imageDirectory, includingPropertiesForKeys: nil, options: [])) ?? []
      var items: [(url: URL, size: Int64, date: Date)] = []
      var totalSize: Int64 = 0

      for url in urls {
        guard
          let attrs = try? self.fileManager.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? NSNumber,
          let mod = attrs[.modificationDate] as? Date
        else { continue }

        let bytes = Int64(size.int64Value)
        totalSize += bytes
        items.append((url, bytes, mod))
      }

      if totalSize <= maxBytes && items.count <= AppConfiguration.maxImageCacheFiles {
        return
      }

      let ordered = items.sorted { $0.date < $1.date }
      var remaining = totalSize
      var pointer = 0

      while (remaining > maxBytes || ordered.count - pointer > AppConfiguration.maxImageCacheFiles) && pointer < ordered.count {
        let candidate = ordered[pointer]
        try? self.fileManager.removeItem(at: candidate.url)
        self.thumbnailCache.removeObject(forKey: NSString(string: candidate.url.path))
        remaining -= candidate.size
        pointer += 1
      }
    }
  }

  func clearCache() {
    queue.async { [weak self] in
      guard let self else { return }
      thumbnailCache.removeAllObjects()
      let contents = (try? self.fileManager.contentsOfDirectory(at: self.imageDirectory, includingPropertiesForKeys: nil, options: [])) ?? []
      for url in contents {
        try? self.fileManager.removeItem(at: url)
      }
      self.removeTemporaryPreviewFiles()
    }
  }

  func clearTemporaryPreviews(wait: Bool = false) {
    let work: () -> Void = { [weak self] in
      guard let self else { return }
      self.removeTemporaryPreviewFiles()
    }
    if wait {
      queue.sync(execute: work)
    } else {
      queue.async(execute: work)
    }
  }

  func flushForTesting() {
    queue.sync {}
  }

  private func thumbImage(_ data: Data) -> NSImage? {
    NSImage(data: data)
  }

  private func encrypted(_ data: Data) -> Data {
    encryptionService.protectData(data)
  }

  private func hardenDirectory(_ url: URL) {
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }

  private func hardenFile(_ url: URL) {
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func isManagedAttachment(path: String) -> Bool {
    URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL == attachmentDirectory.standardizedFileURL
  }

  private func isManagedSidecar(path: String) -> Bool {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
    return directory == imageDirectory.standardizedFileURL || directory == attachmentDirectory.standardizedFileURL
  }

  private func writeTemporaryCopy(data: Data, id: UUID, fileExtension: String) -> URL? {
    let url = temporaryPreviewDirectory.appendingPathComponent("\(id.uuidString)-\(UUID().uuidString).\(fileExtension)")

    do {
      try fileManager.createDirectory(at: temporaryPreviewDirectory, withIntermediateDirectories: true)
      try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryPreviewDirectory.path)
      try data.write(to: url, options: .atomic)
      hardenFile(url)
      return url
    } catch {
      return nil
    }
  }

  private func webLocationData(for value: String) -> Data? {
    let trimmed = value.clipboardTrimmed
    guard !trimmed.isEmpty else { return nil }
    return try? PropertyListSerialization.data(
      fromPropertyList: ["URL": trimmed],
      format: .xml,
      options: 0
    )
  }

  private func removeTemporaryPreviewFiles() {
    guard fileManager.fileExists(atPath: temporaryPreviewDirectory.path) else {
      return
    }

    let contents = (try? fileManager.contentsOfDirectory(
      at: temporaryPreviewDirectory,
      includingPropertiesForKeys: nil,
      options: []
    )) ?? []

    for url in contents {
      try? fileManager.removeItem(at: url)
    }

    if ((try? fileManager.contentsOfDirectory(at: temporaryPreviewDirectory, includingPropertiesForKeys: nil)) ?? []).isEmpty {
      try? fileManager.removeItem(at: temporaryPreviewDirectory)
    }
  }
}
