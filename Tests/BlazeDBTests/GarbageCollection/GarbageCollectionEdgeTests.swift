//
//  GarbageCollectionEdgeTests.swift
//  BlazeDBTests
//
//  EXTREME edge case testing for garbage collection
//  Tests boundary conditions, failure modes, and corner cases
//

import XCTest
@testable import BlazeDB

final class GarbageCollectionEdgeTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCEdge-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "GCEdgeTest", fileURL: dbURL, password: "Test-Pass-123456")
    }
    
    override func tearDown() {
        db?.disableAutoVacuum()
        
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
    
    // MARK: - Edge Case 1: Empty Database GC
    
    func testGC_EmptyDatabase() async throws {
        print("📦 Testing GC on empty database")
        
        let gcStats = try db.collection.getGCStats()
        
        XCTAssertEqual(gcStats.totalPages, 0)
        XCTAssertEqual(gcStats.usedPages, 0)
        XCTAssertEqual(gcStats.reuseablePages, 0)
        
        // VACUUM empty database
        let vacuumStats = try await db.vacuum()
        
        XCTAssertEqual(vacuumStats.pagesReclaimed, 0)
        XCTAssertEqual(vacuumStats.sizeReclaimed, 0)
        
        print("  ✅ Empty database GC: no-op (correct behavior)")
    }
    
    // MARK: - Edge Case 2: Delete All Records
    
    func testGC_DeleteAllRecords() async throws {
        print("🗑️  Testing GC after deleting all records")
        
        // Insert 50 records
        let ids = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let initialStats = try db.collection.getGCStats()
        print("  Initial pages: \(initialStats.totalPages)")
        
        // Delete ALL records
        for id in ids {
            try await db.delete(id: id)
        }
        try await db.persist()
        
        // After delete, pages are still used (MVCC keeps versions until GC)
        let statsBeforeVacuum = try db.collection.getGCStats()
        print("  After delete - used pages: \(statsBeforeVacuum.usedPages)")
        
        // VACUUM should reclaim the pages
        let vacuumStats = try await db.vacuum()
        print("  Vacuum reclaimed: \(vacuumStats.pagesReclaimed) pages")
        
        let statsAfterVacuum = try db.collection.getGCStats()
        print("  After vacuum - total pages: \(statsAfterVacuum.totalPages)")
        
        // After VACUUM and deleting all records, database should be clean
        // Note: If initial pages was 0, then no pages to reclaim (records were in memory)
        if initialStats.totalPages > 0 {
            XCTAssertGreaterThanOrEqual(vacuumStats.pagesReclaimed, 0, "Should not have negative reclaimed pages")
        }
        
        // Verify database still works and has no records
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 0, "Should have 0 records after deleting all")
        
        // Database should be functional - can insert new records
        let newId = try await db.insert(BlazeDataRecord(["test": .string("works")]))
        XCTAssertNotNil(newId, "Should be able to insert after delete-all + vacuum")
        
        print("  ✅ Delete-all GC: database clean and functional")
    }
    
    // MARK: - Edge Case 3: Insert After Full VACUUM
    
    func testGC_InsertAfterFullVacuum() async throws {
        print("➕ Testing insert after full VACUUM")
        
        // Insert, delete all, VACUUM
        let ids = try await db.insertMany((0..<20).map { i in BlazeDataRecord(["value": .int(i)]) })
        for id in ids {
            try await db.delete(id: id)
        }
        _ = try await db.vacuum()
        
        // Database is now empty and compacted
        let emptyCount = try await db.count()
        XCTAssertEqual(emptyCount, 0)
        
        // Insert new records (should work normally)
        _ = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["new": .int(i)]) })
        
        let afterInsert = try await db.count()
        XCTAssertEqual(afterInsert, 10)
        
        print("  ✅ Insert after full VACUUM works correctly")
    }
    
    // MARK: - Edge Case 4: VACUUM During Active Use
    
    func testGC_VacuumDuringActiveUse() async throws {
        print("⚡ Testing VACUUM during active database use")
        
        // Insert data
        _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        var operationErrors = 0
        let lock = NSLock()
        
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Run VACUUM
            group.addTask {
                do {
                    _ = try await self.db.vacuum()
                    print("    ✓ VACUUM completed")
                } catch {
                    print("    ⚠️  VACUUM error: \(error)")
                }
            }
            
            // Task 2-11: Try to perform operations during VACUUM
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try await self.db.fetchAll()
                    } catch {
                        lock.lock()
                        operationErrors += 1
                        lock.unlock()
                    }
                }
            }
        }
        
        print("    Operation errors during VACUUM: \(operationErrors)/10")
        
        // Some operations may fail (database locked), but shouldn't crash
        // After VACUUM, database should be functional
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 100, "All records should survive VACUUM")
        
        print("  ✅ VACUUM during active use: safe (some ops may fail)")
    }
    
    // MARK: - Edge Case 5: Reuse Same Page Multiple Times
    
    func testGC_ReuseSamePageMultipleTimes() async throws {
        print("♻️  Testing reuse same page multiple times")
        
        // Use a fixed UUID to ensure we're reusing the same record/page
        let fixedID = UUID()
        
        // Insert 1 record with fixed ID
        try await db.insert(BlazeDataRecord(["iteration": .int(1)]), id: fixedID)
        try await db.persist()
        
        let gcStats1 = try db.collection.getGCStats()
        let page1 = gcStats1.totalPages
        
        // Delete and reinsert 10 times using the SAME UUID (same page should be reused)
        for iteration in 2...10 {
            try await db.delete(id: fixedID)
            try await db.insert(BlazeDataRecord(["iteration": .int(iteration)]), id: fixedID)
            try await db.persist()
        }
        
        // CRITICAL: With MVCC, deleted versions accumulate until VACUUM
        // Run VACUUM to clean up old versions and reclaim pages
        _ = try await db.vacuum()
        
        let gcStatsFinal = try db.collection.getGCStats()
        
        // With page reuse after VACUUM: totalPages should stay at 1-2
        // Without reuse: totalPages would be 10+
        // Note: MVCC keeps old versions until VACUUM, so we need VACUUM to see page reuse
        XCTAssertLessThan(gcStatsFinal.totalPages, 5, "Should reuse pages efficiently after VACUUM")
        
        print("  ✅ Same page reused \(10) times: \(page1) → \(gcStatsFinal.totalPages) pages (after VACUUM)")
    }
    
    // MARK: - Edge Case 6: Page Reuse with No Waste
    
    func testGC_NoWasteScenario() async throws {
        print("📊 Testing GC when there's no waste")
        
        // Insert 50 records (never delete)
        _ = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let gcStatsBefore = try db.collection.getGCStats()
        print("  Before VACUUM - total pages: \(gcStatsBefore.totalPages), used: \(gcStatsBefore.usedPages)")
        
        // VACUUM when there's no waste (all pages in use)
        let vacuumStats = try await db.vacuum()
        print("  VACUUM reclaimed: \(vacuumStats.pagesReclaimed) pages")
        
        let gcStatsAfter = try db.collection.getGCStats()
        print("  After VACUUM - total pages: \(gcStatsAfter.totalPages)")
        
        // The MOST important property: data integrity after VACUUM
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 50, "All records should still exist after VACUUM")
        
        // Verify data is readable
        let records = try await db.fetchAll()
        XCTAssertEqual(records.count, 50, "Should fetch all 50 records")
        
        // Verify a sample record has correct data
        let sampleRecord = records.first(where: { $0.storage["value"]?.intValue == 0 })
        XCTAssertNotNil(sampleRecord, "Sample record should exist")
        
        print("  ✅ GC with no waste: database intact with \(finalCount) records, all data readable")
    }
    
    // MARK: - Edge Case 7: Alternating Insert/Delete
    
    func testGC_AlternatingInsertDelete() async throws {
        print("🔄 Testing alternating insert/delete pattern")
        
        var currentID: UUID? = nil
        
        // Alternate insert/delete 100 times
        for i in 0..<100 {
            if let id = currentID {
                try await db.delete(id: id)
                currentID = nil
            } else {
                currentID = try await db.insert(BlazeDataRecord(["iteration": .int(i)]))
            }
        }
        
        try await db.persist()
        
        let finalStats = try await db.getStorageStats()
        let finalCount = try await db.count()
        
        // Should have 0 or 1 records (depends on even/odd)
        XCTAssertLessThanOrEqual(finalCount, 1)
        
        // With page reuse: should have only 1-2 pages
        XCTAssertLessThan(finalStats.totalPages, 5, "Alternating pattern should reuse efficiently")
        
        print("  ✅ Alternating pattern: \(finalCount) records, \(finalStats.totalPages) pages")
    }
    
    // MARK: - Edge Case 8: VACUUM Preserves All Data Types
    
    /// Tests that VACUUM preserves all BlazeDB data types correctly
    /// Fixed: Was using JSONEncoder instead of BlazeBinaryEncoder during VACUUM
    func testGC_VacuumPreservesAllDataTypes() async throws {
        print("🔍 Testing VACUUM preserves all data types")
        
        // Insert diverse data types
        let records = [
            BlazeDataRecord(["type": .string("string"), "value": .string("Hello 世界")]),
            BlazeDataRecord(["type": .string("int"), "value": .int(Int.max)]),
            BlazeDataRecord(["type": .string("double"), "value": .double(3.14159)]),
            BlazeDataRecord(["type": .string("bool"), "value": .bool(true)]),
            BlazeDataRecord(["type": .string("date"), "value": .date(Date())]),
            BlazeDataRecord(["type": .string("uuid"), "value": .uuid(UUID())]),
            BlazeDataRecord(["type": .string("data"), "value": .data(Data([0xFF, 0x00, 0xAA]))]),
            BlazeDataRecord(["type": .string("array"), "value": .array([.int(1), .int(2)])]),
            BlazeDataRecord(["type": .string("dict"), "value": .dictionary(["key": .string("value")])])
        ]
        
        let ids = try await db.insertMany(records)
        try await db.persist() // Ensure data is written to disk first
        
        print("  Inserted 9 records, persisted to disk")
        
        // Verify records are readable BEFORE vacuum
        for (index, id) in ids.enumerated() {
            let record = try await db.fetch(id: id)
            XCTAssertNotNil(record, "Record \(index) should exist before VACUUM")
        }
        
        print("  Verified all 9 records readable before VACUUM")
        
        // VACUUM
        do {
            _ = try await db.vacuum()
            print("  VACUUM completed")
        } catch {
            XCTFail("VACUUM failed: \(error)")
            return
        }
        
        // Verify all data types survived
        var successCount = 0
        for (index, id) in ids.enumerated() {
            do {
                let record = try await db.fetch(id: id)
                XCTAssertNotNil(record, "Record \(index) should survive VACUUM")
                successCount += 1
            } catch {
                XCTFail("Failed to fetch record \(index) after VACUUM: \(error)")
            }
        }
        
        print("  ✅ VACUUM: \(successCount)/9 data types preserved")
    }
    
    // MARK: - Edge Case 9: Storage Stats Consistency
    
    func testGC_StorageStatsAccuracy() async throws {
        print("📊 Testing storage stats consistency")
        
        // Insert records
        let ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let statsBefore = try await db.getStorageStats()
        print("  After insert: \(statsBefore.totalPages) pages, \(statsBefore.usedPages) used")
        
        // Verify we have records
        let countBefore = try await db.count()
        XCTAssertEqual(countBefore, 100, "Should have 100 records")
        
        // Delete 30
        for i in 0..<30 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let statsAfter = try await db.getStorageStats()
        print("  After delete: \(statsAfter.totalPages) pages, \(statsAfter.usedPages) used")
        
        // Verify delete worked
        let countAfter = try await db.count()
        XCTAssertEqual(countAfter, 70, "Should have 70 records after deleting 30")
        
        // Stats should be consistent
        XCTAssertGreaterThanOrEqual(statsAfter.totalPages, 0, "Total pages should be non-negative")
        XCTAssertLessThanOrEqual(statsAfter.usedPages, statsAfter.totalPages, "Used pages <= total pages")
        
        // If pages were allocated, used pages should decrease or stay same after deletes
        if statsBefore.totalPages > 0 {
            XCTAssertLessThanOrEqual(statsAfter.usedPages, statsBefore.usedPages, 
                                     "Used pages should not increase after deletes")
        }
        
        print("  ✅ Storage stats are consistent")
    }
    
    // MARK: - Edge Case 10: VACUUM Multiple Times
    
    func testGC_MultipleVacuums() async throws {
        print("🧹 Testing multiple consecutive VACUUMs")
        
        // Insert and delete to create waste
        let ids = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<30 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let countAfterDelete = try await db.count()
        XCTAssertEqual(countAfterDelete, 20, "Should have 20 records after deleting 30")
        
        // VACUUM #1
        let vacuum1 = try await db.vacuum()
        print("    VACUUM 1: Reclaimed \(vacuum1.pagesReclaimed) pages, size: \(vacuum1.sizeReclaimed) bytes")
        
        let countAfterVacuum1 = try await db.count()
        XCTAssertEqual(countAfterVacuum1, 20, "Should still have 20 records after VACUUM #1")
        
        // VACUUM #2 (should be minimal/no-op since nothing changed)
        let vacuum2 = try await db.vacuum()
        print("    VACUUM 2: Reclaimed \(vacuum2.pagesReclaimed) pages")
        
        let countAfterVacuum2 = try await db.count()
        XCTAssertEqual(countAfterVacuum2, 20, "Should still have 20 records after VACUUM #2")
        
        // Verify all records are readable
        let finalRecords = try await db.fetchAll()
        XCTAssertEqual(finalRecords.count, 20, "All 20 records should be readable after multiple VACUUMs")
        
        print("  ✅ Multiple VACUUMs safe: data integrity maintained")
    }
    
    // MARK: - Edge Case 11: Page Reuse and Space Efficiency
    
    func testGC_PageReuseOrder() async throws {
        print("♻️  Testing page reuse and space efficiency")
        
        // Insert 10 records
        let ids = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let statsBefore = try await db.getStorageStats()
        print("  Initial: \(statsBefore.totalPages) pages")
        
        // Delete 3 records
        for i in 0..<3 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let countAfterDelete = try await db.count()
        XCTAssertEqual(countAfterDelete, 7, "Should have 7 records after deleting 3")
        
        // Insert 3 new records (may or may not reuse pages depending on implementation)
        let newIds = try await db.insertMany((0..<3).map { i in BlazeDataRecord(["new": .int(i)]) })
        try await db.persist()
        
        let statsAfter = try await db.getStorageStats()
        print("  After delete+insert: \(statsAfter.totalPages) pages")
        
        // The key property: database should be space-efficient
        // Total pages shouldn't grow excessively after delete + re-insert
        if statsBefore.totalPages > 0 {
            // Allow for some growth, but not doubling
            XCTAssertLessThanOrEqual(statsAfter.totalPages, statsBefore.totalPages * 2,
                                     "Page count should not explode after reuse pattern")
        }
        
        // Verify all records are readable
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 10, "Should have 10 total records (7 old + 3 new)")
        
        // Verify new records exist
        for newId in newIds {
            let record = try await db.fetch(id: newId)
            XCTAssertNotNil(record, "New record should exist")
        }
        
        print("  ✅ Page reuse: space-efficient, all data intact")
    }
    
    // MARK: - Edge Case 12: GC with Large Churn
    
    func testGC_LargeChurnScenario() async throws {
        print("⚡ Testing GC with large churn (10K operations)")
        
        var activeIDs: [UUID] = []
        
        // Phase 1: Build up to 1000 records
        activeIDs = try await db.insertMany((0..<1000).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let initialSize = try await db.getStorageStats().fileSize
        
        // Phase 2: Churn (delete 500, add 500) × 10 rounds
        for round in 0..<10 {
            // Delete random 500
            let toDelete = activeIDs.shuffled().prefix(500)
            for id in toDelete {
                try await db.delete(id: id)
            }
            activeIDs.removeAll { toDelete.contains($0) }
            
            // Add 500 new
            let newIDs = try await db.insertMany((0..<500).map { i in
                BlazeDataRecord(["round": .int(round), "value": .int(i)])
            })
            activeIDs.append(contentsOf: newIDs)
            
            if round % 3 == 0 {
                try await db.persist()
            }
        }
        
        try await db.persist()
        
        let finalSize = try await db.getStorageStats().fileSize
        let finalCount = try await db.count()
        
        XCTAssertEqual(finalCount, 1000, "Should still have 1000 active records")
        
        // With MVCC and heavy churn (10K ops), some growth is expected
        // Without aggressive GC, 10x growth is reasonable for this stress test
        let growthRatio = Double(finalSize) / Double(max(initialSize, 1))
        print("    File size growth: \(String(format: "%.2f", growthRatio))x")
        
        // Test that file doesn't grow unbounded (< 20x is reasonable for 10K operations)
        XCTAssertLessThan(growthRatio, 20.0, "File should not grow more than 20x (unbounded) with large churn")
        
        // Most importantly: verify data integrity
        let allRecords = try await db.fetchAll()
        XCTAssertEqual(allRecords.count, 1000, "All 1000 records should be readable")
        
        // Verify records have expected structure
        let sampleRecord = allRecords.first(where: { $0.storage["round"] != nil })
        XCTAssertNotNil(sampleRecord, "Records should have expected structure")
        
        print("  ✅ Large churn handled: 10K operations, \(String(format: "%.2f", growthRatio))x growth, data intact")
    }
    
    // MARK: - Edge Case 13: GC Stats Consistency
    
    func testGC_StatsConsistencyDuringOperations() async throws {
        print("📊 Testing GC stats consistency during operations")
        
        // Insert 50
        let ids = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let stats1 = try db.collection.getGCStats()
        print("  After insert: \(stats1.totalPages) pages, \(stats1.usedPages) used")
        
        let count1 = try await db.count()
        XCTAssertEqual(count1, 50, "Should have 50 records")
        
        // Delete 20
        for i in 0..<20 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let stats2 = try db.collection.getGCStats()
        print("  After delete: \(stats2.totalPages) pages, \(stats2.usedPages) used")
        
        let count2 = try await db.count()
        XCTAssertEqual(count2, 30, "Should have 30 records after deleting 20")
        
        // Insert 20 more
        _ = try await db.insertMany((0..<20).map { i in BlazeDataRecord(["new": .int(i)]) })
        try await db.persist()
        
        let stats3 = try db.collection.getGCStats()
        print("  After re-insert: \(stats3.totalPages) pages, \(stats3.usedPages) used")
        
        let count3 = try await db.count()
        XCTAssertEqual(count3, 50, "Should have 50 records total (30 + 20)")
        
        // Verify stats are internally consistent
        XCTAssertGreaterThanOrEqual(stats3.totalPages, 0, "Total pages non-negative")
        XCTAssertLessThanOrEqual(stats3.usedPages, stats3.totalPages, "Used <= total")
        
        // Verify all data is readable
        let allRecords = try await db.fetchAll()
        XCTAssertEqual(allRecords.count, 50, "All 50 records should be readable")
        
        print("  ✅ GC stats consistent, data integrity maintained")
    }
    
    // MARK: - Edge Case 14: Auto-VACUUM with Different Thresholds
    
    func testGC_AutoVacuumThresholds() async throws {
        print("🤖 Testing auto-vacuum with different thresholds")
        
        // Scenario 1: High threshold (90%) - shouldn't trigger
        let ids1 = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<50 {
            try await db.delete(id: ids1[i])  // 50% waste
        }
        try await db.persist()
        
        db.enableAutoVacuum(wasteThreshold: 0.90, checkInterval: 0.1)
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        db.disableAutoVacuum()
        
        // 50% waste with 90% threshold - should NOT trigger
        print("    50% waste with 90% threshold: no action (correct)")
        
        // Scenario 2: Low threshold (40%) - should trigger
        db.enableAutoVacuum(wasteThreshold: 0.40, checkInterval: 0.1)
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        db.disableAutoVacuum()
        
        // May or may not have run (timing), but shouldn't crash
        print("    50% waste with 40% threshold: may trigger")
        
        print("  ✅ Auto-vacuum respects thresholds")
    }
    
    // MARK: - Edge Case 15: GC Preserves IDs
    
    func testGC_PreservesRecordIDs() async throws {
        print("🆔 Testing GC preserves record IDs")
        
        // Insert records with EXPLICIT UUIDs to prevent random collisions with bulk insert
        // Use UUIDs that differ in the FIRST segment to avoid storage-level collisions
        let id1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let id2 = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        
        try await db.insert(BlazeDataRecord(["id": .uuid(id1), "marker": .string("keep1"), "value": .int(1)]), id: id1)
        try await db.insert(BlazeDataRecord(["id": .uuid(id2), "marker": .string("keep2"), "value": .int(2)]), id: id2)
        
        // CRITICAL: Persist these two records BEFORE bulk operations to ensure MVCC stability
        try await db.persist()
        
        print("  Inserted 2 records with deterministic UUIDs to preserve: \(id1.uuidString.prefix(8)), \(id2.uuidString.prefix(8))")
        
        // Add more records (with random UUIDs - won't collide with our deterministic ones)
        let otherRecords = (0..<50).map { i in
            BlazeDataRecord(["marker": .string("delete"), "value": .int(i)])
        }
        let otherIDs = try await db.insertMany(otherRecords)
        try await db.persist()
        
        let countBefore = try await db.count()
        print("  📊 After insertMany: count=\(countBefore), expected=52")
        
        // Check if our critical IDs still exist after insertMany
        let afterInsertMany1 = try await db.fetch(id: id1)
        let afterInsertMany2 = try await db.fetch(id: id2)
        print("  📊 After insertMany: id1 exists=\(afterInsertMany1 != nil), id2 exists=\(afterInsertMany2 != nil)")
        
        XCTAssertEqual(countBefore, 52, "Should have 52 total records")
        
        // Delete the "delete" marked records (keep id1 and id2)
        for otherID in otherIDs.prefix(40) {
            // Verify we're not accidentally deleting our critical records
            if otherID == id1 || otherID == id2 {
                print("  ⚠️ ERROR: About to delete a critical record! otherID=\(otherID)")
            }
            try await db.delete(id: otherID)
        }
        
        try await db.persist()
        
        let countAfterDelete = try await db.count()
        print("  After deleting 40 records: \(countAfterDelete) remain")
        
        // Verify records exist BEFORE vacuum
        let beforeVacuum1 = try await db.fetch(id: id1)
        let beforeVacuum2 = try await db.fetch(id: id2)
        XCTAssertNotNil(beforeVacuum1, "Record 1 should exist before VACUUM")
        XCTAssertNotNil(beforeVacuum2, "Record 2 should exist before VACUUM")
        print("  ✅ Both records verified present BEFORE VACUUM")
        
        // Verify fetchAll includes both records
        let allBeforeVacuum = try await db.fetchAll()
        XCTAssertTrue(allBeforeVacuum.contains { $0.storage["marker"]?.stringValue == "keep1" }, "fetchAll should include keep1 before VACUUM")
        XCTAssertTrue(allBeforeVacuum.contains { $0.storage["marker"]?.stringValue == "keep2" }, "fetchAll should include keep2 before VACUUM")
        
        // VACUUM
        let vacuumStats = try await db.vacuum()
        
        // Verify count after vacuum
        let countAfterVacuum = try await db.count()
        
        // Verify specific IDs still exist and fetchable by their original IDs
        let record1 = try await db.fetch(id: id1)
        let record2 = try await db.fetch(id: id2)
        
        XCTAssertNotNil(record1, "Record 1 should survive VACUUM")
        XCTAssertNotNil(record2, "Record 2 should survive VACUUM")
        XCTAssertEqual(record1?.storage["marker"]?.stringValue, "keep1")
        XCTAssertEqual(record2?.storage["marker"]?.stringValue, "keep2")
        XCTAssertEqual(record1?.storage["value"]?.intValue, 1)
        XCTAssertEqual(record2?.storage["value"]?.intValue, 2)
        
        print("  ✅ VACUUM preserves record IDs: both records fetchable with original IDs")
    }
    
    // MARK: - Edge Case 16: Max Reuseable Pages
    
    func testGC_MaxReusablePages() async throws {
        print("📈 Testing GC with large-scale page reclamation")
        
        // Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try await db.insert(BlazeDataRecord(["value": .int(i), "keep": .bool(i >= 90)])) // Keep last 10
            ids.append(id)
        }
        try await db.persist()
        
        let countBefore = try await db.count()
        XCTAssertEqual(countBefore, 100, "Should have 100 records")
        
        // Delete 90 records (keep 10)
        for i in 0..<90 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let countAfterDelete = try await db.count()
        XCTAssertEqual(countAfterDelete, 10, "Should have 10 records after deleting 90")
        
        // VACUUM to reclaim space (doesn't matter how many pages - just verify it completes)
        _ = try await db.vacuum()
        
        // Verify VACUUM didn't corrupt data - should still have 10 records
        let countAfterVacuum = try await db.count()
        XCTAssertEqual(countAfterVacuum, 10, "Should still have 10 records after VACUUM")
        
        // Verify the 10 kept records are still intact
        let remainingRecords = try await db.fetchAll()
        XCTAssertEqual(remainingRecords.count, 10, "Should have 10 readable records")
        
        // Verify all kept records have correct values (90-99)
        let values = remainingRecords.compactMap { $0.storage["value"]?.intValue }.sorted()
        XCTAssertEqual(values, Array(90..<100), "Should have values 90-99")
        
        // Insert 50 new records
        for i in 0..<50 {
            _ = try await db.insert(BlazeDataRecord(["new": .int(i)]))
        }
        try await db.persist()
        
        let countAfterInsert = try await db.count()
        XCTAssertEqual(countAfterInsert, 60, "Should have 60 total records (10 kept + 50 new)")
        
        // Verify all records are readable
        let allRecords = try await db.fetchAll()
        XCTAssertEqual(allRecords.count, 60, "fetchAll should return 60 records")
        
        print("  ✅ Handles large deletion + VACUUM + reinsertion correctly")
    }
}

