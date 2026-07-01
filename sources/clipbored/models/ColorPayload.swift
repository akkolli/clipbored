import AppKit
import Foundation

enum ColorPayload {
  static func hexString(from color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else {
      return nil
    }
    let red = clampedByte(rgb.redComponent)
    let green = clampedByte(rgb.greenComponent)
    let blue = clampedByte(rgb.blueComponent)
    let alpha = clampedByte(rgb.alphaComponent)
    if alpha >= 255 {
      return String(format: "#%02X%02X%02X", red, green, blue)
    }
    return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
  }

  static func color(from payload: String) -> NSColor? {
    var value = payload.clipboardTrimmed
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6 || value.count == 8,
          let raw = UInt32(value, radix: 16) else {
      return nil
    }

    let hasAlpha = value.count == 8
    let red = CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let green = CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let blue = CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let alpha = hasAlpha ? CGFloat(raw & 0xFF) / 255 : 1
    return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
  }

  static func displayHex(from payload: String) -> String {
    if let color = color(from: payload), let hex = hexString(from: color) {
      return hex
    }
    let normalized = payload.clipboardTrimmed
    return normalized.hasPrefix("#") ? normalized.uppercased() : "#\(normalized.uppercased())"
  }

  static func componentSummary(from payload: String) -> String {
    guard let color = color(from: payload),
          let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else {
      return "Color"
    }
    let red = clampedByte(rgb.redComponent)
    let green = clampedByte(rgb.greenComponent)
    let blue = clampedByte(rgb.blueComponent)
    let alpha = clampedByte(rgb.alphaComponent)
    if alpha >= 255 {
      return "RGB \(red) \(green) \(blue)"
    }
    return "RGBA \(red) \(green) \(blue) \(alpha)"
  }

  static func previewText(from payload: String) -> String {
    "\(displayHex(from: payload))\n\(componentSummary(from: payload))"
  }

  static func contrastingTextColor(for color: NSColor) -> NSColor {
    guard let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else {
      return .labelColor
    }
    let luminance = (0.299 * rgb.redComponent) + (0.587 * rgb.greenComponent) + (0.114 * rgb.blueComponent)
    return luminance > 0.62 ? NSColor.black.withAlphaComponent(0.82) : .white
  }

  private static func clampedByte(_ value: CGFloat) -> Int {
    Int((min(1, max(0, value)) * 255).rounded())
  }
}
