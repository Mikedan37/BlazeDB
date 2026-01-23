//
//  QueryResultConversionTests.swift
//  BlazeDBTests
//
//  Tests for QueryResult enum type safety and conversion methods.
//  Tests accessing wrong result types, empty results, and large result sets.
//
//  Created: Phase 2 Feature Completeness Testing
//

import XCTest
@testable import BlazeDBCore

final class QueryResultConversionTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResultConv-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "ResultConvTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Type Conversion Tests
    
    /// Test accessing wrong QueryResult type throws appropriate error
    func testWrongTypeConversionThrows() throws {
        print("🔄 Testing wrong QueryResult type conversion...")
        
        // Insert test data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Execute standard query (returns .records)
        let result = try db.query().execute()
        
        XCTAssertTrue(result.isType(.records), "Should be records type")
        
        // Accessing as records should work
        XCTAssertNoThrow(try result.records, "Should get records")
        
        // Accessing as other types should throw
        XCTAssertThrowsError(try result.joined, "Should throw when accessing as joined")
        XCTAssertThrowsError(try result.aggregation, "Should throw when accessing as aggregation")
        XCTAssertThrowsError(try result.grouped, "Should throw when accessing as grouped")
        XCTAssertThrowsError(try result.searchResults, "Should throw when accessing as search")
        
        print("✅ Wrong type conversion throws correctly")
    }
    
    /// Test nil accessors return nil for wrong types
    func testNilAccessorsForWrongTypes() throws {
        print("🔄 Testing nil accessors for wrong types...")
        
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Standard query
        let recordResult = try db.query().execute()
        XCTAssertNotNil(recordResult.recordsOrNil, "recordsOrNil should return value")
        XCTAssertNil(recordResult.joinedOrNil, "joinedOrNil should return nil")
        XCTAssertNil(recordResult.aggregationOrNil, "aggregationOrNil should return nil")
        XCTAssertNil(recordResult.groupedOrNil, "groupedOrNil should return nil")
        XCTAssertNil(recordResult.searchResultsOrNil, "searchResultsOrNil should return nil")
        
        // Aggregation query
        let aggResult = try db.query().count().execute()
        XCTAssertNil(aggResult.recordsOrNil, "recordsOrNil should return nil for aggregation")
        XCTAssertNotNil(aggResult.aggregationOrNil, "aggregationOrNil should return value")
        
        print("✅ Nil accessors work correctly")
    }
    
    /// Test converting empty results
    func testEmptyResultConversion() throws {
        print("🔄 Testing empty result conversion...")
        
        // Query empty database
        let result = try db.query().execute()
        
        XCTAssertTrue(result.isType(.records), "Empty result should still be records type")
        
        let records = try result.records
        XCTAssertTrue(records.isEmpty, "Should return empty array")
        XCTAssertEqual(result.count, 0)
        
        // Aggregation on empty database
        let aggResult = try db.query().count().execute()
        let agg = try aggResult.aggregation
        XCTAssertEqual(agg.count, 0, "Count on empty DB should be 0")
        
        print("✅ Empty result conversion works correctly")
    }
    
    /// Test QueryResult.count property for all types
    func testQueryResultCountForAllTypes() throws {
        print("🔄 Testing QueryResult.count for all types...")
        
        // Insert test data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i), "category": .string("A")]))
        }
        
        // Records result
        let recordsResult = try db.query().execute()
        XCTAssertEqual(recordsResult.count, 10, "Records count should be 10")
        
        // Aggregation result
        let aggResult = try db.query().count().execute()
        XCTAssertEqual(aggResult.count, 1, "Aggregation always has count 1")
        
        // Grouped result
        let groupedResult = try db.query().groupBy("category").count().execute()
        XCTAssertEqual(groupedResult.count, 1, "Grouped result has 1 group")
        
        print("✅ QueryResult.count works for all types")
    }
    
    /// Test converting large result sets
    func testLargeResultSetConversion() throws {
        print("🔄 Testing large result set conversion...")
        
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 1000 : 100
        
        // Insert many records
        for i in 0..<count {
            _ = try db.insert(BlazeDataRecord(["index": .int(i), "group": .string("G\(i % 10)")]))
        }
        
        try db.persist()
        
        print("  Inserted \(count) records")
        
        // Convert large records result
        let startTime = Date()
        let result = try db.query().execute()
        let records = try result.records
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(records.count, count)
        print("  Converted \(count) records in \(String(format: "%.3f", duration))s")
        
        // Convert large grouped result
        let groupStart = Date()
        let groupedResult = try db.query().groupBy("group").count().execute()
        let grouped = try groupedResult.grouped
        let groupDuration = Date().timeIntervalSince(groupStart)
        
        XCTAssertEqual(grouped.groups.count, 10, "Should have 10 groups")
        print("  Converted grouped result in \(String(format: "%.3f", groupDuration))s")
        
        print("✅ Large result set conversion is efficient")
    }
}

