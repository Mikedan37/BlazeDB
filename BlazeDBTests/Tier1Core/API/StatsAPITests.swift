import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class StatsAPITests: XCTestCase {
    private var dbURL: URL?

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-api-\(UUID().uuidString).blazedb")
    }

    override func tearDownWithError() throws {
        let metaURL = try requireFixture(dbURL).deletingPathExtension().appendingPathExtension("meta")
        try? FileManager.default.removeItem(at: try requireFixture(dbURL))
        try? FileManager.default.removeItem(at: try requireFixture(metaURL))
    }

    func testStatsPrettyPrint_IndicatesCacheHitRateUnavailable() throws {
        let db = try BlazeDBClient(name: "stats-api", fileURL: try requireFixture(dbURL), password: "StatsPass-123!")
        defer { try? try requireFixture(db).close() }

        _ = try requireFixture(db).insert(BlazeDataRecord(["name": .string("alice")]))
        let stats = try requireFixture(db).stats()
        let printed = stats.prettyPrint()

        XCTAssertTrue(
            printed.contains("Cache Hit Rate: unavailable"),
            "Stats output should explicitly report when cache hit rate is unavailable instead of silently omitting it"
        )
    }
}
