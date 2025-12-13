//
//  OrderingIndexTests.swift
//  BlazeDBTests
//
//  Tests for optional fractional ordering system
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class OrderingIndexTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        
        // Aggressively clean up any leftover files from previous test runs
        cleanupDatabaseFilesBeforeInit(at: dbURL)
        
        do {
            db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "OrderingIndexTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        // Clean up database instance to prevent state leaking between tests
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }
    
    // MARK: - Utility Tests
    
    func testBetweenCalculation() {
        // Test between two indices
        XCTAssertEqual(OrderingIndex.between(10.0, 20.0), 15.0)
        XCTAssertEqual(OrderingIndex.between(0.0, 1.0), 0.5)
        
        // Test with nil (before start)
        XCTAssertEqual(OrderingIndex.between(nil, 10.0), 9.0) // before(10.0)
        
        // Test with nil (after end)
        XCTAssertEqual(OrderingIndex.between(10.0, nil), 11.0) // after(10.0)
        
        // Test both nil (default)
        XCTAssertEqual(OrderingIndex.between(nil, nil), OrderingIndex.default)
    }
    
    func testBeforeCalculation() {
        XCTAssertEqual(OrderingIndex.before(10.0), 9.0)
        XCTAssertEqual(OrderingIndex.before(1.0), 0.0)
        XCTAssertEqual(OrderingIndex.before(0.5), -0.5) // Negative values allowed
        XCTAssertEqual(OrderingIndex.before(0.0), -1.0) // Can move before first item
    }
    
    func testAfterCalculation() {
        XCTAssertEqual(OrderingIndex.after(10.0), 11.0)
        XCTAssertEqual(OrderingIndex.after(0.0), 1.0)
    }
    
    // MARK: - Ordering Disabled Tests (Zero Impact)
    
    func testOrderingDisabledByDefault() {
        XCTAssertFalse(db.isOrderingEnabled(), "Ordering should be disabled by default")
    }
    
    func testQueriesWorkWithoutOrdering() {
        // Insert records without ordering
        let record1 = BlazeDataRecord(["name": .string("A")])
        let record2 = BlazeDataRecord(["name": .string("B")])
        
        try! db.insert(record1)
        try! db.insert(record2)
        
        // Query should work normally
        let results = try! db.query().execute()
        let records = try! results.records
        XCTAssertEqual(records.count, 2)
    }
    
    // MARK: - Ordering Enabled Tests
    
    func testEnableOrdering() throws {
        try db.enableOrdering()
        XCTAssertTrue(db.isOrderingEnabled(), "Ordering should be enabled")
    }
    
    func testInsertWithOrderingIndex() throws {
        try db.enableOrdering()
        
        // Insert records with ordering indices
        let record1 = BlazeDataRecord([
            "name": .string("First"),
            "orderingIndex": .double(1000.0)
        ])
        let record2 = BlazeDataRecord([
            "name": .string("Second"),
            "orderingIndex": .double(2000.0)
        ])
        
        try db.insert(record1)
        try db.insert(record2)
        
        // Query should return in order (must sort by orderingIndex)
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "First")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Second")
    }
    
    func testMoveBefore() throws {
        try db.enableOrdering()
        
        // Insert three records
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("A"),
            "orderingIndex": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("B"),
            "orderingIndex": .double(2000.0)
        ]), id: id2)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id3),
            "name": .string("C"),
            "orderingIndex": .double(3000.0)
        ]), id: id3)
        
        // Move C before B
        try db.moveBefore(recordId: id3, beforeId: id2)
        
        // Verify order: A, C, B (must sort by orderingIndex to see the new order)
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "A")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "C")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "B")
    }
    
    func testMoveAfter() throws {
        try db.enableOrdering()
        
        // Insert three records
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("A"),
            "orderingIndex": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("B"),
            "orderingIndex": .double(2000.0)
        ]), id: id2)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id3),
            "name": .string("C"),
            "orderingIndex": .double(3000.0)
        ]), id: id3)
        
        // Move A after B
        try db.moveAfter(recordId: id1, afterId: id2)
        
        // Verify order: B, A, C (must sort by orderingIndex to see the new order)
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "B")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "A")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "C")
    }
    
    func testMoveToIndex() throws {
        try db.enableOrdering()
        
        let id = UUID()
        try db.insert(BlazeDataRecord([
            "id": .uuid(id),
            "name": .string("Test")
        ]))
        
        // Set specific index
        try db.moveToIndex(recordId: id, index: 5000.0)
        
        let record = try db.fetch(id: id)
        XCTAssertEqual(OrderingIndex.getIndex(from: record!, fieldName: "orderingIndex"), 5000.0)
    }
    
    func testStabilityOverMultipleOperations() throws {
        try db.enableOrdering()
        
        // Insert 5 records
        let ids = (0..<5).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "orderingIndex": .double(Double(index) * 1000.0)
            ]), id: id)
        }
        
        // Perform multiple moves
        try db.moveBefore(recordId: ids[4], beforeId: ids[0]) // Move last to first
        try db.moveAfter(recordId: ids[1], afterId: ids[3])  // Move second to after third
        
        // Verify stability - order should be consistent
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records.count, 5)
        
        // All records should still be present
        let names = records.map { $0.storage["name"]?.stringValue ?? "" }
        XCTAssertEqual(Set(names), Set(["Item 0", "Item 1", "Item 2", "Item 3", "Item 4"]))
    }
    
    func testNilIndicesSortLast() throws {
        try db.enableOrdering()
        
        // Insert records with and without indices
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("With Index"),
            "orderingIndex": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("No Index")
        ]), id: id2)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id3),
            "name": .string("With Index 2"),
            "orderingIndex": .double(2000.0)
        ]), id: id3)
        
        // Records with nil index should sort last (must sort by orderingIndex)
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "With Index")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "With Index 2")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "No Index")
    }
    
    func testExplicitSortOverridesOrdering() throws {
        try db.enableOrdering()
        
        let id1 = UUID()
        let id2 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("B"),
            "orderingIndex": .double(2000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("A"),
            "orderingIndex": .double(1000.0)
        ]), id: id2)
        
        // Explicit sort should override ordering index
        let results = try db.query()
            .orderBy("name", descending: false)
            .execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "A")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "B")
    }
    
    // MARK: - Edge Cases
    
    func testEqualIndices() throws {
        // Test handling of equal indices
        let result = OrderingIndex.between(1000.0, 1000.0)
        XCTAssertEqual(result, 1000.1, "Equal indices should increment by 0.1")
    }
    
    func testReverseOrder() throws {
        // Test reverse order handling (shouldn't happen, but be safe)
        let result = OrderingIndex.between(2000.0, 1000.0)
        XCTAssertEqual(result, 1500.0, "Reverse order should still calculate average")
    }
    
    func testNegativeIndexAllowed() throws {
        // Test that before() allows negative values (needed for moving before first item)
        let result = OrderingIndex.before(0.5)
        XCTAssertEqual(result, -0.5, "Negative values should be allowed")
        
        let resultBeforeZero = OrderingIndex.before(0.0)
        XCTAssertEqual(resultBeforeZero, -1.0, "Can move before index 0.0")
    }
    
    func testGetIndexWithIntField() throws {
        // Test extracting index from int field
        let record = BlazeDataRecord([
            "orderingIndex": .int(1000)
        ])
        let index = OrderingIndex.getIndex(from: record)
        XCTAssertEqual(index, 1000.0, "Should convert int to double")
    }
    
    func testGetIndexWithUnsupportedType() throws {
        // Test extracting index from unsupported type
        let record = BlazeDataRecord([
            "orderingIndex": .string("invalid")
        ])
        let index = OrderingIndex.getIndex(from: record)
        XCTAssertNil(index, "Should return nil for unsupported types")
    }
    
    // MARK: - Error Handling
    
    func testMoveBeforeWithoutOrdering() throws {
        let id1 = UUID()
        let id2 = UUID()
        
        try db.insert(BlazeDataRecord(["id": .uuid(id1), "name": .string("A")]), id: id1)
        try db.insert(BlazeDataRecord(["id": .uuid(id2), "name": .string("B")]), id: id2)
        
        // Should throw error when ordering not enabled
        XCTAssertThrowsError(try db.moveBefore(recordId: id1, beforeId: id2)) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
    }
    
    func testMoveAfterWithoutOrdering() throws {
        let id1 = UUID()
        let id2 = UUID()
        
        try db.insert(BlazeDataRecord(["id": .uuid(id1), "name": .string("A")]), id: id1)
        try db.insert(BlazeDataRecord(["id": .uuid(id2), "name": .string("B")]), id: id2)
        
        // Should throw error when ordering not enabled
        XCTAssertThrowsError(try db.moveAfter(recordId: id1, afterId: id2)) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
    }
    
    func testMoveToIndexWithoutOrdering() throws {
        let id = UUID()
        try db.insert(BlazeDataRecord(["id": .uuid(id), "name": .string("A")]), id: id)
        
        // Should throw error when ordering not enabled
        XCTAssertThrowsError(try db.moveToIndex(recordId: id, index: 1000.0)) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
    }
    
    func testMoveBeforeWithNonExistentRecord() throws {
        try db.enableOrdering()
        
        let id1 = UUID()
        let id2 = UUID()
        
        try db.insert(BlazeDataRecord(["id": .uuid(id1), "name": .string("A")]), id: id1)
        
        // Should throw error when target record doesn't exist
        XCTAssertThrowsError(try db.moveBefore(recordId: id1, beforeId: id2)) { error in
            if case BlazeDBError.recordNotFound(let id, _, _) = error {
                XCTAssertEqual(id, id2)
            } else {
                XCTFail("Expected recordNotFound error")
            }
        }
    }
    
    func testMoveAfterWithNonExistentRecord() throws {
        try db.enableOrdering()
        
        let id1 = UUID()
        let id2 = UUID()
        
        try db.insert(BlazeDataRecord(["id": .uuid(id1), "name": .string("A")]), id: id1)
        
        // Should throw error when target record doesn't exist
        XCTAssertThrowsError(try db.moveAfter(recordId: id1, afterId: id2)) { error in
            if case BlazeDBError.recordNotFound(let id, _, _) = error {
                XCTAssertEqual(id, id2)
            } else {
                XCTFail("Expected recordNotFound error")
            }
        }
    }
    
    // MARK: - Custom Field Name
    
    func testCustomFieldName() throws {
        try db.enableOrdering(fieldName: "position")
        
        let id1 = UUID()
        let id2 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("First"),
            "position": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("Second"),
            "position": .double(2000.0)
        ]), id: id2)
        
        // Query should use custom field name (must sort by "position" to see ordering)
        let results = try db.query().orderBy("position", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "First")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Second")
    }
    
    // MARK: - Large Dataset Performance
    
    func testLargeDatasetOrdering() throws {
        try db.enableOrdering()
        
        // Insert 100 records
        let ids = (0..<100).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "orderingIndex": .double(Double(index) * 1000.0)
            ]), id: id)
        }
        
        // Move last item to first
        try db.moveBefore(recordId: ids[99], beforeId: ids[0])
        
        // Verify order
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records.count, 100)
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "Item 99")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Item 0")
    }
    
    // MARK: - Multiple Sequential Moves
    
    func testMultipleSequentialMoves() throws {
        try db.enableOrdering()
        
        // Insert 5 records
        let ids = (0..<5).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "orderingIndex": .double(Double(index) * 1000.0)
            ]), id: id)
        }
        
        // Perform multiple moves
        try db.moveBefore(recordId: ids[4], beforeId: ids[0]) // 4 -> before 0
        try db.moveAfter(recordId: ids[1], afterId: ids[3])   // 1 -> after 3
        try db.moveBefore(recordId: ids[2], beforeId: ids[1]) // 2 -> before 1 (which is now after 3)
        
        // Verify final order
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records.count, 5)
        
        // Expected order: 4, 0, 3, 2, 1
        let names = records.map { $0.storage["name"]?.stringValue ?? "" }
        XCTAssertEqual(names[0], "Item 4")
        XCTAssertEqual(names[1], "Item 0")
        XCTAssertEqual(names[2], "Item 3")
        XCTAssertEqual(names[3], "Item 2")
        XCTAssertEqual(names[4], "Item 1")
    }
    
    // MARK: - Boundary Conditions
    
    func testMoveToFirstPosition() throws {
        try db.enableOrdering()
        
        let ids = (0..<3).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "orderingIndex": .double(Double(index + 1) * 1000.0)
            ]), id: id)
        }
        
        // Move last to first
        try db.moveBefore(recordId: ids[2], beforeId: ids[0])
        
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "Item 2")
    }
    
    func testMoveToLastPosition() throws {
        try db.enableOrdering()
        
        let ids = (0..<3).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "orderingIndex": .double(Double(index + 1) * 1000.0)
            ]), id: id)
        }
        
        // Move first to last
        try db.moveAfter(recordId: ids[0], afterId: ids[2])
        
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "Item 0")
    }
    
    // MARK: - Fractional Index Precision
    
    func testFractionalIndexPrecision() throws {
        try db.enableOrdering()
        
        // Insert records with close indices
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("A"),
            "orderingIndex": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("B"),
            "orderingIndex": .double(1000.1)
        ]), id: id2)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id3),
            "name": .string("C"),
            "orderingIndex": .double(1000.2)
        ]), id: id3)
        
        // Move C between A and B
        try db.moveBefore(recordId: id3, beforeId: id2)
        
        // Verify order is maintained
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "A")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "C")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "B")
    }
    
    // MARK: - Query Integration
    
    func testQueryWithFiltersAndOrdering() throws {
        try db.enableOrdering()
        
        let ids = (0..<5).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "category": .string(index % 2 == 0 ? "A" : "B"),
                "orderingIndex": .double(Double(index) * 1000.0)
            ]), id: id)
        }
        
        // Query with filter, should still use ordering (must explicitly sort)
        let results = try db.query()
            .where("category", equals: .string("A"))
            .orderBy("orderingIndex", descending: false)
            .execute()
        let records = try results.records
        
        // Should return items 0, 2, 4 in order
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "Item 0")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Item 2")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "Item 4")
    }
    
    func testQueryWithLimitAndOrdering() throws {
        try db.enableOrdering()
        
        let ids = (0..<10).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "name": .string("Item \(index)"),
                "orderingIndex": .double(Double(index) * 1000.0)
            ]), id: id)
        }
        
        // Query with limit, should respect ordering (must explicitly sort)
        let results = try db.query()
            .limit(3)
            .orderBy("orderingIndex", descending: false)
            .execute()
        let records = try results.records
        
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "Item 0")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Item 1")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "Item 2")
    }
    
    // MARK: - Persistence Tests
    
    func testOrderingPersistsAcrossSessions() throws {
        try db.enableOrdering()
        
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("First"),
            "orderingIndex": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("Second"),
            "orderingIndex": .double(2000.0)
        ]), id: id2)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id3),
            "name": .string("Third"),
            "orderingIndex": .double(3000.0)
        ]), id: id3)
        
        // Explicitly persist to ensure data is saved before reopening
        try db.persist()
        
        // Reopen database
        let db2URL = tempDir.appendingPathComponent("test.blazedb")
        let db2 = try BlazeDBClient(name: "test", fileURL: db2URL, password: "OrderingIndexTest123!")
        
        // Ordering should still be enabled
        XCTAssertTrue(db2.isOrderingEnabled())
        
        // Query should maintain order
        let results = try db2.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "First")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Second")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "Third")
    }
    
    // MARK: - Comprehensive Integration Tests
    
    func testCompleteOrderingWorkflow() throws {
        // Test complete workflow: enable, insert, move, query
        try db.enableOrdering()
        XCTAssertTrue(db.isOrderingEnabled())
        
        // Insert initial records
        let ids = (0..<10).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try db.insert(BlazeDataRecord([
            "id": .uuid(id),
                "title": .string("Task \(index)"),
                "orderingIndex": .double(Double(index) * 1000.0)
            ]), id: id)
        }
        
        // Verify initial order and indices
        var results = try db.query().orderBy("orderingIndex", descending: false).execute()
        var records = try results.records
        XCTAssertEqual(records[0].storage["title"]?.stringValue, "Task 0")
        XCTAssertEqual(records[9].storage["title"]?.stringValue, "Task 9")
        
        // Verify initial indices are set correctly
        let task9Before = try db.fetch(id: ids[9])
        let task0Before = try db.fetch(id: ids[0])
        let task9IndexBefore = OrderingIndex.getIndex(from: task9Before!, fieldName: "orderingIndex")
        let task0IndexBefore = OrderingIndex.getIndex(from: task0Before!, fieldName: "orderingIndex")
        print("📊 Before move - Task 0 index: \(task0IndexBefore ?? -1), Task 9 index: \(task9IndexBefore ?? -1)")
        XCTAssertEqual(task0IndexBefore, 0.0, "Task 0 should have initial index 0.0")
        XCTAssertEqual(task9IndexBefore, 9000.0, "Task 9 should have initial index 9000.0")
        
        // Test move operation - move Task 9 before Task 0
        try db.moveBefore(recordId: ids[9], beforeId: ids[0])
        
        // Verify Task 9 has a lower orderingIndex than Task 0 after the move
        let task9 = try db.fetch(id: ids[9])
        let task0 = try db.fetch(id: ids[0])
        let task9Index = OrderingIndex.getIndex(from: task9!, fieldName: "orderingIndex")
        let task0Index = OrderingIndex.getIndex(from: task0!, fieldName: "orderingIndex")
        print("📊 After move - Task 0 index: \(task0Index ?? -1), Task 9 index: \(task9Index ?? -1)")
        XCTAssertNotNil(task9Index)
        XCTAssertNotNil(task0Index)
        if let idx9 = task9Index, let idx0 = task0Index {
            XCTAssertLessThan(idx9, idx0, "Task 9 should have lower orderingIndex than Task 0 after moveBefore")
        }
        
        // Query and verify Task 9 appears before Task 0 in sorted results
        results = try db.query().orderBy("orderingIndex", descending: false).execute()
        records = try results.records
        let task9Pos = records.firstIndex { $0.storage["title"]?.stringValue == "Task 9" }
        let task0Pos = records.firstIndex { $0.storage["title"]?.stringValue == "Task 0" }
        XCTAssertNotNil(task9Pos)
        XCTAssertNotNil(task0Pos)
        if let pos9 = task9Pos, let pos0 = task0Pos {
            XCTAssertLessThan(pos9, pos0, "Task 9 should appear before Task 0 in sorted results")
        }
    }
    
    func testOrderingWithMixedNilAndNonNil() throws {
        try db.enableOrdering()
        
        // Insert mix of records with and without indices
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()
        
        try db.insert(BlazeDataRecord([
            "id": .uuid(id1),
            "name": .string("Indexed 1"),
            "orderingIndex": .double(1000.0)
        ]), id: id1)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id2),
            "name": .string("No Index")
        ]), id: id2)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id3),
            "name": .string("Indexed 2"),
            "orderingIndex": .double(2000.0)
        ]), id: id3)
        try db.insert(BlazeDataRecord([
            "id": .uuid(id4),
            "name": .string("No Index 2")
        ]), id: id4)
        
        // Query should sort: indexed records first, then nil records
        let results = try db.query().orderBy("orderingIndex", descending: false).execute()
        let records = try results.records
        
        let indexedCount = records.prefix(2).filter { record in
            OrderingIndex.getIndex(from: record) != nil
        }.count
        XCTAssertEqual(indexedCount, 2, "Indexed records should come first")
        
        let nilCount = records.suffix(2).filter { record in
            OrderingIndex.getIndex(from: record) == nil
        }.count
        XCTAssertEqual(nilCount, 2, "Nil records should come last")
    }
    
    func testSetIndexDirectly() throws {
        try db.enableOrdering()
        
        let id = UUID()
        try db.insert(BlazeDataRecord([
            "id": .uuid(id),
            "name": .string("Test")
        ]), id: id)
        
        // Set index directly
        try db.moveToIndex(recordId: id, index: 5000.0)
        
        let record = try db.fetch(id: id)
        let index = OrderingIndex.getIndex(from: record!)
        XCTAssertEqual(index, 5000.0)
    }
    
    func testOrderingIndexExtractionEdgeCases() throws {
        // Test getIndex with various field types
        let record1 = BlazeDataRecord([
            "orderingIndex": .int(42)
        ])
        XCTAssertEqual(OrderingIndex.getIndex(from: record1), 42.0)
        
        let record2 = BlazeDataRecord([
            "orderingIndex": .double(42.5)
        ])
        XCTAssertEqual(OrderingIndex.getIndex(from: record2), 42.5)
        
        let record3 = BlazeDataRecord([
            "orderingIndex": .string("not a number")
        ])
        XCTAssertNil(OrderingIndex.getIndex(from: record3))
        
        let record4 = BlazeDataRecord([:])
        XCTAssertNil(OrderingIndex.getIndex(from: record4))
    }
    
    func testOrderingIndexCalculationEdgeCases() throws {
        // Test edge cases in index calculation
        XCTAssertEqual(OrderingIndex.between(0.0, 0.0), 0.1) // Equal values
        XCTAssertEqual(OrderingIndex.between(1000.0, 1000.0), 1000.1) // Equal values
        XCTAssertEqual(OrderingIndex.between(1.0, 2.0), 1.5) // Normal case
        XCTAssertEqual(OrderingIndex.between(2.0, 1.0), 1.5) // Reverse order
        XCTAssertEqual(OrderingIndex.between(nil, nil), OrderingIndex.default) // Both nil
        XCTAssertEqual(OrderingIndex.before(0.0), -1.0) // Negative values allowed
        XCTAssertEqual(OrderingIndex.before(1.0), 0.0) // Normal
        XCTAssertEqual(OrderingIndex.before(2.0), 1.0) // Normal
    }
}

