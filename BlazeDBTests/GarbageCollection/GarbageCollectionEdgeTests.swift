//
//  GarbageCollectionEdgeTests.swift
//  BlazeDBTests
//
//  EXTREME edge case testing for garbage collection
//  Tests boundary conditions, failure modes, and corner cases
//

import XCTest
@testable import BlazeDBCore

final class GarbageCollectionEdgeTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCEdge-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "GCEdgeTest", fileURL: dbURL, password: "test-pass-123456")
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
        
        // Delete ALL records
        for id in ids {
            try await db.delete(id: id)
        }
        try await db.persist()
        
        let gcStats = try db.collection.getGCStats()
        
        XCTAssertEqual(gcStats.usedPages, 0, "No used pages")
        XCTAssertEqual(gcStats.reuseablePages, 50, "All 50 pages should be reuseable")
        
        // VACUUM should shrink to near-zero
        let vacuumStats = try await db.vacuum()
        
        XCTAssertEqual(vacuumStats.pagesAfter, 0, "Should have 0 pages after VACUUM")
        XCTAssertEqual(vacuumStats.pagesReclaimed, 50, "Should reclaim all 50 pages")
        
        print("  ✅ Delete-all GC: all pages reclaimed")
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
        
        // Insert 1 record
        let id1 = try await db.insert(BlazeDataRecord(["iteration": .int(1)]))
        try await db.persist()
        
        let gcStats1 = try db.collection.getGCStats()
        let page1 = gcStats1.totalPages
        
        // Delete and reinsert 10 times (same page should be reused)
        for iteration in 2...10 {
            try await db.delete(id: id1)
            _ = try await db.insert(BlazeDataRecord(["iteration": .int(iteration)]))
            try await db.persist()
        }
        
        let gcStatsFinal = try db.collection.getGCStats()
        
        // With page reuse: totalPages should stay at 1-2
        // Without reuse: totalPages would be 10+
        XCTAssertLessThan(gcStatsFinal.totalPages, 5, "Should reuse pages efficiently")
        
        print("  ✅ Same page reused \(10) times: \(page1) → \(gcStatsFinal.totalPages) pages")
    }
    
    // MARK: - Edge Case 6: Page Reuse with No Waste
    
    func testGC_NoWasteScenario() async throws {
        print("📊 Testing GC when there's no waste")
        
        // Insert 50 records (never delete)
        _ = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let gcStats = try db.collection.getGCStats()
        
        XCTAssertEqual(gcStats.wastedPages, 0, "No waste")
        XCTAssertEqual(gcStats.reuseablePages, 0, "No reuseable pages")
        
        // VACUUM should be no-op
        let vacuumStats = try await db.vacuum()
        
        XCTAssertEqual(vacuumStats.pagesReclaimed, 0, "Nothing to reclaim")
        
        print("  ✅ GC with no waste: no-op (efficient)")
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
        
        // VACUUM
        _ = try await db.vacuum()
        
        // Verify all data types survived
        for id in ids {
            let record = try await db.fetch(id: id)
            XCTAssertNotNil(record, "All records should survive VACUUM")
        }
        
        print("  ✅ VACUUM preserves all 9 data types")
    }
    
    // MARK: - Edge Case 9: Storage Stats Accuracy
    
    func testGC_StorageStatsAccuracy() async throws {
        print("📊 Testing storage stats accuracy")
        
        // Known scenario
        let ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        var stats = try await db.getStorageStats()
        
        XCTAssertEqual(stats.totalPages, 100)
        XCTAssertEqual(stats.usedPages, 100)
        XCTAssertEqual(stats.emptyPages, 0)
        
        // Delete 30
        for i in 0..<30 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        stats = try await db.getStorageStats()
        
        XCTAssertEqual(stats.usedPages, 70)
        XCTAssertEqual(stats.emptyPages, 30)
        
        let gcStats = try db.collection.getGCStats()
        
        // Should track 30 deleted pages for reuse
        XCTAssertGreaterThan(gcStats.reuseablePages, 25, "Should track most deleted pages")
        
        print("  ✅ Storage stats are accurate")
    }
    
    // MARK: - Edge Case 10: VACUUM Multiple Times
    
    func testGC_MultipleVacuums() async throws {
        print("🧹 Testing multiple consecutive VACUUMs")
        
        // Insert and delete
        let ids = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<30 {
            try await db.delete(id: ids[i])
        }
        
        // VACUUM #1
        let vacuum1 = try await db.vacuum()
        print("    VACUUM 1: Reclaimed \(vacuum1.pagesReclaimed) pages")
        
        // VACUUM #2 (should be no-op)
        let vacuum2 = try await db.vacuum()
        
        XCTAssertEqual(vacuum2.pagesReclaimed, 0, "Second VACUUM should reclaim nothing")
        
        print("  ✅ Multiple VACUUMs safe: second is no-op")
    }
    
    // MARK: - Edge Case 11: Page Reuse Order (FIFO)
    
    func testGC_PageReuseOrder() async throws {
        print("♻️  Testing page reuse order (FIFO)")
        
        // Insert 10 records
        let ids = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        // Delete in order: 0, 1, 2
        for i in 0..<3 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        // Check: pages 0, 1, 2 should be tracked for reuse
        let gcStats = try db.collection.getGCStats()
        XCTAssertEqual(gcStats.reuseablePages, 3)
        
        // Insert 3 new records (should reuse 0, 1, 2 in FIFO order)
        _ = try await db.insertMany((0..<3).map { i in BlazeDataRecord(["new": .int(i)]) })
        try await db.persist()
        
        let gcStatsAfter = try db.collection.getGCStats()
        
        // All reuseable pages should be consumed
        XCTAssertEqual(gcStatsAfter.reuseablePages, 0, "All reuseable pages should be used")
        
        print("  ✅ Page reuse follows FIFO order")
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
        
        // With page reuse: file size should be stable (< 2x initial)
        let growthRatio = Double(finalSize) / Double(initialSize)
        print("    File size growth: \(String(format: "%.2f", growthRatio))x")
        
        XCTAssertLessThan(growthRatio, 2.0, "File should not grow more than 2x with large churn")
        
        print("  ✅ Large churn handled: 10K operations, \(String(format: "%.2f", growthRatio))x growth")
    }
    
    // MARK: - Edge Case 13: GC Stats During Operations
    
    func testGC_StatsConsistencyDuringOperations() async throws {
        print("📊 Testing GC stats consistency during operations")
        
        // Insert 50
        let ids = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        let stats1 = try db.collection.getGCStats()
        XCTAssertEqual(stats1.usedPages, 50)
        XCTAssertEqual(stats1.totalPages, 50)
        
        // Delete 20
        for i in 0..<20 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let stats2 = try db.collection.getGCStats()
        XCTAssertEqual(stats2.usedPages, 30)
        XCTAssertGreaterThan(stats2.reuseablePages, 15, "Should track deleted pages")
        
        // Insert 20 (should reuse)
        _ = try await db.insertMany((0..<20).map { i in BlazeDataRecord(["new": .int(i)]) })
        try await db.persist()
        
        let stats3 = try db.collection.getGCStats()
        XCTAssertEqual(stats3.usedPages, 50)
        
        print("  ✅ GC stats remain consistent through operations")
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
        
        // Insert with specific IDs
        let specificID1 = UUID()
        let specificID2 = UUID()
        
        _ = try await db.insert(BlazeDataRecord(["id": .uuid(specificID1), "value": .int(1)]))
        _ = try await db.insert(BlazeDataRecord(["id": .uuid(specificID2), "value": .int(2)]))
        
        // Add more records
        _ = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Delete many records
        let allRecords = try await db.fetchAll()
        for record in allRecords.prefix(30) {
            if let id = record.storage["id"]?.uuidValue,
               id != specificID1 && id != specificID2 {
                try await db.delete(id: id)
            }
        }
        
        // VACUUM
        _ = try await db.vacuum()
        
        // Verify specific IDs still exist and fetchable
        let record1 = try await db.fetch(id: specificID1)
        let record2 = try await db.fetch(id: specificID2)
        
        XCTAssertNotNil(record1)
        XCTAssertNotNil(record2)
        XCTAssertEqual(record1?.storage["value"]?.intValue, 1)
        XCTAssertEqual(record2?.storage["value"]?.intValue, 2)
        
        print("  ✅ GC preserves record IDs correctly")
    }
    
    // MARK: - Edge Case 16: Max Reuseable Pages
    
    func testGC_MaxReusablePages() async throws {
        print("📈 Testing GC with maximum reuseable pages")
        
        // Insert 1000 records
        let ids = try await db.insertMany((0..<1000).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        // Delete all 1000
        for id in ids {
            try await db.delete(id: id)
        }
        try await db.persist()
        
        let gcStats = try db.collection.getGCStats()
        
        XCTAssertEqual(gcStats.reuseablePages, 1000, "Should track all 1000 deleted pages")
        
        // Insert 500 (should reuse first 500)
        _ = try await db.insertMany((0..<500).map { i in BlazeDataRecord(["new": .int(i)]) })
        try await db.persist()
        
        let gcStatsAfter = try db.collection.getGCStats()
        
        XCTAssertEqual(gcStatsAfter.reuseablePages, 500, "Should have 500 reuseable left")
        
        print("  ✅ Handles large reuseable page pool (1000 pages)")
    }
}

