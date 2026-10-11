import AppKit
import Foundation
import Vision

private struct CaptureSource {
  let name: String?
  let bundleId: String?
  var description: String { name ?? bundleId ?? "ignored app" }
}

// MARK: - CaptureMonitor

final class CaptureMonitor {
  let store: HistoryStore
  let cacheService: MediaCache
  let settings: Preferences
  let imageTextExtractor: (NSImage) -> String?
  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "clipboard.monitor", qos: .utility)
  private let queueKey = DispatchSpecificKey<Void>()
  private var lastChangeCount: Int
  private var lastActiveChange = Date.distantPast
  private var scheduledInterval: TimeInterval = 0
  var didReportReadFailure = false
  private(set) var isPaused = false
  var onCapturedItem: (Clip) -> Void = { _ in }

  init(
    store: HistoryStore, cacheService: MediaCache, settings: Preferences,
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

  func pollNow() { queue.async { [weak self] in self?.pollPasteboard(rescheduleAfterCapture: false) } }

  func pollNowAndWait() {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      pollPasteboard(rescheduleAfterCapture: false)
    } else {
      queue.sync { pollPasteboard(rescheduleAfterCapture: false) }
    }
  }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    reportCaptureStatus(paused ? "Capture is paused." : "Capture resumed. Waiting for clipboard changes.")
    scheduleTimer(interval: paused ? 1.0 : effectiveProfile.idleInterval)
    lastActiveChange = .distantPast
  }

  func stop() {
    timer?.cancel()
    timer = nil
    scheduledInterval = 0
  }

  #if DEBUG

    var scheduledIntervalForTesting: TimeInterval { scheduledInterval }
  #endif

  private var effectiveProfile: Configuration.PollProfile { settings.pollProfile }

  private func scheduleTimer(interval: TimeInterval) {
    let effective = clampedInterval(interval)
    if timer != nil && scheduledInterval == effective { return }

    timer?.cancel()
    let newTimer = DispatchSource.makeTimerSource(queue: queue)
    timer = nil
    scheduledInterval = 0
    newTimer.schedule(deadline: .now() + effective, repeating: effective, leeway: .milliseconds(12))
    newTimer.setEventHandler { [weak self] in self?.tick() }
    newTimer.resume()
    timer = newTimer
    scheduledInterval = effective
  }

  private func tick() { pollPasteboard(rescheduleAfterCapture: true) }

  private func pollPasteboard(rescheduleAfterCapture: Bool) {
    if isPaused {
      reportCaptureStatus("Capture is paused.")
      return
    }

    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount

    if changeCount == lastChangeCount {
      if Date().timeIntervalSince(lastActiveChange) > effectiveProfile.idleRecoveryWindow {
        if rescheduleAfterCapture { scheduleTimer(interval: effectiveProfile.idleInterval) }
      }
      return
    }

    lastChangeCount = changeCount
    lastActiveChange = Date()

    if ClipboardWrites.consume(changeCount: changeCount) {
      reportReadFailureStatus("Clipboard was updated by Goldfish; skipping capture.")
      return
    }

    didReportReadFailure = false
    if let item = readCurrentItem(from: pasteboard) {
      reportCaptured(item)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        let storedItem = self.store.upsert(item)
        self.onCapturedItem(storedItem)
      }
    } else if !didReportReadFailure {
      reportCaptureStatus("Clipboard changed, but Goldfish could not read a supported item.")
    }

    if rescheduleAfterCapture { scheduleTimer(interval: effectiveProfile.activeInterval) }
  }

  func clampedInterval(_ interval: TimeInterval) -> TimeInterval {
    max(interval, Configuration.minResponsiveActiveInterval)
  }

  private func readCurrentItem(from pasteboard: NSPasteboard) -> Clip? {
    let source = frontmostApp()

    func isIgnored(_ kind: ClipKind) -> Bool { return settings.ignoredItemKindsRaw.contains(kind.rawValue) }

    func ignoredKindMessage(_ kind: ClipKind) -> String {
      return "\(kind.statusName) items are ignored in capture settings."
    }

    if isSourceIgnored(source) {
      reportReadFailureStatus("Ignored clipboard change from \(source.description).")
      return nil
    }

    if isIgnored(.file), hasFileItems(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.file))
      return nil
    }

    if let filePayload = itemFromFiles(pasteboard, source: source) { return filePayload }

    let url = urlPayloadFromPasteboard(pasteboard)

    if isIgnored(.url), url != nil {
      reportReadFailureStatus(ignoredKindMessage(.url))
      return nil
    }

    if let url, settings.excludeSensitive,
      SensitiveContentDetector.isLikelySensitive(
        url.url.absoluteString, sourceBundleId: source.bundleId, sourceApp: source.name)
    {
      reportReadFailureStatus("Copy was ignored because it looks sensitive.")
      return nil
    }

    if let url, hasImage(on: pasteboard) {
      return itemFromURL(url.url, title: url.title, source: source, previewPasteboard: pasteboard)
    }

    let formats: [(ClipKind, (NSPasteboard) -> Bool, (NSPasteboard, CaptureSource) -> Clip?)] = [
      (.color, hasColor, itemFromColor), (.image, hasImage, itemFromImage), (.pdf, hasPDF, itemFromPDF),
      (.video, hasVideo, itemFromVideo), (.audio, hasAudio, itemFromAudio),
      (.richText, hasRichText, { self.itemFromRichText($0, source: $1) }),
    ]
    let readers = formats.map { kind, present, read in (kind, { present(pasteboard) }, { read(pasteboard, source) }) }
    switch readInPriorityOrder(readers) {
    case .captured(let item): return item
    case .ignored(let kind):
      reportReadFailureStatus(ignoredKindMessage(kind))
      return nil
    case .unsupported: break
    }

    if let url {
      let item = itemFromURL(url.url, title: url.title, source: source)
      return item
    }

    if isIgnored(.richText), hasHTMLRichText(on: pasteboard) {
      reportReadFailureStatus(ignoredKindMessage(.richText))
      return nil
    }

    if let htmlPayload = itemFromRichText(pasteboard, source: source, isHTML: true) { return htmlPayload }

    if let string = pasteboard.string(forType: .string) {
      let trimmed = string.clipboardTrimmed
      if !trimmed.isEmpty {
        if CodeSnippetPayload.isLikelyCode(trimmed), isIgnored(.code) {
          reportReadFailureStatus(ignoredKindMessage(.code))
          return nil
        }
        if !CodeSnippetPayload.isLikelyCode(trimmed), isIgnored(.text) {
          reportReadFailureStatus(ignoredKindMessage(.text))
          return nil
        }
      }
    }

    if let string = pasteboard.string(forType: .string), let item = itemFromString(string, source: source) {
      if item.kind == .text || item.kind == .code, item.payload.isEmpty {
        reportReadFailureStatus("Clipboard contains no readable text.")
        return nil
      }
      return item
    }

    reportReadFailureStatus("Clipboard changed, but Goldfish could not read a supported item.")
    return nil
  }

  enum FormatRead {
    case captured(Clip)
    case ignored(ClipKind)
    case unsupported
  }

  func readInPriorityOrder(_ readers: [(ClipKind, () -> Bool, () -> Clip?)]) -> FormatRead {
    for (kind, present, read) in readers {
      if settings.ignoredItemKindsRaw.contains(kind.rawValue), present() { return .ignored(kind) }
      if let item = read() { return .captured(item) }
    }
    return .unsupported
  }

  private func hasImage(on pasteboard: NSPasteboard) -> Bool {
    pasteboard.data(forType: .tiff) != nil || pasteboard.data(forType: .png) != nil
  }

  private func hasPDF(on pasteboard: NSPasteboard) -> Bool { pasteboard.data(forType: .pdf) != nil }

  private func hasAudio(on pasteboard: NSPasteboard) -> Bool { pasteboard.data(forType: .sound) != nil }

  private func hasVideo(on pasteboard: NSPasteboard) -> Bool { VideoPayload.data(from: pasteboard) != nil }

  private func hasColor(on pasteboard: NSPasteboard) -> Bool { NSColor(from: pasteboard) != nil }

  private func hasFileItems(on pasteboard: NSPasteboard) -> Bool {
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
      return false
    }
    return urls.contains(where: \.isFileURL)
  }

  private func hasRichText(on pasteboard: NSPasteboard) -> Bool { pasteboard.data(forType: .rtf) != nil }

  private func hasHTMLRichText(on pasteboard: NSPasteboard) -> Bool { htmlData(from: pasteboard) != nil }
}

