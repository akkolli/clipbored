import AppKit
import Foundation

// MARK: - Clip

enum ClipKind: Int {
  case text = 0
  case url
  case image
  case richText
  case file
  case unknown
  case pdf
  case audio
  case color
  case code
  case video

  // Each content kind defines its presentation and storage capabilities once.
  private var descriptor: (name: String, category: ShelfCategory, symbol: String, search: String, attachment: String?) {
    switch self {
    case .text: return ("text", .text, "text.alignleft", "text", nil)
    case .url: return ("link", .links, "link", "link url", nil)
    case .image: return ("image", .images, "photo", "image", "png")
    case .richText: return ("rich text", .text, "doc.richtext", "richtext rtf", "rtf")
    case .file: return ("file", .files, "doc", "file", nil)
    case .unknown: return ("item", .text, "doc.on.clipboard", "unknown", nil)
    case .pdf: return ("PDF", .files, "doc.fill", "pdf document", "pdf")
    case .audio: return ("audio", .audio, "music.note", "audio sound", "sound")
    case .color: return ("color", .colors, "paintpalette", "color swatch hex", nil)
    case .code:
      return ("code", .code, "chevron.left.forwardslash.chevron.right", "code snippet source programming", nil)
    case .video: return ("video", .videos, "film", "video movie mp4 quicktime", "mp4")
    }
  }
  static let captureKinds: [ClipKind] = [.text, .code, .url, .image, .color, .audio, .video, .richText, .pdf, .file]
  var displayName: String { descriptor.name }
  var category: ShelfCategory { descriptor.category }
  var symbol: String { descriptor.symbol }
  var searchLabel: String { descriptor.search }
  var attachmentExtension: String? { descriptor.attachment }
  var statusName: String { displayName == displayName.uppercased() ? displayName : displayName.capitalized }
  var canOpen: Bool { self == .url || canReveal }
  var canReveal: Bool { [.file, .image, .pdf, .audio, .video].contains(self) }
  var usesManagedPayloadAttachment: Bool { attachmentExtension != nil && self != .image }
  var hasManagedCacheReference: Bool { self == .url || self == .image || usesManagedPayloadAttachment }
}

enum ShelfCategory: Int, CaseIterable {
  case mostRecent = 0
  case mostUsed
  case images
  case links
  case text
  case pinned
  case files
  case audio
  case colors
  case code
  case videos

  static let allCases: [ShelfCategory] = [
    .mostRecent, .mostUsed, .text, .links, .images, .colors, .audio, .videos, .files, .pinned, .code,
  ]
  var title: String {
    switch self {
    case .mostRecent: return "Most Recent"
    case .mostUsed: return "Most Used"
    case .images: return "Images"
    case .links: return "Links"
    case .text: return "Text"
    case .pinned: return "Pinned"
    case .files: return "Files"
    case .audio: return "Audio"
    case .colors: return "Colors"
    case .code: return "Code"
    case .videos: return "Videos"
    }
  }

  func includes(_ item: Clip) -> Bool {
    switch self {
    case .mostRecent, .mostUsed: return true
    case .images: return item.kind == .image
    case .links: return item.kind == .url
    case .text: return item.kind == .text || item.kind == .richText || item.kind == .code
    case .pinned: return item.isPinned
    case .files: return item.kind == .file || item.kind == .pdf
    case .audio: return item.kind == .audio
    case .colors: return item.kind == .color
    case .code: return item.kind == .code
    case .videos: return item.kind == .video
    }
  }
}

enum Pinboards {
  static let names = ["Useful Links", "Important Notes", "Code Snippets", "Read Later"]

  static func normalizedName(_ value: String?) -> String? { value?.normalizedLabel(limit: 40) }

}

struct Clip: Equatable {
  var id: UUID
  var kind: ClipKind
  var displayText: String
  var payload: String
  var payloadHash: String
  var createdAt: Date
  var lastUsedAt: Date
  var useCount: Int
  var sourceApp: String?
  var imagePath: String?
  var thumbnailPath: String?
  var isPinned: Bool
  var sourceAppBundleId: String?
  var ocrText: String?
  var collectionName: String?
  var customTitle: String?
  var sourceDeviceName: String?
  var searchableText: String {
    [
      kind.searchLabel, displayText, payload, customTitle, sourceApp, sourceAppBundleId, collectionName,
      sourceDeviceName,
    ].compactMap { $0 }.joined(separator: " ").lowercased()
  }

