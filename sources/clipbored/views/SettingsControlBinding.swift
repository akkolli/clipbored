import AppKit

/// Retained by Settings while AppKit holds a weak target. Each control defines
/// its model read and write together, instead of matching separate tag switches.
final class SettingsControlBinding: NSObject {
  private let change: SettingsModel.Change
  private let read: () -> Void
  private let write: () -> Void

  init(control: NSControl, change: SettingsModel.Change, read: @escaping () -> Void, write: @escaping () -> Void) {
    self.change = change
    self.read = read
    self.write = write
    super.init()
    control.target = self
    control.action = #selector(valueChanged)
    read()
  }

  func refresh(for change: SettingsModel.Change? = nil) { if change == nil || change == self.change { read() } }

  @objc private func valueChanged() {
    write()
    read()
  }

  static func checkbox(
    _ button: NSButton, settings: SettingsModel, key: ReferenceWritableKeyPath<SettingsModel, Bool>, change: SettingsModel.Change
  ) -> SettingsControlBinding {
    SettingsControlBinding(
      control: button, change: change, read: { button.state = settings[keyPath: key] ? .on : .off },
      write: { settings[keyPath: key] = button.state == .on })
  }

  static func popup<Value: RawRepresentable>(
    _ popup: NSPopUpButton, settings: SettingsModel, key: ReferenceWritableKeyPath<SettingsModel, Value>, change: SettingsModel.Change,
    values: [Value], title: (Value) -> String
  ) -> SettingsControlBinding where Value.RawValue == Int {
    popup.removeAllItems()
    for value in values {
      popup.addItem(withTitle: title(value))
      popup.lastItem?.representedObject = value.rawValue
    }
    return SettingsControlBinding(
      control: popup, change: change,
      read: {
        if let item = popup.itemArray.first(where: { $0.representedObject as? Int == settings[keyPath: key].rawValue }) {
          popup.select(item)
        }
      },
      write: {
        if let raw = popup.selectedItem?.representedObject as? Int, let value = Value(rawValue: raw) { settings[keyPath: key] = value }
      })
  }
}
