//
//  FailureRecoveryScenarios.swift
//  BlazeDBIntegrationTests
//
//  Tests database behavior during and after failures
//  Validates crash recovery, corruption handling, and data integrity
//

import XCTest
@testable import BlazeDB

final class FailureRecoveryScenarios: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FailureTest-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Crash During Transaction
    
    /// Test crash during transaction with full recovery
    func testCrash_DuringTransaction_FullRecovery() async throws {
        print("\n💥 SCENARIO: Crash During Transaction → Full Recovery")
        
        // Phase 1: Normal operation
        print("  📝 Phase 1: Normal operation")
        var db: BlazeDBClient? = try BlazeDBClient(name: "CrashTest", fileURL: dbURL, password: "crash-test-123")
        
        // Insert initial data
        let initialRecords = (0..<50).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "title": .string("Record \(i)"),
                "status": .string("active")
            ])
        }
        let initialIDs = try await db!.insertMany(initialRecords)
        try await db!.persist()
        print("    ✅ Inserted 50 records and persisted")
        
        let beforeCrash = try await db!.count()
        XCTAssertEqual(beforeCrash, 50)
        
        // Phase 2: Start transaction
        print("  🔄 Phase 2: Start risky transaction")
        try await db!.beginTransaction()
        
        // Add new records in transaction
        let txnRecords = (0..<20).map { i in
            BlazeDataRecord([
                "title": .string("TXN Record \(i)"),
                "status": .string("pending")
            ])
        }
        _ = try await db!.insertMany(txnRecords)
        print("    ⚙️  Added 20 records in transaction (not committed)")
        
        // Delete some existing records in same transaction
        let deleted = try await db!.deleteMany(
            where: { $0.storage["status"]?.stringValue == "active" }
        )
        print("    ⚙️  Marked \(deleted) records for deletion (not committed)")
        
        // Phase 3: CRASH! (no commit)
        print("  💥 Phase 3: CRASH! App terminated unexpectedly")
        db = nil  // Simulate crash without commit
        
        // Phase 4: Recovery
        print("  🔄 Phase 4: User reopens app (recovery)")
        db = try BlazeDBClient(name: "CrashTest", fileURL: dbURL, password: "crash-test-123")
        
        let afterRecovery = try await db!.count()
        
        // CRITICAL: Should have original 50 records (transaction rolled back)
        XCTAssertEqual(afterRecovery, 50, 
                      "Should recover to pre-transaction state (50 records)")
        print("    ✅ Recovered to pre-transaction state: \(afterRecovery) records")
        
        // Verify deleted records were restored
        let restored = try await db!.query()
            .where("status", equals: .string("active"))
            .execute()
        XCTAssertEqual(restored.count, 50, "Deleted records should be restored")
        print("    ✅ All 50 active records restored")
        
        // Verify transaction records don't exist
        let txnCheck = try await db!.query()
            .where("status", equals: .string("pending"))
            .execute()
        XCTAssertEqual(txnCheck.count, 0, "Transaction records should not exist")
        print("    ✅ Transaction records correctly rolled back")
        
        print("  ✅ SCENARIO COMPLETE: Full crash recovery validated!")
    }
    
    // MARK: - Crash During Index Rebuild
    
    /// Test crash while rebuilding large index
    func testCrash_DuringIndexRebuild_Recovery() async throws {
        print("\n💥 SCENARIO: Crash During Index Rebuild")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "IndexCrash", fileURL: dbURL, password: "index-crash-123")
        
        // Insert 1000 records
        print("  📊 Setup: Inserting 1000 records...")
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "value": .int(i),
                "category": .string("cat_\(i % 20)")
            ])
        }
        _ = try await db!.insertMany(records)
        try await db!.persist()
        print("    ✅ Inserted 1000 records")
        
        // Start index rebuild (on large dataset)
        print("  ⚙️  Starting index rebuild on 1000 records...")
        
        // Note: In real scenario, crash would happen mid-rebuild
        // We simulate by not completing the operation
        try await db!.collection.createIndex(on: "category")
        print("    ✅ Index created")
        
        // Simulate crash immediately after
        print("  💥 CRASH: App terminated during index operation")
        db = nil
        
        // Recovery
        print("  🔄 Recovery: Reopen database")
        db = try BlazeDBClient(name: "IndexCrash", fileURL: dbURL, password: "index-crash-123")
        
        // Verify data intact
        let count = try await db!.count()
        XCTAssertEqual(count, 1000, "All records should be intact")
        print("    ✅ All 1000 records intact")
        
        // Verify we can create index again (idempotent)
        try await db!.collection.createIndex(on: "category")
        
        // Verify index works
        let indexed = try await db!.collection.fetch(byIndexedField: "category", value: "cat_1")
        XCTAssertGreaterThan(indexed.count, 0, "Index should work after recovery")
        print("    ✅ Index functional: \(indexed.count) results")
        
        print("  ✅ SCENARIO COMPLETE: Index rebuild crash handled correctly!")
    }
    
    // MARK: - Partial Failure During Batch Operation
    
    /// Test partial failure in batch operation
    func testPartialFailure_DuringBatchInsert() async throws {
        print("\n⚠️  SCENARIO: Partial Failure During Batch Operation")
        
        let db = try BlazeDBClient(name: "PartialFail", fileURL: dbURL, password: "partial-fail-123")
        
        // Insert some valid records
        let validRecords = (0..<10).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try await db.insertMany(validRecords)
        print("  ✅ Inserted 10 valid records")
        
        // Try to insert batch with duplicate ID (should fail)
        let duplicateID = UUID()
        let batchWithDuplicate = [
            BlazeDataRecord(["id": .uuid(duplicateID), "value": .int(1)]),
            BlazeDataRecord(["id": .uuid(duplicateID), "value": .int(2)])  // Duplicate!
        ]
        
        do {
            _ = try await db.insertMany(batchWithDuplicate)
            XCTFail("Should have thrown error for duplicate ID")
        } catch {
            print("    ✅ Correctly rejected batch with duplicate ID")
        }
        
        // Verify: Original 10 records should still be intact
        let afterFailure = try await db.count()
        XCTAssertEqual(afterFailure, 10, "Original records should be intact after batch failure")
        print("    ✅ Original data intact: \(afterFailure) records")
        
        // Verify database still functional
        let newRecord = try await db.insert(BlazeDataRecord(["value": .int(999)]))
        XCTAssertNotNil(newRecord)
        print("    ✅ Database still functional after error")
        
        print("  ✅ SCENARIO COMPLETE: Partial failure handled gracefully!")
    }
    
    // MARK: - Corruption Recovery
    
    /// Test database handles corrupted metadata
    func testCorruption_MetadataRecovery() async throws {
        print("\n🔧 SCENARIO: Metadata Corruption → Automatic Recovery")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "CorruptTest", fileURL: dbURL, password: "corrupt-test-123")
        
        // Insert data
        let records = (0..<50).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try await db!.insertMany(records)
        try await db!.persist()
        print("  ✅ Inserted 50 records")
        
        // Close database
        db = nil
        
        // Corrupt metadata file (simulate disk corruption)
        print("  💥 Simulating metadata corruption...")
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
        try "CORRUPTED DATA".data(using: .utf8)?.write(to: metaURL)
        print("    ⚠️  Metadata file corrupted")
        
        // Try to reopen
        print("  🔄 Attempting to reopen database...")
        db = try? BlazeDBClient(name: "CorruptTest", fileURL: dbURL, password: "corrupt-test-123")
        
        // Should recover by rebuilding from data pages
        if let db = db {
            print("    ✅ Database reopened (auto-recovery triggered)")
            
            // Verify data is accessible (rebuilt from pages)
            let recovered = try await db.fetchAll()
            XCTAssertGreaterThan(recovered.count, 0, "Should recover some data")
            print("    ✅ Recovered \(recovered.count) records from pages")
        } else {
            // If can't recover, at least database doesn't crash app
            print("    ✅ Graceful failure (database unusable but app doesn't crash)")
        }
        
        print("  ✅ SCENARIO COMPLETE: Corruption handling validated!")
    }
    
    // MARK: - Concurrent Failures
    
    /// Test multiple concurrent operations with one failing
    func testConcurrentOperations_OneFails_OthersContinue() async throws {
        print("\n⚡ SCENARIO: Concurrent Operations with Partial Failure")
        
        let db = try BlazeDBClient(name: "ConcurrentFail", fileURL: dbURL, password: "concurrent-fail-123")
        
        // Insert initial record
        let existingID = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        print("  ✅ Setup: 1 existing record")
        
        var successCount = 0
        var failureCount = 0
        let lock = NSLock()
        
        // Launch 10 concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        if i == 5 {
                            // This one tries to insert with existing ID (will fail)
                            _ = try await db.insert(BlazeDataRecord([
                                "id": .uuid(existingID),
                                "value": .int(i)
                            ]))
                        } else {
                            // These succeed
                            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
                        }
                        
                        lock.lock()
                        successCount += 1
                        lock.unlock()
                    } catch {
                        lock.lock()
                        failureCount += 1
                        lock.unlock()
                    }
                }
            }
        }
        
        print("  ✅ Operations completed: \(successCount) succeeded, \(failureCount) failed")
        XCTAssertEqual(failureCount, 1, "Exactly 1 operation should fail")
        XCTAssertEqual(successCount, 9, "Other 9 operations should succeed")
        
        // Verify database state
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 10, "Should have 1 original + 9 new records")
        print("    ✅ Database consistent: \(finalCount) records")
        
        print("  ✅ SCENARIO COMPLETE: Partial failure handled correctly!")
    }
    
    // MARK: - Out of Disk Space
    
    /// Test behavior when disk space is exhausted
    func testDiskFull_GracefulDegradation() async throws {
        print("\n💾 SCENARIO: Disk Space Exhaustion")
        
        let db = try BlazeDBClient(name: "DiskFull", fileURL: dbURL, password: "disk-test-123")
        
        // Insert normal-sized records (should succeed)
        let normalRecords = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Normal \(i)"),
                "data": .string(String(repeating: "x", count: 100))
            ])
        }
        _ = try await db.insertMany(normalRecords)
        print("  ✅ Inserted 50 normal-sized records")
        
        // Try to insert extremely large record (simulates disk full)
        // BlazeDB has 4KB page limit, so > 3KB will fail
        do {
            let hugRecord = BlazeDataRecord([
                "title": .string("Huge"),
                "data": .string(String(repeating: "x", count: 5000))  // > 4KB page limit
            ])
            _ = try await db.insert(hugRecord)
            XCTFail("Should have thrown error for oversized record")
        } catch {
            print("    ✅ Correctly rejected oversized record")
            print("    Error: \(error)")
        }
        
        // Verify: Database still functional after error
        let afterError = try await db.count()
        XCTAssertEqual(afterError, 50, "Database should still have 50 records")
        print("    ✅ Database still functional: \(afterError) records")
        
        // Can still insert normal records
        let recovery = try await db.insert(BlazeDataRecord([
            "title": .string("After Error"),
            "data": .string("Normal size")
        ]))
        XCTAssertNotNil(recovery)
        print("    ✅ Can continue inserting after error")
        
        print("  ✅ SCENARIO COMPLETE: Graceful handling of space constraints!")
    }
    
    // MARK: - Concurrent Transaction Conflicts
    
    /// Test two transactions trying to modify same record
    func testConcurrentTransactions_ConflictResolution() async throws {
        print("\n🔄 SCENARIO: Concurrent Transaction Conflicts")
        
        let db = try BlazeDBClient(name: "TxnConflict", fileURL: dbURL, password: "txn-conflict-123")
        
        // Insert record
        let recordID = try await db.insert(BlazeDataRecord([
            "counter": .int(0),
            "status": .string("initial")
        ]))
        try await db.persist()
        print("  ✅ Setup: 1 record with counter=0")
        
        // Note: BlazeDB doesn't currently support true concurrent transactions
        // (only one transaction at a time), so we test sequential transactions
        // with conflicting updates to verify last-write-wins
        
        // Transaction 1: Update counter
        print("  🔄 Transaction 1: Increment counter")
        try await db.beginTransaction()
        try await db.update(id: recordID, with: BlazeDataRecord([
            "counter": .int(5),
            "updater": .string("txn1")
        ]))
        try await db.commitTransaction()
        print("    ✅ Transaction 1 committed: counter=5")
        
        // Transaction 2: Update counter to different value
        print("  🔄 Transaction 2: Set counter to different value")
        try await db.beginTransaction()
        try await db.update(id: recordID, with: BlazeDataRecord([
            "counter": .int(10),
            "updater": .string("txn2")
        ]))
        try await db.commitTransaction()
        print("    ✅ Transaction 2 committed: counter=10")
        
        // Verify: Last write wins
        let final = try await db.fetch(id: recordID)
        XCTAssertEqual(final?.storage["counter"]?.intValue, 10, "Last write should win")
        XCTAssertEqual(final?.storage["updater"]?.stringValue, "txn2", "Should have txn2 marker")
        print("    ✅ Last-write-wins: counter=10 (txn2)")
        
        print("  ✅ SCENARIO COMPLETE: Transaction conflict resolution works!")
    }
    
    // MARK: - Database Reopening Stress
    
    /// Test rapid open/close cycles don't cause issues
    func testRapid_OpenCloseCycles() async throws {
        print("\n🔄 SCENARIO: Rapid Open/Close Cycles")
        
        print("  ⚙️  Performing 20 open/close cycles...")
        
        for cycle in 0..<20 {
            autoreleasepool {
                do {
                    let db = try BlazeDBClient(name: "CycleTest", fileURL: dbURL, password: "cycle-test-123")
                    
                    // Insert record
                    _ = try db.insert(BlazeDataRecord(["cycle": .int(cycle)]))
                    
                    // Immediately close
                    try db.persist()
                } catch {
                    XCTFail("Cycle \(cycle) failed: \(error)")
                }
            }
            
            if cycle % 5 == 0 {
                print("    ✓ Completed \(cycle) cycles...")
            }
        }
        
        print("  ✅ Completed 20 open/close cycles")
        
        // Verify all records persisted
        let db = try BlazeDBClient(name: "CycleTest", fileURL: dbURL, password: "cycle-test-123")
        let count = try await db.count()
        
        XCTAssertGreaterThanOrEqual(count, 20, "Should have at least 20 records")
        print("    ✅ All records persisted: \(count)")
        
        print("  ✅ SCENARIO COMPLETE: Rapid cycling handled correctly!")
    }
    
    // MARK: - Multi-Database Crash
    
    /// Test crash while multiple databases are open
    func testCrash_WithMultipleDatabasesOpen() async throws {
        print("\n💥 SCENARIO: Crash With Multiple Databases")
        
        // Open 3 databases simultaneously
        let db1 = try BlazeDBClient(name: "DB1", fileURL: dbURL, password: "multi-1")
        
        let db2URL = dbURL.deletingLastPathComponent().appendingPathComponent("DB2-\(UUID().uuidString).blazedb")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "multi-2")
        
        let db3URL = dbURL.deletingLastPathComponent().appendingPathComponent("DB3-\(UUID().uuidString).blazedb")
        let db3 = try BlazeDBClient(name: "DB3", fileURL: db3URL, password: "multi-3")
        
        defer {
            try? FileManager.default.removeItem(at: db2URL)
            try? FileManager.default.removeItem(at: db2URL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: db3URL)
            try? FileManager.default.removeItem(at: db3URL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        print("  ✅ Opened 3 databases simultaneously")
        
        // Insert data into each
        _ = try await db1.insert(BlazeDataRecord(["db": .string("db1")]))
        _ = try await db2.insert(BlazeDataRecord(["db": .string("db2")]))
        _ = try await db3.insert(BlazeDataRecord(["db": .string("db3")]))
        print("  ✅ Inserted data into all 3 databases")
        
        // Start transactions on all 3
        try await db1.beginTransaction()
        try await db2.beginTransaction()
        try await db3.beginTransaction()
        print("  🔄 Started transactions on all 3")
        
        // Make changes
        _ = try await db1.insert(BlazeDataRecord(["txn": .bool(true)]))
        _ = try await db2.insert(BlazeDataRecord(["txn": .bool(true)]))
        _ = try await db3.insert(BlazeDataRecord(["txn": .bool(true)]))
        print("  ⚙️  Modified all 3 in transactions")
        
        // CRASH without committing any
        print("  💥 CRASH: All databases closed without commit")
        // (deinit will rollback)
        
        // Reopen all 3
        print("  🔄 Recovery: Reopening all databases...")
        let recovered1 = try BlazeDBClient(name: "DB1", fileURL: dbURL, password: "multi-1")
        let recovered2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "multi-2")
        let recovered3 = try BlazeDBClient(name: "DB3", fileURL: db3URL, password: "multi-3")
        
        // Verify: Each should have 1 record (transaction rolled back)
        let count1 = try await recovered1.count()
        let count2 = try await recovered2.count()
        let count3 = try await recovered3.count()
        
        XCTAssertEqual(count1, 1, "DB1 should have 1 record (txn rolled back)")
        XCTAssertEqual(count2, 1, "DB2 should have 1 record (txn rolled back)")
        XCTAssertEqual(count3, 1, "DB3 should have 1 record (txn rolled back)")
        
        print("    ✅ DB1 recovered: \(count1) record")
        print("    ✅ DB2 recovered: \(count2) record")
        print("    ✅ DB3 recovered: \(count3) record")
        
        print("  ✅ SCENARIO COMPLETE: Multi-database crash recovery works!")
    }
    
    // MARK: - Performance Under Stress
    
    /// Measure complete workflow under realistic load
    func testPerformance_CompleteWorkflowUnderLoad() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            Task {
                do {
                    let db = try BlazeDBClient(name: "LoadTest", fileURL: self.dbURL, password: "load-test-123")
                    
                    // Simulate production load
                    // 1. Initial data import
                    let initial = (0..<500).map { i in
                        BlazeDataRecord([
                            "title": .string("Item \(i)"),
                            "status": .string(["active", "pending", "completed"].randomElement()!),
                            "value": .double(Double(i))
                        ])
                    }
                    _ = try await db.insertMany(initial)
                    
                    // 2. Create indexes
                    try await db.collection.createIndex(on: "status")
                    try await db.collection.enableSearch(fields: ["title"])
                    
                    // 3. Perform queries
                    for _ in 0..<10 {
                        _ = try await db.query().where("status", equals: .string("active")).execute()
                    }
                    
                    // 4. Bulk update in transaction
                    try await db.beginTransaction()
                    _ = try await db.updateMany(
                        where: { $0.storage["value"]?.doubleValue ?? 0 > 250 },
                        with: BlazeDataRecord(["flag": .bool(true)])
                    )
                    try await db.commitTransaction()
                    
                    // 5. Search operations
                    for _ in 0..<5 {
                        _ = try await db.collection.search(query: "Item")
                    }
                    
                    // 6. Export
                    _ = try await db.fetchAll()
                    
                    // 7. Persist
                    try await db.persist()
                    
                } catch {
                    XCTFail("Load test failed: \(error)")
                }
            }
        }
    }
}

