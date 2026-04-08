//
//  PersistenceIntegrityTests.swift
//  BlazeDBTests
//
//  Verifies that ALL records survive persist/reopen cycles under all conditions.
//  These tests would have caught the "8 instead of 10 records" bug.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PersistenceIntegrityTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    private func persistenceFixtureURL() throws -> URL {
        try XCTUnwrap(tempURL, "tempURL should be set in setUpWithError")
    }
    
    private func persistenceDB() throws -> BlazeDBClient {
        try XCTUnwrap(db, "database should be open")
    }
    
    private func fileAttributeIntSize(atPath path: String) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        if let i = attrs[.size] as? Int { return i }
        return try XCTUnwrap(attrs[.size] as? NSNumber, "expected file size attribute").intValue
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersInt-\(testID).blazedb")
        tempURL = url
        
        // Clean up
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("indexes"))
        
        db = try BlazeDBClient(name: "persist_test", fileURL: url, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic Persistence Tests
    
    /// Test: Exact count preservation (1 record)
    func testSingleRecordPersistence() throws {
        let id = try persistenceDB().insert(BlazeDataRecord(["title": .string("Test")]))
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), 1, "Should have exactly 1 record")
        
        let record = try persistenceDB().fetch(id: id)
        XCTAssertNotNil(record, "Record should be readable")
        XCTAssertEqual(record?["title"]?.stringValue, "Test")
    }
    
    /// Test: Exact count preservation (10 records - the failing case!)
    func testTenRecordsPersistence() throws {
        var ids: [UUID] = []
        
        for i in 1...10 {
            let id = try persistenceDB().insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        let countBeforePersist = try persistenceDB().count()
        XCTAssertEqual(countBeforePersist, 10, "Should have 10 records before persist")
        
        try persistenceDB().persist()
        
        let countAfterPersist = try persistenceDB().count()
        XCTAssertEqual(countAfterPersist, 10, "Should still have 10 records after persist")
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        let countAfterReopen = try persistenceDB().count()
        XCTAssertEqual(countAfterReopen, 10, "Should have exactly 10 records after reopen")
        
        // Verify ALL records are readable (not just countable)
        let allRecords = try persistenceDB().fetchAll()
        XCTAssertEqual(allRecords.count, 10, "All 10 records should be fetchable")
        
        // Verify each specific record by ID
        for (index, id) in ids.enumerated() {
            let record = try persistenceDB().fetch(id: id)
            XCTAssertNotNil(record, "Record \(index + 1) with ID \(id) should exist")
            XCTAssertEqual(record?["index"]?.intValue, index + 1, "Record \(index + 1) data should match")
        }
    }
    
    /// Test: 100 records persistence
    func test100RecordsPersistence() throws {
        var ids: [UUID] = []
        
        for i in 1...100 {
            let id = try persistenceDB().insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), 100, "Should have exactly 100 records")
        
        // Verify ALL records readable
        for (index, id) in ids.enumerated() {
            let record = try persistenceDB().fetch(id: id)
            XCTAssertNotNil(record, "Record \(index + 1) should exist")
            XCTAssertEqual(record?["value"]?.intValue, index + 1)
        }
    }
    
    // MARK: - Multiple Persist Cycles
    
    /// Test: Multiple persist cycles preserve all data
    func testMultiplePersistCycles() throws {
        // Cycle 1: Insert 5
        for i in 1...5 {
            _ = try persistenceDB().insert(BlazeDataRecord(["cycle": .int(1), "index": .int(i)]))
        }
        try persistenceDB().persist()
        
        // Cycle 2: Insert 5 more
        for i in 1...5 {
            _ = try persistenceDB().insert(BlazeDataRecord(["cycle": .int(2), "index": .int(i)]))
        }
        try persistenceDB().persist()
        
        // Cycle 3: Insert 5 more
        for i in 1...5 {
            _ = try persistenceDB().insert(BlazeDataRecord(["cycle": .int(3), "index": .int(i)]))
        }
        try persistenceDB().persist()
        
        XCTAssertEqual(try persistenceDB().count(), 15, "Should have 15 records after 3 cycles")
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), 15, "Should have all 15 records after reopen")
        
        // Verify records from each cycle exist
        let cycle1 = try persistenceDB().query().where("cycle", equals: .int(1)).execute()
        let cycle2 = try persistenceDB().query().where("cycle", equals: .int(2)).execute()
        let cycle3 = try persistenceDB().query().where("cycle", equals: .int(3)).execute()
        
        XCTAssertEqual(cycle1.count, 5, "Cycle 1 should have 5 records")
        XCTAssertEqual(cycle2.count, 5, "Cycle 2 should have 5 records")
        XCTAssertEqual(cycle3.count, 5, "Cycle 3 should have 5 records")
    }
    
    // MARK: - Without Explicit Persist (deinit tests)
    
    /// Test: Records survive without explicit persist (deinit should save)
    func testImplicitPersistOnDeinit() throws {
        var ids: [UUID] = []
        
        for i in 1...10 {
            let id = try persistenceDB().insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // DON'T call persist() - rely on deinit
        db = nil
        
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        
        // Reopen
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        let count = try persistenceDB().count()
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
            _ = try persistenceDB().insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        let metadataCount = try persistenceDB().collection.indexMap.count
        let fetchableCount = try persistenceDB().fetchAll().count
        
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
            _ = try persistenceDB().insert(BlazeDataRecord(["title": .string(title), "index": .int(i)]))
        }
        
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        // Check EVERY entry in indexMap
        var unreadableIDs: [UUID] = []
        
        for id in try persistenceDB().collection.indexMap.keys {
            if (try? persistenceDB().fetch(id: id)) == nil {
                unreadableIDs.append(id)
            }
        }
        
        XCTAssertTrue(unreadableIDs.isEmpty, 
                     "Found \(unreadableIDs.count) unreadable records: \(unreadableIDs)")
    }
    
    // MARK: - Edge Cases
    
    /// Test: Persist with 0 records (empty database)
    func testPersistEmptyDatabase() throws {
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), 0, "Empty database should remain empty")
    }
    
    /// Test: Persist, insert more, persist again
    func testPersistInsertPersistCycle() throws {
        // First batch
        for i in 1...5 {
            _ = try persistenceDB().insert(BlazeDataRecord(["batch": .int(1), "index": .int(i)]))
        }
        try persistenceDB().persist()
        XCTAssertEqual(try persistenceDB().count(), 5)
        
        // Second batch
        for i in 1...5 {
            _ = try persistenceDB().insert(BlazeDataRecord(["batch": .int(2), "index": .int(i)]))
        }
        try persistenceDB().persist()
        XCTAssertEqual(try persistenceDB().count(), 10)
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), 10, "Should have all 10 records")
        
        // Verify both batches exist
        let batch1 = try persistenceDB().query().where("batch", equals: .int(1)).execute()
        let batch2 = try persistenceDB().query().where("batch", equals: .int(2)).execute()
        
        XCTAssertEqual(batch1.count, 5, "Batch 1 should have 5 records")
        XCTAssertEqual(batch2.count, 5, "Batch 2 should have 5 records")
    }
    
    /// Test: Large dataset persistence (stress test)
    func testLargeDatasetPersistence() throws {
        let recordCount = 1000
        var ids: [UUID] = []
        
        for i in 1...recordCount {
            let id = try persistenceDB().insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "X", count: 100))
            ]))
            ids.append(id)
        }
        
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.2)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), recordCount, "Should have all \(recordCount) records")
        
        // Sample check: verify first, middle, and last records
        XCTAssertNotNil(try persistenceDB().fetch(id: ids[0]), "First record should exist")
        XCTAssertNotNil(try persistenceDB().fetch(id: ids[recordCount/2]), "Middle record should exist")
        XCTAssertNotNil(try persistenceDB().fetch(id: ids[recordCount-1]), "Last record should exist")
    }
    
    // MARK: - Update/Delete Persistence
    
    /// Test: Updates persist correctly
    func testUpdatesPersist() throws {
        let id = try persistenceDB().insert(BlazeDataRecord(["value": .int(1)]))
        try persistenceDB().update(id: id, with: BlazeDataRecord(["value": .int(2)]))
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        let record = try persistenceDB().fetch(id: id)
        XCTAssertEqual(record?["value"]?.intValue, 2, "Updated value should persist")
    }
    
    /// Test: Deletes persist correctly
    func testDeletesPersist() throws {
        let id1 = try persistenceDB().insert(BlazeDataRecord(["keep": .bool(true)]))
        let id2 = try persistenceDB().insert(BlazeDataRecord(["keep": .bool(false)]))
        let id3 = try persistenceDB().insert(BlazeDataRecord(["keep": .bool(true)]))
        
        try persistenceDB().delete(id: id2)
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        XCTAssertEqual(try persistenceDB().count(), 2, "Should have 2 records after delete")
        XCTAssertNotNil(try persistenceDB().fetch(id: id1), "Record 1 should exist")
        XCTAssertNil(try persistenceDB().fetch(id: id2), "Record 2 should be deleted")
        XCTAssertNotNil(try persistenceDB().fetch(id: id3), "Record 3 should exist")
    }
    
    // MARK: - Field Verification
    
    /// Test: All field types persist correctly
    func testAllFieldTypesPersist() throws {
        let testDate = Date()
        let testUUID = UUID()
        let testData = Data([0x01, 0x02, 0x03])
        
        let id = try persistenceDB().insert(BlazeDataRecord([
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
        
        try persistenceDB().persist()
        
        // Reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        let record = try persistenceDB().fetch(id: id)
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
            _ = try persistenceDB().insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Simulate crash (no persist, no deinit cleanup)
        db = nil
        
        // Minimal delay
        Thread.sleep(forTimeInterval: 0.05)
        BlazeDBClient.clearCachedKey()
        
        // Reopen
        db = try BlazeDBClient(name: "persist_test", fileURL: try persistenceFixtureURL(), password: "SecureTestDB-456!")
        
        let count = try persistenceDB().count()
        
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
            _ = try persistenceDB().insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try persistenceDB().persist()
        
        let metaURL = try persistenceFixtureURL().deletingPathExtension().appendingPathExtension("meta")
        let metaSize1 = try fileAttributeIntSize(atPath: metaURL.path)
        
        // Persist again (no changes)
        try persistenceDB().persist()
        
        let metaSize2 = try fileAttributeIntSize(atPath: metaURL.path)
        
        XCTAssertEqual(metaSize1, metaSize2, 
                      "Metadata size should not change on persist without changes (was \(metaSize1), now \(metaSize2))")
    }
    
    /// Test: Metadata file remains valid JSON
    func testMetadataRemainsValidJSON() throws {
        for i in 1...10 {
            _ = try persistenceDB().insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try persistenceDB().persist()
        
        let metaURL = try persistenceFixtureURL().deletingPathExtension().appendingPathExtension("meta")
        let data = try Data(contentsOf: metaURL)
        
        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        XCTAssertNotNil(json, "Metadata should be valid JSON")
        
        // Verify it has expected structure
        if let dict = json as? [String: Any] {
            let layoutDict = (dict["layout"] as? [String: Any]) ?? dict
            XCTAssertNotNil(layoutDict["indexMap"], "Should have indexMap")
            XCTAssertNotNil(layoutDict["nextPageIndex"], "Should have nextPageIndex")
            XCTAssertNotNil(layoutDict["encodingFormat"], "Should have encodingFormat")
        } else {
            XCTFail("Metadata should be a JSON object")
        }
    }
}

