import Foundation

enum HistoryRetention: Int {
  case forever = 0
  case oneDay = 1
  case oneWeek = 7
  case oneMonth = 30
  case oneYear = 365

  static let allCases: [HistoryRetention] = [.oneDay, .oneWeek, .oneMonth, .oneYear, .forever]

  var title: String {
    switch self {
    case .oneDay: return "1 Day"
    case .oneWeek: return "1 Week"
    case .oneMonth: return "1 Month"
    case .oneYear: return "1 Year"
    case .forever: return "Forever"
    }
  }

  func cutoffDate(relativeTo now: Date = Date()) -> Date? {
    guard self != .forever else { return nil }
    return now.addingTimeInterval(-Double(rawValue) * 24 * 60 * 60)
  }
}

enum ClipboardPanelSide: Int, CaseIterable {
  case left = 0
  case right = 1

  var title: String {
    switch self {
    case .left: return "Left"
    case .right: return "Right"
    }
  }
}

final class SettingsModel {
  enum Change: Equatable {
    case maxHistoryItems
    case historyRetention
    case defaultSortMode
    case imageCacheMaxBytes
    case includeImageTextInSearch
    case pruneDuplicates
    case openShortcut
    case settingsShortcut
    case launchAtLogin
    case showMenuBarIcon
    case showDockIcon
    case panelSide
    case cloudSync
    case pauseCapture
    case ignoredApps
    case ignoredItemKinds
    case keepFirstImage
    case excludeSensitive
    case hideFromScreenCapture
    case clearHistoryOnQuit
    case pollProfile
    case captureStatus
    case collections
    case status
    case other
  }

  enum Keys {
    static let maxHistoryItems = "maxHistoryItems"
    static let historyRetention = "historyRetentionDays"
    static let defaultSortMode = "defaultSortMode"
    static let imageCacheMaxBytes = "imageCacheMaxBytes"
    static let includeImageTextInSearch = "includeImageTextInSearch"
    static let pruneDuplicates = "pruneDuplicates"
    static let launchAtLogin = "launchAtLogin"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let panelSide = "panelSide"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let openShortcut = "openShortcut"
    static let settingsShortcut = "settingsShortcut"
    static let ignoredApps = "ignoredApps"
    static let ignoredItemKinds = "ignoredItemKinds"
    static let pollProfile = "pollProfile"
    static let keepFirstImage = "keepFirstImage"
    static let excludeSensitive = "excludeSensitive"
    static let pauseCapture = "pauseCapture"
    static let pauseCaptureUntil = "pauseCaptureUntil"
    static let hideFromScreenCapture = "hideFromScreenCapture"
    static let clearHistoryOnQuit = "clearHistoryOnQuit"
    static let onboardingCompleted = "onboardingCompleted"
    static let accessibilityNoticeShown = "accessibilityNoticeShown"
    static let customCollectionNames = "customCollectionNames"
    static let collectionColorHexes = "collectionColorHexes"
  }

