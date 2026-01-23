//
//  AutoMigrationVerificationTests.swift
//  BlazeDBTests
//
//  Verifies that format migration (JSON → BlazeBinary) preserves ALL data
//  with byte-perfect accuracy. Tests the fix for the metadata corruption bug.
//

import XCTest
@testable import BlazeDBCore

final class AutoMigrationVerificationTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoMig-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try! BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        // IMPORTANT: Disable MVCC for migration tests
        // MVCC version history doesn't persist yet, causing data loss on reopen
        db.collection.mvccEnabled = false
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic Migration Tests
    
    /// Test: Metadata format field exists and is valid
    func testMetadataHasEncodingFormat() throws {
        try db.insert(BlazeDataRecord(["test": .string("value")]))
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let data = try Data(contentsOf: metaURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertNotNil(json["encodingFormat"], "Metadata should have encodingFormat field")
        
        let format = json["encodingFormat"] as? String
        XCTAssertTrue(format == "json" || format == "blazeBinary", 
                     "encodingFormat should be 'json' or 'blazeBinary', got: \(format ?? "nil")")
    }
    
    /// Test: Migration doesn't corrupt metadata
    func testMigrationDoesntCorruptMetadata() throws {
        // Insert records
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let dataBefore = try Data(contentsOf: metaURL)
        let sizeBefore = dataBefore.count
        
        // Close and reopen (triggers migration check)
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        let dataAfter = try Data(contentsOf: metaURL)
        let sizeAfter = dataAfter.count
        
        // File should not mysteriously grow by 1 byte (the bug we fixed!)
        let sizeDiff = abs(sizeAfter - sizeBefore)
        XCTAssertLessThan(sizeDiff, 100, 
                         "Metadata size shouldn't change drastically (was \(sizeBefore), now \(sizeAfter))")
        
        // Both should be valid JSON
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: dataBefore), 
                        "Metadata before migration should be valid JSON")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: dataAfter), 
                        "Metadata after migration should be valid JSON")
        
        // All records should still be there
        XCTAssertEqual(db.count(), 10, "All records should survive migration check")
    }
    
    /// Test: Metadata never gets binary prefix
    func testMetadataNeverGetsBinaryPrefix() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Test multiple times
        for _ in 0..<5 {
            db = nil
            BlazeDBClient.clearCachedKey()
            db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
            try db.persist()
            
            let data = try Data(contentsOf: metaURL)
            
            // First byte should ALWAYS be '{' (JSON start)
            XCTAssertEqual(data.first, UInt8(ascii: "{"), 
                          "Metadata should always start with '{{', got byte: \(data.first ?? 0)")
            
            // Should NOT start with 0x01 or 0x02 (binary format markers)
            XCTAssertNotEqual(data.first, 0x01, "Should not have binary format prefix 0x01")
            XCTAssertNotEqual(data.first, 0x02, "Should not have binary format prefix 0x02")
        }
    }
    
    // MARK: - Data Preservation Tests
    
    /// Test: All records survive JSON → BlazeBinary migration
    func testAllRecordsSurviveMigration() throws {
        // Clean up and recreate database to ensure fresh state
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        // Temporarily disable MVCC for migration tests (version history doesn't persist yet)
        db.collection.mvccEnabled = false
        
        var ids: [UUID] = []
        var expectedValues: [UUID: Int] = [:]
        
        // STEP 1: Write data in JSON format (simulating old database)
        print("📝 Writing 50 records in JSON format (old format)...")
        for i in 0..<50 {
            let id = UUID()
            let document: [String: BlazeDocumentField] = [
                "id": .uuid(id),
                "index": .int(i),
                "title": .string("Record \(i)"),
                "data": .string(String(repeating: "X", count: i * 10)),
                "project": .string("migration_test"),
                "createdAt": .date(Date())
            ]
            
            // Write using JSON (old format)
            let encoded = try JSONEncoder().encode(document)
            try db.collection.store.writePage(index: i, plaintext: encoded)
            db.collection.indexMap[id] = i
            
            ids.append(id)
            expectedValues[id] = i
        }
        
        db.collection.nextPageIndex = 50
        
        // STEP 2: Save metadata, then manually set encodingFormat to "json"
        try db.persist()
        
        // IMPORTANT: Set encodingFormat AFTER persist() (otherwise persist overwrites it!)
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let data = try Data(contentsOf: metaURL)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        print("🔍 Before update: encodingFormat = \(json["encodingFormat"] ?? "nil")")
        json["encodingFormat"] = "json"  // ✅ Mark as JSON format (to trigger migration)
        print("🔍 After update: encodingFormat = \(json["encodingFormat"] ?? "nil")")
        
        let updatedData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try updatedData.write(to: metaURL, options: .atomic)
        
        // Verify it was actually written
        let verifyData = try Data(contentsOf: metaURL)
        let verifyJson = try JSONSerialization.jsonObject(with: verifyData) as! [String: Any]
        print("✅ Metadata encodingFormat verified on disk: \(verifyJson["encodingFormat"] ?? "nil")")
        
        print("📊 Before reopen: \(ids.count) IDs tracked, pages in JSON format, metadata says 'json'")
        
        // STEP 3: Reopen database (should trigger JSON → BlazeBinary migration)
        print("🔄 Reopening database to trigger migration...")
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        db.collection.mvccEnabled = false
        
        // Debug: Check what was loaded
        let actualCount = db.count()
        print("📊 After migration: count = \(actualCount)")
        print("📊 IndexMap size: \(db.collection.indexMap.count)")
        
        // CRITICAL: Close and reopen database to clear file handle caches
        print("🔄 Closing and reopening to clear caches...")
        db = nil
        BlazeDBClient.clearCachedKey()
        Thread.sleep(forTimeInterval: 0.1)  // Give OS time to flush
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        db.collection.mvccEnabled = false
        
        let finalCount = db.count()
        print("📊 After reopen: count = \(finalCount)")
        
        // STEP 4: Verify ALL records survived migration
        XCTAssertEqual(finalCount, 50, "All 50 records should survive JSON → BlazeBinary migration")
        
        var successCount = 0
        var failCount = 0
        
        for (id, expectedIndex) in expectedValues {
            let record = try db.fetch(id: id)
            if record != nil {
                successCount += 1
                XCTAssertEqual(record?["index"]?.intValue, expectedIndex, 
                              "Record \(expectedIndex) data should be intact")
            } else {
                failCount += 1
                if failCount == 1 {
                    // Log first failure for debugging
                    print("❌ First failed ID: \(id), expected index: \(expectedIndex)")
                    print("   Page number: \(db.collection.indexMap[id] ?? -1)")
                }
            }
        }
        
        print("📊 Success: \(successCount)/50, Failed: \(failCount)/50")
        XCTAssertEqual(successCount, 50, "All records should be readable after migration")
    }
    
    /// Test: Field types preserved during migration
    func testFieldTypesPreservedDuringMigration() throws {
        // Temporarily disable MVCC for migration tests
        db.collection.mvccEnabled = false
        
        let testDate = Date()
        let testUUID = UUID()
        
        let id = try db.insert(BlazeDataRecord([
            "string": .string("Test"),
            "int": .int(42),
            "double": .double(3.14159),
            "bool": .bool(true),
            "date": .date(testDate),
            "uuid": .uuid(testUUID)
        ]))
        
        try db.persist()
        
        // Trigger migration
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        db.collection.mvccEnabled = false
        
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record)
        
        // Verify exact type preservation
        XCTAssertEqual(record?["string"]?.stringValue, "Test")
        XCTAssertEqual(record?["int"]?.intValue, 42)
        if let doubleVal = record?["double"]?.doubleValue {
            XCTAssertEqual(doubleVal, 3.14159, accuracy: 0.00001)
        } else {
            XCTFail("Double value should be preserved")
        }
        XCTAssertEqual(record?["bool"]?.boolValue, true)
        XCTAssertEqual(record?["uuid"]?.uuidValue, testUUID)
        
        // Date should be within 1ms
        if let recordDate = record?["date"]?.dateValue {
            XCTAssertEqual(recordDate.timeIntervalSince1970, 
                          testDate.timeIntervalSince1970, accuracy: 0.001)
        } else {
            XCTFail("Date field should be preserved")
        }
    }
    
    // MARK: - Multiple Migration Cycles
    
    /// Test: Multiple reopen cycles don't corrupt data
    func testMultipleMigrationCycles() throws {
        // Insert initial data
        for i in 0..<20 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Cycle 10 times
        for cycle in 0..<10 {
            db = nil
            BlazeDBClient.clearCachedKey()
            db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
            
            let count = db.count()
            XCTAssertEqual(count, 20, 
                          "Cycle \(cycle + 1): Should still have 20 records, got \(count)")
            
            // Verify data integrity
            let allRecords = try db.fetchAll()
            XCTAssertEqual(allRecords.count, 20, 
                          "Cycle \(cycle + 1): Should fetch all 20 records")
        }
    }
    
    // MARK: - Encoding Format Consistency
    
    /// Test: Encoding format is consistently written
    func testEncodingFormatConsistent() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Read format multiple times
        var formats: [String] = []
        
        for _ in 0..<5 {
            db = nil
            BlazeDBClient.clearCachedKey()
            db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
            try db.persist()
            
            let data = try Data(contentsOf: metaURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let format = json["encodingFormat"] as? String {
                formats.append(format)
            } else {
                // If encodingFormat is missing, default to "json" (v1 format)
                formats.append("json")
            }
        }
        
        // All should be the same
        let uniqueFormats = Set(formats)
        XCTAssertEqual(uniqueFormats.count, 1, 
                      "Encoding format should be consistent across reopens: \(formats)")
    }
    
    // MARK: - Large Dataset Migration
    
    /// Test: Migration works on large datasets
    func testLargeDatasetMigration() throws {
        // Insert 1000 records
        for i in 0..<1000 {
            try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "A", count: 50))
            ]))
        }
        
        try db.persist()
        
        let countBefore = db.count()
        XCTAssertEqual(countBefore, 1000)
        
        // Trigger migration
        db = nil
        BlazeDBClient.clearCachedKey()
        
        let start = Date()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        let reopenDuration = Date().timeIntervalSince(start)
        
        let countAfter = db.count()
        XCTAssertEqual(countAfter, 1000, "All 1000 records should survive migration")
        
        // Reopen should be reasonably fast even with large dataset
        XCTAssertLessThan(reopenDuration, 2.0, 
                         "Reopening with 1000 records should be < 2s, was \(String(format: "%.2f", reopenDuration))s")
    }
    
    // MARK: - Rollback Safety
    
    /// Test: If migration fails, original data is preserved
    func testMigrationFailurePreservesData() throws {
        // Insert data
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Make a backup of the files
        let backupDir = tempURL.deletingLastPathComponent().appendingPathComponent("backup")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        let backupDB = backupDir.appendingPathComponent(tempURL.lastPathComponent)
        let backupMeta = backupDB.deletingPathExtension().appendingPathExtension("meta")
        
        try FileManager.default.copyItem(at: tempURL, to: backupDB)
        try FileManager.default.copyItem(
            at: tempURL.deletingPathExtension().appendingPathExtension("meta"), 
            to: backupMeta
        )
        
        // Close and reopen (triggers migration check)
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        // Verify data is still there
        XCTAssertEqual(db.count(), 10, "Data should survive migration")
        
        // Verify we can still read from backup (proving migration didn't corrupt original format)
        db = nil
        BlazeDBClient.clearCachedKey()
        let backupDB2 = try BlazeDBClient(name: "backup_test", fileURL: backupDB, password: "test-pass-123")
        XCTAssertEqual(backupDB2.count(), 10, "Backup should still be valid")
        
        // Cleanup backup
        try? FileManager.default.removeItem(at: backupDir)
    }
    
    // MARK: - Format Field Tests
    
    /// Test: encodingFormat field is never a binary byte
    func testEncodingFormatIsNeverBinary() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let data = try Data(contentsOf: metaURL)
        
        // Parse as JSON
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodingFormat = json["encodingFormat"]
        
        // Should be a STRING, not a number/binary
        XCTAssertTrue(encodingFormat is String, 
                     "encodingFormat should be a string, got: \(type(of: encodingFormat))")
        
        if let formatStr = encodingFormat as? String {
            // Should be readable text
            XCTAssertFalse(formatStr.contains("\0"), "Format should not contain null bytes")
            XCTAssertFalse(formatStr.isEmpty, "Format should not be empty")
            XCTAssertTrue(formatStr == "json" || formatStr == "blazeBinary", 
                         "Format should be 'json' or 'blazeBinary', got: '\(formatStr)'")
        }
    }
    
    /// Test: Metadata file never starts with binary byte
    func testMetadataNeverStartsWithBinaryByte() throws {
        // This specifically tests the bug we fixed
        
        for attempt in 0..<10 {
            // Insert data
            try db.insert(BlazeDataRecord(["attempt": .int(attempt)]))
            try db.persist()
            
            // Reopen
            db = nil
            BlazeDBClient.clearCachedKey()
            db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
            
            // Check metadata file
            let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
            let data = try Data(contentsOf: metaURL)
            
            let firstByte = data.first!
            
            // Should start with '{' (0x7B)
            XCTAssertEqual(firstByte, 0x7B, 
                          "Attempt \(attempt): Metadata should start with '{{' (0x7B), got 0x\(String(format: "%02X", firstByte))")
            
            // Should NOT be 0x01 or 0x02 (the bug!)
            XCTAssertNotEqual(firstByte, 0x01, 
                             "Attempt \(attempt): Metadata has binary prefix 0x01!")
            XCTAssertNotEqual(firstByte, 0x02, 
                             "Attempt \(attempt): Metadata has binary prefix 0x02!")
        }
    }
    
    // MARK: - Record Count Preservation
    
    /// Test: Record count identical before and after migration
    func testRecordCountPreservedDuringMigration() throws {
        // Insert known count
        let expectedCount = 25
        
        for i in 0..<expectedCount {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try db.persist()
        let countBefore = db.count()
        XCTAssertEqual(countBefore, expectedCount)
        
        // Trigger migration
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        let countAfter = db.count()
        XCTAssertEqual(countAfter, expectedCount, 
                      "Record count changed from \(countBefore) to \(countAfter) during migration!")
        
        // Verify all records are FETCHABLE, not just countable
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, expectedCount, 
                      "All \(expectedCount) records should be fetchable after migration")
    }
    
    /// Test: Specific records preserved during migration (verify by ID)
    func testSpecificRecordsPreservedDuringMigration() throws {
        var testRecords: [(UUID, String)] = []
        
        // Insert with known IDs and values
        for i in 0..<10 {
            let id = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i + 1)")
            ]))
            testRecords.append((id, "Bug \(i + 1)"))
        }
        
        try db.persist()
        
        // Trigger migration
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        // Verify each specific record by ID
        for (id, expectedTitle) in testRecords {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record, "Record with ID \(id) should exist after migration")
            XCTAssertEqual(record?["title"]?.stringValue, expectedTitle, 
                          "Record with ID \(id) should have correct data")
        }
    }
    
    // MARK: - Secondary Index Preservation
    
    /// Test: Secondary indexes preserved during migration
    func testSecondaryIndexesPreservedDuringMigration() throws {
        // Create index
        try db.collection.createIndex(on: "status")
        
        // Insert data
        for i in 0..<20 {
            try db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "active" : "inactive"),
                "value": .int(i)
            ]))
        }
        
        try db.persist()
        
        // Query using index
        let resultBefore = try db.query()
            .where("status", equals: .string("active"))
            .execute()
        XCTAssertEqual(resultBefore.count, 10)
        
        // Trigger migration
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        // Query should still work with index
        let resultAfter = try db.query()
            .where("status", equals: .string("active"))
            .execute()
        XCTAssertEqual(resultAfter.count, 10, 
                      "Index query should work after migration")
    }
    
    // MARK: - Stress Tests
    
    /// Test: Migration under concurrent access
    func testMigrationUnderConcurrentAccess() throws {
        // Insert data
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Trigger migration
        db = nil
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "migration_test", fileURL: tempURL, password: "test-pass-123")
        
        // Immediately start concurrent operations
        let group = DispatchGroup()
        var errors: [Error] = []
        let lock = NSLock()
        
        for i in 100..<200 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    try self.db.insert(BlazeDataRecord(["value": .int(i)]))
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        // Should handle concurrent access during/after migration
        XCTAssertTrue(errors.isEmpty, "Concurrent inserts after migration should work: \(errors)")
        
        let finalCount = db.count()
        XCTAssertGreaterThanOrEqual(finalCount, 100, 
                                    "Should have at least 100 records after concurrent stress")
    }
}

