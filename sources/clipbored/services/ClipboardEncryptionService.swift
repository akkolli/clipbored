import CryptoKit
import Foundation
import LocalAuthentication
import Security

// Swift marks SecAccessCreate deprecated, but macOS still needs kSecAttrAccess
// here to avoid legacy keychain authorization UI during generic-password creation.
@_silgen_name("SecAccessCreate")
private func clipBoredSecAccessCreate(
  _ descriptor: CFString,
  _ trustedList: CFArray?,
  _ accessRef: UnsafeMutablePointer<SecAccess?>
) -> OSStatus

final class ClipboardEncryptionService {
  static let marker = "clipbored:v1:"
  private static let markerData = Data(marker.utf8)

  private let keyProvider: () -> SymmetricKey?
  private let resetProvider: () -> Void

  init() {
    if Self.shouldBypassSystemKeychain() {
      keyProvider = { nil }
      resetProvider = {}
    } else {
      keyProvider = { ClipboardEncryptionKeychain.shared.symmetricKey() }
      resetProvider = { ClipboardEncryptionKeychain.shared.resetStoredKey() }
    }
  }

  init(keyProvider: @escaping () -> SymmetricKey?, resetProvider: @escaping () -> Void = {}) {
    self.keyProvider = keyProvider
    self.resetProvider = resetProvider
  }

  var isAvailable: Bool {
    keyProvider() != nil
  }

  func protect(_ value: String?) -> String? {
    guard let value else { return nil }
    guard let key = keyProvider() else {
      return value
    }
    guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: key),
          let combined = sealed.combined
    else {
      return value
    }
    return Self.marker + combined.base64EncodedString()
  }

  func unprotect(_ value: String?) -> String? {
    guard let value else { return nil }
    guard Self.isProtected(value) else { return value }
    let encoded = String(value.dropFirst(Self.marker.count))
    guard let data = Data(base64Encoded: encoded),
          let sealed = try? AES.GCM.SealedBox(combined: data)
    else {
      return value
    }
    guard let key = keyProvider(),
          let decrypted = try? AES.GCM.open(sealed, using: key)
    else {
      return nil
    }
    return String(data: decrypted, encoding: .utf8)
  }

  func protectData(_ data: Data) -> Data {
    guard let key = keyProvider() else {
      return data
    }
    guard let sealed = try? AES.GCM.seal(data, using: key),
          let combined = sealed.combined
    else {
      return data
    }
    var output = Self.markerData
    output.append(combined)
    return output
  }

  func unprotectData(_ data: Data) -> Data? {
    guard Self.isProtected(data) else {
      return data
    }
    let encrypted = data.dropFirst(Self.markerData.count)
    guard let sealed = try? AES.GCM.SealedBox(combined: encrypted),
          let key = keyProvider(),
          let decrypted = try? AES.GCM.open(sealed, using: key)
    else {
      return nil
    }
    return decrypted
  }

  static func isProtected(_ value: String) -> Bool {
    value.hasPrefix(marker)
  }

  static func isProtected(_ data: Data) -> Bool {
    data.starts(with: markerData)
  }

  func resetStoredKey() {
    resetProvider()
  }

  static func shouldBypassSystemKeychain(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    if environment["CLIPBORED_DISABLE_KEYCHAIN"] == "1" ||
      environment["XCTestConfigurationFilePath"] != nil {
      return true
    }

    return arguments.contains { argument in
      argument.contains(".xctest") || argument.hasSuffix("/xctest")
    }
  }
}

private enum ClipboardEncryptionKeychain {
  static let shared = KeychainBackedKeyProvider()
}

private final class KeychainBackedKeyProvider {
  private let queue = DispatchQueue(label: "clipboard.encryption-keychain")
  private let keychainTimeout: TimeInterval = 0.35
  private var cachedKey: SymmetricKey?

  func symmetricKey() -> SymmetricKey? {
    queue.sync {
      if let cachedKey {
        return cachedKey
      }
      if let fallback = readFallbackKeyData() {
        let key = SymmetricKey(data: fallback)
        cachedKey = key
        return key
      }
      if let existing = readKeyData() {
        let key = SymmetricKey(data: existing)
        cachedKey = key
        return key
      }
      let generated = SymmetricKey(size: .bits256)
      let data = generated.withUnsafeBytes { Data($0) }
      if saveKeyData(data) {
        cachedKey = generated
        return generated
      }
      guard let fallback = loadOrCreateFallbackKeyData() else {
        return nil
      }
      let fallbackKey = SymmetricKey(data: fallback)
      cachedKey = fallbackKey
      return fallbackKey
    }
  }

  func resetStoredKey() {
    queue.sync {
      cachedKey = nil
      _ = deleteKeyData()
      deleteFallbackKeyData()
    }
  }

  private func readKeyData() -> Data? {
    runKeychainOperation {
      var query = self.baseQuery()
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      query[kSecUseAuthenticationContext as String] = self.nonInteractiveContext()

      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      guard status == errSecSuccess else {
        return nil
      }
      return result as? Data
    }
  }

  private func saveKeyData(_ data: Data) -> Bool {
    runKeychainOperation {
      var query = self.baseQuery()
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      query[kSecUseAuthenticationContext as String] = self.nonInteractiveContext()
      if let access = self.keychainAccess() {
        query[kSecAttrAccess as String] = access
      }

      let status = SecItemAdd(query as CFDictionary, nil)
      if status == errSecSuccess {
        return true
      }
      if status == errSecDuplicateItem {
        return self.readKeyData() != nil
      }
      return false
    } ?? false
  }

  private func runKeychainOperation<T>(_ operation: @escaping () -> T?) -> T? {
    let lock = NSLock()
    var result: T?
    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .utility).async {
      let value = operation()
      lock.lock()
      result = value
      lock.unlock()
      semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + keychainTimeout) == .success else {
      return nil
    }
    lock.lock()
    defer { lock.unlock() }
    return result
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.local.clipbored.encryption",
      kSecAttrAccount as String: "history-v1"
    ]
  }

  private func nonInteractiveContext() -> LAContext {
    let context = LAContext()
    context.interactionNotAllowed = true
    return context
  }

  private func keychainAccess() -> SecAccess? {
    var access: SecAccess?
    let status = clipBoredSecAccessCreate("ClipBored encryption key" as CFString, nil, &access)
    guard status == errSecSuccess else {
      return nil
    }
    return access
  }

  private func loadOrCreateFallbackKeyData() -> Data? {
    if let existing = readFallbackKeyData() {
      return existing
    }
    let generated = SymmetricKey(size: .bits256)
    let data = generated.withUnsafeBytes { Data($0) }
    guard saveFallbackKeyData(data) else {
      return nil
    }
    return data
  }

  private func readFallbackKeyData() -> Data? {
    let url = fallbackKeyURL()
    guard let data = try? Data(contentsOf: url), data.count == 32 else {
      return nil
    }
    return data
  }

  private func saveFallbackKeyData(_ data: Data) -> Bool {
    let url = fallbackKeyURL()
    let directory = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try data.write(to: url, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      return true
    } catch {
      return false
    }
  }

  private func deleteKeyData() -> Bool {
    runKeychainOperation {
      let status = SecItemDelete(self.baseQuery() as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound
    } ?? false
  }

  private func deleteFallbackKeyData() {
    try? FileManager.default.removeItem(at: fallbackKeyURL())
  }

  private func fallbackKeyURL() -> URL {
    let base = ClipboardStore.storageDirectory()
    return base.appendingPathComponent("history-encryption.key")
  }
}
