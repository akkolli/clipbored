import AppKit
import Vision

enum ImageTextExtractor {
  static func recognizedText(in image: NSImage) -> String? {
    let boundedImage = image.resized(to: CGSize(
      width: AppConfiguration.maxFullImagePixelSize,
      height: AppConfiguration.maxFullImagePixelSize
    ))
    guard let cgImage = boundedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.015

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return nil
    }

    let lines = request.results?.compactMap { observation in
      observation.topCandidates(1).first?.string.clipboardTrimmed
    } ?? []
    return normalized(lines)
  }

  private static func normalized(_ lines: [String]) -> String? {
    let text = lines
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    return text.isEmpty ? nil : text
  }
}
