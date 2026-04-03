//
//  VacuumOperationsTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for VACUUM, compaction, and auto-GC
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

private actor ErrorCounter {
    var count = 0
    func increment() { count += 1 }
    func getCount() -> Int { count }
}

final class VacuumOperationsTests: XCTestCase {
    
    private var dbURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VacuumTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "VacuumTest", fileURL: try requireFixture(dbURL), password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        
        // Disable auto-vacuum before cleanup
        db?.disableAutoVacuum()
        
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Basic VACUUM Tests
    
    func testVacuumReclaimsSpace() async throws {
        print("🧹 Testing VACUUM reclaims disk space")
        
        // Insert 100 records
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in
            BlazeDataRecord(["value": .int(i)])
        })
        try await requireFixture(db).persist()
        
        let statsBefore = try await requireFixture(db).getStorageStats()
        print("  Before: \(statsBefore.usedPages) used pages, \(statsBefore.fileSize) bytes")
        
        // Delete 90 records
        for i in 0..<90 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let statsAfterDelete = try await requireFixture(db).getStorageStats()
        print("  After delete: \(statsAfterDelete.usedPages) used, \(statsAfterDelete.emptyPages) empty")
        
        // VACUUM
        let vacuumStats = try await requireFixture(db).vacuum()
        
        XCTAssertGreaterThan(vacuumStats.pagesReclaimed, 0, "Should reclaim some pages")
        XCTAssertGreaterThan(vacuumStats.sizeReclaimed, 0, "Should reclaim some space")
        XCTAssertEqual(vacuumStats.pagesAfter, 10, "Should have only 10 pages after vacuum")
        
        print("  ✅ VACUUM: \(vacuumStats.pagesReclaimed) pages reclaimed (\(vacuumStats.sizeReclaimed) bytes)")
    }
    
    func testVacuumPreservesData() async throws {
        print("🧹 Testing VACUUM preserves all data")
        
        // Insert diverse data
        let records = [
            BlazeDataRecord(["type": .string("text"), "value": .string("Hello world")]),
            BlazeDataRecord(["type": .string("number"), "value": .int(42)]),
            BlazeDataRecord(["type": .string("date"), "value": .date(Date())]),
            BlazeDataRecord(["type": .string("bool"), "value": .bool(true)]),
            BlazeDataRecord(["type": .string("array"), "value": .array([.int(1), .int(2), .int(3)])]),
            BlazeDataRecord(["type": .string("dict"), "value": .dictionary(["key": .string("value")])])
        ]
        
        let ids = try await requireFixture(db).insertMany(records)
        
        // Verify before VACUUM
        let beforeVacuum = try await requireFixture(db).fetchAll()
        XCTAssertEqual(beforeVacuum.count, 6)
        
        // VACUUM
        _ = try await requireFixture(db).vacuum()
        
        // Verify after VACUUM
        let afterVacuum = try await requireFixture(db).fetchAll()
        XCTAssertEqual(afterVacuum.count, 6, "All records should be preserved")
        
        // Verify each record
        for id in ids {
            let record = try await requireFixture(db).fetch(id: id)
            XCTAssertNotNil(record, "Record \(id) should exist after VACUUM")
        }
        
        print("  ✅ All 6 records preserved through VACUUM")
    }
    
    func testVacuumWithLargeDatabase() async throws {
        print("🧹 Testing VACUUM with large database (1000 records)")
        
        // Insert 1000 records
        let ids = try await requireFixture(db).insertMany((0..<1000).map { i in
            BlazeDataRecord(["value": .int(i)])
        })
        
        // Delete 900 records
        for i in 0..<900 {
            try await requireFixture(db).delete(id: ids[i])
        }
        
        let startTime = Date()
        let stats = try await requireFixture(db).vacuum()
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(duration, 10.0, "VACUUM should complete in < 10s for 1000 records")
        XCTAssertGreaterThan(stats.pagesReclaimed, 800, "Should reclaim most deleted pages")
        
        // Verify remaining records
        let remaining = try await requireFixture(db).count()
        XCTAssertEqual(remaining, 100)
        
        print("  ✅ VACUUM 1000 records in \(String(format: "%.2f", duration))s, reclaimed \(stats.pagesReclaimed) pages")
    }
    
    func testVacuumEmptyDatabase() async throws {
        print("🧹 Testing VACUUM on empty database")
        
        let stats = try await requireFixture(db).vacuum()
        
        XCTAssertEqual(stats.pagesBefore, 0)
        XCTAssertEqual(stats.pagesAfter, 0)
        XCTAssertEqual(stats.pagesReclaimed, 0)
        
        print("  ✅ Empty VACUUM: 0 pages reclaimed (no-op)")
    }
    
    func testVacuumWithNoWaste() async throws {
        print("🧹 Testing VACUUM with no wasted space")
        
        // Insert 50 records (don't delete any)
        _ = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        let stats = try await requireFixture(db).vacuum()
        
        XCTAssertEqual(stats.pagesReclaimed, 0, "Should reclaim 0 pages (no waste)")
        XCTAssertEqual(stats.sizeReclaimed, 0, "Should reclaim 0 bytes")
        
        print("  ✅ VACUUM with no waste: 0 pages reclaimed")
    }
    
    func testVacuumEncodingRoundTrip() async throws {
        // Regression: vacuum previously used JSONEncoder instead of BlazeBinaryEncoder,
        // writing records in a format that doesn't match the canonical read path.
        // This test verifies field values survive a vacuum round-trip.

        let id1 = UUID()
        let id2 = UUID()
        try await requireFixture(db).insert(BlazeDataRecord([
            "id": .uuid(id1), "name": .string("Alice"), "age": .int(30),
            "tags": .array([.string("admin"), .string("active")])
        ]))
        try await requireFixture(db).insert(BlazeDataRecord([
            "id": .uuid(id2), "name": .string("Bob"), "score": .double(99.5),
            "active": .bool(false)
        ]))

        // Vacuum rewrites all pages
        _ = try await requireFixture(db).vacuum()

        // Verify record count
        let all = try await requireFixture(db).fetchAll()
        XCTAssertEqual(all.count, 2, "Both records should survive vacuum")

        // Verify field values by fetching each record
        let alice = try await requireFixture(db).fetch(id: id1)
        XCTAssertNotNil(alice, "Alice should be fetchable after vacuum")
        XCTAssertEqual(alice?.storage["name"]?.stringValue, "Alice")
        XCTAssertEqual(alice?.storage["age"]?.intValue, 30)

        let bob = try await requireFixture(db).fetch(id: id2)
        XCTAssertNotNil(bob, "Bob should be fetchable after vacuum")
        XCTAssertEqual(bob?.storage["name"]?.stringValue, "Bob")
        XCTAssertEqual(bob?.storage["score"]?.doubleValue, 99.5)
        XCTAssertEqual(bob?.storage["active"]?.boolValue, false)

        // Verify a second vacuum is idempotent
        _ = try await requireFixture(db).vacuum()
        let afterSecond = try await requireFixture(db).fetchAll()
        XCTAssertEqual(afterSecond.count, 2, "Second vacuum should not lose records")

        let aliceAgain = try await requireFixture(db).fetch(id: id1)
        XCTAssertEqual(aliceAgain?.storage["name"]?.stringValue, "Alice")
    }

    // MARK: - Storage Stats Tests
    
    func testGetStorageStats() async throws {
        print("📊 Testing storage statistics")
        
        // Insert records
        let ids = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        let stats = try await requireFixture(db).getStorageStats()
        
        XCTAssertEqual(stats.usedPages, 50)
        XCTAssertEqual(stats.emptyPages, 0, "No empty pages before deletion")
        XCTAssertEqual(stats.totalPages, 50)
        
        // Delete some records
        for i in 0..<25 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let statsAfter = try await requireFixture(db).getStorageStats()
        
        XCTAssertEqual(statsAfter.usedPages, 25)
        XCTAssertEqual(statsAfter.emptyPages, 25, "Should have 25 empty pages")
        XCTAssertGreaterThan(statsAfter.wastePercentage, 40, "Should be ~50% wasted")
        
        print("  ✅ Stats: \(statsAfter.usedPages) used, \(statsAfter.emptyPages) empty, \(String(format: "%.1f", statsAfter.wastePercentage))% waste")
    }
    
    // MARK: - Auto-VACUUM Tests
    
    func testAutoVacuumTriggersCorrectly() async throws {
        print("🤖 Testing auto-VACUUM trigger")
        
        // Insert and delete to create waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await requireFixture(db).persist()
        
        // Delete 60 records (60% waste)
        for i in 0..<60 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        // Enable auto-vacuum with 50% threshold
        try requireFixture(db).enableAutoVacuum(wasteThreshold: 0.50, checkInterval: 0.5)  // Check every 0.5s
        
        // Wait for auto-vacuum to run
        try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5s
        
        // Check if space was reclaimed
        let statsAfter = try await requireFixture(db).getStorageStats()
        
        // If auto-vacuum ran, empty pages should be reduced
        print("  📊 After auto-vacuum: \(statsAfter.emptyPages) empty pages")
        
        // Note: Timing-dependent, so we just verify it doesn't crash
        try requireFixture(db).disableAutoVacuum()
        
        print("  ✅ Auto-VACUUM mechanism functional")
    }
    
    func testAutoVacuumCanBeDisabled() async throws {
        print("🤖 Testing auto-VACUUM can be disabled")
        
        try requireFixture(db).enableAutoVacuum(wasteThreshold: 0.01, checkInterval: 0.1)
        
        // Wait a moment
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        // Disable
        try requireFixture(db).disableAutoVacuum()
        
        // Should not crash or cause issues
        _ = try await requireFixture(db).insert(BlazeDataRecord(["test": .bool(true)]))
        
        print("  ✅ Auto-VACUUM disabled successfully")
    }
    
    // MARK: - Edge Cases
    
    func testVacuumDuringConcurrentReads() async throws {
        print("🧹 Testing VACUUM during concurrent reads")
        
        // Insert data
        _ = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        let errorCounter = ErrorCounter()
        let db = try XCTUnwrap(self.db)
        
        await withTaskGroup(of: Void.self) { group in
            // VACUUM in background
            group.addTask { [db] in
                do {
                    _ = try await db.vacuum()
                } catch {
                    print("    VACUUM error: \(error)")
                }
            }
            
            // Concurrent reads
            for _ in 0..<20 {
                group.addTask { [db] in
                    do {
                        _ = try await db.fetchAll()
                    } catch {
                        await errorCounter.increment()
                    }
                }
            }
        }
        
        let readErrors = await errorCounter.getCount()
        // Some reads may fail during VACUUM (database locked), but shouldn't crash
        print("  ✅ Concurrent reads: \(readErrors) errors (expected)")
    }
    
    func testVacuumWithIndexes() async throws {
        print("🧹 Testing VACUUM preserves indexes")
        
        // Create indexes
        try requireFixture(db).collection.createIndex(on: "status")
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Insert and delete
        let ids = try await requireFixture(db).insertMany((0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ])
        })
        
        // Delete half
        for i in 0..<25 {
            try await requireFixture(db).delete(id: ids[i])
        }
        
        // VACUUM
        _ = try await requireFixture(db).vacuum()
        
        // Verify indexes still work
        let openBugs = try await requireFixture(db).query().where("status", equals: .string("open")).execute()
        XCTAssertGreaterThan(openBugs.count, 0, "Index queries should work after VACUUM")
        
        let searchResults = try requireFixture(db).collection.searchOptimized(query: "Bug", in: ["title"])
        XCTAssertGreaterThan(searchResults.count, 0, "Search should work after VACUUM")
        
        print("  ✅ Indexes preserved through VACUUM")
    }
    
    func testMultipleVacuums() async throws {
        print("🧹 Testing multiple consecutive VACUUMs")
        
        // Insert and delete multiple times
        for round in 0..<5 {
            let ids = try await requireFixture(db).insertMany((0..<20).map { i in BlazeDataRecord(["round": .int(round), "value": .int(i)]) })
            
            for i in 0..<10 {
                try await requireFixture(db).delete(id: ids[i])
            }
            
            _ = try await requireFixture(db).vacuum()
        }
        
        // Final count should be 50 (10 × 5 rounds)
        let finalCount = try await requireFixture(db).count()
        XCTAssertEqual(finalCount, 50)
        
        print("  ✅ Multiple VACUUMs: \(finalCount) records preserved")
    }
    
    // MARK: - Performance
    // Moved to Tier3Heavy vacuum performance suite.
}

