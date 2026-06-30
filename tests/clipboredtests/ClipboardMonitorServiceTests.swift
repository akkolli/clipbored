import XCTest
import Foundation
import AppKit
@testable import ClipBored

final class ClipboardMonitorServiceTests: XCTestCase {
  private var tempURLs: [URL] = []
  private var suiteNames: [String] = []

  override func tearDown() {
    tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    tempURLs.removeAll()
    suiteNames.forEach {
      UserDefaults(suiteName: $0)?.removePersistentDomain(forName: $0)
    }
    suiteNames.removeAll()
    super.tearDown()
  }

  func testClampedIntervalEnforcesResponsiveMinimum() {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.pollProfile = .responsive

    let monitor = ClipboardMonitorService(
      store: makeStore(settings: settings),
      cacheService: ClipboardCacheService(),
      settings: settings
    )

    XCTAssertEqual(monitor.clampedInterval(0.03), AppConfiguration.minResponsiveActiveInterval)
    XCTAssertEqual(monitor.clampedInterval(0.05), AppConfiguration.minResponsiveActiveInterval)
    XCTAssertEqual(monitor.clampedInterval(0.075), AppConfiguration.minResponsiveActiveInterval)
    XCTAssertEqual(monitor.clampedInterval(0.2), 0.2)
  }

  func testClampedIntervalDoesNotIncreaseBalancedProfileWindow() {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.pollProfile = .balanced

    let monitor = ClipboardMonitorService(
      store: makeStore(settings: settings),
      cacheService: ClipboardCacheService(),
      settings: settings
    )

    XCTAssertEqual(monitor.clampedInterval(settings.pollProfile.activeInterval), settings.pollProfile.activeInterval)
    XCTAssertGreaterThanOrEqual(monitor.clampedInterval(settings.pollProfile.idleInterval), settings.pollProfile.idleInterval)
  }

  func testPollProfileChangeEmitsDedicatedNotification() {
    let settings = SettingsModel(defaults: makeTestDefaults())
    var sawPollProfileChange = false

    settings.observe { change in
      if case .pollProfile = change {
        sawPollProfileChange = true
      }
    }

    settings.pollProfile = .responsive

    XCTAssertTrue(sawPollProfileChange)
  }

  func testSetPausedReschedulesWithCurrentPollingProfile() {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.pollProfile = .battery
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)

    monitor.setPaused(false)
    XCTAssertEqual(monitor.scheduledIntervalForTesting, settings.pollProfile.idleInterval)

    settings.pollProfile = .responsive
    monitor.setPaused(false)
    XCTAssertEqual(monitor.scheduledIntervalForTesting, settings.pollProfile.idleInterval)

