import AppKit
import Foundation

final class PasteActionService {
  private let cacheService: ClipboardCacheService
  private let accessibilityPermissionProvider: () -> Bool
  private let targetActivator: (NSRunningApplication) -> Bool
  private let keyboardPasteScheduler: (@escaping () -> Void) -> Void

  init(
    cacheService: ClipboardCacheService = ClipboardCacheService(),
    accessibilityPermissionProvider: @escaping () -> Bool = AccessibilityPermissionService.requestPromptIfNeeded,
    targetActivator: @escaping (NSRunningApplication) -> Bool = PasteActionService.activateForAutomaticPaste,
    keyboardPasteScheduler: @escaping (@escaping () -> Void) -> Void = { action in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        action()
      }
    }
  ) {
    self.cacheService = cacheService
    self.accessibilityPermissionProvider = accessibilityPermissionProvider
    self.targetActivator = targetActivator
    self.keyboardPasteScheduler = keyboardPasteScheduler
  }

  enum PasteActionResult: Equatable {
    case pasted
    case pastedPlainText
    case copied
    case copiedPlainText
    case copiedNeedsPermission
    case copiedPlainTextNeedsPermission
    case failed(String)

    var message: String {
      switch self {
      case .pasted:
        return "Pasted"
      case .pastedPlainText:
        return "Pasted Plain Text"
      case .copied:
        return "Copied"
      case .copiedPlainText:
        return "Copied Plain Text"
      case .copiedNeedsPermission:
        return "Copied. Grant Accessibility access to paste automatically."
      case .copiedPlainTextNeedsPermission:
        return "Copied Plain Text. Grant Accessibility access to paste automatically."
      case .failed(let message):
        return message
      }
    }
  }

  func paste(_ item: ClipboardItem, targetApp: NSRunningApplication?) -> PasteActionResult {
    guard writeToPasteboard(item) else {
      return .failed("Could not write item to clipboard.")
    }

    guard let targetApp,
          !targetApp.isTerminated else {
      return .copied
    }

    guard accessibilityPermissionProvider() else {
      return .copiedNeedsPermission
    }

    guard targetActivator(targetApp) else {
      return .copied
    }

    keyboardPasteScheduler { [weak self] in
      self?.pasteViaKeyboard()
    }
    return .pasted
  }

  func pastePlainText(_ item: ClipboardItem, targetApp: NSRunningApplication?) -> PasteActionResult {
    guard writePlainTextToPasteboard(item) else {
      return .failed("Could not write plain text to clipboard.")
    }

    guard let targetApp,
          !targetApp.isTerminated else {
      return .copiedPlainText
    }

    guard accessibilityPermissionProvider() else {
      return .copiedPlainTextNeedsPermission
    }

    guard targetActivator(targetApp) else {
      return .copiedPlainText
    }

    keyboardPasteScheduler { [weak self] in
      self?.pasteViaKeyboard()
    }
    return .pastedPlainText
  }

  @discardableResult
  func copy(_ item: ClipboardItem) -> PasteActionResult {
    writeToPasteboard(item) ? .copied : .failed("Could not write item to clipboard.")
  }

  @discardableResult
  func copyPlainText(_ item: ClipboardItem) -> PasteActionResult {
    writePlainTextToPasteboard(item) ? .copiedPlainText : .failed("Could not write plain text to clipboard.")
  }

  func pasteboardWriters(for item: ClipboardItem) -> [NSPasteboardWriting] {
    switch item.kind {
    case .image:
      guard let imagePath = item.imagePath, let image = cacheService.image(for: imagePath) else { return [] }
      return [image]

    case .pdf:
      guard let data = cacheService.data(for: item.payload) else { return [] }
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setData(data, forType: .pdf)
      pasteboardItem.setString(dragLabel(for: item), forType: .string)
      return [pasteboardItem]

    case .audio:
      guard let data = cacheService.data(for: item.payload) else { return [] }
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setData(data, forType: .sound)
      pasteboardItem.setString(dragLabel(for: item), forType: .string)
      return [pasteboardItem]

    case .color:
      guard let color = ColorPayload.color(from: item.payload) else { return [] }
      return [color]

    case .richText:
      if let data = cacheService.data(for: item.payload) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: .rtf)
        let text = richTextPlainString(from: data) ?? item.displayText.clipboardTrimmed
        if !text.isEmpty {
          pasteboardItem.setString(text, forType: .string)
        }
        return [pasteboardItem]
      }

      let fallbackText = richTextFallbackPlainString(for: item)
      return fallbackText.isEmpty ? [] : [stringPasteboardItem(fallbackText)]

    case .file:
      let urls = FilePayload.urls(from: item.payload)
      guard !urls.isEmpty, urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
        return []
      }
      return urls.map { $0.standardizedFileURL as NSURL }

    case .url:
      guard !item.payload.isEmpty else { return [] }
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setString(item.payload, forType: .string)
      pasteboardItem.setString(item.payload, forType: .URL)
      if let title = urlTitleForPasteboard(item.displayText, payload: item.payload) {
        pasteboardItem.setString(title, forType: NSPasteboard.PasteboardType(rawValue: "public.url-name"))
      }
      return [pasteboardItem]

    case .text, .unknown:
      guard !item.payload.isEmpty else { return [] }
      return [stringPasteboardItem(item.payload)]
    }
  }

  @discardableResult
  func writeToPasteboard(_ item: ClipboardItem) -> Bool {
    let board = NSPasteboard.general
    let didWrite: Bool
    switch item.kind {
    case .image:
      guard let imagePath = item.imagePath, let image = cacheService.image(for: imagePath) else { return false }
      board.clearContents()
      didWrite = board.writeObjects([image])
    case .pdf:
      guard let data = cacheService.data(for: item.payload) else { return false }
      board.clearContents()
      didWrite = board.setData(data, forType: .pdf)
    case .audio:
      guard let data = cacheService.data(for: item.payload) else { return false }
      board.clearContents()
      didWrite = board.setData(data, forType: .sound)
    case .color:
      guard let color = ColorPayload.color(from: item.payload) else { return false }
      board.clearContents()
      didWrite = board.writeObjects([color])
      if didWrite {
        board.setString(ColorPayload.displayHex(from: item.payload), forType: .string)
      }
    case .richText:
      if let data = cacheService.data(for: item.payload) {
        board.clearContents()
        let text = richTextPlainString(from: data) ?? item.displayText.clipboardTrimmed
        let wroteRTF = board.setData(data, forType: .rtf)
        if !text.isEmpty {
          _ = board.setString(text, forType: .string)
        }
        didWrite = wroteRTF
      } else {
        let fallbackText = richTextFallbackPlainString(for: item)
        guard !fallbackText.isEmpty else { return false }
        board.clearContents()
        didWrite = board.setString(fallbackText, forType: .string)
      }
    case .file:
      let urls = FilePayload.urls(from: item.payload)
      guard !urls.isEmpty, urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return false }
      board.clearContents()
      didWrite = board.writeObjects(urls.map { $0 as NSURL })
      if didWrite {
        board.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
      }
    case .url:
      guard !item.payload.isEmpty else { return false }
      board.clearContents()
      didWrite = writeURL(item.payload, title: item.displayText, to: board)
    case .text, .unknown:
      guard !item.payload.isEmpty else { return false }
      board.clearContents()
      didWrite = board.setString(item.payload, forType: .string)
    }

    if didWrite {
      ClipboardSelfWriteTracker.mark(changeCount: board.changeCount)
    }
    return didWrite
  }

  func plainText(for item: ClipboardItem) -> String? {
    switch item.kind {
    case .text, .unknown:
      return nonEmptyPlainText(item.payload) ?? nonEmptyPlainText(item.displayText)
    case .url, .file:
      return nonEmptyPlainText(item.payload) ?? nonEmptyPlainText(item.displayText)
    case .richText:
      if let data = cacheService.data(for: item.payload),
         let text = richTextPlainString(from: data) {
        return text
      }
      return nonEmptyPlainText(richTextFallbackPlainString(for: item))
    case .image:
      return nonEmptyPlainText(item.ocrText) ?? nonEmptyPlainText(item.displayText)
    case .pdf, .audio:
      return nonEmptyPlainText(item.displayText)
    case .color:
      return nonEmptyPlainText(ColorPayload.displayHex(from: item.payload)) ?? nonEmptyPlainText(item.displayText)
    }
  }

  @discardableResult
  func writePlainTextToPasteboard(_ item: ClipboardItem) -> Bool {
    guard let text = plainText(for: item) else { return false }
    let board = NSPasteboard.general
    board.clearContents()
    let didWrite = board.setString(text, forType: .string)
    if didWrite {
      ClipboardSelfWriteTracker.mark(changeCount: board.changeCount)
    }
    return didWrite
  }

  private func stringPasteboardItem(_ value: String) -> NSPasteboardItem {
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(value, forType: .string)
    return pasteboardItem
  }

  private func dragLabel(for item: ClipboardItem) -> String {
    let display = item.displayText.clipboardTrimmed
    if !display.isEmpty {
      return display
    }
    return item.kind.displayName.capitalized
  }

  private func writeURL(_ payload: String, title: String?, to board: NSPasteboard) -> Bool {
    guard !payload.isEmpty else { return false }
    let wroteString = board.setString(payload, forType: .string)
    board.setString(payload, forType: .URL)
    if let url = URL(string: payload) {
      _ = board.writeObjects([url as NSURL])
    }
    if let title = urlTitleForPasteboard(title, payload: payload) {
      board.setString(title, forType: NSPasteboard.PasteboardType(rawValue: "public.url-name"))
    }
    return wroteString
  }

  private func urlTitleForPasteboard(_ title: String?, payload: String) -> String? {
    guard let title else { return nil }
    let normalized = title.split { $0.isWhitespace }.joined(separator: " ").clipboardTrimmed
    guard !normalized.isEmpty, normalized != payload else { return nil }
    guard !normalized.contains("://") else { return nil }
    return normalized
  }

  private func nonEmptyPlainText(_ value: String?) -> String? {
    guard let value, !value.clipboardTrimmed.isEmpty else { return nil }
    return value
  }

  private func richTextPlainString(from data: Data) -> String? {
    guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
      return nil
    }
    let text = attributed.string.clipboardTrimmed
    return text.isEmpty ? nil : text
  }

  private func richTextFallbackPlainString(for item: ClipboardItem) -> String {
    let payload = item.payload.clipboardTrimmed
    if looksLikeRichTextCachePath(payload) {
      return item.displayText.clipboardTrimmed
    }
    if !payload.isEmpty {
      return payload
    }
    return item.displayText.clipboardTrimmed
  }

  private func looksLikeRichTextCachePath(_ payload: String) -> Bool {
    let url = URL(fileURLWithPath: payload)
    return payload.contains("/") && url.pathExtension.lowercased() == "rtf"
  }

  private static func activateForAutomaticPaste(_ targetApp: NSRunningApplication) -> Bool {
    if #available(macOS 14, *) {
      return targetApp.activate()
    } else {
      return targetApp.activate(options: [.activateIgnoringOtherApps])
    }
  }

  private func pasteViaKeyboard() {
    let keyCode: UInt16 = 9
    guard
      let srcDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
      let srcUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else { return }

    srcDown.flags = .maskCommand
    srcDown.post(tap: .cghidEventTap)
    srcUp.flags = .maskCommand
    srcUp.post(tap: .cghidEventTap)
  }
}
