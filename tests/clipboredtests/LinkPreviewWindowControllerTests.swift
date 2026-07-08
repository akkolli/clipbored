import XCTest
@testable import ClipBored

final class LinkPreviewWindowControllerTests: XCTestCase {
  func testReusedPreviewIgnoresStaleObservedTitleUntilNewNavigationStarts() throws {
    let controller = LinkPreviewWindowController()
    let firstURL = try XCTUnwrap(URL(string: "https://example.com/old"))
    let secondURL = try XCTUnwrap(URL(string: "https://example.com/new"))

    controller.debugPrepareForPreview(LinkPreviewRequest(url: firstURL, title: "Old request title"))
    controller.debugAllowObservedPageTitles()
    controller.debugApplyObservedPageTitle("Old loaded title")

    XCTAssertEqual(controller.debugTitleText, "Old loaded title")

    controller.debugPrepareForPreview(LinkPreviewRequest(url: secondURL, title: "New request title"))
    controller.debugApplyObservedPageTitle("Old loaded title")

    XCTAssertEqual(controller.debugTitleText, "New request title")
    XCTAssertEqual(controller.debugAddressText, "https://example.com/new")
    XCTAssertEqual(controller.debugStatusText, "Loading")

    controller.debugAllowObservedPageTitles()
    controller.debugApplyObservedPageTitle("New loaded title")

    XCTAssertEqual(controller.debugTitleText, "New loaded title")
  }

  func testCancelledNavigationDoesNotShowFalseLoadFailure() throws {
    let controller = LinkPreviewWindowController()
    let url = try XCTUnwrap(URL(string: "https://example.com/new"))

    controller.debugPrepareForPreview(LinkPreviewRequest(url: url, title: "New request title"))
    controller.debugApplyNavigationFailure(URLError(.cancelled))

    XCTAssertEqual(controller.debugStatusText, "Loading")

    controller.debugApplyNavigationFailure(URLError(.timedOut))

    XCTAssertEqual(controller.debugStatusText, "Could not load")
  }

  func testToolbarTooltipsTrackFullVisibleText() throws {
    let controller = LinkPreviewWindowController()
    let url = try XCTUnwrap(URL(string: "https://example.com/articles/a-very-long-release-note-title?ref=clipbored"))

    controller.debugPrepareForPreview(LinkPreviewRequest(url: url, title: "Release note with a long title"))

    XCTAssertEqual(controller.debugTitleTooltip, "Release note with a long title")
    XCTAssertEqual(controller.debugAddressTooltip, url.absoluteString)
    XCTAssertEqual(controller.debugStatusTooltip, "Loading")

    controller.debugAllowObservedPageTitles()
    controller.debugApplyObservedPageTitle("Loaded page title that may truncate in the toolbar")

    XCTAssertEqual(controller.debugTitleTooltip, "Loaded page title that may truncate in the toolbar")

    controller.debugApplyNavigationFailure(URLError(.timedOut))

    XCTAssertEqual(controller.debugStatusTooltip, "Could not load")
  }

  func testOpenInBrowserUsesDisplayedPageURLAndResetsForReusedPreview() throws {
    var openedURLs: [URL] = []
    let controller = LinkPreviewWindowController { openedURLs.append($0) }
    let firstURL = try XCTUnwrap(URL(string: "https://example.com/old"))
    let navigatedURL = try XCTUnwrap(URL(string: "https://example.com/old/details"))
    let secondURL = try XCTUnwrap(URL(string: "https://example.com/new"))

    controller.debugPrepareForPreview(LinkPreviewRequest(url: firstURL, title: "Old request title"))
    controller.debugSetDisplayedPageURL(navigatedURL)
    controller.debugOpenInBrowser()

    XCTAssertEqual(openedURLs, [navigatedURL])

    controller.debugPrepareForPreview(LinkPreviewRequest(url: secondURL, title: "New request title"))
    controller.debugOpenInBrowser()

    XCTAssertEqual(openedURLs, [navigatedURL, secondURL])
  }
}
