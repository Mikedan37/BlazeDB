import Foundation
import XCTest
@testable import BlazeDBCore

/// Filters that never record a `FilterDescriptor` used to share `generateCacheKey()`
/// with an unfiltered query. `execute(withCache:)` then returned the other query's rows.
final class QueryCacheUndescribedFilterTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueryCacheUndescribed-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        let base = databaseURL.deletingPathExtension()
        for url in [databaseURL!, base.appendingPathExtension("meta"),
                    base.appendingPathExtension("salt"), base.appendingPathExtension("wal")] {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    func testLikePatternDoesNotReuseUnfilteredOrOtherPatternCache() throws {
        try assertPatternsDoNotShareCache(first: "a%", second: "b%") { database, pattern in
            database.query().where("name", like: pattern)
        }
    }

    func testRegexPatternDoesNotReuseUnfilteredOrOtherPatternCache() throws {
        try assertPatternsDoNotShareCache(first: "^a", second: "^b") { database, pattern in
            database.query().where("name", matches: pattern)
        }
    }

    func testLegacyLikeCacheDoesNotReuseUnfilteredRows() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        _ = try database.query().executeWithCache(ttl: 60)
        let rows = try database.query().where("name", like: "a%").executeWithCache(ttl: 60)
        XCTAssertEqual(names(rows), ["alpha", "alpine"])
    }

    func testGroupedLikeFilterDoesNotReuseUnfilteredGroups() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let all = try database.query().groupBy("kind").count().execute(withCache: 60).grouped
        XCTAssertEqual(all.groups["a"]?.count, 2)
        XCTAssertEqual(all.groups["b"]?.count, 1)

        let onlyA = try database.query()
            .where("name", like: "a%")
            .groupBy("kind")
            .count()
            .execute(withCache: 60)
            .grouped
        XCTAssertEqual(onlyA.groups["a"]?.count, 2)
        XCTAssertNil(onlyA.groups["b"], "LIKE must not reuse the unfiltered group cache")

        let onlyB = try database.query()
            .where("name", like: "b%")
            .groupBy("kind")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)
        XCTAssertEqual(onlyB.groups["b"]?.count, 1)
        XCTAssertNil(onlyB.groups["a"])
    }

    func testDescribedEqualityStillConsumesPlantedCacheHit() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let query = database.query().where("name", equals: .string("alpha"))
        XCTAssertEqual(names(try query.execute(withCache: 60).records), ["alpha"])
        let key = QueryCacheNamespace.queryResult + query.generateCacheKey()
        QueryCache.shared.set(
            key: key,
            value: QueryResult.records([BlazeDataRecord(["name": .string("planted")])]),
            ttl: 60
        )
        let replay = try database.query().where("name", equals: .string("alpha")).execute(withCache: 60)
        XCTAssertEqual(names(try replay.records), ["planted"],
                       "A fully described filter must still be served from its own cache entry")
    }

    private func assertPatternsDoNotShareCache(
        first: String,
        second: String,
        _ make: (BlazeDBClient, String) -> QueryBuilder
    ) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let unfiltered = database.query()
        _ = try unfiltered.execute(withCache: 60)
        let key = QueryCacheNamespace.queryResult + unfiltered.generateCacheKey()
        QueryCache.shared.set(
            key: key,
            value: QueryResult.records([BlazeDataRecord(["name": .string("planted")])]),
            ttl: 60
        )

        let prefixA = try make(database, first).execute(withCache: 60)
        XCTAssertEqual(names(try prefixA.records), ["alpha", "alpine"])
        let prefixB = try make(database, second).execute(withCache: 60)
        XCTAssertEqual(names(try prefixB.records), ["beta"])
    }

    private func openDatabase() throws -> BlazeDBClient {
        let password = UUID().uuidString + "aA1!"
        let database = try BlazeDBClient(name: "undescribed_cache", fileURL: databaseURL, password: password)
        for (name, kind) in [("alpha", "a"), ("alpine", "a"), ("beta", "b")] {
            _ = try database.insert(BlazeDataRecord([
                "name": .string(name),
                "kind": .string(kind)
            ]))
        }
        return database
    }

    private func names(_ records: [BlazeDataRecord]) -> [String] {
        records.compactMap { $0.storage["name"]?.stringValue }.sorted()
    }
}
