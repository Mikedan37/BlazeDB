import Foundation
import XCTest
@testable import BlazeDBCore

final class QueryCacheDatabaseIsolationTests: XCTestCase {
    private var databaseURLs: [URL] = []

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true

        let testID = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        databaseURLs = [
            directory.appendingPathComponent("QueryCacheDatabaseIsolation-A-\(testID).blazedb"),
            directory.appendingPathComponent("QueryCacheDatabaseIsolation-B-\(testID).blazedb")
        ]
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        for databaseURL in databaseURLs {
            for path in [
                databaseURL,
                databaseURL.deletingPathExtension().appendingPathExtension("meta"),
                databaseURL.deletingPathExtension().appendingPathExtension("salt"),
                databaseURL.deletingPathExtension().appendingPathExtension("wal")
            ] {
                try? FileManager.default.removeItem(at: path)
            }
        }
        super.tearDown()
    }

    func testExecuteWithCacheIsScopedPerDatabaseInstance() throws {
        let (databaseA, databaseB) = try openDatabases()
        defer {
            try? databaseA.close()
            try? databaseB.close()
        }

        // Complete all writes before the first cached query so write invalidation cannot mask a collision.
        try seed(databaseA, owner: "database-a", value: 101)
        try seed(databaseB, owner: "database-b", value: 202)

        let firstA = try databaseA.query()
            .where("kind", equals: .string("shared"))
            .execute(withCache: 60)
        XCTAssertEqual(try firstA.records.compactMap { $0.storage["owner"]?.stringValue }, ["database-a"])

        let repeatedA = try databaseA.query()
            .where("kind", equals: .string("shared"))
            .execute(withCache: 60)
        XCTAssertEqual(try repeatedA.records.compactMap { $0.storage["owner"]?.stringValue }, ["database-a"])

        let firstB = try databaseB.query()
            .where("kind", equals: .string("shared"))
            .execute(withCache: 60)
        XCTAssertEqual(try firstB.records.compactMap { $0.storage["owner"]?.stringValue }, ["database-b"])

        let repeatedB = try databaseB.query()
            .where("kind", equals: .string("shared"))
            .execute(withCache: 60)
        XCTAssertEqual(try repeatedB.records.compactMap { $0.storage["owner"]?.stringValue }, ["database-b"])
    }

    func testGroupedAggregationCacheIsScopedPerDatabaseInstance() throws {
        let (databaseA, databaseB) = try openDatabases()
        defer {
            try? databaseA.close()
            try? databaseB.close()
        }

        // Complete all writes before the first cached aggregation for the same reason as above.
        try seed(databaseA, owner: "database-a", value: 101)
        try seed(databaseB, owner: "database-b", value: 202)

        let firstA = try databaseA.query()
            .groupBy("kind")
            .sum("value", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)
        XCTAssertEqual(firstA.groups["shared"]?.sum("total") ?? 0, 101.0, accuracy: 0.001)

        let repeatedA = try databaseA.query()
            .groupBy("kind")
            .sum("value", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)
        XCTAssertEqual(repeatedA.groups["shared"]?.sum("total") ?? 0, 101.0, accuracy: 0.001)

        let firstB = try databaseB.query()
            .groupBy("kind")
            .sum("value", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)
        XCTAssertEqual(firstB.groups["shared"]?.sum("total") ?? 0, 202.0, accuracy: 0.001)

        let repeatedB = try databaseB.query()
            .groupBy("kind")
            .sum("value", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)
        XCTAssertEqual(repeatedB.groups["shared"]?.sum("total") ?? 0, 202.0, accuracy: 0.001)
    }

    private func openDatabases() throws -> (BlazeDBClient, BlazeDBClient) {
        let databaseA = try BlazeDBClient(
            name: "query_cache_isolation_a",
            fileURL: databaseURLs[0],
            password: "QueryCacheIsolation-Test-2026!"
        )
        let databaseB = try BlazeDBClient(
            name: "query_cache_isolation_b",
            fileURL: databaseURLs[1],
            password: "QueryCacheIsolation-Test-2026!"
        )
        return (databaseA, databaseB)
    }

    private func seed(_ database: BlazeDBClient, owner: String, value: Int) throws {
        try database.insert(BlazeDataRecord([
            "kind": .string("shared"),
            "owner": .string(owner),
            "value": .int(value)
        ]))
    }
}