  var effectiveSourceDeviceName: String { Clip.normalizedDeviceName(sourceDeviceName) ?? Self.localDeviceName }

  var mediaFileExtension: String? {
    kind == .video ? VideoPayload.fileExtension(from: payload) : kind.attachmentExtension
  }

  init(
    id: UUID = UUID(), kind: ClipKind, displayText: String, payload: String, payloadHash: String,
    createdAt: Date = Date(), lastUsedAt: Date = Date(), useCount: Int = 1, sourceApp: String? = nil,
    imagePath: String? = nil, thumbnailPath: String? = nil, isPinned: Bool = false, sourceAppBundleId: String? = nil,
    ocrText: String? = nil, collectionName: String? = nil, customTitle: String? = nil,
    sourceDeviceName: String? = Clip.localDeviceName
  ) {
    self.id = id
    self.kind = kind
    self.displayText = displayText
    self.payload = payload
    self.payloadHash = payloadHash
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
    self.useCount = useCount
    self.sourceApp = sourceApp
    self.imagePath = imagePath
    self.thumbnailPath = thumbnailPath
    self.isPinned = isPinned
    self.sourceAppBundleId = sourceAppBundleId
    self.ocrText = ocrText
    self.collectionName = collectionName
    self.customTitle = Clip.normalizedCustomTitle(customTitle)
    self.sourceDeviceName = Clip.normalizedDeviceName(sourceDeviceName)
  }

  static func normalizedCustomTitle(_ value: String?) -> String? { value?.normalizedLabel(limit: 80) }

  static var localDeviceName: String {
    normalizedDeviceName(Host.current().localizedName) ?? normalizedDeviceName(Host.current().name)
      ?? normalizedDeviceName(ProcessInfo.processInfo.hostName) ?? "This Mac"
  }

  static func normalizedDeviceName(_ value: String?) -> String? { value?.normalizedLabel(limit: 60) }

}

// MARK: - CodeSnippetPayload

enum CodeSnippetPayload {
  static func isLikelyCode(_ value: String) -> Bool {
    let text = value.clipboardTrimmed
    guard text.count >= 12 else { return false }
    if text.hasPrefix("```") { return true }
    if languageLabel(from: text) != "Code" { return true }

    let lines = text.components(separatedBy: .newlines)
    let nonEmptyLines = lines.map(\.clipboardTrimmed).filter { !$0.isEmpty }
    guard !nonEmptyLines.isEmpty else { return false }

    var score = 0
    if nonEmptyLines.count >= 2 && lines.contains(where: { $0.hasPrefix(" ") || $0.hasPrefix("\t") }) { score += 2 }
    if text.contains("{") && text.contains("}") { score += 2 }
    if text.contains(";") { score += 1 }
    if text.contains("=>") || text.contains("->") || text.contains("==") || text.contains("!=") || text.contains("&&")
      || text.contains("||")
    {
      score += 1
    }
    if nonEmptyLines.filter({ $0.hasSuffix("{") || $0.hasSuffix("}") || $0.hasSuffix(";") }).count >= 2 { score += 2 }
    if containsCodeKeyword(text) { score += 2 }
    if containsAssignment(text) { score += 1 }

    return score >= 4
  }