// MARK: - CaptureMonitor — Status

extension CaptureMonitor {
  private func isSourceIgnored(_ source: CaptureSource) -> Bool {
    guard !settings.ignoredApps.isEmpty else { return false }
    let lowerName = source.name?.lowercased() ?? ""
    let lowerBundle = source.bundleId?.lowercased() ?? ""

    return settings.ignoredApps.contains { ignored in
      let candidate = ignored.clipboardTrimmed.lowercased()
      if candidate.isEmpty { return false }
      return !candidate.isEmpty && (lowerName.contains(candidate) || lowerBundle.contains(candidate))
    }
  }

  private func frontmostApp() -> CaptureSource {
    let app = NSWorkspace.shared.frontmostApplication
    return CaptureSource(name: app?.localizedName, bundleId: app?.bundleIdentifier)
  }

  func reportCaptured(_ item: Clip) {
    let source = item.sourceApp ?? "unknown app"
    reportCaptureStatus("Captured \(item.kind.displayName) from \(source).")
  }

  func reportCaptureStatus(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.settings.setCaptureStatus(message: message) }
  }

  func reportReadFailureStatus(_ message: String) {
    didReportReadFailure = true
    reportCaptureStatus(captureFailureDisplayMessage(message))
  }

  private func captureFailureDisplayMessage(_ message: String) -> String {
    let trimmed = message.clipboardTrimmed
    guard !trimmed.isEmpty else { return "Skipped: Clipboard changed, but there was no readable content." }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("skipped:") || lower.hasPrefix("error:") { return trimmed }
    if lower.contains("failed") { return "Error: \(trimmed)" }
    return "Skipped: \(trimmed)"
  }

}

