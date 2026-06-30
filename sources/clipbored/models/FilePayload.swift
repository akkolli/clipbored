import Foundation

enum FilePayload {
  static func paths(from payload: String) -> [String] {
    payload
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { String($0).clipboardTrimmed }
      .filter { !$0.isEmpty }
  }

  static func urls(from payload: String) -> [URL] {
    paths(from: payload).map(fileURL(from:))
  }

  static func payload(from urls: [URL]) -> String {
    urls.map(\.path).joined(separator: "\n")
  }

  static func fileURL(from value: String) -> URL {
    let trimmed = value.clipboardTrimmed
    if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed) {
      return url
    }
    return URL(fileURLWithPath: trimmed)
  }
}