  static func languageLabel(from value: String) -> String {
    let text = value.clipboardTrimmed
    let lower = text.lowercased()
    if isJSON(text) { return "JSON" }
    if lower.contains("<html") || lower.contains("</") && lower.contains(">") { return "HTML" }
    if lower.contains("#include") { return "C/C++" }
    if lower.contains("func ") || lower.contains("let ") || lower.contains("var ") && lower.contains("->") {
      return "Swift"
    }
    if lower.contains("function ") || lower.contains("const ") || lower.contains("let ") && lower.contains("=>") {
      return "JavaScript"
    }
    if lower.contains("def ") || lower.contains("import ") && lower.contains(":") { return "Python" }
    if lower.range(
      of: #"\b(select|insert|update|delete|create)\b[\s\S]+\b(from|into|table|set)\b"#, options: .regularExpression)
      != nil
    {
      return "SQL"
    }
    if lower.range(
      of: #"^\s*(git|npm|yarn|pnpm|curl|ssh|docker|kubectl|brew|swift|python|node)\b"#, options: .regularExpression)
      != nil
    {
      return "Shell"
    }
    if lower.contains("{") && lower.contains(":") && lower.contains(";") { return "CSS" }
    return "Code"
  }

  static func title(from value: String) -> String {
    let language = languageLabel(from: value)
    guard language != "Code" else { return "Code Snippet" }
    return "\(language) Snippet"
  }

  static func previewText(from value: String, maxLines: Int = 4) -> String {
    let lines = value.components(separatedBy: .newlines).map { $0.clipboardTrimmed }.filter {
      !$0.isEmpty && $0 != "```"
    }
    let preview = lines.prefix(maxLines).joined(separator: " ")
    return preview.isEmpty ? "Code snippet" : String(preview.prefix(180))
  }

  static func previewLines(from value: String, maxLines: Int = 5) -> [String] {
    let lines = value.components(separatedBy: .newlines).map { line in line.replacingOccurrences(of: "\t", with: "  ") }
      .filter { !$0.clipboardTrimmed.isEmpty && $0.clipboardTrimmed != "```" }
    return Array(lines.prefix(maxLines))
  }

  private static func containsCodeKeyword(_ value: String) -> Bool {
    value.range(
      of:
        #"\b(import|func|function|class|struct|enum|interface|return|guard|if|else|for|while|switch|case|try|catch|throw|async|await|public|private|static|const|let|var|def)\b"#,
      options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func containsAssignment(_ value: String) -> Bool {
    value.range(of: #"\b[A-Za-z_][A-Za-z0-9_]*\s*(=|:=)\s*[^=\n]"#, options: .regularExpression) != nil
  }

  private static func isJSON(_ value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    let trimmed = value.clipboardTrimmed
    guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
    return (try? JSONSerialization.jsonObject(with: data)) != nil
  }
}

// MARK: - ColorPayload

enum ColorPayload {
  static func hexString(from color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else { return nil }
    let red = clampedByte(rgb.redComponent)
    let green = clampedByte(rgb.greenComponent)
    let blue = clampedByte(rgb.blueComponent)
    let alpha = clampedByte(rgb.alphaComponent)
    if alpha >= 255 { return String(format: "#%02X%02X%02X", red, green, blue) }
    return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
  }

  static func color(from payload: String) -> NSColor? {
    var value = payload.clipboardTrimmed
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6 || value.count == 8, let raw = UInt32(value, radix: 16) else { return nil }

    let hasAlpha = value.count == 8
    let red = CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let green = CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let blue = CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let alpha = hasAlpha ? CGFloat(raw & 0xFF) / 255 : 1
    return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
  }

  static func displayHex(from payload: String) -> String {
    if let color = color(from: payload), let hex = hexString(from: color) { return hex }
    let normalized = payload.clipboardTrimmed
    return normalized.hasPrefix("#") ? normalized.uppercased() : "#\(normalized.uppercased())"
  }

  static func componentSummary(from payload: String) -> String {
    guard let color = color(from: payload), let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB)
    else { return "Color" }
    let red = clampedByte(rgb.redComponent)
    let green = clampedByte(rgb.greenComponent)
    let blue = clampedByte(rgb.blueComponent)
    let alpha = clampedByte(rgb.alphaComponent)
    if alpha >= 255 { return "RGB \(red) \(green) \(blue)" }
    return "RGBA \(red) \(green) \(blue) \(alpha)"
  }

  static func previewText(from payload: String) -> String {
    "\(displayHex(from: payload))\n\(componentSummary(from: payload))"
  }

  private static func clampedByte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
}

// MARK: - FilePayload

enum FilePayload {
  static func paths(from payload: String) -> [String] {
    payload.split(separator: "\n", omittingEmptySubsequences: true).map { String($0).clipboardTrimmed }.filter {
      !$0.isEmpty
    }
  }

  static func urls(from payload: String) -> [URL] { paths(from: payload).map(fileURL(from:)) }

  static func payload(from urls: [URL]) -> String { urls.map(\.path).joined(separator: "\n") }

  static func fileURL(from value: String) -> URL {
    let trimmed = value.clipboardTrimmed
    if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed) { return url }
    return URL(fileURLWithPath: trimmed)
  }
}

// MARK: - LinkPreview

struct LinkPreview: Equatable {
  let url: URL
  let title: String
}

// MARK: - Preferences

enum HistoryRetention: Int, CaseIterable {
  case forever = 0
  case oneDay = 1
  case oneWeek = 7
  case oneMonth = 30
  case oneYear = 365

  static let allCases: [HistoryRetention] = [.oneDay, .oneWeek, .oneMonth, .oneYear, .forever]
  var title: String {
    switch self {
    case .oneDay: return "1 Day"
    case .oneWeek: return "1 Week"
    case .oneMonth: return "1 Month"
    case .oneYear: return "1 Year"
    case .forever: return "Forever"
    }
  }

  func cutoffDate(relativeTo now: Date = Date()) -> Date? {
    guard self != .forever else { return nil }
    return now.addingTimeInterval(-Double(rawValue) * 24 * 60 * 60)
  }
}

enum ClipboardPanelSide: Int, CaseIterable {
  case left = 0
  case right = 1

  var title: String {
    switch self {
    case .left: return "Left"
    case .right: return "Right"
    }
  }
}

final class Preferences {
  enum Change: String {
    case maxHistoryItems
    case historyRetention
    case defaultSortMode
    case imageCacheMaxBytes
    case includeImageTextInSearch
    case pruneDuplicates
    case openShortcut
    case settingsShortcut
    case launchAtLogin
    case showMenuBarIcon
    case showDockIcon
    case panelSide
    case cloudSync
    case pauseCapture
    case ignoredApps
    case ignoredItemKinds
    case keepFirstImage
    case excludeSensitive
    case hideFromScreenCapture
    case clearHistoryOnQuit
    case pollProfile
    case captureStatus
    case collections
    case status
    case other
  }

  enum Keys {
    static let maxHistoryItems = "maxHistoryItems"
    static let historyRetention = "historyRetentionDays"
    static let defaultSortMode = "defaultSortMode"
    static let imageCacheMaxBytes = "imageCacheMaxBytes"
    static let includeImageTextInSearch = "includeImageTextInSearch"
    static let pruneDuplicates = "pruneDuplicates"
    static let launchAtLogin = "launchAtLogin"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let panelSide = "panelSide"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let openShortcut = "openShortcut"
    static let settingsShortcut = "settingsShortcut"
    static let ignoredApps = "ignoredApps"
    static let ignoredItemKinds = "ignoredItemKinds"
    static let pollProfile = "pollProfile"
    static let keepFirstImage = "keepFirstImage"
    static let excludeSensitive = "excludeSensitive"
    static let pauseCapture = "pauseCapture"
    static let pauseCaptureUntil = "pauseCaptureUntil"
    static let hideFromScreenCapture = "hideFromScreenCapture"
    static let clearHistoryOnQuit = "clearHistoryOnQuit"
    static let onboardingCompleted = "onboardingCompleted"
    static let accessibilityNoticeShown = "accessibilityNoticeShown"
    static let customCollectionNames = "customCollectionNames"
    static let collectionColorHexes = "collectionColorHexes"
  }

  @Preference(
    .maxHistoryItems, Configuration.defaultHistoryLength, read: { ($0 as? Int).flatMap { $0 > 0 ? $0 : nil } },
    normalize: Preferences.clampedMaxHistoryItems) var maxHistoryItems: Int
  @Preference(.historyRetention, raw: .oneMonth) var historyRetention: HistoryRetention
  @Preference(.defaultSortMode, raw: .mostRecent) var defaultSortMode: ShelfCategory
  @Preference(
    .imageCacheMaxBytes, Configuration.defaultCacheMaxBytes, read: { ($0 as? Int64).flatMap { $0 > 0 ? $0 : nil } },
    normalize: Preferences.clampedImageCacheMaxBytes) var imageCacheMaxBytes: Int64
  @Preference(.includeImageTextInSearch, false) var includeImageTextInSearch: Bool
  @Preference(.pruneDuplicates, true) var pruneDuplicates: Bool
  @Preference(.launchAtLogin, false) var launchAtLogin: Bool
  @Preference(.showMenuBarIcon, true) var showMenuBarIcon: Bool
  @Preference(.showDockIcon, false) var showDockIcon: Bool
  @Preference(.panelSide, raw: .right) var panelSide: ClipboardPanelSide
  @Preference(.cloudSync, false) var iCloudSyncEnabled: Bool
  @Preference(.openShortcut, shortcut: Configuration.defaultOpenShortcut) var openShortcut: ShortcutBinding
  @Preference(.settingsShortcut, shortcut: Configuration.defaultSettingsShortcut) var settingsShortcut: ShortcutBinding
  @Preference(.ignoredApps, Configuration.defaultIgnoredApps) var ignoredApps: [String]
  @Preference(.ignoredItemKinds, [], normalize: Preferences.normalizedIgnoredItemKinds) var ignoredItemKindsRaw: [Int]
  @Preference(.pollProfile, raw: Configuration.defaultPollProfile) var pollProfileRaw: Configuration.PollProfile
  @Preference(.keepFirstImage, true) var keepFirstImage: Bool
  @Preference(.excludeSensitive, false) var excludeSensitive: Bool
  @Preference(.pauseCapture, false) var pauseCapture: Bool
  @Preference(
    .pauseCapture, nil, key: Keys.pauseCaptureUntil,
    read: { ($0 as? TimeInterval).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } },
    encode: { $0?.timeIntervalSince1970 }) var pauseCaptureUntil: Date?
  @Preference(.hideFromScreenCapture, false) var hideFromScreenCapture: Bool
  @Preference(.clearHistoryOnQuit, false) var clearHistoryOnQuit: Bool
  private(set) var customCollectionNames: [String]
  private(set) var collectionColorHexes: [String: String]
  private(set) var launchAtLoginErrorMessage: String = ""
  private(set) var accessibilityPermissionStatusMessage: String = ""
  private(set) var captureStatusMessage: String = ""
  private(set) var shortcutStatusMessage: String = ""
  private(set) var pasteStatusMessage: String = ""
  private(set) var cloudSyncStatusMessage: String = ""
  private(set) var onboardingCompleted: Bool
  private(set) var accessibilityNoticeShown: Bool
  private let defaults: UserDefaults
  private var observers: [(Change) -> Void] = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let existingProfile = [Keys.maxHistoryItems, Keys.historyRetention, Keys.openShortcut].contains {
      defaults.object(forKey: $0) != nil
    }
    customCollectionNames = Self.normalizedCollectionNames(
      defaults.stringArray(forKey: Keys.customCollectionNames) ?? [])
    collectionColorHexes = Self.normalizedCollectionColorHexes(defaults.dictionary(forKey: Keys.collectionColorHexes))
    onboardingCompleted = defaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? existingProfile
    accessibilityNoticeShown = defaults.object(forKey: Keys.accessibilityNoticeShown) as? Bool ?? false
    load(_maxHistoryItems)
    load(_historyRetention)
    load(_defaultSortMode)
    load(_imageCacheMaxBytes)
    load(_includeImageTextInSearch)
    load(_pruneDuplicates)
    load(_launchAtLogin)
    load(_showMenuBarIcon)
    load(_showDockIcon)
    load(_panelSide)
    load(_iCloudSyncEnabled)
    load(_openShortcut)
    load(_settingsShortcut)
    load(_ignoredApps)
    load(_ignoredItemKindsRaw)
    load(_pollProfileRaw)
    load(_keepFirstImage)
    load(_excludeSensitive)
    load(_pauseCapture)
    load(_pauseCaptureUntil)
    load(_hideFromScreenCapture)
    load(_clearHistoryOnQuit)
    store()
  }

  private func load<Value>(_ preference: Preference<Value>) {
    preference.load(defaults)
    preference.onChange = { [weak self] change in
      if change == .cloudSync { self?.cloudSyncStatusMessage = "" }
      self?.notify(change)
    }
  }

  private func store() {
    defaults.set(customCollectionNames, forKey: Keys.customCollectionNames)
    defaults.set(collectionColorHexes, forKey: Keys.collectionColorHexes)
    defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted)
  }

