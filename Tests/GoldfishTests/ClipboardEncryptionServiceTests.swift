import CryptoKit
import Security
import XCTest
@testable import Goldfish

final class ClipboardEncryptionServiceTests: XCTestCase {
  func testProductionStoragePolicyFailsClosedWithoutAKey() {
    let encryption = ClipboardEncryptionService(keyProvider: { nil }, allowsUnencryptedStorage: false)
    XCTAssertFalse(encryption.canPersist)
    XCTAssertNil(encryption.protect("private clipboard text"))
    XCTAssertThrowsError(try encryption.protectDataForStorage(Data("private media".utf8)))
  }
  func testProtectAndUnprotectRoundTrip() throws {
    let service = makeService(byte: 7)
    let value = "secret clipboard value \(UUID().uuidString)"

    let protected = try XCTUnwrap(service.protect(value))

    XCTAssertTrue(ClipboardEncryptionService.isProtected(protected))
    XCTAssertFalse(protected.contains(value))
    XCTAssertEqual(service.unprotect(protected), value)
  }

  func testUnprotectLeavesPlaintextValuesUntouched() {
    let service = makeService(byte: 7)
    let value = "plain clipboard value"

    XCTAssertEqual(service.unprotect(value), value)
  }

  func testMarkerLookingPlaintextIsStillEncryptable() throws {
    let service = makeService(byte: 7)
    let value = ClipboardEncryptionService.marker + "not encrypted user text"

    let protected = try XCTUnwrap(service.protect(value))

    XCTAssertNotEqual(protected, value)
    XCTAssertEqual(service.unprotect(protected), value)
    XCTAssertEqual(service.unprotect(value), value)
  }

  func testWrongKeyCannotDecryptProtectedValue() throws {
    let service = makeService(byte: 7)
    let wrongService = makeService(byte: 9)
    let protected = try XCTUnwrap(service.protect("keyed secret"))

    XCTAssertNil(wrongService.unprotect(protected))
  }

  func testProtectDataAndUnprotectDataRoundTrip() throws {
    let service = makeService(byte: 7)
    let data = Data((0..<128).map { UInt8($0) })

    let protected = service.protectData(data)

    XCTAssertTrue(ClipboardEncryptionService.isProtected(protected))
    XCTAssertNotEqual(protected, data)
    XCTAssertEqual(service.unprotectData(protected), data)
  }

  func testWrongKeyCannotDecryptProtectedData() {
    let service = makeService(byte: 7)
    let wrongService = makeService(byte: 9)
    let protected = service.protectData(Data("binary secret".utf8))

    XCTAssertNil(wrongService.unprotectData(protected))
  }

  func testProtectFallsBackToPlaintextWhenKeyIsUnavailable() {
    let service = ClipboardEncryptionService(keyProvider: { nil })

    XCTAssertEqual(service.protect("available only in memory"), "available only in memory")
    XCTAssertEqual(service.protectData(Data("available only in memory".utf8)), Data("available only in memory".utf8))
  }

  func testSystemKeychainBypassIsEnabledForTestsAndExplicitEnvironment() {
    XCTAssertTrue(ClipboardEncryptionService.shouldBypassSystemKeychain(
      environment: ["XCTestConfigurationFilePath": "/tmp/GoldfishTests.xctestconfiguration"],
      arguments: ["/tmp/GoldfishTests"]
    ))
    XCTAssertTrue(ClipboardEncryptionService.shouldBypassSystemKeychain(
      environment: ["CLIPBORED_DISABLE_KEYCHAIN": "1"],
      arguments: ["/tmp/Goldfish"]
    ))
    XCTAssertTrue(ClipboardEncryptionService.shouldBypassSystemKeychain(
      environment: [:],
      arguments: ["/tmp/GoldfishPackageTests.xctest/Contents/MacOS/GoldfishPackageTests"]
    ))
    XCTAssertFalse(ClipboardEncryptionService.shouldBypassSystemKeychain(
      environment: [:],
      arguments: ["/Applications/Goldfish.app/Contents/MacOS/Goldfish"]
    ))
  }

  func testDuplicateKeychainItemUsesExistingKeyRatherThanGeneratedKey() {
    let generated = Data(repeating: 7, count: 32)
    let existing = Data(repeating: 9, count: 32)

    XCTAssertEqual(
      ClipboardEncryptionService.resolvedKeyData(
        generatedData: generated,
        addStatus: errSecDuplicateItem,
        existingData: existing
      ),
      existing
    )
  }

  func testIndeterminateKeychainSaveDoesNotSelectCompetingKey() {
    XCTAssertNil(
      ClipboardEncryptionService.resolvedKeyData(
        generatedData: Data(repeating: 7, count: 32),
        addStatus: errSecInteractionNotAllowed,
        existingData: nil
      )
    )
  }

  private func makeService(byte: UInt8) -> ClipboardEncryptionService {
    let keyData = Data(repeating: byte, count: 32)
    return ClipboardEncryptionService(keyProvider: { SymmetricKey(data: keyData) })
  }
}
