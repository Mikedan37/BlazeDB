import Foundation
import XCTest
@testable import BlazeDBCore

/// `generateCacheKey()` used to encode only `aggregations.count`, and HAVING
/// closures were omitted entirely. `execute(withCache:)` and
/// `executeGroupedAggregationWithCache(ttl:)` then returned another query's
/// groups (#453).
final class AggregationQueryCacheIsolationTests: XCTestCase {
    private let databaseName = "aggregation_query_cache_isolation"
    private let password = "AggregationQueryCacheIsolation-Test-2026!"
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AggregationQueryCacheIsolation-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        if let databaseURL {
            for artifact in databaseArtifacts(for: databaseURL) {
                try? FileManager.default.removeItem(at: artifact)
            }
        }
        super.tearDown()
    }

    func testSameAliasMinAndMaxDoNotShareCachedGroup() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        try seed(database)

        let minimum = try database.query()
            .groupBy("team")
            .min("amount", as: "bound")
            .execute(withCache: 60)
        let maximum = try database.query()
            .groupBy("team")
            .max("amount", as: "bound")
            .execute(withCache: 60)

        XCTAssertEqual(try minimum.grouped["red"]?["bound"]?.intValue, 10)
        XCTAssertEqual(try maximum.grouped["red"]?["bound"]?.intValue, 20)
        XCTAssertEqual(QueryCache.shared.stats().entries, 2)
    }

    func testSumAndCountDoNotShareCachedGroup() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        try seed(database)

        let summed = try database.query().groupBy("team").sum("amount").execute(withCache: 60)
        let counted = try database.query().groupBy("team").count().execute(withCache: 60)

        XCTAssertEqual(try summed.grouped["red"]?.sum("sum_amount") ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(try counted.grouped["red"]?.count, 2)
        XCTAssertEqual(QueryCache.shared.stats().entries, 2)
    }

    func testDifferentSumFieldsDoNotShareCachedGroup() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        try seed(database)

        let amount = try database.query()
            .groupBy("team")
            .sum("amount", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)
        let quantity = try database.query()
            .groupBy("team")
            .sum("qty", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)

        XCTAssertEqual(amount["red"]?.sum("total") ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(quantity["red"]?.sum("total") ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(QueryCache.shared.stats().entries, 2)
    }

    func testIdenticalGroupedCountStillReusesOneCacheEntry() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        try seed(database)

        let first = try database.query().groupBy("team").count().execute(withCache: 60)
        let second = try database.query().groupBy("team").count().execute(withCache: 60)

        XCTAssertEqual(try first.grouped["red"]?.count, 2)
        XCTAssertEqual(try second.grouped["red"]?.count, 2)
        XCTAssertEqual(QueryCache.shared.stats().entries, 1)
    }

    func testHavingDoesNotReturnCachedUnfilteredGroups() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        try seed(database)

        let everyone = try database.query().groupBy("team").count().execute(withCache: 60)
        XCTAssertEqual(try everyone.grouped.groups.count, 2)

        let onlyLarge = try database.query()
            .groupBy("team")
            .count()
            .having { ($0.count ?? 0) > 1 }
            .execute(withCache: 60)

        XCTAssertEqual(try onlyLarge.grouped.groups.count, 1)
        XCTAssertEqual(try onlyLarge.grouped["red"]?.count, 2)
        XCTAssertNil(try onlyLarge.grouped["blue"])
        XCTAssertEqual(
            QueryCache.shared.stats().entries,
            1,
            "HAVING must recompute instead of storing a closure-shaped result"
        )
    }

    func testUnfilteredGroupedCacheDoesNotReplayEarlierHavingFilter() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        try seed(database)

        let onlyLarge = try database.query()
            .groupBy("team")
            .count()
            .having { ($0.count ?? 0) > 1 }
            .executeGroupedAggregationWithCache(ttl: 60)
        XCTAssertEqual(onlyLarge.groups.count, 1)

        let everyone = try database.query()
            .groupBy("team")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)

        XCTAssertEqual(everyone.groups.count, 2)
        XCTAssertEqual(everyone["blue"]?.count, 1)
        XCTAssertEqual(QueryCache.shared.stats().entries, 1)
    }

    func testCacheKeyDistinguishesAliasTextFromAFollowingAggregation() throws {
        let database = try openDatabase()
        defer { try? database.close() }

        let injectedAlias = database.query()
            .count(as: "sum6:amount-")
            .generateCacheKey()
        let countThenSum = database.query()
            .count()
            .sum("amount")
            .generateCacheKey()

        XCTAssertNotEqual(injectedAlias, countThenSum)
    }

    private func openDatabase() throws -> BlazeDBClient {
        try BlazeDBClient(name: databaseName, fileURL: databaseURL, password: password)
    }

    private func seed(_ database: BlazeDBClient) throws {
        try database.insert(BlazeDataRecord([
            "team": .string("red"), "amount": .int(10), "qty": .int(1)
        ]))
        try database.insert(BlazeDataRecord([
            "team": .string("red"), "amount": .int(20), "qty": .int(4)
        ]))
        try database.insert(BlazeDataRecord([
            "team": .string("blue"), "amount": .int(5), "qty": .int(1)
        ]))
    }

    private func databaseArtifacts(for url: URL) -> [URL] {
        let base = url.deletingPathExtension()
        return [
            url,
            base.appendingPathExtension("meta"),
            base.appendingPathExtension("salt"),
            base.appendingPathExtension("wal")
        ]
    }
}
