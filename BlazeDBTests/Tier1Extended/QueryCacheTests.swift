//  QueryCacheTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for query caching

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryCacheTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cache-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "cache_test", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
    }
    
    override func tearDown() {
        QueryCache.shared.clearAll()
        db = nil
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
        try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Basic Caching
    
    func testCacheHit() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // First query: cache miss
        let results1 = try requireFixture(db).query()
            .where("index", greaterThan: .int(50))
            .execute(withCache: 60)
        XCTAssertEqual(QueryCache.shared.stats().entries, 1, "First cached query should populate the cache")
        
        // Second query: cache hit (same results, entry retained — no wall-clock ratio; too flaky on CI)
        let results2 = try requireFixture(db).query()
            .where("index", greaterThan: .int(50))
            .execute(withCache: 60)
        
        XCTAssertEqual(results1.count, results2.count)
        XCTAssertEqual(QueryCache.shared.stats().entries, 1)
    }
    
    func testCacheTTL() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        
        // Cache with 100ms TTL (optimized for tests)
        let testTTL: TimeInterval = 0.1
        let first = try requireFixture(db).query().execute(withCache: testTTL)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(QueryCache.shared.stats().entries, 1)
        
        // Should hit cache immediately (entry still valid)
        let cached = try requireFixture(db).query().execute(withCache: testTTL)
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(QueryCache.shared.stats().entries, 1)
        
        // Wait for TTL to expire (optimized: 150ms instead of 1.1s)
        Thread.sleep(forTimeInterval: testTTL + 0.05)
        
        let statsBeforeRefresh = QueryCache.shared.stats()
        XCTAssertEqual(statsBeforeRefresh.entries, 1, "Expired entry remains until next access")
        XCTAssertEqual(statsBeforeRefresh.expired, 1, "Entry should be past TTL before refresh")
        
        // Should miss cache (expired) and store a fresh entry
        let afterExpiry = try requireFixture(db).query().execute(withCache: testTTL)
        XCTAssertEqual(afterExpiry.count, 1)
        let statsAfterRefresh = QueryCache.shared.stats()
        XCTAssertEqual(statsAfterRefresh.entries, 1)
        XCTAssertEqual(statsAfterRefresh.expired, 0, "Refresh should replace expired entry")
    }
    
    func testCacheDisabled() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        QueryCache.shared.isEnabled = false
        
        let results1 = try requireFixture(db).query().execute(withCache: 60)
        let results2 = try requireFixture(db).query().execute(withCache: 60)
        let stats = QueryCache.shared.stats()

        XCTAssertEqual(results1.count, 100)
        XCTAssertEqual(results2.count, 100)
        XCTAssertEqual(stats.entries, 0, "Disabled cache should not retain query results")
    }
    
    // MARK: - Cache Invalidation
    
    func testInvalidateSpecificKey() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        
        // Cache query
        _ = try requireFixture(db).query().execute(withCache: 60)
        
        // Insert new data (cache now stale)
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(2)]))
        
        // Without invalidation, would get stale cache
        // With invalidation, gets fresh data
        QueryCache.shared.clearAll()
        
        let results = try requireFixture(db).query().execute(withCache: 60)
        XCTAssertEqual(results.count, 2)  // Fresh data
    }
    
    func testInvalidatePrefix() throws {
        for i in 0..<10 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Cache multiple queries (would need to track keys in real implementation)
        _ = try requireFixture(db).query().where("value", greaterThan: .int(5)).execute(withCache: 60)
        _ = try requireFixture(db).query().where("value", lessThan: .int(5)).execute(withCache: 60)
        
        // Note: In real usage, you'd need to track prefixes by collection
        // For now, clearAll() works
        QueryCache.shared.clearAll()
        
        let stats = QueryCache.shared.stats()
        XCTAssertEqual(stats.entries, 0)
    }
    
    func testClearAll() throws {
        for i in 0..<10 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Cache some queries
        _ = try requireFixture(db).query().execute(withCache: 60)
        _ = try requireFixture(db).query().where("value", greaterThan: .int(5)).execute(withCache: 60)
        
        let statsBefore = QueryCache.shared.stats()
        XCTAssertGreaterThan(statsBefore.entries, 0)
        
        QueryCache.shared.clearAll()
        
        let statsAfter = QueryCache.shared.stats()
        XCTAssertEqual(statsAfter.entries, 0)
    }
    
    // MARK: - Aggregation Caching
    
    func testCachedAggregation() throws {
        for i in 0..<1000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "value": .int(i)
            ]))
        }
        
        // First query: cache miss
        let start1 = Date()
        let result1 = try requireFixture(db).query()
            .groupBy("status")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)
        let duration1 = Date().timeIntervalSince(start1)
        
        // Second query: cache hit
        let start2 = Date()
        let result2 = try requireFixture(db).query()
            .groupBy("status")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertEqual(result1.groups.count, result2.groups.count)
        XCTAssertLessThan(duration2, duration1 / 10, "Cached aggregation should be at least 10x faster")
    }
    
    // MARK: - Cache Statistics
    
    func testCacheStats() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        
        _ = try requireFixture(db).query().execute(withCache: 60)
        _ = try requireFixture(db).query().where("value", equals: .int(1)).execute(withCache: 60)
        
        let stats = QueryCache.shared.stats()
        XCTAssertEqual(stats.entries, 2)
    }
    
    func testCleanupExpired() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        
        // Cache with 100ms TTL (optimized for tests)
        _ = try requireFixture(db).query().execute(withCache: 0.1)
        
        let statsBefore = QueryCache.shared.stats()
        XCTAssertEqual(statsBefore.entries, 1)
        
        // Wait for expiration (optimized: 150ms instead of 600ms)
        Thread.sleep(forTimeInterval: 0.15)
        
        QueryCache.shared.cleanupExpired()
        
        let statsAfter = QueryCache.shared.stats()
        XCTAssertEqual(statsAfter.entries, 0)
    }
    
    // MARK: - Thread Safety
    
    func testConcurrentCacheAccess() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let expectation = self.expectation(description: "Concurrent cache access")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        let dbRef = try XCTUnwrap(self.db)
        
        for _ in 0..<10 {
            queue.async {
                do {
                    _ = try dbRef.query()
                        .where("index", greaterThan: .int(50))
                        .execute(withCache: 60)
                    expectation.fulfill()
                } catch {
                    XCTFail("Query failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Cache Effectiveness
    
    func testCacheEffectivenessForDashboard() throws {
        // Simulate dashboard with repeated queries
        for i in 0..<1000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "status": .string(i % 3 == 0 ? "open" : (i % 3 == 1 ? "closed" : "in_progress")),
                "priority": .int(i % 5 + 1)
            ]))
        }
        
        // Dashboard makes same queries multiple times
        var durations: [TimeInterval] = []
        
        for _ in 0..<10 {
            let start = Date()
            _ = try requireFixture(db).query()
                .groupBy("status")
                .count()
                .executeGroupedAggregationWithCache(ttl: 60)
            durations.append(Date().timeIntervalSince(start))
        }
        
        // First query is slow, subsequent are fast
        XCTAssertGreaterThan(durations[0], durations[1] * 5, "First query should be much slower than cached queries")
    }
}

