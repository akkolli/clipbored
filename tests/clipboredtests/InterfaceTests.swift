import AppKit
import Carbon
import XCTest

@testable import ClipBored

final class ApplicationTests: ClipBoredTestCase {
  private typealias SettingsUI = SettingsController
  private typealias Panel = ShelfController
  private typealias Keyboard = ShelfKeyboard
  private typealias Setup = SetupController

  func testEntryPointPauseAndSetupLifecycle() {
    for changed in [AppDelegate.PresentationSurface.menuBar, .dock] {
      let plan = AppDelegate.presentationPlan(showMenuBarIcon: false, showDockIcon: false, changedSurface: changed)
      XCTAssertEqual([plan.showMenuBarIcon, plan.showDockIcon], changed == .dock ? [true, false] : [false, true])
      XCTAssertEqual(plan.activationPolicy, changed == .dock ? .accessory : .regular)
    }
    for (until, expired) in [(time(1000) as Date?, true), (time(1001), false), (nil, false)] {
      XCTAssertEqual(
        AppDelegate.shouldResumeExpiredCapturePause(isCapturePaused: true, pauseCaptureUntil: until, now: time(1000)),
        expired)
    }
    XCTAssertEqual(
      Setup.pasteStyleOpenShortcut,
      ShortcutBinding(key: "v", modifierFlags: NSEvent.ModifierFlags([.shift, .command]).rawValue))
    for apply in [false, true] {
      let settings = Preferences(defaults: makeDefaults())
      var finished = 0
      let controller = Setup(settings: settings, onOpenAccessibility: {}, onFinish: { finished += 1 })
      controller.draft.retention = .oneWeek
      controller.draft.shortcut = .pasteStyle
      for _ in 0..<2 { controller.draft.finish?(apply) }
      XCTAssertEqual(finished, 1)
      XCTAssertTrue(settings.onboardingCompleted)
      XCTAssertEqual(settings.historyRetention, apply ? .oneWeek : .oneMonth)
      XCTAssertEqual(settings.openShortcut, apply ? Setup.pasteStyleOpenShortcut : Configuration.defaultOpenShortcut)
    }
    for legacy in [false, true] {
      let defaults = makeDefaults()
      if legacy { defaults.set(Configuration.defaultHistoryLength, forKey: "maxHistoryItems") }
      let settings = Preferences(defaults: defaults)
      var changes: [Preferences.Change] = []
      settings.observe { changes.append($0) }
      XCTAssertEqual(settings.onboardingCompleted, legacy)
      if !legacy {
        settings.markOnboardingCompleted()
        XCTAssertEqual(changes, [.other])
      }
      XCTAssertTrue(defaults.bool(forKey: "onboardingCompleted"))
      XCTAssertTrue(Preferences(defaults: defaults).onboardingCompleted)
    }
  }

  func testStatusMenuOffersSettingsAndResumeWithMouseAccess() {
    XCTAssertEqual(Configuration.appName, "Goldfish")
    XCTAssertEqual(Configuration.storageName, "ClipBored")
    for (event, flags, opens) in [
      (NSEvent.EventType.leftMouseUp, NSEvent.ModifierFlags(), false), (.rightMouseUp, [], true),
      (.leftMouseUp, .control, true), (.leftMouseDragged, .control, false),
    ] { XCTAssertEqual(AppDelegate.shouldOpenStatusMenu(eventType: event, modifierFlags: flags), opens) }
    let paused = AppDelegate.statusMenuPresentation(
      historyCount: 42, isCapturePaused: true, pauseCaptureUntil: time(1300), now: time(1000),
      captureStatus: "Captured", pasteStatus: "Copied", shortcutStatus: "", accessibilityStatus: "",
      launchAtLoginStatus: "")
    XCTAssertEqual(paused.detail, "Capture is paused for 5 more minutes.")
    let menu = AppDelegate.makeStatusMenu(
      presentation: paused, isCapturePaused: true, openShortcut: Configuration.defaultOpenShortcut,
      settingsShortcut: Configuration.defaultSettingsShortcut, target: nil)
    XCTAssertEqual(menu.items.first { $0.title == "Resume Capture" }?.state, .on)
    XCTAssertTrue(menu.items.contains { $0.title == "Settings…" })
    XCTAssertTrue(menu.items.contains { $0.title == "Quit Goldfish" })
    XCTAssertFalse(menu.items.contains { $0.title == "Pause Capture" })
  }

