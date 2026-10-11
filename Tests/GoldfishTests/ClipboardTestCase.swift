import AppKit
import XCTest

/// Test transfers and capture use a named board, never the user's clipboard.
class ClipboardTestCase: XCTestCase {
  let pasteboard = NSPasteboard.withUniqueName()

  override func tearDownWithError() throws {
    pasteboard.releaseGlobally()
    try super.tearDownWithError()
  }
}
