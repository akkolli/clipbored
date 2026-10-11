import AVFoundation
import AppKit
import Foundation

// MARK: - MediaCache

final class MediaCache {
  typealias VideoThumbnailProvider = (URL) -> NSImage?

  private let thumbnailCache = NSCache<NSString, NSImage>()
  private let fileManager = FileManager.default
  private let queue = DispatchQueue(label: "clipboard.cache.service", qos: .utility)
  private let imageDirectory: URL
  private let attachmentDirectory: URL
  private let temporaryPreviewDirectory: URL
  private let encryptionService: HistoryEncryption
  private let videoThumbnailProvider: VideoThumbnailProvider

  init(
    baseURL: URL? = nil, encryptionService: HistoryEncryption = HistoryEncryption(),
    videoThumbnailProvider: VideoThumbnailProvider? = nil
  ) {
    let base = baseURL ?? HistoryStore.storageDirectory()
    imageDirectory = base.appendingPathComponent("images", isDirectory: true)
    attachmentDirectory = base.appendingPathComponent("attachments", isDirectory: true)
    temporaryPreviewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      Configuration.storageName, isDirectory: true
    ).appendingPathComponent("Previews", isDirectory: true)
    self.encryptionService = encryptionService
    self.videoThumbnailProvider = videoThumbnailProvider ?? Self.makeVideoThumbnail
    thumbnailCache.countLimit = 128
    try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    try? fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
    hardenDirectory(imageDirectory)
    hardenDirectory(attachmentDirectory)
    clearTemporaryPreviews(wait: true)
  }

  func cacheImage(_ image: NSImage, id: UUID) -> (full: String, thumb: String)? {
    let fullURL = imageDirectory.appendingPathComponent("\(id.uuidString).png")
    let thumbURL = imageDirectory.appendingPathComponent("thumb-\(id.uuidString).png")

    let boundedFullImage = image.resized(
      to: .init(width: Configuration.maxFullImagePixelSize, height: Configuration.maxFullImagePixelSize))
    guard let fullData = boundedFullImage.pngData() else { return nil }
    let thumbnail = image.resized(to: .init(width: 320, height: 320))
    guard let thumbData = thumbnail.pngData() else { return nil }

    do {
      try writeCachedData(fullData, to: fullURL)
      try writeCachedData(thumbData, to: thumbURL)
      thumbnailCache.setObject(NSImage(data: thumbData) ?? image, forKey: thumbURL.path as NSString)
      return (full: fullURL.path, thumb: thumbURL.path)
    } catch { return nil }
  }

  func cachePDF(_ data: Data, id: UUID) -> String? { cacheAttachmentData(data, id: id, fileExtension: "pdf") }

  func cacheRichText(_ data: Data, id: UUID) -> String? { cacheAttachmentData(data, id: id, fileExtension: "rtf") }

  func cacheAttachmentData(_ data: Data, id: UUID, fileExtension: String) -> String? {
    let sanitizedExtension = fileExtension.split { $0 == "." || $0 == "/" || $0 == "\\" }.last.map(String.init) ?? "dat"
    let normalizedExtension = sanitizedExtension.clipboardTrimmed.isEmpty ? "dat" : sanitizedExtension
    return cacheAttachment(data, id: id, fileExtension: normalizedExtension)
  }

  func cacheImageSidecarData(_ data: Data, id: UUID, fileNamePrefix: String? = nil) -> String? {
    let prefix = fileNamePrefix?.clipboardTrimmed ?? ""
    let fileName = prefix.isEmpty ? "\(id.uuidString).png" : "\(prefix)-\(id.uuidString).png"
    let url = imageDirectory.appendingPathComponent(fileName)
    do {
      try writeCachedData(data, to: url)
      if let image = NSImage(data: data) { thumbnailCache.setObject(image, forKey: url.path as NSString) }
      return url.path
    } catch { return nil }
  }

  private func cacheAttachment(_ data: Data, id: UUID, fileExtension: String) -> String? {
    let url = attachmentDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
    do {
      try writeCachedData(data, to: url)
      return url.path
    } catch { return nil }
  }

  func image(for path: String) -> NSImage? {
    let key = NSString(string: path)
    if let cached = thumbnailCache.object(forKey: key) { return cached }

    guard let data = data(for: path), let image = NSImage(data: data) else { return nil }
    thumbnailCache.setObject(image, forKey: key)
    return image
  }

  func previewThumbnail(for item: Clip) -> NSImage? {
    switch item.kind {
    case .url, .image:
      if let path = item.thumbnailPath, let thumbnail = image(for: path) { return thumbnail }
      guard item.kind == .image, let original = image(for: item.imagePath ?? item.payload) else { return nil }
      return original.resized(to: CGSize(width: 320, height: 320))

    case .pdf:
      let key = NSString(string: "pdf-preview:\(item.id.uuidString):\(item.payload)")
      if let cached = thumbnailCache.object(forKey: key) { return cached }

      if let data = data(for: item.payload), let image = NSImage(data: data), hasDrawableSize(image) {
        let thumbnail = image.resized(to: CGSize(width: 260, height: 132))
        thumbnailCache.setObject(thumbnail, forKey: key)
        return thumbnail
      }
      return filePreviewThumbnail(for: item.payload)

    case .file: return filePreviewThumbnail(for: item.payload)

    case .video: return videoPreviewThumbnail(for: item)

    case .text, .unknown, .audio, .richText, .color, .code: return nil
    }
  }

  func data(for path: String) -> Data? {
    let url = URL(fileURLWithPath: path)
    guard let stored = try? Data(contentsOf: url) else { return nil }

    if HistoryEncryption.isProtected(stored) { return encryptionService.unprotectData(stored) }

    if isManagedSidecar(path: path), encryptionService.isAvailable {
      try? encryptionService.protectData(stored).write(to: url, options: .atomic)
      hardenFile(url)
    }
    return stored
  }

  private func filePreviewThumbnail(for path: String) -> NSImage? {
    guard let url = fileURL(from: path), fileManager.fileExists(atPath: url.path) else { return nil }

    let key = NSString(string: "file-preview:\(url.standardizedFileURL.path)")
    if let cached = thumbnailCache.object(forKey: key) { return cached }

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

  private func videoPreviewThumbnail(for item: Clip) -> NSImage? {
    let key = NSString(string: "video-preview:\(item.id.uuidString):\(item.payload)")
    if let cached = thumbnailCache.object(forKey: key) { return cached }

    guard let data = data(for: item.payload),
      let temporaryURL = writeTemporaryCopy(
        data: data, id: item.id, fileExtension: VideoPayload.fileExtension(from: item.payload))
    else { return nil }
    defer { removeTemporaryCopyIfPossible(temporaryURL) }

    guard let image = videoThumbnailProvider(temporaryURL), hasDrawableSize(image) else { return nil }
    let thumbnail = image.resized(to: CGSize(width: 260, height: 132))
    thumbnailCache.setObject(thumbnail, forKey: key)
    return thumbnail
  }

  private static func makeVideoThumbnail(from url: URL) -> NSImage? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 520, height: 264)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

    for time in [CMTime(seconds: 0.08, preferredTimescale: 600), .zero] {
      if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
      }
    }
    return nil
  }

  private func hasDrawableSize(_ image: NSImage) -> Bool { image.size.width > 0 && image.size.height > 0 }

  private func fileURL(from path: String) -> URL? {
    let trimmed = path.clipboardTrimmed
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed) { return url }
    return URL(fileURLWithPath: trimmed)
  }

  func temporaryReadableURL(for item: Clip) -> URL? {
    guard let fileExtension = item.mediaFileExtension else { return nil }
    let path = item.kind == .image ? item.imagePath ?? item.payload : item.payload
    guard let data = data(for: path) else { return nil }
    return writeTemporaryCopy(data: data, id: item.id, fileExtension: fileExtension)
  }

  func temporaryPreviewURL(for item: Clip) -> URL? {
    switch item.kind {
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      return urls.first { fileManager.fileExists(atPath: $0.path) }
    case .text, .code, .unknown:
      let text = item.payload.clipboardTrimmed.isEmpty ? item.displayText : item.payload
      guard !text.clipboardTrimmed.isEmpty else { return nil }
      return writeTemporaryCopy(data: Data(text.utf8), id: item.id, fileExtension: "txt")
    case .color:
      let text = ColorPayload.previewText(from: item.payload)
      return writeTemporaryCopy(data: Data(text.utf8), id: item.id, fileExtension: "txt")
    case .url:
      guard let data = webLocationData(for: item.payload) else { return nil }
      return writeTemporaryCopy(data: data, id: item.id, fileExtension: "webloc")
    case .image, .pdf, .audio, .richText, .video: return temporaryReadableURL(for: item)
    }
  }

  private func managedReferences(for item: Clip) -> Set<String> {
    let payload = [.image, .pdf, .audio, .richText, .video].contains(item.kind) ? item.payload : nil
    return Set([item.imagePath, item.thumbnailPath, payload].compactMap { $0 }.filter(isManagedSidecar))
  }

  func encryptCachedReferencesIfNeeded(for items: [Clip]) {
    queue.async { [weak self] in
      guard let self else { return }
      for path in items.flatMap({ self.managedReferences(for: $0) }) { _ = self.data(for: path) }
    }
  }

  func removeCachedReferences(_ item: Clip) {
    queue.async { [weak self] in
      guard let self else { return }
      for path in self.managedReferences(for: item) {
        try? self.fileManager.removeItem(atPath: path)
        self.thumbnailCache.removeObject(forKey: path as NSString)
      }
    }
  }

  private func thumbnailFiles() -> [URL] {
    ((try? fileManager.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)) ?? []).filter {
      $0.lastPathComponent.hasPrefix("thumb-")
    }
  }

  func purgeIfNeeded(maxBytes: Int64) {
    queue.async {
      let urls = self.thumbnailFiles()
      var items: [(url: URL, size: Int64, date: Date)] = []
      var totalSize: Int64 = 0

      for url in urls {
        guard let attrs = try? self.fileManager.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? NSNumber, let mod = attrs[.modificationDate] as? Date
        else { continue }

        let bytes = Int64(size.int64Value)
        totalSize += bytes
        items.append((url, bytes, mod))
      }

      if totalSize <= maxBytes && items.count <= Configuration.maxImageCacheFiles { return }

      let ordered = items.sorted { $0.date < $1.date }
      var remaining = totalSize
      var pointer = 0

      while (remaining > maxBytes || ordered.count - pointer > Configuration.maxImageCacheFiles)
        && pointer < ordered.count
      {
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
      let contents = self.thumbnailFiles()
      for url in contents { try? self.fileManager.removeItem(at: url) }
      self.removeTemporaryPreviewFiles()
    }
  }

  func clearTemporaryPreviews(wait: Bool = false) {
    let work: () -> Void = { [weak self] in
      guard let self else { return }
      self.removeTemporaryPreviewFiles()
    }
    if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
  }

  func flushForTesting() { queue.sync {} }

  private func writeCachedData(_ data: Data, to url: URL) throws {
    try encryptionService.protectData(data).write(to: url, options: .atomic)
    hardenFile(url)
  }

  private func hardenDirectory(_ url: URL) {
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }

  private func hardenFile(_ url: URL) {
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func isManagedSidecar(path: String) -> Bool {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath()
    return [imageDirectory, attachmentDirectory].contains { $0.resolvingSymlinksInPath() == directory }
  }

  private func writeTemporaryCopy(data: Data, id: UUID, fileExtension: String) -> URL? {
    let url = temporaryPreviewDirectory.appendingPathComponent("\(id.uuidString)-\(UUID().uuidString).\(fileExtension)")

    do {
      try fileManager.createDirectory(at: temporaryPreviewDirectory, withIntermediateDirectories: true)
      try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryPreviewDirectory.path)
      try data.write(to: url, options: .atomic)
      hardenFile(url)
      return url
    } catch { return nil }
  }

  private func removeTemporaryCopyIfPossible(_ url: URL) {
    try? fileManager.removeItem(at: url)
    if ((try? fileManager.contentsOfDirectory(at: temporaryPreviewDirectory, includingPropertiesForKeys: nil)) ?? [])
      .isEmpty
    {
      try? fileManager.removeItem(at: temporaryPreviewDirectory)
    }
  }

  private func webLocationData(for value: String) -> Data? {
    let trimmed = value.clipboardTrimmed
    guard !trimmed.isEmpty else { return nil }
    return try? PropertyListSerialization.data(fromPropertyList: ["URL": trimmed], format: .xml, options: 0)
  }

  private func removeTemporaryPreviewFiles() {
    guard fileManager.fileExists(atPath: temporaryPreviewDirectory.path) else { return }

    let contents =
      (try? fileManager.contentsOfDirectory(at: temporaryPreviewDirectory, includingPropertiesForKeys: nil, options: []))
      ?? []

    for url in contents { try? fileManager.removeItem(at: url) }

    if ((try? fileManager.contentsOfDirectory(at: temporaryPreviewDirectory, includingPropertiesForKeys: nil)) ?? [])
      .isEmpty
    {
      try? fileManager.removeItem(at: temporaryPreviewDirectory)
    }
  }
}

