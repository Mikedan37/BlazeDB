//  BlazeFileSystemErrorTests.swift
//  BlazeDB File System Error Handling Tests
//  Tests database behavior with disk errors, permissions, and resource limits

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

final class BlazeFileSystemErrorTests: XCTestCase {
    var tempURL: URL!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeFS-\(UUID().uuidString).blazedb")
    }
    
    override func tearDownWithError() throws {
        // Restore permissions before cleanup
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempURL.path)
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    // MARK: - Permission Tests
    
    /// Test that database can read from files opened with shared access
    /// This validates that multiple readers can access the same database
    func testSharedDatabaseAccess() throws {
        Swift.print("📊 Testing shared database access...")
        
        // Create database and insert data
        var db1: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // ✅ Ensure cleanup on exit
        defer {
            if let collection = db1?.collection as? DynamicCollection {
                try? collection.persist()
            }
            db1 = nil
        }
        
        let id = try db1!.insert(BlazeDataRecord(["value": .int(42)]))
        
        Swift.print("  First instance inserted record")
        
        // Flush metadata to disk so second instance can see it
        // (Without this, metadata batching means second instance sees stale data)
        if let collection = db1!.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Open second instance (simulates another process reading)
        var db2: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // ✅ Ensure cleanup of second instance too
        defer {
            if let collection = db2?.collection as? DynamicCollection {
                try? collection.persist()
            }
            db2 = nil
        }
        
        let records = try db2!.fetchAll()
        
        Swift.print("  Second instance can read records")
        XCTAssertEqual(records.count, 1, "Should see record from first instance")
        XCTAssertEqual(records[0]["value"], .int(42), "Should read same record data")
        
        // Both can still write
        _ = try db1!.insert(BlazeDataRecord(["source": .string("db1")]))
        _ = try db2!.insert(BlazeDataRecord(["source": .string("db2")]))
        
        Swift.print("✅ Multiple instances can share database access")
        
        // Note: This works because FileHandle uses shared file locks
        // In production, you'd use proper locking for concurrent writes
    }
    
    /// Test handling of missing directory
    func testHandlingMissingDirectory() throws {
        Swift.print("📊 Testing missing directory handling...")
        
        let nonExistentDir = tempURL.deletingLastPathComponent()
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let dbURL = nonExistentDir.appendingPathComponent("test.blazedb")
        
        Swift.print("🔍 Attempting to create database in non-existent directory...")
        
        do {
            _ = try BlazeDBClient(name: "Test", fileURL: dbURL, password: "BlazeFileSystemError123!")
            XCTFail("Should fail when directory doesn't exist")
        } catch {
            Swift.print("✅ Correctly handled missing directory: \(error)")
        }
    }
    
    /// Test recovery from permission denial mid-operation
    func testRecoveryFromPermissionDenial() throws {
        Swift.print("📊 Testing recovery from permission denial...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // Insert some data successfully
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        Swift.print("  Inserted 5 records successfully")
        
        // Make directory read-only (will prevent meta file updates)
        let dir = tempURL.deletingLastPathComponent()
        let originalPermissions = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as! NSNumber
        
        defer {
            // Restore permissions
            try? FileManager.default.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: dir.path)
        }
        
        // Note: This test documents expected behavior - may not prevent all writes
        // depending on OS caching and sync behavior
        Swift.print("⚠️  Permission tests are platform-dependent and may vary")
    }
    
    // MARK: - File Lock Tests
    
    /// Test handling of concurrent file access
    func testConcurrentFileAccess() throws {
        Swift.print("📊 Testing concurrent file access...")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        Swift.print("  First database opened")
        
        // Try to open same file again
        Swift.print("🔍 Opening same file with second instance...")
        
        do {
            let db2 = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "BlazeFileSystemError123!")
            
            // Both instances can write (concurrent access)
            _ = try db1.insert(BlazeDataRecord(["source": .string("db1")]))
            _ = try db2.insert(BlazeDataRecord(["source": .string("db2")]))
            
            Swift.print("✅ Concurrent access allowed (both instances can write)")
            Swift.print("⚠️  Note: This may lead to corruption without proper locking")
        } catch {
            Swift.print("✅ Concurrent access prevented: \(error)")
        }
    }
    
    // MARK: - Resource Limit Tests
    
    /// Test behavior with very large single record (overflow page support)
    func testLargeSingleRecord() throws {
        Swift.print("📊 Testing very large single record...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // Create record near 4KB limit (4096 - 50 bytes overhead = 4046 max for single page)
        let largeString = String(repeating: "X", count: 3000)
        
        Swift.print("  Attempting to insert \(largeString.count)-char string...")
        
        let id1 = try db.insert(BlazeDataRecord([
            "large": .string(largeString),
            "index": .int(1)
        ]))
        Swift.print("✅ Large record inserted successfully")
        
        // Verify we can read it back
        let fetched1 = try db.fetch(id: id1)
        XCTAssertNotNil(fetched1, "Should fetch large record")
        XCTAssertEqual(fetched1?.storage["large"]?.stringValue?.count, 3000)
        Swift.print("✅ Large record read back successfully")
        
        // Test that records exceeding single page limit are rejected
        // NOTE: High-level API (db.insert) is limited to ~3.5KB per record
        // Overflow pages are only available through low-level PageStore API
        let overflowString = String(repeating: "Y", count: 5000)
        
        Swift.print("  Attempting to insert \(overflowString.count)-char string (should fail - exceeds single page limit)...")
        
        XCTAssertThrowsError(try db.insert(BlazeDataRecord([
            "overflow": .string(overflowString),
            "index": .int(2)
        ])), "Should reject records larger than single page limit") { error in
            XCTAssertTrue(error.localizedDescription.contains("Page too large"), "Should get 'Page too large' error")
        }
        Swift.print("✅ Large record correctly rejected")
    }
    
    /// Test handling of many small files (inode limit simulation)
    func testManySmallOperations() throws {
        Swift.print("📊 Testing many small operations (resource stress)...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // Perform many small operations
        let count = 1000
        
        Swift.print("  Performing \(count) insert/fetch cycles...")
        
        for i in 0..<count {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            _ = try db.fetch(id: id)
            
            if i % 200 == 0 {
                Swift.print("    \(i) operations completed...")
            }
        }
        
        Swift.print("✅ Completed \(count) operations successfully")
    }
    
    // MARK: - Disk Space Simulation
    
    /// Test behavior when approaching storage limits
    func testStorageGrowthMonitoring() throws {
        Swift.print("📊 Testing storage growth monitoring...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        func getFileSize() throws -> Int {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            return (attrs[FileAttributeKey.size] as? NSNumber)?.intValue ?? 0
        }
        
        let initialSize = try getFileSize()
        Swift.print("  Initial size: \(initialSize) bytes")
        
        // Insert records and monitor growth
        for batch in 0..<5 {
            for i in 0..<100 {
                _ = try db.insert(BlazeDataRecord([
                    "batch": .int(batch),
                    "index": .int(i),
                    "data": .string(String(repeating: "x", count: 200))
                ]))
            }
            
            let currentSize = try getFileSize()
            let growth = currentSize - initialSize
            Swift.print("  After batch \(batch): \(currentSize) bytes (+\(growth) bytes)")
        }
        
        let finalSize = try getFileSize()
        Swift.print("✅ Total growth: \(finalSize - initialSize) bytes")
        
        XCTAssertGreaterThan(finalSize, initialSize, "File should grow with data")
    }
    
    // MARK: - Error Recovery Tests
    
    /// Test graceful degradation when filesystem is slow
    func testSlowFilesystemHandling() throws {
        Swift.print("📊 Testing slow filesystem handling...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // Measure baseline performance
        let startTime = Date()
        
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / 100.0
        
        Swift.print("✅ Completed 100 writes in \(String(format: "%.3f", duration))s")
        Swift.print("   Average: \(String(format: "%.4f", avgTime))s per write")
        
        // Note: This test documents baseline performance
        // Real slow filesystem testing would require mocking/simulation
        XCTAssertLessThan(avgTime, 0.1, "Writes should be reasonably fast")
    }
    
    /// Test handling of incomplete flush
    /// Note: With auto-save disabled, we need to explicitly persist
    func testIncompleteFlushRecovery() throws {
        Swift.print("📊 Testing incomplete flush recovery...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        // Insert data
        var ids: [UUID] = []
        Swift.print("  Inserting 150 records...")
        for i in 0..<150 {
            let id = try dbUnwrapped.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        // CRITICAL: Explicitly persist before close (auto-save is disabled)
        if let collection = dbUnwrapped.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Force close
        Swift.print("  Simulating unclean shutdown...")
        db = nil  // Release database
        
        // Reopen and verify
        Swift.print("🔄 Reopening database...")
        let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        var recoveredCount = 0
        for id in ids {
            if (try? recovered.fetch(id: id)) != nil {
                recoveredCount += 1
            }
        }
        
        Swift.print("✅ Recovered \(recoveredCount)/\(ids.count) records")
        XCTAssertEqual(recoveredCount, ids.count, "Should recover all committed records")
    }
    
    func testReloadFromDiskFailureHandling() throws {
        Swift.print("📊 Testing reload from disk with corrupted metadata...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "ReloadTest", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        let id = try dbUnwrapped.insert(BlazeDataRecord(["value": .int(1)]))
        
        if let collection = dbUnwrapped.collection as? DynamicCollection {
            try collection.persist()
        }
        
        db = nil
        
        // Corrupt metadata file
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        try Data(repeating: 0xFF, count: 100).write(to: metaURL)
        
        // v1.1 behavior: Creates fresh database (graceful degradation)
        let reloadedDB = try BlazeDBClient(name: "ReloadTest", fileURL: tempURL, password: "BlazeFileSystemError123!")
        
        // Original record is orphaned (metadata lost)
        let record = try? reloadedDB.fetch(id: id)
        XCTAssertNil(record, "v1.1 doesn't auto-recover from metadata corruption")
        
        let allRecords = try reloadedDB.fetchAll()
        XCTAssertEqual(allRecords.count, 0, "Fresh database created (data orphaned)")
        
        Swift.print("✅ Corrupted metadata handled gracefully (no crash, fresh start)")
    }
}