  func observe(_ observer: @escaping (Change) -> Void) { observers.append(observer) }

  private func storeAndNotify(_ change: Change) {
    store()
    notify(change)
  }

  private func notify(_ change: Change) { for observer in observers { observer(change) } }

  func setLaunchAtLoginStatus(message: String) { setStatus(\.launchAtLoginErrorMessage, message: message) }

  func setAccessibilityPermissionStatus(message: String) {
    setStatus(\.accessibilityPermissionStatusMessage, message: message)
  }

  func setCaptureStatus(message: String) { setStatus(\.captureStatusMessage, message: message, change: .captureStatus) }

  private func setStatus(
    _ field: ReferenceWritableKeyPath<Preferences, String>, message: String, change: Change = .status
  ) {
    guard self[keyPath: field] != message else { return }
    self[keyPath: field] = message
    notify(change)
  }

  func markAccessibilityNoticeShown() {
    guard !accessibilityNoticeShown else { return }
    accessibilityNoticeShown = true
    defaults.set(true, forKey: Keys.accessibilityNoticeShown)
  }

  func markOnboardingCompleted() {
    guard !onboardingCompleted else { return }
    onboardingCompleted = true
    defaults.set(true, forKey: Keys.onboardingCompleted)
    notify(.other)
  }

  func setShortcutStatus(message: String) { setStatus(\.shortcutStatusMessage, message: message) }

