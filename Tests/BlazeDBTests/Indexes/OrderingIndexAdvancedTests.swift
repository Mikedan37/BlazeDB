//
//  OrderingIndexAdvancedTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for advanced ordering features:
//  - Performance optimizations (index-based sorting, caching)
//  - Relative moves (moveUp, moveDown)
//  - Bulk reordering
//  - Multiple ordering fields (per category)
//  - Telemetry and performance metrics
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class OrderingIndexAdvancedTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.db")
        do {
            db = try BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "OrderingIndexAdvanced123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        try! db.enableOrdering()
        
        // Enable telemetry for testing
        db.telemetry.enable(samplingRate: 1.0)
    }
    
    override func tearDown() {
        // Disable telemetry to prevent state leaking between tests
        if db != nil {
            db.telemetry.disable()
        }
        
        try? FileManager.default.removeItem(at: tempDir)
        db = nil
        tempDir = nil
        super.tearDown()
    }
    
    // MARK: - Performance Optimizations Tests
    
    func testIndexBasedSortingForLargeDatasets() throws {
        // Create 1500 records to trigger index-based sorting
        let records = (0..<1500).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        let ids = try db.insertMany(records)
        
        // Verify insertMany returned correct number of IDs
        print("📊 Inserted \(ids.count) records out of \(records.count) attempted")
        XCTAssertEqual(ids.count, 1500, "Should insert all 1500 records")
        
        // Verify all records were inserted with orderingIndex preserved
        var missingIndexCount = 0
        for id in ids.prefix(10) {
            if let record = try db.fetch(id: id) {
                let index = OrderingIndex.getIndex(from: record, fieldName: "orderingIndex")
                if index == nil {
                    missingIndexCount += 1
                    print("⚠️ Record \(id.uuidString.prefix(8)) missing orderingIndex")
                }
            }
        }
        XCTAssertEqual(missingIndexCount, 0, "All records should have orderingIndex after insertMany")
        
        // Query should use index-based sorting (explicitly sort by orderingIndex)
        let startTime = Date()
        let results = try db.query()
            .orderBy("orderingIndex", descending: false)
            .execute()
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(results.count, 1500, "Should return all 1500 records")
        XCTAssertLessThan(duration, 2.0, "Index-based sort should be reasonably fast")
        
        // Verify order - check more records to catch issues
        let recordList = try results.records
        print("📊 Query returned \(recordList.count) records")
        XCTAssertEqual(recordList.count, 1500, "Should have all 1500 records in result")
        
        // Check first 100 records for ordering
        var outOfOrderCount = 0
        var firstOutOfOrder: (Int, Double?, Double?)? = nil
        for i in 0..<min(100, recordList.count - 1) {
            let leftIndex = OrderingIndex.getIndex(from: recordList[i], fieldName: "orderingIndex")
            let rightIndex = OrderingIndex.getIndex(from: recordList[i + 1], fieldName: "orderingIndex")
            XCTAssertNotNil(leftIndex, "Record at index \(i) should have orderingIndex")
            XCTAssertNotNil(rightIndex, "Record at index \(i+1) should have orderingIndex")
            
            if let left = leftIndex, let right = rightIndex {
                // Allow equal values (stable sort maintains insertion order)
                if left > right {
                    outOfOrderCount += 1
                    if firstOutOfOrder == nil {
                        firstOutOfOrder = (i, left, right)
                    }
                    print("❌ Out of order at position \(i): \(left) > \(right)")
                }
            }
        }
        
        if outOfOrderCount > 0 {
            XCTFail("Found \(outOfOrderCount) out-of-order pairs. First at position \(firstOutOfOrder!.0): \(firstOutOfOrder!.1!) > \(firstOutOfOrder!.2!)")
        }
    }
    
    func testCachedSortedOrder() throws {
        // OPTIMIZATION: Use insertMany for faster batch insertion
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        _ = try db.insertMany(records)
        
        // First query (should populate cache)
        let start1 = Date()
        let results1 = try db.query().orderBy("orderingIndex", descending: false).execute()
        let duration1 = Date().timeIntervalSince(start1)
        
        // Second query (should use cache)
        let start2 = Date()
        let results2 = try db.query().orderBy("orderingIndex", descending: false).execute()
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertEqual(results1.count, results2.count)
        let records1 = try results1.records
        let records2 = try results2.records
        XCTAssertEqual(records1.map { $0.storage["id"]?.uuidValue }, records2.map { $0.storage["id"]?.uuidValue }, "Cached results should match")
        
        // Cache should be faster (or at least not slower)
        // Note: For small datasets, difference may be negligible
        XCTAssertLessThanOrEqual(duration2, duration1 * 1.5, "Cached query should be similar or faster")
    }
    
    func testCacheInvalidationOnMove() throws {
        // Insert records
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First"),
            "orderingIndex": .double(100.0)
        ]))
        let id2 = try db.insert(BlazeDataRecord([
            "title": .string("Second"),
            "orderingIndex": .double(200.0)
        ]))
        
        // Query to populate cache
        _ = try db.query().orderBy("orderingIndex", descending: false).execute()
        
        // Move record (should invalidate cache)
        try db.moveBefore(recordId: id2, beforeId: id1)
        
        // Query again (should re-sort)
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records.first?.storage["id"]?.uuidValue, id2, "Moved record should be first")
    }
    
    // MARK: - Relative Moves Tests
    
    func testMoveUp() throws {
        // Insert records with known indices
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First"),
            "orderingIndex": .double(100.0)
        ]))
        let id2 = try db.insert(BlazeDataRecord([
            "title": .string("Second"),
            "orderingIndex": .double(200.0)
        ]))
        let id3 = try db.insert(BlazeDataRecord([
            "title": .string("Third"),
            "orderingIndex": .double(300.0)
        ]))
        
        // Move id3 up 1 position
        try db.moveUp(recordId: id3, positions: 1)
        
        // Verify new index
        let record = try db.collection.fetch(id: id3)
        XCTAssertNotNil(record)
        guard let record = record else { return }
        let newIndex = OrderingIndex.getIndex(from: record, fieldName: "orderingIndex")
        XCTAssertEqual(newIndex, 299.0, "Should have moved up by 1.0")
        
        // Verify order
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        let ids = records.compactMap { $0.storage["id"]?.uuidValue }
        XCTAssertEqual(ids[0], id1)
        XCTAssertEqual(ids[1], id2)
        XCTAssertEqual(ids[2], id3, "id3 should still be last but with lower index")
    }
    
    func testMoveUpMultiplePositions() throws {
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First"),
            "orderingIndex": .double(100.0)
        ]))
        
        // Move up 5 positions
        try db.moveUp(recordId: id1, positions: 5)
        
        guard let record2 = try db.collection.fetch(id: id1) else {
            XCTFail("Record not found")
            return
        }
        let newIndex2 = OrderingIndex.getIndex(from: record2, fieldName: "orderingIndex")
        XCTAssertEqual(newIndex2, 95.0, "Should have moved up by 5.0")
    }
    
    func testMoveDown() throws {
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First"),
            "orderingIndex": .double(100.0)
        ]))
        
        // Move down 1 position
        try db.moveDown(recordId: id1, positions: 1)
        
        guard let record = try db.collection.fetch(id: id1) else {
            XCTFail("Record not found")
            return
        }
        let newIndex = OrderingIndex.getIndex(from: record, fieldName: "orderingIndex")
        XCTAssertEqual(newIndex, 101.0, "Should have moved down by 1.0")
    }
    
    func testMoveDownMultiplePositions() throws {
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First"),
            "orderingIndex": .double(100.0)
        ]))
        
        // Move down 3 positions
        try db.moveDown(recordId: id1, positions: 3)
        
        guard let record = try db.collection.fetch(id: id1) else {
            XCTFail("Record not found")
            return
        }
        let newIndex = OrderingIndex.getIndex(from: record, fieldName: "orderingIndex")
        XCTAssertEqual(newIndex, 103.0, "Should have moved down by 3.0")
    }
    
    func testMoveUpWithNilIndex() throws {
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First")
            // No orderingIndex
        ]))
        
        // Move up (should use default - positions)
        try db.moveUp(recordId: id1, positions: 1)
        
        guard let record = try db.collection.fetch(id: id1) else {
            XCTFail("Record not found")
            return
        }
        let newIndex = OrderingIndex.getIndex(from: record, fieldName: "orderingIndex")
        XCTAssertEqual(newIndex, 999.0, "Should use default (1000.0) - 1.0")
    }
    
    // MARK: - Bulk Reordering Tests
    
    func testBulkReorder() throws {
        // OPTIMIZATION: Use insertMany for faster batch insertion
        let records = (0..<10).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        let ids = try db.insertMany(records)
        
        // Bulk reorder: reverse the order
        let operations = ids.enumerated().map { (index, id) in
            BulkReorderOperation(recordId: id, newIndex: Double(9 - index) * 10.0)
        }
        
        let result = try db.bulkReorder(operations)
        
        XCTAssertEqual(result.successful, 10)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.errors.isEmpty)
        
        // Verify order is reversed
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let fetchedRecords = try results.records
        XCTAssertEqual(fetchedRecords.first?.storage["id"]?.uuidValue, ids.last, "First should be last")
        XCTAssertEqual(fetchedRecords.last?.storage["id"]?.uuidValue, ids.first, "Last should be first")
    }
    
    func testBulkReorderWithSomeFailures() throws {
        let id1 = try db.insert(BlazeDataRecord([
            "title": .string("First"),
            "orderingIndex": .double(100.0)
        ]))
        let fakeId = UUID()
        
        // Bulk reorder with one invalid ID
        let operations = [
            BulkReorderOperation(recordId: id1, newIndex: 200.0),
            BulkReorderOperation(recordId: fakeId, newIndex: 300.0)
        ]
        
        let result = try db.bulkReorder(operations)
        
        XCTAssertEqual(result.successful, 1)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.0, fakeId, "First error should be for fakeId")
    }
    
    func testBulkReorderPerformance() throws {
        // Ordering is already enabled in setUp()
        // OPTIMIZATION: Use insertMany for faster batch insertion
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        let ids = try db.insertMany(records)
        
        // Bulk reorder all
        let operations = ids.map { BulkReorderOperation(recordId: $0, newIndex: Double.random(in: 0...1000)) }
        
        let startTime = Date()
        let result = try db.bulkReorder(operations)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(result.successful, 100)
        XCTAssertLessThan(duration, 1.0, "Bulk reorder should be fast")
    }
    
    // MARK: - Multiple Ordering Fields (Category) Tests
    
    func testEnableOrderingWithCategories() throws {
        try db.enableOrderingWithCategories(categoryField: "status")
        
        XCTAssertTrue(db.collection.supportsOrdering())
        XCTAssertTrue(db.collection.supportsMultipleOrdering())
        XCTAssertEqual(db.collection.orderingCategoryField(), "status")
    }
    
    func testMoveInCategory() throws {
        try db.enableOrderingWithCategories(categoryField: "status")
        
        // Insert records in different categories
        let todo1 = try db.insert(BlazeDataRecord([
            "title": .string("Todo 1"),
            "status": .string("todo"),
            "orderingIndex_todo": .double(100.0)
        ]))
        let todo2 = try db.insert(BlazeDataRecord([
            "title": .string("Todo 2"),
            "status": .string("todo"),
            "orderingIndex_todo": .double(200.0)
        ]))
        let done1 = try db.insert(BlazeDataRecord([
            "title": .string("Done 1"),
            "status": .string("done"),
            "orderingIndex_done": .double(100.0)
        ]))
        
        // Move todo2 before todo1
        try db.moveInCategory(recordId: todo2, categoryValue: "todo", beforeId: todo1)
        
        // Verify todo ordering changed
        guard let todoRecord = try db.collection.fetch(id: todo2) else {
            XCTFail("Todo record not found")
            return
        }
        let newIndex = OrderingIndex.getIndex(from: todoRecord, categoryField: "status", categoryValue: "todo")
        XCTAssertNotNil(newIndex)
        XCTAssertLessThan(newIndex!, 100.0, "Should be before todo1")
        
        // Verify done ordering unchanged
        guard let doneRecord = try db.collection.fetch(id: done1) else {
            XCTFail("Done record not found")
            return
        }
        let doneIndex = OrderingIndex.getIndex(from: doneRecord, categoryField: "status", categoryValue: "done")
        XCTAssertEqual(doneIndex, 100.0, "Done ordering should be unchanged")
    }
    
    func testMoveInCategoryAfter() throws {
        try db.enableOrderingWithCategories(categoryField: "status")
        
        let todo1 = try db.insert(BlazeDataRecord([
            "title": .string("Todo 1"),
            "status": .string("todo"),
            "orderingIndex_todo": .double(100.0)
        ]))
        let todo2 = try db.insert(BlazeDataRecord([
            "title": .string("Todo 2"),
            "status": .string("todo"),
            "orderingIndex_todo": .double(200.0)
        ]))
        
        // Move todo1 after todo2
        try db.moveInCategory(recordId: todo1, categoryValue: "todo", afterId: todo2)
        
        guard let record = try db.collection.fetch(id: todo1) else {
            XCTFail("Record not found")
            return
        }
        let newIndex = OrderingIndex.getIndex(from: record, categoryField: "status", categoryValue: "todo")
        XCTAssertGreaterThan(newIndex!, 200.0, "Should be after todo2")
    }
    
    func testMoveInCategoryErrorWhenNotEnabled() throws {
        // Don't enable category ordering
        try db.enableOrdering()
        
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Test"),
            "status": .string("todo")
        ]))
        
        XCTAssertThrowsError(try db.moveInCategory(recordId: id, categoryValue: "todo", beforeId: id)) { error in
            if case BlazeDBError.transactionFailed(let msg, _) = error {
                XCTAssertTrue(msg.contains("enableOrderingWithCategories"), "Error message should mention enableOrderingWithCategories")
            } else {
                XCTFail("Expected transactionFailed error")
            }
        }
    }
    
    // MARK: - Telemetry Tests
    
    func testTelemetryForMoveOperations() throws {
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Test"),
            "orderingIndex": .double(100.0)
        ]))
        
        // Perform move operations
        try db.moveUp(recordId: id, positions: 1)
        try db.moveDown(recordId: id, positions: 1)
        try db.moveBefore(recordId: id, beforeId: id)
        try db.moveAfter(recordId: id, afterId: id)
        try db.moveToIndex(recordId: id, index: 500.0)
        
        // Telemetry should be recorded (sampling rate is 1.0)
        // Note: Actual telemetry verification would require querying the metrics DB
        // For now, we just verify operations complete without errors
        XCTAssertNoThrow(try db.moveUp(recordId: id, positions: 1))
    }
    
    func testTelemetryForBulkReorder() throws {
        // OPTIMIZATION: Use insertMany for faster batch insertion
        let records = (0..<10).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        let ids = try db.insertMany(records)
        
        let operations = ids.map { BulkReorderOperation(recordId: $0, newIndex: Double.random(in: 0...1000)) }
        let result = try db.bulkReorder(operations)
        
        XCTAssertEqual(result.successful, 10)
        // Telemetry should be recorded
    }
    
    // MARK: - Performance Metrics Tests
    
    func testOrderingQueryPerformance() throws {
        // OPTIMIZATION: Use insertMany for faster batch insertion
        let records = (0..<500).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        _ = try db.insertMany(records)
        
        // Query with ordering (should use standard sort for < 1000 records)
        let startTime = Date()
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(results.count, 500)
        XCTAssertLessThan(duration, 0.5, "Ordering query should be fast")
        
        // Verify order (allow equal values for stable sort)
        let fetchedRecords = try results.records
        for i in 0..<min(10, fetchedRecords.count - 1) {
            let leftIndex = OrderingIndex.getIndex(from: fetchedRecords[i], fieldName: "orderingIndex")
            let rightIndex = OrderingIndex.getIndex(from: fetchedRecords[i + 1], fieldName: "orderingIndex")
            XCTAssertNotNil(leftIndex)
            XCTAssertNotNil(rightIndex)
            if let left = leftIndex, let right = rightIndex {
                XCTAssertLessThanOrEqual(left, right, "Records should be in ascending order (equal values allowed)")
            }
        }
    }
    
    func testLargeDatasetOrderingPerformance() throws {
        // Insert 2000 records to trigger index-based sorting
        let records = (0..<2000).map { i in
            BlazeDataRecord([
                "title": .string("Record \(i)"),
                "orderingIndex": .double(Double(i) * 10.0)
            ])
        }
        let ids = try db.insertMany(records)
        
        print("📊 Inserted \(ids.count) records out of \(records.count) attempted")
        XCTAssertEqual(ids.count, 2000, "Should insert all 2000 records")
        
        let startTime = Date()
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let duration = Date().timeIntervalSince(startTime)
        
        print("📊 Query returned \(results.count) records in \(String(format: "%.2f", duration))s")
        XCTAssertEqual(results.count, 2000, "Should return all 2000 records")
        XCTAssertLessThan(duration, 3.0, "Index-based sort should handle large datasets efficiently")
        
        // Verify order (allow equal values for stable sort)
        let recordList = try results.records
        for i in 0..<min(10, recordList.count - 1) {
            let leftIndex = OrderingIndex.getIndex(from: recordList[i], fieldName: "orderingIndex")
            let rightIndex = OrderingIndex.getIndex(from: recordList[i + 1], fieldName: "orderingIndex")
            XCTAssertNotNil(leftIndex)
            XCTAssertNotNil(rightIndex)
            if let left = leftIndex, let right = rightIndex {
                XCTAssertLessThanOrEqual(left, right, "Records should be in ascending order (equal values allowed)")
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testMoveUpWithZeroPositions() throws {
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Test"),
            "orderingIndex": .double(100.0)
        ]))
        
        try db.moveUp(recordId: id, positions: 0)
        
        let record = try db.collection.fetch(id: id)!
        let index = OrderingIndex.getIndex(from: record, fieldName: "orderingIndex")
        XCTAssertEqual(index, 100.0, "Index should be unchanged")
    }
    
    func testBulkReorderEmptyArray() throws {
        let result = try db.bulkReorder([])
        
        XCTAssertEqual(result.successful, 0)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }
    
    func testCacheClearing() throws {
        // Insert and query to populate cache
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Test"),
            "orderingIndex": .double(100.0)
        ]))
        _ = try db.query().orderBy("orderingIndex", descending: false).execute()
        
        // Clear cache
        OrderingIndexCache.shared.clear()
        
        // Query should still work (just re-sort)
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteOrderingWorkflow() throws {
        // 1. Enable ordering
        try db.enableOrdering()
        XCTAssertTrue(db.isOrderingEnabled())
        
        // 2. Insert records
        let id1 = try db.insert(BlazeDataRecord(["title": .string("First")]))
        let id2 = try db.insert(BlazeDataRecord(["title": .string("Second")]))
        let id3 = try db.insert(BlazeDataRecord(["title": .string("Third")]))
        
        // 3. Query (should be ordered)
        var results = try db.query().orderBy("orderingIndex", descending: false).execute()
        XCTAssertEqual(results.count, 3)
        
        // 4. Move record
        try db.moveBefore(recordId: id3, beforeId: id1)
        
        // 5. Query again (order should change)
        results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let recordsAfterMove = try results.records
        XCTAssertEqual(recordsAfterMove.first?.storage["id"]?.uuidValue, id3, "Moved record should be first")
        
        // 6. Relative move
        try db.moveDown(recordId: id3, positions: 1)
        
        // 7. Bulk reorder
        let operations = [
            BulkReorderOperation(recordId: id1, newIndex: 1000.0),
            BulkReorderOperation(recordId: id2, newIndex: 2000.0),
            BulkReorderOperation(recordId: id3, newIndex: 3000.0)
        ]
        let result = try db.bulkReorder(operations)
        XCTAssertEqual(result.successful, 3)
        
        // 8. Final query
        results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let finalRecords = try results.records
        let finalIds = finalRecords.compactMap { $0.storage["id"]?.uuidValue }
        XCTAssertEqual(finalIds, [id1, id2, id3], "Should be in new order")
    }
}

