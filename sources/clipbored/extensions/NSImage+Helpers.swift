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
}

extension NSView {
  var isInAnyViewHierarchy: Bool {
    return window != nil
  }
}
