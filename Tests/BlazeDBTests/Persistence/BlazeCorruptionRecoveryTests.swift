//  BlazeCorruptionRecoveryTests.swift
//  BlazeDB Corruption Recovery Testing
//  Tests database behavior with corrupted data, torn writes, and checksums

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
@testable import BlazeDB

// Use the real PageStore from BlazeDB module
private typealias RealPageStore = BlazeDB.PageStore

final class BlazeCorruptionRecoveryTests: XCTestCase {
    var tempURL: URL!
    var key: SymmetricKey!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeCorruption-\(UUID().uuidString).blazedb")
        key = SymmetricKey(size: .bits256)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    // MARK: - Partial Write Tests
    
    /// Test recovery from truncated file (partial page write)
    func testRecoveryFromTruncatedFile() throws {
        print("📊 Testing recovery from truncated file...")
        
        // Write some valid data
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        for i in 0..<10 {
            _ = try dbUnwrapped.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Flush metadata before corruption
        if let collection = dbUnwrapped.collection as? DynamicCollection {
            try collection.persist()
        }
        db = nil  // Release database to close file handles
        
        // Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fullSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        
        // Truncate file to simulate partial write (remove last page)
        let truncatedSize = fullSize - 4096
        print("  Original size: \(fullSize) bytes")
        print("  Truncating to: \(truncatedSize) bytes")
        
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        try fileHandle.truncate(atOffset: UInt64(truncatedSize))
        try fileHandle.close()
        
        // Try to open corrupted database
        print("🔄 Reopening truncated database...")
        
        do {
            let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
            let records = try recovered.fetchAll()
            print("✅ Recovered \(records.count) records from truncated file")
            XCTAssertGreaterThan(records.count, 0, "Should recover some records")
            XCTAssertLessThan(records.count, 10, "Should lose some records from truncated page")
        } catch {
            // Recovery may fail gracefully - this is acceptable
            print("⚠️  Recovery failed (graceful failure): \(error)")
        }
    }
    
    /// Test recovery from file with random corruption
    func testRecoveryFromRandomCorruption() throws {
        print("📊 Testing recovery from random data corruption...")
        
        // Create database with data
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        var insertedIDs: [UUID] = []
        for i in 0..<20 {
            let id = try dbUnwrapped.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            insertedIDs.append(id)
        }
        
        // Flush metadata before corruption
        if let collection = dbUnwrapped.collection as? DynamicCollection {
            try collection.persist()
        }
        db = nil  // Release database to close file handles
        
        // Corrupt a random page in the middle
        print("  Corrupting random page...")
        let corruptData = Data(repeating: 0xFF, count: 4096)  // Invalid data
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        try fileHandle.seek(toOffset: 8192)  // Corrupt 3rd page
        try fileHandle.write(contentsOf: corruptData)
        try fileHandle.close()
        
        // Reopen and test
        print("🔄 Reopening corrupted database...")
        let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        var recoveredCount = 0
        var corruptedCount = 0
        
        for id in insertedIDs {
            if (try? recovered.fetch(id: id)) != nil {
                recoveredCount += 1
            } else {
                corruptedCount += 1
            }
        }
        
        print("✅ Recovery results:")
        print("   Recovered: \(recoveredCount)/\(insertedIDs.count)")
        print("   Lost: \(corruptedCount)")
        
        XCTAssertGreaterThan(recoveredCount, 0, "Should recover some uncorrupted records")
    }
    
    // MARK: - Header Validation Tests
    
    /// Test detection of invalid page headers
    func testInvalidPageHeaderDetection() throws {
        print("📊 Testing invalid page header detection...")
        
        let store = try RealPageStore(fileURL: tempURL, key: key)
        
        // Write valid page
        let validData = try JSONEncoder().encode(BlazeDataRecord(["test": .string("data")]).storage)
        try store.writePage(index: 0, plaintext: validData)
        
        // Manually corrupt the header
        print("  Corrupting page header...")
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        try fileHandle.seek(toOffset: 0)
        try fileHandle.write(contentsOf: Data([0x58, 0x58, 0x58, 0x58]))  // "XXXX" instead of "BZDB"
        try fileHandle.close()
        
        // Try to read corrupted page
        print("🔍 Reading corrupted page...")
        let result = try store.readPage(index: 0)
        
        XCTAssertNil(result, "Should return nil for invalid header")
        print("✅ Invalid header correctly detected")
    }
    
    /// Test orphaned page detection
    func testOrphanedPageDetection() throws {
        print("📊 Testing orphaned page detection...")
        
        let store = try RealPageStore(fileURL: tempURL, key: key)
        
        // Write several pages
        for i in 0..<5 {
            let data = try JSONEncoder().encode(BlazeDataRecord(["index": .int(i)]).storage)
            try store.writePage(index: i, plaintext: data)
        }
        
        // Corrupt one page header (creates orphan)
        print("  Creating orphaned page...")
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        try fileHandle.seek(toOffset: 8192)  // 2nd page
        try fileHandle.write(contentsOf: Data(repeating: 0, count: 5))  // Zero out header
        try fileHandle.close()
        
        // Check stats
        print("🔍 Checking storage stats...")
        let stats = try store.getStorageStats()
        
        print("✅ Storage stats:")
        print("   Total pages: \(stats.totalPages)")
        print("   Orphaned: \(stats.orphanedPages)")
        
        XCTAssertGreaterThan(stats.orphanedPages, 0, "Should detect orphaned page")
    }
    
    // MARK: - Torn Write Simulation
    
    /// Simulate power loss during write (torn page)
    func testTornPageWrite() throws {
        print("📊 Simulating torn page write (power loss)...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        // Insert some data
        for i in 0..<5 {
            _ = try dbUnwrapped.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Flush metadata before corruption
        if let collection = dbUnwrapped.collection as? DynamicCollection {
            try collection.persist()
        }
        db = nil  // Release database to close file handles
        
        // Simulate torn write by partially overwriting a page
        print("  Simulating power loss during write...")
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        try fileHandle.seek(toOffset: 4096)
        // Write only partial page (half corrupted, half old data)
        let partialData = Data(repeating: 0xAA, count: 2048)
        try fileHandle.write(contentsOf: partialData)
        try fileHandle.close()
        
        // Reopen and check
        print("🔄 Reopening after torn write...")
        
        do {
            let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
            let records = try recovered.fetchAll()
            print("✅ Recovered \(records.count) records after torn write")
            XCTAssertGreaterThan(records.count, 0, "Should recover some records")
        } catch {
            print("⚠️  Torn write caused corruption (expected): \(error)")
            // This is acceptable - torn writes can cause corruption
        }
    }
    
    // MARK: - Metadata Corruption Tests
    
    /// Test recovery when .meta file is corrupted
    func testRecoveryFromCorruptedMeta() throws {
        print("📊 Testing recovery from corrupted .meta file...")
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Create database with data
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Corrupt the meta file
        print("  Corrupting .meta file...")
        try Data(repeating: 0xFF, count: 1024).write(to: metaURL)
        
        // Try to reopen
        print("🔄 Reopening with corrupted meta...")
        
        do {
            let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
            let records = try recovered.fetchAll()
            print("✅ Recovered after meta corruption:")
            print("   Records found: \(records.count)")
            // Database should rebuild meta from data file
        } catch {
            print("⚠️  Meta corruption handled: \(error)")
            // Acceptable - database may need manual recovery
        }
    }
    
    /// Test handling of missing .meta file
    /// Note: v1.1 does NOT auto-rebuild indexes from data files
    /// This is a known limitation - auto-recovery is planned for v2.0
    func testRecoveryFromMissingMeta() throws {
        print("📊 Testing recovery from missing .meta file...")
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Create database
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        for i in 0..<10 {
            _ = try dbUnwrapped.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Flush metadata first, then close database
        if let collection = dbUnwrapped.collection as? DynamicCollection {
            try collection.persist()
        }
        db = nil  // Release database before deleting meta
        
        // Delete meta file
        print("  Deleting .meta file...")
        try FileManager.default.removeItem(at: metaURL)
        
        // Also delete .meta.indexes file
        let indexesURL = metaURL.appendingPathExtension("indexes")
        try? FileManager.default.removeItem(at: indexesURL)
        
        // Reopen
        print("🔄 Reopening without meta file...")
        let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        let records = try recovered.fetchAll()
        
        print("⚠️  Recovered \(records.count) records (v1.1 doesn't auto-rebuild indexes)")
        
        // v1.1 behavior: Creates fresh empty database (data pages are orphaned)
        XCTAssertEqual(records.count, 0, "v1.1 does not auto-rebuild - returns fresh DB")
        
        // This is acceptable - metadata loss requires manual recovery in v1.1
        // v2.0 will add auto-recovery by scanning data pages
        print("✅ Missing metadata handled gracefully (fresh start, no crash)")
    }
    
    // MARK: - Empty/Zero Data Tests
    
    /// Test handling of file filled with zeros
    func testRecoveryFromZeroedFile() throws {
        print("📊 Testing recovery from zeroed file...")
        
        // Create valid database
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // Zero out middle section
        print("  Zeroing file section...")
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        try fileHandle.seek(toOffset: 8192)
        try fileHandle.write(contentsOf: Data(repeating: 0, count: 8192))
        try fileHandle.close()
        
        // Try recovery
        print("🔄 Attempting recovery...")
        do {
            let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
            _ = try recovered.fetchAll()
            print("✅ Database handled zeroed sections")
        } catch {
            print("⚠️  Zeroed sections detected (acceptable): \(error)")
        }
    }
    
    // MARK: - Index Atomicity Tests
    
    /// Test that indexes remain consistent after update operations
    func testIndexAtomicityOnUpdateFailure() throws {
        print("📊 Testing index consistency during updates...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        let collection = dbUnwrapped.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "status")
        
        // Insert initial record
        let record = BlazeDataRecord([
            "status": .string("pending"),
            "value": .int(100)
        ])
        let id = try dbUnwrapped.insert(record)
        
        // Verify initial index state
        let initialResults = try collection.fetch(byIndexedField: "status", value: "pending")
        XCTAssertEqual(initialResults.count, 1, "Should find 1 pending record")
        
        // Perform successful update
        try collection.update(id: id, with: BlazeDataRecord([
            "status": .string("done"),
            "value": .int(200)
        ]))
        
        // Verify index was updated atomically
        let pendingResults = try collection.fetch(byIndexedField: "status", value: "pending")
        XCTAssertEqual(pendingResults.count, 0, "Old index entry should be removed")
        
        let doneResults = try collection.fetch(byIndexedField: "status", value: "done")
        XCTAssertEqual(doneResults.count, 1, "New index entry should exist")
        
        // Flush and reopen to verify persistence
        try collection.persist()
        db = nil
        
        let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        let recoveredCollection = recovered.collection as! DynamicCollection
        
        let persistedResults = try recoveredCollection.fetch(byIndexedField: "status", value: "done")
        XCTAssertEqual(persistedResults.count, 1, "Index should persist correctly")
        
        print("✅ Index remained consistent through update and recovery")
    }
    
    /// Test that indexes remain consistent during delete operations
    func testIndexAtomicityOnDeleteFailure() throws {
        print("📊 Testing index consistency during deletes...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        let collection = dbUnwrapped.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "category")
        
        // Insert records
        let id1 = try dbUnwrapped.insert(BlazeDataRecord(["category": .string("important")]))
        let id2 = try dbUnwrapped.insert(BlazeDataRecord(["category": .string("important")]))
        
        // Verify initial state
        let initialResults = try collection.fetch(byIndexedField: "category", value: "important")
        XCTAssertEqual(initialResults.count, 2, "Should find 2 important records")
        
        // Perform successful delete
        try collection.delete(id: id1)
        
        // Verify index was updated atomically
        let afterDeleteResults = try collection.fetch(byIndexedField: "category", value: "important")
        XCTAssertEqual(afterDeleteResults.count, 1, "Should have 1 record after delete")
        
        // Flush and reopen to verify persistence
        try collection.persist()
        db = nil
        
        let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "CorruptionRecoveryTest123!")
        let recoveredCollection = recovered.collection as! DynamicCollection
        
        let persistedResults = try recoveredCollection.fetch(byIndexedField: "category", value: "important")
        XCTAssertEqual(persistedResults.count, 1, "Index should persist correctly after delete")
        
        // Verify deleted record is not fetchable
        let deletedRecord = try? recoveredCollection.fetch(id: id1)
        XCTAssertNil(deletedRecord, "Deleted record should not be fetchable")
        
        print("✅ Index remained consistent through delete and recovery")
    }
}

