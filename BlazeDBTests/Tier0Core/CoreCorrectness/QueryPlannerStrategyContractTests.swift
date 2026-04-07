import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

#if !BLAZEDB_LINUX_CORE
final class QueryPlannerStrategyContractTests: XCTestCase {
    private var tempURL: URL?
    private var db: BlazeDBClient?

    override func setUpWithError() throws {
        try super.setUpWithError()
        BlazeDBClient.clearCachedKey()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlannerContract-\(UUID().uuidString).blazedb")
        let dbURL = try XCTUnwrap(tempURL)
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(
            at: dbURL
                .deletingPathExtension()
                .appendingPathExtension("meta")
        )
        db = try BlazeDBClient(
            name: "planner_contract_test",
            fileURL: dbURL,
            password: "SecureTestDB-456!"
        )
    }

    override func tearDownWithError() throws {
        try db?.close()
        db = nil
        if let dbURL = tempURL {
            try? FileManager.default.removeItem(at: dbURL)
            try? FileManager.default.removeItem(
                at: dbURL
                    .deletingPathExtension()
                    .appendingPathExtension("meta")
            )
        }
        BlazeDBClient.clearCachedKey()
        try super.tearDownWithError()
    }

    func testVectorQueryPlannerUsesExecutableStrategyAndMatchesExecution() throws {
        let vectorData = encodeVector([1.0, 0.0, 0.0, 0.0])
        let records = (0..<2501).map { i in
            BlazeDataRecord([
                "id": .int(i),
                "embedding": .data(vectorData)
            ])
        }
        _ = try XCTUnwrap(db).insertMany(records)

        let plannedQuery = try XCTUnwrap(db).query()
            .vectorNearest(field: "embedding", to: [1.0, 0.0, 0.0, 0.0], limit: 50, threshold: 0.0)

        let plan = try plannedQuery.getAdvancedPlan(collection: try XCTUnwrap(db).collection)
        switch plan.strategy {
        case .sequential:
            break
        default:
            XCTFail("Planner chose non-executable strategy \(plan.strategy) for vector query fallback path")
        }

        let plannedResult = try plannedQuery.executeWithPlanner()
        let baselineResult = try XCTUnwrap(db).query()
            .vectorNearest(field: "embedding", to: [1.0, 0.0, 0.0, 0.0], limit: 50, threshold: 0.0)
            .execute()

        XCTAssertEqual(plannedResult.count, baselineResult.count)
        XCTAssertGreaterThan(plannedResult.count, 0)
    }

    private func encodeVector(_ values: [Float]) -> Data {
        var copy = values
        return copy.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
#endif
