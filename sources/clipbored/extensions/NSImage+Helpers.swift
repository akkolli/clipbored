import AppKit

extension NSImage {
  func resized(to fitSize: CGSize) -> NSImage {
    let target = NSSize(width: fitSize.width, height: fitSize.height)
    let currentSize = size
    let ratio = min(target.width / currentSize.width, target.height / currentSize.height, 1.0)

    let newSize = NSSize(width: currentSize.width * ratio, height: currentSize.height * ratio)
    let newImage = NSImage(size: newSize)
    newImage.lockFocus()
    draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: currentSize),
      operation: .sourceOver,
      fraction: 1.0
    )
    newImage.unlockFocus()
    newImage.size = newSize
    return newImage
  }

  func pngData() -> Data? {
    guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
  }

  func rotatedClockwise() -> NSImage? {
    guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil),
          cgImage.width > 0,
          cgImage.height > 0 else {
      return nil
    }

    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
      data: nil,
      width: cgImage.height,
      height: cgImage.width,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      return nil
    }

    context.interpolationQuality = .high
    context.translateBy(x: CGFloat(cgImage.height), y: 0)
    context.rotate(by: .pi / 2)
    context.draw(
      cgImage,
      in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    )

    guard let output = context.makeImage() else { return nil }
    return NSImage(
      cgImage: output,
      size: NSSize(width: cgImage.height, height: cgImage.width)
    )
  }
}

extension NSView {
  var isInAnyViewHierarchy: Bool {
    return window != nil
  }
}
