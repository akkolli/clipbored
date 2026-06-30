import CryptoKit
import XCTest
@testable import ClipBored

final class ClipboardEncryptionServiceTests: XCTestCase {
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

  private func makeService(byte: UInt8) -> ClipboardEncryptionService {
    let keyData = Data(repeating: byte, count: 32)
    return ClipboardEncryptionService(keyProvider: { SymmetricKey(data: keyData) })
  }
}
