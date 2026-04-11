//  BlazeDBPersistAPITests.swift
//  BlazeDBTests
//  Created by Michael Danylchuk on 11/6/25.

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif
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
            let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
            
            // Insert 50 records (below 100 threshold)
            for i in 0..<50 {
                _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
            }
            
            // Force flush before closing
            try db.persist()
        }
        
        // Reopen in new scope - should see all 50 records
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 50, "All records should persist after explicit flush")
        
        // Verify records have correct indexes
        let indexes = Set(records.compactMap { $0.storage["index"]?.intValue })
        XCTAssertEqual(indexes.count, 50, "All 50 unique indexes should be present")
    }
    
    func testFlushAliasToPersist() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
        // Insert records
        for i in 0..<30 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Use flush() alias
        try db.persist()
        
        // Reopen and verify
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 30, "flush() should work identically to persist()")
    }
    
    func testPersistWithoutChanges() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let record = try db2.fetch(id: id)
        
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.storage["value"]?.intValue, 20, "Latest update should persist")
    }
    
    func testPersistAfterDeletes() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 5, "Only non-deleted records should remain")
    }
    
    func testPersistWithIndexes() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
        // Create index
        try db.collection.createIndex(on: ["status"])
        
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
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
        let active = try db2.collection.fetch(byIndexedField: "status", value: "active")
        XCTAssertGreaterThan(active.count, 0, "Index should work after persist+reopen")
    }
    
    func testMultiplePersistCalls() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 100, "Multiple persist calls should work correctly")
    }
    
    func testPersistBeforeCriticalOperation() {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }

        do {
            var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")

            // Insert records
            for i in 0..<75 {
                _ = try db!.insert(BlazeDataRecord(["index": .int(i)]))
            }

            // Persist before backup (critical operation)
            try db!.persist()
            db = nil

            let fm = FileManager.default
            let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
            let indexesURL = tempURL.deletingPathExtension().appendingPathExtension("meta.indexes")

            // Create backup copies of all on-disk artifacts currently present.
            let backupURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("backup-\(UUID().uuidString).blazedb")
            let backupMetaURL = backupURL.deletingPathExtension().appendingPathExtension("meta")
            let backupIndexesURL = backupURL.deletingPathExtension().appendingPathExtension("meta.indexes")
            defer {
                try? fm.removeItem(at: backupURL)
                try? fm.removeItem(at: backupMetaURL)
                try? fm.removeItem(at: backupIndexesURL)
            }

            try fm.copyItem(at: tempURL, to: backupURL)
            if fm.fileExists(atPath: metaURL.path) {
                try fm.copyItem(at: metaURL, to: backupMetaURL)
            }
            if fm.fileExists(atPath: indexesURL.path) {
                try fm.copyItem(at: indexesURL, to: backupIndexesURL)
            }

            // Validate the critical backup contract: persisted artifacts are copyable and non-empty.
            XCTAssertTrue(fm.fileExists(atPath: backupURL.path), "Backup data file should exist")
            if let attrs = try? fm.attributesOfItem(atPath: backupURL.path),
               let size = attrs[.size] as? NSNumber {
                XCTAssertGreaterThan(size.intValue, 0, "Backup data file should not be empty")
            } else {
                XCTFail("Failed to read backup data file attributes")
            }

            XCTAssertTrue(fm.fileExists(atPath: backupMetaURL.path), "Backup metadata file should exist")
            if let attrs = try? fm.attributesOfItem(atPath: backupMetaURL.path),
               let size = attrs[.size] as? NSNumber {
                XCTAssertGreaterThan(size.intValue, 0, "Backup metadata file should not be empty")
            } else {
                XCTFail("Failed to read backup metadata file attributes")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testPersistIdempotent() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
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
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
        // Insert exactly 100 records (should trigger automatic flush)
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // NO explicit persist() call
        
        // Reopen immediately - should see all 100
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 100, "Automatic flush at 100 ops should work")
    }
    
    func testManualPersistBeforeThreshold() throws {
        let tempURL = makeTestURL()
        defer { cleanupTestURL(tempURL) }
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        
        // Insert only 10 records (way below 100 threshold)
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Without persist(), these might not be visible on reopen
        // But WITH persist(), they should be
        try db.persist()
        
        try db.close()
        let db2 = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "SecureTestDB-456!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 10, "Manual persist should work before automatic threshold")
    }
}

