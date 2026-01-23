//
//  BlazeDBAsyncTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for async operations, query caching, and operation pooling
//
//  Created by Michael Danylchuk on 1/15/25.
//

import XCTest
@testable import BlazeDBCore

final class BlazeDBAsyncTests: XCTestCase {
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_\(UUID().uuidString).blazedb")
        
        db = try BlazeDBClient(name: "TestAsync", fileURL: tempURL, password: "test1234")
    }
    
    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Async Insert Tests
    
    func testAsyncInsert() async throws {
        let record = BlazeDataRecord([
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        let id = try await db.insertAsync(record)
        XCTAssertNotNil(id)
        
        // Verify with sync fetch
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.string("title"), "Test")
    }
    
    func testAsyncInsertMany() async throws {
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "value": .string("Record \(i)")
            ])
        }
        
        let ids = try await db.insertManyAsync(records)
        XCTAssertEqual(ids.count, 100)
        
        // Verify all inserted
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 100)
    }
    
    func testAsyncInsertConcurrent() async throws {
        let records = (0..<50).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "value": .string("Concurrent \(i)")
            ])
        }
        
        // Insert all concurrently
        let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
            for record in records {
                group.addTask {
                    try await self.db.insertAsync(record)
                }
            }
            
            var allIds: [UUID] = []
            for try await id in group {
                allIds.append(id)
            }
            return allIds
        }
        
        XCTAssertEqual(ids.count, 50)
        
        // Verify all inserted
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 50)
    }
    
    // MARK: - Async Fetch Tests
    
    func testAsyncFetch() async throws {
        let record = BlazeDataRecord([
            "title": .string("Async Fetch Test"),
            "value": .int(100)
        ])
        
        let id = try db.insert(record)
        
        let fetched = try await db.fetchAsync(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.string("title"), "Async Fetch Test")
        XCTAssertEqual(fetched?.int("value"), 100)
    }
    
    func testAsyncFetchAll() async throws {
        // Insert test data
        for i in 0..<20 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "value": .string("Item \(i)")
            ])
            _ = try db.insert(record)
        }
        
        let all = try await db.fetchAllAsync()
        XCTAssertEqual(all.count, 20)
    }
    
    func testAsyncFetchPage() async throws {
        // Insert test data
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "value": .string("Item \(i)")
            ])
            _ = try db.insert(record)
        }
        
        let page1 = try await db.fetchPageAsync(offset: 0, limit: 10)
        XCTAssertEqual(page1.count, 10)
        
        let page2 = try await db.fetchPageAsync(offset: 10, limit: 10)
        XCTAssertEqual(page2.count, 10)
        
        // Pages should be different
        XCTAssertNotEqual(page1.first?.uuid("id"), page2.first?.uuid("id"))
    }
    
    func testAsyncFetchConcurrent() async throws {
        // Insert test data
        let ids = (0..<50).map { i -> UUID in
            let record = BlazeDataRecord([
                "index": .int(i),
                "value": .string("Item \(i)")
            ])
            return try! db.insert(record)
        }
        
        // Fetch all concurrently
        let fetched = try await withThrowingTaskGroup(of: BlazeDataRecord?.self) { group in
            for id in ids {
                group.addTask {
                    try await self.db.fetchAsync(id: id)
                }
            }
            
            var results: [BlazeDataRecord?] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        
        XCTAssertEqual(fetched.count, 50)
        XCTAssertTrue(fetched.allSatisfy { $0 != nil })
    }
    
    // MARK: - Async Update Tests
    
    func testAsyncUpdate() async throws {
        let record = BlazeDataRecord([
            "title": .string("Original"),
            "value": .int(1)
        ])
        
        let id = try db.insert(record)
        
        let updated = BlazeDataRecord([
            "title": .string("Updated"),
            "value": .int(2)
        ])
        
        try await db.updateAsync(id: id, with: updated)
        
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.string("title"), "Updated")
        XCTAssertEqual(fetched?.int("value"), 2)
    }
    
    func testAsyncUpdateConcurrent() async throws {
        let record = BlazeDataRecord([
            "counter": .int(0)
        ])
        
        let id = try db.insert(record)
        
        // Update concurrently (last write wins)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let updated = BlazeDataRecord([
                        "counter": .int(i)
                    ])
                    try await self.db.updateAsync(id: id, with: updated)
                }
            }
            
            for try await _ in group {}
        }
        
        // Final value should be one of the updates
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        let counter = fetched?.int("counter") ?? -1
        XCTAssertTrue((1...10).contains(counter))
    }
    
    // MARK: - Async Delete Tests
    
    func testAsyncDelete() async throws {
        let record = BlazeDataRecord([
            "title": .string("To Delete")
        ])
        
        let id = try db.insert(record)
        
        try await db.deleteAsync(id: id)
        
        let fetched = try db.fetch(id: id)
        XCTAssertNil(fetched)
    }
    
    func testAsyncDeleteConcurrent() async throws {
        // Insert test data
        let ids = (0..<50).map { i -> UUID in
            let record = BlazeDataRecord([
                "index": .int(i)
            ])
            return try! db.insert(record)
        }
        
        // Delete all concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try await self.db.deleteAsync(id: id)
                }
            }
            
            for try await _ in group {}
        }
        
        // All should be deleted
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 0)
    }
    
    // MARK: - Query Caching Tests
    
    func testQueryCacheHit() async throws {
        // Insert test data
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "status": .string("open"),
                "index": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // First query (cache miss)
        let start1 = Date()
        let results1 = try await db.queryAsync(
            where: "status",
            equals: .string("open"),
            useCache: true
        )
        let duration1 = Date().timeIntervalSince(start1)
        
        // Second query (cache hit - should be faster)
        let start2 = Date()
        let results2 = try await db.queryAsync(
            where: "status",
            equals: .string("open"),
            useCache: true
        )
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertEqual(results1.count, 10)
        XCTAssertEqual(results2.count, 10)
        XCTAssertEqual(results1.map { $0.uuid("id") }, results2.map { $0.uuid("id") })
        
        // Cache hit should be faster (or at least not slower)
        // Note: This might not always be true due to system load, but cache hit should be very fast
        print("First query (cache miss): \(duration1 * 1000)ms")
        print("Second query (cache hit): \(duration2 * 1000)ms")
    }
    
    func testQueryCacheInvalidation() async throws {
        // Insert test data
        let record = BlazeDataRecord([
            "status": .string("open")
        ])
        let id = try db.insert(record)
        
        // Query (cache miss)
        let results1 = try await db.queryAsync(
            where: "status",
            equals: .string("open"),
            useCache: true
        )
        XCTAssertEqual(results1.count, 1)
        
        // Update record (should invalidate cache)
        let updated = BlazeDataRecord([
            "status": .string("closed")
        ])
        try await db.updateAsync(id: id, with: updated)
        
        // Query again (should get fresh results, not cached)
        let results2 = try await db.queryAsync(
            where: "status",
            equals: .string("open"),
            useCache: true
        )
        XCTAssertEqual(results2.count, 0) // Should be 0, not 1 (cache invalidated)
    }
    
    func testQueryCacheManualInvalidation() async throws {
        // Insert test data
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "status": .string("open"),
                "index": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // Query (cache miss)
        let results1 = try await db.queryAsync(
            where: "status",
            equals: .string("open"),
            useCache: true
        )
        XCTAssertEqual(results1.count, 10)
        
        // Manually invalidate cache
        await db.invalidateQueryCache()
        
        // Insert new record
        let newRecord = BlazeDataRecord([
            "status": .string("open"),
            "index": .int(10)
        ])
        _ = try db.insert(newRecord)
        
        // Query again (should get fresh results including new record)
        let results2 = try await db.queryAsync(
            where: "status",
            equals: .string("open"),
            useCache: true
        )
        XCTAssertEqual(results2.count, 11) // Should include new record
    }
    
    // MARK: - Operation Pool Tests
    
    func testOperationPoolLoad() async throws {
        let initialLoad = await db.getOperationPoolLoad()
        XCTAssertEqual(initialLoad, 0)
        
        // Start multiple concurrent operations
        let records = (0..<20).map { i in
            BlazeDataRecord([
                "index": .int(i)
            ])
        }
        
        // Insert concurrently (should use operation pool)
        let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
            for record in records {
                group.addTask {
                    try await self.db.insertAsync(record)
                }
            }
            
            var allIds: [UUID] = []
            for try await id in group {
                allIds.append(id)
            }
            return allIds
        }
        
        XCTAssertEqual(ids.count, 20)
        
        // Load should be back to 0 after operations complete
        let finalLoad = await db.getOperationPoolLoad()
        XCTAssertEqual(finalLoad, 0)
    }
    
    func testOperationPoolLimit() async throws {
        // Test that operation pool limits concurrent operations
        // This is harder to test directly, but we can verify operations complete successfully
        // even with many concurrent requests
        
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "value": .string("Concurrent \(i)")
            ])
        }
        
        // Insert 100 records concurrently (should be limited by pool)
        let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
            for record in records {
                group.addTask {
                    try await self.db.insertAsync(record)
                }
            }
            
            var allIds: [UUID] = []
            for try await id in group {
                allIds.append(id)
            }
            return allIds
        }
        
        XCTAssertEqual(ids.count, 100)
        
        // Verify all inserted
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 100)
    }
    
    // MARK: - Performance Tests
    
    func testAsyncVsSyncPerformance() async throws {
        // Insert test data
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "value": .string("Record \(i)")
            ])
        }
        
        // Sync insert
        let syncStart = Date()
        let syncIds = try db.insertMany(records)
        let syncDuration = Date().timeIntervalSince(syncStart)
        
        // Clear and try async
        try db.deleteMany { _ in true }
        
        let asyncStart = Date()
        let asyncIds = try await db.insertManyAsync(records)
        let asyncDuration = Date().timeIntervalSince(asyncStart)
        
        XCTAssertEqual(syncIds.count, asyncIds.count)
        
        print("Sync insert: \(syncDuration * 1000)ms")
        print("Async insert: \(asyncDuration * 1000)ms")
        
        // Async should be comparable or faster (non-blocking)
        // Note: For small datasets, sync might be faster due to overhead
        // But async allows concurrent operations which is the real benefit
    }
    
    // MARK: - Integration Tests
    
    func testAsyncFullWorkflow() async throws {
        // Insert
        let record1 = BlazeDataRecord([
            "title": .string("Task 1"),
            "status": .string("todo")
        ])
        let id1 = try await db.insertAsync(record1)
        
        let record2 = BlazeDataRecord([
            "title": .string("Task 2"),
            "status": .string("todo")
        ])
        let id2 = try await db.insertAsync(record2)
        
        // Query
        let todos = try await db.queryAsync(
            where: "status",
            equals: .string("todo"),
            useCache: true
        )
        XCTAssertEqual(todos.count, 2)
        
        // Update
        let updated = BlazeDataRecord([
            "title": .string("Task 1"),
            "status": .string("done")
        ])
        try await db.updateAsync(id: id1, with: updated)
        
        // Query again (cache should be invalidated)
        let remainingTodos = try await db.queryAsync(
            where: "status",
            equals: .string("todo"),
            useCache: true
        )
        XCTAssertEqual(remainingTodos.count, 1)
        
        // Delete
        try await db.deleteAsync(id: id2)
        
        // Final query
        let finalTodos = try await db.queryAsync(
            where: "status",
            equals: .string("todo"),
            useCache: true
        )
        XCTAssertEqual(finalTodos.count, 0)
    }
}

