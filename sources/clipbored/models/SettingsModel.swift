import Foundation

final class SettingsModel {
  enum Change: Equatable {
    case maxHistoryItems
    case imageCacheMaxBytes
    case openShortcut
    case settingsShortcut
    case launchAtLogin
    case showMenuBarIcon
    case showDockIcon
    case pauseCapture
    case pollProfile
    case captureStatus
    case collections
    case status
    case other
  }

  enum Keys {
    static let maxHistoryItems = "maxHistoryItems"
    static let defaultSortMode = "defaultSortMode"
    static let imageCacheMaxBytes = "imageCacheMaxBytes"
    static let includeImageTextInSearch = "includeImageTextInSearch"
    static let pruneDuplicates = "pruneDuplicates"
    static let launchAtLogin = "launchAtLogin"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let openShortcut = "openShortcut"
    static let settingsShortcut = "settingsShortcut"
    static let ignoredApps = "ignoredApps"
    static let ignoredItemKinds = "ignoredItemKinds"
    static let pollProfile = "pollProfile"
    static let keepFirstImage = "keepFirstImage"
    static let excludeSensitive = "excludeSensitive"
    static let pauseCapture = "pauseCapture"
    static let clearHistoryOnQuit = "clearHistoryOnQuit"
    static let accessibilityNoticeShown = "accessibilityNoticeShown"
    static let customCollectionNames = "customCollectionNames"
    static let collectionColorHexes = "collectionColorHexes"
  }

  var maxHistoryItems: Int {
    didSet { if oldValue != maxHistoryItems { storeAndNotify(.maxHistoryItems) } }
  }
  var defaultSortMode: ClipboardSortMode {
    didSet { if oldValue != defaultSortMode { storeAndNotify(.other) } }
  }
  var imageCacheMaxBytes: Int64 {
    didSet { if oldValue != imageCacheMaxBytes { storeAndNotify(.imageCacheMaxBytes) } }
  }
  var includeImageTextInSearch: Bool {
    didSet { if oldValue != includeImageTextInSearch { storeAndNotify(.other) } }
  }
  var pruneDuplicates: Bool {
    didSet { if oldValue != pruneDuplicates { storeAndNotify(.other) } }
  }
  var launchAtLogin: Bool {
    didSet { if oldValue != launchAtLogin { storeAndNotify(.launchAtLogin) } }
  }
  var showMenuBarIcon: Bool {
    didSet { if oldValue != showMenuBarIcon { storeAndNotify(.showMenuBarIcon) } }
  }
  var showDockIcon: Bool {
    didSet { if oldValue != showDockIcon { storeAndNotify(.showDockIcon) } }
  }
  var openShortcut: ShortcutBinding {
    didSet { if oldValue != openShortcut { storeAndNotify(.openShortcut) } }
  }
  var settingsShortcut: ShortcutBinding {
    didSet { if oldValue != settingsShortcut { storeAndNotify(.settingsShortcut) } }
  }
  var ignoredApps: [String] {
    didSet { if oldValue != ignoredApps { storeAndNotify(.other) } }
  }
  var ignoredItemKindsRaw: [Int] {
    didSet { if oldValue != ignoredItemKindsRaw { storeAndNotify(.other) } }
  }
  var pollProfileRaw: AppConfiguration.PollProfile {
    didSet { if oldValue != pollProfileRaw { storeAndNotify(.pollProfile) } }
  }
  var keepFirstImage: Bool {
    didSet { if oldValue != keepFirstImage { storeAndNotify(.other) } }
  }
  var excludeSensitive: Bool {
    didSet { if oldValue != excludeSensitive { storeAndNotify(.other) } }
  }
  var pauseCapture: Bool {
    didSet { if oldValue != pauseCapture { storeAndNotify(.pauseCapture) } }
  }
  var clearHistoryOnQuit: Bool {
    didSet { if oldValue != clearHistoryOnQuit { storeAndNotify(.other) } }
  }
  private(set) var customCollectionNames: [String]
  private(set) var collectionColorHexes: [String: String]
  private(set) var launchAtLoginErrorMessage: String = ""
  private(set) var accessibilityPermissionStatusMessage: String = ""
  private(set) var captureStatusMessage: String = ""
  private(set) var shortcutStatusMessage: String = ""
  private(set) var pasteStatusMessage: String = ""
  private(set) var accessibilityNoticeShown: Bool

