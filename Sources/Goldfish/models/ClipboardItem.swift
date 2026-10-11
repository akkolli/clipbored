import Foundation

enum ClipboardItemKind: Int {
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

  var displayName: String {
    switch self {
    case .text: return "text"
    case .url: return "link"
    case .image: return "image"
    case .richText: return "rich text"
    case .file: return "file"
    case .unknown: return "item"
    case .pdf: return "PDF"
    case .audio: return "audio"
    case .color: return "color"
    case .code: return "code"
    case .video: return "video"
    }
  }
}

extension ClipboardItemKind {
  var canOpen: Bool {
    switch self {
    case .url, .file, .image, .pdf, .audio, .video: return true
    case .text, .richText, .unknown, .color, .code: return false
    }
  }

  var canReveal: Bool {
    switch self {
    case .file, .image, .pdf, .audio, .video: return true
    case .text, .richText, .unknown, .url, .color, .code: return false
    }
  }

  var hasManagedCacheReference: Bool {
    switch self {
    case .url, .image, .pdf, .audio, .richText, .video: return true
    case .text, .file, .unknown, .color, .code: return false
    }
  }
}

enum ClipboardSortMode: Int {
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

  static let allCases: [ClipboardSortMode] = [
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

  func includes(_ item: ClipboardItem) -> Bool {
    switch self {
    case .mostRecent, .mostUsed: return true
    case .images: return item.presentationKind == .image
    case .links: return item.presentationKind == .url
    case .text: return item.presentationKind == .text || item.presentationKind == .richText || item.presentationKind == .code
    case .pinned: return item.isPinned
    case .files: return item.presentationKind == .file || item.presentationKind == .pdf
    case .audio: return item.presentationKind == .audio
    case .colors: return item.presentationKind == .color
    case .code: return item.presentationKind == .code
    case .videos: return item.presentationKind == .video
    }
  }
}

enum ClipboardCollectionDefaults {
  static func normalizedName(_ value: String?) -> String? {
    guard let value else { return nil }
    let name = value.split { $0.isWhitespace }.joined(separator: " ").clipboardTrimmed
    guard !name.isEmpty else { return nil }
    return String(name.prefix(40))
  }
}

struct ClipboardItem: Equatable {
  var id: UUID
  var kind: ClipboardItemKind
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

  /// A URL copied as plain or rich text is still recognizable as a link. Preserve the
  /// original clipboard representation for paste and archive compatibility.
  var presentationKind: ClipboardItemKind { linkURL == nil ? kind : .url }

  var linkURL: URL? {
    guard [.url, .text, .richText, .unknown].contains(kind) else { return nil }
    let candidate = (kind == .richText ? displayText : payload).clipboardTrimmed
    guard !candidate.contains(where: { $0.isWhitespace }), let url = URL(string: candidate),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false
    else { return nil }
    return url
  }

  var linkAddress: String { linkURL?.absoluteString ?? payload }

  var searchableText: String {
    var text = kindLabel + " " + displayText.lowercased() + " " + payload.lowercased()
    if let customTitle { text += " " + customTitle.lowercased() }
    if let sourceApp { text += " " + sourceApp.lowercased() }
    if let sourceAppBundleId { text += " " + sourceAppBundleId.lowercased() }
    if let collectionName { text += " " + collectionName.lowercased() }
    if let sourceDeviceName { text += " " + sourceDeviceName.lowercased() }
    return text
  }

  var effectiveSourceDeviceName: String { ClipboardItem.normalizedDeviceName(sourceDeviceName) ?? Self.localDeviceName }

  private var kindLabel: String {
    switch kind {
    case .text: return "text"
    case .url: return "link url"
    case .image: return "image"
    case .richText: return "richtext rtf"
    case .file: return "file"
    case .unknown: return "unknown"
    case .pdf: return "pdf document"
    case .audio: return "audio sound"
    case .color: return "color swatch hex"
    case .code: return "code snippet source programming"
    case .video: return "video movie mp4 quicktime"
    }
  }

  init(
    id: UUID, kind: ClipboardItemKind, displayText: String, payload: String, payloadHash: String, createdAt: Date, lastUsedAt: Date,
    useCount: Int, sourceApp: String?, imagePath: String?, thumbnailPath: String?, isPinned: Bool = false, sourceAppBundleId: String? = nil,
    ocrText: String? = nil, collectionName: String? = nil, customTitle: String? = nil,
    sourceDeviceName: String? = ClipboardItem.localDeviceName
  ) {
    self.id = id
    self.kind = kind
    self.displayText = displayText
    self.payload = payload
    self.payloadHash = payloadHash
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
    self.useCount = min(Int(Int32.max), max(0, useCount))
    self.sourceApp = sourceApp
    self.imagePath = imagePath
    self.thumbnailPath = thumbnailPath
    self.isPinned = isPinned
    self.sourceAppBundleId = sourceAppBundleId
    self.ocrText = ocrText
    self.collectionName = collectionName
    self.customTitle = ClipboardItem.normalizedCustomTitle(customTitle)
    self.sourceDeviceName = ClipboardItem.normalizedDeviceName(sourceDeviceName)
  }

  static func normalizedCustomTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let title = value.split { $0.isWhitespace }.joined(separator: " ").clipboardTrimmed
    guard !title.isEmpty else { return nil }
    return String(title.prefix(80))
  }

  static var localDeviceName: String {
    normalizedDeviceName(Host.current().localizedName) ?? normalizedDeviceName(Host.current().name) ?? normalizedDeviceName(
      ProcessInfo.processInfo.hostName) ?? "This Mac"
  }

  static func normalizedDeviceName(_ value: String?) -> String? {
    guard let value else { return nil }
    let name = value.split { $0.isWhitespace }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    return String(name.prefix(60))
  }
}