  var maxHistoryItems: Int {
    didSet {
      maxHistoryItems = Self.clampedMaxHistoryItems(maxHistoryItems)
      if oldValue != maxHistoryItems { storeAndNotify(.maxHistoryItems) }
    }
  }
  var historyRetention: HistoryRetention {
    didSet { if oldValue != historyRetention { storeAndNotify(.historyRetention) } }
  }
  var defaultSortMode: ClipboardSortMode {
    didSet { if oldValue != defaultSortMode { storeAndNotify(.defaultSortMode) } }
  }
  var imageCacheMaxBytes: Int64 {
    didSet {
      imageCacheMaxBytes = Self.clampedImageCacheMaxBytes(imageCacheMaxBytes)
      if oldValue != imageCacheMaxBytes { storeAndNotify(.imageCacheMaxBytes) }
    }
  }
  var includeImageTextInSearch: Bool {
    didSet { if oldValue != includeImageTextInSearch { storeAndNotify(.includeImageTextInSearch) } }
  }
  var pruneDuplicates: Bool {
    didSet { if oldValue != pruneDuplicates { storeAndNotify(.pruneDuplicates) } }
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
  var panelSide: ClipboardPanelSide {
    didSet { if oldValue != panelSide { storeAndNotify(.panelSide) } }
  }
  var iCloudSyncEnabled: Bool {
    didSet {
      guard oldValue != iCloudSyncEnabled else { return }
      cloudSyncStatusMessage = ""
      storeAndNotify(.cloudSync)
    }
  }
  var openShortcut: ShortcutBinding {
    didSet { if oldValue != openShortcut { storeAndNotify(.openShortcut) } }
  }
  var settingsShortcut: ShortcutBinding {
    didSet { if oldValue != settingsShortcut { storeAndNotify(.settingsShortcut) } }
  }
  var ignoredApps: [String] {
    didSet { if oldValue != ignoredApps { storeAndNotify(.ignoredApps) } }
  }
  var ignoredItemKindsRaw: [Int] {
    didSet {
      let normalized = Self.normalizedIgnoredItemKinds(ignoredItemKindsRaw)
      if normalized != ignoredItemKindsRaw {
        ignoredItemKindsRaw = normalized
      }
      if oldValue != ignoredItemKindsRaw { storeAndNotify(.ignoredItemKinds) }
    }
  }
  var pollProfileRaw: AppConfiguration.PollProfile {
    didSet { if oldValue != pollProfileRaw { storeAndNotify(.pollProfile) } }
  }
  var keepFirstImage: Bool {
    didSet { if oldValue != keepFirstImage { storeAndNotify(.keepFirstImage) } }
  }
  var excludeSensitive: Bool {
    didSet { if oldValue != excludeSensitive { storeAndNotify(.excludeSensitive) } }
  }
  var pauseCapture: Bool {
    didSet { if oldValue != pauseCapture { storeAndNotify(.pauseCapture) } }
  }
  var pauseCaptureUntil: Date? {
    didSet { if oldValue != pauseCaptureUntil { storeAndNotify(.pauseCapture) } }
  }
  var hideFromScreenCapture: Bool {
    didSet { if oldValue != hideFromScreenCapture { storeAndNotify(.hideFromScreenCapture) } }
  }
  var clearHistoryOnQuit: Bool {
    didSet { if oldValue != clearHistoryOnQuit { storeAndNotify(.clearHistoryOnQuit) } }
  }
  private(set) var customCollectionNames: [String]
  private(set) var collectionColorHexes: [String: String]
  private(set) var launchAtLoginErrorMessage: String = ""
  private(set) var accessibilityPermissionStatusMessage: String = ""
  private(set) var captureStatusMessage: String = ""
  private(set) var shortcutStatusMessage: String = ""
  private(set) var pasteStatusMessage: String = ""
  private(set) var cloudSyncStatusMessage: String = ""
  private(set) var onboardingCompleted: Bool
  private(set) var accessibilityNoticeShown: Bool

  private let defaults: UserDefaults
  private var observers: [(Change) -> Void] = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let savedHistory = defaults.integer(forKey: Keys.maxHistoryItems)
    let savedRetention = defaults.object(forKey: Keys.historyRetention) as? Int
    let savedSort = defaults.integer(forKey: Keys.defaultSortMode)
    let savedCacheObject = defaults.object(forKey: Keys.imageCacheMaxBytes)
    let savedCache = defaults.integer(forKey: Keys.imageCacheMaxBytes)
    let savedPanelSide = defaults.object(forKey: Keys.panelSide) as? Int
    let existingProfile = defaults.object(forKey: Keys.maxHistoryItems) != nil
      || defaults.object(forKey: Keys.historyRetention) != nil
      || defaults.object(forKey: Keys.openShortcut) != nil

    maxHistoryItems = savedHistory > 0 ? savedHistory : AppConfiguration.defaultHistoryLength
    historyRetention = savedRetention.flatMap(HistoryRetention.init(rawValue:)) ?? .oneMonth
    defaultSortMode = ClipboardSortMode(rawValue: savedSort) ?? .mostRecent
    imageCacheMaxBytes = savedCache > 0 ? Int64(savedCache) : AppConfiguration.defaultCacheMaxBytes
    includeImageTextInSearch = defaults.object(forKey: Keys.includeImageTextInSearch) as? Bool ?? false
    pruneDuplicates = defaults.object(forKey: Keys.pruneDuplicates) as? Bool ?? true
    launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
    showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
    showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
    panelSide = savedPanelSide.flatMap(ClipboardPanelSide.init(rawValue:)) ?? .right
    iCloudSyncEnabled = defaults.object(forKey: Keys.iCloudSyncEnabled) as? Bool ?? false
    openShortcut = Self.readShortcut(from: defaults.string(forKey: Keys.openShortcut)) ?? AppConfiguration.defaultOpenShortcut
    settingsShortcut = Self.readShortcut(from: defaults.string(forKey: Keys.settingsShortcut)) ?? AppConfiguration.defaultSettingsShortcut
    ignoredApps = defaults.stringArray(forKey: Keys.ignoredApps) ?? AppConfiguration.defaultIgnoredApps
    let storedIgnoredItemKinds = defaults.object(forKey: Keys.ignoredItemKinds) as? [Int] ?? []
    ignoredItemKindsRaw = Self.normalizedIgnoredItemKinds(storedIgnoredItemKinds)
    let profileValue = defaults.integer(forKey: Keys.pollProfile)
    pollProfileRaw = AppConfiguration.PollProfile(rawValue: profileValue) ?? AppConfiguration.defaultPollProfile
    keepFirstImage = defaults.object(forKey: Keys.keepFirstImage) as? Bool ?? true
    excludeSensitive = defaults.object(forKey: Keys.excludeSensitive) as? Bool ?? false
    pauseCapture = defaults.object(forKey: Keys.pauseCapture) as? Bool ?? false
    if let pauseUntilValue = defaults.object(forKey: Keys.pauseCaptureUntil) as? TimeInterval,
       pauseUntilValue > 0 {
      pauseCaptureUntil = Date(timeIntervalSince1970: pauseUntilValue)
    } else {
      pauseCaptureUntil = nil
    }
    hideFromScreenCapture = defaults.object(forKey: Keys.hideFromScreenCapture) as? Bool ?? false
    clearHistoryOnQuit = defaults.object(forKey: Keys.clearHistoryOnQuit) as? Bool ?? false
    customCollectionNames = Self.normalizedCollectionNames(defaults.stringArray(forKey: Keys.customCollectionNames) ?? [])
    collectionColorHexes = Self.normalizedCollectionColorHexes(defaults.dictionary(forKey: Keys.collectionColorHexes))
    onboardingCompleted = defaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? existingProfile
    accessibilityNoticeShown = defaults.object(forKey: Keys.accessibilityNoticeShown) as? Bool ?? false

    maxHistoryItems = Self.clampedMaxHistoryItems(maxHistoryItems)
    imageCacheMaxBytes = Self.clampedImageCacheMaxBytes(imageCacheMaxBytes)
    if defaults.object(forKey: Keys.maxHistoryItems) == nil
      || savedHistory != maxHistoryItems
      || defaults.object(forKey: Keys.historyRetention) == nil
      || savedCacheObject == nil
      || savedCache <= 0
      || Int64(savedCache) != imageCacheMaxBytes
      || storedIgnoredItemKinds != ignoredItemKindsRaw
      || savedPanelSide == nil
      || ClipboardPanelSide(rawValue: savedPanelSide ?? -1) == nil {
      store()
    }
  }

