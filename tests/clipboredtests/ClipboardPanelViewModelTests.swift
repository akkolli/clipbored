import AppKit
import XCTest
@testable import ClipBored

final class ClipboardPanelViewModelTests: XCTestCase {
  private var tempURLs: [URL] = []

  override func tearDownWithError() throws {
    for url in tempURLs {
      try? FileManager.default.removeItem(at: url)
    }
    tempURLs.removeAll()
    try super.tearDownWithError()
  }

  func testComputeVisibleItemsFiltersAndSortsByMode() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: ClipboardCacheService())

    let sampleItems = makeSampleItems()

    let filteredLinks = viewModel.computeVisibleItems(from: sampleItems, query: "https://", sortMode: .links)
    XCTAssertEqual(filteredLinks.map(\.payload), ["https://apple.com"])

    let recentByUse = viewModel.computeVisibleItems(from: sampleItems, query: "", sortMode: .mostUsed)
    XCTAssertEqual(recentByUse.map(\.payload), ["two", "/tmp/report.pdf", "/tmp/voice.sound", "one", "https://apple.com", "four"])

    let textOnly = viewModel.computeVisibleItems(from: sampleItems, query: "", sortMode: .text)
    XCTAssertEqual(textOnly.map(\.payload), ["four", "two", "one"])

    let filesOnly = viewModel.computeVisibleItems(from: sampleItems, query: "", sortMode: .files)
    XCTAssertEqual(filesOnly.map(\.payload), ["/tmp/report.pdf"])

    let audioOnly = viewModel.computeVisibleItems(from: sampleItems, query: "", sortMode: .audio)
    XCTAssertEqual(audioOnly.map(\.payload), ["/tmp/voice.sound"])

    let pinnedOnly = viewModel.computeVisibleItems(from: sampleItems, query: "", sortMode: .pinned)
    XCTAssertEqual(pinnedOnly.map(\.payload), ["four", "one"])
  }

  func testSearchMatchesIndependentTokensCaseInsensitively() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: ClipboardCacheService())

    let items = [
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "GitHub release token",
        payload: "Copied from github.com",
        payloadHash: hash("github-token"),
        createdAt: Date(timeIntervalSince1970: 100),
        lastUsedAt: Date(timeIntervalSince1970: 100),
        useCount: 0,
        sourceApp: "Safari",
        imagePath: nil,
        thumbnailPath: nil
      ),
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Unrelated note",
        payload: "release notes",
        payloadHash: hash("note"),
        createdAt: Date(timeIntervalSince1970: 90),
        lastUsedAt: Date(timeIntervalSince1970: 90),
        useCount: 0,
        sourceApp: "Notes",
        imagePath: nil,
        thumbnailPath: nil
      )
    ]

    let result = viewModel.computeVisibleItems(from: items, query: "TOKEN github", sortMode: .mostRecent)
    XCTAssertEqual(result.map(\.displayText), ["GitHub release token"])
  }

  func testStructuredSearchFiltersBySourceTypeCollectionAndPinState() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: ClipboardCacheService())
    let items = [
      ClipboardItem(
        id: UUID(),
        kind: .url,
        displayText: "Release notes",
        payload: "https://example.com/releases",
        payloadHash: hash("release"),
        createdAt: Date(timeIntervalSince1970: 200),
        lastUsedAt: Date(timeIntervalSince1970: 200),
        useCount: 0,
        sourceApp: "Safari",
        imagePath: nil,
        thumbnailPath: nil,
        sourceAppBundleId: "com.apple.Safari",
        collectionName: "Useful Links"
      ),
      ClipboardItem(
        id: UUID(),
        kind: .image,
        displayText: "Campaign portrait",
        payload: "/tmp/campaign.png",
        payloadHash: hash("campaign"),
        createdAt: Date(timeIntervalSince1970: 300),
        lastUsedAt: Date(timeIntervalSince1970: 300),
        useCount: 0,
        sourceApp: "Photos",
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: true,
        sourceAppBundleId: "com.apple.Photos",
        collectionName: "Visual References"
      ),
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Meeting note",
        payload: "Budget follow-up",
        payloadHash: hash("meeting"),
        createdAt: Date(timeIntervalSince1970: 100),
        lastUsedAt: Date(timeIntervalSince1970: 100),
        useCount: 0,
        sourceApp: "Notes",
        imagePath: nil,
        thumbnailPath: nil
      )
    ]

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "app:safari type:link", sortMode: .mostRecent).map(\.displayText),
      ["Release notes"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "app:apple.photos type:photo pinned:on", sortMode: .mostRecent).map(\.displayText),
      ["Campaign portrait"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "collection:visual type:image", sortMode: .mostRecent).map(\.displayText),
      ["Campaign portrait"]
    )
    XCTAssertTrue(
      viewModel.computeVisibleItems(from: items, query: "app:safari type:image", sortMode: .mostRecent).isEmpty
    )
  }

  func testStructuredSearchFiltersByCreatedDate() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: ClipboardCacheService())
    let first = makeTextItem("June twenty nine", createdAt: isoDate("2026-06-29"))
    let second = makeTextItem("June thirty", createdAt: isoDate("2026-06-30"))
    let third = makeTextItem("July first", createdAt: isoDate("2026-07-01"))
    let items = [first, second, third]

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "date:2026-06-30", sortMode: .mostRecent).map(\.payload),
      ["June thirty"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "after:2026-06-30", sortMode: .mostRecent).map(\.payload),
      ["July first", "June thirty"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "before:2026-06-30", sortMode: .mostRecent).map(\.payload),
      ["June twenty nine"]
    )
  }

  func testCollectionsFilterSearchAndPersistSelection() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let link = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Release notes",
      payload: "https://example.com/releases",
      payloadHash: hash("https://example.com/releases"),
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Safari",
      imagePath: nil,
      thumbnailPath: nil
    )
    let note = makeTextItem("Important meeting note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(link)
    store.upsert(note)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.selectItem(at: 1)
    viewModel.assignSelected(to: "  Client   Work  ")
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 2)

    XCTAssertEqual(viewModel.collectionNames, ["Client Work"])
    XCTAssertEqual(viewModel.collectionCount(named: "Client Work"), 1)
    XCTAssertEqual(viewModel.statusMessage, "Added to Client Work")

    viewModel.selectCollection(named: "Client Work")
    waitForVisibleItems(in: viewModel, count: 1)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["https://example.com/releases"])

    viewModel.searchText = "release"
    XCTAssertEqual(viewModel.collectionCount(named: "Client Work"), 1)
    XCTAssertEqual(viewModel.visibleItems.map(\.displayText), ["Release notes"])

    viewModel.searchText = "meeting"
    XCTAssertEqual(viewModel.collectionCount(named: "Client Work"), 0)
    XCTAssertTrue(viewModel.visibleItems.isEmpty)
  }

  func testSearchTextRecomputesVisibleItemsImmediately() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("alpha note", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("needle note", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.searchText = "needle"

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["needle note"])
    XCTAssertEqual(viewModel.selectedItem?.payload, "needle note")
  }

  func testSelectFirstItemSelectsFirstVisibleItem() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("older", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("newer", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.selectItem(at: 1)
    viewModel.selectFirstItem()

    XCTAssertEqual(viewModel.selectedItem?.payload, "newer")
  }

  func testSelectFirstItemPrefersLatestOnSubsequentUpdates() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("older", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("newer", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.selectItem(at: 1)
    viewModel.selectFirstItem()
    store.upsert(makeTextItem("latest", createdAt: Date(timeIntervalSince1970: 300)))
    store.flushPersistenceForTesting()

    waitForVisibleItems(in: viewModel, count: 3)
    XCTAssertEqual(viewModel.selectedItem?.payload, "latest")
  }

  func testDuplicateRecopyMovesExistingClipToMostRecentFront() {
    let settings = makeSettings()
    settings.pruneDuplicates = true
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("older duplicate text", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("new unique text", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    XCTAssertEqual(viewModel.visibleItems.first?.payload, "new unique text")

    store.upsert(makeTextItem("older duplicate text", createdAt: Date(timeIntervalSince1970: 50)))
    store.flushPersistenceForTesting()

    waitForVisibleItems(in: viewModel, count: 2)
    XCTAssertEqual(viewModel.visibleItems.first?.payload, "older duplicate text")
  }

  func testPollThenSearchAndCopyFlow() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)

    let payload = "clipbored-flow-test-\(UUID().uuidString)"
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(payload, forType: .string))

    monitor.pollNowAndWait()
    waitForStoreCount(store, count: 1, matching: payload)

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.searchText = payload
    waitForVisibleItems(in: viewModel, count: 1)
    XCTAssertEqual(viewModel.visibleItems.first?.payload, payload)

    viewModel.copySelected()
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), payload)
    XCTAssertEqual(viewModel.statusMessage, "Copied")
  }

  func testCopySelectedWritesTextToPasteboard() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeTextItem("panel copy text", createdAt: Date(timeIntervalSince1970: 100))
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.copySelected()

    XCTAssertEqual(viewModel.statusMessage, "Copied")
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), item.payload)
  }

  func testCopySelectedWritesURLToPasteboardTypes() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "https://example.com",
      payload: "https://example.com",
      payloadHash: hash("https://example.com"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.copySelected()

    XCTAssertEqual(viewModel.statusMessage, "Copied")
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), item.payload)
    XCTAssertEqual(NSPasteboard.general.string(forType: .URL), item.payload)
  }

  func testCopySelectedPlainTextWritesOnlyStringRepresentation() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Example",
      payload: "https://example.com",
      payloadHash: hash("https://example.com"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.copySelectedPlainText()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.statusMessage, "Copied Plain Text")
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), item.payload)
    XCTAssertNil(NSPasteboard.general.string(forType: .URL))
    XCTAssertEqual(store.items.first?.id, item.id)
    XCTAssertEqual(store.items.first?.useCount, 1)
  }

  func testQuickPasteItemByVisibleIndexWritesThatCard() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("first visible quick paste", createdAt: Date(timeIntervalSince1970: 200)))
    store.upsert(makeTextItem("second visible quick paste", createdAt: Date(timeIntervalSince1970: 100)))
    store.flushPersistenceForTesting()
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    NSPasteboard.general.clearContents()

    viewModel.pasteItem(at: 1)

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "second visible quick paste")
    XCTAssertEqual(viewModel.statusMessage, "Copied")
  }

  func testQuickPastePlainTextByVisibleIndexOmitsRichPasteboardTypes() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Example",
      payload: "https://example.com/quick",
      payloadHash: hash("https://example.com/quick"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: "Safari",
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(item)
    store.flushPersistenceForTesting()
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)
    NSPasteboard.general.clearContents()

    viewModel.pasteItemPlainText(at: 0)

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://example.com/quick")
    XCTAssertNil(NSPasteboard.general.string(forType: .URL))
  }

  func testStackPastesQueuedItemsInOrderAndConsumesThem() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first stacked clip", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second stacked clip", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(first)
    store.upsert(second)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()

    XCTAssertEqual(viewModel.stackCount, 2)
    XCTAssertEqual(viewModel.statusMessage, "Added to Stack")

    viewModel.pasteNextStackItem()
    store.flushPersistenceForTesting()

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "first stacked clip")
    XCTAssertEqual(viewModel.statusMessage, "Copied from Stack")
    XCTAssertEqual(viewModel.stackCount, 1)
    XCTAssertEqual(store.items.first(where: { $0.id == first.id })?.useCount, 1)

    viewModel.copyNextStackItem()
    store.flushPersistenceForTesting()

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "second stacked clip")
    XCTAssertEqual(viewModel.statusMessage, "Copied from Stack")
    XCTAssertEqual(viewModel.stackCount, 0)
  }

  func testStackToggleAndClearUpdateCount() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("stack toggle clip", createdAt: Date(timeIntervalSince1970: 100)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.toggleSelectedStackMembership()
    XCTAssertEqual(viewModel.stackCount, 1)
    XCTAssertEqual(viewModel.statusMessage, "Added to Stack")
    XCTAssertTrue(viewModel.isItemStacked(at: 0))

    viewModel.toggleSelectedStackMembership()
    XCTAssertEqual(viewModel.stackCount, 0)
    XCTAssertEqual(viewModel.statusMessage, "Removed from Stack")
    XCTAssertFalse(viewModel.isItemStacked(at: 0))

    viewModel.toggleSelectedStackMembership()
    viewModel.clearStack()
    XCTAssertEqual(viewModel.stackCount, 0)
    XCTAssertEqual(viewModel.statusMessage, "Cleared Stack")
  }

  func testSelectingStackFiltersVisibleItemsInQueueOrder() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first queue note", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second queue note", createdAt: Date(timeIntervalSince1970: 200))
    let outside = makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(first)
    store.upsert(second)
    store.upsert(outside)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["outside note", "second queue note", "first queue note"])

    viewModel.selectItem(at: 2)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectStack()

    XCTAssertTrue(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["first queue note", "second queue note"])

    viewModel.searchText = "second"
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["second queue note"])

    viewModel.clearSearch()
    viewModel.sortMode = .text
    XCTAssertFalse(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["outside note", "second queue note", "first queue note"])
  }

  func testUpdateSelectedTextRefreshesVisibleItemAndSearch() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeTextItem("draft meeting note", createdAt: Date(timeIntervalSince1970: 100))
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(viewModel.editableTextForSelected(), "draft meeting note")
    viewModel.updateSelectedText(to: "final launch note")
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(viewModel.statusMessage, "Updated text clip")
    XCTAssertEqual(viewModel.selectedItem?.id, item.id)
    XCTAssertEqual(viewModel.selectedItem?.displayText, "final launch note")
    XCTAssertEqual(viewModel.selectedItem?.payload, "final launch note")

    viewModel.searchText = "launch"
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["final launch note"])
    viewModel.searchText = "draft"
    XCTAssertTrue(viewModel.visibleItems.isEmpty)
  }

  func testUpdateSelectedTextRejectsEmptyAndNonTextSelections() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let text = makeTextItem("editable note", createdAt: Date(timeIntervalSince1970: 100))
    let file = makeMissingFileItem(useCount: 0)
    store.upsert(text)
    store.upsert(file)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    XCTAssertNil(viewModel.editableTextForItem(at: 0))
    viewModel.selectItem(at: 0)
    viewModel.updateSelectedText(to: "should not apply")
    XCTAssertEqual(store.items.first?.payload, file.payload)

    viewModel.selectItem(at: 1)
    viewModel.updateSelectedText(to: "   \n")
    XCTAssertEqual(viewModel.statusMessage, "Text clip cannot be empty")
    XCTAssertEqual(store.items.last?.payload, "editable note")
  }

  func testFailedCopyDoesNotMarkItemUsed() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeMissingFileItem(useCount: 0)
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.copySelected()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.statusMessage, "Could not write item to clipboard.")
    XCTAssertEqual(store.items.first?.id, item.id)
    XCTAssertEqual(store.items.first?.useCount, 0)
    XCTAssertEqual(store.items.first?.lastUsedAt, item.lastUsedAt)
  }

  func testFailedPasteDoesNotMarkItemUsed() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeMissingFileItem(useCount: 2)
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    var didRequestHide = false
    viewModel.willPasteToTarget = { didRequestHide = true }
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.pasteSelected()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.statusMessage, "Could not write item to clipboard.")
    XCTAssertFalse(didRequestHide)
    XCTAssertEqual(store.items.first?.id, item.id)
    XCTAssertEqual(store.items.first?.useCount, 2)
    XCTAssertEqual(store.items.first?.lastUsedAt, item.lastUsedAt)
  }

  func testPasteWithoutTargetCopiesButDoesNotRequestPanelHide() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeTextItem("manual paste fallback", createdAt: Date(timeIntervalSince1970: 10))
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    var didRequestHide = false
    viewModel.willPasteToTarget = { didRequestHide = true }
    viewModel.targetApplicationProvider = { nil }
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.pasteSelected()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.statusMessage, "Copied")
    XCTAssertFalse(didRequestHide)
    XCTAssertEqual(store.items.first?.id, item.id)
    XCTAssertEqual(store.items.first?.useCount, 1)
  }

  func testActionStatusIsNotOverwrittenUntilCaptureStatusChanges() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeTextItem("status visibility", createdAt: Date(timeIntervalSince1970: 10))
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)
    viewModel.copySelected()

    XCTAssertEqual(viewModel.statusMessage, "Copied")

    settings.setCaptureStatus(message: "Capture status updated while panel is open")
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    XCTAssertEqual(viewModel.statusMessage, "")
  }

  private func makeSettings() -> SettingsModel {
    let settings = SettingsModel(defaults: UserDefaults(suiteName: "com.clipbored.testmodel.\(UUID().uuidString)")!)
    settings.maxHistoryItems = 10
    settings.includeImageTextInSearch = false
    settings.pruneDuplicates = false
    return settings
  }

  private func makeStore(settings: SettingsModel) -> ClipboardStore {
    let cacheService = makeCacheService()
    return makeStore(settings: settings, cacheService: cacheService)
  }

  private func makeStore(settings: SettingsModel, cacheService: ClipboardCacheService) -> ClipboardStore {
    let tempURL = makeTempDirectory()
    return ClipboardStore(
      settings: settings,
      cacheService: cacheService,
      baseURL: tempURL,
      encryptionService: ClipboardEncryptionService(keyProvider: { nil })
    )
  }

  private func makeCacheService() -> ClipboardCacheService {
    ClipboardCacheService(baseURL: makeTempDirectory(), encryptionService: ClipboardEncryptionService(keyProvider: { nil }))
  }

  private func makeTempDirectory() -> URL {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboredtests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    tempURLs.append(tempURL)
    return tempURL
  }

  private func makeMissingFileItem(useCount: Int) -> ClipboardItem {
    let date = Date(timeIntervalSince1970: 2_000)
    let missingPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipbored-missing-\(UUID().uuidString)")
      .path
    return ClipboardItem(
      id: UUID(),
      kind: .file,
      displayText: "Missing file",
      payload: missingPath,
      payloadHash: hash(missingPath),
      createdAt: date,
      lastUsedAt: date,
      useCount: useCount,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
  }

  private func makeTextItem(_ text: String, createdAt: Date) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: text,
      payload: text,
      payloadHash: hash(text),
      createdAt: createdAt,
      lastUsedAt: createdAt,
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
  }

  private func waitForStoreCount(
    _ store: ClipboardStore,
    count: Int,
    matching payload: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(1)
    while store.items.filter({ $0.payload == payload }).count != count && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertEqual(store.items.filter({ $0.payload == payload }).count, count, file: file, line: line)
  }

  private func waitForVisibleItems(
    in viewModel: ClipboardPanelViewModel,
    count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(1)
    while viewModel.visibleItems.count != count && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertEqual(viewModel.visibleItems.count, count, file: file, line: line)
  }

  private func makeSampleItems() -> [ClipboardItem] {
    [
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Project notes",
        payload: "one",
        payloadHash: hash("one"),
        createdAt: Date(timeIntervalSince1970: 1000),
        lastUsedAt: Date(timeIntervalSince1970: 1000),
        useCount: 2,
        sourceApp: nil,
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: true
      ),
      ClipboardItem(
        id: UUID(),
        kind: .richText,
        displayText: "Two",
        payload: "two",
        payloadHash: hash("two"),
        createdAt: Date(timeIntervalSince1970: 1100),
        lastUsedAt: Date(timeIntervalSince1970: 1080),
        useCount: 4,
        sourceApp: "Mail",
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: false
      ),
      ClipboardItem(
        id: UUID(),
        kind: .url,
        displayText: "Apple",
        payload: "https://apple.com",
        payloadHash: hash("https://apple.com"),
        createdAt: Date(timeIntervalSince1970: 1030),
        lastUsedAt: Date(timeIntervalSince1970: 1050),
        useCount: 1,
        sourceApp: "Safari",
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: false
      ),
      ClipboardItem(
        id: UUID(),
        kind: .file,
        displayText: "report.pdf",
        payload: "/tmp/report.pdf",
        payloadHash: hash("/tmp/report.pdf"),
        createdAt: Date(timeIntervalSince1970: 1060),
        lastUsedAt: Date(timeIntervalSince1970: 1070),
        useCount: 3,
        sourceApp: "Finder",
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: false
      ),
      ClipboardItem(
        id: UUID(),
        kind: .audio,
        displayText: "Voice memo",
        payload: "/tmp/voice.sound",
        payloadHash: hash("/tmp/voice.sound"),
        createdAt: Date(timeIntervalSince1970: 1040),
        lastUsedAt: Date(timeIntervalSince1970: 1060),
        useCount: 2,
        sourceApp: "Voice Memos",
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: false
      ),
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Four",
        payload: "four",
        payloadHash: hash("four"),
        createdAt: Date(timeIntervalSince1970: 1200),
        lastUsedAt: Date(timeIntervalSince1970: 1200),
        useCount: 0,
        sourceApp: "Notes",
        imagePath: nil,
        thumbnailPath: nil,
        isPinned: true
      )
    ]
  }

  private func hash(_ value: String) -> String {
    value
  }

  private func isoDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)!
  }
}
