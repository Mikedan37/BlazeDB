import XCTest
@testable import BlazeDBCore

final class HealthAPITests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        let tmp = FileManager.default.temporaryDirectory
        for name in ["health-api-1", "health-api-2"] {
            try? FileManager.default.removeItem(
                at: tmp.appendingPathComponent("\(name).blazedb")
            )
            try? FileManager.default.removeItem(
                at: tmp.appendingPathComponent("\(name).meta")
            )
        }
    }

    func testHealthReturnsBlessedType() throws {
        let db = try BlazeDBClient.openForTesting(name: "health-api-1", password: "Test-Health-123!")
        defer { try? db.close() }

        let report = try db.health()
        // HealthReport is the blessed return type with status, reasons, suggestedActions
        XCTAssertNotNil(report.status)
        XCTAssertNotNil(report.reasons)
        XCTAssertNotNil(report.suggestedActions)
    }

    func testHealthReportsOKForFreshDatabase() throws {
        let db = try BlazeDBClient.openForTesting(name: "health-api-2", password: "Test-Health-123!")
        defer { try? db.close() }

        let report = try db.health()
        // A fresh empty database should be healthy
        XCTAssertEqual(report.status, .ok)
        // HealthAnalyzer always populates reasons (e.g., "All checks passed" when OK)
        XCTAssertFalse(report.reasons.isEmpty, "HealthReport should always provide reasons")
        XCTAssertTrue(report.suggestedActions.isEmpty, "Fresh database should have no suggested actions")
    }
}