  lazy var defaults = makeDefaults()
  lazy var settings = Preferences(defaults: defaults)
  func testPreferencesPersistenceBoundsNotificationsAndCaptureRules() {
    for (path, key, initial, change) in [
      (\Preferences.showDockIcon, "showDockIcon", false, Preferences.Change.showDockIcon),
      (\.hideFromScreenCapture, "hideFromScreenCapture", false, .hideFromScreenCapture),
      (\.includeImageTextInSearch, "includeImageTextInSearch", false, .includeImageTextInSearch),
      (\.pruneDuplicates, "pruneDuplicates", true, .pruneDuplicates),
      (\.keepFirstImage, "keepFirstImage", true, .keepFirstImage),
      (\.excludeSensitive, "excludeSensitive", false, .excludeSensitive),
      (\.clearHistoryOnQuit, "clearHistoryOnQuit", false, .clearHistoryOnQuit),
    ] { preference(path, key: key, initial: initial, value: !initial, stored: !initial, change: change) }
    preference(
      \.panelSide, key: "panelSide", initial: .right, value: .left, stored: ClipboardPanelSide.left.rawValue,
      change: .panelSide)
    preference(
      \.historyRetention, key: "historyRetentionDays", initial: .oneMonth, value: .oneWeek,
      stored: HistoryRetention.oneWeek.rawValue, change: .historyRetention)
    settings.defaultSortMode = .links
    settings.ignoredItemKindsRaw = [ClipKind.image.rawValue]
    XCTAssertEqual(Preferences(defaults: defaults).defaultSortMode, .links)
    XCTAssertEqual(Preferences(defaults: defaults).ignoredItemKindsRaw, [ClipKind.image.rawValue])
    let mib = 1024 * 1024
    limits(
      "imageCacheMaxBytes", property: \.imageCacheMaxBytes,
      cases: [(0, 120 * mib), (mib, 2 * mib), (2048 * mib, 512 * mib)])
    limits("maxHistoryItems", property: \.maxHistoryItems, cases: [(0, 300), (1, 50), (100000, 2000)])
    for enabled in [true, false] {
      settings.setCloudSyncStatus(message: "Synced 3 clips")
      settings.iCloudSyncEnabled = enabled
      XCTAssertEqual(settings.cloudSyncStatusMessage, "")
      XCTAssertEqual(Preferences(defaults: defaults).iCloudSyncEnabled, enabled)
    }
    settings.pauseCapture = true
    settings.pauseCaptureUntil = time(1_234_567)
    let restored = Preferences(defaults: defaults)
    XCTAssertTrue(restored.pauseCapture)
    XCTAssertEqual(restored.pauseCaptureUntil, time(1_234_567))
    restored.pauseCaptureUntil = nil
    XCTAssertNil(defaults.object(forKey: "pauseCaptureUntil"))
    let all = ClipKind.captureKinds.map(\.rawValue)
    let expected = all.filter { $0 != ClipKind.text.rawValue }
    for stored in [false, true] {
      let defaults = makeDefaults()
      if stored { defaults.set(all, forKey: "ignoredItemKinds") }
      let settings = Preferences(defaults: defaults)
      if !stored { settings.ignoredItemKindsRaw = all }
      XCTAssertEqual(settings.ignoredItemKindsRaw, expected)
      XCTAssertEqual(Preferences(defaults: defaults).ignoredItemKindsRaw, expected)
    }
  }
  func testBoardNormalizationColorsRenameAndDeletePersist() {
    defaults.set(["  Research   Stack  ", "research stack", "  "], forKey: "customCollectionNames")
    XCTAssertEqual(settings.customCollectionNames, ["Research Stack"])
    settings.ensureCollection(named: "  Research   Stack  ", colorHex: "0a9eb8")
    settings.ensureCollection(named: "research stack", colorHex: "#FF3355")
    settings.ensureCollection(named: "Client Work", colorHex: "invalid")
    XCTAssertEqual(settings.customCollectionNames, ["Research Stack", "Client Work"])
    XCTAssertEqual(settings.collectionColorHex(forCollectionNamed: "research stack"), "#FF3355")
    XCTAssertNil(settings.collectionColorHex(forCollectionNamed: "Client Work"))
    XCTAssertEqual(settings.updateCollection(named: "research stack", to: "Product", colorHex: "#3366FF"), "Product")
    XCTAssertNil(settings.collectionColorHex(forCollectionNamed: "Research Stack"))
    settings.deleteCollection(named: "client work")
    let restored = Preferences(defaults: defaults)
    XCTAssertEqual(restored.customCollectionNames, ["Product"])
    XCTAssertEqual(restored.collectionColorHex(forCollectionNamed: "Product"), "#3366FF")
  }
  private func preference<Value: Equatable, Stored: Equatable>(
    _ path: ReferenceWritableKeyPath<Preferences, Value>, key: String, initial: Value, value: Value, stored: Stored,
    change: Preferences.Change
  ) {
    let defaults = makeDefaults()
    let settings = Preferences(defaults: defaults)
    var changes: [Preferences.Change] = []
    settings.observe { changes.append($0) }
    XCTAssertEqual(settings[keyPath: path], initial, key)
    settings[keyPath: path] = value
    XCTAssertEqual(defaults.object(forKey: key) as? Stored, stored, key)
    XCTAssertEqual(changes, [change], key)
    XCTAssertEqual(Preferences(defaults: defaults)[keyPath: path], value, key)
  }
  private func limits<Value: BinaryInteger>(
    _ key: String, property: ReferenceWritableKeyPath<Preferences, Value>, cases: [(Int, Int)]
  ) {
    for (input, expected) in cases {
      let defaults = makeDefaults()
      defaults.set(input, forKey: key)
      XCTAssertEqual(Preferences(defaults: defaults)[keyPath: property], Value(expected))
      XCTAssertEqual(defaults.integer(forKey: key), expected)
      if input != 0 {
        let model = Preferences(defaults: makeDefaults())
        model[keyPath: property] = Value(input)
        XCTAssertEqual(model[keyPath: property], Value(expected))
      }
    }
  }
  func testStatusFailuresWarningsAndCloudPrecedence() {
    let errors: [(String) -> SettingsUI.StatusPresentation] = [
      SettingsUI.pasteStatusPresentation, SettingsUI.captureStatusPresentation, SettingsUI.dataStatusPresentation,
      SettingsUI.shortcutStatusPresentation, SettingsUI.launchAtLoginStatusPresentation,
    ]
    for render in errors { XCTAssertEqual(render("Error: operation failed").textColor, .systemRed) }
    XCTAssertEqual(SettingsUI.captureStatusPresentation(storedStatus: "Skipped: Ignored.").textColor, .systemOrange)
    XCTAssertEqual(
      SettingsUI.accessibilityPermissionStatusPresentation(storedStatus: "", isTrusted: true).textColor, .systemGreen)
    let cloud = ArchiveSyncStatus(isAvailable: false, archiveURL: nil, lastModifiedAt: nil, message: "Unavailable")
    for enabled in [false, true] {
      let status = SettingsUI.cloudSyncStatusPresentation(storedStatus: "", isSyncEnabled: enabled, cloudStatus: cloud)
      XCTAssertEqual(status.textColor, enabled ? .systemOrange : .secondaryLabelColor)
      XCTAssertEqual(status.message, enabled ? "Unavailable" : "iCloud Sync is off.")
    }
  }

  func testPanelAndPreviewGeometryScreensSpacesAndPrivacy() {
    for (screen, visible, side, shown, hidden) in [
      (
        rect(0, 0, 640, 320), rect(0, 48, 640, 220), ClipboardPanelSide.right, rect(320, 0, 320, 268),
        rect(641, 0, 320, 268)
      ), (rect(0, 0, 1512, 982), rect(80, 0, 1432, 957), .left, rect(80, 0, 336, 957), rect(-257, 0, 336, 957)),
    ] {
      let frames = Panel.panelFrames(forScreenFrame: screen, visibleFrame: visible, side: side)
      XCTAssertEqual(frames.shown, shown)
      XCTAssertEqual(frames.hidden, hidden)
    }
    for active in ["active", nil] as [String?] {
      XCTAssertEqual(
        Panel.selectedOpenScreen(explicit: active, preferred: nil, pointer: "pointer", fallback: "fallback"),
        active ?? "pointer")
      XCTAssertEqual(
        Panel.selectedReflowScreen(
          currentPanel: active, lastKnown: "last", preferred: nil, pointer: "pointer", fallback: "fallback"),
        active ?? "last")
    }
    XCTAssertEqual(Panel.panelCollectionBehavior, [.moveToActiveSpace, .fullScreenAuxiliary, .transient])
    XCTAssertEqual(Panel.panelSharingType(hideFromScreenCapture: false), .readOnly)
    XCTAssertEqual(Panel.panelSharingType(hideFromScreenCapture: true), .none)
    XCTAssertEqual(
      LinkPreviewController.previewFrame(parentFrame: rect(0, 0, 1512, 408), visibleFrame: rect(0, 0, 1512, 982)),
      rect(212, 422, 1088, 536))
  }