  func setPasteStatus(message: String) { setStatus(\.pasteStatusMessage, message: message) }

  func setCloudSyncStatus(message: String) { setStatus(\.cloudSyncStatusMessage, message: message) }

  @discardableResult func ensureCollection(named name: String, colorHex: String? = nil) -> String? {
    guard let normalizedName = Pinboards.normalizedName(name) else { return nil }
    let existingName = customCollectionNames.first { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }
    let canonicalName = existingName ?? normalizedName
    var changed = false

    if existingName == nil {
      customCollectionNames.append(normalizedName)
      changed = true
    }

    if let normalizedHex = Self.normalizedHexColor(colorHex), collectionColorHexes[canonicalName] != normalizedHex {
      for key in collectionColorHexes.keys
      where key.caseInsensitiveCompare(canonicalName) == .orderedSame && key != canonicalName {
        collectionColorHexes.removeValue(forKey: key)
      }
      collectionColorHexes[canonicalName] = normalizedHex
      changed = true
    }

    if changed { storeAndNotify(.collections) }
    return normalizedName
  }

  func collectionColorHex(forCollectionNamed name: String) -> String? {
    guard let normalizedName = Pinboards.normalizedName(name) else { return nil }
    if let exact = collectionColorHexes[normalizedName] { return exact }
    return collectionColorHexes.first { storedName, _ in
      storedName.caseInsensitiveCompare(normalizedName) == .orderedSame
    }?.value
  }