// MARK: - PasteService

final class PasteService {
  private let cacheService: MediaCache
  private let accessibilityPermissionProvider: () -> Bool
  private let targetActivator: (NSRunningApplication) -> Bool
  private let keyboardPasteScheduler: (@escaping () -> Void) -> Void

  init(
    cacheService: MediaCache = MediaCache(),
    accessibilityPermissionProvider: @escaping () -> Bool = AccessibilityPermissionService.requestPromptIfNeeded,
    targetActivator: @escaping (NSRunningApplication) -> Bool = PasteService.activateForAutomaticPaste,
    keyboardPasteScheduler: @escaping (@escaping () -> Void) -> Void = { action in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { action() }
    }
  ) {
    self.cacheService = cacheService
    self.accessibilityPermissionProvider = accessibilityPermissionProvider
    self.targetActivator = targetActivator
    self.keyboardPasteScheduler = keyboardPasteScheduler
  }

  enum PasteActionResult: Equatable {
    case pasted
    case pastedPlainText
    case copied
    case copiedPlainText
    case copiedNeedsPermission
    case copiedPlainTextNeedsPermission
    case failed(String)

    var message: String {
      switch self {
      case .pasted: return "Pasted"
      case .pastedPlainText: return "Pasted Plain Text"
      case .copied: return "Copied"
      case .copiedPlainText: return "Copied Plain Text"
      case .copiedNeedsPermission: return "Copied. Grant Accessibility access to paste automatically."
      case .copiedPlainTextNeedsPermission:
        return "Copied Plain Text. Grant Accessibility access to paste automatically."
      case .failed(let message): return message
      }
    }
  }

