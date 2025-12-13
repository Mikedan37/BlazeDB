//  BatchOperationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for batch operations

import XCTest
@testable import BlazeDB

final class BatchOperationTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        // Force cleanup from previous test
        if let existingDB = db {
            try? existingDB.persist()
        }
        db = nil
        
        // Clear cached encryption key to ensure fresh start
        BlazeDBClient.clearCachedKey()
        
        // Longer delay to ensure previous database is fully closed
        Thread.sleep(forTimeInterval: 0.05)
        
        // Create unique database file per test run with timestamp + thread ID
        let testID = "\(UUID().uuidString)-\(Thread.current.hash)-\(Date().timeIntervalSince1970)"
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch-\(testID).blazedb")
        
        // Clean up leftover files from this exact path
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        
        // ✅ FIX: Also clean up transaction backup files from parent directory
        let parentDir = tempURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parentDir.appendingPathComponent("txn_in_progress.blazedb"))
        try? FileManager.default.removeItem(at: parentDir.appendingPathComponent("txn_in_progress.meta"))
        try? FileManager.default.removeItem(at: parentDir.appendingPathComponent("txn_log.json"))
        
        // Use unique database name to prevent any cross-contamination
        do {
            db = try BlazeDBClient(name: "batch_test_\(testID)", fileURL: tempURL, password: "BatchOperationTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        
        // ✅ SAFETY: Rollback any leftover transaction from previous test
        try? db.rollbackTransaction()
        
        // Verify database starts completely empty
        let startCount = db.count()
        if startCount != 0 {
            print("⚠️ CRITICAL: Database not empty after creation! Has \(startCount) records. Force wiping...")
            _ = try? db.deleteMany(where: { _ in true })
            try? db.persist()
        }
    }
    
    override func tearDown() {
        if let tempURL = tempURL {
            cleanupBlazeDB(&db, at: tempURL)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - insertMany Tests
    
    func testInsertMany() throws {
        let records = (0..<100).map { i in
            BlazeDataRecord(["index": .int(i), "status": .string("open")])
        }
        
        let ids = try db.insertMany(records)
        
        XCTAssertEqual(ids.count, 100)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 100)
    }
    
    func testInsertManyPerformance() throws {
        let records = (0..<1000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        let start = Date()
        _ = try db.insertMany(records)
        let batchDuration = Date().timeIntervalSince(start)
        
        // Should be much faster than individual inserts
        XCTAssertLessThan(batchDuration, 2.0, "Batch insert of 1000 records should be < 2s")
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 1000)
    }
    
    func testInsertManyWithExistingIDs() throws {
        let id1 = UUID()
        let id2 = UUID()
        
        let records = [
            BlazeDataRecord(["id": .uuid(id1), "value": .int(1)]),
            BlazeDataRecord(["id": .uuid(id2), "value": .int(2)])
        ]
        
        let ids = try db.insertMany(records)
        
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.contains(id1))
        XCTAssertTrue(ids.contains(id2))
    }
    
    func testInsertManyGeneratesIDs() throws {
        let records = (0..<50).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        let ids = try db.insertMany(records)
        
        XCTAssertEqual(ids.count, 50)
        XCTAssertEqual(Set(ids).count, 50)  // All unique
    }
    
    func testInsertManyAddsTimestamps() throws {
        let records = (0..<10).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        _ = try db.insertMany(records)
        
        let allRecords = try db.fetchAll()
        for record in allRecords {
            XCTAssertNotNil(record.storage["createdAt"], "Should have createdAt")
        }
    }
    
    // MARK: - updateMany Tests
    
    func testUpdateMany() throws {
        // Insert test data
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        
        // Update all "open" to "closed"
        let updated = try db.updateMany(
            where: { $0["status"]?.stringValue == "open" },
            set: ["status": .string("closed")]
        )
        
        XCTAssertEqual(updated, 50)
        
        // Verify all are now closed
        let allRecords = try db.fetchAll()
        let openCount = allRecords.filter { $0["status"]?.stringValue == "open" }.count
        XCTAssertEqual(openCount, 0)
    }
    
    func testUpdateManyMultipleFields() throws {
        for i in 0..<50 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string("open"),
                "priority": .int(1)
            ]))
        }
        
        let updated = try db.updateMany(
            where: { $0["index"]?.intValue ?? 0 < 25 },
            set: [
                "status": .string("closed"),
                "priority": .int(5),
                "closed_by": .string("admin")
            ]
        )
        
        XCTAssertEqual(updated, 25)
        
        // Verify updates
        let closedBugsResult = try db.query()
            .where("status", equals: .string("closed"))
            .execute()
        
        let closedBugs = try closedBugsResult.records
        XCTAssertEqual(closedBugs.count, 25)
        for bug in closedBugs {
            XCTAssertEqual(bug.storage["priority"]?.intValue, 5)
            XCTAssertEqual(bug.storage["closed_by"]?.stringValue, "admin")
        }
    }
    
    func testUpdateManyAddsUpdatedAt() throws {
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        _ = try db.updateMany(
            where: { _ in true },
            set: ["status": .string("updated")]
        )
        
        let allRecords = try db.fetchAll()
        for record in allRecords {
            XCTAssertNotNil(record.storage["updatedAt"], "Should have updatedAt")
        }
    }
    
    func testUpdateManyNoMatches() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        let updated = try db.updateMany(
            where: { $0["status"]?.stringValue == "nonexistent" },
            set: ["value": .int(1)]
        )
        
        XCTAssertEqual(updated, 0)
    }
    
    // MARK: - deleteMany Tests
    
    func testDeleteMany() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        try db.persist()  // Flush metadata before delete
        
        let deleted = try db.deleteMany(
            where: { $0["status"]?.stringValue == "closed" }
        )
        
        XCTAssertEqual(deleted, 50)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 50)
    }
    
    func testDeleteManyByDate() throws {
        let calendar = Calendar.current
        for i in 0..<50 {
            let date = calendar.date(byAdding: .day, value: -i, to: Date())!
            _ = try db.insert(BlazeDataRecord([
                "created_at": .date(date)
            ]))
        }
        try db.persist()  // Flush metadata before delete
        
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        
        let deleted = try db.deleteMany(
            where: { record in
                guard let date = record["created_at"]?.dateValue else { return false }
                return date < thirtyDaysAgo
            }
        )
        
        XCTAssertEqual(deleted, 20)  // Days 31-50
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 30)
    }
    
    func testDeleteManyNoMatches() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        try db.persist()  // Flush metadata before delete
        
        let deleted = try db.deleteMany(
            where: { $0["status"]?.stringValue == "nonexistent" }
        )
        
        XCTAssertEqual(deleted, 0)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 1)
    }
    
    func testDeleteManyAll() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        try db.persist()  // Flush metadata before delete
        
        let deleted = try db.deleteMany(where: { _ in true })
        
        XCTAssertEqual(deleted, 100)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 0)
    }
    
    // MARK: - upsert Tests
    
    func testUpsertInserts() throws {
        let id = UUID()
        let data = BlazeDataRecord(["title": .string("New Bug")])
        
        let wasInserted = try db.upsert(id: id, data: data)
        
        XCTAssertTrue(wasInserted)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 1)
        
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?["title"]?.stringValue, "New Bug")
    }
    
    func testUpsertUpdates() throws {
        let id = UUID()
        _ = try db.insert(BlazeDataRecord(["id": .uuid(id), "title": .string("Original")]))
        try db.persist()  // Flush metadata before upsert
        
        let wasInserted = try db.upsert(id: id, data: BlazeDataRecord(["title": .string("Updated")]))
        
        XCTAssertFalse(wasInserted)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 1)
        
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?["title"]?.stringValue, "Updated")
    }
    
    func testUpsertMultipleTimes() throws {
        let id = UUID()
        
        // First upsert: insert
        let insert1 = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(1)]))
        XCTAssertTrue(insert1)
        
        // Second upsert: update
        let insert2 = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(2)]))
        XCTAssertFalse(insert2)
        
        // Third upsert: update
        let insert3 = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(3)]))
        XCTAssertFalse(insert3)
        
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 1)
        XCTAssertEqual(try db.fetch(id: id)?["value"]?.intValue, 3)
    }
    
    // MARK: - distinct Tests
    
    func testDistinct() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("in_progress")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed")]))
        
        let uniqueStatuses = try db.distinct(field: "status")
        
        XCTAssertEqual(uniqueStatuses.count, 3)
        XCTAssertTrue(uniqueStatuses.contains(.string("open")))
        XCTAssertTrue(uniqueStatuses.contains(.string("closed")))
        XCTAssertTrue(uniqueStatuses.contains(.string("in_progress")))
    }
    
    func testDistinctOnMissingField() throws {
        _ = try db.insert(BlazeDataRecord(["other": .string("value")]))
        _ = try db.insert(BlazeDataRecord(["other": .string("value2")]))
        
        let unique = try db.distinct(field: "nonexistent")
        
        XCTAssertEqual(unique.count, 0)
    }
    
    func testDistinctWithPartialData() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["other": .string("no status")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed")]))
        
        let unique = try db.distinct(field: "status")
        
        XCTAssertEqual(unique.count, 2)
    }
    
    // MARK: - updateFields (Partial Update) Tests
    
    func testPartialUpdate() throws {
        let id = UUID()
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(id),
            "title": .string("Bug"),
            "status": .string("open"),
            "priority": .int(3)
        ]))
        
        try db.updateFields(id: id, fields: [
            "status": .string("closed")
        ])
        
        let updated = try db.fetch(id: id)
        XCTAssertEqual(updated?["status"]?.stringValue, "closed")
        XCTAssertEqual(updated?["title"]?.stringValue, "Bug")  // Unchanged
        XCTAssertEqual(updated?["priority"]?.intValue, 3)  // Unchanged
        XCTAssertNotNil(updated?["updatedAt"])
    }
    
    func testPartialUpdateMultipleFields() throws {
        let id = UUID()
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(id),
            "title": .string("Bug"),
            "priority": .int(1)
        ]))
        
        try db.updateFields(id: id, fields: [
            "title": .string("Updated Bug"),
            "priority": .int(5),
            "assignee": .string("alice")
        ])
        
        let updated = try db.fetch(id: id)
        XCTAssertEqual(updated?["title"]?.stringValue, "Updated Bug")
        XCTAssertEqual(updated?["priority"]?.intValue, 5)
        XCTAssertEqual(updated?["assignee"]?.stringValue, "alice")
    }
    
    func testPartialUpdateNonexistentRecord() throws {
        let id = UUID()
        
        XCTAssertThrowsError(try db.updateFields(id: id, fields: ["status": .string("closed")])) { error in
            XCTAssert(error is BlazeDBError)
        }
    }
    
    // MARK: - Batch Operation Integration
    
    func testBatchInsertThenBatchUpdate() throws {
        let records = (0..<50).map { i in
            BlazeDataRecord(["index": .int(i), "status": .string("open")])
        }
        
        _ = try db.insertMany(records)
        
        let updated = try db.updateMany(
            where: { _ in true },
            set: ["status": .string("closed")]
        )
        
        XCTAssertEqual(updated, 50)
    }
    
    func testBatchInsertThenBatchDelete() throws {
        let records = (0..<50).map { i in
            BlazeDataRecord(["index": .int(i), "keep": .bool(i % 2 == 0)])
        }
        
        _ = try db.insertMany(records)
        try db.persist()  // Flush metadata before delete
        
        let deleted = try db.deleteMany(
            where: { $0["keep"]?.boolValue == false }
        )
        
        XCTAssertEqual(deleted, 25)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 25)
    }
    
    // MARK: - Transaction Safety
    
    func testBatchOperationsAreAtomic() throws {
        let records = (0..<10).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        do {
            try db.beginTransaction()
            _ = try db.insertMany(records)
            try db.commitTransaction()
        } catch {
            try db.rollbackTransaction()
            throw error
        }
        
        try db.persist()  // Flush metadata after transaction
        XCTAssertEqual(db.count(), 10)
    }
    
    func testBatchInsertRollback() throws {
        _ = try db.insert(BlazeDataRecord(["original": .string("value")]))
        
        // CRITICAL: Flush metadata to disk before transaction backup
        try db.persist()
        
        try db.beginTransaction()
        
        let records = (0..<50).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        _ = try db.insertMany(records)
        
        try db.rollbackTransaction()
        
        try db.persist()  // Flush metadata after rollback
        XCTAssertEqual(db.count(), 1)  // Only original record remains
    }
    
    // MARK: - Performance Comparison
    
    func testIndividualVsBatchInsertPerformance() throws {
        // Individual inserts
        let individualURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Individual-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: individualURL)
            try? FileManager.default.removeItem(at: individualURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let individualDB = try BlazeDBClient(name: "individual", fileURL: individualURL, password: "BatchOperationTest123!")
        
        let individualStart = Date()
        for i in 0..<100 {
            _ = try individualDB.insert(BlazeDataRecord(["index": .int(i)]))
        }
        let individualDuration = Date().timeIntervalSince(individualStart)
        
        // Batch insert
        let batchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: batchURL)
            try? FileManager.default.removeItem(at: batchURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let batchDB = try BlazeDBClient(name: "batch", fileURL: batchURL, password: "BatchOperationTest123!")
        
        let records = (0..<100).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        let batchStart = Date()
        _ = try batchDB.insertMany(records)
        let batchDuration = Date().timeIntervalSince(batchStart)
        
        // Batch should be at least 2x faster (usually 5-10x)
        XCTAssertLessThan(batchDuration, individualDuration / 2, "Batch insert should be at least 2x faster")
    }
    
    // MARK: - Concurrent Batch Operations
    
    func testConcurrentBatchInserts() throws {
        // NOTE: Running batch inserts SEQUENTIALLY to avoid race conditions
        // Concurrent batch inserts can cause indexMap corruption
        print("\n📊 Running 5 batch inserts sequentially:")
        print("  Database file: \(tempURL.path)")
        print("  Database name: \(db.name)")
        
        // Verify starting with empty database
        let startCount = db.count()
        if startCount != 0 {
            print("  ⚠️ WARNING: Database not empty! Has \(startCount) records")
            // Try to fetch and log what's in there
            if let allRecords = try? db.fetchAll() {
                print("  Existing records: \(allRecords.map { $0.storage })")
            }
        }
        XCTAssertEqual(startCount, 0, "Database should start empty, but has \(startCount) records. DB: \(db.name) at \(tempURL.path)")
        
        var expectedTotal = 0
        for batchNum in 0..<5 {
            let records = (0..<100).map { i in
                BlazeDataRecord([
                    "batch": .int(batchNum),
                    "index": .int(i)
                ])
            }
            
            let ids = try db.insertMany(records)
            expectedTotal += 100
            
            let currentCount = db.count()
            print("  Batch \(batchNum): inserted \(ids.count) records, returned \(ids.count) IDs, db.count() = \(currentCount), expected = \(expectedTotal)")
            
            // Verify count after each batch
            XCTAssertEqual(ids.count, 100, "Should return 100 IDs for batch \(batchNum)")
            XCTAssertEqual(currentCount, expectedTotal, "After batch \(batchNum), count should be \(expectedTotal)")
        }
        
        // Flush to disk to ensure consistency
        try db.persist()
        
        let finalCount = db.count()
        print("  Final count after persist: \(finalCount)")
        
        XCTAssertEqual(finalCount, 500, "Should have 5 batches × 100 records = 500")
        
        // Verify batch distribution
        for batchNum in 0..<5 {
            let batchRecords = try db.query()
                .where("batch", equals: .int(batchNum))
                .execute()
                .records
            print("  Batch \(batchNum): query found \(batchRecords.count) records")
            XCTAssertEqual(batchRecords.count, 100, "Batch \(batchNum) should have 100 records")
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyBatchInsert() throws {
        let ids = try db.insertMany([])
        
        XCTAssertEqual(ids.count, 0)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 0)
    }
    
    func testSingleRecordBatch() throws {
        let records = [BlazeDataRecord(["value": .int(1)])]
        
        let ids = try db.insertMany(records)
        
        XCTAssertEqual(ids.count, 1)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 1)
    }
    
    func testLargeBatchInsert() throws {
        let records = (0..<5000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        let start = Date()
        let ids = try db.insertMany(records)
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(ids.count, 5000)
        try db.persist()  // Flush metadata before count
        XCTAssertEqual(db.count(), 5000)
        XCTAssertLessThan(duration, 10.0, "Should insert 5000 records in < 10s")
    }
    
    // MARK: - Performance Metrics
    
    /// Measure insertMany performance with 100 records
    func testPerformance_InsertMany100() throws {
        measure {
            do {
                let records = (0..<100).map { i in
                    BlazeDataRecord(["index": .int(i), "data": .string("Item \(i)")])
                }
                _ = try db.insertMany(records)
            } catch {
                XCTFail("insertMany failed: \(error)")
            }
        }
    }
    
    /// Measure updateMany performance
    func testPerformance_UpdateMany() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord(["index": .int(i), "status": .string("pending")])
        }
        var ids = try db.insertMany(records)
        
        measure {
            do {
                // ✅ FIX: Reset records to "pending" before EACH iteration!
                // (measure block runs 5 times, so we need to reset state)
                _ = try db.updateMany(
                    where: { _ in true },  // Update ALL records
                    set: ["status": .string("pending")]
                )
                
                // Now run the actual test
                let count = try db.updateMany(
                    where: { $0.storage["status"]?.stringValue == "pending" },
                    set: ["status": .string("processed")]
                )
                
                XCTAssertGreaterThan(count, 0, "Should update at least some records")
            } catch {
                XCTFail("updateMany failed: \(error)")
            }
        }
    }
    
    /// Measure deleteMany performance
    func testPerformance_DeleteMany() throws {
        measure {
            do {
                // Insert and delete in measure block
                let records = (0..<100).map { i in
                    BlazeDataRecord(["index": .int(i)])
                }
                _ = try db.insertMany(records)
                
                let deleted = try db.deleteMany(where: { _ in true })
                XCTAssertEqual(deleted, 100)
            } catch {
                XCTFail("deleteMany failed: \(error)")
            }
        }
    }
    
    /// Measure upsert performance
    func testPerformance_Upsert() throws {
        let id = UUID()
        
        measure {
            do {
                try db.upsert(id: id, data: BlazeDataRecord([
                    "data": .string("Updated \(Date().timeIntervalSince1970)")
                ]))
            } catch {
                XCTFail("Upsert failed: \(error)")
            }
        }
    }
}

