import AppKit
import Carbon
import XCTest
@testable import ClipBored

final class ShortcutManagerTests: XCTestCase {
  func testVirtualKeyCodeMappingSupportsDefaults() {
    XCTAssertEqual(ShortcutManager.virtualKeyCode(for: "v"), UInt16(kVK_ANSI_V))
    XCTAssertEqual(ShortcutManager.virtualKeyCode(for: ","), UInt16(kVK_ANSI_Comma))
  }

  func testVirtualKeyCodeRejectsUnsupportedKeys() {
    XCTAssertNil(ShortcutManager.virtualKeyCode(for: "space"))
    XCTAssertNil(ShortcutManager.virtualKeyCode(for: ""))
  }

  func testCarbonModifierMapping() {
    let flags = NSEvent.ModifierFlags.command.union(.option).rawValue
    let carbon = ShortcutManager.carbonModifiers(for: flags)
    XCTAssertTrue(carbon & UInt32(cmdKey) != 0)
    XCTAssertTrue(carbon & UInt32(optionKey) != 0)
    XCTAssertFalse(carbon & UInt32(controlKey) != 0)
  }

  func testRejectsBareGlobalShortcut() {
    let manager = makeManager(openShortcut: ShortcutBinding(key: "v", modifierFlags: 0))

    XCTAssertEqual(manager.start(), .unsupportedShortcut("V"))
    manager.stop()
  }

  func testRejectsShiftOnlyGlobalShortcut() {
    let manager = makeManager(openShortcut: ShortcutBinding(key: "v", modifierFlags: NSEvent.ModifierFlags.shift.rawValue))

    XCTAssertEqual(manager.start(), .unsupportedShortcut("⇧V"))
    manager.stop()
  }

  func testRejectsUnsupportedSettingsShortcutBeforeRegistration() {
    let manager = makeManager(
      openShortcut: AppConfiguration.defaultOpenShortcut,
      settingsShortcut: ShortcutBinding(key: "space", modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    )

    XCTAssertEqual(manager.start(), .unsupportedShortcut("⌘SPACE"))
    manager.stop()
  }

  func testRejectsDuplicateShortcutBindingsBeforeRegistration() {
    let manager = makeManager(
      openShortcut: AppConfiguration.defaultOpenShortcut,
      settingsShortcut: AppConfiguration.defaultOpenShortcut
    )

    XCTAssertEqual(manager.start(), .conflict(AppConfiguration.defaultOpenShortcut.displayText))
    manager.stop()
  }

  private func makeManager(
    openShortcut: ShortcutBinding,
    settingsShortcut: ShortcutBinding = AppConfiguration.defaultSettingsShortcut
  ) -> ShortcutManager {
    ShortcutManager(
      onOpenClipboardPanel: {},
      onOpenSettings: {},
      openShortcut: openShortcut,
      settingsShortcut: settingsShortcut
    )
  }
}
