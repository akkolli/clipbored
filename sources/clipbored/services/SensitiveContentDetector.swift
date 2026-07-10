import Foundation

enum SensitiveContentDetector {
  enum Reason: String {
    case privateKey
    case bearerToken
    case githubToken
    case slackToken
    case awsAccessKey
    case stripeKey
    case openAIToken
    case googleAPIKey
    case jsonWebToken
    case creditCard
    case highEntropyToken
    case oneTimeCode
    case keyword
  }

  private static let tokenPatterns: [(Reason, NSRegularExpression)] = [
    (.bearerToken, regex(#"(?i)\bbearer\s+[A-Za-z0-9._+/=-]{20,}(?![A-Za-z0-9_])"#)),
    (.githubToken, regex(#"\bgh[porus]_[A-Za-z0-9_]{30,}(?![A-Za-z0-9_])"#)),
    (.slackToken, regex(#"\bxox[baprs]-[A-Za-z0-9-]{20,}(?![A-Za-z0-9_])"#)),
    (.awsAccessKey, regex(#"\bAKIA[A-Z0-9]{16}(?![A-Za-z0-9_])"#)),
    (.stripeKey, regex(#"\b[srp]k_(?:live|test)_[A-Za-z0-9]{16,}(?![A-Za-z0-9_])"#)),
    (.openAIToken, regex(#"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_])"#)),
    (.googleAPIKey, regex(#"\bAIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_])"#)),
    (.jsonWebToken, regex(#"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_])"#))
  ]

  static func detect(
    _ text: String,
    sourceBundleId: String? = nil,
    sourceApp: String? = nil
  ) -> Reason? {
    let value = text.clipboardTrimmed
    guard !value.isEmpty else { return nil }

    if value.contains("-----BEGIN "), value.contains("PRIVATE KEY-----") {
      return .privateKey
    }
    if let match = tokenPatterns.first(where: { matches($0.1, in: value) }) {
      return match.0
    }
    if containsCreditCard(value) { return .creditCard }
    if looksLikeOneTimeCode(value, sourceBundleId: sourceBundleId, sourceApp: sourceApp) {
      return .oneTimeCode
    }
    if looksHighEntropy(value) { return .highEntropyToken }

    let lowered = value.lowercased()
    if lowered.contains("password")
      || lowered.contains("secret")
      || lowered.contains("api_key")
      || looksLikeSecretAssignment(lowered) {
      return .keyword
    }
    return nil
  }

  static func isLikelySensitive(
    _ text: String,
    sourceBundleId: String? = nil,
    sourceApp: String? = nil
  ) -> Bool {
    detect(text, sourceBundleId: sourceBundleId, sourceApp: sourceApp) != nil
  }

  private static func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern)
  }

  private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  private static func looksHighEntropy(_ text: String) -> Bool {
    guard (32...256).contains(text.count),
          !text.contains(where: \.isWhitespace) else {
      return false
    }

    var characterClasses = 0
    var hasSymbol = false
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 48...57: characterClasses |= 1
      case 65...90: characterClasses |= 2
      case 97...122: characterClasses |= 4
      case 43, 45, 46, 47, 61, 95: hasSymbol = true
      default: return false
      }
    }
    return characterClasses.nonzeroBitCount >= 2 && hasSymbol
  }

  private static func looksLikeOneTimeCode(
    _ text: String,
    sourceBundleId: String?,
    sourceApp: String?
  ) -> Bool {
    guard (6...8).contains(text.count), text.allSatisfy(\.isNumber) else {
      return false
    }
    let source = "\(sourceBundleId ?? "") \(sourceApp ?? "")".lowercased()
    return ["auth", "1password", "bitwarden", "lastpass", "keeper", "dashlane"]
      .contains(where: source.contains)
  }

  private static func containsCreditCard(_ text: String) -> Bool {
    var digits: [Int] = []
    func isCard(_ digits: [Int]) -> Bool {
      guard (13...19).contains(digits.count),
            let first = digits.first,
            digits.contains(where: { $0 != first }) else {
        return false
      }
      var sum = 0
      for (index, digit) in digits.reversed().enumerated() {
        let doubled = index.isMultiple(of: 2) ? digit : digit * 2
        sum += doubled > 9 ? doubled - 9 : doubled
      }
      return sum.isMultiple(of: 10)
    }

    for character in text {
      if let digit = character.wholeNumberValue {
        digits.append(digit)
      } else if (character == " " || character == "-"), !digits.isEmpty {
        continue
      } else {
        if isCard(digits) { return true }
        digits.removeAll(keepingCapacity: true)
      }
    }
    return isCard(digits)
  }

  private static func looksLikeSecretAssignment(_ text: String) -> Bool {
    let keys = [
      "api_key", "apikey", "access_token", "auth_token", "client_secret",
      "private_token", "refresh_token", "secret_key", "passwd"
    ]
    for key in keys {
      guard let range = text.range(of: key) else { continue }
      let suffix = text[range.upperBound...].drop(while: \.isWhitespace)
      guard suffix.first == "=" || suffix.first == ":" else { continue }
      let value = suffix.dropFirst().drop {
        $0.isWhitespace || $0 == "\"" || $0 == "'"
      }
      if value.prefix(while: {
        !$0.isWhitespace && $0 != "\"" && $0 != "'" && $0 != ","
      }).count >= 8 {
        return true
      }
    }
    return false
  }
}