  func testKeyboardActionsSearchPrecedenceAndGlobalRegistration() {
    let keys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    let categories: [ShelfCategory] = [
      .mostRecent, .mostUsed, .text, .links, .images, .files, .pinned, .audio, .colors, .code,
    ]
    for (index, key) in keys.enumerated() {
      for plain in [false, true] {
        XCTAssertEqual(
          Keyboard.resolve(keyCode: key, modifiers: plain ? [.command, .shift] : .command),
          index < 9 ? .paste(index, plain: plain) : nil)
      }
      XCTAssertEqual(Keyboard.resolve(keyCode: key, modifiers: [.command, .option]), .category(categories[index]))
    }
    assertKeyboard([
      (18, [], nil), (18, [.command, .option, .shift], nil), (115, [], .move(.first, extending: false)),
      (119, [], .move(.last, extending: false)), (126, .command, .move(.first, extending: false)),
      (125, .command, .move(.last, extending: false)), (124, .shift, .move(.next, extending: true)),
      (119, .shift, .move(.last, extending: true)), (0, .command, .selectAll), (0, [], nil),
    ])
    assertKeyboard([
      (8, .command, .command(.copy)), (14, .command, .command(.edit)), (3, .command, .command(.focusSearch)),
      (5, .command, .command(.showInClipboard)), (16, .command, .command(.preview)), (31, .command, .command(.open)),
      (15, .command, .command(.rename)), (17, .command, .command(.toggleCapturePause)),
      (6, .command, .command(.undoDelete)), (123, .command, .command(.previousCollection)),
      (124, .command, .command(.nextCollection)), (8, [], nil), (36, .shift, .command(.pastePlainText)),
      (1, [.command, .shift], .command(.toggleStack)), (8, [.command, .shift], .command(.toggleStackCapture)),
      (45, [.command, .shift], .command(.newCollection)), (36, [.command, .shift], .command(.pasteStackNext)),
      (8, [.command, .option, .shift], nil), (UInt16(kVK_ANSI_Comma), .command, .settings),
      (UInt16(kVK_ANSI_Comma), [.command, .shift], nil), (53, [], .cancel), (51, [], .delete), (117, [], .delete),
      (35, [], .pin), (36, [], .paste(nil, plain: false)), (49, [], .preview),
    ])
    for (key, flags, query, expected) in [
      (UInt16(49), NSEvent.ModifierFlags(), "", Keyboard.Intent.preview), (49, [], "release", nil),
      (49, .command, "", nil), (115, [], "", nil), (119, .shift, "", nil), (0, .command, "", nil),
      (8, .command, "release", .command(.copy)), (18, .command, "release", .paste(0, plain: false)),
    ] {
      XCTAssertEqual(Keyboard.resolve(keyCode: key, modifiers: flags, editingSearch: true, searchText: query), expected)
    }
    let custom = ShortcutBinding(key: "c", modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    XCTAssertEqual(Keyboard.resolve(keyCode: 8, modifiers: .command, settingsShortcut: custom), .settings)
    for (key, expected) in [
      ("v", UInt16(kVK_ANSI_V) as UInt16?), (",", UInt16(kVK_ANSI_Comma)), ("space", nil), ("", nil),
    ] { XCTAssertEqual(ShortcutManager.virtualKeyCode(for: key), expected, key) }
    XCTAssertEqual(
      ShortcutManager.carbonModifiers(for: NSEvent.ModifierFlags([.command, .option]).rawValue),
      UInt32(cmdKey | optionKey))
    let conflict = ShortcutManager.stackCaptureShortcut
    for (binding, expected) in [
      (ShortcutBinding(key: "v", modifierFlags: 0), ShortcutManager.RegistrationStatus.unsupportedShortcut("V")),
      (ShortcutBinding(key: "v", modifierFlags: NSEvent.ModifierFlags.shift.rawValue), .unsupportedShortcut("⇧V")),
      (conflict, .conflict(conflict.displayText)),
    ] {
      let manager = ShortcutManager(onOpenClipboardPanel: {}, openShortcut: binding)
      XCTAssertEqual(manager.start(), expected)
      manager.stop()
    }
  }

  private func assertKeyboard(_ cases: [(UInt16, NSEvent.ModifierFlags, Keyboard.Intent?)]) {
    for (key, flags, expected) in cases {
      XCTAssertEqual(Keyboard.resolve(keyCode: key, modifiers: flags), expected, "key=\(key), flags=\(flags.rawValue)")
    }
  }
  private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
  }
  func testSensitiveFormatsAssignmentsAndSourceDependentOTP() {
    let cases: [(String, SensitiveContentDetector.Reason?)] = [
      ("-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----", .privateKey),
      ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456", .bearerToken),
      ("ghp_abcdefghijklmnopqrstuvwxyzABCDE1234567890", .githubToken), ("AKIA1234567890ABCDEF", .awsAccessKey),
      ("xoxb-abcdefghijklmnopqrst", .slackToken), ("sk_live_abcdefghijklmnop", .stripeKey),
      ("sk-proj-abcdefghijklmnopqrstuvwxyz1234567890", .openAIToken),
      ("AIzaabcdefghijklmnopqrstuvwxyz123456789", .googleAPIKey),
      ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature123", .jsonWebToken),
      ("4242424242424242", .creditCard), ("Card: 4242 4242 4242 4242", .creditCard), ("4242424242424241", nil),
      ("Project notes for tomorrow", nil), ("https://www.apple.com/mac/", nil),
      ("Remember to request the API key from the platform team", nil), ("Release token cleanup notes", nil),
      ("OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz", .openAIToken),
      ("client_secret: supersecretvalue", .keyword), ("refresh_token = \"abc1234567890\"", .keyword),
      ("passwd='correct-horse-battery'", .keyword),
    ]
    for (value, expected) in cases { XCTAssertEqual(SensitiveContentDetector.detect(value), expected, value) }
    XCTAssertNil(SensitiveContentDetector.detect("123456"))
    XCTAssertEqual(
      SensitiveContentDetector.detect("123456", sourceBundleId: "com.1password.1password", sourceApp: "1Password"),
      .oneTimeCode)
  }
}