// MARK: - CaptureMonitor — Text

extension CaptureMonitor {
  private func itemFromString(_ value: String, source: CaptureSource) -> Clip? {
    let trimmed = value.clipboardTrimmed
    if trimmed.isEmpty {
      reportReadFailureStatus("Clipboard string is empty.")
      return nil
    }

    if settings.excludeSensitive,
      SensitiveContentDetector.isLikelySensitive(trimmed, sourceBundleId: source.bundleId, sourceApp: source.name)
    {
      reportReadFailureStatus("Copy was ignored because it looks sensitive.")
      return nil
    }

    if let url = detectURL(trimmed) { return capturedClip(.url, payload: url.absoluteString, source: source) }

    if CodeSnippetPayload.isLikelyCode(trimmed) {
      return capturedClip(.code, payload: trimmed, title: CodeSnippetPayload.title(from: trimmed), source: source)
    }

    return capturedClip(.text, payload: trimmed, source: source)
  }

  private func itemFromRichText(_ pasteboard: NSPasteboard, source: CaptureSource, isHTML: Bool = false) -> Clip? {
    let format = isHTML ? "HTML" : "RTF"
    let label = isHTML ? "HTML text" : "Rich text"
    guard let data = isHTML ? htmlData(from: pasteboard) : pasteboard.data(forType: .rtf) else {
      if !isHTML { reportReadFailureStatus("Clipboard pasteboard reported RTF but text could not be read.") }
      return nil
    }
    let attributed =
      isHTML ? attributedString(fromHTMLData: data) : NSAttributedString(rtf: data, documentAttributes: nil)
    guard let attributed else {
      reportReadFailureStatus("Clipboard pasteboard reported \(format) but text could not be read.")
      return nil
    }

    let text = attributed.string.clipboardTrimmed
    if text.isEmpty {
      reportReadFailureStatus("\(label) from pasteboard is empty.")
      return nil
    }

    if settings.excludeSensitive,
      SensitiveContentDetector.isLikelySensitive(text, sourceBundleId: source.bundleId, sourceApp: source.name)
    {
      reportReadFailureStatus("\(label) was ignored because it looks sensitive.")
      return nil
    }

    let rtfData =
      isHTML ? attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) : data
    guard let rtfData else {
      reportReadFailureStatus("Failed to convert HTML clipboard data for clipboard history.")
      return nil
    }

