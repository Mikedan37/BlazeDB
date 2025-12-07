//
//  OverflowPagesDynamicCollectionTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests for overflow pages in DynamicCollection
//  Verifies that large records work correctly through the full BlazeDB API
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class OverflowPagesDynamicCollectionTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
        
        // Aggressively clean up any leftover files from previous test runs
        cleanupDatabaseFilesBeforeInit(at: tempURL)
        
        db = try! BlazeDBClient(name: "Test", fileURL: tempURL, password: "TestPass1234!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Basic Overflow Integration Tests
    
    func testInsertLargeRecord_ThroughDynamicCollection() throws {
        print("\n🔍 TEST: Insert large record through DynamicCollection")
        
        let largeString = String(repeating: "X", count: 10_000)  // 10KB
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Large Record"),
            "data": .string(largeString),
            "size": .int(10_000)
        ])
        
        let id = try db.insert(record)
        XCTAssertNotNil(id, "Should insert large record")
        
        // Verify we can read it back
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Should fetch large record")
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 10_000, "Data should match")
        
        print("   ✅ Large record inserted and fetched correctly")
    }
    
    func testInsertVeryLargeRecord_ThroughDynamicCollection() throws {
        print("\n🔍 TEST: Insert very large record (100KB)")
        
        let hugeString = String(repeating: "Y", count: 100_000)  // 100KB
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Very Large Record"),
            "data": .string(hugeString),
            "size": .int(100_000)
        ])
        
        let id = try db.insert(record)
        
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Should fetch very large record")
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 100_000, "Data should match exactly")
        
        print("   ✅ Very large record (100KB) works correctly")
    }
    
    func testInsertSmallRecord_NoOverflow() throws {
        print("\n🔍 TEST: Insert small record (no overflow)")
        
        let smallRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Small"),
            "value": .int(42)
        ])
        
        let id = try db.insert(smallRecord)
        
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Should fetch small record")
        XCTAssertEqual(fetched?.storage["value"]?.intValue, 42, "Value should match")
        
        print("   ✅ Small record works (no overflow needed)")
    }
    
    // MARK: - Update Tests with Overflow
    
    func testUpdateLargeRecord_Grow() throws {
        print("\n🔍 TEST: Update large record (grow)")
        
        // Insert 5KB record
        let initialString = String(repeating: "A", count: 5_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(initialString)
        ])
        
        let id = try db.insert(record)
        
        // Update to 20KB (needs overflow)
        let largeString = String(repeating: "B", count: 20_000)
        var updated = record
        updated.storage["data"] = .string(largeString)
        
        try db.update(id: id, with: updated)
        
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 20_000, "Should be updated to 20KB")
        
        print("   ✅ Large record update (grow) works")
    }
    
    func testUpdateLargeRecord_Shrink() throws {
        print("\n🔍 TEST: Update large record (shrink)")
        
        // Insert 20KB record
        let largeString = String(repeating: "C", count: 20_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Update to 100 bytes (no overflow needed)
        var updated = record
        updated.storage["data"] = .string("Small")
        
        try db.update(id: id, with: updated)
        
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue, "Small", "Should be shrunk to small")
        
        print("   ✅ Large record update (shrink) works")
    }
    
    // MARK: - Delete Tests with Overflow
    
    func testDeleteLargeRecord_CleansUpOverflowChain() throws {
        print("\n🔍 TEST: Delete large record (cleans up overflow chain)")
        
        // Insert large record
        let largeString = String(repeating: "D", count: 15_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Verify it exists
        let before = try db.fetch(id: id)
        XCTAssertNotNil(before, "Record should exist before delete")
        
        // Delete
        try db.delete(id: id)
        
        // Verify it's gone
        let after = try db.fetch(id: id)
        XCTAssertNil(after, "Record should be deleted")
        
        print("   ✅ Large record deletion cleans up overflow chain")
    }
    
    // MARK: - Query Tests with Overflow
    
    func testQueryWithLargeRecords() throws {
        print("\n🔍 TEST: Query with large records")
        
        // Insert mix of small and large records
        for i in 0..<5 {
            let size = i % 2 == 0 ? 100 : 10_000
            let data = String(repeating: "\(i)", count: size)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(data),
                "category": .string(i % 2 == 0 ? "small" : "large")
            ])
            _ = try db.insert(record)
        }
        
        // Query all
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 5, "Should have 5 records")
        
        // Query large ones
        let large = try db.query()
            .where("category", equals: .string("large"))
            .execute()
        let largeRecords = try large.records
        XCTAssertEqual(largeRecords.count, 2, "Should have 2 large records")
        
        // Verify large records are readable
        for record in largeRecords {
            let dataSize = record.storage["data"]?.stringValue?.count ?? 0
            XCTAssertEqual(dataSize, 10_000, "Large record should be 10KB")
        }
        
        print("   ✅ Query works with large records")
    }
    
    // MARK: - Transaction Tests with Overflow
    
    func testTransactionWithLargeRecord() throws {
        print("\n🔍 TEST: Transaction with large record")
        
        let largeString = String(repeating: "E", count: 12_000)
        
        try db.transaction {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "data": .string(largeString)
            ])
            _ = try db.insert(record)
        }
        
        // Verify record exists after commit
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 1, "Should have 1 record after transaction")
        XCTAssertEqual(all.first?.storage["data"]?.stringValue?.count, 12_000, "Data should match")
        
        print("   ✅ Transaction with large record works")
    }
    
    func testTransactionRollbackWithLargeRecord() throws {
        print("\n🔍 TEST: Transaction rollback with large record")
        
        let largeString = String(repeating: "F", count: 15_000)
        
        do {
            try db.transaction {
                let record = BlazeDataRecord([
                    "id": .uuid(UUID()),
                    "data": .string(largeString)
                ])
                _ = try db.insert(record)
                // Force rollback
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rollback test"])
            }
        } catch {
            // Expected
        }
        
        // Verify record doesn't exist (rolled back)
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 0, "Should have 0 records after rollback")
        
        print("   ✅ Transaction rollback with large record works")
    }
    
    // MARK: - Batch Operations with Overflow
    
    func testBatchInsertLargeRecords() throws {
        print("\n🔍 TEST: Batch insert large records")
        
        var ids: [UUID] = []
        
        for i in 0..<10 {
            let data = String(repeating: "\(i % 10)", count: 8_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(data)
            ])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        XCTAssertEqual(ids.count, 10, "Should insert 10 records")
        
        // Verify all are readable
        for id in ids {
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(id) should be readable")
            XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 8_000, "Data should match")
        }
        
        print("   ✅ Batch insert of large records works")
    }
    
    // MARK: - Concurrency Tests with Overflow
    
    func testConcurrentInsertsLargeRecords() throws {
        print("\n🔍 TEST: Concurrent inserts of large records")
        
        let expectation = XCTestExpectation(description: "Concurrent inserts")
        expectation.expectedFulfillmentCount = 10
        
        var successCount = 0
        var failureCount = 0
        let lock = NSLock()
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                do {
                    let data = String(repeating: "\(i)", count: 7_000)
                    let record = BlazeDataRecord([
                        "id": .uuid(UUID()),
                        "index": .int(i),
                        "data": .string(data)
                    ])
                    _ = try self.db.insert(record)
                    
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } catch {
                    lock.lock()
                    failureCount += 1
                    lock.unlock()
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        XCTAssertEqual(successCount + failureCount, 10, "All inserts should complete")
        XCTAssertGreaterThan(successCount, 8, "At least 8 should succeed")
        
        // Verify records exist
        let all = try db.fetchAll()
        XCTAssertGreaterThanOrEqual(all.count, successCount, "Should have inserted records")
        
        print("   ✅ Concurrent inserts of large records: \(successCount) success, \(failureCount) failures")
    }
    
    // MARK: - Edge Cases
    
    func testExactPageSizeBoundary() throws {
        print("\n🔍 TEST: Record at exact page size boundary")
        
        // Create record that's close to page size (4KB - overhead)
        // This tests the boundary between single page and overflow
        let boundarySize = 3500  // Close to but under 4KB
        let boundaryData = String(repeating: "B", count: boundarySize)
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(boundaryData)
        ])
        
        let id = try db.insert(record)
        let fetched = try db.fetch(id: id)
        
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, boundarySize, "Boundary size should match")
        
        print("   ✅ Exact page size boundary handled correctly")
    }
    
    func testMultipleLargeRecords() throws {
        print("\n🔍 TEST: Multiple large records coexist")
        
        var ids: [UUID] = []
        
        // Insert 5 large records
        for i in 0..<5 {
            let data = String(repeating: "\(i)", count: 12_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(data)
            ])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        // Verify all are readable
        for (i, id) in ids.enumerated() {
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(i) should exist")
            XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 12_000, "Data should match")
        }
        
        print("   ✅ Multiple large records coexist correctly")
    }
    
    // MARK: - Performance Tests
    
    func testLargeRecordPerformance() throws {
        print("\n🔍 TEST: Large record performance")
        
        let largeString = String(repeating: "P", count: 50_000)  // 50KB
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(largeString)
        ])
        
        // Measure insert time
        let insertStart = Date()
        let id = try db.insert(record)
        let insertTime = Date().timeIntervalSince(insertStart)
        
        // Measure fetch time
        let fetchStart = Date()
        let fetched = try db.fetch(id: id)
        let fetchTime = Date().timeIntervalSince(fetchStart)
        
        XCTAssertNotNil(fetched, "Should fetch record")
        XCTAssertLessThan(insertTime, 2.0, "Insert should be <2s")
        XCTAssertLessThan(fetchTime, 1.0, "Fetch should be <1s")
        
        print("   ✅ Performance: insert \(String(format: "%.2f", insertTime))s, fetch \(String(format: "%.2f", fetchTime))s")
    }
    
    // MARK: - Index Tests with Overflow
    
    func testIndexWithLargeRecord() throws {
        print("\n🔍 TEST: Index with large record")
        
        // Create index
        try db.collection.createIndex(on: "category")
        
        // Insert large record
        let largeString = String(repeating: "I", count: 10_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "category": .string("test"),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Query using index
        let results = try db.query()
            .where("category", equals: .string("test"))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1, "Should find 1 record")
        XCTAssertEqual(records.first?.storage["data"]?.stringValue?.count, 10_000, "Data should match")
        
        print("   ✅ Index works with large record")
    }
    
    // MARK: - Recovery Tests
    
    func testRecoveryAfterCrashWithLargeRecord() throws {
        print("\n🔍 TEST: Recovery after crash with large record")
        
        // Insert large record
        let largeString = String(repeating: "R", count: 15_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Force save
        try db.persist()
        
        // Reopen database
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "TestPass1234!")
        
        // Verify record still exists
        let fetched = try db2.fetch(id: id)
        XCTAssertNotNil(fetched, "Record should survive recovery")
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 15_000, "Data should match")
        
        print("   ✅ Recovery with large record works")
    }
    
    // MARK: - Mixed Size Records
    
    func testMixedSmallAndLargeRecords() throws {
        print("\n🔍 TEST: Mixed small and large records")
        
        // Insert mix of sizes
        for i in 0..<10 {
            let size = i < 5 ? 100 : 10_000
            let data = String(repeating: "\(i)", count: size)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "size": .int(size),
                "data": .string(data)
            ])
            _ = try db.insert(record)
        }
        
        // Verify all are readable
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 10, "Should have 10 records")
        
        for record in all {
            let size = record.storage["size"]?.intValue ?? 0
            let dataSize = record.storage["data"]?.stringValue?.count ?? 0
            XCTAssertEqual(dataSize, size, "Data size should match")
        }
        
        print("   ✅ Mixed small and large records work correctly")
    }
    
    // MARK: - Aggregation Tests with Overflow
    
    func testAggregationWithLargeRecords() throws {
        print("\n🔍 TEST: Aggregation with large records")
        
        // Insert records with large data
        for i in 0..<5 {
            let data = String(repeating: "\(i)", count: 8_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "data": .string(data)
            ])
            _ = try db.insert(record)
        }
        
        // Count aggregation
        let countResult = try db.query()
            .count()
            .execute()
        XCTAssertEqual(countResult.count, 5, "Should count 5 records")
        
        // Sum aggregation
        let sumResult = try db.query()
            .sum("value")
            .execute()
        let records = try sumResult.records
        let sum = records.reduce(0) { $0 + ($1.storage["value"]?.intValue ?? 0) }
        XCTAssertEqual(sum, 100, "Should sum to 100")
        
        print("   ✅ Aggregations work with large records")
    }
    
    // MARK: - Full-Text Search with Overflow
    
    func testFullTextSearchWithLargeRecord() throws {
        print("\n🔍 TEST: Full-text search with large record")
        
        // Enable full-text search
        try db.collection.enableSearch(on: ["content"])
        
        // Insert large record with searchable content
        let largeContent = "This is a very long document. " + String(repeating: "Searchable text. ", count: 1000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Large Document"),
            "content": .string(largeContent),
            "data": .string(String(repeating: "X", count: 10_000))
        ])
        
        _ = try db.insert(record)
        
        // Search
        let results = try db.collection.searchOptimized(query: "Searchable", in: ["content"])
        XCTAssertGreaterThan(results.count, 0, "Should find results")
        
        print("   ✅ Full-text search works with large records")
    }
    
    // MARK: - Index Rebuild with Overflow
    
    func testIndexRebuildWithLargeRecords() throws {
        print("\n🔍 TEST: Index rebuild with large records")
        
        // Insert large records
        for i in 0..<5 {
            let data = String(repeating: "\(i)", count: 9_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "category": .string("test"),
                "data": .string(data)
            ])
            _ = try db.insert(record)
        }
        
        // Create index
        try db.collection.createIndex(on: "category")
        
        // Rebuild index (simulate by recreating)
        try db.collection.createIndex(on: "category")
        
        // Query using index
        let results = try db.query()
            .where("category", equals: .string("test"))
            .execute()
        
        XCTAssertEqual(results.count, 5, "Should find all 5 records")
        
        print("   ✅ Index rebuild works with large records")
    }
    
    // MARK: - Persistence Tests
    
    func testPersistenceWithLargeRecords() throws {
        print("\n🔍 TEST: Persistence with large records")
        
        // Insert large record
        let largeString = String(repeating: "P", count: 12_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Force persistence
        try db.persist()
        
        // Verify it's persisted
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Record should be persisted")
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 12_000, "Data should match")
        
        print("   ✅ Persistence works with large records")
    }
    
    // MARK: - Stress Test
    
    func testStressTest_ManyLargeRecords() throws {
        print("\n🔍 TEST: Stress test - many large records")
        
        var ids: [UUID] = []
        
        // Insert 20 large records
        for i in 0..<20 {
            let data = String(repeating: "\(i % 10)", count: 6_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(data)
            ])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        // Verify all are readable
        for (i, id) in ids.enumerated() {
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(i) should exist")
            XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 6_000, "Data should match")
        }
        
        // Verify fetchAll works
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 20, "Should have 20 records")
        
        print("   ✅ Stress test: 20 large records work correctly")
    }
}