final class ShelfSearchTests: ShelfTestCase {
  func testCategoryUsageKindAliasesAndTextFilters() {
    var items = [
      clip("one", at: time(1), count: 2, pinned: true), clip("two", kind: .richText, at: time(2), count: 4),
      clip("https://apple.com", kind: .url, at: time(3), count: 1), clip("file", kind: .file, at: time(4), count: 3),
      clip("audio", kind: .audio, at: time(5), count: 2), clip("four", at: time(6), pinned: true),
    ]
    for (mode, query, expected) in [
      (ShelfCategory.links, "https://", ["https://apple.com"]),
      (.mostUsed, "", ["two", "file", "audio", "one", "https://apple.com", "four"]),
      (.text, "", ["four", "two", "one"]), (.files, "", ["file"]), (.audio, "", ["audio"]),
      (.pinned, "", ["four", "one"]),
    ] { XCTAssertEqual(filtered(items, query, mode: mode).map(\.payload), expected, query) }
    resetShelf([])
    items = [
      clip("#0A84FF", kind: .color), clip("func greet() {}", kind: .code, at: time(300)),
      clip("/tmp/clip.mp4", kind: .video, at: time(200)), clip("Meeting", at: time(100)), clip("image", kind: .image),
    ]
    for (mode, query, kinds) in [
      (ShelfCategory.colors, "", [ClipKind.color]), (.mostRecent, "type:swatch", [.color]),
      (.mostRecent, "hex 0a84ff", [.color]), (.code, "", [.code]), (.text, "", [.code, .text]),
      (.mostRecent, "type:snippet greet", [.code]), (.videos, "", [.video]), (.mostRecent, "type:movie", [.video]),
      (.mostRecent, "mp4", [.video]),
    ] { XCTAssertEqual(filtered(items, query, mode: mode).map(\.kind), kinds, query) }
  }

  func testEquivalentQueriesSelectionCallbacksAndCaptureStatus() {
    textShelf("release note", "meeting note")
    shelf.selectItem(at: 1)
    let events = ShelfEvents(shelf)
    var selected: [String?] = []
    let model = shelf
    shelf.onVisibleItemsChanged = { [weak model] _ in selected.append(model?.selectedItem?.payload) }
    for (query, expected) in [("release", "release note"), (" Release ", "release note"), ("meeting", "meeting note")] {
      shelf.searchText = query
      rows([expected])
    }
    XCTAssertEqual(selected, ["release note", "meeting note"])
    XCTAssertEqual(events.searchText, ["release", " Release ", "meeting"])
    XCTAssertEqual(events.collections, 0)
    textShelf("status")
    shelf.copySelected()
    XCTAssertEqual(shelf.statusMessage, "Copied")
    let statusEvents = ShelfEvents(shelf)
    settings.setCaptureStatus(message: "Capture updated")
    eventually { statusEvents.capture == 1 }
    XCTAssertEqual(statusEvents.status, [""])
  }

  func testOCRDependentQueriesAndShowInClipboardFilterRestoration() {
    resetShelf([
      clip("rare", at: time(100), count: 1), clip("frequent", at: time(50), count: 9),
      clip("image", kind: .image, at: time(25), ocr: "Receipt total"),
    ])
    let events = ShelfEvents(shelf)
    shelf.searchText = "receipt"
    rows([])
    settings.includeImageTextInSearch = true
    rows(["image"])
    XCTAssertEqual(shelf.collectionCount(for: .images), 1)
    shelf.searchText = "type:image"
    events.visible = 0
    settings.includeImageTextInSearch = false
    rows(["image"])
    XCTAssertEqual(events.visible, 0)
    for mode in [ShelfCategory.mostRecent, .mostUsed] {
      let older = clip("release", at: time(100), collection: "Work")
      resetShelf([older, clip("meeting", at: time(200))])
      shelf.sortMode = mode
      shelf.selectCollection(named: "Work")
      shelf.searchText = "release"
      XCTAssertTrue(shelf.canShowSelectedInClipboard)
      let events = ShelfEvents(shelf)
      shelf.showSelectedInClipboard()
      rows(["meeting", "release"], selected: "release", status: "Showing in Clipboard")
      XCTAssertEqual(shelf.selectedItem?.id, older.id)
      XCTAssertNil(shelf.selectedCollectionName)
      XCTAssertFalse(shelf.canShowSelectedInClipboard)
      XCTAssertEqual(events.searchText, [""])
      XCTAssertEqual(events.sort, mode == .mostRecent ? [] : [.mostRecent])
      XCTAssertEqual([events.visible, events.collections, events.stack], [1, 1, 0])
    }
  }

  func testEditsAndBoardAssignmentsPreserveActiveIdentityAndSearch() {
    let item = textShelf("draft meeting")[0]
    shelf.updateSelectedText(to: "final launch")
    shelf.searchText = "launch"
    rows(["final launch"])
    XCTAssertEqual(shelf.selectedItem?.id, item.id)
    let file = missingFile(useCount: 0)
    resetShelf([file])
    shelf.updateSelectedTitle(to: "  Launch   Brief  ")
    XCTAssertEqual(shelf.selectedItem?.customTitle, "Launch Brief")
    XCTAssertEqual(shelf.selectedItem?.payloadHash, file.payloadHash)
    shelf.searchText = "brief"
    rows([file.payload])
    shelf.updateSelectedTitle(to: "   ")
    eventually { shelf.visibleItems.isEmpty }
    rows([], status: "Cleared clip title")
    XCTAssertTrue(store.items.contains { $0.id == file.id && $0.customTitle == nil && $0.payload == file.payload })
    resetShelf([clip("link", kind: .url, title: "Release notes", at: time(100)), clip("meeting", at: time(200))])
    shelf.selectItem(at: 1)
    shelf.assignSelected(to: "  Client   Work  ")
    XCTAssertEqual(shelf.collectionNames, ["Client Work"])
    shelf.selectCollection(named: "Client Work")
    for (query, expected) in [("release", ["link"]), ("meeting", [])] {
      shelf.searchText = query
      rows(expected)
      XCTAssertEqual(shelf.collectionCount(named: "Client Work"), expected.count)
    }
    for selected in [false, true] {
      let first = textShelf("first", "second")[0]
      shelf.selectItem(at: selected ? 1 : 0)
      let active = shelf.selectedItem?.id
      let events = ShelfEvents(shelf)
      if selected { shelf.assignSelected(to: "Work") } else { shelf.assignItem(withID: first.id, to: "Work") }
      rows(["second", "first"], selected: selected ? "first" : "second", status: "Added to Work")
      XCTAssertEqual(shelf.selectedItem?.id, active)
      XCTAssertEqual(shelf.collectionCount(named: "Work"), 1)
      XCTAssertEqual([events.visible, events.collections], [1, 1])
    }
  }

