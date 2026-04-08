//
//  PageGCTests.swift
//  BlazeDBTests
//
//  Tests for page-level garbage collection and VACUUM
//
//  Validates that disk pages are reclaimed and file size stays bounded
//
//  Created: 2025-11-13
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PageGCTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageGC-\(testID).blazedb")
        tempURL = url
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "page_gc_test", fileURL: url, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }

    private func databaseFileSize() throws -> Int {
        let url = try XCTUnwrap(tempURL)
        return try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
    }
    
    // MARK: - Page GC Foundation Tests
    
    func testPageGC_MarkAndReuse() {
        print("\n♻️ Testing Page Mark and Reuse")
        
        let pageGC = PageGarbageCollector()
        
        // Mark pages as obsolete
        pageGC.markPageObsolete(10)
        pageGC.markPageObsolete(20)
        pageGC.markPageObsolete(30)
        
        let stats1 = pageGC.getStats()
        XCTAssertEqual(stats1.freePagesAvailable, 3)
        print("  📊 Free pages: \(stats1.freePagesAvailable)")
        
        // Reuse a page
        let reused1 = pageGC.getFreePage()
        XCTAssertNotNil(reused1)
        XCTAssertTrue([10, 20, 30].contains(reused1!))
        print("  ♻️ Reused page: \(reused1!)")
        
        let stats2 = pageGC.getStats()
        XCTAssertEqual(stats2.freePagesAvailable, 2)
        XCTAssertEqual(stats2.totalPagesReused, 1)
        
        print("  ✅ Page reuse works!")
    }
    
    func testPageGC_MultiplePages() {
        let pageGC = PageGarbageCollector()
        
        // Free many pages
        let pages = Array(0..<100)
        pageGC.markPagesObsolete(pages)
        
        let stats = pageGC.getStats()
        XCTAssertEqual(stats.freePagesAvailable, 100)
        
        // Reuse 10 pages
        let reused = pageGC.getMultipleFreePages(count: 10)
        XCTAssertEqual(reused.count, 10)
        
        let stats2 = pageGC.getStats()
        XCTAssertEqual(stats2.freePagesAvailable, 90)
        XCTAssertEqual(stats2.totalPagesReused, 10)
        
        print("✅ Multiple page reuse works!")
    }
    
    func testPageGC_ReuseRate() {
        let pageGC = PageGarbageCollector()
        
        // Free 100 pages
        pageGC.markPagesObsolete(Array(0..<100))
        
        // Reuse 80 pages
        for _ in 0..<80 {
            _ = pageGC.getFreePage()
        }
        
        let stats = pageGC.getStats()
        XCTAssertEqual(stats.totalPagesFreed, 100)
        XCTAssertEqual(stats.totalPagesReused, 80)
        XCTAssertEqual(stats.reuseRate, 0.8, accuracy: 0.01)
        
        print("✅ Reuse rate tracking works!")
    }
    
    // MARK: - Integration with Version GC
    
    func testVersionGC_FreesPages() {
        print("\n🗑️ Testing Version GC Frees Disk Pages")
        
        let versionManager = VersionManager()
        let recordID = UUID()
        
        // Create 5 versions of same record
        for i in 1...5 {
            let version = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i * 10,  // Pages: 10, 20, 30, 40, 50
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(version)
        }
        
        let pageStatsBefore = versionManager.pageGC.getStats()
        print("  Free pages before GC: \(pageStatsBefore.freePagesAvailable)")
        
        // Run GC (should keep only v5, free pages 10, 20, 30, 40)
        let removed = versionManager.garbageCollect()
        
        let pageStatsAfter = versionManager.pageGC.getStats()
        print("  Free pages after GC: \(pageStatsAfter.freePagesAvailable)")
        
        XCTAssertEqual(removed, 4, "Should remove 4 versions")
        XCTAssertEqual(pageStatsAfter.freePagesAvailable, 4, "Should free 4 pages")
        
        print("  ✅ Version GC correctly frees disk pages!")
    }
    
    func testPageReuse_PreventsFileGrowth() throws {
        print("\n📏 Testing Page Reuse Prevents File Growth")
        
        // Enable MVCC
        try requireFixture(db).setMVCCEnabled(true)
        
        // Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 1000))
            ]))
            ids.append(id)
        }
        
        try requireFixture(db).persist()
        let sizeAfterInsert = try databaseFileSize()
        print("  Size after 100 inserts: \(sizeAfterInsert / 1000) KB")
        
        // Delete 90 records
        for id in ids.prefix(90) {
            try requireFixture(db).delete(id: id)
        }
        
        // Trigger GC
        try requireFixture(db).runGarbageCollection()
        
        try requireFixture(db).persist()
        let sizeAfterDelete = try databaseFileSize()
        print("  Size after 90 deletes: \(sizeAfterDelete / 1000) KB")
        
        // Insert 90 new records (should reuse freed pages!)
        for i in 0..<90 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i + 1000),
                "data": .string(String(repeating: "y", count: 1000))
            ]))
        }
        
        try requireFixture(db).persist()
        let sizeAfterReinsert = try databaseFileSize()
        print("  Size after 90 re-inserts: \(sizeAfterReinsert / 1000) KB")
        
        // File should NOT have grown much (pages were reused)
        let growth = sizeAfterReinsert - sizeAfterInsert
        let growthPercentage = Double(growth) / Double(sizeAfterInsert)
        
        print("  📊 File growth: \(growth / 1000) KB (\(String(format: "%.1f", growthPercentage * 100))%)")
        
        // Should grow < 20% (allowing for overhead)
        XCTAssertLessThan(growthPercentage, 0.20, "Page reuse should limit file growth")
        
        print("  ✅ Page reuse prevents file blowup!")
    }
    
    // MARK: - VACUUM Tests
    
    func testVACUUM_ReclaimsSpace() throws {
        print("\n🗑️ Testing VACUUM Reclaims Disk Space")
        
        // Insert 1000 records
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 500))
            ]))
            ids.append(id)
        }
        
        try requireFixture(db).persist()
        let sizeBeforeDelete = try databaseFileSize()
        print("  Size with 1000 records: \(sizeBeforeDelete / 1_000_000) MB")
        
        // Delete 900 records (90%!)
        for id in ids.prefix(900) {
            try requireFixture(db).delete(id: id)
        }
        
        try requireFixture(db).persist()
        let sizeAfterDelete = try databaseFileSize()
        print("  Size after deleting 900: \(sizeAfterDelete / 1_000_000) MB")
        
        // File should still be large (deleted data still on disk)
        XCTAssertGreaterThan(sizeAfterDelete, sizeBeforeDelete * 8 / 10, "Deleted data still on disk")
        
        // Run VACUUM
        let reclaimed = try requireFixture(db).vacuum()
        
        let sizeAfterVacuum = try databaseFileSize()
        print("  Size after VACUUM: \(sizeAfterVacuum / 1_000_000) MB")
        print("  Reclaimed: \(reclaimed / 1_000_000) MB")
        
        // File should be much smaller now (only 100 records)
        XCTAssertLessThan(sizeAfterVacuum, sizeBeforeDelete / 5, "VACUUM should shrink file significantly")
        
        // Should still have 100 records
        let finalCount = try requireFixture(db).count()
        XCTAssertEqual(finalCount, 100)
        
        print("  ✅ VACUUM successfully reclaimed \(reclaimed / 1_000_000) MB!")
    }
    
    func testVACUUM_PreservesData() throws {
        print("\n🔒 Testing VACUUM Preserves All Data")
        
        // Insert records with specific data
        var expectedRecords: [UUID: BlazeDataRecord] = [:]
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "name": .string("Record \(i)"),
                "value": .double(Double(i) * 1.5)
            ])
            let id = try requireFixture(db).insert(record)
            expectedRecords[id] = record
        }
        
        // Run VACUUM
        try requireFixture(db).vacuum()
        
        // Verify all data intact
        for (id, expected) in expectedRecords {
            let fetched = try requireFixture(db).fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(id) should exist after VACUUM")
            XCTAssertEqual(fetched?["index"]?.intValue, expected["index"]?.intValue)
            XCTAssertEqual(fetched?["name"]?.stringValue, expected["name"]?.stringValue)
        }
        
        print("  ✅ VACUUM preserved all data perfectly!")
    }
    
    // MARK: - Storage Health Tests
    
    func testStorageHealth_Monitoring() throws {
        print("\n📊 Testing Storage Health Monitoring")
        
        // Insert records
        for i in 0..<500 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 1000))
            ]))
        }
        
        try requireFixture(db).persist()
        
        let health = try requireFixture(db).getStorageHealth()
        print(health.description)
        
        XCTAssertGreaterThan(health.fileSizeBytes, 0)
        XCTAssertGreaterThan(health.activeDataBytes, 0)
        XCTAssertGreaterThan(health.totalPages, 0)
        
        print("  ✅ Storage health monitoring works!")
    }
    
    func testStorageHealth_DetectsWaste() throws {
        print("\n⚠️ Testing Storage Health Detects Waste")
        
        // Insert 100 records
        var ids: [UUID] = []
        for _ in 0..<100 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "data": .string(String(repeating: "x", count: 2000))
            ]))
            ids.append(id)
        }
        
        try requireFixture(db).persist()
        
        let healthBefore = try requireFixture(db).getStorageHealth()
        print("  Before delete: \(String(format: "%.1f", healthBefore.wastedPercentage * 100))% wasted")
        
        // Delete 80 records
        for id in ids.prefix(80) {
            try requireFixture(db).delete(id: id)
        }
        
        // Enable MVCC and run GC
        try requireFixture(db).setMVCCEnabled(true)
        try requireFixture(db).runGarbageCollection()
        
        let healthAfter = try requireFixture(db).getStorageHealth()
        print("  After delete+GC: \(String(format: "%.1f", healthAfter.wastedPercentage * 100))% wasted")
        
        // Should detect waste
        XCTAssertGreaterThan(healthAfter.wastedPercentage, 0.5, "Should detect >50% waste")
        XCTAssertTrue(healthAfter.needsVacuum, "Should recommend VACUUM")
        
        print("  ✅ Storage health correctly detects waste!")
    }
    
    func testAutoVacuum_TriggersWhenNeeded() throws {
        print("\n🤖 Testing Auto-VACUUM")
        
        // Insert and delete to create waste
        var ids: [UUID] = []
        for _ in 0..<200 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "data": .string(String(repeating: "x", count: 2000))
            ]))
            ids.append(id)
        }
        
        // Delete most records
        for id in ids.prefix(180) {
            try requireFixture(db).delete(id: id)
        }
        
        try requireFixture(db).setMVCCEnabled(true)
        try requireFixture(db).runGarbageCollection()
        
        let sizeBefore = try databaseFileSize()
        
        // Auto-vacuum should trigger
        try requireFixture(db).autoVacuumIfNeeded()
        
        let sizeAfter = try databaseFileSize()
        
        print("  Before: \(sizeBefore / 1_000_000) MB")
        print("  After:  \(sizeAfter / 1_000_000) MB")
        print("  Savings: \(String(format: "%.1f", Double(sizeBefore - sizeAfter) / Double(sizeBefore) * 100))%")
        
        XCTAssertLessThan(sizeAfter, sizeBefore, "Auto-vacuum should shrink file")
        
        print("  ✅ Auto-vacuum works!")
    }
    
    // MARK: - Stress Tests
    
    func testPageGC_HeavyUpdateWorkload() throws {
        print("\n💪 Testing Page GC Under Heavy Updates")
        
        try requireFixture(db).setMVCCEnabled(true)
        
        // Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        let sizeInitial = try databaseFileSize()
        
        // Update each record 10 times (creates 1000 versions!)
        for _ in 0..<10 {
            for id in ids {
                try requireFixture(db).update(id: id, with: BlazeDataRecord([
                    "value": .int(Int.random(in: 0...1000))
                ]))
            }
            
            // Trigger GC every 100 updates
            try requireFixture(db).runGarbageCollection()
        }
        
        try requireFixture(db).persist()
        let sizeFinal = try databaseFileSize()
        
        let growth = Double(sizeFinal - sizeInitial) / max(Double(sizeInitial), 1.0)
        
        print("  Initial size: \(sizeInitial / 1000) KB")
        print("  Final size:   \(sizeFinal / 1000) KB")
        print("  Growth:       \(String(format: "%.1f", growth * 100))%")
        
        // MVCC updates need one spare generation of pages before old versions can be reclaimed,
        // so steady-state growth should stay bounded to roughly one extra working set.
        XCTAssertLessThan(growth, 1.10, "Page reuse should keep MVCC update growth bounded")
        
        print("  ✅ Page GC prevents blowup during heavy updates!")
    }
    
    func testPageGC_DeleteInsertChurn() throws {
        print("\n🔄 Testing Delete/Insert Churn")
        
        try requireFixture(db).setMVCCEnabled(true)
        
        var baselineSize: Int?
        
        // Churn: Insert 100, delete 100, repeat 10 times
        for cycle in 0..<10 {
            var ids: [UUID] = []
            
            // Insert 100
            for i in 0..<100 {
                let id = try requireFixture(db).insert(BlazeDataRecord([
                    "cycle": .int(cycle),
                    "index": .int(i)
                ]))
                ids.append(id)
            }
            
            // Delete 100
            for id in ids {
                try requireFixture(db).delete(id: id)
            }
            
            // GC after each cycle
            try requireFixture(db).runGarbageCollection()

            if cycle == 0 {
                try requireFixture(db).persist()
                baselineSize = try databaseFileSize()
            }
        }
        
        try requireFixture(db).persist()
        let sizeFinal = try databaseFileSize()
        let sizeInitial = baselineSize ?? sizeFinal
        
        let growth = Double(sizeFinal - sizeInitial) / max(Double(sizeInitial), 1.0)
        
        print("  Initial size: \(sizeInitial / 1000) KB")
        print("  Final size:   \(sizeFinal / 1000) KB")
        print("  Growth:       \(String(format: "%.1f", growth * 100))%")
        
        // With page reuse, file should not grow much
        XCTAssertLessThan(growth, 2.0, "Page reuse should prevent blowup during churn")
        
        print("  ✅ Page reuse handles churn!")
    }
    
    // MARK: - VACUUM Edge Cases
    
    func testVACUUM_EmptyDatabase() throws {
        print("\n🗑️ Testing VACUUM on Empty Database")
        
        // VACUUM empty DB (should not crash)
        XCTAssertNoThrow(try requireFixture(db).vacuum())
        
        // Should still be usable
        let id = try requireFixture(db).insert(BlazeDataRecord(["test": .string("value")]))
        let fetched = try requireFixture(db).fetch(id: id)
        XCTAssertNotNil(fetched)
        
        print("  ✅ VACUUM on empty DB works!")
    }
    
    func testVACUUM_LargeDatabase() throws {
        print("\n🗑️ Testing VACUUM on Large Database")
        
        // Insert 5000 records
        for i in 0..<5000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
        }

        // Ensure the backing file exists on disk before compaction.
        try requireFixture(db).persist()
        
        let countBefore = try requireFixture(db).count()
        
        // VACUUM
        let reclaimed = try requireFixture(db).vacuum()
        
        let countAfter = try requireFixture(db).count()
        
        print("  Records before: \(countBefore)")
        print("  Records after:  \(countAfter)")
        print("  Reclaimed:      \(reclaimed / 1_000_000) MB")
        
        XCTAssertEqual(countBefore, countAfter, "VACUUM should preserve all records")
        
        print("  ✅ VACUUM works on large database!")
    }
    
    // MARK: - Integration Tests
    
    func testCompleteGC_MemoryAndDisk() throws {
        print("\n🔥 Complete GC Test: Memory AND Disk")
        
        try requireFixture(db).setMVCCEnabled(true)
        
        // Heavy workload
        var ids: [UUID] = []
        for i in 0..<500 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "value": .int(i)
            ]))
            ids.append(id)
        }
        
        // Update many times
        for _ in 0..<5 {
            for id in ids.prefix(400) {
                try requireFixture(db).update(id: id, with: BlazeDataRecord([
                    "value": .int(Int.random(in: 0...1000))
                ]))
            }
        }
        
        // Delete half
        for id in ids.prefix(250) {
            try requireFixture(db).delete(id: id)
        }
        
        // Check health before GC
        let healthBefore = try requireFixture(db).getStorageHealth()
        print("  Before GC:")
        print(healthBefore.description)
        
        // Run complete GC
        try requireFixture(db).runGarbageCollection()  // Version GC (memory + pages)
        
        let healthAfter = try requireFixture(db).getStorageHealth()
        print("  After GC:")
        print(healthAfter.description)
        
        // Obsolete pages should be tracked
        XCTAssertGreaterThan(healthAfter.obsoletePages, 0, "Should have obsolete pages")
        
        // Run VACUUM to actually shrink file
        _ = try requireFixture(db).vacuum()
        
        let healthFinal = try requireFixture(db).getStorageHealth()
        print("  After VACUUM:")
        print(healthFinal.description)
        
        print("  ✅ Complete GC (memory + disk) works!")
    }
}

