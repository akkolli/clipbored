// Rebuild the scalable Goldfish mark: swift scripts/generate-app-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("sources/clipbored/resources")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Goldfish-icon-\(UUID().uuidString)")
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func drawMark(size: Int, appearance: String = "default") -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let transform = NSAffineTransform()
  transform.scale(by: CGFloat(size) / 1024)
  transform.concat()
  let orange = appearance == "monochrome" ? NSColor(white: 0.24, alpha: 1)
    : NSColor(srgbRed: 0.96, green: 0.43, blue: 0.19, alpha: 1)
  let background = appearance == "dark" ? NSColor(srgbRed: 0.23, green: 0.12, blue: 0.08, alpha: 1) : orange
  background.setFill()
  NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184).fill()
  let cream = NSColor(srgbRed: 1, green: 0.97, blue: 0.90, alpha: 1)
  // A rounded tail and one sweeping body stay legible at menu and Dock sizes.
  let tail = NSBezierPath()
  tail.move(to: NSPoint(x: 418, y: 512))
  tail.curve(to: NSPoint(x: 228, y: 652), controlPoint1: NSPoint(x: 330, y: 548), controlPoint2: NSPoint(x: 228, y: 690))
  tail.curve(to: NSPoint(x: 250, y: 512), controlPoint1: NSPoint(x: 222, y: 594), controlPoint2: NSPoint(x: 250, y: 548))
  tail.curve(to: NSPoint(x: 228, y: 372), controlPoint1: NSPoint(x: 250, y: 476), controlPoint2: NSPoint(x: 222, y: 430))
  tail.curve(to: NSPoint(x: 418, y: 512), controlPoint1: NSPoint(x: 228, y: 334), controlPoint2: NSPoint(x: 330, y: 476))
  tail.close()
  cream.withAlphaComponent(0.78).setFill()
  tail.fill()
  let fin = NSBezierPath()
  fin.move(to: NSPoint(x: 432, y: 652))
  fin.curve(to: NSPoint(x: 603, y: 681), controlPoint1: NSPoint(x: 459, y: 745), controlPoint2: NSPoint(x: 558, y: 766))
  fin.line(to: NSPoint(x: 432, y: 652))
  cream.withAlphaComponent(0.78).setFill()
  fin.fill()
  let body = NSBezierPath()
  body.move(to: NSPoint(x: 354, y: 512))
  body.curve(to: NSPoint(x: 800, y: 512), controlPoint1: NSPoint(x: 479, y: 761), controlPoint2: NSPoint(x: 722, y: 708))
  body.curve(to: NSPoint(x: 354, y: 512), controlPoint1: NSPoint(x: 722, y: 316), controlPoint2: NSPoint(x: 479, y: 263))
  body.close()
  cream.setFill()
  body.fill()
  background.setFill()
  NSBezierPath(ovalIn: NSRect(x: 669, y: 534, width: 38, height: 38)).fill()
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
  try drawMark(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
  try drawMark(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
let previews = root.appendingPathComponent("docs/goldfish-design-2026-09-21")
try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
for appearance in ["default", "dark", "monochrome"] {
  try drawMark(size: 256, appearance: appearance).write(to: previews.appendingPathComponent("icon-\(appearance).png"))
}