  private let defaults: UserDefaults
  private var observers: [(Change) -> Void] = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let savedHistory = defaults.integer(forKey: Keys.maxHistoryItems)
    let savedSort = defaults.integer(forKey: Keys.defaultSortMode)
    let savedCache = defaults.integer(forKey: Keys.imageCacheMaxBytes)

    maxHistoryItems = savedHistory > 0 ? savedHistory : AppConfiguration.defaultHistoryLength
    defaultSortMode = ClipboardSortMode(rawValue: savedSort) ?? .mostRecent
    imageCacheMaxBytes = savedCache > 0 ? Int64(savedCache) : AppConfiguration.defaultCacheMaxBytes
    includeImageTextInSearch = defaults.object(forKey: Keys.includeImageTextInSearch) as? Bool ?? false
    pruneDuplicates = defaults.object(forKey: Keys.pruneDuplicates) as? Bool ?? true
    launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
    showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
    showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
    openShortcut = Self.readShortcut(from: defaults.string(forKey: Keys.openShortcut)) ?? AppConfiguration.defaultOpenShortcut
    settingsShortcut = Self.readShortcut(from: defaults.string(forKey: Keys.settingsShortcut)) ?? AppConfiguration.defaultSettingsShortcut
    ignoredApps = defaults.stringArray(forKey: Keys.ignoredApps) ?? AppConfiguration.defaultIgnoredApps
    ignoredItemKindsRaw = defaults.object(forKey: Keys.ignoredItemKinds) as? [Int] ?? []
    let profileValue = defaults.integer(forKey: Keys.pollProfile)
    pollProfileRaw = AppConfiguration.PollProfile(rawValue: profileValue) ?? AppConfiguration.defaultPollProfile
    keepFirstImage = defaults.object(forKey: Keys.keepFirstImage) as? Bool ?? true
    excludeSensitive = defaults.object(forKey: Keys.excludeSensitive) as? Bool ?? false
    pauseCapture = defaults.object(forKey: Keys.pauseCapture) as? Bool ?? false
    clearHistoryOnQuit = defaults.object(forKey: Keys.clearHistoryOnQuit) as? Bool ?? false
    customCollectionNames = Self.normalizedCollectionNames(defaults.stringArray(forKey: Keys.customCollectionNames) ?? [])
    collectionColorHexes = Self.normalizedCollectionColorHexes(defaults.dictionary(forKey: Keys.collectionColorHexes))
    accessibilityNoticeShown = defaults.object(forKey: Keys.accessibilityNoticeShown) as? Bool ?? false

    maxHistoryItems = max(AppConfiguration.minHistoryLength, min(AppConfiguration.maxHistoryLength, maxHistoryItems))
    imageCacheMaxBytes = max(4 * 1024 * 1024, imageCacheMaxBytes)

