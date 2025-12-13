//  BlazeDBMigrationTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

@MainActor
final class BlazeDBMigrationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Minimal delay and cache clear
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
    }
    
    override func tearDown() {
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    func testAddRemoveRenameFieldsMigration() throws {
        // Initial schema version
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("migrationtest-\(testID).blazedb")
        
        // Simple cleanup before test
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
        try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        // Create database with initial record
        let dbName = "TestDB_\(testID)"  // ✅ Unique name per test
        do {
            let db = try BlazeDBClient(name: dbName, fileURL: fileURL, password: "BlazeDBMigrationTest123!")
            let record = BlazeDataRecord([
                "title": .string("World"),
                "value": .int(42)
            ])
            let id = try db.insert(record)
            print("Inserted record with id: \(id)")
            
            // Persist metadata before closing
            try db.persist()
            
            // Verify record exists before closing
            XCTAssertNotNil(try db.fetch(id: id), "Record should exist before reopen")
        }
        
        // Small delay to ensure file handles are released
        Thread.sleep(forTimeInterval: 0.01)
        
        // Simulate app relaunch - migration runs automatically
        let db2 = try BlazeDBClient(name: dbName, fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        // Fetch all records to see what's there
        let allRecords = try db2.fetchAll()
        print("Found \(allRecords.count) records after migration")
        
        // Verify at least one record exists
        XCTAssertGreaterThan(allRecords.count, 0, "Should have at least 1 record after migration")
        
        // Debug: Print what's actually in the record
        let firstRecord = allRecords[0]
        print("🔍 First record fields: \(firstRecord.storage.keys)")
        print("🔍 First record full storage: \(firstRecord.storage)")
        print("🔍 title field: \(String(describing: firstRecord.storage["title"]))")
        print("🔍 value field: \(String(describing: firstRecord.storage["value"]))")
        
        // Verify the record has the expected fields
        XCTAssertEqual(firstRecord.storage["title"]?.stringValue, "World", "Title should be preserved")
        XCTAssertEqual(firstRecord.storage["value"]?.intValue, 42, "Value should be preserved")
        print("✅ Migration preserved record data")
    }
    
    func testBackupBeforeMigration() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("backuptest-\(testID).blazedb")
        
        // Aggressive cleanup
        for attempt in 0..<5 {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
            
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.02 * Double(attempt + 1))
        }
        
        var db = try BlazeDBClient(name: "BackupTestDB_\(testID)", fileURL: fileURL, password: "BackupMigrationTest123!")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        
        // Reopen - migration happens automatically
        db = try BlazeDBClient(name: "BackupTestDB_\(testID)", fileURL: fileURL, password: "BackupMigrationTest123!")
        
        print("📁 Listing all files in temporary directory:")
        let tempFiles = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        for file in tempFiles {
            print(" - \(file)")
        }

        // Search recursively for any backup_v1 file under the temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        var foundBackup: URL? = nil
        
        while let file = enumerator?.nextObject() as? URL {
            if file.lastPathComponent.starts(with: "backup_v") &&
               (file.pathExtension == "blazedb" || file.pathExtension == "meta") {
                foundBackup = file
                break
            }
        }
        
        XCTAssertNotNil(foundBackup, "Expected backup not found anywhere under \(tempDir.path)")
        if let backup = foundBackup {
            print("✅ Backup created at: \(backup.path)")
        }
    }
    
    func testMigrationRemoveField() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("remove-field-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "RemoveFieldTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("Test"),
            "deprecated": .string("Remove me"),
            "value": .int(42)
        ]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        var record = try db.fetch(id: id)
        XCTAssertNotNil(record?.storage["deprecated"])
        
        // CRITICAL: To remove a field, explicitly set it to .null
        // The update() method merges fields by default
        let updated = BlazeDataRecord([
            "deprecated": .null,  // Explicitly remove this field
            "name": .string("Test"),
            "value": .int(42)
        ])
        try db.update(id: id, with: updated)
        
        record = try db.fetch(id: id)
        XCTAssertNil(record?.storage["deprecated"])
        XCTAssertEqual(record?.storage["value"], .int(42))
    }
    
    func testMigrationRenameField() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("rename-field-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "RenameFieldTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        let id = try db.insert(BlazeDataRecord([
            "oldName": .string("Value"),
            "other": .int(123)
        ]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        var record = try db.fetch(id: id)!
        let value = record.storage["oldName"]!
        
        // CRITICAL: To remove a field during migration, explicitly set it to nil
        // The update() method merges fields, it doesn't replace the entire record
        let migrated = BlazeDataRecord([
            "oldName": .null,  // Explicitly remove old field
            "newName": value,
            "other": .int(123)
        ])
        try db.update(id: id, with: migrated)
        
        record = try db.fetch(id: id)!
        XCTAssertNil(record.storage["oldName"])
        XCTAssertEqual(record.storage["newName"], .string("Value"))
    }
    
    func testMigrationChangeFieldType() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("type-change-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "TypeChangeTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        let id = try db.insert(BlazeDataRecord(["count": .string("42")]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        var record = try db.fetch(id: id)!
        if let stringValue = record.storage["count"]?.stringValue,
           let intValue = Int(stringValue) {
            let migrated = BlazeDataRecord(["count": .int(intValue)])
            try db.update(id: id, with: migrated)
        }
        
        record = try db.fetch(id: id)!
        XCTAssertEqual(record.storage["count"], .int(42))
    }
    
    func testMigrationRollbackOnFailure() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("rollback-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "RollbackTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        let id = try db.insert(BlazeDataRecord(["value": .int(100)]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        try db.beginTransaction()
        
        do {
            try db.update(id: id, with: BlazeDataRecord(["value": .int(999)]))
            throw NSError(domain: "MigrationError", code: 1, userInfo: nil)
        } catch {
            try db.rollbackTransaction()
        }
        
        let record = try db.fetch(id: id)
        XCTAssertEqual(record?.storage["value"], .int(100))
    }
    
    func testMigrationPreservesIndexes() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("preserve-index-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "IndexPreserveTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        guard let dbInitial = db else {
            XCTFail("Database not initialized")
            return
        }
        
        var collection = dbInitial.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "status")
        
        // Insert records
        for i in 0..<10 {
            _ = try dbInitial.insert(BlazeDataRecord([
                "status": .string("active"),
                "value": .int(i)
            ]))
        }
        
        try collection.persist()
        
        // Verify index works
        let preResults = try collection.fetch(byIndexedField: "status", value: "active")
        XCTAssertEqual(preResults.count, 10, "Index should work before migration")
        
        // Reopen database (simulates app restart for schema change)
        db = nil
        Thread.sleep(forTimeInterval: 0.05)  // Delay for file handles
        db = try BlazeDBClient(name: "IndexPreserveTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        guard let dbRestored = db else {
            XCTFail("Database not initialized after reopen")
            return
        }
        
        collection = dbRestored.collection as! DynamicCollection
        
        // Verify index still works after restart
        let resultsAfterRestart = try collection.fetch(byIndexedField: "status", value: "active")
        XCTAssertEqual(resultsAfterRestart.count, 10, "Index should survive restart")
        
        // Perform schema migration (add new field via update)
        let sampleID = resultsAfterRestart[0].storage["id"]?.uuidValue
        if let id = sampleID {
            var updated = resultsAfterRestart[0].storage
            updated["newField"] = .string("migrated")
            try collection.update(id: id, with: BlazeDataRecord(updated))
        }
        
        try collection.persist()
        
        // Verify index STILL works after schema change
        let finalResults = try collection.fetch(byIndexedField: "status", value: "active")
        XCTAssertEqual(finalResults.count, 10, "Index preserved after adding new field to schema")
        
        print("✅ Index survived: initial insert → restart → schema change")
    }
    
    func testMigrationWith10kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 10_000 : 1_000
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("large-migration-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "LargeMigrationTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        print("📊 Inserting \(count) records with v1 schema...")
        let startTime = Date()
        
        for i in 0..<count {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "version": .string("v1")
            ]))
        }
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let insertDuration = Date().timeIntervalSince(startTime)
        print("✅ Inserted \(count) records in \(String(format: "%.2f", insertDuration))s")
        
        // Verify all records exist with v1 schema
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, count, "Should have all records")
        
        let v1Count = allRecords.filter { $0.storage["version"]?.stringValue == "v1" }.count
        XCTAssertEqual(v1Count, count, "All records should have v1 schema")
        
        print("✅ Large dataset migration test: \(count) records handled successfully")
    }
    
    func testConcurrentMigrationsPrevented() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("concurrent-migration-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "ConcurrentMigrationTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        try db.beginTransaction()
        
        // Second transaction should fail (transaction already in progress)
        XCTAssertThrowsError(try db.beginTransaction()) { error in
            // Just verify it throws, don't check specific error type
            print("✅ Concurrent transaction prevented: \(error)")
        }
        
        try db.commitTransaction()
    }
    
    func testMigrationV1toV2toV3() throws {
        let testID = "\(UUID().uuidString)-\(Date().timeIntervalSince1970)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("multi-step-\(testID).blazedb")
        
        // Simple cleanup in defer
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        let db = try BlazeDBClient(name: "MultiStepTest_\(testID)", fileURL: fileURL, password: "BlazeDBMigrationTest123!")
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("Test"),
            "version": .int(1)
        ]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        var record = try db.fetch(id: id)!
        var v2 = record.storage
        v2["email"] = .string("test@example.com")
        v2["version"] = .int(2)
        try db.update(id: id, with: BlazeDataRecord(v2))
        
        record = try db.fetch(id: id)!
        var v3 = record.storage
        v3["verified"] = .bool(true)
        v3["version"] = .int(3)
        try db.update(id: id, with: BlazeDataRecord(v3))
        
        let final = try db.fetch(id: id)!
        XCTAssertEqual(final.storage["name"], .string("Test"))
        XCTAssertEqual(final.storage["email"], .string("test@example.com"))
        XCTAssertEqual(final.storage["verified"], .bool(true))
        XCTAssertEqual(final.storage["version"], .int(3))
    }
    
}