  @discardableResult func updateCollection(named currentName: String, to newName: String, colorHex: String? = nil)
    -> String?
  {
    guard let normalizedCurrentName = Pinboards.normalizedName(currentName),
      let normalizedNewName = Pinboards.normalizedName(newName)
    else { return nil }

    let oldIndex = customCollectionNames.firstIndex { $0.caseInsensitiveCompare(normalizedCurrentName) == .orderedSame }
    let oldCanonicalName = oldIndex.map { customCollectionNames[$0] } ?? normalizedCurrentName
    let targetIndex = customCollectionNames.firstIndex { $0.caseInsensitiveCompare(normalizedNewName) == .orderedSame }
    let targetCanonicalName: String
    if let targetIndex, targetIndex != oldIndex {
      targetCanonicalName = customCollectionNames[targetIndex]
    } else {
      targetCanonicalName = normalizedNewName
    }
    var changed = false

    if let oldIndex {
      if let targetIndex, targetIndex != oldIndex {
        customCollectionNames.remove(at: oldIndex)
        changed = true
      } else if customCollectionNames[oldIndex] != normalizedNewName {
        customCollectionNames[oldIndex] = normalizedNewName
        changed = true
      }
    } else if targetIndex == nil {
      customCollectionNames.append(normalizedNewName)
      changed = true
    }

    let existingColor = collectionColorHex(forCollectionNamed: oldCanonicalName)
    for key in collectionColorHexes.keys where key.caseInsensitiveCompare(oldCanonicalName) == .orderedSame {
      collectionColorHexes.removeValue(forKey: key)
      changed = true
    }
    let resolvedColor = Self.normalizedHexColor(colorHex) ?? existingColor
    if let resolvedColor, collectionColorHexes[targetCanonicalName] != resolvedColor {
      collectionColorHexes[targetCanonicalName] = resolvedColor
      changed = true
    }

    if changed { storeAndNotify(.collections) }
    return targetCanonicalName
  }

