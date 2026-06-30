import AppKit

@main
struct ClipBoredApp {
  private static let appDelegate = AppDelegate()

  static func main() {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.delegate = appDelegate
    application.activate(ignoringOtherApps: true)
    application.run()
  }
}
