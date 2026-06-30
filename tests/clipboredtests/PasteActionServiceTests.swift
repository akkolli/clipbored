import AppKit
import CryptoKit
import XCTest
@testable import ClipBored

final class PasteActionServiceTests: XCTestCase {
  private var tempURLs: [URL] = []

  override func tearDown() {
    tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    tempURLs.removeAll()
    super.tearDown()
  }

  func testCopyWritesTextToPasteboard() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Hello",
      payload: "Hello",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello")
  }

  func testPasteboardWritersExposeTextForDragOut() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "Drag text",
      payload: "Drag text",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()

    XCTAssertTrue(pasteboard.writeObjects(service.pasteboardWriters(for: item)))
    XCTAssertEqual(pasteboard.string(forType: .string), "Drag text")
  }

  func testPasteboardWritersExposeURLAndTitleForDragOut() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Apple",
      payload: "https://apple.com",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()

    XCTAssertTrue(pasteboard.writeObjects(service.pasteboardWriters(for: item)))
    XCTAssertEqual(pasteboard.string(forType: .string), "https://apple.com")
    XCTAssertEqual(pasteboard.string(forType: .URL), "https://apple.com")
    XCTAssertEqual(
      pasteboard.string(forType: NSPasteboard.PasteboardType(rawValue: "public.url-name")),
      "Apple"
    )
  }

  func testPasteWithoutTargetCopiesWithoutRequestingAutomaticPaste() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "No target",
      payload: "No target",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.paste(item, targetApp: nil), .copied)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "No target")
  }

  func testAutomaticPasteActivatesTargetAndSchedulesKeyboardPasteWhenPermissionGranted() throws {
    var activatedProcessID: pid_t?
    let targetApp = try makeRunningTargetApp()
    var didScheduleKeyboardPaste = false
    let service = PasteActionService(
      accessibilityPermissionProvider: { true },
      targetActivator: { app in
        activatedProcessID = app.processIdentifier
        return true
      },
      keyboardPasteScheduler: { _ in
        didScheduleKeyboardPaste = true
      }
    )

    XCTAssertEqual(service.paste(makeTextItem("Paste into target"), targetApp: targetApp), .pasted)
    XCTAssertEqual(activatedProcessID, targetApp.processIdentifier)
    XCTAssertTrue(didScheduleKeyboardPaste)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Paste into target")
  }

  func testAutomaticPlainTextPasteActivatesTargetAndSchedulesKeyboardPasteWhenPermissionGranted() throws {
    var activatedProcessID: pid_t?
    let targetApp = try makeRunningTargetApp()
    var didScheduleKeyboardPaste = false
    let service = PasteActionService(
      accessibilityPermissionProvider: { true },
      targetActivator: { app in
        activatedProcessID = app.processIdentifier
        return true
      },
      keyboardPasteScheduler: { _ in
        didScheduleKeyboardPaste = true
      }
    )
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Apple",
      payload: "https://apple.com",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.pastePlainText(item, targetApp: targetApp), .pastedPlainText)
    XCTAssertEqual(activatedProcessID, targetApp.processIdentifier)
    XCTAssertTrue(didScheduleKeyboardPaste)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://apple.com")
    XCTAssertNil(NSPasteboard.general.string(forType: .URL))
  }

  func testAutomaticPasteDoesNotPostShortcutWhenTargetActivationFails() throws {
    var didAttemptActivation = false
    let targetApp = try makeRunningTargetApp()
    let service = PasteActionService(
      accessibilityPermissionProvider: { true },
      targetActivator: { _ in
        didAttemptActivation = true
        return false
      },
      keyboardPasteScheduler: { _ in
        XCTFail("Keyboard paste should not be scheduled when target activation fails")
      }
    )

    XCTAssertEqual(service.paste(makeTextItem("Activation failed"), targetApp: targetApp), .copied)
    XCTAssertTrue(didAttemptActivation)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Activation failed")
  }

  func testAutomaticPasteWithoutPermissionDoesNotActivateTarget() throws {
    let targetApp = try makeRunningTargetApp()
    let service = PasteActionService(
      accessibilityPermissionProvider: { false },
      targetActivator: { _ in
        XCTFail("Target should not be activated without Accessibility permission")
        return true
      },
      keyboardPasteScheduler: { _ in
        XCTFail("Keyboard paste should not be scheduled without Accessibility permission")
      }
    )

    XCTAssertEqual(service.paste(makeTextItem("Needs permission"), targetApp: targetApp), .copiedNeedsPermission)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Needs permission")
  }

  func testCopyMissingFileDoesNotClearExistingPasteboard() {
    let service = PasteActionService()
    let board = NSPasteboard.general
    board.clearContents()
    XCTAssertTrue(board.setString("keep me", forType: .string))

    let item = ClipboardItem(
      id: UUID(),
      kind: .file,
      displayText: "Missing file",
      payload: "/tmp/clipbored-missing-\(UUID().uuidString)",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .failed("Could not write item to clipboard."))
    XCTAssertEqual(board.string(forType: .string), "keep me")
  }

  func testCopyEmptyTextDoesNotClearExistingPasteboard() {
    let service = PasteActionService()
    let board = NSPasteboard.general
    board.clearContents()
    XCTAssertTrue(board.setString("keep me", forType: .string))

    let item = ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: "",
      payload: "",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .failed("Could not write item to clipboard."))
    XCTAssertEqual(board.string(forType: .string), "keep me")
  }

  func testCopyWritesURLType() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Apple",
      payload: "https://apple.com",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://apple.com")
    XCTAssertEqual(NSPasteboard.general.string(forType: .URL), "https://apple.com")
    XCTAssertEqual(
      NSPasteboard.general.string(forType: NSPasteboard.PasteboardType(rawValue: "public.url-name")),
      "Apple"
    )
  }

  func testCopyWritesRichTextRTFAndPlainStringFallback() throws {
    let directory = try makeTempDirectory()
    let cacheService = ClipboardCacheService(baseURL: directory, encryptionService: fixedEncryptionService())
    let attributed = NSAttributedString(
      string: "Styled clipboard text",
      attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]
    )
    let rtfData = try XCTUnwrap(
      attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    )
    let path = try XCTUnwrap(cacheService.cacheRichText(rtfData, id: UUID()))
    let service = PasteActionService(cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .richText,
      displayText: attributed.string,
      payload: path,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .rtf), rtfData)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), attributed.string)
  }

  func testCopyPlainTextStripsRichTextFormatting() throws {
    let directory = try makeTempDirectory()
    let cacheService = ClipboardCacheService(baseURL: directory, encryptionService: fixedEncryptionService())
    let attributed = NSAttributedString(
      string: "Styled clipboard text",
      attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]
    )
    let rtfData = try XCTUnwrap(
      attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    )
    let path = try XCTUnwrap(cacheService.cacheRichText(rtfData, id: UUID()))
    let service = PasteActionService(cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .richText,
      displayText: attributed.string,
      payload: path,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copyPlainText(item), .copiedPlainText)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), attributed.string)
    XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
  }

  func testCopyLegacyRichTextWritesPlainPayloadWhenRTFCacheIsUnavailable() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .richText,
      displayText: "Legacy rich text",
      payload: "Legacy rich text",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Legacy rich text")
    XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
  }

  func testCopyRichTextWithMissingCacheWritesDisplayTextInsteadOfPath() throws {
    let missingPath = try makeTempDirectory().appendingPathComponent("missing-rich-text.rtf").path
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .richText,
      displayText: "Readable rich text",
      payload: missingPath,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: missingPath))
    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Readable rich text")
  }

  func testCopyPlainTextForURLOmitsURLPasteboardTypes() {
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .url,
      displayText: "Apple",
      payload: "https://apple.com",
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copyPlainText(item), .copiedPlainText)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://apple.com")
    XCTAssertNil(NSPasteboard.general.string(forType: .URL))
    XCTAssertNil(NSPasteboard.general.string(forType: NSPasteboard.PasteboardType(rawValue: "public.url-name")))
  }

  func testCopyWritesFileReferenceType() throws {
    let fileURL = try makeTempFile(contents: "file contents")
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .file,
      displayText: fileURL.path,
      payload: fileURL.path,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    XCTAssertEqual(objects?.first?.standardizedFileURL, fileURL.standardizedFileURL)
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), fileURL.path)
  }

  func testCopyWritesMultipleFileReferences() throws {
    let firstURL = try makeTempFile(contents: "first file")
    let secondURL = try makeTempFile(contents: "second file")
    let payload = FilePayload.payload(from: [firstURL, secondURL])
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .file,
      displayText: "2 files",
      payload: payload,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    XCTAssertEqual(objects?.map(\.standardizedFileURL), [firstURL.standardizedFileURL, secondURL.standardizedFileURL])
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), payload)
  }

  func testCopyWritesPDFData() throws {
    let pdfData = Data("%PDF-1.4\nclipbored\n%%EOF".utf8)
    let fileURL = try makeTempFile(contents: pdfData)
    let service = PasteActionService()
    let item = ClipboardItem(
      id: UUID(),
      kind: .pdf,
      displayText: "PDF",
      payload: fileURL.path,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .pdf), pdfData)
  }

  func testCopyWritesAudioData() throws {
    let directory = try makeTempDirectory()
    let cacheService = ClipboardCacheService(baseURL: directory, encryptionService: fixedEncryptionService())
    let audioData = Data([1, 3, 5, 7, 9])
    let path = try XCTUnwrap(cacheService.cacheAudio(audioData, id: UUID()))
    let service = PasteActionService(cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .audio,
      displayText: "Audio",
      payload: path,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .sound), audioData)
  }

  func testCopyWritesEncryptedPDFData() throws {
    let directory = try makeTempDirectory()
    let cacheService = ClipboardCacheService(baseURL: directory, encryptionService: fixedEncryptionService())
    let pdfData = Data("%PDF-1.4\nencrypted clipbored\n%%EOF".utf8)
    let path = try XCTUnwrap(cacheService.cachePDF(pdfData, id: UUID()))
    let service = PasteActionService(cacheService: cacheService)
    let item = ClipboardItem(
      id: UUID(),
      kind: .pdf,
      displayText: "PDF",
      payload: path,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )

    XCTAssertTrue(ClipboardEncryptionService.isProtected(try Data(contentsOf: URL(fileURLWithPath: path))))
    XCTAssertEqual(service.copy(item), .copied)
    XCTAssertEqual(NSPasteboard.general.data(forType: .pdf), pdfData)
  }

  private func makeTempFile(contents: String) throws -> URL {
    try makeTempFile(contents: Data(contents.utf8))
  }

  private func makeTextItem(_ value: String) -> ClipboardItem {
    ClipboardItem(
      id: UUID(),
      kind: .text,
      displayText: value,
      payload: value,
      payloadHash: "hash",
      createdAt: Date(),
      lastUsedAt: Date(),
      useCount: 0,
      sourceApp: nil,
      imagePath: nil,
      thumbnailPath: nil
    )
  }

  private func makeRunningTargetApp() throws -> NSRunningApplication {
    try XCTUnwrap(
      NSWorkspace.shared.runningApplications.first {
        !$0.isTerminated && $0.processIdentifier > 0
      }
    )
  }

  private func makeTempFile(contents: Data) throws -> URL {
    let directory = try makeTempDirectory()
    let url = directory.appendingPathComponent("payload")
    try contents.write(to: url)
    return url
  }

  private func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboredtests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    tempURLs.append(directory)
    return directory
  }

  private func fixedEncryptionService(byte: UInt8 = 7) -> ClipboardEncryptionService {
    let keyData = Data(repeating: byte, count: 32)
    return ClipboardEncryptionService(keyProvider: { SymmetricKey(data: keyData) })
  }
}