    let id = UUID()
    guard let path = cacheService.cacheRichText(rtfData, id: id) else {
      reportReadFailureStatus("Failed to cache \(isHTML ? "HTML text" : "rich text") for clipboard history.")
      return nil
    }

    return capturedClip(.richText, payload: path, title: text, hash: store.hashData(data), source: source, id: id)
  }

  func plainText(fromHTML html: String) -> String? {
    guard let data = html.data(using: .utf8) else { return nil }
    return attributedString(fromHTMLData: data)?.string
  }

  func htmlData(from pasteboard: NSPasteboard) -> Data? {
    if let data = pasteboard.data(forType: .html), !data.isEmpty { return data }
    if let html = pasteboard.string(forType: .html), let data = html.data(using: .utf8), !data.isEmpty { return data }
    return nil
  }

  private func attributedString(fromHTMLData data: Data) -> NSAttributedString? {
    try? NSAttributedString(
      data: data,
      options: [
        .documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue,
      ], documentAttributes: nil)
  }
}

// MARK: - CaptureMonitor — Links

extension CaptureMonitor {
  private func itemFromURL(_ url: URL, title: String?, source: CaptureSource, previewPasteboard: NSPasteboard? = nil)
    -> Clip
  {
    let displayText = urlDisplayText(url: url, title: title)
    let id = UUID()
    let previewPaths = previewPasteboard.flatMap { previewImagePaths(from: $0, id: id) }
    return capturedClip(
      .url, payload: url.absoluteString, title: displayText, source: source, id: id, images: previewPaths)
  }

  func detectURL(_ candidate: String) -> URL? {
    if let direct = URL(string: candidate), let scheme = direct.scheme, !scheme.isEmpty { return direct }

    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      let range = NSRange(location: 0, length: candidate.utf16.count)
      if let match = detector.firstMatch(in: candidate, options: [], range: range), match.resultType == .link,
        match.range.location == range.location, match.range.length == range.length, let value = match.url
      {
        return value
      }
    }

    if let comps = URLComponents(string: "https://" + candidate), let host = comps.host, host.contains(".") {
      return comps.url
    }

