import Foundation

enum ClipboardSelfWriteTracker {
  private static let queue = DispatchQueue(label: "clipboard.self-write-tracker")
  private static var changeCounts: [Int] = []

  static func mark(changeCount: Int) {
    queue.sync {
      changeCounts.append(changeCount)
      if changeCounts.count > 16 {
        changeCounts.removeFirst(changeCounts.count - 16)
      }
    }
  }

  static func consume(changeCount: Int) -> Bool {
    queue.sync {
      guard let index = changeCounts.firstIndex(of: changeCount) else {
        return false
      }
      changeCounts.remove(at: index)
      return true
    }
  }
}
