import AppKit

enum ClipboardCollectionVisuals {
  private static let customPalette: [NSColor] = [
    NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.32, alpha: 1), NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.95, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.88, alpha: 1), NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.72, alpha: 1), NSColor(calibratedRed: 0.74, green: 0.42, blue: 0.16, alpha: 1),
  ]

  static func color(for mode: ClipboardSortMode) -> NSColor {
    switch mode {
    case .mostRecent: return .secondaryLabelColor
    case .mostUsed: return NSColor(calibratedRed: 0.58, green: 0.42, blue: 0.92, alpha: 1)
    case .text: return NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.00, alpha: 1)
    case .links: return NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.98, alpha: 1)
    case .images: return NSColor(calibratedRed: 1.00, green: 0.22, blue: 0.25, alpha: 1)
    case .colors: return NSColor(calibratedRed: 0.00, green: 0.65, blue: 0.74, alpha: 1)
    case .audio: return NSColor(calibratedRed: 0.93, green: 0.12, blue: 0.34, alpha: 1)
    case .files: return NSColor(calibratedRed: 0.11, green: 0.68, blue: 0.36, alpha: 1)
    case .pinned: return NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.48, alpha: 1)
    case .code: return NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.78, alpha: 1)
    case .videos: return NSColor(calibratedRed: 0.43, green: 0.32, blue: 0.94, alpha: 1)
    }
  }

  static func color(forCollectionNamed name: String, overrideHex: String? = nil) -> NSColor {
    if let color = color(fromHex: overrideHex) { return color }
    return defaultColor(forCollectionNamed: name)
  }

  static func defaultColor(forCollectionNamed name: String) -> NSColor { customPalette[stablePaletteIndex(for: name)] }

  static func hexString(for color: NSColor) -> String {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    let red = Int((rgb.redComponent * 255).rounded())
    let green = Int((rgb.greenComponent * 255).rounded())
    let blue = Int((rgb.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
  }

  private static func color(fromHex value: String?) -> NSColor? {
    guard let value else { return nil }
    var hex = value.clipboardTrimmed
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6, let rawValue = Int(hex, radix: 16) else { return nil }
    let red = CGFloat((rawValue >> 16) & 0xFF) / 255
    let green = CGFloat((rawValue >> 8) & 0xFF) / 255
    let blue = CGFloat(rawValue & 0xFF) / 255
    return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
  }

  private static func stablePaletteIndex(for name: String) -> Int {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for scalar in name.lowercased().unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return Int(hash % UInt64(customPalette.count))
  }
}

struct CollectionCreationRequest {
  let name: String
  let colorHex: String
  let icon: String
}
