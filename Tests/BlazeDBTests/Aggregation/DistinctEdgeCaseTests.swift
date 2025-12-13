//
//  DistinctEdgeCaseTests.swift
//  BlazeDBTests
//
//  Edge case tests for distinct() operations.
//  Tests high cardinality, performance, indexed vs non-indexed fields.
//
//  Created: Phase 3 Robustness Testing
//

import XCTest
@testable import BlazeDB

final class DistinctEdgeCaseTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Distinct-\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "DistinctTest", fileURL: tempURL, password: "DistinctEdgeCaseTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - High Cardinality Tests
    
    /// Test distinct with very high cardinality (many unique values)
    func testDistinctWithHighCardinality() throws {
        print("🎯 Testing distinct with high cardinality...")
        
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 1000 : 100
        
        // Insert records where every value is unique
        for i in 0..<count {
            _ = try db.insert(BlazeDataRecord([
                "uniqueID": .string(UUID().uuidString),
                "index": .int(i)
            ]))
        }
        
        print("  Inserted \(count) records with unique values")
        
        // Get distinct values
        let startTime = Date()
        let distinct = try db.distinct(field: "uniqueID")
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(distinct.count, count, "Should have \(count) distinct values")
        
        print("  Found \(distinct.count) distinct values in \(String(format: "%.3f", duration))s")
        print("  Rate: \(String(format: "%.0f", Double(count) / duration)) values/sec")
        
        // Should be reasonably fast even with high cardinality
        let maxDuration: TimeInterval = count == 1000 ? 0.5 : 0.2
        XCTAssertLessThan(duration, maxDuration, "Distinct should be fast")
        
        print("✅ High cardinality distinct works efficiently")
    }
    
    /// Test distinct with low cardinality (many duplicates)
    func testDistinctWithLowCardinality() throws {
        print("🎯 Testing distinct with low cardinality...")
        
        // Insert 100 records with only 5 distinct values
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "category": .string("cat_\(i % 5)"),  // Only 5 distinct values
                "index": .int(i)
            ]))
        }
        
        print("  Inserted 100 records with 5 distinct categories")
        
        // Get distinct
        let distinct = try db.distinct(field: "category")
        
        XCTAssertEqual(distinct.count, 5, "Should have 5 distinct values from 100 records")
        
        // Verify actual values
        let categories = distinct.compactMap { $0.stringValue }.sorted()
        XCTAssertEqual(categories, ["cat_0", "cat_1", "cat_2", "cat_3", "cat_4"])
        
        print("✅ Low cardinality distinct works correctly")
    }
    
    /// Test distinct performance on indexed vs non-indexed field
    func testDistinctPerformanceIndexedVsNonIndexed() throws {
        print("🎯 Testing distinct performance: indexed vs non-indexed...")
        
        let collection = db.collection
        
        // Insert data
        for i in 0..<200 {
            _ = try db.insert(BlazeDataRecord([
                "indexed": .string("val_\(i % 20)"),
                "nonIndexed": .string("val_\(i % 20)")
            ]))
        }
        
        // Create index on one field
        try collection.createIndex(on: "indexed")
        try db.persist()
        
        print("  Setup: 200 records, 20 distinct values per field")
        
        // Distinct on non-indexed field
        let start1 = Date()
        let distinct1 = try db.distinct(field: "nonIndexed")
        let duration1 = Date().timeIntervalSince(start1)
        
        // Distinct on indexed field
        let start2 = Date()
        let distinct2 = try db.distinct(field: "indexed")
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertEqual(distinct1.count, 20)
        XCTAssertEqual(distinct2.count, 20)
        
        print("  Non-indexed: \(String(format: "%.4f", duration1))s")
        print("  Indexed:     \(String(format: "%.4f", duration2))s")
        
        // Indexed should be faster (or at least not slower)
        // Note: For distinct, both might do full scan, but index helps
        
        print("✅ Distinct works on both indexed and non-indexed fields")
    }
    
    /// Test distinct on field with all null/missing values
    func testDistinctOnMissingField() throws {
        print("🎯 Testing distinct on missing field...")
        
        // Insert records without the field
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["other": .int(i)]))
        }
        
        // Distinct on non-existent field
        let distinct = try db.distinct(field: "nonExistent")
        
        // Should return empty (no values present)
        XCTAssertEqual(distinct.count, 0, "Distinct on missing field should return empty")
        
        print("✅ Distinct on missing field returns empty correctly")
    }
}

