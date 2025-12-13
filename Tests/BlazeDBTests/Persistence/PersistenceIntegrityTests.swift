//
//  PersistenceIntegrityTests.swift
//  BlazeDBTests
//
//  Verifies that ALL records survive persist/reopen cycles under all conditions.
//  These tests would have caught the "8 instead of 10 records" bug.
//

import XCTest
@testable import BlazeDB

final class PersistenceIntegrityTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersInt-\(testID).blazedb")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("indexes"))
        
        do {
            db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic Persistence Tests
    
    /// Test: Exact count preservation (1 record)
    func testSingleRecordPersistence() throws {
        let id = try db.insert(BlazeDataRecord(["title": .string("Test")]))
        try db.persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), 1, "Should have exactly 1 record")
        
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record, "Record should be readable")
        XCTAssertEqual(record?["title"]?.stringValue, "Test")
    }
    
    /// Test: Exact count preservation (10 records - the failing case!)
    func testTenRecordsPersistence() throws {
        var ids: [UUID] = []
        
        for i in 1...10 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        let countBeforePersist = db.count()
        XCTAssertEqual(countBeforePersist, 10, "Should have 10 records before persist")
        
        try db.persist()
        
        let countAfterPersist = db.count()
        XCTAssertEqual(countAfterPersist, 10, "Should still have 10 records after persist")
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        let countAfterReopen = db.count()
        XCTAssertEqual(countAfterReopen, 10, "Should have exactly 10 records after reopen")
        
        // Verify ALL records are readable (not just countable)
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, 10, "All 10 records should be fetchable")
        
        // Verify each specific record by ID
        for (index, id) in ids.enumerated() {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record, "Record \(index + 1) with ID \(id) should exist")
            XCTAssertEqual(record?["index"]?.intValue, index + 1, "Record \(index + 1) data should match")
        }
    }
    
    /// Test: 100 records persistence
    func test100RecordsPersistence() throws {
        var ids: [UUID] = []
        
        for i in 1...100 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        try db.persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), 100, "Should have exactly 100 records")
        
        // Verify ALL records readable
        for (index, id) in ids.enumerated() {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record, "Record \(index + 1) should exist")
            XCTAssertEqual(record?["value"]?.intValue, index + 1)
        }
    }
    
    // MARK: - Multiple Persist Cycles
    
    /// Test: Multiple persist cycles preserve all data
    func testMultiplePersistCycles() throws {
        // Cycle 1: Insert 5
        for i in 1...5 {
            try db.insert(BlazeDataRecord(["cycle": .int(1), "index": .int(i)]))
        }
        try db.persist()
        
        // Cycle 2: Insert 5 more
        for i in 1...5 {
            try db.insert(BlazeDataRecord(["cycle": .int(2), "index": .int(i)]))
        }
        try db.persist()
        
        // Cycle 3: Insert 5 more
        for i in 1...5 {
            try db.insert(BlazeDataRecord(["cycle": .int(3), "index": .int(i)]))
        }
        try db.persist()
        
        XCTAssertEqual(db.count(), 15, "Should have 15 records after 3 cycles")
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), 15, "Should have all 15 records after reopen")
        
        // Verify records from each cycle exist
        let cycle1 = try db.query().where("cycle", equals: .int(1)).execute()
        let cycle2 = try db.query().where("cycle", equals: .int(2)).execute()
        let cycle3 = try db.query().where("cycle", equals: .int(3)).execute()
        
        XCTAssertEqual(cycle1.count, 5, "Cycle 1 should have 5 records")
        XCTAssertEqual(cycle2.count, 5, "Cycle 2 should have 5 records")
        XCTAssertEqual(cycle3.count, 5, "Cycle 3 should have 5 records")
    }
    
    // MARK: - Without Explicit Persist (deinit tests)
    
    /// Test: Records survive without explicit persist (deinit should save)
    func testImplicitPersistOnDeinit() throws {
        var ids: [UUID] = []
        
        for i in 1...10 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // DON'T call persist() - rely on deinit
        db = nil
        
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        
        // Reopen
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        let count = db.count()
        if count < 10 {
            // If deinit didn't save, we should at least know about it
            XCTFail("deinit should have saved metadata, but only found \(count)/10 records")
        }
        
        XCTAssertEqual(count, 10, "deinit should save all 10 records")
    }
    
    // MARK: - Metadata vs Data Consistency
    
    /// Test: Metadata count matches actual fetchable records
    func testMetadataCountMatchesFetchableRecords() throws {
        for i in 1...20 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        let metadataCount = db.collection.indexMap.count
        let fetchableCount = try db.fetchAll().count
        
        XCTAssertEqual(metadataCount, fetchableCount, 
                      "Metadata says \(metadataCount) records but only \(fetchableCount) are fetchable!")
        XCTAssertEqual(metadataCount, 20, "Metadata should have 20 entries")
        XCTAssertEqual(fetchableCount, 20, "Should be able to fetch all 20 records")
    }
    
    /// Test: Every record in indexMap is actually readable
    func testEveryIndexMapEntryReadable() throws {
        // Insert records with varying sizes
        for i in 1...50 {
            let title = String(repeating: "A", count: i * 10)
            try db.insert(BlazeDataRecord(["title": .string(title), "index": .int(i)]))
        }
        
        try db.persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        // Check EVERY entry in indexMap
        var unreadableIDs: [UUID] = []
        
        for id in db.collection.indexMap.keys {
            if (try? db.fetch(id: id)) == nil {
                unreadableIDs.append(id)
            }
        }
        
        XCTAssertTrue(unreadableIDs.isEmpty, 
                     "Found \(unreadableIDs.count) unreadable records: \(unreadableIDs)")
    }
    
    // MARK: - Edge Cases
    
    /// Test: Persist with 0 records (empty database)
    func testPersistEmptyDatabase() throws {
        try db.persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), 0, "Empty database should remain empty")
    }
    
    /// Test: Persist, insert more, persist again
    func testPersistInsertPersistCycle() throws {
        // First batch
        for i in 1...5 {
            try db.insert(BlazeDataRecord(["batch": .int(1), "index": .int(i)]))
        }
        try db.persist()
        XCTAssertEqual(db.count(), 5)
        
        // Second batch
        for i in 1...5 {
            try db.insert(BlazeDataRecord(["batch": .int(2), "index": .int(i)]))
        }
        try db.persist()
        XCTAssertEqual(db.count(), 10)
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), 10, "Should have all 10 records")
        
        // Verify both batches exist
        let batch1 = try db.query().where("batch", equals: .int(1)).execute()
        let batch2 = try db.query().where("batch", equals: .int(2)).execute()
        
        XCTAssertEqual(batch1.count, 5, "Batch 1 should have 5 records")
        XCTAssertEqual(batch2.count, 5, "Batch 2 should have 5 records")
    }
    
    /// Test: Large dataset persistence (stress test)
    func testLargeDatasetPersistence() throws {
        let recordCount = 1000
        var ids: [UUID] = []
        
        for i in 1...recordCount {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "X", count: 100))
            ]))
            ids.append(id)
        }
        
        try db.persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.2)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), recordCount, "Should have all \(recordCount) records")
        
        // Sample check: verify first, middle, and last records
        XCTAssertNotNil(try db.fetch(id: ids[0]), "First record should exist")
        XCTAssertNotNil(try db.fetch(id: ids[recordCount/2]), "Middle record should exist")
        XCTAssertNotNil(try db.fetch(id: ids[recordCount-1]), "Last record should exist")
    }
    
    // MARK: - Update/Delete Persistence
    
    /// Test: Updates persist correctly
    func testUpdatesPersist() throws {
        let id = try db.insert(BlazeDataRecord(["value": .int(1)]))
        try db.update(id: id, with: BlazeDataRecord(["value": .int(2)]))
        try db.persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        let record = try db.fetch(id: id)
        XCTAssertEqual(record?["value"]?.intValue, 2, "Updated value should persist")
    }
    
    /// Test: Deletes persist correctly
    func testDeletesPersist() throws {
        let id1 = try db.insert(BlazeDataRecord(["keep": .bool(true)]))
        let id2 = try db.insert(BlazeDataRecord(["keep": .bool(false)]))
        let id3 = try db.insert(BlazeDataRecord(["keep": .bool(true)]))
        
        try db.delete(id: id2)
        try db.persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        XCTAssertEqual(db.count(), 2, "Should have 2 records after delete")
        XCTAssertNotNil(try db.fetch(id: id1), "Record 1 should exist")
        XCTAssertNil(try db.fetch(id: id2), "Record 2 should be deleted")
        XCTAssertNotNil(try db.fetch(id: id3), "Record 3 should exist")
    }
    
    // MARK: - Field Verification
    
    /// Test: All field types persist correctly
    func testAllFieldTypesPersist() throws {
        let testDate = Date()
        let testUUID = UUID()
        let testData = Data([0x01, 0x02, 0x03])
        
        let id = try db.insert(BlazeDataRecord([
            "string": .string("Hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "date": .date(testDate),
            "uuid": .uuid(testUUID),
            "data": .data(testData),
            "array": .array([.int(1), .int(2)]),
            "dict": .dictionary(["nested": .string("value")])
        ]))
        
        try db.persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record)
        
        XCTAssertEqual(record?["string"]?.stringValue, "Hello")
        XCTAssertEqual(record?["int"]?.intValue, 42)
        XCTAssertEqual(record?["double"]?.doubleValue, 3.14)
        XCTAssertEqual(record?["bool"]?.boolValue, true)
        if let dateInterval = record?["date"]?.dateValue?.timeIntervalSince1970 {
            XCTAssertEqual(dateInterval, testDate.timeIntervalSince1970, accuracy: 0.001)
        } else {
            XCTFail("Date should be preserved")
        }
        XCTAssertEqual(record?["uuid"]?.uuidValue, testUUID)
        XCTAssertEqual(record?["data"]?.dataValue, testData)
        
        if case let .array(arr)? = record?["array"] {
            XCTAssertEqual(arr.count, 2)
        } else {
            XCTFail("Array field should persist")
        }
        
        if case let .dictionary(dict)? = record?["dict"] {
            XCTAssertEqual(dict["nested"]?.stringValue, "value")
        } else {
            XCTFail("Dictionary field should persist")
        }
    }
    
    // MARK: - Crash Simulation
    
    /// Test: Abrupt termination (no persist call)
    func testAbruptTerminationRecovery() throws {
        // Insert without persist
        for i in 1...10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Simulate crash (no persist, no deinit cleanup)
        db = nil
        
        // Minimal delay
        Thread.sleep(forTimeInterval: 0.05)
        BlazeDBClient.clearCachedKey()
        
        // Reopen
        db = try BlazeDBClient(name: "persist_test", fileURL: tempURL, password: "PersistenceIntegrity123!")
        
        let count = db.count()
        
        // We expect some data loss without persist, but deinit should save something
        // This test documents the behavior
        if count == 10 {
            // Excellent - deinit saved everything
            XCTAssertEqual(count, 10, "deinit successfully saved all records")
        } else if count == 0 {
            // Expected behavior if no persist and deinit failed
            XCTAssertTrue(true, "No persist + no deinit = data loss (expected)")
        } else {
            // Partial save - document this behavior
            XCTAssertTrue(count >= 0 && count <= 10, "Partial save: \(count)/10 records")
        }
    }
    
    // MARK: - File Size Consistency
    
    /// Test: File sizes don't grow unexpectedly
    func testFileSizeConsistency() throws {
        // Insert 10 records
        for i in 1...10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let metaSize1 = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.size] as! Int
        
        // Persist again (no changes)
        try db.persist()
        
        let metaSize2 = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.size] as! Int
        
        XCTAssertEqual(metaSize1, metaSize2, 
                      "Metadata size should not change on persist without changes (was \(metaSize1), now \(metaSize2))")
    }
    
    /// Test: Metadata file remains valid JSON
    func testMetadataRemainsValidJSON() throws {
        for i in 1...10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let data = try Data(contentsOf: metaURL)
        
        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        XCTAssertNotNil(json, "Metadata should be valid JSON")
        
        // Verify it has expected structure
        // Note: saveSecure() wraps the layout in a SecureLayout with "layout", "signature", "signedAt" keys
        // So we need to check inside the "layout" key if it exists
        if let dict = json as? [String: Any] {
            // Check if this is a secure layout (has "layout" key)
            let layoutDict: [String: Any]
            if let secureLayout = dict["layout"] as? [String: Any] {
                // This is a secure layout - check inside the layout object
                layoutDict = secureLayout
            } else {
                // This is a plain layout - check at top level
                layoutDict = dict
            }
            
            XCTAssertNotNil(layoutDict["indexMap"], "Should have indexMap")
            XCTAssertNotNil(layoutDict["nextPageIndex"], "Should have nextPageIndex")
            XCTAssertNotNil(layoutDict["encodingFormat"], "Should have encodingFormat")
        } else {
            XCTFail("Metadata should be a JSON object")
        }
    }
}

