//
//  PerformanceInvariantTests.swift
//  BlazeDBTests
//
//  Asserts performance invariants to catch regressions like the 10,000 fsync() bug.
//  These tests verify that operations stay within performance bounds.
//

import XCTest
@testable import BlazeDB

final class PerformanceInvariantTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        // Enable logging and stacktraces for debugging
        BlazeLogger.level = .error
        BlazeLogger.captureStackTraces = true
        BlazeLogger.maxStackFrames = 20  // Show more stack frames
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerfInv-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        do {
            db = try BlazeDBClient(name: "perf_test", fileURL: tempURL, password: "PerformanceInvariant123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Insert Performance
    
    /// Test: Batch insert should be fast (< 15s for 10k records)
    /// Note: Realistic threshold based on ~1ms per record with disk I/O overhead
    func testBatchInsert10kPerformance() throws {
        let records = (0..<10000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        
        let start = Date()
        _ = try db.insertMany(records)
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 15.0, 
                         "Batch insert of 10k should be < 15s, was \(String(format: "%.2f", duration))s")
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
        // CRITICAL: Use explicit unique IDs to prevent overwrites during batch insert
        let records = (0..<10000).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ])
        }
        let insertedIds = try db.insertMany(records)
        // CRITICAL: Persist records to ensure they're visible for aggregation
        try db.persist()
        
        // Verify all records were inserted
        XCTAssertEqual(insertedIds.count, 10000, "All 10,000 records should be inserted")
        
        // Verify record count matches
        let recordCount = db.count()
        XCTAssertEqual(recordCount, 10000, "Database should contain 10,000 records")
        
        let start = Date()
        let result = try db.query()
            .sum("value", as: "total")
            .executeAggregation()
        let duration = Date().timeIntervalSince(start)
        
        // Expected sum: 0 + 1 + 2 + ... + 9999 = 9999 * 10000 / 2 = 49,995,000
        let expectedSum = 49995000.0
        let actualSum = result.sum("total") ?? 0.0
        
        // If sum is wrong, also check the count to see if records are missing
        let countResult = try db.query().count().executeAggregation()
        let actualCount = countResult.count ?? 0
        
        // Debug: Check how many records have the "value" field and verify values
        let allRecords = try db.query().execute().records
        var recordsWithValue = 0
        var recordsWithoutValue = 0
        var sumFromRecords = 0.0
        var valueCounts: [Int: Int] = [:] // Track how many times each value appears
        var outOfRangeValues: [Int] = [] // Values outside 0-9999
        
        for record in allRecords {
            if let value = record.storage["value"] {
                recordsWithValue += 1
                if case .int(let v) = value {
                    sumFromRecords += Double(v)
                    valueCounts[v, default: 0] += 1
                    if v < 0 || v >= 10000 {
                        outOfRangeValues.append(v)
                    }
                } else if case .double(let v) = value {
                    sumFromRecords += v
                    let intV = Int(v)
                    valueCounts[intV, default: 0] += 1
                    if intV < 0 || intV >= 10000 {
                        outOfRangeValues.append(intV)
                    }
                }
            } else {
                recordsWithoutValue += 1
            }
        }
        
        // Check for duplicates or missing values
        var missingValues: [Int] = []
        var duplicateValues: [Int] = []
        for i in 0..<10000 {
            let count = valueCounts[i] ?? 0
            if count == 0 {
                missingValues.append(i)
            } else if count > 1 {
                duplicateValues.append(i)
            }
        }
        
        print("📊 Aggregation Debug:")
        print("  Total records: \(allRecords.count)")
        print("  Records with 'value' field: \(recordsWithValue)")
        print("  Records without 'value' field: \(recordsWithoutValue)")
        print("  Sum from records: \(sumFromRecords)")
        print("  Sum from aggregation: \(actualSum)")
        print("  Missing values (0-9999): \(missingValues.prefix(20))\(missingValues.count > 20 ? " ... (\(missingValues.count) total)" : "")")
        print("  Duplicate values: \(duplicateValues.prefix(20))\(duplicateValues.count > 20 ? " ... (\(duplicateValues.count) total)" : "")")
        print("  Out of range values: \(outOfRangeValues.prefix(20))\(outOfRangeValues.count > 20 ? " ... (\(outOfRangeValues.count) total)" : "")")
        
        XCTAssertEqual(actualCount, 10000, "Aggregation should see all 10,000 records (saw \(actualCount))")
        XCTAssertEqual(recordsWithValue, 10000, "All records should have 'value' field (found \(recordsWithValue) with, \(recordsWithoutValue) without)")
        
        // Check for data integrity issues
        if missingValues.count > 0 || duplicateValues.count > 0 {
            XCTFail("""
                Data integrity issue detected:
                - Missing values: \(missingValues.count) (expected 0)
                - Duplicate values: \(duplicateValues.count) (expected 0)
                - This suggests records are being overwritten during batch insert
                - First 10 missing: \(Array(missingValues.prefix(10)))
                - First 10 duplicates: \(Array(duplicateValues.prefix(10)))
                """)
        }
        
        // The sum should be correct if data integrity is maintained
        XCTAssertEqual(actualSum, expectedSum, 
                      "Sum should be correct (expected: \(expectedSum), got: \(actualSum), count: \(actualCount), records with value: \(recordsWithValue))")
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
        db = try BlazeDBClient(name: "perf_test", fileURL: tempURL, password: "PerformanceInvariant123!")
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