  func paste(_ item: Clip, targetApp: NSRunningApplication?) -> PasteActionResult {
    guard writeToPasteboard(item) else { return .failed("Could not write item to clipboard.") }

    return completePaste(targetApp: targetApp)
  }

  func paste(_ items: [Clip], targetApp: NSRunningApplication?) -> PasteActionResult {
    guard writeToPasteboard(items) else { return .failed("Could not write items to clipboard.") }

    return completePaste(targetApp: targetApp)
  }

  private func completePaste(targetApp: NSRunningApplication?, plainText: Bool = false) -> PasteActionResult {
    let copied: PasteActionResult = plainText ? .copiedPlainText : .copied
    guard let targetApp, !targetApp.isTerminated else { return copied }
    guard accessibilityPermissionProvider() else {
      return plainText ? .copiedPlainTextNeedsPermission : .copiedNeedsPermission
    }
    guard targetActivator(targetApp) else { return copied }
    keyboardPasteScheduler { [weak self] in self?.pasteViaKeyboard() }
    return plainText ? .pastedPlainText : .pasted
  }

  func pastePlainText(_ item: Clip, targetApp: NSRunningApplication?) -> PasteActionResult {
    guard let text = plainText(for: item), writePlainTextToPasteboard(text) else {
      return .failed("Could not write plain text to clipboard.")
    }

    return completePaste(targetApp: targetApp, plainText: true)
  }