    return nil
  }

  struct PasteboardURLPayload {
    let url: URL
    let title: String?
  }

  func urlPayloadFromPasteboard(_ pasteboard: NSPasteboard) -> PasteboardURLPayload? {
    guard let url = pasteboard.string(forType: .URL) else { return nil }
    guard let detected = detectURL(url) else { return nil }
    return PasteboardURLPayload(url: detected, title: urlTitle(from: pasteboard, url: detected))
  }

  private func urlDisplayText(url: URL, title: String?) -> String {
    if let candidate = cleanURLTitle(title, url: url) { return candidate }
    return url.absoluteString
  }

  private func urlTitle(from pasteboard: NSPasteboard, url: URL) -> String? {
    let titleTypes = [
      NSPasteboard.PasteboardType(rawValue: "public.url-name"),
      NSPasteboard.PasteboardType(rawValue: "com.apple.pasteboard.promised-file-url-name"),
    ]
    for type in titleTypes { if let title = cleanURLTitle(pasteboard.string(forType: type), url: url) { return title } }

    if let html = pasteboard.string(forType: .html), let title = cleanURLTitle(plainText(fromHTML: html), url: url) {
      return title
    }

    if let data = pasteboard.data(forType: .html), let html = String(data: data, encoding: .utf8),
      let title = cleanURLTitle(plainText(fromHTML: html), url: url)
    {
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
}

// MARK: - CaptureMonitor — Media

extension CaptureMonitor {
  private func capturedClip(
    _ kind: ClipKind, payload: String, title: String? = nil, hash: String? = nil, source: CaptureSource,
    id: UUID = UUID(), images: (full: String, thumb: String)? = nil, ocr: String? = nil
  ) -> Clip {
    Clip(
      id: id, kind: kind, displayText: title ?? payload, payload: payload,
      payloadHash: hash ?? store.hashString(payload), sourceApp: source.name, imagePath: images?.full,
      thumbnailPath: images?.thumb, sourceAppBundleId: source.bundleId, ocrText: ocr)
  }

  func previewImagePaths(from pasteboard: NSPasteboard, id: UUID) -> (full: String, thumb: String)? {
    guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png), let image = NSImage(data: data)
    else { return nil }
    return cacheService.cacheImage(image, id: id)
  }

  private func itemFromImage(_ pasteboard: NSPasteboard, source: CaptureSource) -> Clip? {
    let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png)
    guard let data = imageData, let image = NSImage(data: data) else {
      if imageData != nil { reportReadFailureStatus("Clipboard image data is present but could not be decoded.") }
      return nil
    }

    let id = UUID()
    guard let cachePaths = cacheService.cacheImage(image, id: id) else {
      reportReadFailureStatus("Failed to cache image for clipboard history.")
      return nil
    }
    let recognizedText = recognizedTextIfEnabled(for: image)

    return capturedClip(
      .image, payload: cachePaths.full, title: "Image", hash: store.hashString(data.base64EncodedString()),
      source: source, id: id, images: cachePaths, ocr: recognizedText)
  }

  private func recognizedTextIfEnabled(for image: NSImage) -> String? {
    guard settings.includeImageTextInSearch, let text = imageTextExtractor(image)?.clipboardTrimmed, !text.isEmpty
    else { return nil }

    return ImageTextExtractor.normalizedRecognizedText(text)
  }

  private func itemFromPDF(_ pasteboard: NSPasteboard, source: CaptureSource) -> Clip? {
    guard let data = pasteboard.data(forType: .pdf) else { return nil }
    return attachmentItem(data, kind: .pdf, title: "PDF", extension: "pdf", source: source)
  }

  private func itemFromAudio(_ pasteboard: NSPasteboard, source: CaptureSource) -> Clip? {
    guard let data = pasteboard.data(forType: .sound) else { return nil }
    return attachmentItem(data, kind: .audio, title: "Audio", extension: "sound", source: source)
  }

  private func itemFromVideo(_ pasteboard: NSPasteboard, source: CaptureSource) -> Clip? {
    guard let video = VideoPayload.data(from: pasteboard) else { return nil }
    return attachmentItem(
      video.data, kind: .video, title: "Video", extension: VideoPayload.fileExtension(for: video.type), source: source)
  }

  private func attachmentItem(_ data: Data, kind: ClipKind, title: String, extension ext: String, source: CaptureSource)
    -> Clip?
  {
    let id = UUID()
    guard let path = cacheService.cacheAttachmentData(data, id: id, fileExtension: ext) else {
      reportReadFailureStatus("Failed to cache \(kind.displayName) for clipboard history.")
      return nil
    }
    let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    return capturedClip(
      kind, payload: path, title: "\(title) (\(size))", hash: store.hashString(data.base64EncodedString()),
      source: source, id: id)
  }

  private func itemFromColor(_ pasteboard: NSPasteboard, source: CaptureSource) -> Clip? {
    guard let color = NSColor(from: pasteboard) else { return nil }
    guard let hex = ColorPayload.hexString(from: color) else {
      reportReadFailureStatus("Clipboard color is present but could not be decoded.")
      return nil
    }

    return capturedClip(.color, payload: hex, source: source)
  }

  private func itemFromFiles(_ pasteboard: NSPasteboard, source: CaptureSource) -> Clip? {
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
      if let maybeURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !maybeURLs.isEmpty {
        reportReadFailureStatus("Clipboard file list could not be read.")
      }
      return nil
    }

    let fileURLs = urls.filter(\.isFileURL)
    guard !fileURLs.isEmpty else { return nil }
    let text = FilePayload.payload(from: fileURLs)
    let display = fileURLs.count == 1 ? text : "\(fileURLs.count) files"
    return capturedClip(.file, payload: text, title: display, source: source)
  }
}