  func testSearchTokensSourcesQuotedBoardsAndDateBoundaries() {
    search([
      (
        [
          clip("Copied from github.com", title: "GitHub release token"), clip("release notes"),
          clip(
            "Candidate résumé", title: "Résumé draft", app: "Café Notes", collection: "Résumé Board",
            device: "MacBook Café"), clip("vip-note", app: "Research \"Lab\"", collection: "Client \"VIP\""),
          clip("plain-note", app: "Research Lab", collection: "Client VIP"),
        ],
        [
          "TOKEN github": ["Copied from github.com"], "resume candidate": ["Candidate résumé"],
          "app:\"Cafe Notes\" device:\"MacBook Cafe\" pinboard:\"Resume Board\"": ["Candidate résumé"],
          #"app:"Research \"Lab\"" pinboard:"Client \"VIP\"""#: ["vip-note"],
        ]
      ),
      (
        [
          clip(
            "link", kind: .url, at: time(100), app: "Safari", bundle: "com.apple.Safari", collection: "Useful Links",
            device: "Studio Mac"),
          clip(
            "image", kind: .image, at: time(300), app: "Photos", pinned: true, bundle: "com.apple.Photos",
            collection: "Read Later", device: "Design MacBook"),
          clip("file", kind: .file, at: time(200), app: "Finder", collection: "Client Work"),
          clip("preview", at: time(50), app: "Safari Technology Preview", device: "Studio MacBook"),
        ],
        [
          "app:safari": ["link", "preview"], "app:\"Safari\"": ["link"], "app:safari type:link": ["link"],
          "app:apple.photos type:photo pinned:on": ["image"], "collection:read type:image": ["image"],
          "device:studio type:link": ["link"], "device:\"Studio Mac\"": ["link"],
          "device:\"Design MacBook\" app:photos": ["image"], "app:safari type:image": [], "device:ipad": [],
          "pinboard:\"Client Work\"": ["file"], "pinboard:\"Useful Links\",\"Read Later\"": ["image", "link"],
          "board:\"Client Work\" type:file,pdf": ["file"], "pinboard:\"Client Work\" type:image": [],
        ]
      ),
      (
        [
          clip("before", at: localDate("2026-06-29")), clip("early", at: localDate("2026-06-30", hour: 0, minute: 5)),
          clip("late", at: localDate("2026-06-30", hour: 23, minute: 55)),
          clip("after", at: localDate("2026-07-01", hour: 0, minute: 5)),
        ],
        [
          "date:2026-06-30": ["late", "early"], "after:2026-06-30": ["after", "late", "early"],
          "before:2026-06-30": ["before"],
        ]
      ),
    ])

  }

  func testCategoryAndBoardTransitionsEmitPreciseCallbacks() {
    for (queue, toStack, toText, expected, collectionEvents) in [
      (false, false, false, ["client"], 0), (false, false, true, ["outside", "client"], 0),
      (true, false, false, ["client"], 0), (true, true, false, ["client", "outside"], 1),
    ] {
      resetShelf([clip("client", at: time(100), collection: "Work"), clip("outside", at: time(200))])
      if queue { queueStack(at: [1, 0]) }
      if toStack || toText { shelf.selectCollection(named: "Work") } else if queue { shelf.selectStack() }
      let events = ShelfEvents(shelf)
      if toText {
        shelf.sortMode = .text
      } else if toStack {
        shelf.selectStack()
      } else {
        shelf.selectCollection(named: "Work")
      }
      rows(expected, selected: "client")
      XCTAssertEqual(shelf.isStackFilterSelected, toStack)
      XCTAssertEqual(shelf.selectedCollectionName, toStack || toText ? nil : "Work")
      XCTAssertEqual([events.visible, events.collections, events.stack], [1, collectionEvents, 0])
    }
    for union in [false, true] {
      resetShelf([clip("research", at: time(100), collection: "Research"), clip("outside", at: time(200))])
      shelf.createCollection(named: "Research", colorHex: "#0A9EB8")
      if union { shelf.selectSortMode(.images, extending: true) }
      let events = ShelfEvents(shelf)
      shelf.updateCollection(named: "Research", to: "Product", colorHex: "#3366FF")
      rows(["research"], status: "Updated Product")
      XCTAssertEqual(shelf.selectedCollectionName, union ? nil : "Product")
      XCTAssertEqual(shelf.isCollectionCategorySelected(named: "Product"), true)
      XCTAssertEqual(shelf.collectionColorHex(named: "Product"), "#3366FF")
      XCTAssertEqual(store.items.last?.collectionName, "Product")
      XCTAssertEqual([events.visible, events.collections], [1, 1])
      shelf.deleteCollection(named: "Product")
      rows(union ? [] : ["outside"], status: "Deleted Product", stored: ["outside"])
      XCTAssertEqual(shelf.collectionNames, [])
      XCTAssertNil(shelf.selectedCollectionName)
      XCTAssertEqual([events.visible, events.collections], [2, 2])
    }
  }

  func testEmptyBoardsCreationPersistenceAndWrappedNavigation() {
    for mode in ["Selected", "Unselected", "External"] {
      textShelf("outside")
      let events = ShelfEvents(shelf)
      if mode == "External" {
        settings.ensureCollection(named: "Work", colorHex: "#0A9EB8")
      } else {
        shelf.createCollection(named: "  Work  ", colorHex: "#0A9EB8", selectAfterCreate: mode == "Selected")
      }
      rows(mode == "Selected" ? [] : ["outside"])
      XCTAssertEqual(shelf.collectionCount(named: "Work"), 0)
      XCTAssertEqual(shelf.selectedCollectionName, mode == "Selected" ? "Work" : nil)
      XCTAssertEqual([events.visible, events.collections], mode == "Selected" ? [1, 0] : [0, 1])
      let restored = Preferences(defaults: defaults)
      XCTAssertEqual(restored.customCollectionNames, ["Work"])
      XCTAssertEqual(restored.collectionColorHex(forCollectionNamed: "work"), "#0A9EB8")
    }
    resetShelf([])
    shelf.selectAdjacentCollection(delta: 1)
    XCTAssertEqual(shelf.statusMessage, "No collections")
    for name in ["Alpha", "Beta"] { shelf.createCollection(named: name, selectAfterCreate: false) }
    for (step, name) in [(1, "Alpha"), (1, "Beta"), (1, "Alpha"), (-1, "Beta")] {
      shelf.selectAdjacentCollection(delta: step)
      XCTAssertEqual(shelf.selectedCollectionName, name)
      XCTAssertEqual(shelf.statusMessage, "Selected \(name)")
    }
  }

}

