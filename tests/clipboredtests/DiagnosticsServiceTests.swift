import XCTest
@testable import ClipBored

final class DiagnosticsServiceTests: XCTestCase {
  func testCountersCanBeIncrementedAndReset() {
    let diagnostics = DiagnosticsService.shared
    diagnostics.reset()

    diagnostics.incrementMonitorTick()
    diagnostics.incrementPasteboardChange()
    diagnostics.incrementExtractionAttempt()
    diagnostics.incrementDatabaseMutation()
    diagnostics.incrementCachePurge()

    // The counters use a serial async queue for low overhead; sync through reset's queue by reading a snapshot.
    let snapshot = waitForSnapshot { diagnostics.currentSnapshot() }
    XCTAssertEqual(snapshot.monitorTicks, 1)
    XCTAssertEqual(snapshot.pasteboardChanges, 1)
    XCTAssertEqual(snapshot.extractionAttempts, 1)
    XCTAssertEqual(snapshot.databaseMutations, 1)
    XCTAssertEqual(snapshot.cachePurges, 1)

    diagnostics.reset()
    XCTAssertEqual(diagnostics.currentSnapshot(), .init(monitorTicks: 0, pasteboardChanges: 0, extractionAttempts: 0, databaseMutations: 0, cachePurges: 0))
  }

  private func waitForSnapshot(_ snapshot: @escaping () -> DiagnosticsService.Snapshot) -> DiagnosticsService.Snapshot {
    let expectation = expectation(description: "diagnostics queue")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1)
    return snapshot()
  }
}
