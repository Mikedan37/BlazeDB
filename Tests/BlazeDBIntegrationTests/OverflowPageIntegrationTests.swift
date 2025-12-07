//
//  OverflowPageIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests for overflow page support
//  Tests overflow pages through the full BlazeDB API
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class OverflowPageIntegrationTests: XCTestCase {
    
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
        super.tearDown()
    }
    
    // MARK: - Basic CRUD with Large Records
    
    func testInsertLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Insert large record through BlazeDBClient")
        
        // Create a large record (>4KB)
        let largeString = String(repeating: "A", count: 10_000)  // 10KB string
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Large Record"),
            "data": .string(largeString),
            "size": .int(largeString.count)
        ])
        
        // Insert through BlazeDBClient
        let id = try db.insert(record)
        print("   Inserted record with ID: \(id)")
        
        // Verify we can fetch it back
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Should fetch large record")
        XCTAssertEqual(fetched?.storage["title"]?.stringValue, "Large Record")
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 10_000)
        XCTAssertEqual(fetched?.storage["size"]?.intValue, 10_000)
        
        print("   ✅ Large record insert/fetch works through BlazeDBClient")
    }
    
    func testInsertVeryLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Insert very large record (100KB)")
        
        let veryLargeString = String(repeating: "B", count: 100_000)  // 100KB
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Very Large Record"),
            "data": .string(veryLargeString),
            "metadata": .string("This is a very large record for testing overflow pages")
        ])
        
        let id = try db.insert(record)
        print("   Inserted very large record: \(id)")
        
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Should fetch very large record")
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 100_000)
        
        print("   ✅ Very large record works")
    }
    
    func testUpdateLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Update large record")
        
        // Insert initial record
        let initialString = String(repeating: "C", count: 5_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Updatable Record"),
            "data": .string(initialString)
        ])
        
        let id = try db.insert(record)
        
        // Update to larger size
        let updatedString = String(repeating: "D", count: 20_000)
        var updated = record
        updated.storage["data"] = .string(updatedString)
        updated.storage["updated"] = .bool(true)
        
        try db.update(id: id, with: updated)
        print("   Updated record to larger size")
        
        // Verify update
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 20_000)
        XCTAssertEqual(fetched?.storage["updated"]?.boolValue, true)
        
        print("   ✅ Large record update works")
    }
    
    func testUpdateLargeRecordShrink() throws {
        print("\n🔍 INTEGRATION TEST: Update large record (shrink)")
        
        // Insert large record
        let largeString = String(repeating: "E", count: 20_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Shrinkable Record"),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Update to smaller size
        let smallString = String(repeating: "F", count: 1_000)
        var updated = record
        updated.storage["data"] = .string(smallString)
        
        try db.update(id: id, with: updated)
        print("   Updated record to smaller size")
        
        // Verify update
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 1_000)
        
        print("   ✅ Large record shrink works")
    }
    
    func testDeleteLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Delete large record")
        
        // Insert large record
        let largeString = String(repeating: "G", count: 15_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Deletable Record"),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Delete it
        try db.delete(id: id)
        print("   Deleted large record")
        
        // Verify deletion
        let fetched = try db.fetch(id: id)
        XCTAssertNil(fetched, "Large record should be deleted")
        
        print("   ✅ Large record deletion works")
    }
    
    // MARK: - Query Tests with Large Records
    
    func testQueryWithLargeRecords() throws {
        print("\n🔍 INTEGRATION TEST: Query with large records")
        
        // Insert multiple records, some large, some small
        let smallRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Small"),
            "data": .string("Small data"),
            "size": .string("small")
        ])
        
        let largeRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Large"),
            "data": .string(String(repeating: "X", count: 10_000)),
            "size": .string("large")
        ])
        
        let smallID = try db.insert(smallRecord)
        let largeID = try db.insert(largeRecord)
        
        // Query all records
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, 2, "Should fetch both records")
        
        // Query by size
        let result = try db.query()
            .where("size", equals: .string("large"))
            .execute()
        
        let largeRecords = try result.records
        XCTAssertEqual(largeRecords.count, 1, "Should find one large record")
        XCTAssertEqual(largeRecords.first?.storage["id"]?.uuidValue, largeID)
        
        print("   ✅ Query with large records works")
    }
    
    func testQueryLargeRecordFields() throws {
        print("\n🔍 INTEGRATION TEST: Query and access large record fields")
        
        let largeString = String(repeating: "Y", count: 50_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Queryable Large Record"),
            "content": .string(largeString),
            "category": .string("test")
        ])
        
        let id = try db.insert(record)
        
        // Query and access large field
        let result = try db.query()
            .where("category", equals: .string("test"))
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        
        let fetched = records.first!
        let content = fetched.storage["content"]?.stringValue
        XCTAssertNotNil(content, "Should access large field")
        XCTAssertEqual(content?.count, 50_000, "Large field should be complete")
        
        print("   ✅ Query and access large fields works")
    }
    
    // MARK: - Batch Operations with Large Records
    
    func testBatchInsertLargeRecords() throws {
        print("\n🔍 INTEGRATION TEST: Batch insert large records")
        
        var records: [BlazeDataRecord] = []
        for i in 0..<10 {
            let largeString = String(repeating: "\(i)", count: 5_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(largeString)
            ])
            records.append(record)
        }
        
        let ids = try db.insertMany(records)
        XCTAssertEqual(ids.count, 10, "Should insert all records")
        
        // Verify all records
        for (index, id) in ids.enumerated() {
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(index) should exist")
            XCTAssertEqual(fetched?.storage["index"]?.intValue, index)
            XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 5_000)
        }
        
        print("   ✅ Batch insert large records works")
    }
    
    func testBatchUpdateLargeRecords() throws {
        print("\n🔍 INTEGRATION TEST: Batch update large records")
        
        // Insert records
        var records: [BlazeDataRecord] = []
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(String(repeating: "A", count: 3_000))
            ])
            records.append(record)
        }
        
        let ids = try db.insertMany(records)
        
        // Update all to larger size
        for (index, id) in ids.enumerated() {
            var updated = records[index]
            updated.storage["data"] = .string(String(repeating: "B", count: 10_000))
            updated.storage["updated"] = .bool(true)
            try db.update(id: id, with: updated)
        }
        
        // Verify updates
        for id in ids {
            let fetched = try db.fetch(id: id)
            XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 10_000)
            XCTAssertEqual(fetched?.storage["updated"]?.boolValue, true)
        }
        
        print("   ✅ Batch update large records works")
    }
    
    // MARK: - Transaction Tests with Large Records
    
    func testTransactionWithLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Transaction with large record")
        
        let largeString = String(repeating: "T", count: 8_000)
        
        try db.beginTransaction()
        defer {
            try? db.rollbackTransaction()
        }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Transactional Large Record"),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Update within transaction
        var updated = record
        updated.storage["data"] = .string(String(repeating: "U", count: 12_000))
        try db.update(id: id, with: updated)
        
        // Verify within transaction
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 12_000)
        
        try db.commitTransaction()
        
        print("   ✅ Transaction with large record works")
    }
    
    func testTransactionRollbackLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Transaction rollback with large record")
        
        let largeString = String(repeating: "R", count: 10_000)
        
        do {
            try db.beginTransaction()
            defer {
                try? db.rollbackTransaction()
            }
            
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "title": .string("Rollback Test"),
                "data": .string(largeString)
            ])
            
            let id = try db.insert(record)
            
            // Force rollback
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test rollback"])
        } catch {
            // Expected - transaction rolled back
        }
        
        // Verify record was not inserted
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, 0, "Rolled back record should not exist")
        
        print("   ✅ Transaction rollback with large record works")
    }
    
    // MARK: - MVCC Tests with Large Records
    
    func testMVCCWithLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: MVCC with large record")
        
        // MVCC is always enabled in BlazeDB
        
        let largeString = String(repeating: "M", count: 10_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("MVCC Large Record"),
            "data": .string(largeString),
            "version": .int(1)
        ])
        
        let id = try db.insert(record)
        
        // Create multiple versions
        for version in 2...5 {
            var updated = record
            updated.storage["data"] = .string(String(repeating: "\(version)", count: 10_000))
            updated.storage["version"] = .int(version)
            try db.update(id: id, with: updated)
        }
        
        // Verify latest version
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["version"]?.intValue, 5)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.first, "5")
        
        print("   ✅ MVCC with large record works")
    }
    
    // MARK: - Sync Tests with Large Records
    
    func testSyncWithLargeRecord() async throws {
        print("\n🔍 INTEGRATION TEST: Sync with large record")
        
        // Create two databases
        let db1URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
        let db2URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "TestPass1234!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "TestPass1234!")
        
        defer {
            try? FileManager.default.removeItem(at: db1URL)
            try? FileManager.default.removeItem(at: db2URL)
        }
        
        // Insert large record in db1
        let largeString = String(repeating: "S", count: 15_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Sync Large Record"),
            "data": .string(largeString)
        ])
        
        let id = try await db1.insert(record)
        
        // Setup sync
        let topology = try await db1.sync(with: db2, mode: .bidirectional, role: .server)
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        
        // Verify record synced to db2
        let synced = try await db2.fetch(id: id)
        XCTAssertNotNil(synced, "Large record should sync")
        XCTAssertEqual(synced?.storage["data"]?.stringValue?.count, 15_000)
        
        print("   ✅ Sync with large record works")
    }
    
    // MARK: - Index Tests with Large Records
    
    func testIndexWithLargeRecord() async throws {
        print("\n🔍 INTEGRATION TEST: Index with large record")
        
        // Create index
        try await db.collection.createIndex(on: "category")
        
        // Insert large records with different categories
        let categories = ["A", "B", "C"]
        var ids: [UUID] = []
        
        for (index, category) in categories.enumerated() {
            let largeString = String(repeating: category, count: 8_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "category": .string(category),
                "data": .string(largeString),
                "index": .int(index)
            ])
            ids.append(try await db.insert(record))
        }
        
        // Query using index
        let result = try await db.query()
            .where("category", equals: .string("B"))
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.storage["id"]?.uuidValue, ids[1])
        XCTAssertEqual(records.first?.storage["data"]?.stringValue?.count, 8_000)
        
        print("   ✅ Index with large record works")
    }
    
    // MARK: - Aggregation Tests with Large Records
    
    func testAggregationWithLargeRecords() throws {
        print("\n🔍 INTEGRATION TEST: Aggregation with large records")
        
        // Insert records with large data but small numeric fields
        for i in 0..<10 {
            let largeString = String(repeating: "\(i)", count: 5_000)
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "data": .string(largeString)
            ])
            _ = try db.insert(record)
        }
        
        // Aggregate (should work even with large records)
        let result = try db.query()
            .sum("value")
            .execute()
        
        // Sum should be 0+10+20+...+90 = 450
        let aggregation = try result.aggregation
        let sum = Int(aggregation.sum("value") ?? 0)
        XCTAssertEqual(sum, 450, "Sum should be correct")
        
        print("   ✅ Aggregation with large records works")
    }
    
    // MARK: - Full-Text Search with Large Records
    
    func testFullTextSearchWithLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Full-text search with large record")
        
        // Insert large record with searchable text
        let largeText = "This is a test. " + String(repeating: "search term ", count: 1000) + " End of text."
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Searchable Large Record"),
            "content": .string(largeText)
        ])
        
        let id = try db.insert(record)
        
        // Search
        let results = try db.collection.searchOptimized(query: "search term", in: ["content"])
        XCTAssertGreaterThan(results.count, 0, "Should find record")
        XCTAssertTrue(results.contains { $0.record.storage["id"]?.uuidValue == id })
        
        print("   ✅ Full-text search with large record works")
    }
    
    // MARK: - Concurrent Operations with Large Records
    
    func testConcurrentInsertsLargeRecords() throws {
        print("\n🔍 INTEGRATION TEST: Concurrent inserts of large records")
        
        let expectation = XCTestExpectation(description: "Concurrent inserts")
        expectation.expectedFulfillmentCount = 10
        
        var insertedIDs: [UUID] = []
        let lock = NSLock()
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                do {
                    let largeString = String(repeating: "\(i)", count: 5_000)
                    let record = BlazeDataRecord([
                        "id": .uuid(UUID()),
                        "index": .int(i),
                        "data": .string(largeString)
                    ])
                    
                    let id = try self.db.insert(record)
                    
                    lock.lock()
                    insertedIDs.append(id)
                    lock.unlock()
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent insert \(i) failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        XCTAssertEqual(insertedIDs.count, 10, "All inserts should succeed")
        
        // Verify all records
        for id in insertedIDs {
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record should exist")
        }
        
        print("   ✅ Concurrent inserts of large records work")
    }
    
    // MARK: - Recovery Tests with Large Records
    
    func testRecoveryAfterCrashWithLargeRecord() throws {
        print("\n🔍 INTEGRATION TEST: Recovery after crash with large record")
        
        // Insert large record
        let largeString = String(repeating: "R", count: 10_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Recovery Test"),
            "data": .string(largeString)
        ])
        
        let id = try db.insert(record)
        
        // Simulate crash by closing database without proper shutdown
        // (In real scenario, this would be a crash)
        db = nil
        
        // Reopen database
        db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "TestPass1234!")
        
        // Verify record still exists (recovery)
        let recovered = try db.fetch(id: id)
        XCTAssertNotNil(recovered, "Large record should be recovered")
        XCTAssertEqual(recovered?.storage["data"]?.stringValue?.count, 10_000)
        
        print("   ✅ Recovery with large record works")
    }
    
    // MARK: - Edge Cases
    
    func testMixedSmallAndLargeRecords() throws {
        print("\n🔍 INTEGRATION TEST: Mixed small and large records")
        
        // Insert mix of small and large records
        for i in 0..<20 {
            let isLarge = i % 2 == 0
            let dataSize = isLarge ? 10_000 : 100
            let data = String(repeating: "\(i)", count: dataSize)
            
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "size": .string(isLarge ? "large" : "small"),
                "data": .string(data)
            ])
            
            _ = try db.insert(record)
        }
        
        // Fetch all
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, 20)
        
        // Verify sizes
        for record in allRecords {
            let size = record.storage["size"]?.stringValue ?? ""
            let dataSize = record.storage["data"]?.stringValue?.count ?? 0
            
            if size == "large" {
                XCTAssertEqual(dataSize, 10_000)
            } else {
                XCTAssertEqual(dataSize, 100)
            }
        }
        
        print("   ✅ Mixed small and large records work")
    }
    
    func testLargeRecordWithManyFields() throws {
        print("\n🔍 INTEGRATION TEST: Large record with many fields")
        
        var storage: [String: BlazeDocumentField] = [:]
        storage["id"] = .uuid(UUID())
        
        // Add many small fields
        for i in 0..<100 {
            storage["field\(i)"] = .string("Value \(i)")
        }
        
        // Add one very large field
        storage["largeField"] = .string(String(repeating: "X", count: 20_000))
        
        let record = BlazeDataRecord(storage)
        
        let id = try db.insert(record)
        
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.storage.count, 102)  // id + 100 fields + largeField
        XCTAssertEqual(fetched?.storage["largeField"]?.stringValue?.count, 20_000)
        
        print("   ✅ Large record with many fields works")
    }
    
    // MARK: - Performance Tests
    
    func testLargeRecordPerformance() throws {
        print("\n🔍 INTEGRATION TEST: Large record performance")
        
        let largeString = String(repeating: "P", count: 50_000)  // 50KB
        
        // Measure insert
        let insertStart = Date()
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(largeString)
        ])
        let id = try db.insert(record)
        let insertTime = Date().timeIntervalSince(insertStart)
        
        // Measure fetch
        let fetchStart = Date()
        let fetched = try db.fetch(id: id)
        let fetchTime = Date().timeIntervalSince(fetchStart)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.storage["data"]?.stringValue?.count, 50_000)
        
        print("   Insert time: \(String(format: "%.3f", insertTime))s")
        print("   Fetch time: \(String(format: "%.3f", fetchTime))s")
        
        // Performance expectations
        XCTAssertLessThan(insertTime, 2.0, "Insert should be <2s")
        XCTAssertLessThan(fetchTime, 1.0, "Fetch should be <1s")
        
        print("   ✅ Large record performance acceptable")
    }
}