  func pastePlainText(_ value: String, targetApp: NSRunningApplication?) -> PasteActionResult {
    guard writePlainTextToPasteboard(value) else { return .failed("Could not write plain text to clipboard.") }

    return completePaste(targetApp: targetApp, plainText: true)
  }

  @discardableResult func copy(_ item: Clip) -> PasteActionResult {
    writeToPasteboard(item) ? .copied : .failed("Could not write item to clipboard.")
  }

  @discardableResult func copy(_ items: [Clip]) -> PasteActionResult {
    writeToPasteboard(items) ? .copied : .failed("Could not write items to clipboard.")
  }

  @discardableResult func copyPlainText(_ item: Clip) -> PasteActionResult {
    writePlainTextToPasteboard(item) ? .copiedPlainText : .failed("Could not write plain text to clipboard.")
  }

  @discardableResult func copyPlainText(_ value: String) -> PasteActionResult {
    writePlainTextToPasteboard(value) ? .copiedPlainText : .failed("Could not write plain text to clipboard.")
  }

  func pasteboardWriters(for item: Clip) -> [NSPasteboardWriting] {
    switch item.kind {
    case .image:
      guard let imagePath = item.imagePath, let image = cacheService.image(for: imagePath) else { return [] }
      return [image]

    case .pdf, .audio, .video:
      guard let data = cacheService.data(for: item.payload) else { return [] }
      let type: NSPasteboard.PasteboardType =
        item.kind == .pdf ? .pdf : item.kind == .audio ? .sound : VideoPayload.pasteboardType(forPath: item.payload)
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setData(data, forType: type)
      pasteboardItem.setString(dragLabel(for: item), forType: .string)
      return [pasteboardItem]

    case .color:
      guard let color = ColorPayload.color(from: item.payload) else { return [] }
      return [color]

    case .richText:
      if let data = cacheService.data(for: item.payload) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: .rtf)
        let text = richTextPlainString(from: data) ?? item.displayText.clipboardTrimmed
        if !text.isEmpty { pasteboardItem.setString(text, forType: .string) }
        return [pasteboardItem]
      }

