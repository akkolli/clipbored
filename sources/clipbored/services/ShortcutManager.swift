import AppKit
import Carbon

final class ShortcutManager {
  enum RegistrationStatus: Equatable {
    case registered
    case unsupportedShortcut(String)
    case conflict(String)
    case registrationFailed(String)

    var message: String {
      switch self {
      case .registered:
        return ""
      case .unsupportedShortcut(let shortcut):
        return "Unsupported shortcut: \(shortcut)"
      case .conflict(let shortcut):
        return "Shortcut is already in use: \(shortcut)"
      case .registrationFailed(let message):
        return "Shortcut registration failed: \(message)"
      }
    }
  }

  private enum HotKeyID: UInt32 {
    case openPanel = 1
    case stackCapture = 3
  }

  private let onOpenClipboardPanel: () -> Void
  private let onToggleStackCapture: () -> Void
  private let onStatusChange: (RegistrationStatus) -> Void

  private var openBinding: ShortcutBinding
  private var openHotKey: EventHotKeyRef?
  private var stackCaptureHotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  init(
    onOpenClipboardPanel: @escaping () -> Void,
    onToggleStackCapture: @escaping () -> Void = {},
    onStatusChange: @escaping (RegistrationStatus) -> Void = { _ in },
    openShortcut: ShortcutBinding
  ) {
    self.onOpenClipboardPanel = onOpenClipboardPanel
    self.onToggleStackCapture = onToggleStackCapture
    self.onStatusChange = onStatusChange
    self.openBinding = openShortcut
  }

  deinit {
    stop()
  }

  @discardableResult
  func start() -> RegistrationStatus {
    stop()

    if let status = Self.validationFailure(for: openBinding) {
      onStatusChange(status)
      return status
    }
    if openBinding == Self.stackCaptureShortcut {
      let status = RegistrationStatus.conflict(Self.stackCaptureShortcut.displayText)
      onStatusChange(status)
      return status
    }

    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handle(event: event)
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    guard installStatus == noErr else {
      let status = RegistrationStatus.registrationFailed(osStatusMessage(installStatus))
      onStatusChange(status)
      return status
    }

    let openStatus = register(binding: openBinding, id: .openPanel, target: &openHotKey)
    guard openStatus == .registered else {
      stop()
      onStatusChange(openStatus)
      return openStatus
    }

    let stackCaptureStatus = register(binding: Self.stackCaptureShortcut, id: .stackCapture, target: &stackCaptureHotKey)
    guard stackCaptureStatus == .registered else {
      stop()
      onStatusChange(stackCaptureStatus)
      return stackCaptureStatus
    }

    onStatusChange(.registered)
    return .registered
  }

  @discardableResult
  func reconfigure(openShortcut: ShortcutBinding) -> RegistrationStatus {
    openBinding = openShortcut
    return start()
  }

  func stop() {
    if let openHotKey {
      UnregisterEventHotKey(openHotKey)
    }
    if let stackCaptureHotKey {
      UnregisterEventHotKey(stackCaptureHotKey)
    }
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }

    openHotKey = nil
    stackCaptureHotKey = nil
    eventHandler = nil
  }

  private func register(binding: ShortcutBinding, id: HotKeyID, target: inout EventHotKeyRef?) -> RegistrationStatus {
    guard let keyCode = Self.virtualKeyCode(for: binding.key) else {
      return .unsupportedShortcut(binding.displayText)
    }

    let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id.rawValue)
    let status = RegisterEventHotKey(
      UInt32(keyCode),
      Self.carbonModifiers(for: binding.modifierFlags),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &target
    )

    if status == noErr {
      return .registered
    }

    if status == eventHotKeyExistsErr {
      return .conflict(binding.displayText)
    }

    return .registrationFailed(osStatusMessage(status))
  }

  static func validationFailure(for binding: ShortcutBinding) -> RegistrationStatus? {
    guard Self.virtualKeyCode(for: binding.key) != nil else {
      return .unsupportedShortcut(binding.displayText)
    }
    let required = NSEvent.ModifierFlags.command.rawValue
      | NSEvent.ModifierFlags.option.rawValue
      | NSEvent.ModifierFlags.control.rawValue
    return binding.modifierFlags & required == 0 ? .unsupportedShortcut(binding.displayText) : nil
  }

  private func handle(event: EventRef?) {
    guard let event else { return }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )

    guard status == noErr, hotKeyID.signature == Self.hotKeySignature else { return }

    switch HotKeyID(rawValue: hotKeyID.id) {
    case .openPanel:
      onOpenClipboardPanel()
    case .stackCapture:
      onToggleStackCapture()
    case nil:
      break
    }
  }

  static func virtualKeyCode(for key: String) -> UInt16? {
    guard key.utf8.count == 1, var byte = key.utf8.first else { return nil }
    if byte >= 65, byte <= 90 {
      byte += 32
    }

    switch byte {
    case 97: return UInt16(kVK_ANSI_A)
    case 98: return UInt16(kVK_ANSI_B)
    case 99: return UInt16(kVK_ANSI_C)
    case 100: return UInt16(kVK_ANSI_D)
    case 101: return UInt16(kVK_ANSI_E)
    case 102: return UInt16(kVK_ANSI_F)
    case 103: return UInt16(kVK_ANSI_G)
    case 104: return UInt16(kVK_ANSI_H)
    case 105: return UInt16(kVK_ANSI_I)
    case 106: return UInt16(kVK_ANSI_J)
    case 107: return UInt16(kVK_ANSI_K)
    case 108: return UInt16(kVK_ANSI_L)
    case 109: return UInt16(kVK_ANSI_M)
    case 110: return UInt16(kVK_ANSI_N)
    case 111: return UInt16(kVK_ANSI_O)
    case 112: return UInt16(kVK_ANSI_P)
    case 113: return UInt16(kVK_ANSI_Q)
    case 114: return UInt16(kVK_ANSI_R)
    case 115: return UInt16(kVK_ANSI_S)
    case 116: return UInt16(kVK_ANSI_T)
    case 117: return UInt16(kVK_ANSI_U)
    case 118: return UInt16(kVK_ANSI_V)
    case 119: return UInt16(kVK_ANSI_W)
    case 120: return UInt16(kVK_ANSI_X)
    case 121: return UInt16(kVK_ANSI_Y)
    case 122: return UInt16(kVK_ANSI_Z)
    case 48: return UInt16(kVK_ANSI_0)
    case 49: return UInt16(kVK_ANSI_1)
    case 50: return UInt16(kVK_ANSI_2)
    case 51: return UInt16(kVK_ANSI_3)
    case 52: return UInt16(kVK_ANSI_4)
    case 53: return UInt16(kVK_ANSI_5)
    case 54: return UInt16(kVK_ANSI_6)
    case 55: return UInt16(kVK_ANSI_7)
    case 56: return UInt16(kVK_ANSI_8)
    case 57: return UInt16(kVK_ANSI_9)
    case 44: return UInt16(kVK_ANSI_Comma)
    case 46: return UInt16(kVK_ANSI_Period)
    case 47: return UInt16(kVK_ANSI_Slash)
    case 59: return UInt16(kVK_ANSI_Semicolon)
    case 39: return UInt16(kVK_ANSI_Quote)
    case 91: return UInt16(kVK_ANSI_LeftBracket)
    case 93: return UInt16(kVK_ANSI_RightBracket)
    case 45: return UInt16(kVK_ANSI_Minus)
    case 61: return UInt16(kVK_ANSI_Equal)
    case 96: return UInt16(kVK_ANSI_Grave)
    default: return nil
    }
  }

  static func carbonModifiers(for modifierFlags: UInt) -> UInt32 {
    var carbonFlags: UInt32 = 0
    if modifierFlags & NSEvent.ModifierFlags.command.rawValue != 0 { carbonFlags |= UInt32(cmdKey) }
    if modifierFlags & NSEvent.ModifierFlags.option.rawValue != 0 { carbonFlags |= UInt32(optionKey) }
    if modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0 { carbonFlags |= UInt32(controlKey) }
    if modifierFlags & NSEvent.ModifierFlags.shift.rawValue != 0 { carbonFlags |= UInt32(shiftKey) }
    return carbonFlags
  }

  private static let hotKeySignature: OSType = 0x436C7042

  static let stackCaptureShortcut = ShortcutBinding(
    key: "c",
    modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
  )

  private func osStatusMessage(_ status: OSStatus) -> String {
    "OSStatus \(status)"
  }
}
