//
//  PageReuseGCTests.swift
//  BlazeDBTests
//
//  Tests for page reuse garbage collection (PRIMARY GC mechanism)
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PageReuseGCTests: XCTestCase {
    
    private var dbURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageReuseTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "PageReuseTest", fileURL: try requireFixture(dbURL), password: "SecureTestDB-456!")
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
    
    // MARK: - Page Reuse Tests
    
    func testPageReuse_DeletedPagesAreReused() async throws {
        print("♻️  Testing deleted pages are reused")
        
        // Insert 100 records
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await requireFixture(db).persist()
        
        // Get storage stats before delete
        let statsBefore = try await requireFixture(db).getStorageStats()
        let pagesBefore = statsBefore.totalPages
        
        print("  📊 Before: \(pagesBefore) pages")
        
        // Delete 50 records
        for i in 0..<50 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let statsAfterDelete = try await requireFixture(db).getStorageStats()
        print("  📊 After delete: \(statsAfterDelete.usedPages) used, \(statsAfterDelete.emptyPages) empty")
        
        // Insert 50 NEW records
        _ = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["new": .int(i)]) })
        try await requireFixture(db).persist()
        
        // Check if file grew or stayed same
        let statsAfterReinsert = try await requireFixture(db).getStorageStats()
        
        // With page reuse: totalPages should stay same or grow minimally
        // Without page reuse: totalPages would be 150 (100 + 50)
        
        print("  📊 After reinsert: \(statsAfterReinsert.totalPages) pages")
        
        // If page reuse works: totalPages ≈ pagesBefore
        // If not working: totalPages = 150
        
        let growth = statsAfterReinsert.totalPages - pagesBefore
        print("  📊 File growth: +\(growth) pages")
        
        // Allow some growth (reuse might not be perfect yet)
        XCTAssertLessThan(growth, 30, "Should reuse most deleted pages (< 30 new pages)")
    }
    
    func testPageReuse_FileSizeStability() async throws {
        print("♻️  Testing file size stability over time")
        
        // Simulate churning database (insert + delete repeatedly)
        var allIDs: [UUID] = []
        
        // Round 1: Insert 100
        allIDs = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await requireFixture(db).persist()
        
        let sizeRound1 = try await requireFixture(db).getStorageStats().fileSize
        print("  Round 1 (100 records): \(sizeRound1 / 1024) KB")
        
        // Round 2: Delete 50, insert 50
        for i in 0..<50 {
            try await requireFixture(db).delete(id: allIDs[i])
        }
        let newIDs = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i + 1000)]) })
        allIDs = Array(allIDs.suffix(50)) + newIDs
        try await requireFixture(db).persist()
        
        let sizeRound2 = try await requireFixture(db).getStorageStats().fileSize
        print("  Round 2 (churn 50): \(sizeRound2 / 1024) KB")
        
        // Round 3: Delete 50, insert 50 again
        for i in 0..<50 {
            try await requireFixture(db).delete(id: allIDs[i])
        }
        _ = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i + 2000)]) })
        try await requireFixture(db).persist()
        
        let sizeRound3 = try await requireFixture(db).getStorageStats().fileSize
        print("  Round 3 (churn 50): \(sizeRound3 / 1024) KB")
        
        // With page reuse: sizes should be similar
        // Without reuse: Round3 >> Round2 >> Round1
        
        let growth = sizeRound3 - sizeRound1
        let growthPercent = Double(growth) / Double(sizeRound1) * 100
        
        print("  📊 Total growth: +\(growth / 1024) KB (\(String(format: "%.1f", growthPercent))%)")
        
        // Allow up to 50% growth (should be much less with page reuse)
        XCTAssertLessThan(growthPercent, 50, "File should not grow significantly with page reuse")
    }
    
    func testPageReuse_PreventsUnboundedGrowth() async throws {
        print("♻️  Testing page reuse prevents unbounded growth")
        
        // Simulate long-running app with churn
        var currentIDs: [UUID] = []
        var fileSizes: [Int64] = []
        
        for round in 0..<10 {
            // Delete old records
            if !currentIDs.isEmpty {
                for id in currentIDs {
                    try await requireFixture(db).delete(id: id)
                }
            }
            
            // Insert new records
            currentIDs = try await requireFixture(db).insertMany((0..<100).map { i in
                BlazeDataRecord(["round": .int(round), "value": .int(i)])
            })
            try await requireFixture(db).persist()
            
            // Track file size
            let stats = try await requireFixture(db).getStorageStats()
            fileSizes.append(stats.fileSize)
            
            print("  Round \(round): \(stats.fileSize / 1024) KB, \(stats.usedPages) used, \(stats.emptyPages) empty")
        }
        
        // With page reuse: file size should stabilize
        // Without reuse: file size grows linearly (10x)
        
        let initialSize = fileSizes[0]
        let finalSize = fileSizes[9]
        let growth = Double(finalSize - initialSize) / Double(initialSize) * 100
        
        print("  📊 Growth after 10 rounds: \(String(format: "%.1f", growth))%")
        
        // With perfect reuse: 0% growth
        // Allow up to 100% growth (should be much less)
        XCTAssertLessThan(growth, 100, "File should not grow unbounded")
    }
    
    func testGCStats_AccurateReporting() async throws {
        print("📊 Testing GC statistics accuracy")
        
        // Insert 50 records
        let ids = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await requireFixture(db).persist()
        
        let gcStats = try requireFixture(db).collection.getGCStats()
        
        XCTAssertEqual(gcStats.totalPages, 50)
        XCTAssertEqual(gcStats.usedPages, 50)
        XCTAssertEqual(gcStats.reuseablePages, 0, "No deletes yet")
        
        print("  Before delete: \(gcStats.description)")
        
        // Delete 25 records
        for i in 0..<25 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let gcStatsAfter = try requireFixture(db).collection.getGCStats()
        
        XCTAssertEqual(gcStatsAfter.usedPages, 25)
        // Note: reuseablePages will be > 0 if page tracking works
        
        print("  After delete: \(gcStatsAfter.description)")
    }
    
    // MARK: - Performance Impact
    
    func testPerformance_InsertWithPageReuse() async throws {
        // Swift 6: Use synchronous insertMany for performance measurement
        // Async within measure() causes 'sending' parameter issues
        let start = Date()
        
        // Create churn scenario
        var ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Delete and re-insert (test reuse performance)
        for _ in 0..<5 {
            for id in ids.prefix(50) {
                try await requireFixture(db).delete(id: id)
            }
            let newIDs = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
            ids = Array(ids.suffix(50)) + newIDs
        }
        
        let elapsed = Date().timeIntervalSince(start)
        print("  Page reuse performance: \(elapsed * 1000)ms")
    }
    
    func testPerformance_DeleteWithPageTracking() async throws {
        // Swift 6: Use synchronous delete for performance measurement
        let start = Date()
        
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        for id in ids {
            try await requireFixture(db).delete(id: id)
        }
        
        let elapsed = Date().timeIntervalSince(start)
        print("  Delete with tracking performance: \(elapsed * 1000)ms")
    }
}