      let fallbackText = richTextFallbackPlainString(for: item)
      return fallbackText.isEmpty ? [] : [stringPasteboardItem(fallbackText)]

    case .file:
      let urls = FilePayload.urls(from: item.payload)
      guard !urls.isEmpty, urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return [] }
      return urls.map { $0.standardizedFileURL as NSURL }

    case .url:
      guard !item.payload.isEmpty else { return [] }
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setString(item.payload, forType: .string)
      pasteboardItem.setString(item.payload, forType: .URL)
      if let title = urlTitleForPasteboard(item.displayText, payload: item.payload) {
        pasteboardItem.setString(title, forType: NSPasteboard.PasteboardType(rawValue: "public.url-name"))
      }
      return [pasteboardItem]

    case .text, .code, .unknown:
      guard !item.payload.isEmpty else { return [] }
      return [stringPasteboardItem(item.payload)]
    }
  }

  @discardableResult func writeToPasteboard(_ item: Clip) -> Bool {
    let writers = pasteboardWriters(for: item)
    guard !writers.isEmpty else { return false }
    let board = NSPasteboard.general
    board.clearContents()
    guard board.writeObjects(writers) else { return false }
    if item.kind == .color { board.setString(ColorPayload.displayHex(from: item.payload), forType: .string) }
    if item.kind == .file {
      board.setString(FilePayload.urls(from: item.payload).map(\.path).joined(separator: "\n"), forType: .string)
    }
    ClipboardWrites.mark(changeCount: board.changeCount)
    return true
  }

  @discardableResult func writeToPasteboard(_ items: [Clip]) -> Bool {
    guard !items.isEmpty else { return false }
    var writers: [NSPasteboardWriting] = []
    for item in items {
      let itemWriters = pasteboardWriters(for: item)
      guard !itemWriters.isEmpty else { return false }
      writers.append(contentsOf: itemWriters)
    }
    guard !writers.isEmpty else { return false }

    let board = NSPasteboard.general
    board.clearContents()
    let didWrite = board.writeObjects(writers)
    if didWrite { ClipboardWrites.mark(changeCount: board.changeCount) }
    return didWrite
  }

  func plainText(for item: Clip) -> String? {
    switch item.kind {
    case .text, .code, .unknown: return nonEmptyPlainText(item.payload) ?? nonEmptyPlainText(item.displayText)
    case .url, .file: return nonEmptyPlainText(item.payload) ?? nonEmptyPlainText(item.displayText)
    case .richText:
      if let data = cacheService.data(for: item.payload), let text = richTextPlainString(from: data) { return text }
      return nonEmptyPlainText(richTextFallbackPlainString(for: item))
    case .image: return nonEmptyPlainText(item.ocrText) ?? nonEmptyPlainText(item.displayText)
    case .pdf, .audio, .video: return nonEmptyPlainText(item.displayText)
    case .color:
      return nonEmptyPlainText(ColorPayload.displayHex(from: item.payload)) ?? nonEmptyPlainText(item.displayText)
    }
  }

  @discardableResult func writePlainTextToPasteboard(_ item: Clip) -> Bool {
    guard let text = plainText(for: item) else { return false }
    return writePlainTextToPasteboard(text)
  }

  @discardableResult private func writePlainTextToPasteboard(_ text: String) -> Bool {
    guard !text.clipboardTrimmed.isEmpty else { return false }
    let board = NSPasteboard.general
    board.clearContents()
    let didWrite = board.setString(text, forType: .string)
    if didWrite { ClipboardWrites.mark(changeCount: board.changeCount) }
    return didWrite
  }

  private func stringPasteboardItem(_ value: String) -> NSPasteboardItem {
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(value, forType: .string)
    return pasteboardItem
  }

  private func dragLabel(for item: Clip) -> String {
    let display = item.displayText.clipboardTrimmed
    if !display.isEmpty { return display }
    return item.kind.displayName.capitalized
  }

  private func urlTitleForPasteboard(_ title: String?, payload: String) -> String? {
    guard let title else { return nil }
    let normalized = title.split { $0.isWhitespace }.joined(separator: " ").clipboardTrimmed
    guard !normalized.isEmpty, normalized != payload else { return nil }
    guard !normalized.contains("://") else { return nil }
    return normalized
  }

  private func nonEmptyPlainText(_ value: String?) -> String? {
    guard let value, !value.clipboardTrimmed.isEmpty else { return nil }
    return value
  }

  private func richTextPlainString(from data: Data) -> String? {
    guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil }
    let text = attributed.string.clipboardTrimmed
    return text.isEmpty ? nil : text
  }

  private func richTextFallbackPlainString(for item: Clip) -> String {
    let payload = item.payload.clipboardTrimmed
    if looksLikeRichTextCachePath(payload) { return item.displayText.clipboardTrimmed }
    if !payload.isEmpty { return payload }
    return item.displayText.clipboardTrimmed
  }

  private func looksLikeRichTextCachePath(_ payload: String) -> Bool {
    let url = URL(fileURLWithPath: payload)
    return payload.contains("/") && url.pathExtension.lowercased() == "rtf"
  }

  private static func activateForAutomaticPaste(_ targetApp: NSRunningApplication) -> Bool {
    if #available(macOS 14, *) {
      return targetApp.activate()
    } else {
      return targetApp.activate(options: [.activateIgnoringOtherApps])
    }
  }

  private func pasteViaKeyboard() {
    let keyCode: UInt16 = 9
    guard let srcDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
      let srcUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else { return }

    srcDown.flags = .maskCommand
    srcDown.post(tap: .cghidEventTap)
    srcUp.flags = .maskCommand
    srcUp.post(tap: .cghidEventTap)
  }
}

