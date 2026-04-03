import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class GraphQueryAPITests: XCTestCase {
    private var dbURL: URL?
    private var db: BlazeDBClient?

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-query-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "graph-query", fileURL: try requireFixture(dbURL), password: "GraphPass-123!")
    }

    override func tearDownWithError() throws {
        try? try requireFixture(db).close()
        db = nil
        let metaURL = try requireFixture(dbURL).deletingPathExtension().appendingPathExtension("meta")
        try? FileManager.default.removeItem(at: try requireFixture(dbURL))
        try? FileManager.default.removeItem(at: try requireFixture(metaURL))
    }

    func testGraphCountByCategory_ReturnsGroupedPoints() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "value": .int(1)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "value": .int(2)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("closed"), "value": .int(3)]))

        let points = try requireFixture(db).graph()
            .x("status")
            .y(.count)
            .toPoints()

        XCTAssertEqual(points.count, 2, "Expected one point per category")
        let labels = Set(points.compactMap { $0.x as? String })
        XCTAssertEqual(labels, Set(["open", "closed"]))
    }

    func testGraphSumByCategory_ReturnsNumericYValues() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "value": .double(1.5)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "value": .double(2.5)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("closed"), "value": .double(3.0)]))

        let points = try requireFixture(db).graph()
            .x("status")
            .y(.sum("value"))
            .toPoints()

        XCTAssertEqual(points.count, 2)
        XCTAssertTrue(points.allSatisfy { $0.y is Double }, "Sum aggregation should produce Double y-values")
    }
}
