import AppKit
import UniformTypeIdentifiers

enum ClipboardArchivePanel {
  static func configure(_ panel: NSSavePanel) {
    if let type = UTType(filenameExtension: ClipboardArchiveService.fileExtension, conformingTo: .data) {
      panel.allowedContentTypes = [type]
    }
    panel.isExtensionHidden = false
  }

  static func suggestedName(_ fileName: String) -> String {
    let suffix = "." + ClipboardArchiveService.fileExtension
    return fileName.hasSuffix(suffix) ? String(fileName.dropLast(suffix.count)) : fileName
  }
}