// MARK: - SensitiveContentDetector

enum SensitiveContentDetector {
  enum Reason: String {
    case privateKey
    case bearerToken
    case githubToken
    case slackToken
    case awsAccessKey
    case stripeKey
    case openAIToken
    case googleAPIKey
    case jsonWebToken
    case creditCard
    case highEntropyToken
    case oneTimeCode
    case keyword
  }

  private static let tokenPatterns: [(Reason, NSRegularExpression)] = [
    (.bearerToken, regex(#"(?i)\bbearer\s+[A-Za-z0-9._+/=-]{20,}(?![A-Za-z0-9_])"#)),
    (.githubToken, regex(#"\bgh[porus]_[A-Za-z0-9_]{30,}(?![A-Za-z0-9_])"#)),
    (.slackToken, regex(#"\bxox[baprs]-[A-Za-z0-9-]{20,}(?![A-Za-z0-9_])"#)),
    (.awsAccessKey, regex(#"\bAKIA[A-Z0-9]{16}(?![A-Za-z0-9_])"#)),
    (.stripeKey, regex(#"\b[srp]k_(?:live|test)_[A-Za-z0-9]{16,}(?![A-Za-z0-9_])"#)),
    (.openAIToken, regex(#"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_])"#)),
    (.googleAPIKey, regex(#"\bAIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_])"#)),
    (.jsonWebToken, regex(#"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_])"#)),
  ]

  static func detect(_ text: String, sourceBundleId: String? = nil, sourceApp: String? = nil) -> Reason? {
    let value = text.clipboardTrimmed
    guard !value.isEmpty else { return nil }

    if value.contains("-----BEGIN "), value.contains("PRIVATE KEY-----") { return .privateKey }
    if let match = tokenPatterns.first(where: { matches($0.1, in: value) }) { return match.0 }
    if containsCreditCard(value) { return .creditCard }
    if looksLikeOneTimeCode(value, sourceBundleId: sourceBundleId, sourceApp: sourceApp) { return .oneTimeCode }
    if looksHighEntropy(value) { return .highEntropyToken }

    let lowered = value.lowercased()
    if lowered.contains("password") || lowered.contains("secret") || lowered.contains("api_key")
      || looksLikeSecretAssignment(lowered)
    {
      return .keyword
    }
    return nil
  }

  static func isLikelySensitive(_ text: String, sourceBundleId: String? = nil, sourceApp: String? = nil) -> Bool {
    detect(text, sourceBundleId: sourceBundleId, sourceApp: sourceApp) != nil
  }

  private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

  private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  private static func looksHighEntropy(_ text: String) -> Bool {
    guard (32...256).contains(text.count), !text.contains(where: \.isWhitespace) else { return false }

    var characterClasses = 0
    var hasSymbol = false
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 48...57: characterClasses |= 1
      case 65...90: characterClasses |= 2
      case 97...122: characterClasses |= 4
      case 43, 45, 46, 47, 61, 95: hasSymbol = true
      default: return false
      }
    }
    return characterClasses.nonzeroBitCount >= 2 && hasSymbol
  }

  private static func looksLikeOneTimeCode(_ text: String, sourceBundleId: String?, sourceApp: String?) -> Bool {
    guard (6...8).contains(text.count), text.allSatisfy(\.isNumber) else { return false }
    let source = "\(sourceBundleId ?? "") \(sourceApp ?? "")".lowercased()
    return ["auth", "1password", "bitwarden", "lastpass", "keeper", "dashlane"].contains(where: source.contains)
  }

  private static func containsCreditCard(_ text: String) -> Bool {
    var digits: [Int] = []
    func isCard(_ digits: [Int]) -> Bool {
      guard (13...19).contains(digits.count), let first = digits.first, digits.contains(where: { $0 != first }) else {
        return false
      }
      var sum = 0
      for (index, digit) in digits.reversed().enumerated() {
        let doubled = index.isMultiple(of: 2) ? digit : digit * 2
        sum += doubled > 9 ? doubled - 9 : doubled
      }
      return sum.isMultiple(of: 10)
    }

    for character in text {
      if let digit = character.wholeNumberValue {
        digits.append(digit)
      } else if character == " " || character == "-", !digits.isEmpty {
        continue
      } else {
        if isCard(digits) { return true }
        digits.removeAll(keepingCapacity: true)
      }
    }
    return isCard(digits)
  }

  private static func looksLikeSecretAssignment(_ text: String) -> Bool {
    let keys = [
      "api_key", "apikey", "access_token", "auth_token", "client_secret", "private_token", "refresh_token",
      "secret_key", "passwd",
    ]
    for key in keys {
      guard let range = text.range(of: key) else { continue }
      let suffix = text[range.upperBound...].drop(while: \.isWhitespace)
      guard suffix.first == "=" || suffix.first == ":" else { continue }
      let value = suffix.dropFirst().drop { $0.isWhitespace || $0 == "\"" || $0 == "'" }
      if value.prefix(while: { !$0.isWhitespace && $0 != "\"" && $0 != "'" && $0 != "," }).count >= 8 { return true }
    }
    return false
  }
}

// MARK: - ImageTextExtractor

enum ImageTextExtractor {
  static func recognizedText(in image: NSImage) -> String? {
    let boundedImage = image.resized(
      to: CGSize(width: Configuration.maxFullImagePixelSize, height: Configuration.maxFullImagePixelSize))
    guard let cgImage = boundedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.015

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do { try handler.perform([request]) } catch { return nil }

    let lines =
      request.results?.compactMap { observation in observation.topCandidates(1).first?.string.clipboardTrimmed } ?? []
    return normalizedRecognizedText(lines.joined(separator: " "))
  }

  static func normalizedRecognizedText(_ text: String?) -> String? {
    guard let text else { return nil }
    let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !normalized.isEmpty else { return nil }
    return String(normalized.prefix(Configuration.maxRecognizedImageTextLength))
  }

}

// MARK: - ClipboardWrites

enum ClipboardWrites {
  private static let queue = DispatchQueue(label: "clipboard.self-write-tracker")
  private static var changeCounts: [Int] = []

  static func mark(changeCount: Int) {
    queue.sync {
      changeCounts.append(changeCount)
      if changeCounts.count > 16 { changeCounts.removeFirst(changeCounts.count - 16) }
    }
  }

  static func consume(changeCount: Int) -> Bool {
    queue.sync {
      guard let index = changeCounts.firstIndex(of: changeCount) else { return false }
      changeCounts.remove(at: index)
      return true
    }
  }
}