    if defaults.object(forKey: Keys.maxHistoryItems) == nil {
      store()
    }
  }

  private func store() {
    defaults.set(maxHistoryItems, forKey: Keys.maxHistoryItems)
    defaults.set(defaultSortMode.rawValue, forKey: Keys.defaultSortMode)
    defaults.set(imageCacheMaxBytes, forKey: Keys.imageCacheMaxBytes)
    defaults.set(includeImageTextInSearch, forKey: Keys.includeImageTextInSearch)
    defaults.set(pruneDuplicates, forKey: Keys.pruneDuplicates)
    defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
    defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
    defaults.set(showDockIcon, forKey: Keys.showDockIcon)
    defaults.set(openShortcut.encoded(), forKey: Keys.openShortcut)
    defaults.set(settingsShortcut.encoded(), forKey: Keys.settingsShortcut)
    defaults.set(ignoredApps, forKey: Keys.ignoredApps)
    defaults.set(ignoredItemKindsRaw, forKey: Keys.ignoredItemKinds)
    defaults.set(pollProfileRaw.rawValue, forKey: Keys.pollProfile)
    defaults.set(keepFirstImage, forKey: Keys.keepFirstImage)
    defaults.set(excludeSensitive, forKey: Keys.excludeSensitive)
    defaults.set(pauseCapture, forKey: Keys.pauseCapture)
    defaults.set(clearHistoryOnQuit, forKey: Keys.clearHistoryOnQuit)
    defaults.set(customCollectionNames, forKey: Keys.customCollectionNames)
    defaults.set(collectionColorHexes, forKey: Keys.collectionColorHexes)
  }

  func observe(_ observer: @escaping (Change) -> Void) {
    observers.append(observer)
  }

  private func storeAndNotify(_ change: Change) {
    store()
    notify(change)
  }

  private func notify(_ change: Change) {
    for observer in observers {
      observer(change)
    }
  }

  func setLaunchAtLoginStatus(message: String) {
    guard launchAtLoginErrorMessage != message else { return }
    launchAtLoginErrorMessage = message
    notify(.status)
  }

  func setAccessibilityPermissionStatus(message: String) {
    guard accessibilityPermissionStatusMessage != message else { return }
    accessibilityPermissionStatusMessage = message
    notify(.status)
  }

  func setCaptureStatus(message: String) {
    guard captureStatusMessage != message else { return }
    captureStatusMessage = message
    notify(.captureStatus)
  }

  func markAccessibilityNoticeShown() {
    guard !accessibilityNoticeShown else { return }
    accessibilityNoticeShown = true
    defaults.set(true, forKey: Keys.accessibilityNoticeShown)
  }

  func setShortcutStatus(message: String) {
    guard shortcutStatusMessage != message else { return }
    shortcutStatusMessage = message
    notify(.status)
  }

  func setPasteStatus(message: String) {
    guard pasteStatusMessage != message else { return }
    pasteStatusMessage = message
    notify(.status)
  }

  @discardableResult
  func ensureCollection(named name: String, colorHex: String? = nil) -> String? {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return nil }
    let existingName = customCollectionNames.first {
      $0.caseInsensitiveCompare(normalizedName) == .orderedSame
    }
    let canonicalName = existingName ?? normalizedName
    var changed = false

    if existingName == nil {
      customCollectionNames.append(normalizedName)
      changed = true
    }

    if let normalizedHex = Self.normalizedHexColor(colorHex),
       collectionColorHexes[canonicalName] != normalizedHex {
      for key in collectionColorHexes.keys where key.caseInsensitiveCompare(canonicalName) == .orderedSame && key != canonicalName {
        collectionColorHexes.removeValue(forKey: key)
      }
      collectionColorHexes[canonicalName] = normalizedHex
      changed = true
    }

    if changed {
      storeAndNotify(.collections)
    }
    return normalizedName
  }

  func collectionColorHex(forCollectionNamed name: String) -> String? {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return nil }
    if let exact = collectionColorHexes[normalizedName] {
      return exact
    }
    return collectionColorHexes.first { storedName, _ in
      storedName.caseInsensitiveCompare(normalizedName) == .orderedSame
    }?.value
  }

  private static func readShortcut(from value: String?) -> ShortcutBinding? {
    guard let value else { return nil }
    return ShortcutBinding(encoded: value)
  }

  var pollProfile: AppConfiguration.PollProfile {
    get { pollProfileRaw }
    set { pollProfileRaw = newValue }
  }

  func sanitizeLimits() {
    maxHistoryItems = max(AppConfiguration.minHistoryLength, min(AppConfiguration.maxHistoryLength, maxHistoryItems))
    imageCacheMaxBytes = max(4 * 1024 * 1024, imageCacheMaxBytes)
  }

  private static func normalizedCollectionNames(_ names: [String]) -> [String] {
    var normalized: [String] = []
    for name in names {
      guard let value = ClipboardCollectionDefaults.normalizedName(name) else { continue }
      guard !normalized.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { continue }
      normalized.append(value)
    }
    return normalized
  }

  private static func normalizedCollectionColorHexes(_ rawValue: [String: Any]?) -> [String: String] {
    guard let rawValue else { return [:] }
    var normalized: [String: String] = [:]
    for (name, color) in rawValue {
      guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name),
            let hex = normalizedHexColor(color as? String) else {
        continue
      }
      normalized[normalizedName] = hex
    }
    return normalized
  }

  private static func normalizedHexColor(_ value: String?) -> String? {
    guard let value else { return nil }
    var hex = value.clipboardTrimmed.uppercased()
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }
    guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else {
      return nil
    }
    return "#\(hex)"
  }
}
