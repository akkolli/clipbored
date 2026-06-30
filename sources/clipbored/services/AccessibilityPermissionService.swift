import ApplicationServices
import Foundation
import AppKit

enum AccessibilityPermissionService {
  static var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  static func requestPromptIfNeeded() -> Bool {
    if isTrusted {
      return true
    }

    guard let optionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String? else {
      return false
    }
    let options: CFDictionary = [optionPrompt: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openSystemSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
       NSWorkspace.shared.open(url) {
      return
    }

    let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    _ = NSWorkspace.shared.open(fallback)
  }
}
