import XCTest
@testable import ClipBored

final class SensitiveContentDetectorTests: XCTestCase {
  func testDetectsKnownSecretFormats() {
    XCTAssertEqual(
      SensitiveContentDetector.detect("-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----"),
      .privateKey
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456"),
      .bearerToken
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("ghp_abcdefghijklmnopqrstuvwxyzABCDE1234567890"),
      .githubToken
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("AKIA1234567890ABCDEF"),
      .awsAccessKey
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("xoxb-abcdefghijklmnopqrst"),
      .slackToken
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("sk_live_abcdefghijklmnop"),
      .stripeKey
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("sk-proj-abcdefghijklmnopqrstuvwxyz1234567890"),
      .openAIToken
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("AIzaabcdefghijklmnopqrstuvwxyz123456789"),
      .googleAPIKey
    )
    XCTAssertEqual(
      SensitiveContentDetector.detect("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature123"),
      .jsonWebToken
    )
  }

  func testDetectsCreditCardWithLuhnCheck() {
    XCTAssertEqual(SensitiveContentDetector.detect("4242424242424242"), .creditCard)
    XCTAssertNil(SensitiveContentDetector.detect("4242424242424241"))
  }

  func testAllowsNormalClipboardText() {
    XCTAssertNil(SensitiveContentDetector.detect("Project notes for tomorrow"))
    XCTAssertNil(SensitiveContentDetector.detect("https://www.apple.com/mac/"))
    XCTAssertNil(SensitiveContentDetector.detect("Remember to request the API key from the platform team"))
    XCTAssertNil(SensitiveContentDetector.detect("Release token cleanup notes"))
  }

  func testDetectsOtpOnlyForSensitiveSources() {
    XCTAssertNil(SensitiveContentDetector.detect("123456"))
    XCTAssertEqual(
      SensitiveContentDetector.detect("123456", sourceBundleId: "com.1password.1password", sourceApp: "1Password"),
      .oneTimeCode
    )
  }

  func testDetectsSecretAssignments() {
    XCTAssertEqual(SensitiveContentDetector.detect("OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz"), .openAIToken)
    XCTAssertEqual(SensitiveContentDetector.detect("client_secret: supersecretvalue"), .keyword)
    XCTAssertEqual(SensitiveContentDetector.detect("refresh_token = \"abc1234567890\""), .keyword)
    XCTAssertEqual(SensitiveContentDetector.detect("passwd='correct-horse-battery'"), .keyword)
  }
}
