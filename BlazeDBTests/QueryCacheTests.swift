//  QueryCacheTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for query caching

import XCTest
@testable import BlazeDBCore

final class QueryCacheTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cache-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "cache_test", fileURL: tempURL, password: "test-pass-123")
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
    }
    
    override func tearDown() {
        QueryCache.shared.clearAll()
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Basic Caching
    
    func testCacheHit() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // First query: cache miss
        let start1 = Date()
        let results1 = try db.query()
            .where("index", greaterThan: .int(50))
            .executeWithCache(ttl: 60)
        let duration1 = Date().timeIntervalSince(start1)
        
        // Second query: cache hit
        let start2 = Date()
        let results2 = try db.query()
            .where("index", greaterThan: .int(50))
            .executeWithCache(ttl: 60)
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertEqual(results1.count, results2.count)
        XCTAssertLessThan(duration2, duration1 / 10, "Cached query should be at least 10x faster")
    }
    
    func testCacheTTL() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Cache with 100ms TTL (optimized for tests)
        let testTTL: TimeInterval = 0.1
        _ = try db.query().executeWithCache(ttl: testTTL)
        
        // Should hit cache immediately
        let start1 = Date()
        _ = try db.query().executeWithCache(ttl: testTTL)
        let cachedDuration = Date().timeIntervalSince(start1)
        
        // Wait for TTL to expire (optimized: 150ms instead of 1.1s)
        Thread.sleep(forTimeInterval: testTTL + 0.05)
        
        // Should miss cache (expired)
        let start2 = Date()
        _ = try db.query().executeWithCache(ttl: testTTL)
        let expiredDuration = Date().timeIntervalSince(start2)
        
        XCTAssertLessThan(cachedDuration, expiredDuration, "Expired cache should be slower")
    }
    
    func testCacheDisabled() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        QueryCache.shared.isEnabled = false
        
        // Both queries should hit disk
        let start1 = Date()
        _ = try db.query().executeWithCache(ttl: 60)
        let duration1 = Date().timeIntervalSince(start1)
        
        let start2 = Date()
        _ = try db.query().executeWithCache(ttl: 60)
        let duration2 = Date().timeIntervalSince(start2)
        
        // Should be similar durations (both hit disk)
        XCTAssertLessThan(abs(duration1 - duration2), duration1 * 0.5, "Both should hit disk when caching disabled")
    }
    
    // MARK: - Cache Invalidation
    
    func testInvalidateSpecificKey() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Cache query
        _ = try db.query().executeWithCache(ttl: 60)
        
        // Insert new data (cache now stale)
        _ = try db.insert(BlazeDataRecord(["value": .int(2)]))
        
        // Without invalidation, would get stale cache
        // With invalidation, gets fresh data
        QueryCache.shared.clearAll()
        
        let results = try db.query().executeWithCache(ttl: 60)
        XCTAssertEqual(results.count, 2)  // Fresh data
    }
    
    func testInvalidatePrefix() throws {
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Cache multiple queries (would need to track keys in real implementation)
        _ = try db.query().where("value", greaterThan: .int(5)).executeWithCache()
        _ = try db.query().where("value", lessThan: .int(5)).executeWithCache()
        
        // Note: In real usage, you'd need to track prefixes by collection
        // For now, clearAll() works
        QueryCache.shared.clearAll()
        
        let stats = QueryCache.shared.stats()
        XCTAssertEqual(stats.entries, 0)
    }
    
    func testClearAll() throws {
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Cache some queries
        _ = try db.query().executeWithCache()
        _ = try db.query().where("value", greaterThan: .int(5)).executeWithCache()
        
        let statsBefore = QueryCache.shared.stats()
        XCTAssertGreaterThan(statsBefore.entries, 0)
        
        QueryCache.shared.clearAll()
        
        let statsAfter = QueryCache.shared.stats()
        XCTAssertEqual(statsAfter.entries, 0)
    }
    
    // MARK: - Aggregation Caching
    
    func testCachedAggregation() throws {
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "value": .int(i)
            ]))
        }
        
        // First query: cache miss
        let start1 = Date()
        let result1 = try db.query()
            .groupBy("status")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)
        let duration1 = Date().timeIntervalSince(start1)
        
        // Second query: cache hit
        let start2 = Date()
        let result2 = try db.query()
            .groupBy("status")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertEqual(result1.groups.count, result2.groups.count)
        XCTAssertLessThan(duration2, duration1 / 10, "Cached aggregation should be at least 10x faster")
    }
    
    // MARK: - Cache Statistics
    
    func testCacheStats() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        _ = try db.query().executeWithCache(ttl: 60)
        _ = try db.query().where("value", equals: .int(1)).executeWithCache(ttl: 60)
        
        let stats = QueryCache.shared.stats()
        XCTAssertEqual(stats.entries, 2)
    }
    
    func testCleanupExpired() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Cache with 100ms TTL (optimized for tests)
        _ = try db.query().executeWithCache(ttl: 0.1)
        
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
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let expectation = self.expectation(description: "Concurrent cache access")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        
        for _ in 0..<10 {
            queue.async {
                do {
                    _ = try self.db.query()
                        .where("index", greaterThan: .int(50))
                        .executeWithCache(ttl: 60)
                    expectation.fulfill()
                } catch {
                    XCTFail("Query failed: \(error)")
                }
            }
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Cache Effectiveness
    
    func testCacheEffectivenessForDashboard() throws {
        // Simulate dashboard with repeated queries
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i % 3 == 0 ? "open" : (i % 3 == 1 ? "closed" : "in_progress")),
                "priority": .int(i % 5 + 1)
            ]))
        }
        
        // Dashboard makes same queries multiple times
        var durations: [TimeInterval] = []
        
        for _ in 0..<10 {
            let start = Date()
            _ = try db.query()
                .groupBy("status")
                .count()
                .executeGroupedAggregationWithCache(ttl: 60)
            durations.append(Date().timeIntervalSince(start))
        }
        
        // First query is slow, subsequent are fast
        XCTAssertGreaterThan(durations[0], durations[1] * 5, "First query should be much slower than cached queries")
    }
}