  @discardableResult func deleteCollection(named name: String) -> String? {
    guard let normalizedName = Pinboards.normalizedName(name) else { return nil }
    var changed = false
    if let index = customCollectionNames.firstIndex(where: { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }
    ) {
      customCollectionNames.remove(at: index)
      changed = true
    }
    for key in collectionColorHexes.keys where key.caseInsensitiveCompare(normalizedName) == .orderedSame {
      collectionColorHexes.removeValue(forKey: key)
      changed = true
    }
    if changed { storeAndNotify(.collections) }
    return normalizedName
  }

  var pollProfile: Configuration.PollProfile {
    get { pollProfileRaw }
    set { pollProfileRaw = newValue }
  }

  func sanitizeLimits() {
    maxHistoryItems = Self.clampedMaxHistoryItems(maxHistoryItems)
    imageCacheMaxBytes = Self.clampedImageCacheMaxBytes(imageCacheMaxBytes)
  }

  private static func clampedMaxHistoryItems(_ count: Int) -> Int {
    max(Configuration.minHistoryLength, min(Configuration.maxHistoryLength, count))
  }

  private static func clampedImageCacheMaxBytes(_ bytes: Int64) -> Int64 {
    max(Configuration.minCacheMaxBytes, min(Configuration.maxCacheMaxBytes, bytes))
  }

  private static func normalizedCollectionNames(_ names: [String]) -> [String] {
    var normalized: [String] = []
    for name in names {
      guard let value = Pinboards.normalizedName(name) else { continue }
      guard !normalized.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { continue }
      normalized.append(value)
    }
    return normalized
  }

  private static let userVisibleItemKindRawValues = Set(ClipKind.captureKinds.map(\.rawValue))

  private static func normalizedIgnoredItemKinds(_ values: [Int]) -> [Int] {
    let ignoredVisibleKinds = Set(values).intersection(userVisibleItemKindRawValues)
    guard userVisibleItemKindRawValues.isSubset(of: ignoredVisibleKinds) else { return values }
    return values.filter { $0 != ClipKind.text.rawValue }
  }

  private static func normalizedCollectionColorHexes(_ rawValue: [String: Any]?) -> [String: String] {
    guard let rawValue else { return [:] }
    var normalized: [String: String] = [:]
    for (name, color) in rawValue {
      guard let normalizedName = Pinboards.normalizedName(name), let hex = normalizedHexColor(color as? String) else {
        continue
      }
      normalized[normalizedName] = hex
    }
    return normalized
  }

  private static func normalizedHexColor(_ value: String?) -> String? {
    guard let value else { return nil }
    var hex = value.clipboardTrimmed.uppercased()
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
    return "#\(hex)"
  }
}

