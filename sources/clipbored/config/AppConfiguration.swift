import Foundation
import AppKit

enum AppConfiguration {
  static let appName = "ClipBored"
  static let storageDirectoryOverrideEnvironmentKey = "CLIPBORED_STORAGE_DIR"
  static let defaultHistoryLength = 300
  static let minHistoryLength = 50
  static let maxHistoryLength = 2000
  static let minCacheMaxBytes: Int64 = 2 * 1024 * 1024
  static let defaultCacheMaxBytes: Int64 = 120 * 1024 * 1024
  static let maxCacheMaxBytes: Int64 = 512 * 1024 * 1024
  static let maxPinnedItems = 250
  static let maxFullImagePixelSize: CGFloat = 1600
  static let maxRecognizedImageTextLength = 4096
  static let maxImageCacheFiles = 1000
  static let defaultOpenShortcut = ShortcutBinding(key: "v", modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue)
  static let defaultSettingsShortcut = ShortcutBinding(key: ",", modifierFlags: NSEvent.ModifierFlags.command.rawValue)
  static let defaultIgnoredApps: [String] = [
    "1password",
    "bitwarden",
    "lastpass",
    "dashlane",
    "keeper",
    "keepass",
    "authy"
  ]
  static let defaultPollProfile: PollProfile = .balanced
  static let minResponsiveActiveInterval: TimeInterval = 0.075

  enum PollProfile: Int {
    case battery = 0
    case balanced = 1
    case responsive = 2

    static let allCases: [PollProfile] = [.battery, .balanced, .responsive]

    var title: String {
      switch self {
      case .battery: return "Battery Saver"
      case .balanced: return "Balanced"
      case .responsive: return "Responsive"
      }
    }

    var idleInterval: TimeInterval {
      switch self {
      case .battery: return 0.50
      case .balanced: return 0.25
      case .responsive: return 0.12
      }
    }

    var activeInterval: TimeInterval {
      switch self {
        case .battery: return 0.12
        case .balanced: return 0.075
        case .responsive: return 0.075
      }
    }

    var idleRecoveryWindow: TimeInterval {
      switch self {
      case .battery: return 3.5
      case .balanced: return 2.0
      case .responsive: return 1.2
      }
    }
  }
}

struct ShortcutBinding: Equatable {
  let key: String
  let modifierFlags: UInt

  init(key: String, modifierFlags: UInt) {
    self.key = key.lowercased()
    self.modifierFlags = modifierFlags
  }

  var displayText: String {
    var text = ""
    if modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0 { text += "⌘" }
    if modifierFlags & NSEvent.ModifierFlags.option.rawValue != 0 { text += "⌥" }
    if modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0 { text += "⌃" }
    if modifierFlags & NSEvent.ModifierFlags.shift.rawValue != 0 { text += "⇧" }
    return text + key.uppercased()
  }

  func matches(_ event: NSEvent) -> Bool {
    guard let eventChar = event.charactersIgnoringModifiers?.lowercased(), eventChar.count == 1 else {
      return false
    }
    let mask = event.modifierFlags.rawValue & (
      NSEvent.ModifierFlags.command.rawValue |
      NSEvent.ModifierFlags.option.rawValue |
      NSEvent.ModifierFlags.control.rawValue |
      NSEvent.ModifierFlags.shift.rawValue
    )
    return eventChar == key && mask == modifierFlags
  }

  func encoded() -> String {
    "\(modifierFlags)|\(key)"
  }

  func has(_ flag: NSEvent.ModifierFlags) -> Bool {
    modifierFlags & flag.rawValue != 0
  }

  init?(encoded value: String) {
    let parts = value.split(separator: "|")
    guard parts.count == 2, let flags = UInt(parts[0]), let key = parts.last else {
      return nil
    }
    self.key = String(key).lowercased()
    self.modifierFlags = flags
  }
}
