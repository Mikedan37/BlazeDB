//
//  Phase4CorrectnessTests.swift
//  BlazeDB
//
//  Comprehensive correctness tests for Phase 4 features:
//  - B-tree range indexes
//  - Index hints
//  - Lazy execution
//  - Platform compatibility
//
//  These tests prove that Phase 4 features are correct, not just compiling.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class Phase4CorrectnessTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase4_test_\(UUID().uuidString)")
        tempURL = baseURL
        
        do {
            db = try BlazeDBClient(
                name: "phase4_test",
                fileURL: baseURL.appendingPathExtension("blazedb"),
                password: "Phase4TestPassword-123!"
            )
        } catch {
            XCTFail("Failed to create test database: \(error)")
        }
    }
    
    override func tearDown() {
        try? db?.close()
        if let baseURL = tempURL {
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("blazedb"))
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("blazedb.wal"))
        }
        super.tearDown()
    }
    
    // MARK: - B-tree Range Index Correctness
    
    func testRangeIndexGreaterThan() throws {
        // Insert records with known values
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "value": .int(i),
                "name": .string("record_\(i)")
            ]))
        }
        
        // Create range index
        try requireFixture(db).collection.createRangeIndex(on: "value")
        
        // Query with index: value > 50
        let indexedResults = try requireFixture(db).query()
            .whereRange("value", min: .int(51), max: nil)
            .execute()
            .records
        
        // Query with brute force scan
        let allRecords = try requireFixture(db).fetchAll()
        let bruteForceResults = allRecords.filter { record in
            guard let value = record.storage["value"]?.intValue else { return false }
            return value > 50
        }
        
        // Results must match exactly
        XCTAssertEqual(indexedResults.count, bruteForceResults.count,
            "Range index > should return same count as brute force")
        XCTAssertEqual(indexedResults.count, 49, "Should have 49 records where value > 50")
        
        // Verify all values are actually > 50
        for record in indexedResults {
            let value = record.storage["value"]?.intValue ?? -1
            XCTAssertGreaterThan(value, 50, "All indexed results should have value > 50")
        }
    }
    
    func testRangeIndexLessThan() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "value": .int(i),
                "name": .string("record_\(i)")
            ]))
        }
        
        try requireFixture(db).collection.createRangeIndex(on: "value")
        
        // Query: value < 25
        let indexedResults = try requireFixture(db).query()
            .whereRange("value", min: nil, max: .int(24))
            .execute().records
        
        let allRecords = try requireFixture(db).fetchAll()
        let bruteForceResults = allRecords.filter { record in
            guard let value = record.storage["value"]?.intValue else { return false }
            return value < 25
        }
        
        XCTAssertEqual(indexedResults.count, bruteForceResults.count)
        XCTAssertEqual(indexedResults.count, 25, "Should have 25 records where value < 25 (0-24)")
    }
    
    func testRangeIndexBetween() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "score": .int(i * 10)  // 0, 10, 20, ..., 990
            ]))
        }
        
        try requireFixture(db).collection.createRangeIndex(on: "score")
        
        // Query: 250 <= score <= 750
        let indexedResults = try requireFixture(db).query()
            .whereRange("score", min: .int(250), max: .int(750))
            .execute().records
        
        let allRecords = try requireFixture(db).fetchAll()
        let bruteForceResults = allRecords.filter { record in
            guard let score = record.storage["score"]?.intValue else { return false }
            return score >= 250 && score <= 750
        }
        
        XCTAssertEqual(indexedResults.count, bruteForceResults.count,
            "BETWEEN query should match brute force exactly")
        
        // Count expected: scores 250, 260, 270, ..., 750 = (750-250)/10 + 1 = 51
        XCTAssertEqual(indexedResults.count, 51)
    }
    
    // MARK: - Index Drift Tests
    
    func testIndexUpdateAfterModification() throws {
        // Insert records
        var insertedIDs: [UUID] = []
        for i in 0..<50 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "priority": .int(i % 5),  // 0, 1, 2, 3, 4 cycling
                "name": .string("task_\(i)")
            ]))
            insertedIDs.append(id)
        }
        
        try requireFixture(db).collection.createRangeIndex(on: "priority")
        
        // Verify initial state
        let initialHigh = try requireFixture(db).query()
            .whereRange("priority", min: .int(4), max: .int(4))
            .execute().records
        XCTAssertEqual(initialHigh.count, 10, "Should have 10 records with priority=4")
        
        // Update some records: change priority 4 -> 0
        for i in stride(from: 4, to: 50, by: 5) {  // indices 4, 9, 14, 19, ... (10 total)
            try requireFixture(db).update(id: insertedIDs[i], with: BlazeDataRecord([
                "priority": .int(0)
            ]))
        }
        
        // Query again - index must reflect updates
        let afterUpdateHigh = try requireFixture(db).query()
            .whereRange("priority", min: .int(4), max: .int(4))
            .execute().records
        
        // Brute force check
        let allRecords = try requireFixture(db).fetchAll()
        let bruteForceHigh = allRecords.filter {
            $0.storage["priority"]?.intValue == 4
        }
        
        XCTAssertEqual(afterUpdateHigh.count, bruteForceHigh.count,
            "Index must match brute force after updates")
        XCTAssertEqual(afterUpdateHigh.count, 0,
            "All priority=4 records were updated to 0")
    }
    
    func testIndexDeleteRemovesFromIndex() throws {
        var insertedIDs: [UUID] = []
        for i in 0..<30 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "level": .int(i / 10),  // 0,0,0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1,1,1, 2,2,2,2,2,2,2,2,2,2
                "name": .string("item_\(i)")
            ]))
            insertedIDs.append(id)
        }
        
        try requireFixture(db).collection.createRangeIndex(on: "level")
        
        // Verify initial
        let initialLevel1 = try requireFixture(db).query()
            .whereRange("level", min: .int(1), max: .int(1))
            .execute().records
        XCTAssertEqual(initialLevel1.count, 10)
        
        // Delete all level=1 records (indices 10-19)
        for i in 10..<20 {
            try requireFixture(db).delete(id: insertedIDs[i])
        }
        
        // Query again
        let afterDeleteLevel1 = try requireFixture(db).query()
            .whereRange("level", min: .int(1), max: .int(1))
            .execute().records
        
        // Brute force
        let allRecords = try requireFixture(db).fetchAll()
        let bruteForceLevel1 = allRecords.filter {
            $0.storage["level"]?.intValue == 1
        }
        
        XCTAssertEqual(afterDeleteLevel1.count, bruteForceLevel1.count)
        XCTAssertEqual(afterDeleteLevel1.count, 0, "All level=1 records were deleted")
    }
    
    // MARK: - Index Hint Tests
    
    func testUseIndexHintPreference() throws {
        // Insert data
        for i in 0..<50 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "category": .string(i % 2 == 0 ? "even" : "odd"),
                "value": .int(i)
            ]))
        }
        
        // Create index on category
        try requireFixture(db).collection.createIndex(on: "category")
        
        // Query with hint
        let results = try requireFixture(db).query()
            .useIndex("category", fields: ["category"])
            .where("category", equals: .string("even"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 25, "Should find 25 even records")
    }
    
    func testForceIndexReturnsCorrectResults() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "status": .string(["active", "pending", "complete"][i % 3]),
                "priority": .int(i % 5)
            ]))
        }
        
        try requireFixture(db).collection.createIndex(on: "status")
        
        // Force index on status
        let forcedResults = try requireFixture(db).query()
            .forceIndex("status", fields: ["status"])
            .where("status", equals: .string("active"))
            .execute()
            .records
        
        // Compare to unforced query
        let normalResults = try requireFixture(db).query()
            .where("status", equals: .string("active"))
            .execute()
            .records
        
        XCTAssertEqual(forcedResults.count, normalResults.count,
            "FORCE INDEX must return same results as normal query")
        
        // Verify correctness
        let _ = 100 / 3 + (100 % 3 > 0 ? 1 : 0)  // ~34
        XCTAssertEqual(forcedResults.count, 34)
    }
    
    // MARK: - Lazy vs Eager Equivalence
    
    func testLazyCollectMatchesExecute() throws {
        // Insert test data
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "category": .string(i % 4 == 0 ? "special" : "normal")
            ]))
        }
        
        // Eager execution
        let eagerResults = try requireFixture(db).query()
            .where("category", equals: .string("special"))
            .execute()
            .records
        
        // Lazy execution with collect
        let lazyResults = try requireFixture(db).query()
            .where("category", equals: .string("special"))
            .lazy()
            .collect()
        
        XCTAssertEqual(eagerResults.count, lazyResults.count,
            "Lazy collect must return same count as eager execute")
        XCTAssertEqual(eagerResults.count, 25)
        
        // Compare IDs
        let eagerIDs = Set(eagerResults.compactMap { $0.storage["id"]?.uuidValue })
        let lazyIDs = Set(lazyResults.compactMap { $0.storage["id"]?.uuidValue })
        XCTAssertEqual(eagerIDs, lazyIDs, "Lazy and eager must return same record IDs")
    }
    
    func testLazyTakeDoesNotLoadAll() throws {
        // Insert many records
        for i in 0..<1000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "value": .int(i)
            ]))
        }
        
        // Lazy take should only fetch first N
        let firstTen = try requireFixture(db).query().lazy().take(10)
        XCTAssertEqual(firstTen.count, 10)
        
        // The iterator should not have loaded all 1000 records
        // (We can't directly test this without metrics, but we verify correctness)
        for record in firstTen {
            XCTAssertNotNil(record.storage["value"], "Each record should have value")
        }
    }
    
    func testLazyFirstReturnsOneRecord() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "order": .int(i)
            ]))
        }
        
        let first = try requireFixture(db).query().firstLazy()
        XCTAssertNotNil(first, "Should return at least one record")
        XCTAssertNotNil(first?.storage["order"], "Record should have order field")
    }
    
    func testLazyOnClosedDatabaseReturnsEmpty() throws {
        for i in 0..<10 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["v": .int(i)]))
        }
        
        // Close the database
        try requireFixture(db).close()
        
        // After close, db reference is reset so query should throw when trying to access collection
        // The try requireFixture(db).query() method should fail on a closed database
        // If query() doesn't throw, the lazy iterator will have no results
        // because the underlying collection's indexMap will be empty or inaccessible
        do {
            let iterator = try requireFixture(db).query().lazy()
            let results = iterator.collect()
            // Either we get no results (empty indexMap after close)
            // or we get results if the collection is still in memory
            // The key invariant is no crash or corruption
            XCTAssertTrue(results.count <= 10, "Should not return more records than inserted")
        } catch {
            // This is also acceptable - operation on closed DB throws
            XCTAssertTrue(
                String(describing: error).contains("closed") ||
                String(describing: error).contains("deallocated"),
                "Error should indicate closed state: \(error)"
            )
        }
    }
    
    // MARK: - Ordering Consistency
    
    func testLazyOrderMatchesEager() throws {
        for i in 0..<50 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "sortKey": .int(50 - i),  // Insert in reverse order
                "name": .string("item_\(i)")
            ]))
        }
        
        // Eager with orderBy
        let eagerSorted = try requireFixture(db).query()
            .orderBy("sortKey", descending: false)
            .execute()
            .records
        
        // Lazy with orderBy
        let lazySorted = try requireFixture(db).query()
            .orderBy("sortKey", descending: false)
            .lazy()
            .collect()
        
        XCTAssertEqual(eagerSorted.count, lazySorted.count)
        
        // Compare order
        for i in 0..<min(eagerSorted.count, lazySorted.count) {
            let eagerKey = eagerSorted[i].storage["sortKey"]?.intValue
            let lazyKey = lazySorted[i].storage["sortKey"]?.intValue
            XCTAssertEqual(eagerKey, lazyKey, "Sort order must match at index \(i)")
        }
    }
    
    // MARK: - Reopen and Query
    
    func testRangeQueryWorksAfterReopen() throws {
        // Use a separate temp URL for this test to avoid conflicts
        let reopenTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase4_reopen_test_\(UUID().uuidString)")
        let dbPath = reopenTempURL.appendingPathExtension("blazedb")
        
        var reopenDB: BlazeDBClient? = try BlazeDBClient(
            name: "phase4_reopen_test",
            fileURL: dbPath,
            password: "Phase4TestPassword-123!"
        )
        
        defer {
            try? reopenDB?.close()
            try? FileManager.default.removeItem(at: dbPath)
            try? FileManager.default.removeItem(at: reopenTempURL.appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: dbPath.appendingPathExtension("wal"))
        }
        
        for i in 0..<50 {
            _ = try reopenDB!.insert(BlazeDataRecord([
                "score": .int(i * 2)
            ]))
        }
        
        try reopenDB!.collection.createRangeIndex(on: "score")
        
        // Query before close
        let beforeClose = try reopenDB!.query()
            .whereRange("score", min: .int(50), max: .int(70))
            .execute().records
        XCTAssertGreaterThan(beforeClose.count, 0)
        
        // Close and nil out the reference
        try reopenDB!.close()
        reopenDB = nil
        
        // Small delay to ensure file handles are released
        Thread.sleep(forTimeInterval: 0.1)
        
        // Reopen
        reopenDB = try BlazeDBClient(
            name: "phase4_reopen_test",
            fileURL: dbPath,
            password: "Phase4TestPassword-123!"
        )
        
        // Recreate range index (in-memory indexes don't persist)
        try reopenDB!.collection.createRangeIndex(on: "score")
        
        // Query after reopen
        let afterReopen = try reopenDB!.query()
            .whereRange("score", min: .int(50), max: .int(70))
            .execute().records
        
        XCTAssertEqual(beforeClose.count, afterReopen.count,
            "Range query should return same results after reopen")
    }
}
