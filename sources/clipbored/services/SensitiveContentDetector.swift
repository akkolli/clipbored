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

  static func detect(_ text: String, sourceBundleId: String? = nil, sourceApp: String? = nil) -> Reason? {
    let trimmed = text.clipboardTrimmed
    guard !trimmed.isEmpty else { return nil }
    let bytes = Array(trimmed.utf8)

    if containsPrivateKey(trimmed) { return .privateKey }
    if containsBearerToken(bytes) { return .bearerToken }
    if containsGitHubToken(bytes) { return .githubToken }
    if containsSlackToken(bytes) { return .slackToken }
    if containsAWSAccessKey(bytes) { return .awsAccessKey }
    if containsStripeKey(bytes) { return .stripeKey }
    if containsOpenAIToken(bytes) { return .openAIToken }
    if containsGoogleAPIKey(bytes) { return .googleAPIKey }
    if containsJSONWebToken(bytes) { return .jsonWebToken }
    if containsCreditCard(trimmed) { return .creditCard }
    if looksLikeOneTimeCode(trimmed, sourceBundleId: sourceBundleId, sourceApp: sourceApp) { return .oneTimeCode }
    if looksHighEntropy(trimmed) { return .highEntropyToken }

    let lowered = trimmed.lowercased()
    if lowered.contains("password") || lowered.contains("secret") || lowered.contains("api_key") || looksLikeSecretAssignment(lowered) {
      return .keyword
    }

    return nil
  }

  static func isLikelySensitive(_ text: String, sourceBundleId: String? = nil, sourceApp: String? = nil) -> Bool {
    detect(text, sourceBundleId: sourceBundleId, sourceApp: sourceApp) != nil
  }

  private static func containsPrivateKey(_ text: String) -> Bool {
    text.contains("-----BEGIN ") && text.contains("PRIVATE KEY-----")
  }

  private static func looksHighEntropy(_ text: String) -> Bool {
    let candidate = text.clipboardTrimmed
    guard candidate.count >= 32, candidate.count <= 256 else { return false }
    guard !candidate.contains(where: { $0.isWhitespace }) else { return false }

    var hasLower = false
    var hasUpper = false
    var hasDigit = false
    var symbolCount = 0

    for scalar in candidate.unicodeScalars {
      let value = scalar.value
      if value >= 48, value <= 57 {
        hasDigit = true
      } else if value >= 65, value <= 90 {
        hasUpper = true
      } else if value >= 97, value <= 122 {
        hasLower = true
      } else if value == 95 || value == 45 || value == 46 || value == 43 || value == 47 || value == 61 {
        symbolCount += 1
      } else {
        return false
      }
    }

    let classCount = (hasLower ? 1 : 0) + (hasUpper ? 1 : 0) + (hasDigit ? 1 : 0)
    return classCount >= 2 && symbolCount > 0
  }

  private static func looksLikeOneTimeCode(_ text: String, sourceBundleId: String?, sourceApp: String?) -> Bool {
    let value = text.clipboardTrimmed
    guard value.count >= 6, value.count <= 8, value.allSatisfy({ $0.isNumber }) else { return false }

    let source = ((sourceBundleId ?? "") + " " + (sourceApp ?? "")).lowercased()
    guard !source.isEmpty else { return false }
    return source.contains("auth") ||
      source.contains("1password") ||
      source.contains("bitwarden") ||
      source.contains("lastpass") ||
      source.contains("keeper") ||
      source.contains("dashlane")
  }

  private static func containsCreditCard(_ text: String) -> Bool {
    var digits: [Int] = []

    for char in text {
      if char.isNumber, let digit = char.wholeNumberValue {
        digits.append(digit)
      } else {
        if isCreditCardGroup(digits) {
          return true
        }
        digits.removeAll(keepingCapacity: true)
      }
    }

    return isCreditCardGroup(digits)
  }

  private static func isCreditCardGroup(_ digits: [Int]) -> Bool {
    guard digits.count >= 13, digits.count <= 19, let first = digits.first else {
      return false
    }
    guard digits.contains(where: { $0 != first }) else {
      return false
    }
    return passesLuhn(digits)
  }

  private static func passesLuhn(_ digits: [Int]) -> Bool {
    var sum = 0
    var shouldDouble = false

    for digit in digits.reversed() {
      var value = digit
      if shouldDouble {
        value *= 2
        if value > 9 {
          value -= 9
        }
      }
      sum += value
      shouldDouble.toggle()
    }

    return sum % 10 == 0
  }

  private static func containsBearerToken(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 27 else { return false }
    for index in 0...(bytes.count - 6) where isWordBoundaryBefore(bytes, index) {
      guard matchesBearer(bytes, index) else { continue }
      var cursor = index + 6
      guard cursor < bytes.count, isWhitespace(bytes[cursor]) else { continue }
      while cursor < bytes.count, isWhitespace(bytes[cursor]) {
        cursor += 1
      }
      let start = cursor
      while cursor < bytes.count, isBearerByte(bytes[cursor]) {
        cursor += 1
      }
      if cursor - start >= 20, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsGitHubToken(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 34 else { return false }
    for index in 0..<(bytes.count - 3) where isWordBoundaryBefore(bytes, index) {
      let marker = bytes[index + 2]
      guard bytes[index] == 103, bytes[index + 1] == 104, (marker == 112 || marker == 111 || marker == 117 || marker == 115 || marker == 114), bytes[index + 3] == 95 else {
        continue
      }
      var cursor = index + 4
      while cursor < bytes.count, isAlphaNumeric(bytes[cursor]) || bytes[cursor] == 95 {
        cursor += 1
      }
      if cursor - (index + 4) >= 30, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsSlackToken(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 25 else { return false }
    for index in 0..<(bytes.count - 4) where isWordBoundaryBefore(bytes, index) {
      let marker = bytes[index + 3]
      guard bytes[index] == 120, bytes[index + 1] == 111, bytes[index + 2] == 120, (marker == 98 || marker == 97 || marker == 112 || marker == 114 || marker == 115), bytes[index + 4] == 45 else {
        continue
      }
      var cursor = index + 5
      while cursor < bytes.count, isAlphaNumeric(bytes[cursor]) || bytes[cursor] == 45 {
        cursor += 1
      }
      if cursor - (index + 5) >= 20, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsAWSAccessKey(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 20 else { return false }
    for index in 0...(bytes.count - 20) where isWordBoundaryBefore(bytes, index) {
      guard bytes[index] == 65, bytes[index + 1] == 75, bytes[index + 2] == 73, bytes[index + 3] == 65 else { continue }
      var cursor = index + 4
      while cursor < index + 20, isUpperAlphaNumeric(bytes[cursor]) {
        cursor += 1
      }
      if cursor == index + 20, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsStripeKey(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 24 else { return false }
    for index in 0..<(bytes.count - 8) where isWordBoundaryBefore(bytes, index) {
      let prefix = bytes[index]
      guard (prefix == 115 || prefix == 114 || prefix == 112), bytes[index + 1] == 107, bytes[index + 2] == 95 else { continue }
      let live = bytes[index + 3] == 108 && bytes[index + 4] == 105 && bytes[index + 5] == 118 && bytes[index + 6] == 101 && bytes[index + 7] == 95
      let test = bytes[index + 3] == 116 && bytes[index + 4] == 101 && bytes[index + 5] == 115 && bytes[index + 6] == 116 && bytes[index + 7] == 95
      guard live || test else { continue }
      var cursor = index + 8
      while cursor < bytes.count, isAlphaNumeric(bytes[cursor]) {
        cursor += 1
      }
      if cursor - (index + 8) >= 16, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsOpenAIToken(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 24 else { return false }
    for index in 0..<(bytes.count - 3) where isWordBoundaryBefore(bytes, index) {
      guard bytes[index] == 115, bytes[index + 1] == 107, bytes[index + 2] == 45 else { continue }
      var cursor = index + 3
      if cursor + 5 <= bytes.count,
         bytes[cursor] == 112,
         bytes[cursor + 1] == 114,
         bytes[cursor + 2] == 111,
         bytes[cursor + 3] == 106,
         bytes[cursor + 4] == 45 {
        cursor += 5
      }
      let tokenStart = cursor
      while cursor < bytes.count, isTokenByte(bytes[cursor]) {
        cursor += 1
      }
      if cursor - tokenStart >= 20, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsGoogleAPIKey(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 39 else { return false }
    for index in 0...(bytes.count - 39) where isWordBoundaryBefore(bytes, index) {
      guard bytes[index] == 65, bytes[index + 1] == 73, bytes[index + 2] == 122, bytes[index + 3] == 97 else { continue }
      var cursor = index + 4
      while cursor < index + 39, isTokenByte(bytes[cursor]) {
        cursor += 1
      }
      if cursor == index + 39, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
    }
    return false
  }

  private static func containsJSONWebToken(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 32 else { return false }
    var index = 0
    while index + 3 < bytes.count {
      guard isWordBoundaryBefore(bytes, index), bytes[index] == 101, bytes[index + 1] == 121, bytes[index + 2] == 74 else {
        index += 1
        continue
      }

      var cursor = index
      let firstStart = cursor
      while cursor < bytes.count, isBase64URLByte(bytes[cursor]) {
        cursor += 1
      }
      guard cursor - firstStart >= 8, cursor < bytes.count, bytes[cursor] == 46 else {
        index += 1
        continue
      }

      cursor += 1
      let secondStart = cursor
      while cursor < bytes.count, isBase64URLByte(bytes[cursor]) {
        cursor += 1
      }
      guard cursor - secondStart >= 8, cursor < bytes.count, bytes[cursor] == 46 else {
        index += 1
        continue
      }

      cursor += 1
      let thirdStart = cursor
      while cursor < bytes.count, isBase64URLByte(bytes[cursor]) {
        cursor += 1
      }
      if cursor - thirdStart >= 8, isWordBoundaryAfter(bytes, cursor) {
        return true
      }
      index += 1
    }
    return false
  }

  private static func looksLikeSecretAssignment(_ lowered: String) -> Bool {
    let keys = [
      "api_key",
      "apikey",
      "access_token",
      "auth_token",
      "client_secret",
      "private_token",
      "refresh_token",
      "secret_key",
      "passwd"
    ]

    for key in keys {
      guard let range = lowered.range(of: key) else { continue }
      let suffix = lowered[range.upperBound...].drop(while: { $0.isWhitespace })
      guard let separator = suffix.first, separator == "=" || separator == ":" else { continue }
      let value = suffix.dropFirst().drop(while: { $0.isWhitespace || $0 == "\"" || $0 == "'" })
      let valueLength = value.prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" && $0 != "," }.count
      if valueLength >= 8 {
        return true
      }
    }

    return false
  }

  private static func matchesBearer(_ bytes: [UInt8], _ index: Int) -> Bool {
    (bytes[index] == 98 || bytes[index] == 66) &&
      (bytes[index + 1] == 101 || bytes[index + 1] == 69) &&
      (bytes[index + 2] == 97 || bytes[index + 2] == 65) &&
      (bytes[index + 3] == 114 || bytes[index + 3] == 82) &&
      (bytes[index + 4] == 101 || bytes[index + 4] == 69) &&
      (bytes[index + 5] == 114 || bytes[index + 5] == 82)
  }

  private static func isWordBoundaryBefore(_ bytes: [UInt8], _ index: Int) -> Bool {
    index == 0 || !isWordByte(bytes[index - 1])
  }

  private static func isWordBoundaryAfter(_ bytes: [UInt8], _ index: Int) -> Bool {
    index >= bytes.count || !isWordByte(bytes[index])
  }

  private static func isWordByte(_ byte: UInt8) -> Bool {
    isAlphaNumeric(byte) || byte == 95
  }

  private static func isAlphaNumeric(_ byte: UInt8) -> Bool {
    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
  }

  private static func isUpperAlphaNumeric(_ byte: UInt8) -> Bool {
    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
  }

  private static func isBearerByte(_ byte: UInt8) -> Bool {
    isAlphaNumeric(byte) || byte == 46 || byte == 95 || byte == 45 || byte == 43 || byte == 47 || byte == 61
  }

  private static func isTokenByte(_ byte: UInt8) -> Bool {
    isAlphaNumeric(byte) || byte == 95 || byte == 45
  }

  private static func isBase64URLByte(_ byte: UInt8) -> Bool {
    isAlphaNumeric(byte) || byte == 95 || byte == 45
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 32 || byte == 9 || byte == 10 || byte == 13
  }
}
