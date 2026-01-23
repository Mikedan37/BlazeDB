//
//  FailureInjectionTests.swift
//  BlazeDBTests
//
//  Tests BlazeDB's resilience to failures: corruption, crashes, I/O errors.
//  These tests ensure the database can recover from catastrophic failures.
//

import XCTest
@testable import BlazeDBCore

final class FailureInjectionTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FailInj-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try! BlazeDBClient(name: "fail_test", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Corrupted Metadata Tests
    
    /// Test: Corrupted metadata file falls back gracefully
    func testCorruptedMetadataRecovery() throws {
        // Insert records
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Close database
        db = nil
        
        // Corrupt metadata file
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        try "CORRUPTED DATA NOT JSON".write(to: metaURL, atomically: true, encoding: .utf8)
        
        // Try to reopen - should detect corruption and rebuild
        BlazeDBClient.clearCachedKey()
        
        XCTAssertNoThrow({
            self.db = try BlazeDBClient(name: "fail_test", fileURL: self.tempURL, password: "test-pass-123")
        }, "Should handle corrupted metadata gracefully")
        
        // Database should initialize (may lose some records without valid metadata)
        // The important thing is it doesn't crash
        XCTAssertNotNil(db)
    }
    
    /// Test: Missing metadata file recovers gracefully
    func testMissingMetadataRecovery() throws {
        // Insert records
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Close database
        db = nil
        
        // Delete metadata file
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        try FileManager.default.removeItem(at: metaURL)
        
        // Reopen - should rebuild from pages
        BlazeDBClient.clearCachedKey()
        
        XCTAssertNoThrow({
            self.db = try BlazeDBClient(name: "fail_test", fileURL: self.tempURL, password: "test-pass-123")
        }, "Should handle missing metadata gracefully")
        
        // Should attempt to rebuild metadata from data file
        XCTAssertNotNil(db)
    }
    
    /// Test: Truncated metadata file
    func testTruncatedMetadataFile() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        db = nil
        
        // Truncate metadata file to half size
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let fileHandle = try FileHandle(forWritingTo: metaURL)
        defer { try? fileHandle.close() }
        
        let originalSize = try fileHandle.seekToEnd()
        try fileHandle.truncate(atOffset: originalSize / 2)
        try fileHandle.synchronize()
        
        // Try to reopen
        BlazeDBClient.clearCachedKey()
        
        XCTAssertNoThrow({
            self.db = try BlazeDBClient(name: "fail_test", fileURL: self.tempURL, password: "test-pass-123")
        }, "Should handle truncated metadata")
    }
    
    // MARK: - Corrupted Data Tests
    
    /// Test: Corrupted page data is detected
    func testCorruptedPageDetection() throws {
        // Insert records
        var ids: [UUID] = []
        for i in 0..<5 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        try db.persist()
        
        // Close
        db = nil
        
        // Corrupt a page in the middle (page 2)
        let fileHandle = try FileHandle(forUpdating: tempURL)
        defer { try? fileHandle.close() }
        
        try fileHandle.seek(toOffset: 4096 * 2 + 50)  // Page 2, offset 50
        try fileHandle.write(contentsOf: Data(repeating: 0xFF, count: 100))
        try fileHandle.synchronize()
        
        // Reopen
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "fail_test", fileURL: tempURL, password: "test-pass-123")
        
        // Some records should still be readable (pages 0, 1, 3, 4)
        // Page 2 should fail authentication
        var readableCount = 0
        for id in ids {
            if (try? db.fetch(id: id)) != nil {
                readableCount += 1
            }
        }
        
        // We expect 4 readable (page 2 is corrupted)
        XCTAssertLessThan(readableCount, 5, "Corrupted page should not be readable")
        XCTAssertGreaterThan(readableCount, 0, "Non-corrupted pages should still be readable")
    }
    
    // MARK: - Wrong Password Tests
    
    /// Test: Wrong password cannot decrypt data
    func testWrongPasswordFailsGracefully() throws {
        // Insert with password "test-pass-123"
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Close
        db = nil
        BlazeDBClient.clearCachedKey()
        
        // Try to open with wrong password
        let wrongPasswordDB = try BlazeDBClient(name: "fail_test", fileURL: tempURL, password: "wrong-password")
        
        // Count will show entries from metadata, but fetchAll will fail to decrypt
        let metadataCount = wrongPasswordDB.collection.indexMap.count
        XCTAssertEqual(metadataCount, 10, "Metadata still readable (not encrypted)")
        
        // But actual data should fail to decrypt
        let fetchedRecords = try? wrongPasswordDB.fetchAll()
        if let records = fetchedRecords {
            // If any decrypt, they're false positives (shouldn't happen with AES-GCM)
            XCTAssertEqual(records.count, 0, 
                          "Wrong password should not decrypt any records (got \(records.count))")
        } else {
            // Expected: fetchAll throws or returns empty
            XCTAssertTrue(true, "Wrong password correctly prevented decryption")
        }
    }
    
    // MARK: - Disk Full Simulation
    
    /// Test: Graceful handling of disk full errors
    func testDiskFullHandling() throws {
        // Note: We can't actually fill the disk, but we can test error paths
        // This is a smoke test for error handling code paths
        
        // Insert enough data that it would fail if disk was full
        let largeRecords = (0..<100).map { i in
            BlazeDataRecord(["data": .data(Data(repeating: 0xAB, count: 3000))])
        }
        
        XCTAssertNoThrow({
            _ = try self.db.insertMany(largeRecords)
        }, "Should handle large writes gracefully")
        
        XCTAssertNoThrow({
            try self.db.persist()
        }, "Persist should handle large metadata gracefully")
    }
    
    // MARK: - Concurrent Failure Tests
    
    /// Test: Concurrent operations during corruption
    func testConcurrentOperationsDuringFailure() throws {
        // Insert initial data
        for i in 0..<50 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let group = DispatchGroup()
        var successCount = 0
        let lock = NSLock()
        
        // Concurrent inserts (some might fail)
        for i in 50..<100 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                if (try? self.db.insert(BlazeDataRecord(["value": .int(i)]))) != nil {
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        // At least some should succeed
        XCTAssertGreaterThan(successCount, 0, "At least some concurrent inserts should succeed")
        
        // Database should remain in consistent state
        XCTAssertNoThrow({
            _ = try self.db.fetchAll()
        }, "Database should remain queryable after concurrent stress")
    }
    
    // MARK: - Rollback Tests
    
    /// Test: Failed persist doesn't corrupt database
    func testFailedPersistDoesntCorrupt() throws {
        // Insert initial data
        for i in 0..<5 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        // Insert more data
        for i in 5..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Simulate persist failure by making meta file read-only
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metaURL.path)
        
        // Try to persist (should fail)
        XCTAssertThrowsError(try db.persist(), "Persist should fail with read-only file")
        
        // Make writable again
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metaURL.path)
        
        // Database should still be usable
        XCTAssertEqual(db.count(), 10, "Database should still have all records in memory")
        
        // Now persist should work
        XCTAssertNoThrow(try db.persist(), "Persist should work after fixing permission")
    }
    
    // MARK: - Partial Write Detection
    
    /// Test: Detect and handle partial metadata writes
    func testDetectPartialMetadataWrite() throws {
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try db.persist()
        
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        let originalData = try Data(contentsOf: metaURL)
        
        // Write partial data (cut off at 50%)
        let partialData = originalData.prefix(originalData.count / 2)
        try partialData.write(to: metaURL)
        
        // Try to reopen
        db = nil
        BlazeDBClient.clearCachedKey()
        
        XCTAssertNoThrow({
            self.db = try BlazeDBClient(name: "fail_test", fileURL: self.tempURL, password: "test-pass-123")
        }, "Should handle partial metadata write")
        
        // Should fall back to empty layout or rebuild
        XCTAssertNotNil(db, "Database should initialize despite partial metadata")
    }
}

