//  BlazeIndexStressTests.swift
//  BlazeDB Index Stress Testing
//  Tests index performance under high cardinality and large datasets

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDBCore

final class BlazeIndexStressTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeIndexStress-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "IndexStressTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - Single-Field Index Stress
    
    /// Test index rebuild on large dataset
    /// Note: Set RUN_HEAVY_STRESS=1 to use 10k records, otherwise uses 1k
    func testIndexRebuildOn10kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 10_000 : 1_000
        
        print("📊 Inserting \(count) records...")
        for i in 0..<count {
            let record = BlazeDataRecord([
                "category": .string("cat_\(i % 100)"),  // 100 unique values
                "priority": .int(i % 5),                 // 5 unique values
                "value": .double(Double(i))
            ])
            _ = try db.insert(record)
        }
        
        // Flush metadata before creating index
        let collection = db.collection as! DynamicCollection
        try collection.persist()
        
        // Create index definition (starts empty)
        print("🔨 Creating index on 'category'...")
        try collection.createIndex(on: "category")
        
        // Close and reopen to trigger index rebuild
        print("🔄 Reopening database to trigger index rebuild...")
        db = nil
        let startTime = Date()
        db = try BlazeDBClient(name: "IndexStressTest", fileURL: tempURL, password: "test-password-123")
        let rebuildDuration = Date().timeIntervalSince(startTime)
        
        print("✅ Index rebuilt in \(String(format: "%.3f", rebuildDuration))s")
        print("   Rate: \(String(format: "%.0f", Double(count) / rebuildDuration)) records/sec")
        
        // Verify index works
        print("🔍 Testing index query...")
        let queryStart = Date()
        let rebuiltCollection = db.collection as! DynamicCollection
        let results = try rebuiltCollection.fetch(byIndexedField: "category", value: "cat_50")
        let queryDuration = Date().timeIntervalSince(queryStart)
        
        print("✅ Index query returned \(results.count) results in \(String(format: "%.4f", queryDuration))s")
        XCTAssertEqual(results.count, 10, "Should find 10 records with cat_50 (1000 records % 100 categories = 10 per category)")
    }
    
    /// Test high cardinality index (many unique values)
    /// Note: Set RUN_HEAVY_STRESS=1 to use 5k records, otherwise uses 500
    func testHighCardinalityIndex() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 5_000 : 500
        
        print("📊 Creating high cardinality index with \(count) unique values...")
        
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "uniqueID")
        
        for i in 0..<count {
            let record = BlazeDataRecord([
                "uniqueID": .string(UUID().uuidString),  // Every value is unique!
                "data": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        print("✅ Inserted \(count) records with unique indexed values")
        
        // Flush metadata to ensure records are visible
        try db.persist()
        
        // Query performance should still be good
        let allRecords = try collection.fetchAll()
        guard let randomRecord = allRecords.randomElement(),
              let testUUID = randomRecord.storage["uniqueID"]?.uuidValue else {
            XCTFail("Failed to get random UUID from \(allRecords.count) records")
            return
        }
        
        let queryStart = Date()
        let results = try collection.fetch(byIndexedField: "uniqueID", value: testUUID)
        let queryDuration = Date().timeIntervalSince(queryStart)
        
        print("✅ High cardinality index query: \(String(format: "%.4f", queryDuration))s")
        XCTAssertEqual(results.count, 1, "Should find exactly 1 record")
        XCTAssertLessThan(queryDuration, 0.01, "Query should be fast even with high cardinality")
    }
    
    // MARK: - Compound Index Stress
    
    /// Test compound index with 3+ fields on large dataset
    /// Note: Set RUN_HEAVY_STRESS=1 to use 5k records, otherwise uses 500
    func testCompoundIndex3FieldsOn5kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 5_000 : 500
        
        print("📊 Testing compound index with 3 fields on \(count) records...")
        
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: ["status", "priority", "category"])
        
        let statuses = ["open", "closed", "pending"]
        let priorities = [1, 2, 3, 4, 5]
        let categories = ["bug", "feature", "task"]
        
        print("  Inserting records...")
        for i in 0..<count {
            let record = BlazeDataRecord([
                "status": .string(statuses[i % statuses.count]),
                "priority": .int(priorities[i % priorities.count]),
                "category": .string(categories[i % categories.count]),
                "description": .string("Item \(i)")
            ])
            _ = try db.insert(record)
        }
        
        // Test compound query
        print("🔍 Testing compound index query...")
        let queryStart = Date()
        let results = try collection.fetch(
            byIndexedFields: ["status", "priority", "category"],
            values: ["open", 3, "bug"]
        )
        let queryDuration = Date().timeIntervalSince(queryStart)
        
        print("✅ Compound query returned \(results.count) results in \(String(format: "%.4f", queryDuration))s")
        
        // Verify all results match criteria
        for result in results {
            XCTAssertEqual(result.storage["status"]?.stringValue, "open")
            XCTAssertEqual(result.storage["priority"]?.intValue, 3)
            XCTAssertEqual(result.storage["category"]?.stringValue, "bug")
        }
        
        XCTAssertGreaterThan(results.count, 0, "Should find matching records")
    }
    
    /// Test index maintenance during heavy updates
    func testIndexMaintenanceDuringUpdates() throws {
        let count = 1_000
        let updateRounds = 5
        
        print("📊 Testing index maintenance with \(count) records x \(updateRounds) update rounds...")
        
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "status")
        try collection.createIndex(on: ["status", "priority"])
        
        // Insert initial data
        var recordIDs: [UUID] = []
        for i in 0..<count {
            let record = BlazeDataRecord([
                "status": .string("pending"),
                "priority": .int(1),
                "index": .int(i)
            ])
            let id = try db.insert(record)
            recordIDs.append(id)
        }
        
        let statuses = ["pending", "in_progress", "done", "blocked"]
        
        // Perform multiple update rounds
        for round in 0..<updateRounds {
            print("  Round \(round + 1)/\(updateRounds)...")
            let startTime = Date()
            
            for (idx, id) in recordIDs.enumerated() {
                guard let record = try collection.fetch(id: id) else { continue }
                var updated = record.storage
                updated["status"] = .string(statuses[idx % statuses.count])
                updated["priority"] = .int((idx % 5) + 1)
                try collection.update(id: id, with: BlazeDataRecord(updated))
            }
            
            let duration = Date().timeIntervalSince(startTime)
            print("    Completed in \(String(format: "%.2f", duration))s")
        }
        
        // Verify index still works correctly
        print("🔍 Verifying index integrity after updates...")
        let results = try collection.fetch(byIndexedField: "status", value: "done")
        
        // All results should actually have status="done"
        for result in results {
            XCTAssertEqual(result.storage["status"]?.stringValue, "done",
                          "Index should return only matching records")
        }
        
        print("✅ Index maintained correctly through \(count * updateRounds) updates")
    }
    
    /// Test index performance vs full scan
    /// Note: Set RUN_HEAVY_STRESS=1 to use 5k records, otherwise uses 500
    func testIndexedVsFullScanPerformance() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 5_000 : 500
        let searchValue = "target_value"
        
        print("📊 Comparing indexed vs full scan performance on \(count) records...")
        
        let collection = db.collection as! DynamicCollection
        
        // Insert records (10% have target value)
        for i in 0..<count {
            let record = BlazeDataRecord([
                "searchField": .string(i % 10 == 0 ? searchValue : "other_\(i)"),
                "data": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // Flush metadata before testing (ensure all records are indexed)
        try collection.persist()
        
        // Full scan (no index)
        print("  Testing full scan...")
        var fullScanStart = Date()
        let fullScanResults = try collection.filter { record in
            record.storage["searchField"]?.stringValue == searchValue
        }
        var fullScanDuration = Date().timeIntervalSince(fullScanStart)
        
        // Create index definition
        try collection.createIndex(on: "searchField")
        
        // Reopen to trigger index rebuild
        db = nil
        db = try BlazeDBClient(name: "IndexStressTest", fileURL: tempURL, password: "test-password-123")
        let rebuiltCollection = db.collection as! DynamicCollection
        
        print("  Testing indexed query...")
        let indexedStart = Date()
        let indexedResults = try rebuiltCollection.fetch(byIndexedField: "searchField", value: searchValue)
        let indexedDuration = Date().timeIntervalSince(indexedStart)
        
        print("✅ Performance comparison:")
        print("   Full scan: \(String(format: "%.4f", fullScanDuration))s (\(fullScanResults.count) results)")
        print("   Indexed:   \(String(format: "%.4f", indexedDuration))s (\(indexedResults.count) results)")
        print("   Speedup:   \(String(format: "%.1f", fullScanDuration / indexedDuration))x")
        
        XCTAssertEqual(fullScanResults.count, indexedResults.count, "Should return same results")
        XCTAssertLessThan(indexedDuration, fullScanDuration, "Index should be faster than full scan")
    }
    
    // MARK: - Index Persistence Stress
    
    /// Test index survives restart with large dataset
    /// Note: Set RUN_HEAVY_STRESS=1 to use 5k records, otherwise uses 500
    func testIndexPersistenceWith5kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 5_000 : 500
        
        print("📊 Testing index persistence with \(count) records...")
        
        var collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "category")
        try collection.createIndex(on: ["status", "priority"])
        
        // Insert data
        for i in 0..<count {
            let record = BlazeDataRecord([
                "category": .string("cat_\(i % 50)"),
                "status": .string(["open", "closed"][i % 2]),
                "priority": .int((i % 5) + 1)
            ])
            _ = try db.insert(record)
        }
        
        print("  Inserted \(count) records with indexes")
        
        // Flush metadata before closing (ensure indexes are persisted)
        try collection.persist()
        
        // Close and reopen
        print("🔄 Closing and reopening database...")
        db = nil
        db = try BlazeDBClient(name: "IndexStressTest", fileURL: tempURL, password: "test-password-123")
        collection = db.collection as! DynamicCollection
        
        // Test indexes still work
        print("🔍 Testing single-field index after reload...")
        let singleResults = try collection.fetch(byIndexedField: "category", value: "cat_25")
        print("   Found \(singleResults.count) results")
        
        print("🔍 Testing compound index after reload...")
        let compoundResults = try collection.fetch(
            byIndexedFields: ["status", "priority"],
            values: ["open", 3]
        )
        print("   Found \(compoundResults.count) results")
        
        XCTAssertGreaterThan(singleResults.count, 0, "Single index should work after reload")
        XCTAssertGreaterThan(compoundResults.count, 0, "Compound index should work after reload")
        
        print("✅ Indexes persisted and restored successfully")
    }
}

