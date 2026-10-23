import Foundation
import XCTest
@testable import BlazeDBCore

final class QueryCacheShapeIdentityTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueryCacheShapeIdentity-\(UUID().uuidString).blazedb")
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

    func testUnifiedAggregationOperationsHaveDistinctCacheEntries() throws {
        try assertOperations(groupedAPI: false)
    }

    func testGroupedAggregationOperationsHaveDistinctCacheEntries() throws {
        try assertOperations(groupedAPI: true)
    }

    func testUnifiedAggregationFieldsHaveDistinctCacheEntries() throws {
        try assertFields(groupedAPI: false)
    }

    func testGroupedAggregationFieldsHaveDistinctCacheEntries() throws {
        try assertFields(groupedAPI: true)
    }

    func testUnifiedAggregationAliasesHaveDistinctCacheEntries() throws {
        try assertAliases(groupedAPI: false)
    }

    func testGroupedAggregationAliasesHaveDistinctCacheEntries() throws {
        try assertAliases(groupedAPI: true)
    }

    func testUnifiedAggregationSeparatorsCannotAliasComponents() throws {
        try assertSeparators(groupedAPI: false)
    }

    func testGroupedAggregationSeparatorsCannotAliasComponents() throws {
        try assertSeparators(groupedAPI: true)
    }

    func testUnifiedAggregationSequenceHasDistinctCacheEntries() throws {
        try assertSequence(groupedAPI: false)
    }

    func testGroupedAggregationSequenceHasDistinctCacheEntries() throws {
        try assertSequence(groupedAPI: true)
    }

    func testUnifiedHavingDoesNotReuseOrStoreClosureResults() throws {
        try assertHaving(groupedAPI: false)
    }

    func testGroupedHavingDoesNotReuseOrStoreClosureResults() throws {
        try assertHaving(groupedAPI: true)
    }

    func testUnifiedIdenticalAggregationConsumesPlantedHit() throws {
        try assertPlantedHit(groupedAPI: false)
    }

    func testGroupedIdenticalAggregationConsumesPlantedHit() throws {
        try assertPlantedHit(groupedAPI: true)
    }

    func testUnifiedGroupingSeparatorsCannotAliasComponents() throws {
        try assertGroupingSeparators(groupedAPI: false)
    }

    func testGroupedGroupingSeparatorsCannotAliasComponents() throws {
        try assertGroupingSeparators(groupedAPI: true)
    }

    private func openDatabase() throws -> BlazeDBClient {
        let password = UUID().uuidString + "aA1!"
        let database = try BlazeDBClient(name: "query_cache_shape", fileURL: databaseURL, password: password)
        for (value, other) in [(10, 100), (20, 200)] {
            _ = try database.insert(BlazeDataRecord([
                "kind": .string("shared"), "value": .int(value), "other": .int(other),
                "a,b": .string("shared"), "a": .int(value), "b": .string("shared"),
                "value:part|_a12": .int(other)
            ]))
        }
        return database
    }

    private func cached(_ query: QueryBuilder, groupedAPI: Bool) throws -> GroupedAggregationResult {
        if groupedAPI {
            return try query.executeGroupedAggregationWithCache(ttl: 60)
        }
        return try query.execute(withCache: 60).grouped
    }

    private func assertOperations(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let cases: [(AggregationType, BlazeDocumentField)] = [
            (.count(as: "total"), .int(2)),
            (.sum("value", as: "total"), .double(30)),
            (.avg("value", as: "total"), .double(15)),
            (.min("value", as: "total"), .int(10)),
            (.max("value", as: "total"), .int(20))
        ]
        for (operation, expected) in cases {
            let result = try cached(database.query().groupBy("kind").aggregate([operation]), groupedAPI: groupedAPI)
            XCTAssertEqual(result.groups["shared"]?.values, ["total": expected],
                           "Each operation must return its own aggregate")
        }
    }

    private func assertFields(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        for (field, expected) in [("value", 30.0), ("other", 300.0)] {
            let result = try cached(database.query().groupBy("kind").sum(field, as: "total"), groupedAPI: groupedAPI)
            XCTAssertEqual(result.groups["shared"]?.values, ["total": .double(expected)])
        }
    }

    private func assertAliases(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        // nil and the empty alias are distinct outputs too.
        let aliases: [String?] = [nil, "", "total", "other|:_a12"]
        for alias in aliases {
            let result = try cached(database.query().groupBy("kind").sum("value", as: alias), groupedAPI: groupedAPI)
            XCTAssertEqual(result.groups["shared"]?.values, [alias ?? "sum_value": .double(30)])
        }
    }

    private func assertSeparators(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        // A colon-delimited field/alias tuple would encode these identically.
        let first = database.query().groupBy("kind").sum("value:part|_a12", as: "total")
        let second = database.query().groupBy("kind").sum("value", as: "part|_a12:total")
        XCTAssertNotEqual(first.generateCacheKey(), second.generateCacheKey())
        XCTAssertEqual(try cached(first, groupedAPI: groupedAPI).groups["shared"]?.values,
                       ["total": .double(300)])
        XCTAssertEqual(try cached(second, groupedAPI: groupedAPI).groups["shared"]?.values,
                       ["part|_a12:total": .double(30)])
    }

    private func assertGroupingSeparators(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let first = database.query().groupBy("a,b").count()
        let second = database.query().groupBy("a", "b").count()
        let repeatQuery = database.query().groupBy("a", "b").count()
        XCTAssertNotEqual(first.generateCacheKey(), second.generateCacheKey())
        XCTAssertEqual(second.generateCacheKey(), repeatQuery.generateCacheKey())
        XCTAssertEqual(try cached(first, groupedAPI: groupedAPI).groups["shared"]?.count, 2)
        XCTAssertEqual(try cached(second, groupedAPI: groupedAPI).groups.count, 2,
                       "A different grouping list must not reuse the first query's groups")
        let key = (groupedAPI ? QueryCacheNamespace.groupedAggregation : QueryCacheNamespace.queryResult)
            + second.generateCacheKey()
        let sentinel = GroupedAggregationResult(groups: ["planted": AggregationResult(values: ["count": .int(999)])])
        if groupedAPI {
            QueryCache.shared.set(key: key, value: sentinel, ttl: 60)
        } else {
            QueryCache.shared.set(key: key, value: QueryResult.grouped(sentinel), ttl: 60)
        }
        XCTAssertEqual(try cached(repeatQuery, groupedAPI: groupedAPI), sentinel,
                       "An identical grouping list must consume the planted hit")
    }

    private func assertHaving(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let all = database.query().groupBy("kind").count().having { _ in true }
        let none = database.query().groupBy("kind").count().having { _ in false }
        XCTAssertEqual(try cached(all, groupedAPI: groupedAPI).groups["shared"]?.count, 2)
        XCTAssertEqual(try cached(none, groupedAPI: groupedAPI).groups, [:], "Reject-all HAVING must reject cached groups")
        XCTAssertEqual(QueryCache.shared.stats().entries, 0, "Closure results must not enter the cache")
        QueryCache.shared.clearAll()
        XCTAssertEqual(try cached(none, groupedAPI: groupedAPI).groups, [:])
        XCTAssertEqual(try cached(all, groupedAPI: groupedAPI).groups["shared"]?.count, 2,
                       "Accept-all HAVING must not reuse reject-all results")
        XCTAssertEqual(QueryCache.shared.stats().entries, 0)
        // A cached non-HAVING shape must not satisfy a HAVING query either.
        _ = try cached(database.query().groupBy("kind").count(), groupedAPI: groupedAPI)
        XCTAssertEqual(try cached(none, groupedAPI: groupedAPI).groups, [:])
    }

    private func assertSequence(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        // Both operations write the same alias, so their order changes the output.
        let first = database.query().groupBy("kind").aggregate([.sum("value", as: "total"), .count(as: "total")])
        let second = database.query().groupBy("kind").aggregate([.count(as: "total"), .sum("value", as: "total")])
        XCTAssertEqual(try cached(first, groupedAPI: groupedAPI).groups["shared"]?.values, ["total": .int(2)])
        XCTAssertEqual(try cached(second, groupedAPI: groupedAPI).groups["shared"]?.values, ["total": .double(30)])
    }

    private func assertPlantedHit(groupedAPI: Bool) throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let query = database.query().groupBy("kind").sum("value", as: "total")
        XCTAssertEqual(try cached(query, groupedAPI: groupedAPI).groups["shared"]?.values, ["total": .double(30)])
        let key = (groupedAPI ? QueryCacheNamespace.groupedAggregation : QueryCacheNamespace.queryResult)
            + query.generateCacheKey()
        let sentinel = GroupedAggregationResult(groups: ["planted": AggregationResult(values: ["total": .double(999)])])
        if groupedAPI {
            let inserted: GroupedAggregationResult? = QueryCache.shared.get(key: key)
            XCTAssertEqual(inserted?.groups["shared"]?.values, ["total": .double(30)], "Insert must use the lookup key")
            QueryCache.shared.set(key: key, value: sentinel, ttl: 60)
        } else {
            let inserted: QueryResult? = QueryCache.shared.get(key: key)
            XCTAssertEqual(try inserted?.grouped.groups["shared"]?.values, ["total": .double(30)])
            QueryCache.shared.set(key: key, value: QueryResult.grouped(sentinel), ttl: 60)
        }
        let repeatQuery = database.query().groupBy("kind").sum("value", as: "total")
        XCTAssertEqual(try cached(repeatQuery, groupedAPI: groupedAPI), sentinel,
                       "An identical shape must consume the planted hit, not recompute storage")
    }

    #if !BLAZEDB_LINUX_CORE
    func testAsyncEqualityValuesHaveDistinctCachedRows() async throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let first = await database.query().where("value", equals: .int(10))
        let second = await database.query().where("value", equals: .int(20))
        let firstResult = try await first.execute(withCache: 60)
        let secondResult = try await second.execute(withCache: 60)
        XCTAssertEqual(try firstResult.records.compactMap { $0.storage["value"]?.intValue }, [10])
        XCTAssertEqual(try secondResult.records.compactMap { $0.storage["value"]?.intValue }, [20])
    }

    // A synchronous helper selects the sync overload even when called from an async test.
    private func syncPredicates(_ database: BlazeDBClient) -> [QueryBuilder] {
        [database.query().where("value|:_a12", equals: .int(10)),
         database.query().where("value|:_a12", notEquals: .int(10)),
         database.query().where("value|:_a12", greaterThan: .int(10)),
         database.query().where("value|:_a12", lessThan: .int(10))]
    }

    func testAsyncOverloadsMatchSyncDescriptorsFieldsAndMissingFieldSemantics() async throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let sync = syncPredicates(database)
        let asyncQueries = [await database.query().where("value|:_a12", equals: .int(10)),
                            await database.query().where("value|:_a12", notEquals: .int(10)),
                            await database.query().where("value|:_a12", greaterThan: .int(10)),
                            await database.query().where("value|:_a12", lessThan: .int(10))]
        let missing = BlazeDataRecord(["other": .int(99)])
        for (index, operation) in ["eq", "ne", "gt", "lt"].enumerated() {
            let query = asyncQueries[index]
            XCTAssertEqual(query.filterDescriptors, sync[index].filterDescriptors, operation)
            XCTAssertEqual(query.filterFields, sync[index].filterFields, operation)
            XCTAssertEqual(query.filterFields, ["value|:_a12"], operation)
            XCTAssertEqual(query.filterDescriptors.first?.field, "value|:_a12", operation)
            XCTAssertEqual(query.filterDescriptors.first?.operation, operation)
            XCTAssertEqual(query.filterDescriptors.first?.value, .int(10), operation)
            XCTAssertEqual(query.filters.first?(missing), operation == "ne", operation)
            XCTAssertEqual(query.generateCacheKey(), sync[index].generateCacheKey(), operation)
        }
    }
    #endif
}