  private func store() {
    defaults.set(maxHistoryItems, forKey: Keys.maxHistoryItems)
    defaults.set(historyRetention.rawValue, forKey: Keys.historyRetention)
    defaults.set(defaultSortMode.rawValue, forKey: Keys.defaultSortMode)
    defaults.set(imageCacheMaxBytes, forKey: Keys.imageCacheMaxBytes)
    defaults.set(includeImageTextInSearch, forKey: Keys.includeImageTextInSearch)
    defaults.set(pruneDuplicates, forKey: Keys.pruneDuplicates)
    defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
    defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
    defaults.set(showDockIcon, forKey: Keys.showDockIcon)
    defaults.set(panelSide.rawValue, forKey: Keys.panelSide)
    defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled)
    defaults.set(openShortcut.encoded(), forKey: Keys.openShortcut)
    defaults.set(settingsShortcut.encoded(), forKey: Keys.settingsShortcut)
    defaults.set(ignoredApps, forKey: Keys.ignoredApps)
    defaults.set(ignoredItemKindsRaw, forKey: Keys.ignoredItemKinds)
    defaults.set(pollProfileRaw.rawValue, forKey: Keys.pollProfile)
    defaults.set(keepFirstImage, forKey: Keys.keepFirstImage)
    defaults.set(excludeSensitive, forKey: Keys.excludeSensitive)
    defaults.set(pauseCapture, forKey: Keys.pauseCapture)
    if let pauseCaptureUntil {
      defaults.set(pauseCaptureUntil.timeIntervalSince1970, forKey: Keys.pauseCaptureUntil)
    } else {
      defaults.removeObject(forKey: Keys.pauseCaptureUntil)
    }
    defaults.set(hideFromScreenCapture, forKey: Keys.hideFromScreenCapture)
    defaults.set(clearHistoryOnQuit, forKey: Keys.clearHistoryOnQuit)
    defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted)
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

  func markOnboardingCompleted() {
    guard !onboardingCompleted else { return }
    onboardingCompleted = true
    defaults.set(true, forKey: Keys.onboardingCompleted)
    notify(.other)
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

  func setCloudSyncStatus(message: String) {
    guard cloudSyncStatusMessage != message else { return }
    cloudSyncStatusMessage = message
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

  @discardableResult
  func updateCollection(named currentName: String, to newName: String, colorHex: String? = nil) -> String? {
    guard let normalizedCurrentName = ClipboardCollectionDefaults.normalizedName(currentName),
          let normalizedNewName = ClipboardCollectionDefaults.normalizedName(newName) else {
      return nil
    }

    let oldIndex = customCollectionNames.firstIndex {
      $0.caseInsensitiveCompare(normalizedCurrentName) == .orderedSame
    }
    let oldCanonicalName = oldIndex.map { customCollectionNames[$0] } ?? normalizedCurrentName
    let targetIndex = customCollectionNames.firstIndex {
      $0.caseInsensitiveCompare(normalizedNewName) == .orderedSame
    }
    let targetCanonicalName: String
    if let targetIndex, targetIndex != oldIndex {
      targetCanonicalName = customCollectionNames[targetIndex]
    } else {
      targetCanonicalName = normalizedNewName
    }
    var changed = false

    if let oldIndex {
      if let targetIndex, targetIndex != oldIndex {
        customCollectionNames.remove(at: oldIndex)
        changed = true
      } else if customCollectionNames[oldIndex] != normalizedNewName {
        customCollectionNames[oldIndex] = normalizedNewName
        changed = true
      }
    } else if targetIndex == nil {
      customCollectionNames.append(normalizedNewName)
      changed = true
    }

    let existingColor = collectionColorHex(forCollectionNamed: oldCanonicalName)
    for key in collectionColorHexes.keys where key.caseInsensitiveCompare(oldCanonicalName) == .orderedSame {
      collectionColorHexes.removeValue(forKey: key)
      changed = true
    }
    let resolvedColor = Self.normalizedHexColor(colorHex) ?? existingColor
    if let resolvedColor,
       collectionColorHexes[targetCanonicalName] != resolvedColor {
      collectionColorHexes[targetCanonicalName] = resolvedColor
      changed = true
    }

    if changed {
      storeAndNotify(.collections)
    }
    return targetCanonicalName
  }

  @discardableResult
  func deleteCollection(named name: String) -> String? {
    guard let normalizedName = ClipboardCollectionDefaults.normalizedName(name) else { return nil }
    var changed = false
    if let index = customCollectionNames.firstIndex(where: { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
      customCollectionNames.remove(at: index)
      changed = true
    }
    for key in collectionColorHexes.keys where key.caseInsensitiveCompare(normalizedName) == .orderedSame {
      collectionColorHexes.removeValue(forKey: key)
      changed = true
    }
    if changed {
      storeAndNotify(.collections)
    }
    return normalizedName
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
    maxHistoryItems = Self.clampedMaxHistoryItems(maxHistoryItems)
    imageCacheMaxBytes = Self.clampedImageCacheMaxBytes(imageCacheMaxBytes)
  }

  private static func clampedMaxHistoryItems(_ count: Int) -> Int {
    max(AppConfiguration.minHistoryLength, min(AppConfiguration.maxHistoryLength, count))
  }

  private static func clampedImageCacheMaxBytes(_ bytes: Int64) -> Int64 {
    max(AppConfiguration.minCacheMaxBytes, min(AppConfiguration.maxCacheMaxBytes, bytes))
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

  private static let userVisibleItemKindRawValues: Set<Int> = [
    ClipboardItemKind.text.rawValue,
    ClipboardItemKind.code.rawValue,
    ClipboardItemKind.url.rawValue,
    ClipboardItemKind.image.rawValue,
    ClipboardItemKind.color.rawValue,
    ClipboardItemKind.audio.rawValue,
    ClipboardItemKind.video.rawValue,
    ClipboardItemKind.richText.rawValue,
    ClipboardItemKind.pdf.rawValue,
    ClipboardItemKind.file.rawValue
  ]

  private static func normalizedIgnoredItemKinds(_ values: [Int]) -> [Int] {
    let ignoredVisibleKinds = Set(values).intersection(userVisibleItemKindRawValues)
    guard userVisibleItemKindRawValues.isSubset(of: ignoredVisibleKinds) else { return values }
    return values.filter { $0 != ClipboardItemKind.text.rawValue }
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