class ShelfTestCase: HistoryTestCase {
  lazy var shelf = ShelfModel(store: store, settings: settings, cacheService: cache)
  override func setUp() {
    super.setUp()
    settings.pruneDuplicates = false
  }
  func storeItems(_ items: [Clip]) {
    items.forEach { store.upsert($0) }
    store.flushPersistenceForTesting()
  }
  func resetShelf(_ items: [Clip]) {
    resetHistory()
    settings.pruneDuplicates = false
    shelf = ShelfModel(store: store, settings: settings, cacheService: cache)
    storeItems(items)
    eventually { shelf.visibleItems.count == items.count }
    shelf.selectItem(at: 0)
  }
  @discardableResult func textShelf(_ payloads: String...) -> [Clip] {
    let items = payloads.enumerated().map { clip($0.element, at: time(Double($0.offset + 1) * 100)) }
    resetShelf(items)
    return items
  }
  func missingFile(useCount: Int) -> Clip {
    clip(
      tempDirectory().appendingPathComponent("missing").path, kind: .file, at: time(2000), count: useCount,
      device: "Mac")
  }
  func queueStack(at indices: [Int]) {
    for index in indices {
      shelf.selectItem(at: index)
      shelf.toggleSelectedStackMembership()
    }
  }
  func rows(
    _ payloads: [String], selected: String? = nil, count: Int? = nil, status: String? = nil, stored: [String]? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(shelf.visibleItems.map(\.payload), payloads, file: file, line: line)
    XCTAssertEqual(shelf.selectedItem?.payload, selected ?? payloads.first, file: file, line: line)
    if let count { XCTAssertEqual(shelf.selectedItemCount, count, file: file, line: line) }
    if let status { XCTAssertEqual(shelf.statusMessage, status, file: file, line: line) }
    if let stored { XCTAssertEqual(store.items.map(\.payload), stored, file: file, line: line) }
  }
  func filtered(_ items: [Clip], _ query: String, mode: ShelfCategory = .mostRecent) -> [Clip] {
    shelf.computeVisibleItems(from: items, query: query, sortMode: mode)
  }
  func search(_ cases: [(items: [Clip], queries: [String: [String]])]) {
    for (items, queries) in cases {
      resetShelf([])
      for (query, expected) in queries { XCTAssertEqual(filtered(items, query).map(\.payload), expected, query) }
    }
  }
  func localDate(_ value: String, hour: Int = 12, minute: Int = 0) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: formatter.date(from: value)!)!
  }
}

final class ShelfEvents {
  var visible = 0, collections = 0, stack = 0, selectedIndices = 0, capture = 0
  var searchText: [String] = [], status: [String] = []
  var sort: [ShelfCategory] = []
  init(_ model: ShelfModel) {
    model.onVisibleItemsChanged = { [self] _ in visible += 1 }
    model.onCollectionsChanged = { [self] in collections += 1 }
    model.onStackChanged = { [self] in stack += 1 }
    model.onSelectedIndexChanged = { [self] _ in selectedIndices += 1 }
    model.onCaptureStatusChanged = { [self] in capture += 1 }
    model.onSearchTextChanged = { [self] in searchText.append($0) }
    model.onSortModeChanged = { [self] in sort.append($0) }
    model.onStatusMessageChanged = { [self] in status.append($0) }
  }
}

final class ShelfActionTests: ShelfTestCase {
  func testEndpointSelectionDeleteUndoClearAndDuplicateRecopy() {
    textShelf("older", "newer")
    let events = ShelfEvents(shelf)
    for first in [false, true] {
      shelf.selectItem(at: first ? 1 : 0)
      if first { shelf.selectFirstItem() } else { shelf.selectLastItem() }
      XCTAssertEqual(shelf.selectedItem?.payload, first ? "newer" : "older")
      let callbacks = events.selectedIndices
      if first { shelf.selectFirstItem() } else { shelf.selectLastItem() }
      XCTAssertEqual(events.selectedIndices, callbacks + 1)
    }
    storeItems([clip("latest", at: time(300))])
    rows(["latest", "newer", "older"])
    resetShelf([])
    shelf.undoLastDelete()
    XCTAssertEqual(shelf.statusMessage, "Nothing to undo")
    textShelf("oldest", "middle", "newest")
    shelf.selectItem(at: 2, mode: .toggle)
    shelf.deleteSelected()
    rows(["middle"], status: "Deleted 2 clips", stored: ["middle"])
    shelf.undoLastDelete()
    rows(["newest", "middle", "oldest"], count: 2, status: "Restored 2 clips", stored: ["newest", "middle", "oldest"])
    XCTAssertEqual((0...2).map { shelf.isItemSelected(at: $0) }, [true, false, true])
    shelf.clearHistory(since: time(150))
    rows(["oldest"], status: "Cleared 2 clips", stored: ["oldest"])
    shelf.clearHistory(since: .distantPast)
    rows([], status: "Cleared 1 clip", stored: [])
    shelf.clearHistory(since: .distantPast)
    XCTAssertEqual(shelf.statusMessage, "No clips to clear")
    textShelf("duplicate", "unique")
    settings.pruneDuplicates = true
    storeItems([clip("duplicate", at: time(50))])
    eventually { shelf.visibleItems.first?.payload == "duplicate" }
    rows(["duplicate", "unique"], selected: "unique")
  }

  func testRangeCopySelectionOrderAndRejectedEdits() {
    let items = textShelf("oldest", "middle", "newest")
    shelf.moveSelection(2, extending: true)
    XCTAssertEqual(shelf.selectedItemIDs, items.reversed().map(\.id))
    shelf.copySelectedPlainText()
    clipboardText("newest\n\nmiddle\n\noldest")
    XCTAssertEqual(store.items.map(\.useCount), [1, 1, 1])
    textShelf("oldest", "middle", "newest")
    shelf.selectItem(at: 1)
    shelf.selectAllVisibleItems()
    rows(["newest", "middle", "oldest"], selected: "middle", count: 3, status: "Selected 3 clips")
    let file = missingFile(useCount: 0)
    resetShelf([clip("editable", at: time(100)), file])
    XCTAssertNil(shelf.editableTextForSelected())
    shelf.updateSelectedText(to: "bad edit")
    XCTAssertEqual(store.items.first?.payload, file.payload)
    shelf.selectItem(at: 1)
    shelf.updateSelectedText(to: "   \n")
    XCTAssertEqual(shelf.statusMessage, "Text clip cannot be empty")
    XCTAssertEqual(store.items.last?.payload, "editable")
  }

