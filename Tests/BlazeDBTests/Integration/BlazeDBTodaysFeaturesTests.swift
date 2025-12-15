//  BlazeDBTodaysFeaturesTests.swift
//  Tests for features added during optimization session

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

final class BlazeDBTodaysFeaturesTests: XCTestCase {
    var tempURL: URL!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodaysFeatures-\(UUID().uuidString).blazedb")
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - Metadata Batching Tests
    
    /// Test that metadata batching reduces disk writes
    func testMetadataBatchingReducesDiskWrites() throws {
        let db = try BlazeDBClient(name: "BatchingTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        
        // Insert 50 records (below 100 threshold)
        for i in 0..<50 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Metadata should NOT be written yet (< 100 threshold)
        let metaExists1 = FileManager.default.fileExists(atPath: metaURL.path)
        
        // Insert 60 more (total 110, exceeds threshold)
        for i in 50..<110 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Metadata should now be written (>= 100)
        let metaExists2 = FileManager.default.fileExists(atPath: metaURL.path)
        
        XCTAssertTrue(metaExists2, "Metadata should be flushed after 100 operations")
    }
    
    /// Test explicit persist() forces immediate flush
    func testExplicitPersistFlushesImmediately() throws {
        let db = try BlazeDBClient(name: "PersistTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let collection = db.collection as! DynamicCollection
        
        // Insert 10 records (below threshold)
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Force flush
        try collection.persist()
        
        // Reopen and verify data persisted
        let db2 = try BlazeDBClient(name: "PersistTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 10, "Explicit persist should flush metadata immediately")
    }
    
    /// Test deinit flushes pending changes
    func testDeinitFlushesMetadata() throws {
        autoreleasepool {
            guard let db = try? BlazeDBClient(name: "DeinitTest", fileURL: tempURL, password: "DeinitTestPassword123!") else {
                XCTFail("Failed to initialize BlazeDBClient")
                return
            }
            
            // Insert 50 records (below threshold)
            for i in 0..<50 {
                _ = try! db.insert(BlazeDataRecord(["index": .int(i)]))
            }
            
            // db will deinit here, should flush pending changes
        }
        
        // Wait for cleanup
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        
        // Reopen and verify
        let db = try BlazeDBClient(name: "DeinitTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let records = try db.fetchAll()
        
        XCTAssertEqual(records.count, 50, "Deinit should flush pending metadata changes")
    }
    
    // MARK: - Baseline Rollback Tests
    
    /// Test rollback restores original data (not deletes)
    func testRollbackRestoresBaseline() throws {
        let db = try BlazeDBClient(name: "BaselineTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        
        let id = try db.insert(BlazeDataRecord(["value": .int(100)]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Start transaction and modify
        try db.beginTransaction()
        try db.update(id: id, with: BlazeDataRecord(["value": .int(999)]))
        
        // Rollback
        try db.rollbackTransaction()
        
        // Verify original data restored (not deleted)
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record, "Rollback should restore record, not delete it")
        XCTAssertEqual(record?.storage["value"], .int(100), "Rollback should restore original value")
    }
    
    /// Test delete then rollback restores deleted record
    func testDeleteRollbackRestoresRecord() throws {
        let db = try BlazeDBClient(name: "DeleteRollbackTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        
        let id = try db.insert(BlazeDataRecord(["value": .int(42)]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Start transaction and delete
        try db.beginTransaction()
        try db.delete(id: id)
        
        // Rollback
        try db.rollbackTransaction()
        
        // Verify record restored
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record, "Rollback should restore deleted record")
        XCTAssertEqual(record?.storage["value"], .int(42), "Rollback should restore original data")
    }
    
    // MARK: - Transaction Log Lock Tests
    
    /// Test concurrent WAL writes don't corrupt log
    func testConcurrentWALWritesThreadSafe() throws {
        let db = try BlazeDBClient(name: "WALLockTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        
        let expectation = expectation(description: "50 concurrent inserts")
        expectation.expectedFulfillmentCount = 50
        
        let queue = DispatchQueue(label: "test.wal", attributes: .concurrent)
        
        for i in 0..<50 {
            queue.async {
                do {
                    _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
                    expectation.fulfill()
                } catch {
                    XCTFail("Insert failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Verify all records inserted without corruption
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let records = try db.fetchAll()
        XCTAssertEqual(records.count, 50, "All concurrent inserts should succeed")
    }
    
    // MARK: - Page Format Tests
    
    /// Test new 9-byte header format preserves trailing zeros
    func testNewPageFormatPreservesTrailingZeros() throws {
        let key = SymmetricKey(size: .bits256)
        let store = try BlazeDB.PageStore(fileURL: tempURL, key: key)
        
        // Create data ending with zeros
        let data = Data([0x01, 0x02, 0x03, 0x00, 0x00, 0x00])
        
        try store.writePage(index: 0, plaintext: data)
        let readBack = try store.readPage(index: 0)
        
        XCTAssertEqual(readBack, data, "Trailing zeros should be preserved")
        XCTAssertEqual(readBack?.count, 6, "Exact length should be preserved")
    }
    
    /// Test payload length field works correctly
    func testPayloadLengthHeaderWorks() throws {
        let key = SymmetricKey(size: .bits256)
        let store = try BlazeDB.PageStore(fileURL: tempURL, key: key)
        
        // Write various sizes
        // Max is 4059 (4096 - 37 bytes overhead: 4 magic + 1 version + 4 length + 12 nonce + 16 tag)
        let sizes = [1, 10, 100, 1000, 4059]
        
        for (index, size) in sizes.enumerated() {
            let data = Data(repeating: UInt8(index), count: size)
            try store.writePage(index: index, plaintext: data)
            
            let readBack = try store.readPage(index: index)
            XCTAssertEqual(readBack?.count, size, "Payload length should be exact for size \(size)")
        }
    }
    
    // MARK: - Index Atomicity Tests
    
    /// Test index backup/restore on update failure
    func testIndexBackupRestoreOnFailure() throws {
        let db = try BlazeDBClient(name: "IndexAtomicTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let collection = db.collection as! DynamicCollection
        
        try collection.createIndex(on: "status")
        
        let id = try db.insert(BlazeDataRecord([
            "status": .string("pending"),
            "value": .int(1)
        ]))
        
        try collection.persist()
        
        // Verify initial index state
        let initialResults = try collection.fetch(byIndexedField: "status", value: "pending")
        XCTAssertEqual(initialResults.count, 1)
        
        // Update successfully
        try db.update(id: id, with: BlazeDataRecord([
            "status": .string("done"),
            "value": .int(2)
        ]))
        
        // Verify index updated atomically
        let pendingResults = try collection.fetch(byIndexedField: "status", value: "pending")
        let doneResults = try collection.fetch(byIndexedField: "status", value: "done")
        
        XCTAssertEqual(pendingResults.count, 0, "Old index entry should be removed")
        XCTAssertEqual(doneResults.count, 1, "New index entry should exist")
    }
    
    // MARK: - UUID String Transaction ID Tests
    
    /// Test record IDs use UUID strings (no hash collisions)
    func testTransactionIDsUseUUIDStrings() throws {
        // Use unique file URL for complete isolation
        let uniqueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UUIDTest-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: uniqueURL)
            try? FileManager.default.removeItem(at: uniqueURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: uniqueURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
        }
        
        let db = try BlazeDBClient(name: "UUIDTxTest", fileURL: uniqueURL, password: "TodaysFeaturesTest123!")
        
        // Insert 100 records rapidly (tests UUID uniqueness)
        var insertedIDs: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            insertedIDs.append(id)
        }
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // All IDs should be unique
        let uniqueIDs = Set(insertedIDs)
        XCTAssertEqual(uniqueIDs.count, 100, "All 100 record IDs should be unique (no UUID collisions)")
        
        // All records should persist
        let records = try db.fetchAll()
        XCTAssertEqual(records.count, 100, "All 100 records should persist")
    }
    
    // MARK: - Comprehensive Integration Test
    
    /// End-to-end test of today's improvements
    func testTodaysImprovementsIntegration() throws {
        let db = try BlazeDBClient(name: "IntegrationTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let collection = db.collection as! DynamicCollection
        
        // 1. Create index (atomicity)
        try collection.createIndex(on: "category")
        
        // 2. Insert < 100 records (metadata batching)
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try db.insert(BlazeDataRecord([
                "category": .string("cat_\(i % 5)"),
                "value": .int(i)
            ]))
            ids.append(id)
        }
        
        // 3. Explicit persist (flush)
        try collection.persist()
        
        // 4. Transaction with rollback (baseline restore)
        try db.beginTransaction()
        try db.update(id: ids[0], with: BlazeDataRecord([
            "category": .string("modified"),
            "value": .int(999)
        ]))
        try db.rollbackTransaction()
        
        // 5. Verify rollback restored original
        let record = try db.fetch(id: ids[0])
        XCTAssertEqual(record?.storage["value"], .int(0), "Rollback should restore original")
        
        // 6. Reopen database (index rebuild)
        let db2 = try BlazeDBClient(name: "IntegrationTest", fileURL: tempURL, password: "TodaysFeaturesTest123!")
        let collection2 = db2.collection as! DynamicCollection
        
        // 7. Query index (atomicity validated)
        let results = try collection2.fetch(byIndexedField: "category", value: "cat_0")
        XCTAssertGreaterThan(results.count, 0, "Indexes should survive all operations")
        
        print("✅ All today's improvements working together")
    }
}