    monitor.stop()
  }

  func testPollNowCapturesCopiedTextOnce() {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.pruneDuplicates = false
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(
      store: store,
      cacheService: cacheService,
      settings: settings
    )
    let text = "ClipBored monitor smoke \(UUID().uuidString)"

    let captured = expectation(description: "copied text captured")
    store.observeItems { items in
      if items.contains(where: { $0.payload == text }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(text, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    monitor.pollNowAndWait()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(store.items.filter { $0.payload == text }.count, 1)
  }

  func testPollNowIgnoresClipBoredPasteboardWrites() {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Internal copy",
      payload: "Internal copy \(UUID().uuidString)",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(PasteActionService().copy(item), .copied)
    monitor.pollNowAndWait()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    XCTAssertTrue(store.items.isEmpty)
  }

  func testPollNowCapturesPDFAsRestorableAttachment() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let pdfData = Data("%PDF-1.4\nclipbored\n%%EOF".utf8)
    let captured = expectation(description: "PDF captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .pdf }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(pdfData, forType: .pdf))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    let item = try XCTUnwrap(store.items.first(where: { $0.kind == .pdf }))
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.payload))
    XCTAssertEqual(cacheService.data(for: item.payload), pdfData)
    XCTAssertEqual(PasteActionService(cacheService: cacheService).copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .pdf), pdfData)
  }

  func testPollNowCapturesAudioAsRestorableAttachment() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let audioData = Data([1, 2, 3, 4, 8, 16])
    let captured = expectation(description: "audio captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .audio }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(audioData, forType: .sound))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    let item = try XCTUnwrap(store.items.first(where: { $0.kind == .audio }))
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.payload))
    XCTAssertEqual(cacheService.data(for: item.payload), audioData)
    XCTAssertEqual(PasteActionService(cacheService: cacheService).copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .sound), audioData)
  }

  func testPollNowCapturesFileReference() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let fileURL = try makeTempFile(contents: "file reference")
    let captured = expectation(description: "file reference captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .file && $0.payload == fileURL.path }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .file)
    XCTAssertEqual(store.items.first?.payload, fileURL.path)
  }

  func testPollNowCapturesMultipleFileReferencesAsOneRestorableItem() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let firstURL = try makeTempFile(contents: "first file reference")
    let secondURL = try makeTempFile(contents: "second file reference")
    let payload = FilePayload.payload(from: [firstURL, secondURL])
    let captured = expectation(description: "multiple file references captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .file && $0.payload == payload }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([firstURL as NSURL, secondURL as NSURL]))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(item.kind, .file)
    XCTAssertEqual(item.displayText, "2 files")
    XCTAssertEqual(item.payload, payload)
    XCTAssertEqual(PasteActionService(cacheService: cacheService).copy(item), .copied)
    let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    XCTAssertEqual(objects?.map(\.standardizedFileURL), [firstURL.standardizedFileURL, secondURL.standardizedFileURL])
  }

  func testPollNowPrefersFileReferenceOverStringFallback() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let fileURL = try makeTempFile(contents: "file reference with fallback")
    let captured = expectation(description: "file reference captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .file && $0.payload == fileURL.path }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))
    XCTAssertTrue(pasteboard.setString(fileURL.path, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .file)
    XCTAssertEqual(store.items.first?.payload, fileURL.path)
  }

  func testPollNowCapturesBareURLAsLink() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let url = "https://example.com/releases"
    let captured = expectation(description: "URL captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .url && $0.payload == url }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(url, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .url)
    XCTAssertEqual(store.items.first?.payload, url)
  }

  func testPollNowUsesPasteboardURLNameAsLinkTitle() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let url = "https://example.com/releases"
    let title = "Release notes"
    let captured = expectation(description: "URL with title captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .url && $0.payload == url && $0.displayText == title }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(url, forType: .URL))
    XCTAssertTrue(pasteboard.setString(title, forType: NSPasteboard.PasteboardType(rawValue: "public.url-name")))
    XCTAssertTrue(pasteboard.setString(url, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .url)
    XCTAssertEqual(store.items.first?.displayText, title)
    XCTAssertEqual(store.items.first?.payload, url)
  }

  func testPollNowUsesHTMLAnchorTextAsLinkTitle() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let url = "https://example.com/releases"
    let title = "Read the release notes"
    let html = "<a href=\"\(url)\">\(title)</a>"
    let captured = expectation(description: "URL with HTML title captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .url && $0.payload == url && $0.displayText == title }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(url, forType: .URL))
    XCTAssertTrue(pasteboard.setString(html, forType: .html))
    XCTAssertTrue(pasteboard.setString(url, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .url)
    XCTAssertEqual(store.items.first?.displayText, title)
    XCTAssertEqual(store.items.first?.payload, url)
  }

  func testPollNowCapturesURLWithLocalImagePreviewAsLink() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let url = "https://example.com/lookbook"
    let title = "Lookbook"
    let preview = makeImage(color: .systemTeal)
    let captured = expectation(description: "URL with local preview captured")

    store.observeItems { items in
      if let item = items.first, item.kind == .url, item.payload == url, item.thumbnailPath != nil {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(url, forType: .URL))
    XCTAssertTrue(pasteboard.setString(title, forType: NSPasteboard.PasteboardType(rawValue: "public.url-name")))
    XCTAssertTrue(pasteboard.setData(try XCTUnwrap(preview.tiffRepresentation), forType: .tiff))
    XCTAssertTrue(pasteboard.setString(url, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)
    cacheService.flushForTesting()

    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(item.kind, .url)
    XCTAssertEqual(item.displayText, title)
    XCTAssertNotNil(item.imagePath)
    XCTAssertNotNil(item.thumbnailPath)
    XCTAssertNotNil(cacheService.previewThumbnail(for: item))
  }

  func testPollNowCapturesImageWithRecognizedTextWhenSearchIsEnabled() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.includeImageTextInSearch = true
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(
      store: store,
      cacheService: cacheService,
      settings: settings,
      imageTextExtractor: { _ in "  Receipt total $42\nOrder 1001  " }
    )
    let image = makeImage(color: .systemOrange)
    let captured = expectation(description: "image with recognized text captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .image && $0.ocrText == "Receipt total $42 Order 1001" }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([image]))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(item.kind, .image)
    XCTAssertEqual(item.ocrText, "Receipt total $42 Order 1001")
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.payload))
  }

  func testPollNowSkipsImageTextExtractionWhenSearchIsDisabled() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.includeImageTextInSearch = false
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    var extractionCount = 0
    let monitor = ClipboardMonitorService(
      store: store,
      cacheService: cacheService,
      settings: settings,
      imageTextExtractor: { _ in
        extractionCount += 1
        return "Should not be captured"
      }
    )
    let image = makeImage(color: .systemPurple)
    let captured = expectation(description: "image captured without recognized text")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .image }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([image]))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(item.kind, .image)
    XCTAssertNil(item.ocrText)
    XCTAssertEqual(extractionCount, 0)
  }

  func testIgnoredFileSettingDoesNotBlockWebURLObjects() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.ignoredItemKindsRaw = [ClipboardItemKind.file.rawValue]
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let url = "https://example.com/releases"
    let captured = expectation(description: "web URL captured when files are ignored")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .url && $0.payload == url }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([NSURL(string: url)!]))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .url)
    XCTAssertEqual(store.items.first?.payload, url)
  }

  func testPollNowKeepsTextContainingURLAsText() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let text = "Review https://example.com/releases before shipping"
    let captured = expectation(description: "text with URL captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .text && $0.payload == text }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(text, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .text)
    XCTAssertEqual(store.items.first?.payload, text)
  }

  func testPollNowPrefersRichTextOverPlainStringFallback() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let text = "Rich clipboard text"
    let attributed = NSAttributedString(
      string: text,
      attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
    )
    let rtfData = try XCTUnwrap(
      attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    )
    let captured = expectation(description: "rich text captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .richText && $0.displayText == text }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(rtfData, forType: .rtf))
    XCTAssertTrue(pasteboard.setString(text, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    XCTAssertEqual(store.items.first?.kind, .richText)
    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(item.displayText, text)
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.payload))
    XCTAssertEqual(cacheService.data(for: item.payload), rtfData)
    XCTAssertEqual(PasteActionService(cacheService: cacheService).copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .rtf), rtfData)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), text)
  }

  func testPollNowCapturesHTMLClipboardDataAsRestorableRichText() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    let (store, cacheService) = makeStoreAndCache(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let text = "Styled HTML clipboard text"
    let html = """
    <span style="font-weight: 700; color: #0a84ff;">Styled HTML</span> clipboard text
    """
    let htmlData = Data(html.utf8)
    let captured = expectation(description: "HTML rich text captured")

    store.observeItems { items in
      if items.contains(where: { $0.kind == .richText && $0.displayText == text }) {
        captured.fulfill()
      }
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(htmlData, forType: .html))
    XCTAssertTrue(pasteboard.setString(text, forType: .string))

    monitor.pollNowAndWait()
    wait(for: [captured], timeout: 1.0)

    let item = try XCTUnwrap(store.items.first)
    XCTAssertEqual(item.kind, .richText)
    XCTAssertEqual(item.displayText, text)
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.payload))
    let cachedRTF = try XCTUnwrap(cacheService.data(for: item.payload))
    XCTAssertNotNil(NSAttributedString(rtf: cachedRTF, documentAttributes: nil))
    XCTAssertEqual(PasteActionService(cacheService: cacheService).copy(item), .copied)
    XCTAssertNotNil(NSPasteboard.general.data(forType: .rtf))
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), text)
  }

  func testIgnoredImageKindDoesNotWriteCacheFiles() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.ignoredItemKindsRaw = [ClipboardItemKind.image.rawValue]
    let (store, cacheService, baseURL) = makeStoreCacheAndBaseURL(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let image = makeImage(color: .systemOrange)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([image]))

    monitor.pollNowAndWait()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    cacheService.flushForTesting()

    XCTAssertTrue(store.items.isEmpty)
    XCTAssertTrue(try imageCacheFileURLs(in: baseURL).isEmpty)
  }

  func testIgnoredPDFKindDoesNotWriteAttachmentFiles() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.ignoredItemKindsRaw = [ClipboardItemKind.pdf.rawValue]
    let (store, cacheService, baseURL) = makeStoreCacheAndBaseURL(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(Data("%PDF-1.4\n%%EOF".utf8), forType: .pdf))

    monitor.pollNowAndWait()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    cacheService.flushForTesting()

    XCTAssertTrue(store.items.isEmpty)
    XCTAssertTrue(try attachmentFileURLs(in: baseURL).isEmpty)
    XCTAssertEqual(settings.captureStatusMessage, "Skipped: PDF items are ignored in capture settings.")
  }

  func testIgnoredAudioKindDoesNotWriteAttachmentFiles() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.ignoredItemKindsRaw = [ClipboardItemKind.audio.rawValue]
    let (store, cacheService, baseURL) = makeStoreCacheAndBaseURL(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(Data([3, 1, 4, 1, 5]), forType: .sound))

    monitor.pollNowAndWait()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    cacheService.flushForTesting()

    XCTAssertTrue(store.items.isEmpty)
    XCTAssertTrue(try attachmentFileURLs(in: baseURL).isEmpty)
    XCTAssertEqual(settings.captureStatusMessage, "Skipped: Audio items are ignored in capture settings.")
  }

  func testIgnoredRichTextKindDoesNotWriteHTMLAttachmentFiles() throws {
    let settings = SettingsModel(defaults: makeTestDefaults())
    settings.ignoredItemKindsRaw = [ClipboardItemKind.richText.rawValue]
    let (store, cacheService, baseURL) = makeStoreCacheAndBaseURL(settings: settings)
    let monitor = ClipboardMonitorService(store: store, cacheService: cacheService, settings: settings)
    let text = "Ignored HTML clipboard text"
    let html = "<strong>Ignored HTML</strong> clipboard text"

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(Data(html.utf8), forType: .html))
    XCTAssertTrue(pasteboard.setString(text, forType: .string))

    monitor.pollNowAndWait()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    cacheService.flushForTesting()

    XCTAssertTrue(store.items.isEmpty)
    XCTAssertTrue(try attachmentFileURLs(in: baseURL).isEmpty)
    XCTAssertEqual(settings.captureStatusMessage, "Skipped: Rich Text items are ignored in capture settings.")
  }

  private func makeTestDefaults() -> UserDefaults {
    let suiteName = "com.clipbored.testmonitor.\(UUID().uuidString)"
    suiteNames.append(suiteName)
    return UserDefaults(suiteName: suiteName)!
  }

  private func makeStore(settings: SettingsModel) -> ClipboardStore {
    makeStoreAndCache(settings: settings).store
  }

  private func makeStoreAndCache(settings: SettingsModel) -> (store: ClipboardStore, cacheService: ClipboardCacheService) {
    let result = makeStoreCacheAndBaseURL(settings: settings)
    return (result.store, result.cacheService)
  }

  private func makeStoreCacheAndBaseURL(settings: SettingsModel) -> (store: ClipboardStore, cacheService: ClipboardCacheService, baseURL: URL) {
    let baseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboredtests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    tempURLs.append(baseURL)
    let cacheService = ClipboardCacheService(
      baseURL: baseURL,
      encryptionService: ClipboardEncryptionService(keyProvider: { nil })
    )
    return (
      ClipboardStore(
        settings: settings,
        cacheService: cacheService,
        baseURL: baseURL,
        encryptionService: ClipboardEncryptionService(keyProvider: { nil })
      ),
      cacheService,
      baseURL
    )
  }

  private func makeTempFile(contents: String) throws -> URL {
    let baseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboredtests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    tempURLs.append(baseURL)
    let fileURL = baseURL.appendingPathComponent("payload.txt")
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  private func imageCacheFileURLs(in baseURL: URL) throws -> [URL] {
    let imageDirectory = baseURL.appendingPathComponent("images", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)
  }

  private func attachmentFileURLs(in baseURL: URL) throws -> [URL] {
    let attachmentDirectory = baseURL.appendingPathComponent("attachments", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: attachmentDirectory, includingPropertiesForKeys: nil)
  }

  private func makeImage(color: NSColor) -> NSImage {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }
}