  func testCaptureRulesAndOptionalStackCapture() {
    resetShelf([clip("rule", app: "Slack", bundle: "com.tinyspeck.slackmacgap")])
    let ignored = settings.ignoredApps
    shelf.ignoreSelectedSourceApp()
    shelf.ignoreSelectedSourceApp()
    XCTAssertEqual(settings.ignoredApps, ignored + ["com.tinyspeck.slackmacgap"])
    XCTAssertEqual(shelf.statusMessage, "Slack is already ignored")
    resetShelf([clip("image", kind: .image)])
    shelf.ignoreSelectedKind()
    XCTAssertEqual(settings.ignoredItemKindsRaw, [ClipKind.image.rawValue])
    shelf.ignoreSelectedKind()
    XCTAssertEqual(shelf.statusMessage, "Image items are already ignored")
    textShelf("last kind")
    let allExceptText = ClipKind.captureKinds.filter { $0 != .text }.map(\.rawValue)
    settings.ignoredItemKindsRaw = allExceptText
    shelf.ignoreSelectedKind()
    XCTAssertEqual(settings.ignoredItemKindsRaw, allExceptText)
    XCTAssertEqual(shelf.statusMessage, "At least one content type must stay enabled.")
    let items = textShelf("first", "second")
    shelf.addCapturedItemToStack(items[0])
    XCTAssertEqual(shelf.stackCount, 0)
    shelf.toggleStackCaptureMode()
    XCTAssertTrue(shelf.isStackCaptureEnabled)
    items.forEach(shelf.addCapturedItemToStack)
    XCTAssertEqual(shelf.statusMessage, "Captured to Stack (2 clips)")
    shelf.selectStack()
    rows(["first", "second"], selected: "second")
    shelf.toggleStackCaptureMode()
    XCTAssertFalse(shelf.isStackCaptureEnabled)
    XCTAssertEqual(shelf.statusMessage, "Stack capture is off")
  }

  func testStackOrderFiltersQueueDeduplicationAndRemovalCallbacks() {
    textShelf("first", "second", "outside")
    queueStack(at: [2, 1])
    shelf.selectStack()
    rows(["first", "second"], selected: "second")
    shelf.searchText = "second"
    rows(["second"])
    shelf.searchText = ""
    let events = ShelfEvents(shelf)
    shelf.sortMode = .text
    rows(["outside", "second", "first"], selected: "second")
    XCTAssertFalse(shelf.isStackFilterSelected)
    XCTAssertEqual(events.visible, 1)
    textShelf("older needle", "hidden", "newer needle")
    shelf.selectItem(at: 2, mode: .toggle)
    shelf.addSelectedItemsToStack()
    shelf.selectStack()
    rows(["newer needle", "older needle"], selected: "older needle", status: "Added 2 selected clips to Stack")
    shelf.clearStack()
    shelf.sortMode = .mostRecent
    shelf.searchText = "needle"
    shelf.addVisibleItemsToStack()
    XCTAssertEqual(shelf.stackCount, 2)
    shelf.selectStack()
    rows(["newer needle", "older needle"], selected: "older needle")
    shelf.addVisibleItemsToStack()
    XCTAssertEqual(shelf.stackCount, 2)
    XCTAssertEqual(shelf.statusMessage, "Visible clips are already in Stack")
    textShelf("first", "second")
    queueStack(at: [1, 0])
    XCTAssertTrue(shelf.isItemStacked(at: 0))
    shelf.selectStack()
    let removalEvents = ShelfEvents(shelf)
    shelf.selectItem(at: 0)
    shelf.toggleSelectedStackMembership()
    rows(["second"], status: "Removed from Stack")
    XCTAssertEqual([removalEvents.visible, removalEvents.stack], [1, 1])
    shelf.clearStack()
    rows(["second", "first"], status: "Cleared Stack")
    XCTAssertEqual(shelf.stackCount, 0)
  }

  func testStackAndSelectionTransfersTrackUsageOnlyOnSuccess() throws {
    for batch in [false, true] {
      textShelf("first", "second")
      queueStack(at: [1, 0])
      if batch {
        shelf.copyStackAsText()
        clipboardText("first\n\nsecond")
      } else {
        shelf.pasteNextStackItem()
        clipboardText("first")
        XCTAssertEqual(shelf.stackCount, 1)
        shelf.copyNextStackItem()
        clipboardText("second")
      }
      XCTAssertEqual(shelf.stackCount, 0)
      XCTAssertEqual(store.items.map(\.useCount), [1, 1])
    }
    let transfers: [(action: (ShelfModel) -> Void, plain: Bool)] = [
      ({ $0.copySelected() }, false), ({ $0.copySelectedPlainText() }, true), ({ $0.pasteItem(at: 1) }, false),
      ({ $0.pasteItem(at: 1, plainText: true) }, true), ({ $0.pasteSelected() }, false),
    ]
    for (action, plain) in transfers {
      let link = clip("https://example.com", kind: .url, at: time(100))
      resetShelf([link, clip("other", at: time(200))])
      var hidden = false
      shelf.willPasteToTarget = { hidden = true }
      shelf.selectItem(at: 1)
      action(shelf)
      clipboardText(link.payload, url: plain ? nil : link.payload)
      XCTAssertFalse(hidden)
      XCTAssertEqual(store.items.first { $0.id == link.id }?.useCount, 1)
    }
    for paste in [false, true] {
      let item = missingFile(useCount: 2)
      resetShelf([item])
      var hidden = false
      shelf.willPasteToTarget = { hidden = true }
      if paste { shelf.pasteSelected() } else { shelf.copySelected() }
      XCTAssertEqual(shelf.statusMessage, "Could not write item to clipboard.")
      XCTAssertFalse(hidden)
      XCTAssertEqual(try XCTUnwrap(store.items.first), item)
    }
  }

  func testCaptureSearchAndCopyFlow() {
    let monitor = CaptureMonitor(store: store, cacheService: cache, settings: settings)
    let text = "capture flow \(UUID().uuidString)"
    clipboard.clearContents()
    XCTAssertTrue(clipboard.setString(text, forType: .string))
    monitor.pollNowAndWait()
    eventually { store.items.filter { $0.payload == text }.count == 1 }
    shelf.searchText = text
    rows([text])
    shelf.copySelected()
    clipboardText(text)
    XCTAssertEqual(store.items.first?.useCount, 2)
  }

