import AppKit

struct ClipboardItemCardLayout: Equatable {
  let width: CGFloat
  let height: CGFloat
  let inset: CGFloat
  let headerHeight: CGFloat
  var bodyHeight: CGFloat { height - headerHeight - footerHeight }
  let footerHeight: CGFloat
  var textScale: CGFloat = 1
  var usesGalleryStyle = false

  static func gallery(width: ClipboardShelfWidth, largerText: Bool) -> ClipboardItemCardLayout {
    let size: NSSize
    switch width {
    case .compact: size = NSSize(width: 204, height: 224)
    case .standard: size = NSSize(width: 240, height: 260)
    case .wide: size = NSSize(width: 280, height: 300)
    }
    let height = size.height + (largerText ? 28 : 0)
    return ClipboardItemCardLayout(
      width: size.width, height: height, inset: 16, headerHeight: 52, footerHeight: 32, textScale: largerText ? 1.2 : 1,
      usesGalleryStyle: true)
  }

  static let compact = ClipboardItemCardLayout(
    width: 264, height: 244, inset: ClipboardShelfStyle.inset, headerHeight: 84, footerHeight: 32)

  var contentInset: CGFloat { width < 260 ? 12 : 16 }
  var cornerRadius: CGFloat { width < 260 ? 18 : ClipboardShelfStyle.cardRadius }

  func fittingVerticalContent(of item: ClipboardItem) -> ClipboardItemCardLayout {
    // AppKit rounds autoresized child frames to backing pixels. Integral
    // sections keep that rounding from taking a fraction off the final text line.
    let isTile = width < 260
    let header: CGFloat = ceil((isTile ? 44 : 46) * textScale)
    let footer: CGFloat = ceil((isTile ? 28 : 30) * textScale)
    let body: CGFloat
    switch item.presentationKind {
    case .text, .richText, .code, .unknown:
      let measured = ClipboardCardTextLayout(
        item: item, scale: textScale, size: NSSize(width: max(1, width - contentInset * 2), height: 10_000)
      ).height
      let maximum = isTile ? 142 : 154
      body = min(CGFloat(maximum) * textScale, max(44 * textScale, measured + ClipboardCardTextLayout.verticalInset * 2))
    case .image, .video, .pdf: body = (isTile ? 132 : min(180, max(148, width * 0.40))) * textScale
    case .color: body = (isTile ? 112 : 120) * textScale
    case .url: body = (isTile ? 88 : 92) * textScale
    case .file, .audio: body = (isTile ? 82 : 88) * textScale
    }
    return ClipboardItemCardLayout(
      width: width, height: header + ceil(body) + footer, inset: 16, headerHeight: header, footerHeight: footer, textScale: textScale,
      usesGalleryStyle: true)
  }

  var size: NSSize { NSSize(width: width, height: height) }

  func withWidth(_ width: CGFloat) -> ClipboardItemCardLayout {
    ClipboardItemCardLayout(
      width: width, height: height, inset: inset, headerHeight: headerHeight, footerHeight: footerHeight, textScale: textScale,
      usesGalleryStyle: usesGalleryStyle)
  }

  func withHeight(_ height: CGFloat) -> ClipboardItemCardLayout {
    ClipboardItemCardLayout(
      width: width, height: height, inset: inset, headerHeight: headerHeight, footerHeight: footerHeight, textScale: textScale,
      usesGalleryStyle: usesGalleryStyle)
  }

  func fittingGalleryHeight(_ availableHeight: CGFloat) -> ClipboardItemCardLayout {
    guard usesGalleryStyle, availableHeight > 120, availableHeight < height else { return self }
    return withHeight(availableHeight)
  }

  func withLargerText(_ larger: Bool) -> ClipboardItemCardLayout {
    var result = self
    result.textScale = larger ? 1.2 : 1
    return result
  }
}
