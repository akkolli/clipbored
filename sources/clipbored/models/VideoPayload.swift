import AppKit
import Foundation
import UniformTypeIdentifiers

enum VideoPayload {
  static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
    NSPasteboard.PasteboardType(rawValue: UTType.mpeg4Movie.identifier),
    NSPasteboard.PasteboardType(rawValue: UTType.quickTimeMovie.identifier),
    NSPasteboard.PasteboardType(rawValue: UTType.movie.identifier),
    NSPasteboard.PasteboardType(rawValue: UTType.video.identifier),
    NSPasteboard.PasteboardType(rawValue: "com.apple.m4v-video")
  ]

  static func data(from pasteboard: NSPasteboard) -> (data: Data, type: NSPasteboard.PasteboardType)? {
    for type in pasteboardTypes {
      if let data = pasteboard.data(forType: type), !data.isEmpty {
        return (data, type)
      }
    }
    return nil
  }

  static func fileExtension(for type: NSPasteboard.PasteboardType) -> String {
    switch type.rawValue {
    case UTType.mpeg4Movie.identifier:
      return "mp4"
    case UTType.quickTimeMovie.identifier, UTType.movie.identifier, UTType.video.identifier:
      return "mov"
    case "com.apple.m4v-video":
      return "m4v"
    default:
      return "mov"
    }
  }

  static func pasteboardType(forPath path: String) -> NSPasteboard.PasteboardType {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "mp4":
      return NSPasteboard.PasteboardType(rawValue: UTType.mpeg4Movie.identifier)
    case "m4v":
      return NSPasteboard.PasteboardType(rawValue: "com.apple.m4v-video")
    case "mov", "qt":
      return NSPasteboard.PasteboardType(rawValue: UTType.quickTimeMovie.identifier)
    default:
      return NSPasteboard.PasteboardType(rawValue: UTType.movie.identifier)
    }
  }

  static func displayTitle(byteCount: Int) -> String {
    "Video (\(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)))"
  }

  static func fileExtension(from path: String) -> String {
    let value = URL(fileURLWithPath: path).pathExtension.clipboardTrimmed
    return value.isEmpty ? "mov" : value.lowercased()
  }

  static func kindText(from path: String) -> String {
    let value = fileExtension(from: path)
    return value.isEmpty ? "Video" : value.uppercased()
  }
}
