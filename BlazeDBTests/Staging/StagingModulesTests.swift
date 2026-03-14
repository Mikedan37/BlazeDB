import XCTest
@testable import BlazeDBSyncStaging
@testable import BlazeDBTelemetryStaging

final class StagingModulesTests: XCTestCase {
    func testLamportOrderingUsesCounterThenNodeID() {
        let nodeA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let nodeB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let earlier = StagingLamportTimestamp(counter: 1, nodeID: nodeA)
        let later = StagingLamportTimestamp(counter: 2, nodeID: nodeA)
        let tieA = StagingLamportTimestamp(counter: 5, nodeID: nodeA)
        let tieB = StagingLamportTimestamp(counter: 5, nodeID: nodeB)

        XCTAssertLessThan(earlier, later)
        XCTAssertLessThan(tieA, tieB)
    }

    func testTelemetryCollectorSummary() async {
        let collector = StagingTelemetryCollector()
        await collector.record(.init(operation: "insert", durationMS: 10, success: true))
        await collector.record(.init(operation: "update", durationMS: 20, success: false))

        let summary = await collector.summary()
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.successes, 1)
        XCTAssertEqual(summary.failures, 1)
        XCTAssertEqual(summary.avgDurationMS, 15, accuracy: 0.001)
    }
}
