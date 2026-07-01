import AppKit
import Foundation

final class ClipboardMonitorService {
  private let store: ClipboardStore
  private let cacheService: ClipboardCacheService
  private let settings: SettingsModel
  private let imageTextExtractor: (NSImage) -> String?

  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "clipboard.monitor", qos: .utility)
  private let queueKey = DispatchSpecificKey<Void>()
  private var lastChangeCount: Int
  private var lastActiveChange = Date.distantPast
  private var scheduledInterval: TimeInterval = 0
  private var didReportReadFailure = false
  private(set) var isPaused = false

  init(
    store: ClipboardStore,
    cacheService: ClipboardCacheService,
    settings: SettingsModel,
    imageTextExtractor: @escaping (NSImage) -> String? = ImageTextExtractor.recognizedText(in:)
  ) {
    self.store = store
    self.cacheService = cacheService
    self.settings = settings
    self.imageTextExtractor = imageTextExtractor
    self.lastChangeCount = NSPasteboard.general.changeCount
    queue.setSpecific(key: queueKey, value: ())
  }

  func start() {
    if isPaused {
      reportCaptureStatus("Capture is paused.")
      scheduleTimer(interval: 1.0)
      return
    }

    reportCaptureStatus("Capture is running. Waiting for clipboard changes.")
    scheduleTimer(interval: effectiveProfile.idleInterval)
    pollNow()
  }

  func pollNow() {
    queue.async { [weak self] in
      self?.pollPasteboard(rescheduleAfterCapture: false)
    }
  }

  func pollNowAndWait() {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      pollPasteboard(rescheduleAfterCapture: false)
    } else {
      queue.sync {
        pollPasteboard(rescheduleAfterCapture: false)
      }
    }
  }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    if paused {
      reportCaptureStatus("Capture is paused.")
      scheduleTimer(interval: 1.0)
      lastActiveChange = .distantPast
    } else {
      reportCaptureStatus("Capture resumed. Waiting for clipboard changes.")
      scheduleTimer(interval: effectiveProfile.idleInterval)
      lastActiveChange = .distantPast
    }
  }

  func stop() {
    timer?.cancel()
    timer = nil
    scheduledInterval = 0
  }

  #if DEBUG
  var scheduledIntervalForTesting: TimeInterval {
    scheduledInterval
  }
  #endif

  private var effectiveProfile: AppConfiguration.PollProfile {
    settings.pollProfile
  }

  private func scheduleTimer(interval: TimeInterval) {
    let effective = clampedInterval(interval)
    if timer != nil && scheduledInterval == effective {
      return
    }

    timer?.cancel()
    let newTimer = DispatchSource.makeTimerSource(queue: queue)
    timer = nil
    scheduledInterval = 0
    newTimer.schedule(deadline: .now() + effective, repeating: effective, leeway: .milliseconds(12))
    newTimer.setEventHandler { [weak self] in
      self?.tick()
    }
    newTimer.resume()
    timer = newTimer
    scheduledInterval = effective
  }

  private func tick() {
    DiagnosticsService.shared.incrementMonitorTick()
    pollPasteboard(rescheduleAfterCapture: true)
  }

  private func pollPasteboard(rescheduleAfterCapture: Bool) {
    if isPaused {
      reportCaptureStatus("Capture is paused.")
      return
    }

    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount

    if changeCount == lastChangeCount {
      if Date().timeIntervalSince(lastActiveChange) > effectiveProfile.idleRecoveryWindow {
        if rescheduleAfterCapture {
          scheduleTimer(interval: effectiveProfile.idleInterval)
        }
      }
      return
    }

    lastChangeCount = changeCount
    lastActiveChange = Date()

    if ClipboardSelfWriteTracker.consume(changeCount: changeCount) {
      reportReadFailureStatus("Clipboard was updated by ClipBored; skipping capture.")
      return
    }

    DiagnosticsService.shared.incrementPasteboardChange()

    didReportReadFailure = false
    if let item = readCurrentItem(from: pasteboard) {
      reportCaptured(item)
      DispatchQueue.main.async { [weak self] in
        self?.store.upsert(item)
      }
    } else if !didReportReadFailure {
      reportCaptureStatus("Clipboard changed, but ClipBored could not read a supported item.")
    }

    if rescheduleAfterCapture {
      scheduleTimer(interval: effectiveProfile.activeInterval)
    }
  }

  func clampedInterval(_ interval: TimeInterval) -> TimeInterval {
    max(interval, AppConfiguration.minResponsiveActiveInterval)
  }

  private func readCurrentItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
    DiagnosticsService.shared.incrementExtractionAttempt()
    let source = frontmostApp()

    func isIgnored(_ kind: ClipboardItemKind) -> Bool {
      return settings.ignoredItemKindsRaw.contains(kind.rawValue)
    }

    func ignoredKindMessage(_ kind: ClipboardItemKind) -> String {
      return "\(displayNameForStatus(kind)) items are ignored in capture settings."
    }

    if isSourceIgnored(source) {
      reportReadFailureStatus("Ignored clipboard change from \(sourceDescription(source)).")
      return nil
    }

    if isIgnored(.file), hasFileItems(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.file))
      return nil
    }

    if let filePayload = itemFromFiles(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return filePayload
    }

    let url = urlPayloadFromPasteboard(pasteboard)

    if isIgnored(.url), url != nil {
      reportReadFailureStatus(ignoredKindMessage(.url))
      return nil
    }

    if let url, hasImage(on: pasteboard) {
      return itemFromURL(url.url, title: url.title, sourceApp: source.name, sourceBundleId: source.bundleId, previewPasteboard: pasteboard)
    }

    if isIgnored(.color), hasColor(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.color))
      return nil
    }

    if let colorItem = itemFromColor(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return colorItem
    }

    if isIgnored(.image), hasImage(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.image))
      return nil
    }

    if let imageItem = itemFromImage(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return imageItem
    }

    if isIgnored(.pdf), hasPDF(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.pdf))
      return nil
    }

    if let pdfItem = itemFromPDF(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return pdfItem
    }

    if isIgnored(.audio), hasAudio(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.audio))
      return nil
    }

    if let audioItem = itemFromAudio(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return audioItem
    }

    if isIgnored(.richText), hasRichText(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.richText))
      return nil
    }

    if let rtfPayload = itemFromRichText(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return rtfPayload
    }

    if let url {
      let item = itemFromURL(url.url, title: url.title, sourceApp: source.name, sourceBundleId: source.bundleId)
      return item
    }

    if isIgnored(.richText), hasHTMLRichText(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.richText))
      return nil
    }

    if let htmlPayload = itemFromHTMLRichText(pasteboard, sourceApp: source.name, sourceBundleId: source.bundleId) {
      return htmlPayload
    }

    if isIgnored(.text), let string = pasteboard.string(forType: .string) {
      let trimmed = string.clipboardTrimmed
      if !trimmed.isEmpty {
        reportReadFailureStatus(ignoredKindMessage(.text))
        return nil
      }
    }

    if let string = pasteboard.string(forType: .string),
       let item = itemFromString(string, sourceApp: source.name, sourceBundleId: source.bundleId) {
      if item.kind == .text, item.payload.isEmpty {
        reportReadFailureStatus("Clipboard contains no readable text.")
        return nil
      }
      return item
    }

    reportReadFailureStatus("Clipboard changed, but ClipBored could not read a supported item.")
    return nil
  }

  private func itemFromString(_ value: String, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    let trimmed = value.clipboardTrimmed
    if trimmed.isEmpty {
      reportReadFailureStatus("Clipboard string is empty.")
      return nil
    }

    if settings.excludeSensitive, SensitiveContentDetector.isLikelySensitive(trimmed, sourceBundleId: sourceBundleId, sourceApp: sourceApp) {
      reportReadFailureStatus("Copy was ignored because it looks sensitive.")
      return nil
    }

    if let url = detectURL(trimmed) {
      return ClipboardItem(
        id: UUID(),
        kind: .url,
        displayText: url.absoluteString,
        payload: url.absoluteString,
        payloadHash: store.hashString(url.absoluteString),
        createdAt: Date(),
        lastUsedAt: Date(),
        useCount: 1,
        sourceApp: sourceApp,
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: false,
        sourceAppBundleId: sourceBundleId
      )
    }

    return ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: trimmed,
      payload: trimmed,
      payloadHash: store.hashString(trimmed),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func itemFromURL(
    _ url: URL,
    title: String?,
    sourceApp: String?,
    sourceBundleId: String?,
    previewPasteboard: NSPasteboard? = nil
  ) -> ClipboardItem {
    let displayText = urlDisplayText(url: url, title: title)
    let id = UUID()
    let previewPaths = previewPasteboard.flatMap { previewImagePaths(from: $0, id: id) }
    return ClipboardItem(
      id: id,
      kind: .url,
      displayText: displayText,
      payload: url.absoluteString,
      payloadHash: store.hashString(url.absoluteString),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: previewPaths?.full,
      thumbnailPath: previewPaths?.thumb,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func previewImagePaths(from pasteboard: NSPasteboard, id: UUID) -> (full: String, thumb: String)? {
    guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
          let image = NSImage(data: data) else {
      return nil
    }
    return cacheService.cacheImage(image, id: id)
  }

  private func itemFromImage(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png)
    guard let data = imageData, let image = NSImage(data: data) else {
      if imageData != nil {
        reportReadFailureStatus("Clipboard image data is present but could not be decoded.")
      }
      return nil
    }

    let id = UUID()
    guard let cachePaths = cacheService.cacheImage(image, id: id) else {
      reportReadFailureStatus("Failed to cache image for clipboard history.")
      return nil
    }
    let recognizedText = recognizedTextIfEnabled(for: image)

    return ClipboardItem(
      id: id,
      kind: .image,
      displayText: "Image",
      payload: cachePaths.full,
      payloadHash: store.hashString(data.base64EncodedString()),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: cachePaths.full,
      thumbnailPath: cachePaths.thumb,
      isPinned: false,
      sourceAppBundleId: sourceBundleId,
      ocrText: recognizedText
    )
  }

  private func recognizedTextIfEnabled(for image: NSImage) -> String? {
    guard settings.includeImageTextInSearch,
          let text = imageTextExtractor(image)?.clipboardTrimmed,
          !text.isEmpty else {
      return nil
    }

    let normalized = text
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    return String(normalized.prefix(AppConfiguration.maxRecognizedImageTextLength))
  }

  private func hasImage(on pasteboard: NSPasteboard) -> Bool {
    pasteboard.data(forType: .tiff) != nil || pasteboard.data(forType: .png) != nil
  }

  private func hasPDF(on pasteboard: NSPasteboard) -> Bool {
    pasteboard.data(forType: .pdf) != nil
  }

  private func hasAudio(on pasteboard: NSPasteboard) -> Bool {
    pasteboard.data(forType: .sound) != nil
  }

  private func hasColor(on pasteboard: NSPasteboard) -> Bool {
    NSColor(from: pasteboard) != nil
  }

  private func hasFileItems(on pasteboard: NSPasteboard) -> Bool {
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
      return false
    }
    return urls.contains(where: \.isFileURL)
  }

  private func hasRichText(on pasteboard: NSPasteboard) -> Bool {
    pasteboard.data(forType: .rtf) != nil
  }

  private func hasHTMLRichText(on pasteboard: NSPasteboard) -> Bool {
    htmlData(from: pasteboard) != nil
  }

  private func itemFromPDF(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    guard let data = pasteboard.data(forType: .pdf) else { return nil }
    let id = UUID()
    let hash = store.hashString(data.base64EncodedString())
    guard let path = cacheService.cachePDF(data, id: id) else {
      reportReadFailureStatus("Failed to cache PDF for clipboard history.")
      return nil
    }

    return ClipboardItem(
      id: id,
      kind: .pdf,
      displayText: "PDF (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))",
      payload: path,
      payloadHash: hash,
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func itemFromAudio(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    guard let data = pasteboard.data(forType: .sound) else { return nil }
    let id = UUID()
    let hash = store.hashString(data.base64EncodedString())
    guard let path = cacheService.cacheAudio(data, id: id) else {
      reportReadFailureStatus("Failed to cache audio for clipboard history.")
      return nil
    }

    return ClipboardItem(
      id: id,
      kind: .audio,
      displayText: "Audio (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))",
      payload: path,
      payloadHash: hash,
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func itemFromColor(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    guard let color = NSColor(from: pasteboard) else { return nil }
    guard let hex = ColorPayload.hexString(from: color) else {
      reportReadFailureStatus("Clipboard color is present but could not be decoded.")
      return nil
    }

    return ClipboardItem(
      id: UUID(),
      kind: .color,
      displayText: hex,
      payload: hex,
      payloadHash: store.hashString(hex),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func itemFromRichText(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    guard let data = pasteboard.data(forType: .rtf),
          let attributed = NSAttributedString(rtf: data, documentAttributes: nil)
    else {
      reportReadFailureStatus("Clipboard pasteboard reported RTF but text could not be read.")
      return nil
    }

    let text = attributed.string.clipboardTrimmed
    if text.isEmpty {
      reportReadFailureStatus("Rich text from pasteboard is empty.")
      return nil
    }

    if settings.excludeSensitive, SensitiveContentDetector.isLikelySensitive(text, sourceBundleId: sourceBundleId, sourceApp: sourceApp) {
      reportReadFailureStatus("Rich text was ignored because it looks sensitive.")
      return nil
    }

    let id = UUID()
    guard let path = cacheService.cacheRichText(data, id: id) else {
      reportReadFailureStatus("Failed to cache rich text for clipboard history.")
      return nil
    }

    return ClipboardItem(
      id: id,
      kind: .richText,
      displayText: text,
      payload: path,
      payloadHash: store.hashData(data),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func itemFromHTMLRichText(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    guard let htmlData = htmlData(from: pasteboard) else { return nil }
    guard let attributed = attributedString(fromHTMLData: htmlData) else {
      reportReadFailureStatus("Clipboard pasteboard reported HTML but text could not be read.")
      return nil
    }

    let text = attributed.string.clipboardTrimmed
    if text.isEmpty {
      reportReadFailureStatus("HTML text from pasteboard is empty.")
      return nil
    }

    if settings.excludeSensitive, SensitiveContentDetector.isLikelySensitive(text, sourceBundleId: sourceBundleId, sourceApp: sourceApp) {
      reportReadFailureStatus("HTML text was ignored because it looks sensitive.")
      return nil
    }

    guard let rtfData = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) else {
      reportReadFailureStatus("Failed to convert HTML clipboard data for clipboard history.")
      return nil
    }

    let id = UUID()
    guard let path = cacheService.cacheRichText(rtfData, id: id) else {
      reportReadFailureStatus("Failed to cache HTML text for clipboard history.")
      return nil
    }

    return ClipboardItem(
      id: id,
      kind: .richText,
      displayText: text,
      payload: path,
      payloadHash: store.hashData(htmlData),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func itemFromFiles(_ pasteboard: NSPasteboard, sourceApp: String?, sourceBundleId: String?) -> ClipboardItem? {
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
          !urls.isEmpty
    else {
      if let maybeURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
         !maybeURLs.isEmpty {
        reportReadFailureStatus("Clipboard file list could not be read.")
      }
      return nil
    }

    let fileURLs = urls.filter(\.isFileURL)
    guard !fileURLs.isEmpty else { return nil }
    let text = FilePayload.payload(from: fileURLs)
    let display = fileURLs.count == 1 ? text : "\(fileURLs.count) files"
    return ClipboardItem(
      id: UUID(),
      kind: .file,
      displayText: display,
      payload: text,
      payloadHash: store.hashString(text),
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 1,
      sourceApp: sourceApp,
      imagePath: nil,
      thumbnailPath: nil,
      isPinned: false,
      sourceAppBundleId: sourceBundleId
    )
  }

  private func detectURL(_ candidate: String) -> URL? {
    if let direct = URL(string: candidate), let scheme = direct.scheme, !scheme.isEmpty {
      return direct
    }

    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      let range = NSRange(location: 0, length: candidate.utf16.count)
      if let match = detector.firstMatch(in: candidate, options: [], range: range),
         match.resultType == .link,
         match.range.location == range.location,
         match.range.length == range.length,
         let value = match.url {
        return value
      }
    }

    if let comps = URLComponents(string: "https://" + candidate), let host = comps.host, host.contains(".") {
      return comps.url
    }

    return nil
  }

  private struct PasteboardURLPayload {
    let url: URL
    let title: String?
  }

  private func urlPayloadFromPasteboard(_ pasteboard: NSPasteboard) -> PasteboardURLPayload? {
    guard let url = pasteboard.string(forType: .URL) else {
      return nil
    }
    guard let detected = detectURL(url) else { return nil }
    return PasteboardURLPayload(url: detected, title: urlTitle(from: pasteboard, url: detected))
  }

  private func urlDisplayText(url: URL, title: String?) -> String {
    if let candidate = cleanURLTitle(title, url: url) {
      return candidate
    }
    return url.absoluteString
  }

  private func urlTitle(from pasteboard: NSPasteboard, url: URL) -> String? {
    let titleTypes = [
      NSPasteboard.PasteboardType(rawValue: "public.url-name"),
      NSPasteboard.PasteboardType(rawValue: "com.apple.pasteboard.promised-file-url-name")
    ]
    for type in titleTypes {
      if let title = cleanURLTitle(pasteboard.string(forType: type), url: url) {
        return title
      }
    }

    if let html = pasteboard.string(forType: .html),
       let title = cleanURLTitle(plainText(fromHTML: html), url: url) {
      return title
    }

    if let data = pasteboard.data(forType: .html),
       let html = String(data: data, encoding: .utf8),
       let title = cleanURLTitle(plainText(fromHTML: html), url: url) {
      return title
    }

    return nil
  }

  private func cleanURLTitle(_ value: String?, url: URL) -> String? {
    guard let value else { return nil }
    let normalized = value.split { $0.isWhitespace }.joined(separator: " ").clipboardTrimmed
    guard !normalized.isEmpty else { return nil }
    guard normalized != url.absoluteString else { return nil }
    guard detectURL(normalized) == nil else { return nil }
    return normalized
  }

  private func plainText(fromHTML html: String) -> String? {
    guard let data = html.data(using: .utf8) else { return nil }
    return attributedString(fromHTMLData: data)?.string
  }

  private func htmlData(from pasteboard: NSPasteboard) -> Data? {
    if let data = pasteboard.data(forType: .html), !data.isEmpty {
      return data
    }
    if let html = pasteboard.string(forType: .html),
       let data = html.data(using: .utf8),
       !data.isEmpty {
      return data
    }
    return nil
  }

  private func attributedString(fromHTMLData data: Data) -> NSAttributedString? {
    try? NSAttributedString(
      data: data,
      options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ],
      documentAttributes: nil
    )
  }

  private func isSourceIgnored(_ source: (name: String?, bundleId: String?)) -> Bool {
    guard !settings.ignoredApps.isEmpty else { return false }
    let lowerName = source.name?.lowercased() ?? ""
    let lowerBundle = source.bundleId?.lowercased() ?? ""

    return settings.ignoredApps.contains { ignored in
      let candidate = ignored.clipboardTrimmed.lowercased()
      if candidate.isEmpty { return false }
      return !candidate.isEmpty && (lowerName.contains(candidate) || lowerBundle.contains(candidate))
    }
  }

  private func frontmostApp() -> (name: String?, bundleId: String?) {
    guard let app = NSWorkspace.shared.frontmostApplication else {
      return (nil, nil)
    }
    return (app.localizedName, app.bundleIdentifier)
  }

  private func reportCaptured(_ item: ClipboardItem) {
    let source = item.sourceApp ?? "unknown app"
    reportCaptureStatus("Captured \(item.kind.displayName) from \(source).")
  }

  private func displayNameForStatus(_ kind: ClipboardItemKind) -> String {
    let name = kind.displayName
    if name == name.uppercased() {
      return name
    }
    return name.capitalized
  }

  private func reportCaptureStatus(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.settings.setCaptureStatus(message: message)
    }
  }

  private func reportReadFailureStatus(_ message: String) {
    didReportReadFailure = true
    reportCaptureStatus(captureFailureDisplayMessage(message))
  }

  private func captureFailureDisplayMessage(_ message: String) -> String {
    let trimmed = message.clipboardTrimmed
    guard !trimmed.isEmpty else { return "Skipped: Clipboard changed, but there was no readable content." }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("skipped:") || lower.hasPrefix("error:") {
      return trimmed
    }
    if lower.contains("failed") {
      return "Error: \(trimmed)"
    }
    return "Skipped: \(trimmed)"
  }

  private func sourceDescription(_ source: (name: String?, bundleId: String?)) -> String {
    source.name ?? source.bundleId ?? "ignored app"
  }
}