  func testBackgroundThumbnailCoalescingAndImageActionsPreserveMetadata() throws {
    let started = expectation(description: "Loader called exactly once")
    let completed = expectation(description: "Both requests completed")
    completed.expectedFulfillmentCount = 2
    let gate = DispatchSemaphore(value: 0)
    let model = ShelfModel(
      store: store, settings: settings, cacheService: cache,
      thumbnailLoader: { _ in
        XCTAssertFalse(Thread.isMainThread)
        started.fulfill()
        _ = gate.wait(timeout: .now() + 2)
        return NSImage(size: NSSize(width: 20, height: 20))
      })
    let item = clip("image", kind: .image, thumbnail: "/tmp/thumbnail.png")
    let callback: (NSImage?) -> Void = { image in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNotNil(image)
      completed.fulfill()
    }
    model.loadThumbnail(for: item, completion: callback)
    wait(for: [started], timeout: 1)
    model.loadThumbnail(for: item, completion: callback)
    gate.signal()
    wait(for: [completed], timeout: 2)
    for action in ["Rotate", "OCR", "Empty OCR"] {
      resetShelf([])
      var expected = try cachedImage(using: cache, width: 80, height: 40)
      let originalSize = try XCTUnwrap(cache.image(for: expected.payload)).size
      storeItems([expected])
      eventually { shelf.visibleItems.count == 1 }
      var calls = 0
      let model = ShelfModel(
        store: store, settings: settings, cacheService: cache,
        imageTextExtractor: { image in
          calls += 1
          XCTAssertGreaterThan(image.size.width, 0)
          return action == "OCR" ? "  Receipt   total\n$42  " : " \n\t "
        })
      let done = expectation(description: action)
      if action == "Rotate" {
        model.rotateSelectedImageClockwise(completion: done.fulfill)
      } else {
        model.extractTextFromSelectedImage(completion: done.fulfill)
      }
      wait(for: [done], timeout: 2)
      let actual = try XCTUnwrap(store.items.first)
      if action == "Rotate" {
        XCTAssertNotEqual(actual.payloadHash, expected.payloadHash)
        expected.payloadHash = actual.payloadHash
        XCTAssertEqual(
          try XCTUnwrap(cache.image(for: expected.payload)).size,
          NSSize(width: originalSize.height, height: originalSize.width))
      } else {
        XCTAssertEqual(calls, 1)
        if action == "OCR" { expected.ocrText = "Receipt total $42" }
      }
      XCTAssertEqual(actual, expected)
      XCTAssertEqual(
        model.statusMessage,
        action == "Rotate" ? "Rotated image" : action == "OCR" ? "Extracted text from image" : "No text found in image")
    }
  }

  func testLinkPreviewsNativeContextSearchAndMultipleFileDrag() throws {
    textShelf("Preview text\nwithout pasting")
    XCTAssertNotNil(shelf.previewURLForSelected())
    for url in ["https://example.com", "mailto:hello@example.com"] {
      resetShelf([clip(url, kind: .url, title: "Release Notes")])
      let request = shelf.linkPreviewRequestForSelected()
      XCTAssertEqual(request?.url.absoluteString, url.hasPrefix("https:") ? url : nil)
      XCTAssertEqual(request?.title, url.hasPrefix("https:") ? "Release Notes" : nil)
    }
    let menuPanel = nativeShelf([clip("Alpha"), clip("Beta"), clip("Gamma")])
    menuPanel.viewModel.selectItem(at: 2, mode: .toggle)
    let selected = menuPanel.viewModel.selectedItemIDs
    let menu = try XCTUnwrap(menuPanel.clipMenu(at: 0))
    XCTAssertEqual(menuPanel.viewModel.selectedItemIDs, selected)
    for title in ["Paste Selection", "Add Selection to Stack", "Capture Rules"] {
      XCTAssertTrue(menu.items.contains { $0.title == title })
    }
    menuPanel.startSearchFromShelf("Beta")
    XCTAssertEqual(menuPanel.viewModel.visibleItems.map(\.payload), ["Beta"])
    XCTAssertFalse(menuPanel.searchField.isHidden)
    let files = try ["one", "two"].map { try tempFile(contents: $0) }
    let item = clip(FilePayload.payload(from: files), kind: .file)
    let panel = nativeShelf([item])
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertTrue(panel.tableView(panel.table, writeRowsWith: IndexSet(integer: 0), to: board))
    XCTAssertEqual(Set(board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []), Set(files))
    XCTAssertEqual(board.string(forType: ClipboardItemDragPasteboard.itemIDType), item.id.uuidString)
  }

  func testNativeHoverKeepsSelectionAndMaterializesOnlyVisibleRows() {
    let panel = nativeShelf((0..<1000).map { clip("Clip \($0)", at: time(Double($0))) })
    let selected = panel.viewModel.selectedItemIDs
    panel.setHoverRow(2)
    XCTAssertEqual(panel.viewModel.selectedItemIDs, selected)
    XCTAssertEqual(panel.tableView(panel.table, heightOfRow: 2), 220)
    XCTAssertEqual(panel.table.numberOfRows, 1000)
    var materialized = 0
    panel.table.enumerateAvailableRowViews { _, _ in materialized += 1 }
    XCTAssertLessThan(materialized, 30)
    XCTAssertGreaterThan(panel.listScroll.frame.height, 400)
    XCTAssertGreaterThan(panel.listScroll.frame.width, 200)
    withExtendedLifetime(panel) { drainMainQueue() }
  }

  func testSettingsDraftRefreshCommitAndShortcutValidation() {
    let controller = SettingsController(settings: settings, store: store, cacheService: cache)
    let form = controller.form
    settings.ignoredApps = ["Safari"]
    controller.refreshFromSettings()
    XCTAssertEqual(form.ignoredApps, "Safari")
    form.ignoredApps = "Draft App, com.example.draft\n Second App"
    form.shortcuts[0].key = "B"
    settings.ignoredApps = ["Mail"]
    settings.openShortcut = ShortcutBinding(key: "k", modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    settings.setCaptureStatus(message: "Captured")
    controller.refreshFromSettings()
    XCTAssertEqual(form.ignoredApps, "Draft App, com.example.draft\n Second App")
    XCTAssertEqual(form.shortcuts[0].key, "B")
    controller.commitPendingEditorDrafts()
    XCTAssertEqual(settings.ignoredApps, ["Draft App", "com.example.draft", "Second App"])
    XCTAssertEqual(settings.openShortcut.key, "b")
    form.shortcuts[0].key = ""
    form.commitShortcut(0)
    XCTAssertEqual(settings.openShortcut.key, "b")
    XCTAssertEqual(form.shortcuts[0], SettingsFormState.ShortcutDraft(settings.openShortcut))
    withExtendedLifetime(controller) { drainMainQueue() }
    resetShelf([])
    let glyphs = SettingsFormState(settings: settings)
    glyphs.shortcuts[0].key = "⌃⇧B"
    glyphs.commitShortcut(0)
    let expected = ShortcutBinding(key: "b", modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue)
    XCTAssertEqual(settings.openShortcut, expected)
    glyphs.shortcuts[0].key = "⌘⇧C"
    glyphs.commitShortcut(0)
    XCTAssertEqual(settings.openShortcut, expected)
    XCTAssertEqual(glyphs.shortcuts[0].key, "B")
    XCTAssertTrue(settings.shortcutStatusMessage.contains("already in use"))
  }

  private func nativeShelf(_ items: [Clip]) -> ShelfView {
    resetShelf([])
    _ = NSApplication.shared
    shelf.items = items
    shelf.recomputeVisibleItems()
    let panel = ShelfView(viewModel: shelf, onClose: {})
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 700), styleMask: [.borderless], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = panel
    panel.layoutSubtreeIfNeeded()
    addTeardownBlock { window.close() }
    return panel
  }
}
