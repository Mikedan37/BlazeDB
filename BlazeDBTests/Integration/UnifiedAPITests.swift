//
//  UnifiedAPITests.swift
//  BlazeDBTests
//
//  Comprehensive tests for the unified QueryResult API.
//  Tests that the smart execute() method correctly auto-detects query types
//  and returns the appropriate QueryResult variant.
//

import XCTest
@testable import BlazeDBCore

final class UnifiedAPITests: XCTestCase {
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        
        // Small delay and clear cache
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UA-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        db = try! BlazeDBClient(name: "unified_test_\(testID)", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        try? db?.persist()
        db = nil
        
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Standard Query Tests
    
    func testStandardQuery_ReturnsRecordsResult() throws {
        // Insert test data
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "status": .string("open")
        ]))
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "status": .string("closed")
        ]))
        
        // Execute unified query
        let result = try db.query()
            .where("status", equals: .string("open"))
            .execute()
        
        // Verify it's a records result
        XCTAssertTrue(result.isType(.records), "Should detect as records query")
        XCTAssertEqual(result.resultType, "records")
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.isEmpty)
        
        // Extract records
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].storage["title"]?.stringValue, "Bug 1")
        
        // Verify nil accessors
        XCTAssertNil(result.joinedOrNil)
        XCTAssertNil(result.aggregationOrNil)
    }
    
    func testEmptyQuery_ReturnsEmptyRecordsResult() throws {
        let result = try db.query()
            .where("nonexistent", equals: .string("value"))
            .execute()
        
        XCTAssertTrue(result.isType(.records))
        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.isEmpty)
        
        let records = try result.records
        XCTAssertEqual(records.count, 0)
    }
    
    // MARK: - JOIN Query Tests
    
    func testJoinQuery_ReturnsJoinedResult() throws {
        // Create second collection
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123")
        
        // Insert users
        let userId1 = UUID()
        let userId2 = UUID()
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userId1),
            "name": .string("Alice")
        ]))
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userId2),
            "name": .string("Bob")
        ]))
        
        // Insert bugs
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "authorId": .uuid(userId1)
        ]))
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "authorId": .uuid(userId2)
        ]))
        
        // Execute unified JOIN query
        let result = try db.query()
            .join(usersDB.collection, on: "authorId")
            .execute()
        
        // Verify it's a joined result
        XCTAssertTrue(result.isType(.joined), "Should detect as JOIN query")
        XCTAssertEqual(result.resultType, "joined")
        XCTAssertEqual(result.count, 2)
        
        // Extract joined records
        let joined = try result.joined
        XCTAssertEqual(joined.count, 2)
        
        // Verify join worked
        for record in joined {
            XCTAssertNotNil(record.left["title"])
            XCTAssertNotNil(record.right?["name"])
        }
        
        // Verify nil accessors
        XCTAssertNil(result.recordsOrNil)
        XCTAssertNil(result.aggregationOrNil)
    }
    
    func testJoinQuery_CanFlattenToRecords() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users2-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users2", fileURL: usersURL, password: "test-pass-123")
        
        let userId = UUID()
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userId),
            "name": .string("Alice")
        ]))
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "authorId": .uuid(userId)
        ]))
        
        // Execute JOIN
        let result = try db.query()
            .join(usersDB.collection, on: "authorId")
            .execute()
        
        // Flatten to records (takes left side)
        let records = try result.flattenJoined()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["title"]?.stringValue, "Bug 1")
    }
    
    // MARK: - Aggregation Query Tests
    
    func testAggregationQuery_ReturnsAggregationResult() throws {
        // Insert test data
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(20)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(30)]))
        
        // Execute aggregation query with explicit alias
        let result = try db.query()
            .sum("value", as: "total")
            .execute()
        
        // Verify it's an aggregation result
        XCTAssertTrue(result.isType(.aggregation))
        XCTAssertEqual(result.resultType, "aggregation")
        XCTAssertEqual(result.count, 1) // Aggregations have count 1
        
        // Extract aggregation
        let agg = try result.aggregation
        XCTAssertEqual(agg.sum("total") ?? 0, 60, "Sum should be 60")
        
        // Verify nil accessors
        XCTAssertNil(result.recordsOrNil)
        XCTAssertNil(result.joinedOrNil)
    }
    
    func testCountAggregation() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed")]))
        
        let result = try db.query()
            .where("status", equals: .string("open"))
            .count()
            .execute()
        
        XCTAssertTrue(result.isType(.aggregation))
        let agg = try result.aggregation
        XCTAssertEqual(agg.count, 2)
    }
    
    // MARK: - Grouped Aggregation Tests
    
    func testGroupedAggregation_ReturnsGroupedResult() throws {
        // Insert test data
        _ = try db.insert(BlazeDataRecord(["category": .string("A"), "value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["category": .string("A"), "value": .int(20)]))
        _ = try db.insert(BlazeDataRecord(["category": .string("B"), "value": .int(30)]))
        
        // Execute grouped aggregation with explicit alias
        let result = try db.query()
            .groupBy("category")
            .sum("value", as: "total")
            .execute()
        
        // Verify it's a grouped result
        XCTAssertTrue(result.isType(.grouped))
        XCTAssertEqual(result.resultType, "grouped")
        XCTAssertEqual(result.count, 2) // Two groups
        
        // Extract grouped data
        let grouped = try result.grouped
        XCTAssertEqual(grouped.groups.count, 2)
        
        // Verify group totals
        XCTAssertEqual(grouped.groups["A"]?["total"]?.doubleValue ?? 0, 30, "Category A should sum to 30")
        XCTAssertEqual(grouped.groups["B"]?["total"]?.doubleValue ?? 0, 30, "Category B should sum to 30")
        
        // Verify nil accessors
        XCTAssertNil(result.recordsOrNil)
        XCTAssertNil(result.aggregationOrNil)
    }
    
    // MARK: - Error Handling Tests
    
    func testAccessingWrongType_ThrowsError() throws {
        let result = try db.query().execute()
        
        // This is a records result, so accessing joined should throw
        XCTAssertThrowsError(try result.joined) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
        
        XCTAssertThrowsError(try result.aggregation) { error in
            XCTAssertTrue(error is BlazeDBError)
        }
    }
    
    func testOrNilAccessors() throws {
        let result = try db.query().execute()
        
        // Records result should have recordsOrNil
        XCTAssertNotNil(result.recordsOrNil)
        XCTAssertNil(result.joinedOrNil)
        XCTAssertNil(result.aggregationOrNil)
        XCTAssertNil(result.groupedOrNil)
    }
    
    // MARK: - Query Type Detection Tests
    
    func testIsTypeMethod() throws {
        // Standard query
        let standard = try db.query().execute()
        XCTAssertTrue(standard.isType(.records))
        XCTAssertFalse(standard.isType(.joined))
        XCTAssertFalse(standard.isType(.aggregation))
        XCTAssertFalse(standard.isType(.grouped))
    }
    
    func testResultTypeString() throws {
        let result = try db.query().execute()
        XCTAssertEqual(result.resultType, "records")
    }
}