// Each preference owns its normalization and serialization. A mutation writes
// only that key and emits one narrow change after the stored value is updated.
@propertyWrapper final class Preference<Value: Equatable> {
  private var value: Value
  private var defaults: UserDefaults?
  var onChange: ((Preferences.Change) -> Void)?
  let change: Preferences.Change
  let key: String
  let read: (Any?) -> Value?
  let encode: (Value) -> Any?
  let normalize: (Value) -> Value

  init(
    _ change: Preferences.Change, _ initial: Value, key: String? = nil,
    read: @escaping (Any?) -> Value? = { $0 as? Value }, encode: @escaping (Value) -> Any? = { $0 },
    normalize: @escaping (Value) -> Value = { $0 }
  ) {
    value = initial
    self.change = change
    self.key =
      key
      ?? (change == .cloudSync
        ? Preferences.Keys.iCloudSyncEnabled
        : change == .historyRetention ? Preferences.Keys.historyRetention : change.rawValue)
    self.read = read
    self.encode = encode
    self.normalize = normalize
  }

  convenience init(_ change: Preferences.Change, raw initial: Value)
  where Value: RawRepresentable, Value.RawValue == Int {
    self.init(change, initial, read: { ($0 as? Int).flatMap(Value.init(rawValue:)) }, encode: { $0.rawValue })
  }

  convenience init(_ change: Preferences.Change, shortcut initial: Value) where Value == ShortcutBinding {
    self.init(
      change, initial, read: { ($0 as? String).flatMap(ShortcutBinding.init(encoded:)) }, encode: { $0.encoded() })
  }

  func load(_ defaults: UserDefaults) {
    self.defaults = defaults
    value = normalize(read(defaults.object(forKey: key)) ?? value)
    defaults.set(encode(value), forKey: key)
  }

  var wrappedValue: Value {
    get { value }
    set {
      let normalized = normalize(newValue)
      guard value != normalized else { return }
      value = normalized
      defaults?.set(encode(normalized), forKey: key)
      onChange?(change)
    }
  }
}

// MARK: - VideoPayload

enum VideoPayload {
  private enum TypeIdentifier {
    static let mpeg4Movie = "public.mpeg-4"
    static let quickTimeMovie = "com.apple.quicktime-movie"
    static let movie = "public.movie"
    static let video = "public.video"
  }

  static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
    NSPasteboard.PasteboardType(rawValue: TypeIdentifier.mpeg4Movie),
    NSPasteboard.PasteboardType(rawValue: TypeIdentifier.quickTimeMovie),
    NSPasteboard.PasteboardType(rawValue: TypeIdentifier.movie),
    NSPasteboard.PasteboardType(rawValue: TypeIdentifier.video),
    NSPasteboard.PasteboardType(rawValue: "com.apple.m4v-video"),
  ]

  static func data(from pasteboard: NSPasteboard) -> (data: Data, type: NSPasteboard.PasteboardType)? {
    for type in pasteboardTypes { if let data = pasteboard.data(forType: type), !data.isEmpty { return (data, type) } }
    return nil
  }

  static func fileExtension(for type: NSPasteboard.PasteboardType) -> String {
    switch type.rawValue {
    case TypeIdentifier.mpeg4Movie: return "mp4"
    case TypeIdentifier.quickTimeMovie, TypeIdentifier.movie, TypeIdentifier.video: return "mov"
    case "com.apple.m4v-video": return "m4v"
    default: return "mov"
    }
  }

  static func pasteboardType(forPath path: String) -> NSPasteboard.PasteboardType {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "mp4": return NSPasteboard.PasteboardType(rawValue: TypeIdentifier.mpeg4Movie)
    case "m4v": return NSPasteboard.PasteboardType(rawValue: "com.apple.m4v-video")
    case "mov", "qt": return NSPasteboard.PasteboardType(rawValue: TypeIdentifier.quickTimeMovie)
    default: return NSPasteboard.PasteboardType(rawValue: TypeIdentifier.movie)
    }
  }

  static func fileExtension(from path: String) -> String {
    let value = URL(fileURLWithPath: path).pathExtension.clipboardTrimmed
    return value.isEmpty ? "mov" : value.lowercased()
  }

}
