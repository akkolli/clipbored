import Foundation

final class DiagnosticsService {
  static let shared = DiagnosticsService()

  struct Snapshot: Equatable {
    var monitorTicks: Int
    var pasteboardChanges: Int
    var extractionAttempts: Int
    var databaseMutations: Int
    var cachePurges: Int
  }

  private let queue = DispatchQueue(label: "clipboard.diagnostics", qos: .utility)
  private var snapshot = Snapshot(
    monitorTicks: 0,
    pasteboardChanges: 0,
    extractionAttempts: 0,
    databaseMutations: 0,
    cachePurges: 0
  )

  private init() {}

  func incrementMonitorTick() {
    queue.async { self.snapshot.monitorTicks += 1 }
  }

  func incrementPasteboardChange() {
    queue.async { self.snapshot.pasteboardChanges += 1 }
  }

  func incrementExtractionAttempt() {
    queue.async { self.snapshot.extractionAttempts += 1 }
  }

  func incrementDatabaseMutation() {
    queue.async { self.snapshot.databaseMutations += 1 }
  }

  func incrementCachePurge() {
    queue.async { self.snapshot.cachePurges += 1 }
  }

  func currentSnapshot() -> Snapshot {
    queue.sync { snapshot }
  }

  func reset() {
    queue.sync {
      snapshot = Snapshot(
        monitorTicks: 0,
        pasteboardChanges: 0,
        extractionAttempts: 0,
        databaseMutations: 0,
        cachePurges: 0
      )
    }
  }

}
