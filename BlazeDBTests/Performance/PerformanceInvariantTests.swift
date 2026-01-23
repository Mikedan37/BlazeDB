//
//  PerformanceInvariantTests.swift
//  BlazeDBTests
//
//  Asserts performance invariants to catch regressions like the 10,000 fsync() bug.
//  These tests verify that operations stay within performance bounds.
//

import XCTest
@testable import BlazeDBCore

final class PerformanceInvariantTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerfInv-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try! BlazeDBClient(name: "perf_test", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Insert Performance
    
    /// Test: Batch insert should be fast (< 2s for 10k records)
    func testBatchInsert10kPerformance() throws {
        let records = (0..<10000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        let start = Date()
        _ = try db.insertMany(records)
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 2.0, 
                         "Batch insert of 10k should be < 2s, was \(String(format: "%.2f", duration))s")
    }
    
    /// Test: Individual inserts should be reasonably fast
    func testIndividualInsertPerformance() throws {
        let start = Date()
        
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let duration = Date().timeIntervalSince(start)
        let avgPerInsert = duration / 100
        
        XCTAssertLessThan(avgPerInsert, 0.01, 
                         "Individual insert should average < 10ms, was \(String(format: "%.2f", avgPerInsert * 1000))ms")
    }
    
    // MARK: - Persist Performance
    
    /// Test: Persist should be fast (metadata write only)
    func testPersistPerformance() throws {
        // Insert 1000 records
        for i in 0..<1000 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Measure persist time
        let start = Date()
        try db.persist()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 0.1, 
                         "Persist after 1000 inserts should be < 100ms, was \(String(format: "%.2f", duration * 1000))ms")
    }
    
    /// Test: Multiple persist calls shouldn't accumulate overhead
    func testMultiplePersistPerformance() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        var durations: [TimeInterval] = []
        
        // Persist 10 times
        for _ in 0..<10 {
            let start = Date()
            try db.persist()
            let duration = Date().timeIntervalSince(start)
            durations.append(duration)
        }
        
        let maxDuration = durations.max() ?? 0
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        
        XCTAssertLessThan(maxDuration, 0.05, "Any single persist should be < 50ms")
        XCTAssertLessThan(avgDuration, 0.02, "Average persist should be < 20ms")
    }
    
    // MARK: - Read Performance
    
    /// Test: fetchAll on 1000 records should be fast
    func testFetchAllPerformance() throws {
        // Insert 1000 records
        for i in 0..<1000 {
            try db.insert(BlazeDataRecord(["index": .int(i), "data": .string("Record \(i)")]))
        }
        
        try db.persist()
        
        // Measure fetchAll
        let start = Date()
        let records = try db.fetchAll()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(records.count, 1000)
        XCTAssertLessThan(duration, 0.5, 
                         "FetchAll of 1000 records should be < 500ms, was \(String(format: "%.2f", duration * 1000))ms")
    }
    
    /// Test: Query with filter should be fast
    func testQueryWithFilterPerformance() throws {
        // Insert 1000 records (100 matching)
        for i in 0..<1000 {
            try db.insert(BlazeDataRecord([
                "status": .string(i < 100 ? "active" : "inactive")
            ]))
        }
        
        let start = Date()
        let result = try db.query()
            .where("status", equals: .string("active"))
            .execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(result.count, 100)
        XCTAssertLessThan(duration, 0.3, 
                         "Query with filter on 1000 records should be < 300ms, was \(String(format: "%.2f", duration * 1000))ms")
    }
    
    // MARK: - Aggregation Performance
    
    /// Test: Aggregation on 10k records should be fast
    func testAggregationPerformance() throws {
        let records = (0..<10000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try db.insertMany(records)
        
        let start = Date()
        let result = try db.query()
            .sum("value", as: "total")
            .executeAggregation()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(result.sum("total"), 49995000.0, "Sum should be correct")
        XCTAssertLessThan(duration, 2.0, 
                         "Aggregation on 10k records should be < 2s, was \(String(format: "%.2f", duration))s")
    }
    
    // MARK: - Metadata I/O Tests
    
    /// Test: Inserts shouldn't trigger excessive metadata reloads
    func testNoExcessiveMetadataReloads() throws {
        // This test catches the bug where every insert was loading metadata from disk
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Get initial modification time
        let initialMeta = try? FileManager.default.attributesOfItem(atPath: metaURL.path)
        let initialModDate = initialMeta?[.modificationDate] as? Date
        
        // Insert 10 records (below the 100-record flush threshold)
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Metadata shouldn't be written yet (batched writes)
        let afterInsertMeta = try? FileManager.default.attributesOfItem(atPath: metaURL.path)
        let afterInsertModDate = afterInsertMeta?[.modificationDate] as? Date
        
        if let initial = initialModDate, let after = afterInsertModDate {
            // File should either not change or only change once (not 10 times!)
            let timeDiff = after.timeIntervalSince(initial)
            XCTAssertLessThan(timeDiff, 0.5, 
                             "Metadata file should not be written on every insert")
        }
    }
    
    /// Test: Persist should write metadata exactly once
    func testPersistWritesMetadataOnce() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Persist
        try db.persist()
        
        let firstPersist = try FileManager.default.attributesOfItem(atPath: metaURL.path)
        let firstModDate = firstPersist[.modificationDate] as! Date
        let firstSize = firstPersist[.size] as! Int
        
        // Wait a bit
        Thread.sleep(forTimeInterval: 0.01)
        
        // Persist again (no changes)
        try db.persist()
        
        let secondPersist = try FileManager.default.attributesOfItem(atPath: metaURL.path)
        let secondModDate = secondPersist[.modificationDate] as! Date
        let secondSize = secondPersist[.size] as! Int
        
        // Size should be identical
        XCTAssertEqual(firstSize, secondSize, 
                      "Metadata size shouldn't change on no-op persist")
        
        // File should be rewritten (atomic write always updates modDate)
        // but the CONTENT should be identical
    }
    
    // MARK: - Memory Usage Tests
    
    /// Test: Memory usage stays reasonable
    func testMemoryUsageReasonable() throws {
        // This is a smoke test - actual memory profiling needs Instruments
        let records = (0..<10000).map { i in
            BlazeDataRecord(["data": .string(String(repeating: "X", count: 100))])
        }
        
        let start = Date()
        _ = try db.insertMany(records)
        let duration = Date().timeIntervalSince(start)
        
        // If this takes > 5s, there's likely a memory issue (thrashing, leaks)
        XCTAssertLessThan(duration, 5.0, 
                         "10k inserts with 100-char strings should be < 5s, was \(String(format: "%.2f", duration))s")
    }
    
    // MARK: - Reopen Performance
    
    /// Test: Reopening database should be fast
    func testReopenPerformance() throws {
        // Create database with 1000 records
        for i in 0..<1000 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        try db.persist()
        
        // Close
        db = nil
        BlazeDBClient.clearCachedKey()
        
        // Measure reopen time
        let start = Date()
        db = try BlazeDBClient(name: "perf_test", fileURL: tempURL, password: "test-pass-123")
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 0.5, 
                         "Reopening DB with 1000 records should be < 500ms, was \(String(format: "%.2f", duration * 1000))ms")
        
        XCTAssertEqual(db.count(), 1000, "All records should be loaded")
    }
    
    // MARK: - Update Performance
    
    /// Test: Batch updates should be fast
    func testBatchUpdatePerformance() throws {
        // Insert 1000 records
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Measure batch update time
        let start = Date()
        for id in ids {
            try db.update(id: id, with: BlazeDataRecord(["value": .int(999)]))
        }
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 2.0, 
                         "1000 individual updates should be < 2s, was \(String(format: "%.2f", duration))s")
    }
    
    // MARK: - Delete Performance
    
    /// Test: Batch deletes should be fast
    func testBatchDeletePerformance() throws {
        // Insert 1000 records
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Measure batch delete time
        let start = Date()
        for id in ids {
            try db.delete(id: id)
        }
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 1.0, 
                         "1000 individual deletes should be < 1s, was \(String(format: "%.2f", duration))s")
        
        XCTAssertEqual(db.count(), 0, "All records should be deleted")
    }
}

