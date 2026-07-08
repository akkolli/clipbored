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
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())

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

  func testSelectingCollectionWithEmptySearchUsesIndexedVisibleItems() {
    let settings = makeSettings()
    settings.maxHistoryItems = 260
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)

    for index in 0..<220 {
      store.upsert(makeTextItem("outside indexed category \(index)", createdAt: Date(timeIntervalSince1970: Double(index))))
    }
    for index in 0..<30 {
      var item = makeTextItem("client indexed category \(index)", createdAt: Date(timeIntervalSince1970: Double(1_000 + index)))
      item.collectionName = "Client Work"
      store.upsert(item)
    }
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 250)
    viewModel.debugResetVisibleItemsPerformanceCounters()

    viewModel.selectCollection(named: "Client Work")

    XCTAssertEqual(viewModel.visibleItems.count, 30)
    XCTAssertEqual(viewModel.debugVisibleItemsFullScanCount, 0)
    XCTAssertEqual(viewModel.debugVisibleItemsIndexedLookupCount, 1)
    XCTAssertEqual(viewModel.visibleItems.first?.payload, "client indexed category 29")
  }

  func testRepeatedThirtyItemCollectionSelectionsStayOnIndexedFastPath() {
    let collectionCount = 60
    let itemsPerCollection = 30
    let settings = makeSettings()
    settings.maxHistoryItems = collectionCount * itemsPerCollection
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let collectionNames = (0..<collectionCount).map { "Client Work \($0)" }

    for (collectionIndex, collectionName) in collectionNames.enumerated() {
      for itemIndex in 0..<itemsPerCollection {
        var item = makeTextItem(
          "\(collectionName) clip \(itemIndex)",
          createdAt: Date(timeIntervalSince1970: Double((collectionIndex * itemsPerCollection) + itemIndex))
        )
        item.collectionName = collectionName
        store.upsert(item)
      }
    }
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: collectionCount * itemsPerCollection)
    viewModel.debugResetVisibleItemsPerformanceCounters()

    let start = CFAbsoluteTimeGetCurrent()
    for collectionName in collectionNames {
      viewModel.selectCollection(named: collectionName)
      XCTAssertEqual(viewModel.visibleItems.count, itemsPerCollection)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertEqual(viewModel.debugVisibleItemsFullScanCount, 0)
    XCTAssertEqual(viewModel.debugVisibleItemsIndexedLookupCount, collectionCount)
    XCTAssertLessThan(elapsed, 0.20)
  }

  func testCommandSelectedCategoriesUseIndexedUnionFastPath() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)

    let text = makeTextItem("category text", createdAt: Date(timeIntervalSince1970: 100))
    let link = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "category link",
      payload: "https://example.com/category",
      payloadHash: store.hashString("https://example.com/category"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(text)
    store.upsert(link)

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.debugResetVisibleItemsPerformanceCounters()

    viewModel.selectSortMode(.text, extending: true)
    viewModel.selectSortMode(.links, extending: true)

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["https://example.com/category", "category text"])
    XCTAssertEqual(viewModel.debugVisibleItemsFullScanCount, 0)
    XCTAssertEqual(viewModel.debugVisibleItemsIndexedLookupCount, 2)
    XCTAssertTrue(viewModel.isSortModeCategorySelected(.text))
    XCTAssertTrue(viewModel.isSortModeCategorySelected(.links))
  }

  func testCommandSelectedCustomCollectionCombinesWithCategoryFilter() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)

    var client = makeTextItem("client note", createdAt: Date(timeIntervalSince1970: 100))
    client.collectionName = "Client Work"
    let link = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "category link",
      payload: "https://example.com/category",
      payloadHash: store.hashString("https://example.com/category"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(client)
    store.upsert(link)

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.debugResetVisibleItemsPerformanceCounters()

    viewModel.selectCollection(named: "Client Work")
    viewModel.selectSortMode(.links, extending: true)

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["https://example.com/category", "client note"])
    XCTAssertEqual(viewModel.debugVisibleItemsFullScanCount, 0)
    XCTAssertEqual(viewModel.debugVisibleItemsIndexedLookupCount, 2)
    XCTAssertTrue(viewModel.isCollectionCategorySelected(named: "Client Work"))
    XCTAssertTrue(viewModel.isSortModeCategorySelected(.links))
  }

  func testEmptySearchCollectionCountSummaryUsesIndexedCounts() {
    let settings = makeSettings()
    settings.maxHistoryItems = 260
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)

    for index in 0..<220 {
      store.upsert(makeTextItem("outside indexed count \(index)", createdAt: Date(timeIntervalSince1970: Double(index))))
    }
    for index in 0..<30 {
      var item = makeTextItem("client indexed count \(index)", createdAt: Date(timeIntervalSince1970: Double(1_000 + index)))
      item.collectionName = "Client Work"
      store.upsert(item)
    }
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 250)
    viewModel.debugResetVisibleItemsPerformanceCounters()

    let counts = viewModel.collectionCountSummary()

    XCTAssertEqual(counts.count(for: .mostRecent), 250)
    XCTAssertEqual(counts.count(for: .text), 250)
    XCTAssertEqual(counts.count(named: "Client Work"), 30)
    XCTAssertEqual(viewModel.debugCollectionCountFullScanCount, 0)
    XCTAssertEqual(viewModel.debugCollectionCountIndexedLookupCount, 1)
  }

  func testComputeVisibleItemsFiltersColorClipsAndStructuredType() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let color = ClipboardItem(
      id: UUID(),
      kind: .color,
      displayText: "#0A84FF",
      payload: "#0A84FF",
      payloadHash: hash("#0A84FF"),
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Design Tool",
      imagePath: nil,
      thumbnailPath: nil
    )
    let text = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Color note",
      payload: "Color note",
      payloadHash: hash("Color note"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: "Notes",
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [text, color], query: "", sortMode: .colors).map(\.payload),
      ["#0A84FF"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [text, color], query: "type:swatch", sortMode: .mostRecent).map(\.payload),
      ["#0A84FF"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [text, color], query: "hex 0a84ff", sortMode: .mostRecent).map(\.payload),
      ["#0A84FF"]
    )
  }

  func testComputeVisibleItemsFiltersCodeSnippetsAndKeepsThemInTextView() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let code = ClipboardItem(
      id: UUID(),
      kind: .code,
      displayText: "Swift Snippet",
      payload: "func greet(name: String) -> String {\n  return \"Hi \\(name)\"\n}",
      payloadHash: hash("swift-snippet"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: "Xcode",
      imagePath: nil,
      thumbnailPath: nil
    )
    let text = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Meeting note",
      payload: "Meeting note",
      payloadHash: hash("Meeting note"),
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Notes",
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [code, text], query: "", sortMode: .code).map(\.kind),
      [.code]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [code, text], query: "", sortMode: .text).map(\.kind),
      [.code, .text]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [code, text], query: "type:snippet greet", sortMode: .mostRecent).map(\.kind),
      [.code]
    )
  }

  func testComputeVisibleItemsFiltersVideoClipsAndStructuredType() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let video = ClipboardItem(
      id: UUID(),
      kind: .video,
      displayText: "Video (12 KB)",
      payload: "/tmp/clip.mp4",
      payloadHash: hash("clip-video"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: "QuickTime Player",
      imagePath: nil,
      thumbnailPath: nil
    )
    let image = ClipboardItem(
      id: UUID(),
      kind: .image,
      displayText: "Image",
      payload: "/tmp/image.png",
      payloadHash: hash("image"),
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Preview",
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [video, image], query: "", sortMode: .videos).map(\.kind),
      [.video]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [video, image], query: "type:movie", sortMode: .mostRecent).map(\.kind),
      [.video]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: [video, image], query: "mp4", sortMode: .mostRecent).map(\.kind),
      [.video]
    )
  }

  func testSearchMatchesIndependentTokensCaseInsensitively() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())

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

  func testSearchMatchesDiacriticsInTextAndStructuredFilters() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Résumé draft",
      payload: "Candidate résumé",
      payloadHash: hash("candidate-resume"),
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Café Notes",
      imagePath: nil,
      thumbnailPath: nil,
      collectionName: "Résumé Board",
      sourceDeviceName: "MacBook Café"
    )
    let items = [item]

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "resume candidate", sortMode: .mostRecent).map(\.payload),
      ["Candidate résumé"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(
        from: items,
        query: "app:\"Cafe Notes\" device:\"MacBook Cafe\" pinboard:\"Resume Board\"",
        sortMode: .mostRecent
      ).map(\.payload),
      ["Candidate résumé"]
    )
  }

  func testStructuredSearchFiltersBySourceTypeCollectionAndPinState() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
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
        collectionName: "Useful Links",
        sourceDeviceName: "Studio Mac"
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
        collectionName: "Visual References",
        sourceDeviceName: "Design MacBook"
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
        thumbnailPath: nil,
        sourceDeviceName: "Studio Mac"
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
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "device:studio type:link", sortMode: .mostRecent).map(\.displayText),
      ["Release notes"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "device:\"Design MacBook\" app:photos", sortMode: .mostRecent).map(\.displayText),
      ["Campaign portrait"]
    )
    XCTAssertTrue(
      viewModel.computeVisibleItems(from: items, query: "app:safari type:image", sortMode: .mostRecent).isEmpty
    )
    XCTAssertTrue(
      viewModel.computeVisibleItems(from: items, query: "device:ipad", sortMode: .mostRecent).isEmpty
    )
  }

  func testQuotedStructuredSearchFiltersMatchExactValues() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let items = [
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Safari clip",
        payload: "safari",
        payloadHash: hash("safari"),
        createdAt: Date(timeIntervalSince1970: 100),
        lastUsedAt: Date(timeIntervalSince1970: 100),
        useCount: 0,
        sourceApp: "Safari",
        imagePath: nil,
        thumbnailPath: nil,
        sourceDeviceName: "Studio Mac"
      ),
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Preview clip",
        payload: "preview",
        payloadHash: hash("preview"),
        createdAt: Date(timeIntervalSince1970: 200),
        lastUsedAt: Date(timeIntervalSince1970: 200),
        useCount: 0,
        sourceApp: "Safari Technology Preview",
        imagePath: nil,
        thumbnailPath: nil,
        sourceDeviceName: "Studio MacBook"
      )
    ]

    XCTAssertEqual(
      Set(viewModel.computeVisibleItems(from: items, query: "app:safari", sortMode: .mostRecent).map(\.payload)),
      ["safari", "preview"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "app:\"Safari\"", sortMode: .mostRecent).map(\.payload),
      ["safari"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "device:\"Studio Mac\"", sortMode: .mostRecent).map(\.payload),
      ["safari"]
    )
  }

  func testStructuredSearchSupportsQuotedPinboardAndMultiValueFilters() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let items = [
      ClipboardItem(
        id: UUID(),
        kind: .url,
        displayText: "Launch link",
        payload: "https://example.com/launch",
        payloadHash: hash("launch-link"),
        createdAt: Date(timeIntervalSince1970: 100),
        lastUsedAt: Date(timeIntervalSince1970: 100),
        useCount: 0,
        sourceApp: "Safari",
        imagePath: nil,
        thumbnailPath: nil,
        collectionName: "Useful Links"
      ),
      ClipboardItem(
        id: UUID(),
        kind: .image,
        displayText: "Moodboard",
        payload: "/tmp/moodboard.png",
        payloadHash: hash("moodboard"),
        createdAt: Date(timeIntervalSince1970: 300),
        lastUsedAt: Date(timeIntervalSince1970: 300),
        useCount: 0,
        sourceApp: "Photos",
        imagePath: nil,
        thumbnailPath: nil,
        collectionName: "Read Later"
      ),
      ClipboardItem(
        id: UUID(),
        kind: .file,
        displayText: "Launch brief",
        payload: "/tmp/brief.pdf",
        payloadHash: hash("launch-brief"),
        createdAt: Date(timeIntervalSince1970: 200),
        lastUsedAt: Date(timeIntervalSince1970: 200),
        useCount: 0,
        sourceApp: "Finder",
        imagePath: nil,
        thumbnailPath: nil,
        collectionName: "Client Work"
      ),
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Standalone note",
        payload: "outside",
        payloadHash: hash("outside"),
        createdAt: Date(timeIntervalSince1970: 400),
        lastUsedAt: Date(timeIntervalSince1970: 400),
        useCount: 0,
        sourceApp: "Notes",
        imagePath: nil,
        thumbnailPath: nil
      )
    ]

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "pinboard:\"Client Work\"", sortMode: .mostRecent).map(\.displayText),
      ["Launch brief"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "pinboard:\"Useful Links\",\"Read Later\"", sortMode: .mostRecent).map(\.displayText),
      ["Moodboard", "Launch link"]
    )
    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "board:\"Client Work\" type:file,pdf", sortMode: .mostRecent).map(\.displayText),
      ["Launch brief"]
    )
    XCTAssertTrue(
      viewModel.computeVisibleItems(from: items, query: "pinboard:\"Client Work\" type:image", sortMode: .mostRecent).isEmpty
    )
  }

  func testStructuredSearchSupportsEscapedQuotesInFilterValues() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let items = [
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Quoted project note",
        payload: "vip-note",
        payloadHash: hash("vip-note"),
        createdAt: Date(timeIntervalSince1970: 100),
        lastUsedAt: Date(timeIntervalSince1970: 100),
        useCount: 0,
        sourceApp: "Research \"Lab\"",
        imagePath: nil,
        thumbnailPath: nil,
        collectionName: "Client \"VIP\""
      ),
      ClipboardItem(
        id: UUID(),
        kind: .text,
        displayText: "Plain project note",
        payload: "plain-note",
        payloadHash: hash("plain-note"),
        createdAt: Date(timeIntervalSince1970: 200),
        lastUsedAt: Date(timeIntervalSince1970: 200),
        useCount: 0,
        sourceApp: "Research Lab",
        imagePath: nil,
        thumbnailPath: nil,
        collectionName: "Client VIP"
      )
    ]

    XCTAssertEqual(
      viewModel.computeVisibleItems(
        from: items,
        query: "app:\"Research \\\"Lab\\\"\" pinboard:\"Client \\\"VIP\\\"\"",
        sortMode: .mostRecent
      ).map(\.payload),
      ["vip-note"]
    )
  }

  func testStructuredSearchFiltersByCreatedDate() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let first = makeTextItem("June twenty nine", createdAt: localDate("2026-06-29"))
    let second = makeTextItem("June thirty", createdAt: localDate("2026-06-30"))
    let third = makeTextItem("July first", createdAt: localDate("2026-07-01"))
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

  func testStructuredDateSearchUsesLocalCalendarDayBoundaries() {
    let settings = makeSettings()
    let store = makeStore(settings: settings)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: makeCacheService())
    let early = makeTextItem("Early local day", createdAt: localDate("2026-06-30", hour: 0, minute: 5))
    let late = makeTextItem("Late local day", createdAt: localDate("2026-06-30", hour: 23, minute: 55))
    let next = makeTextItem("Next local day", createdAt: localDate("2026-07-01", hour: 0, minute: 5))
    let items = [early, late, next]

    XCTAssertEqual(
      viewModel.computeVisibleItems(from: items, query: "date:2026-06-30", sortMode: .mostRecent).map(\.payload),
      ["Late local day", "Early local day"]
    )
  }

  func testVisibleItemsCallbackSeesRestoredSelectionAfterSearchNarrowsResults() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let older = makeTextItem("keep selected note", createdAt: Date(timeIntervalSince1970: 100))
    let newer = makeTextItem("other note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(older)
    store.upsert(newer)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 1)
    XCTAssertEqual(viewModel.selectedItem?.payload, "keep selected note")

    var selectedPayloadsObservedDuringVisibleCallbacks: [String?] = []
    viewModel.onVisibleItemsChanged = { _ in
      selectedPayloadsObservedDuringVisibleCallbacks.append(viewModel.selectedItem?.payload)
    }

    viewModel.searchText = "keep selected"

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["keep selected note"])
    XCTAssertEqual(viewModel.selectedIndex, 0)
    XCTAssertEqual(viewModel.selectedItem?.payload, "keep selected note")
    XCTAssertEqual(selectedPayloadsObservedDuringVisibleCallbacks, ["keep selected note"])
  }

  func testSearchTextRecomputeDoesNotNotifyCollectionRailWhenCollectionsDoNotChange() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("release note", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("meeting note", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.searchText = "release"

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["release note"])
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 0)
  }

  func testEquivalentSearchTextEditsSyncWithoutReloadingVisibleItems() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("release note", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("meeting note", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    var visibleCallbackCount = 0
    var searchTextCallbacks: [String] = []
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onSearchTextChanged = { searchTextCallbacks.append($0) }

    viewModel.searchText = "release"

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["release note"])
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(searchTextCallbacks, ["release"])

    viewModel.searchText = " Release "

    XCTAssertEqual(viewModel.searchText, " Release ")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["release note"])
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(searchTextCallbacks, ["release", " Release "])

    viewModel.searchText = "meeting"

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["meeting note"])
    XCTAssertEqual(visibleCallbackCount, 2)
    XCTAssertEqual(searchTextCallbacks, ["release", " Release ", "meeting"])
  }

  func testSelectingCollectionUsesVisibleReloadWithoutExtraCollectionCallback() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var item = makeTextItem("client note", createdAt: Date(timeIntervalSince1970: 100))
    item.collectionName = "Client Work"
    store.upsert(item)
    store.flushPersistenceForTesting()
    settings.ensureCollection(named: "Client Work")

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)
    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.selectCollection(named: "Client Work")

    XCTAssertEqual(viewModel.selectedCollectionName, "Client Work")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client note"])
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 0)
  }

  func testSortModeChangeClearsSelectedCollectionWithSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var client = makeTextItem("client text", createdAt: Date(timeIntervalSince1970: 100))
    client.collectionName = "Client Work"
    let outside = makeTextItem("outside text", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(client)
    store.upsert(outside)
    store.flushPersistenceForTesting()
    settings.ensureCollection(named: "Client Work")

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectCollection(named: "Client Work")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client text"])

    var visibleCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }

    viewModel.sortMode = .text

    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["outside text", "client text"])
    XCTAssertEqual(visibleCallbackCount, 1)
  }

  func testSortModeChangeClearsStackFilterWithSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first stack text", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second stack text", createdAt: Date(timeIntervalSince1970: 200))
    let outside = makeTextItem("outside stack text", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(first)
    store.upsert(second)
    store.upsert(outside)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)
    viewModel.selectItem(at: 2)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectStack()
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["first stack text", "second stack text"])

    var visibleCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }

    viewModel.sortMode = .text

    XCTAssertFalse(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["outside stack text", "second stack text", "first stack text"])
    XCTAssertEqual(visibleCallbackCount, 1)
  }

  func testSelectingCollectionFromStackUsesSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var client = makeTextItem("client stack text", createdAt: Date(timeIntervalSince1970: 100))
    client.collectionName = "Client Work"
    let outside = makeTextItem("outside stack text", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(client)
    store.upsert(outside)
    store.flushPersistenceForTesting()
    settings.ensureCollection(named: "Client Work")

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectStack()
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client stack text", "outside stack text"])

    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    var stackCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }
    viewModel.onStackChanged = { stackCallbackCount += 1 }

    viewModel.selectCollection(named: "Client Work")

    XCTAssertFalse(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.selectedCollectionName, "Client Work")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client stack text"])
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 0)
    XCTAssertEqual(stackCallbackCount, 0)
  }

  func testSelectingStackFromCollectionUsesSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var client = makeTextItem("client stack text", createdAt: Date(timeIntervalSince1970: 100))
    client.collectionName = "Client Work"
    let outside = makeTextItem("outside stack text", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(client)
    store.upsert(outside)
    store.flushPersistenceForTesting()
    settings.ensureCollection(named: "Client Work")

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectCollection(named: "Client Work")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client stack text"])

    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    var stackCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }
    viewModel.onStackChanged = { stackCallbackCount += 1 }

    viewModel.selectStack()

    XCTAssertTrue(viewModel.isStackFilterSelected)
    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client stack text", "outside stack text"])
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 1)
    XCTAssertEqual(stackCallbackCount, 0)
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

  func testAssignSelectedToNewCollectionUsesSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first clip", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second clip", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(first)
    store.upsert(second)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 1)

    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.assignSelected(to: "Client Work")

    XCTAssertEqual(viewModel.selectedItem?.id, first.id)
    XCTAssertEqual(viewModel.collectionNames, ["Client Work"])
    XCTAssertEqual(viewModel.collectionCount(named: "Client Work"), 1)
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 1)
    XCTAssertEqual(viewModel.statusMessage, "Added to Client Work")
  }

  func testAssignItemByIDAddsCollectionWithoutChangingSelection() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first clip", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second clip", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(first)
    store.upsert(second)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 0)

    viewModel.assignItem(withID: first.id, to: "Pinned Research")
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 2)

    XCTAssertEqual(viewModel.selectedItem?.id, second.id)
    XCTAssertEqual(viewModel.collectionNames, ["Pinned Research"])
    XCTAssertEqual(viewModel.collectionCount(named: "Pinned Research"), 1)
    XCTAssertEqual(viewModel.statusMessage, "Added to Pinned Research")
  }

  func testAssignItemByIDToNewCollectionUsesSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first clip", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second clip", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(first)
    store.upsert(second)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 0)
    XCTAssertEqual(viewModel.selectedItem?.id, second.id)

    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.assignItem(withID: first.id, to: "Pinned Research")

    XCTAssertEqual(viewModel.selectedItem?.id, second.id)
    XCTAssertEqual(viewModel.collectionNames, ["Pinned Research"])
    XCTAssertEqual(viewModel.collectionCount(named: "Pinned Research"), 1)
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 1)
    XCTAssertEqual(viewModel.statusMessage, "Added to Pinned Research")
  }

  func testCreateCollectionAddsEmptySelectableCollection() {
    let suiteName = "com.clipbored.testmodel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let settings = SettingsModel(defaults: defaults)
    settings.maxHistoryItems = 10
    settings.historyRetention = .forever
    settings.includeImageTextInSearch = false
    settings.pruneDuplicates = false
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 100)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.createCollection(named: "  Client   Work  ", colorHex: "#0A9EB8")

    XCTAssertEqual(viewModel.collectionNames, ["Client Work"])
    XCTAssertEqual(viewModel.collectionCount(named: "Client Work"), 0)
    XCTAssertEqual(viewModel.selectedCollectionName, "Client Work")
    XCTAssertTrue(viewModel.visibleItems.isEmpty)
    XCTAssertEqual(viewModel.collectionColorHex(named: "client work"), "#0A9EB8")
    XCTAssertEqual(viewModel.statusMessage, "Created Client Work")

    let restoredSettings = SettingsModel(defaults: defaults)
    let restoredViewModel = ClipboardPanelViewModel(store: store, settings: restoredSettings, cacheService: cacheService)
    waitForVisibleItems(in: restoredViewModel, count: 1)
    XCTAssertEqual(restoredViewModel.collectionNames, ["Client Work"])
    XCTAssertEqual(restoredViewModel.collectionColorHex(named: "Client Work"), "#0A9EB8")
  }

  func testCreateCollectionSelectsPinboardWithoutExtraCollectionCallback() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 100)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    var visibleCallbackCount = 0
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.createCollection(named: "Client Work", colorHex: "#0A9EB8")

    XCTAssertEqual(viewModel.collectionNames, ["Client Work"])
    XCTAssertEqual(viewModel.selectedCollectionName, "Client Work")
    XCTAssertTrue(viewModel.visibleItems.isEmpty)
    XCTAssertEqual(viewModel.statusMessage, "Created Client Work")
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(collectionCallbackCount, 0)
  }

  func testSettingsChangesRefreshPanelSortAndImageTextSearch() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var rarelyUsed = makeTextItem("rare note", createdAt: Date(timeIntervalSince1970: 100))
    rarelyUsed.useCount = 1
    rarelyUsed.lastUsedAt = Date(timeIntervalSince1970: 100)
    var oftenUsed = makeTextItem("frequent note", createdAt: Date(timeIntervalSince1970: 50))
    oftenUsed.useCount = 9
    oftenUsed.lastUsedAt = Date(timeIntervalSince1970: 50)
    let image = ClipboardItem(
      id: UUID(),
      kind: .image,
      displayText: "Screenshot",
      payload: "screenshot-path",
      payloadHash: hash("screenshot-path"),
      createdAt: Date(timeIntervalSince1970: 25),
      lastUsedAt: Date(timeIntervalSince1970: 25),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil,
      ocrText: "Receipt total"
    )
    store.upsert(rarelyUsed)
    store.upsert(oftenUsed)
    store.upsert(image)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)

    settings.defaultSortMode = .mostUsed
    waitForVisibleItems(in: viewModel, count: 3)

    XCTAssertEqual(viewModel.sortMode, .mostUsed)
    XCTAssertEqual(viewModel.visibleItems.first?.payload, "frequent note")

    viewModel.searchText = "receipt"
    XCTAssertTrue(viewModel.visibleItems.isEmpty)
    XCTAssertEqual(viewModel.collectionCount(for: .images), 0)

    settings.includeImageTextInSearch = true
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(viewModel.visibleItems.first?.kind, .image)
    XCTAssertEqual(viewModel.collectionCount(for: .images), 1)
  }

  func testAdjacentCollectionNavigationWrapsThroughPinboards() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    viewModel.createCollection(named: "Alpha", colorHex: "#0A9EB8", selectAfterCreate: false)
    viewModel.createCollection(named: "Beta", colorHex: "#3366FF", selectAfterCreate: false)

    viewModel.selectAdjacentCollection(delta: 1)

    XCTAssertEqual(viewModel.selectedCollectionName, "Alpha")
    XCTAssertEqual(viewModel.statusMessage, "Selected Alpha")

    viewModel.selectAdjacentCollection(delta: 1)
    XCTAssertEqual(viewModel.selectedCollectionName, "Beta")
    XCTAssertEqual(viewModel.statusMessage, "Selected Beta")

    viewModel.selectAdjacentCollection(delta: 1)
    XCTAssertEqual(viewModel.selectedCollectionName, "Alpha")

    viewModel.selectAdjacentCollection(delta: -1)
    XCTAssertEqual(viewModel.selectedCollectionName, "Beta")
  }

  func testAdjacentCollectionNavigationReportsEmptyState() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)

    viewModel.selectAdjacentCollection(delta: 1)

    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertEqual(viewModel.statusMessage, "No collections")
  }

  func testCompactModeToggleIsRemovedAndDoesNotPersist() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)

    XCTAssertFalse(viewModel.isCompactModeEnabled)

    viewModel.toggleCompactMode()

    XCTAssertFalse(settings.compactMode)
    XCTAssertFalse(viewModel.isCompactModeEnabled)
    XCTAssertEqual(viewModel.statusMessage, "Compact Mode was removed")

    viewModel.toggleCompactMode()

    XCTAssertFalse(settings.compactMode)
    XCTAssertFalse(viewModel.isCompactModeEnabled)
    XCTAssertEqual(viewModel.statusMessage, "Compact Mode was removed")
  }

  func testCreateTextClipAddsSearchableSelectedItem() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    viewModel.sortMode = .images
    viewModel.searchText = "old query"
    let now = Date(timeIntervalSince1970: 1_800)

    let created = viewModel.createTextClip("  Launch note  ", now: now)
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(created?.kind, .text)
    XCTAssertEqual(created?.payload, "Launch note")
    XCTAssertEqual(created?.displayText, "Launch note")
    XCTAssertEqual(created?.sourceApp, AppConfiguration.appName)
    XCTAssertEqual(created?.useCount, 0)
    XCTAssertEqual(created?.createdAt, now)
    XCTAssertEqual(viewModel.sortMode, .text)
    XCTAssertEqual(viewModel.searchText, "")
    XCTAssertEqual(viewModel.selectedItem?.id, created?.id)
    XCTAssertEqual(viewModel.visibleItems.first?.payload, "Launch note")
    XCTAssertEqual(viewModel.statusMessage, "Created text clip")
  }

  func testCreateTextClipBatchesFilterResetIntoSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let seed = makeTextItem("stack seed", createdAt: Date(timeIntervalSince1970: 100))
    store.upsert(seed)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)
    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()
    viewModel.sortMode = .images
    viewModel.selectStack()
    viewModel.searchText = "old query"
    XCTAssertTrue(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.sortMode, .images)
    XCTAssertEqual(viewModel.searchText, "old query")

    var visibleCallbackCount = 0
    var searchTextCallbacks: [String] = []
    var sortCallbacks: [ClipboardSortMode] = []
    var collectionCallbackCount = 0
    var stackCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onSearchTextChanged = { searchTextCallbacks.append($0) }
    viewModel.onSortModeChanged = { sortCallbacks.append($0) }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }
    viewModel.onStackChanged = { stackCallbackCount += 1 }

    let created = viewModel.createTextClip("Launch note", now: Date(timeIntervalSince1970: 200))

    XCTAssertEqual(created?.payload, "Launch note")
    XCTAssertFalse(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.sortMode, .text)
    XCTAssertEqual(viewModel.searchText, "")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["Launch note", "stack seed"])
    XCTAssertEqual(viewModel.selectedItem?.id, created?.id)
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(searchTextCallbacks, [""])
    XCTAssertEqual(sortCallbacks, [.text])
    XCTAssertEqual(collectionCallbackCount, 0)
    XCTAssertEqual(stackCallbackCount, 0)
    XCTAssertEqual(viewModel.statusMessage, "Created text clip")
  }

  func testCreateTextClipAddsItemToActiveCollection() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    viewModel.createCollection(named: "Client Work", colorHex: "#0A9EB8")

    let created = viewModel.createTextClip("Pinboard note", now: Date(timeIntervalSince1970: 1_900))
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(created?.collectionName, "Client Work")
    XCTAssertEqual(store.items.first?.collectionName, "Client Work")
    XCTAssertEqual(viewModel.selectedCollectionName, "Client Work")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["Pinboard note"])
    XCTAssertEqual(viewModel.collectionCount(named: "Client Work"), 1)
  }

  func testCreateTextClipMergesDuplicateIntoActiveCollection() {
    let settings = makeSettings()
    settings.pruneDuplicates = true
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var existing = makeTextItem("Reusable note", createdAt: Date(timeIntervalSince1970: 100))
    existing.payloadHash = store.hashString(existing.payload)
    store.upsert(existing)
    store.flushPersistenceForTesting()
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)
    viewModel.createCollection(named: "Client Work", colorHex: "#0A9EB8")

    let created = viewModel.createTextClip("Reusable note", now: Date(timeIntervalSince1970: 2_000))
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(store.items.count, 1)
    XCTAssertEqual(created?.id, existing.id)
    XCTAssertEqual(store.items.first?.id, existing.id)
    XCTAssertEqual(store.items.first?.collectionName, "Client Work")
    XCTAssertEqual(viewModel.selectedItem?.id, existing.id)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["Reusable note"])
  }

  func testUpdateCollectionRenamesAssignedItemsAndColor() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var research = makeTextItem("research note", createdAt: Date(timeIntervalSince1970: 100))
    research.collectionName = "Research Stack"
    let outside = makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(research)
    store.upsert(outside)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.createCollection(named: "Research Stack", colorHex: "#0A9EB8")

    viewModel.updateCollection(named: "Research Stack", to: "Product Research", colorHex: "#3366FF")
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.collectionNames, ["Product Research"])
    XCTAssertEqual(viewModel.collectionColorHex(named: "Product Research"), "#3366FF")
    XCTAssertEqual(viewModel.selectedCollectionName, "Product Research")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["research note"])
    XCTAssertEqual(viewModel.statusMessage, "Updated Product Research")
    XCTAssertEqual(store.items.first(where: { $0.payload == "research note" })?.collectionName, "Product Research")
  }

  func testUpdateSelectedCollectionUsesSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var research = makeTextItem("research note", createdAt: Date(timeIntervalSince1970: 100))
    research.collectionName = "Research Stack"
    let outside = makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(research)
    store.upsert(outside)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.createCollection(named: "Research Stack", colorHex: "#0A9EB8")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["research note"])

    var visibleCallbackPayloads: [[String]] = []
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { items in visibleCallbackPayloads.append(items.map(\.payload)) }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.updateCollection(named: "Research Stack", to: "Product Research", colorHex: "#3366FF")

    XCTAssertEqual(viewModel.collectionNames, ["Product Research"])
    XCTAssertEqual(viewModel.selectedCollectionName, "Product Research")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["research note"])
    XCTAssertEqual(visibleCallbackPayloads, [["research note"]])
    XCTAssertEqual(collectionCallbackCount, 1)
  }

  func testDeleteCollectionRemovesCollectionItemsFromHistory() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var client = makeTextItem("client note", createdAt: Date(timeIntervalSince1970: 100))
    client.collectionName = "Client Work"
    let outside = makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(client)
    store.upsert(outside)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.createCollection(named: "Client Work", colorHex: "#0A9EB8")

    viewModel.deleteCollection(named: "Client Work")
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.collectionNames, [])
    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["outside note"])
    XCTAssertEqual(store.items.map(\.payload), ["outside note"])
    XCTAssertEqual(viewModel.statusMessage, "Deleted Client Work")
  }

  func testDeleteSelectedCollectionUsesSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var client = makeTextItem("client note", createdAt: Date(timeIntervalSince1970: 100))
    client.collectionName = "Client Work"
    let outside = makeTextItem("outside note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(client)
    store.upsert(outside)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.createCollection(named: "Client Work", colorHex: "#0A9EB8")
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["client note"])

    var visibleCallbackPayloads: [[String]] = []
    var collectionCallbackCount = 0
    viewModel.onVisibleItemsChanged = { items in visibleCallbackPayloads.append(items.map(\.payload)) }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }

    viewModel.deleteCollection(named: "Client Work")

    XCTAssertEqual(viewModel.collectionNames, [])
    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["outside note"])
    XCTAssertEqual(visibleCallbackPayloads, [["outside note"]])
    XCTAssertEqual(collectionCallbackCount, 1)
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

  func testShowSelectedInClipboardClearsFiltersAndKeepsHistoryPosition() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let older = makeTextItem("release needle", createdAt: Date(timeIntervalSince1970: 100))
    let newer = makeTextItem("meeting note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(older)
    store.upsert(newer)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["meeting note", "release needle"])

    viewModel.selectItem(at: 1)
    viewModel.assignSelected(to: "Client Work")
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.selectCollection(named: "Client Work")
    viewModel.searchText = "release"

    XCTAssertTrue(viewModel.canShowSelectedInClipboard)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["release needle"])

    viewModel.showSelectedInClipboard()

    XCTAssertEqual(viewModel.searchText, "")
    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertFalse(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.sortMode, .mostRecent)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["meeting note", "release needle"])
    XCTAssertEqual(viewModel.selectedItem?.id, older.id)
    XCTAssertEqual(viewModel.selectedIndex, 1)
    XCTAssertFalse(viewModel.canShowSelectedInClipboard)
    XCTAssertEqual(viewModel.statusMessage, "Showing in Clipboard")
  }

  func testShowSelectedInClipboardBatchesFilterResetIntoSingleVisibleReload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var older = makeTextItem("release needle", createdAt: Date(timeIntervalSince1970: 100))
    older.collectionName = "Client Work"
    let newer = makeTextItem("meeting note", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(older)
    store.upsert(newer)
    store.flushPersistenceForTesting()
    settings.ensureCollection(named: "Client Work")

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.sortMode = .mostUsed
    viewModel.selectCollection(named: "Client Work")
    viewModel.searchText = "release"
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["release needle"])

    var visibleCallbackCount = 0
    var searchTextCallbacks: [String] = []
    var sortCallbacks: [ClipboardSortMode] = []
    var collectionCallbackCount = 0
    var stackCallbackCount = 0
    viewModel.onVisibleItemsChanged = { _ in visibleCallbackCount += 1 }
    viewModel.onSearchTextChanged = { searchTextCallbacks.append($0) }
    viewModel.onSortModeChanged = { sortCallbacks.append($0) }
    viewModel.onCollectionsChanged = { collectionCallbackCount += 1 }
    viewModel.onStackChanged = { stackCallbackCount += 1 }

    viewModel.showSelectedInClipboard()

    XCTAssertEqual(viewModel.searchText, "")
    XCTAssertNil(viewModel.selectedCollectionName)
    XCTAssertFalse(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.sortMode, .mostRecent)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["meeting note", "release needle"])
    XCTAssertEqual(viewModel.selectedItem?.id, older.id)
    XCTAssertEqual(viewModel.selectedIndex, 1)
    XCTAssertEqual(visibleCallbackCount, 1)
    XCTAssertEqual(searchTextCallbacks, [""])
    XCTAssertEqual(sortCallbacks, [.mostRecent])
    XCTAssertEqual(collectionCallbackCount, 1)
    XCTAssertEqual(stackCallbackCount, 0)
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

  func testSelectLastItemSelectsLastVisibleItem() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("older", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("newer", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.selectFirstItem()
    viewModel.selectLastItem()

    XCTAssertEqual(viewModel.selectedItem?.payload, "older")
  }

  func testDeleteSelectedRemovesBatchAndUndoRestoresSelection() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let oldest = makeTextItem("oldest selected delete", createdAt: Date(timeIntervalSince1970: 100))
    let middle = makeTextItem("middle kept delete", createdAt: Date(timeIntervalSince1970: 200))
    let newest = makeTextItem("newest selected delete", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(oldest)
    store.upsert(middle)
    store.upsert(newest)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)
    viewModel.selectItem(at: 0)
    viewModel.selectItem(at: 2, mode: .toggle)

    viewModel.deleteSelected()

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["middle kept delete"])
    XCTAssertEqual(viewModel.selectedItem?.payload, "middle kept delete")
    XCTAssertEqual(viewModel.statusMessage, "Deleted 2 clips")
    XCTAssertEqual(store.items.map(\.payload), ["middle kept delete"])

    viewModel.undoLastDelete()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["newest selected delete", "middle kept delete", "oldest selected delete"])
    XCTAssertEqual(viewModel.selectedItem?.payload, "newest selected delete")
    XCTAssertEqual(viewModel.selectedItemCount, 2)
    XCTAssertTrue(viewModel.isItemSelected(at: 0))
    XCTAssertFalse(viewModel.isItemSelected(at: 1))
    XCTAssertTrue(viewModel.isItemSelected(at: 2))
    XCTAssertEqual(viewModel.statusMessage, "Restored 2 clips")
    XCTAssertEqual(store.items.map(\.payload), ["newest selected delete", "middle kept delete", "oldest selected delete"])
  }

  func testClearHistorySinceRemovesRecentClips() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("old kept clear", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("recent clear", createdAt: Date(timeIntervalSince1970: 200)))
    store.upsert(makeTextItem("newest clear", createdAt: Date(timeIntervalSince1970: 300)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)

    viewModel.clearHistory(since: Date(timeIntervalSince1970: 150))

    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["old kept clear"])
    XCTAssertEqual(viewModel.selectedItem?.payload, "old kept clear")
    XCTAssertEqual(viewModel.statusMessage, "Cleared 2 clips")
    XCTAssertEqual(store.items.map(\.payload), ["old kept clear"])
  }

  func testClearAllHistoryRemovesEverythingAndReportsEmptyClear() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    store.upsert(makeTextItem("clear all one", createdAt: Date(timeIntervalSince1970: 100)))
    store.upsert(makeTextItem("clear all two", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.clearHistory(since: .distantPast)

    XCTAssertTrue(viewModel.visibleItems.isEmpty)
    XCTAssertEqual(viewModel.statusMessage, "Cleared 2 clips")
    XCTAssertTrue(store.items.isEmpty)

    viewModel.clearHistory(since: .distantPast)

    XCTAssertEqual(viewModel.statusMessage, "No clips to clear")
  }

  func testUndoLastDeleteReportsWhenNothingCanBeRestored() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)

    viewModel.undoLastDelete()

    XCTAssertEqual(viewModel.statusMessage, "Nothing to undo")
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

  func testPreviewURLForSelectedTextWritesTemporaryTextPreview() throws {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeTextItem("Preview this text\nwithout pasting", createdAt: Date(timeIntervalSince1970: 100))
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    let previewURL = try XCTUnwrap(viewModel.previewURLForSelected())
    defer { try? FileManager.default.removeItem(at: previewURL) }

    XCTAssertEqual(previewURL.pathExtension, "txt")
    XCTAssertEqual(try String(contentsOf: previewURL), item.payload)
  }

  func testLinkPreviewRequestForSelectedWebURLUsesReadableTitle() throws {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Release Notes",
      payload: "https://example.com/releases",
      payloadHash: hash("https://example.com/releases"),
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

    let request = try XCTUnwrap(viewModel.linkPreviewRequestForSelected())
    XCTAssertEqual(request.url.absoluteString, "https://example.com/releases")
    XCTAssertEqual(request.title, "Release Notes")
  }

  func testLinkPreviewRequestRejectsNonWebURL() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Mail Link",
      payload: "mailto:hello@example.com",
      payloadHash: hash("mailto:hello@example.com"),
      createdAt: Date(timeIntervalSince1970: 200),
      lastUsedAt: Date(timeIntervalSince1970: 200),
      useCount: 0,
      sourceApp: "Mail",
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertNil(viewModel.linkPreviewRequestForSelected())
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

  func testRangeSelectionCopiesSelectedClipsAsPlainTextBatch() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let oldest = makeTextItem("oldest selected clip", createdAt: Date(timeIntervalSince1970: 100))
    let middle = makeTextItem("middle selected clip", createdAt: Date(timeIntervalSince1970: 200))
    let newest = makeTextItem("newest selected clip", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(oldest)
    store.upsert(middle)
    store.upsert(newest)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)
    NSPasteboard.general.clearContents()

    viewModel.selectItem(at: 0)
    viewModel.selectItem(at: 2, mode: .range)

    XCTAssertEqual(viewModel.selectedItemCount, 3)
    XCTAssertEqual(viewModel.selectedItemIDs, [newest.id, middle.id, oldest.id])
    XCTAssertTrue(viewModel.isItemSelected(at: 1))

    viewModel.copySelectedPlainText()
    store.flushPersistenceForTesting()

    XCTAssertEqual(
      NSPasteboard.general.string(forType: .string),
      "newest selected clip\n\nmiddle selected clip\n\noldest selected clip"
    )
    XCTAssertEqual(viewModel.statusMessage, "Copied 3 selected clips as Text")
    XCTAssertEqual(store.items.first(where: { $0.id == newest.id })?.useCount, 1)
    XCTAssertEqual(store.items.first(where: { $0.id == middle.id })?.useCount, 1)
    XCTAssertEqual(store.items.first(where: { $0.id == oldest.id })?.useCount, 1)
  }

  func testMultiSelectionCopiesOriginalPasteboardItems() throws {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let text = makeTextItem("plain selected note", createdAt: Date(timeIntervalSince1970: 100))
    let link = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Selected Link",
      payload: "https://example.com/selected",
      payloadHash: hash("https://example.com/selected"),
      createdAt: Date(timeIntervalSince1970: 300),
      lastUsedAt: Date(timeIntervalSince1970: 300),
      useCount: 0,
      sourceApp: "Safari",
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(text)
    store.upsert(link)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    NSPasteboard.general.clearContents()

    viewModel.selectItem(at: 0)
    viewModel.selectItem(at: 1, mode: .toggle)
    viewModel.copySelected()
    store.flushPersistenceForTesting()

    let pasteboardItems = try XCTUnwrap(NSPasteboard.general.pasteboardItems)
    XCTAssertEqual(pasteboardItems.count, 2)
    XCTAssertEqual(pasteboardItems[0].string(forType: .URL), "https://example.com/selected")
    XCTAssertEqual(pasteboardItems[1].string(forType: .string), "plain selected note")
    XCTAssertEqual(viewModel.statusMessage, "Copied 2 selected clips")
    XCTAssertEqual(store.items.first(where: { $0.id == link.id })?.useCount, 1)
    XCTAssertEqual(store.items.first(where: { $0.id == text.id })?.useCount, 1)
  }

  func testToggleSelectionAddsSelectedClipsToStackInChosenOrder() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let oldest = makeTextItem("oldest toggle-selected clip", createdAt: Date(timeIntervalSince1970: 100))
    let middle = makeTextItem("middle toggle-selected clip", createdAt: Date(timeIntervalSince1970: 200))
    let newest = makeTextItem("newest toggle-selected clip", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(oldest)
    store.upsert(middle)
    store.upsert(newest)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)

    viewModel.selectItem(at: 0)
    viewModel.selectItem(at: 2, mode: .toggle)

    XCTAssertEqual(viewModel.selectedItemCount, 2)
    XCTAssertEqual(viewModel.selectedItemIDs, [newest.id, oldest.id])
    XCTAssertFalse(viewModel.isItemSelected(at: 1))

    viewModel.addSelectedItemsToStack()
    viewModel.selectStack()

    XCTAssertEqual(viewModel.statusMessage, "Added 2 selected clips to Stack")
    XCTAssertEqual(viewModel.stackCount, 2)
    XCTAssertEqual(viewModel.visibleItems.map(\.id), [newest.id, oldest.id])
  }

  func testSelectAllVisibleItemsSelectsShelfOrderWithoutMovingActiveCard() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let oldest = makeTextItem("oldest select-all clip", createdAt: Date(timeIntervalSince1970: 100))
    let middle = makeTextItem("middle select-all clip", createdAt: Date(timeIntervalSince1970: 200))
    let newest = makeTextItem("newest select-all clip", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(oldest)
    store.upsert(middle)
    store.upsert(newest)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)

    viewModel.selectItem(at: 1)
    viewModel.selectAllVisibleItems()

    XCTAssertEqual(viewModel.selectedIndex, 1)
    XCTAssertEqual(viewModel.selectedItem?.id, middle.id)
    XCTAssertEqual(viewModel.selectedItemIDs, [newest.id, middle.id, oldest.id])
    XCTAssertEqual(viewModel.selectedItemCount, 3)
    XCTAssertEqual(viewModel.statusMessage, "Selected 3 clips")
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

  func testStackCopiesQueuedClipsAsPlainTextBatchAndConsumesThem() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first reusable stack clip", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second reusable stack clip", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(first)
    store.upsert(second)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    NSPasteboard.general.clearContents()

    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()

    viewModel.copyStackAsText()
    store.flushPersistenceForTesting()

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "first reusable stack clip\n\nsecond reusable stack clip")
    XCTAssertEqual(viewModel.statusMessage, "Copied 2 Stack clips as Text")
    XCTAssertEqual(viewModel.stackCount, 0)
    XCTAssertEqual(store.items.first(where: { $0.id == first.id })?.useCount, 1)
    XCTAssertEqual(store.items.first(where: { $0.id == second.id })?.useCount, 1)
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

  func testRemovingVisibleStackItemRefreshesActiveStackFilter() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = makeTextItem("first stack removal clip", createdAt: Date(timeIntervalSince1970: 100))
    let second = makeTextItem("second stack removal clip", createdAt: Date(timeIntervalSince1970: 200))
    store.upsert(first)
    store.upsert(second)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)
    viewModel.selectItem(at: 1)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()
    viewModel.selectStack()
    XCTAssertEqual(viewModel.visibleItems.map(\.id), [first.id, second.id])

    var visibleCallbackPayloads: [[String]] = []
    var stackCallbackCount = 0
    viewModel.onVisibleItemsChanged = { items in visibleCallbackPayloads.append(items.map(\.payload)) }
    viewModel.onStackChanged = { stackCallbackCount += 1 }

    viewModel.selectItem(at: 0)
    viewModel.toggleSelectedStackMembership()

    XCTAssertTrue(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.stackCount, 1)
    XCTAssertEqual(viewModel.visibleItems.map(\.id), [second.id])
    XCTAssertEqual(viewModel.selectedItem?.id, second.id)
    XCTAssertEqual(viewModel.statusMessage, "Removed from Stack")
    XCTAssertEqual(visibleCallbackPayloads, [["second stack removal clip"]])
    XCTAssertEqual(stackCallbackCount, 1)
  }

  func testAddVisibleItemsToStackQueuesFilteredShelfInOrder() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let olderNeedle = makeTextItem("older visible needle", createdAt: Date(timeIntervalSince1970: 100))
    let hidden = makeTextItem("hidden meeting note", createdAt: Date(timeIntervalSince1970: 200))
    let newerNeedle = makeTextItem("newer visible needle", createdAt: Date(timeIntervalSince1970: 300))
    store.upsert(olderNeedle)
    store.upsert(hidden)
    store.upsert(newerNeedle)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 3)
    viewModel.searchText = "needle"

    XCTAssertEqual(viewModel.visibleItems.map(\.id), [newerNeedle.id, olderNeedle.id])

    viewModel.addVisibleItemsToStack()
    XCTAssertEqual(viewModel.stackCount, 2)
    XCTAssertEqual(viewModel.statusMessage, "Added 2 clips to Stack")

    viewModel.selectStack()
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["newer visible needle", "older visible needle"])

    viewModel.addVisibleItemsToStack()
    XCTAssertEqual(viewModel.stackCount, 2)
    XCTAssertEqual(viewModel.statusMessage, "Visible clips are already in Stack")
  }

  func testStackCaptureModeQueuesCapturedItemsInCopyOrder() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let first = store.upsert(makeTextItem("first captured stack clip", createdAt: Date(timeIntervalSince1970: 100)))
    let second = store.upsert(makeTextItem("second captured stack clip", createdAt: Date(timeIntervalSince1970: 200)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 2)

    viewModel.toggleStackCaptureMode()
    XCTAssertTrue(viewModel.isStackCaptureEnabled)
    XCTAssertEqual(viewModel.statusMessage, "Stack capture is on")

    viewModel.addCapturedItemToStack(first)
    viewModel.addCapturedItemToStack(second)
    XCTAssertEqual(viewModel.stackCount, 2)
    XCTAssertEqual(viewModel.statusMessage, "Captured to Stack (2 clips)")

    viewModel.selectStack()
    XCTAssertTrue(viewModel.isStackFilterSelected)
    XCTAssertEqual(viewModel.visibleItems.map(\.payload), ["first captured stack clip", "second captured stack clip"])

    viewModel.toggleStackCaptureMode()
    XCTAssertFalse(viewModel.isStackCaptureEnabled)
    XCTAssertEqual(viewModel.statusMessage, "Stack capture is off")
  }

  func testCapturedItemsAreIgnoredWhenStackCaptureModeIsOff() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = store.upsert(makeTextItem("ignored capture clip", createdAt: Date(timeIntervalSince1970: 100)))
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.addCapturedItemToStack(item)

    XCTAssertFalse(viewModel.isStackCaptureEnabled)
    XCTAssertEqual(viewModel.stackCount, 0)
  }

  func testIgnoreSelectedSourceAppAddsPreciseCaptureRule() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    var item = makeTextItem("source rule clip", createdAt: Date(timeIntervalSince1970: 100))
    item.sourceApp = "Slack"
    item.sourceAppBundleId = "com.tinyspeck.slackmacgap"
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)
    let initialIgnoredApps = settings.ignoredApps

    viewModel.ignoreSelectedSourceApp()

    XCTAssertEqual(settings.ignoredApps, initialIgnoredApps + ["com.tinyspeck.slackmacgap"])
    XCTAssertEqual(viewModel.statusMessage, "Ignored Slack for future captures")

    viewModel.ignoreSelectedSourceApp()
    XCTAssertEqual(settings.ignoredApps, initialIgnoredApps + ["com.tinyspeck.slackmacgap"])
    XCTAssertEqual(viewModel.statusMessage, "Slack is already ignored")
  }

  func testIgnoreSelectedKindAddsContentTypeCaptureRule() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .image,
      displayText: "Image",
      payload: "/tmp/image.png",
      payloadHash: hash("image"),
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Photos",
      imagePath: nil,
      thumbnailPath: nil
    )
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.ignoreSelectedKind()

    XCTAssertEqual(settings.ignoredItemKindsRaw, [ClipboardItemKind.image.rawValue])
    XCTAssertEqual(viewModel.statusMessage, "Ignored Image items for future captures")

    viewModel.ignoreSelectedKind()
    XCTAssertEqual(settings.ignoredItemKindsRaw, [ClipboardItemKind.image.rawValue])
    XCTAssertEqual(viewModel.statusMessage, "Image items are already ignored")
  }

  func testIgnoreSelectedKindKeepsAtLeastOneContentTypeCaptureRule() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let ignoredExceptText = Self.visibleItemKinds
      .filter { $0 != .text }
      .map(\.rawValue)
    settings.ignoredItemKindsRaw = ignoredExceptText
    let item = makeTextItem("last allowed kind", createdAt: Date(timeIntervalSince1970: 100))
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.ignoreSelectedKind()

    XCTAssertEqual(settings.ignoredItemKindsRaw, ignoredExceptText)
    XCTAssertEqual(viewModel.statusMessage, "At least one content type must stay enabled.")
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

  func testUpdateSelectedTitleRefreshesSearchWithoutChangingPayload() {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let item = makeMissingFileItem(useCount: 0)
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(viewModel.editableTitleForSelected(), "")
    viewModel.updateSelectedTitle(to: "  Launch   Brief  ")
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 1)

    XCTAssertEqual(viewModel.statusMessage, "Renamed clip")
    XCTAssertEqual(viewModel.selectedItem?.id, item.id)
    XCTAssertEqual(viewModel.selectedItem?.customTitle, "Launch Brief")
    XCTAssertEqual(viewModel.selectedItem?.payload, item.payload)
    XCTAssertEqual(viewModel.selectedItem?.payloadHash, item.payloadHash)

    viewModel.searchText = "launch"
    XCTAssertEqual(viewModel.visibleItems.map(\.id), [item.id])
    viewModel.searchText = "missing"
    XCTAssertEqual(viewModel.visibleItems.map(\.id), [item.id])
    viewModel.searchText = "brief"
    XCTAssertEqual(viewModel.visibleItems.map(\.id), [item.id])

    viewModel.updateSelectedTitle(to: "   ")
    store.flushPersistenceForTesting()
    waitForVisibleItems(in: viewModel, count: 0)

    XCTAssertEqual(viewModel.statusMessage, "Cleared clip title")
    XCTAssertTrue(store.items.contains { $0.id == item.id && $0.customTitle == nil && $0.payload == item.payload })
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

  func testRotateSelectedImageClockwiseUpdatesCachedImageAndPreservesMetadata() throws {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let id = UUID()
    let paths = try XCTUnwrap(cacheService.cacheImage(makeImage(width: 80, height: 40), id: id))
    let originalData = try XCTUnwrap(cacheService.data(for: paths.full))
    let originalImage = try XCTUnwrap(NSImage(data: originalData))
    var item = ClipboardItem(
      id: id,
      kind: .image,
      displayText: "Screenshot",
      payload: paths.full,
      payloadHash: "original-image-hash",
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Preview",
      imagePath: paths.full,
      thumbnailPath: paths.thumb,
      isPinned: true,
      sourceAppBundleId: "com.apple.Preview",
      ocrText: "searchable screenshot text",
      collectionName: "Client Work",
      customTitle: "Launch Image",
      sourceDeviceName: "Studio Mac"
    )
    item.customTitle = "Launch Image"
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(store: store, settings: settings, cacheService: cacheService)
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.rotateSelectedImageClockwise()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.statusMessage, "Rotated image")
    let updated = try XCTUnwrap(store.items.first)
    XCTAssertEqual(updated.id, item.id)
    XCTAssertEqual(updated.kind, .image)
    XCTAssertEqual(updated.displayText, "Screenshot")
    XCTAssertEqual(updated.imagePath, paths.full)
    XCTAssertEqual(updated.thumbnailPath, paths.thumb)
    XCTAssertEqual(updated.payload, paths.full)
    XCTAssertNotEqual(updated.payloadHash, "original-image-hash")
    XCTAssertEqual(updated.isPinned, true)
    XCTAssertEqual(updated.sourceApp, "Preview")
    XCTAssertEqual(updated.sourceAppBundleId, "com.apple.Preview")
    XCTAssertEqual(updated.ocrText, "searchable screenshot text")
    XCTAssertEqual(updated.collectionName, "Client Work")
    XCTAssertEqual(updated.customTitle, "Launch Image")
    XCTAssertEqual(updated.sourceDeviceName, "Studio Mac")

    let rotatedData = try XCTUnwrap(cacheService.data(for: paths.full))
    let rotatedImage = try XCTUnwrap(NSImage(data: rotatedData))
    XCTAssertEqual(rotatedImage.size.width, originalImage.size.height, accuracy: 0.5)
    XCTAssertEqual(rotatedImage.size.height, originalImage.size.width, accuracy: 0.5)
  }

  func testExtractTextFromSelectedImageUpdatesOCRTextAndPreservesMetadata() throws {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let id = UUID()
    let paths = try XCTUnwrap(cacheService.cacheImage(makeImage(width: 80, height: 40), id: id))
    let item = ClipboardItem(
      id: id,
      kind: .image,
      displayText: "Screenshot",
      payload: paths.full,
      payloadHash: "image-hash",
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Preview",
      imagePath: paths.full,
      thumbnailPath: paths.thumb,
      isPinned: true,
      sourceAppBundleId: "com.apple.Preview",
      ocrText: nil,
      collectionName: "Client Work",
      customTitle: "Launch Image",
      sourceDeviceName: "Studio Mac"
    )
    store.upsert(item)
    store.flushPersistenceForTesting()

    var extractionCount = 0
    let viewModel = ClipboardPanelViewModel(
      store: store,
      settings: settings,
      cacheService: cacheService,
      imageTextExtractor: { image in
        extractionCount += 1
        XCTAssertGreaterThan(image.size.width, 0)
        return "  Receipt   total\n$42   Order 1001  "
      }
    )
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.extractTextFromSelectedImage()
    store.flushPersistenceForTesting()

    XCTAssertEqual(extractionCount, 1)
    XCTAssertEqual(viewModel.statusMessage, "Extracted text from image")
    let updated = try XCTUnwrap(store.items.first)
    XCTAssertEqual(updated.id, item.id)
    XCTAssertEqual(updated.kind, .image)
    XCTAssertEqual(updated.displayText, "Screenshot")
    XCTAssertEqual(updated.imagePath, paths.full)
    XCTAssertEqual(updated.thumbnailPath, paths.thumb)
    XCTAssertEqual(updated.payload, paths.full)
    XCTAssertEqual(updated.payloadHash, "image-hash")
    XCTAssertEqual(updated.isPinned, true)
    XCTAssertEqual(updated.sourceApp, "Preview")
    XCTAssertEqual(updated.sourceAppBundleId, "com.apple.Preview")
    XCTAssertEqual(updated.ocrText, "Receipt total $42 Order 1001")
    XCTAssertEqual(updated.collectionName, "Client Work")
    XCTAssertEqual(updated.customTitle, "Launch Image")
    XCTAssertEqual(updated.sourceDeviceName, "Studio Mac")
  }

  func testExtractTextFromSelectedImageLeavesOCRTextAloneWhenNoTextIsFound() throws {
    let settings = makeSettings()
    let cacheService = makeCacheService()
    let store = makeStore(settings: settings, cacheService: cacheService)
    let id = UUID()
    let paths = try XCTUnwrap(cacheService.cacheImage(makeImage(width: 80, height: 40), id: id))
    let item = ClipboardItem(
      id: id,
      kind: .image,
      displayText: "Screenshot",
      payload: paths.full,
      payloadHash: "image-hash",
      createdAt: Date(timeIntervalSince1970: 100),
      lastUsedAt: Date(timeIntervalSince1970: 100),
      useCount: 0,
      sourceApp: "Preview",
      imagePath: paths.full,
      thumbnailPath: paths.thumb,
      ocrText: "existing text"
    )
    store.upsert(item)
    store.flushPersistenceForTesting()

    let viewModel = ClipboardPanelViewModel(
      store: store,
      settings: settings,
      cacheService: cacheService,
      imageTextExtractor: { _ in " \n\t " }
    )
    waitForVisibleItems(in: viewModel, count: 1)

    viewModel.extractTextFromSelectedImage()
    store.flushPersistenceForTesting()

    XCTAssertEqual(viewModel.statusMessage, "No text found in image")
    XCTAssertEqual(store.items.first?.ocrText, "existing text")
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
    settings.historyRetention = .forever
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

  private func makeImage(width: CGFloat, height: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor.systemOrange.setFill()
    NSRect(x: width * 0.55, y: height * 0.15, width: width * 0.3, height: height * 0.7).fill()
    image.unlockFocus()
    return image
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

  private static let visibleItemKinds: [ClipboardItemKind] = [
    .text,
    .code,
    .url,
    .image,
    .color,
    .audio,
    .video,
    .richText,
    .pdf,
    .file
  ]

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

  private func localDate(_ value: String, hour: Int = 12, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .autoupdatingCurrent
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    let date = formatter.date(from: value)!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
  }
}