// MARK: - HistoryArchive

struct ArchiveSummary: Equatable {
  let itemCount: Int
  let sidecarCount: Int
  let skippedItemCount: Int
  let skippedSidecarCount: Int
}

struct ArchiveImport {
  let items: [Clip]
  let collections: [ArchivePinboard]
  let summary: ArchiveSummary
}

struct ArchivePinboard: Codable, Equatable {
  let name: String
  let colorHex: String?
}

enum ArchiveError: LocalizedError {
  case unsupportedVersion(Int)
  case invalidArchive

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version): return "This Goldfish archive uses unsupported format version \(version)."
    case .invalidArchive: return "The selected file is not a valid Goldfish archive."
    }
  }
}

final class HistoryArchive {
  static let fileExtension = "clipboredarchive"
  private static let currentFormatVersion = 1
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) { self.fileManager = fileManager }

  func exportArchive(items: [Clip], to url: URL, cacheService: MediaCache, collections: [ArchivePinboard] = []) throws
    -> ArchiveSummary
  {
    var sidecarCount = 0
    let archivedItems = items.map { item -> ArchiveItem in
      let sidecars = archivedSidecars(for: item, cacheService: cacheService)
      sidecarCount += sidecars.count
      return ArchiveItem(item: item, sidecars: sidecars)
    }

    let archive = ArchivePayload(
      formatVersion: Self.currentFormatVersion, createdBy: Configuration.appName, exportedAt: Date(),
      collections: collections, items: archivedItems)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(archive)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

    return ArchiveSummary(
      itemCount: items.count, sidecarCount: sidecarCount, skippedItemCount: 0, skippedSidecarCount: 0)
  }

  func importArchive(from url: URL, cacheService: MediaCache) throws -> ArchiveImport {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let archive: ArchivePayload
    do { archive = try decoder.decode(ArchivePayload.self, from: data) } catch { throw ArchiveError.invalidArchive }
    guard archive.formatVersion <= Self.currentFormatVersion else {
      throw ArchiveError.unsupportedVersion(archive.formatVersion)
    }

    var importedItems: [Clip] = []
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
        let path: String?
        switch sidecar.role {
        case .image:
          path = cacheService.cacheImageSidecarData(sidecar.data, id: item.id)
          if let path {
            item.imagePath = path
            if item.kind == .image { item.payload = path }
          }

        case .thumbnail:
          path = cacheService.cacheImageSidecarData(sidecar.data, id: item.id, fileNamePrefix: "thumb")
          if let path { item.thumbnailPath = path }

        case .attachment:
          path = cacheService.cacheAttachmentData(sidecar.data, id: item.id, fileExtension: sidecar.fileExtension)
          if let path, item.kind.usesManagedPayloadAttachment { item.payload = path }
        }
        if path != nil { sidecarCount += 1 } else { skippedSidecarCount += 1 }
      }

      importedItems.append(item)
    }

    let summary = ArchiveSummary(
      itemCount: importedItems.count, sidecarCount: sidecarCount, skippedItemCount: skippedItemCount,
      skippedSidecarCount: skippedSidecarCount)
    return ArchiveImport(items: importedItems, collections: archive.collections ?? [], summary: summary)
  }

  private func archivedSidecars(for item: Clip, cacheService: MediaCache) -> [ArchiveSidecar] {
    var sidecars: [ArchiveSidecar] = []
    var archivedPaths = Set<String>()

    func append(_ role: ArchiveSidecarRole, path: String?, fallbackExtension: String) {
      guard let path, !path.clipboardTrimmed.isEmpty, !archivedPaths.contains(path) else { return }
      guard let data = cacheService.data(for: path) else { return }
      archivedPaths.insert(path)
      sidecars.append(
        ArchiveSidecar(role: role, fileExtension: fileExtension(for: path, fallback: fallbackExtension), data: data))
    }

    switch item.kind {
    case .image:
      append(.image, path: item.imagePath ?? item.payload, fallbackExtension: "png")
      append(.thumbnail, path: item.thumbnailPath, fallbackExtension: "png")

    case .url: append(.thumbnail, path: item.thumbnailPath, fallbackExtension: "png")

    default:
      if let fileExtension = item.mediaFileExtension {
        append(.attachment, path: item.payload, fallbackExtension: fileExtension)
      }
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
  let collections: [ArchivePinboard]?
  let items: [ArchiveItem]

  init(formatVersion: Int, createdBy: String, exportedAt: Date, collections: [ArchivePinboard], items: [ArchiveItem]) {
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

  init(item: Clip, sidecars: [ArchiveSidecar]) {
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

  func clipboardItem() -> Clip? {
    guard let kind = ClipKind(rawValue: kind) else { return nil }
    return Clip(
      id: id, kind: kind, displayText: displayText, payload: payload, payloadHash: payloadHash, createdAt: createdAt,
      lastUsedAt: lastUsedAt, useCount: useCount, sourceApp: sourceApp, imagePath: imagePath,
      thumbnailPath: thumbnailPath, isPinned: isPinned, sourceAppBundleId: sourceAppBundleId, ocrText: ocrText,
      collectionName: collectionName, customTitle: customTitle, sourceDeviceName: sourceDeviceName)
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

// MARK: - ArchiveSync

struct ArchiveSyncStatus: Equatable {
  let isAvailable: Bool
  let archiveURL: URL?
  let lastModifiedAt: Date?
  let message: String
}

protocol ArchiveSyncing {
  func syncArchiveURL() throws -> URL
  func status() -> ArchiveSyncStatus
  @discardableResult func push(store: HistoryStore) throws -> ArchiveSummary
  @discardableResult func pull(store: HistoryStore) throws -> ArchiveSummary
}

enum ArchiveSyncError: LocalizedError, Equatable {
  case unavailable
  case noRemoteArchive(URL)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return
        "iCloud Sync is unavailable. Sign Goldfish with an iCloud container entitlement and make sure iCloud Drive is enabled."
    case .noRemoteArchive: return "No Goldfish iCloud archive has been created yet."
    }
  }
}

final class ArchiveSync: ArchiveSyncing {
  static let archiveFileName = "\(Configuration.storageName).\(HistoryArchive.fileExtension)"
  private let fileManager: FileManager
  private let containerProvider: () -> URL?

  init(
    fileManager: FileManager = .default,
    containerProvider: @escaping () -> URL? = { FileManager.default.url(forUbiquityContainerIdentifier: nil) }
  ) {
    self.fileManager = fileManager
    self.containerProvider = containerProvider
  }

  func syncArchiveURL() throws -> URL {
    guard let containerURL = containerProvider() else { throw ArchiveSyncError.unavailable }

    let directory = containerURL.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(
      Configuration.storageName, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    return directory.appendingPathComponent(Self.archiveFileName)
  }

  func status() -> ArchiveSyncStatus {
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
      return ArchiveSyncStatus(isAvailable: true, archiveURL: url, lastModifiedAt: lastModifiedAt, message: message)
    } catch {
      return ArchiveSyncStatus(
        isAvailable: false, archiveURL: nil, lastModifiedAt: nil, message: error.localizedDescription)
    }
  }

  @discardableResult func push(store: HistoryStore) throws -> ArchiveSummary {
    let url = try syncArchiveURL()
    return try store.exportArchive(to: url)
  }

  @discardableResult func pull(store: HistoryStore) throws -> ArchiveSummary {
    let url = try syncArchiveURL()
    guard fileManager.fileExists(atPath: url.path) else { throw ArchiveSyncError.noRemoteArchive(url) }

    startDownloadingIfNeeded(url)
    return try store.importArchive(from: url)
  }

  private func startDownloadingIfNeeded(_ url: URL) {
    let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
    guard values?.isUbiquitousItem == true else { return }
    try? fileManager.startDownloadingUbiquitousItem(at: url)
  }
}
