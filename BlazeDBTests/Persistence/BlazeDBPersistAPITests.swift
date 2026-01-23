//  BlazeDBPersistAPITests.swift
//  BlazeDBTests
//  Created by Michael Danylchuk on 11/6/25.

import XCTest
@testable import BlazeDBCore
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif

final class BlazeDBPersistAPITests: XCTestCase {
    
    // Generate unique URL per test to avoid conflicts
    func makeTestURL() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("persist-test-\(UUID().uuidString).blazedb")
    }
    
    func cleanupTestURL(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - persist() Tests
    
    func testPersistForcesMetadataFlush() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        do {
            let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
            
            // Insert 50 records (below 100 threshold)
            for i in 0..<50 {
                _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
            }
            
            // Force flush before closing
            try db.persist()
        }
        
        // Reopen in new scope - should see all 50 records
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 50, "All records should persist after explicit flush")
        
        // Verify records have correct indexes
        let indexes = Set(records.compactMap { $0.storage["index"]?.intValue })
        XCTAssertEqual(indexes.count, 50, "All 50 unique indexes should be present")
    }
    
    func testFlushAliasToPersist() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert records
        for i in 0..<30 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Use flush() alias
        try db.flush()
        
        // Reopen and verify
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 30, "flush() should work identically to persist()")
    }
    
    func testPersistWithoutChanges() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Persist with no changes - should not throw
        XCTAssertNoThrow(try db.persist())
        
        // Insert one record
        _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // Persist again
        XCTAssertNoThrow(try db.persist())
        
        // Persist multiple times
        XCTAssertNoThrow(try db.persist())
        XCTAssertNoThrow(try db.persist())
    }
    
    func testPersistAfterUpdates() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert and get ID
        let id = try db.insert(BlazeDataRecord(["value": .int(1)]))
        try db.persist()
        
        // Update 20 times (below threshold)
        for i in 2...20 {
            try db.update(id: id, with: BlazeDataRecord(["value": .int(i)]))
        }
        
        // Force flush
        try db.persist()
        
        // Reopen and verify latest value
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let record = try db2.fetch(id: id)
        
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.storage["value"]?.intValue, 20, "Latest update should persist")
    }
    
    func testPersistAfterDeletes() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert records
        var ids: [UUID] = []
        for i in 0..<10 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        try db.persist()
        
        // Delete half
        for i in 0..<5 {
            try db.delete(id: ids[i])
        }
        
        // Force flush
        try db.persist()
        
        // Reopen and verify
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 5, "Only non-deleted records should remain")
    }
    
    func testPersistWithIndexes() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Create index
        if let collection = db.collection as? DynamicCollection {
            try collection.createIndex(on: ["status"])
        }
        
        // Insert records (below threshold)
        for i in 0..<25 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ]))
        }
        
        // Force flush
        try db.persist()
        
        // Reopen and verify index works
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        if let collection = db2.collection as? DynamicCollection {
            let active = try collection.fetch(byIndexedField: "status", value: "active")
            XCTAssertGreaterThan(active.count, 0, "Index should work after persist+reopen")
        }
    }
    
    func testMultiplePersistCalls() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert in batches with persist after each
        for batch in 0..<5 {
            for i in 0..<20 {
                _ = try db.insert(BlazeDataRecord([
                    "batch": .int(batch),
                    "index": .int(i)
                ]))
            }
            try db.persist()
        }
        
        // Reopen and verify all records
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 100, "Multiple persist calls should work correctly")
    }
    
    func testPersistBeforeCriticalOperation() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert records
        for i in 0..<75 {
            _ = try db!.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Persist before backup (critical operation)
        try db!.persist()
        
        // Close database before backing up files
        db = nil
        
        // Create backup
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString).blazedb")
        let backupMetaURL = backupURL.deletingPathExtension().appendingPathExtension("meta")
        let backupIndexesURL = backupURL.deletingPathExtension().appendingPathExtension("meta.indexes")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupMetaURL)
            try? FileManager.default.removeItem(at: backupIndexesURL)
        }
        
        // Copy all related files
        try FileManager.default.copyItem(at: tempURL, to: backupURL)
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.copyItem(at: metaURL, to: backupMetaURL)
        }
        let indexesURL = tempURL.deletingPathExtension().appendingPathExtension("meta.indexes")
        if FileManager.default.fileExists(atPath: indexesURL.path) {
            try FileManager.default.copyItem(at: indexesURL, to: backupIndexesURL)
        }
        
        // Verify backup is complete
        let dbBackup = try BlazeDBClient(name: "Backup", fileURL: backupURL, password: "test1234")
        let backupRecords = try dbBackup.fetchAll()
        
        XCTAssertEqual(backupRecords.count, 75, "Backup should contain all records after persist")
    }
    
    func testPersistIdempotent() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // Multiple persist calls should be safe
        try db.persist()
        try db.persist()
        try db.persist()
        
        let records = try db.fetchAll()
        XCTAssertEqual(records.count, 1, "Multiple persist calls should not duplicate data")
    }
    
    func testPersistDoesNotThrowOnNormalOperation() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // persist() should not throw under normal conditions
        XCTAssertNoThrow(try db.persist(), "persist() should succeed under normal conditions")
        
        // Verify data persisted correctly
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path), "Metadata file should exist after persist")
        
        // Verify we can read it back
        let layout = try? StorageLayout.load(from: metaURL)
        XCTAssertNotNil(layout, "Should be able to load persisted layout")
        XCTAssertEqual(layout?.indexMap.count, 1, "Should have 1 record in persisted layout")
    }
    
    // MARK: - Performance Tests
    
    func testPersistPerformance() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert 1000 records
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Measure persist time
        let start = Date()
        try db.persist()
        let duration = Date().timeIntervalSince(start)
        
        // Should be fast (< 100ms for 1000 records)
        XCTAssertLessThan(duration, 0.1, "persist() should be fast")
    }
    
    func testAutomaticFlushAt100Operations() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert exactly 100 records (should trigger automatic flush)
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // NO explicit persist() call
        
        // Reopen immediately - should see all 100
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 100, "Automatic flush at 100 ops should work")
    }
    
    func testManualPersistBeforeThreshold() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert only 10 records (way below 100 threshold)
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Without persist(), these might not be visible on reopen
        // But WITH persist(), they should be
        try db.persist()
        
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 10, "Manual persist should work before automatic threshold")
    }
}

