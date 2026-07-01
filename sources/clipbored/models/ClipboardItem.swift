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
    }
  }
}

extension ClipboardItemKind {
  var canOpen: Bool {
    switch self {
    case .url, .file, .image, .pdf, .audio:
      return true
    case .text, .richText, .unknown, .color, .code:
      return false
    }
  }

  var canReveal: Bool {
    switch self {
    case .file, .image, .pdf, .audio:
      return true
    case .text, .richText, .unknown, .url, .color, .code:
      return false
    }
  }

  var hasManagedCacheReference: Bool {
    switch self {
    case .url, .image, .pdf, .audio, .richText:
      return true
    case .text, .file, .unknown, .color, .code:
      return false
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

  static let allCases: [ClipboardSortMode] = [.mostRecent, .mostUsed, .text, .links, .images, .colors, .audio, .files, .pinned, .code]

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
    }
  }
}

enum ClipboardCollectionDefaults {
  static let names = [
    "Useful Links",
    "Important Notes",
    "Code Snippets",
    "Read Later"
  ]

  static func normalizedName(_ value: String?) -> String? {
    guard let value else { return nil }
    let name = value
      .split { $0.isWhitespace }
      .joined(separator: " ")
      .clipboardTrimmed
    guard !name.isEmpty else { return nil }
    return String(name.prefix(40))
  }
}

struct ClipboardItem {
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

  var searchableText: String {
    var text = kindLabel + " " + displayText.lowercased() + " " + payload.lowercased()
    if let customTitle {
      text += " " + customTitle.lowercased()
    }
    if let sourceApp {
      text += " " + sourceApp.lowercased()
    }
    if let ocrText {
      text += " " + ocrText.lowercased()
    }
    if let sourceAppBundleId {
      text += " " + sourceAppBundleId.lowercased()
    }
    if let collectionName {
      text += " " + collectionName.lowercased()
    }
    return text
  }

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
    }
  }

  init(
    id: UUID,
    kind: ClipboardItemKind,
    displayText: String,
    payload: String,
    payloadHash: String,
    createdAt: Date,
    lastUsedAt: Date,
    useCount: Int,
    sourceApp: String?,
    imagePath: String?,
    thumbnailPath: String?,
    isPinned: Bool = false,
    sourceAppBundleId: String? = nil,
    ocrText: String? = nil,
    collectionName: String? = nil,
    customTitle: String? = nil
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
    self.customTitle = ClipboardItem.normalizedCustomTitle(customTitle)
  }

  static func normalizedCustomTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let title = value
      .split { $0.isWhitespace }
      .joined(separator: " ")
      .clipboardTrimmed
    guard !title.isEmpty else { return nil }
    return String(title.prefix(80))
  }
}
