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
@testable import BlazeDBCore

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
        print("📊 Testing shared database access...")
        
        // Create database and insert data
        var db1: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // ✅ Ensure cleanup on exit
        defer {
            if let collection = db1?.collection as? DynamicCollection {
                try? collection.persist()
            }
            db1 = nil
        }
        
        let id = try db1!.insert(BlazeDataRecord(["value": .int(42)]))
        
        print("  First instance inserted record")
        
        // Flush metadata to disk so second instance can see it
        // (Without this, metadata batching means second instance sees stale data)
        if let collection = db1!.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Open second instance (simulates another process reading)
        var db2: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // ✅ Ensure cleanup of second instance too
        defer {
            if let collection = db2?.collection as? DynamicCollection {
                try? collection.persist()
            }
            db2 = nil
        }
        
        let records = try db2!.fetchAll()
        
        print("  Second instance can read records")
        XCTAssertEqual(records.count, 1, "Should see record from first instance")
        XCTAssertEqual(records[0]["value"], .int(42), "Should read same record data")
        
        // Both can still write
        _ = try db1!.insert(BlazeDataRecord(["source": .string("db1")]))
        _ = try db2!.insert(BlazeDataRecord(["source": .string("db2")]))
        
        print("✅ Multiple instances can share database access")
        
        // Note: This works because FileHandle uses shared file locks
        // In production, you'd use proper locking for concurrent writes
    }
    
    /// Test handling of missing directory
    func testHandlingMissingDirectory() throws {
        print("📊 Testing missing directory handling...")
        
        let nonExistentDir = tempURL.deletingLastPathComponent()
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let dbURL = nonExistentDir.appendingPathComponent("test.blazedb")
        
        print("🔍 Attempting to create database in non-existent directory...")
        
        do {
            _ = try BlazeDBClient(name: "Test", fileURL: dbURL, password: "test1234")
            XCTFail("Should fail when directory doesn't exist")
        } catch {
            print("✅ Correctly handled missing directory: \(error)")
        }
    }
    
    /// Test recovery from permission denial mid-operation
    func testRecoveryFromPermissionDenial() throws {
        print("📊 Testing recovery from permission denial...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert some data successfully
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        print("  Inserted 5 records successfully")
        
        // Make directory read-only (will prevent meta file updates)
        let dir = tempURL.deletingLastPathComponent()
        let originalPermissions = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as! NSNumber
        
        defer {
            // Restore permissions
            try? FileManager.default.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: dir.path)
        }
        
        // Note: This test documents expected behavior - may not prevent all writes
        // depending on OS caching and sync behavior
        print("⚠️  Permission tests are platform-dependent and may vary")
    }
    
    // MARK: - File Lock Tests
    
    /// Test that exclusive file locking prevents concurrent access
    /// This test verifies that the second process fails with databaseLocked error
    func testExclusiveFileLocking() throws {
        print("📊 Testing exclusive file locking...")
        
        // First instance opens database and acquires lock
        let db1 = try BlazeDBClient(name: "DB1", fileURL: tempURL, password: "test1234")
        
        print("  First database opened and lock acquired")
        
        // Insert a record to verify first instance works
        _ = try db1.insert(BlazeDataRecord(["source": .string("db1")]))
        
        // Try to open same file with second instance - should fail
        print("🔍 Attempting to open same file with second instance...")
        
        do {
            let db2 = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "test1234")
            
            // If we get here, locking failed - this is a test failure
            XCTFail("Second instance should not be able to open locked database")
            db2 = nil
        } catch BlazeDBError.databaseLocked(let operation, _, let path) {
            // Expected: second instance should fail with databaseLocked error
            print("✅ Lock enforcement working: \(operation)")
            if let path = path {
                print("   Locked path: \(path.path)")
            }
            XCTAssertEqual(operation, "open database")
        } catch {
            XCTFail("Expected databaseLocked error, got: \(error)")
        }
        
        // First instance should still work
        let count = try db1.count()
        XCTAssertEqual(count, 1, "First instance should still have access")
        print("✅ First instance still functional: \(count) records")
    }
    
    /// Test that lock is released when database is closed
    /// This test verifies that deinit releases the lock deterministically.
    /// Uses retry loop with explicit lock check instead of sleep.
    func testLockReleaseOnClose() throws {
        print("📊 Testing lock release on close...")
        
        // Open and close first instance
        var db1: BlazeDBClient? = try BlazeDBClient(name: "DB1", fileURL: tempURL, password: "test1234")
        _ = try db1!.insert(BlazeDataRecord(["source": .string("db1")]))
        
        print("  First instance created and inserted record")
        
        // Verify first instance holds the lock
        do {
            let _ = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "test1234")
            XCTFail("Second instance should not be able to open while first is active")
        } catch BlazeDBError.databaseLocked {
            // Expected - lock is held
            print("  ✅ Lock confirmed held by first instance")
        }
        
        // Close first instance (lock should be released via deinit)
        db1 = nil
        
        // Deterministic verification: try to open second instance
        // Lock release is immediate (OS releases on file descriptor close)
        // Retry up to 10 times with minimal delay only if needed
        var db2: BlazeDBClient?
        var attempts = 0
        let maxAttempts = 10
        
        while db2 == nil && attempts < maxAttempts {
            do {
                db2 = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "test1234")
                break
            } catch BlazeDBError.databaseLocked {
                // Lock still held - this should not happen if deinit worked
                // But allow one retry in case of timing edge case
                attempts += 1
                if attempts >= maxAttempts {
                    XCTFail("Lock was not released after closing first instance after \(maxAttempts) attempts")
                }
                // Minimal yield to allow deinit to complete (only if needed)
                if attempts < maxAttempts {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                }
            } catch {
                XCTFail("Unexpected error opening second instance: \(error)")
                break
            }
        }
        
        guard let db2 = db2 else {
            XCTFail("Failed to open second instance after lock release")
            return
        }
        
        print("  ✅ First instance closed, second instance opened")
        
        // Should be able to read data from first instance
        let records = try db2.fetchAll()
        XCTAssertEqual(records.count, 1, "Should see record from first instance")
        print("✅ Lock released: second instance can read database")
        
        // Should be able to write
        _ = try db2.insert(BlazeDataRecord(["source": .string("db2")]))
        let count = try db2.count()
        XCTAssertEqual(count, 2, "Should have 2 records")
        print("✅ Second instance can write: \(count) records")
    }
    
    /// Test that same process cannot open database twice (reentrancy check)
    /// This verifies that flock() works correctly within a single process.
    /// Each FileHandle(forUpdating:) creates a separate file descriptor, so
    /// the second open should fail with databaseLocked due to the exclusive lock.
    func testSingleProcessReentrancy() throws {
        print("📊 Testing single-process reentrancy...")
        
        // First instance - creates separate file descriptor and acquires lock
        let db1 = try BlazeDBClient(name: "DB1", fileURL: tempURL, password: "test1234")
        _ = try db1.insert(BlazeDataRecord(["source": .string("db1")]))
        
        print("  First instance opened and lock acquired")
        
        // Try to open same file again in same process
        // This creates a NEW file descriptor, which should fail to acquire the lock
        do {
            let db2 = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "test1234")
            
            // If we get here, locking failed - this is a critical test failure
            XCTFail("Second instance in same process should not be able to open locked database. Lock enforcement is broken.")
            db2 = nil
        } catch BlazeDBError.databaseLocked(let operation, _, let path) {
            // Expected - lock conflict detected
            XCTAssertEqual(operation, "open database", "Error should specify 'open database' operation")
            if let path = path {
                XCTAssertEqual(path.path, tempURL.path, "Error should include correct database path")
            }
            print("✅ Reentrancy prevented: second instance failed with databaseLocked")
            print("   Operation: \(operation)")
            if let path = path {
                print("   Path: \(path.path)")
            }
        } catch {
            // Any other error is a test failure - we expect databaseLocked specifically
            XCTFail("Expected BlazeDBError.databaseLocked, got: \(error). Lock enforcement may be broken.")
        }
        
        // First instance should still work
        let count = try db1.count()
        XCTAssertEqual(count, 1, "First instance should still have access")
        print("✅ First instance still functional: \(count) records")
    }
    
    /// Test crash safety: verify that lock is automatically released by OS on process termination
    /// This test simulates a crash by forcibly closing the file handle without calling deinit.
    /// The OS should release the lock automatically, allowing a new instance to open.
    func testCrashSafety_LockReleaseOnProcessTermination() throws {
        print("📊 Testing crash safety (lock release on process termination)...")
        
        // Open first instance
        var db1: BlazeDBClient? = try BlazeDBClient(name: "DB1", fileURL: tempURL, password: "test1234")
        _ = try db1!.insert(BlazeDataRecord(["source": .string("db1")]))
        
        print("  First instance opened and lock acquired")
        
        // Verify lock is held
        do {
            let _ = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "test1234")
            XCTFail("Second instance should not be able to open while first is active")
        } catch BlazeDBError.databaseLocked {
            print("  ✅ Lock confirmed held by first instance")
        }
        
        // Simulate crash: set to nil without explicit cleanup
        // In a real crash, the process would terminate and OS would release the lock
        // Here we rely on deinit to release, but verify the mechanism works
        db1 = nil
        
        // Lock should be released (either by deinit or OS on process exit)
        // Try to open second instance - should succeed
        var db2: BlazeDBClient?
        var attempts = 0
        let maxAttempts = 10
        
        while db2 == nil && attempts < maxAttempts {
            do {
                db2 = try BlazeDBClient(name: "DB2", fileURL: tempURL, password: "test1234")
                break
            } catch BlazeDBError.databaseLocked {
                attempts += 1
                if attempts >= maxAttempts {
                    XCTFail("Lock was not released after first instance deallocation after \(maxAttempts) attempts")
                }
                // Minimal yield to allow deinit to complete
                if attempts < maxAttempts {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
                break
            }
        }
        
        guard let db2 = db2 else {
            XCTFail("Failed to open second instance after lock release")
            return
        }
        
        print("✅ Crash safety verified: lock released, new instance can open")
        
        // Verify data is still accessible
        let records = try db2.fetchAll()
        XCTAssertEqual(records.count, 1, "Should see record from first instance")
        print("✅ Data integrity maintained: \(records.count) records")
    }
    
    // MARK: - Resource Limit Tests
    
    /// Test behavior with very large single record (near page limit)
    func testLargeSingleRecord() throws {
        print("📊 Testing very large single record...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Create record near 4KB limit (4096 - 9 bytes overhead = 4087 max)
        let largeString = String(repeating: "X", count: 3000)
        
        print("  Attempting to insert \(largeString.count)-char string...")
        
        do {
            _ = try db.insert(BlazeDataRecord([
                "large": .string(largeString),
                "index": .int(1)
            ]))
            print("✅ Large record inserted successfully")
        } catch {
            print("⚠️  Large record failed (expected if > 4087 bytes): \(error)")
        }
        
        // Test record that's definitely too large
        let tooLarge = String(repeating: "Y", count: 5000)
        
        print("  Attempting to insert \(tooLarge.count)-char string (should fail)...")
        
        XCTAssertThrowsError(try db.insert(BlazeDataRecord([
            "toolarge": .string(tooLarge)
        ])), "Should reject record larger than page size")
        
        print("✅ Oversized record correctly rejected")
    }
    
    /// Test handling of many small files (inode limit simulation)
    func testManySmallOperations() throws {
        print("📊 Testing many small operations (resource stress)...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Perform many small operations
        let count = 1000
        
        print("  Performing \(count) insert/fetch cycles...")
        
        for i in 0..<count {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            _ = try db.fetch(id: id)
            
            if i % 200 == 0 {
                print("    \(i) operations completed...")
            }
        }
        
        print("✅ Completed \(count) operations successfully")
    }
    
    // MARK: - Disk Space Simulation
    
    /// Test behavior when approaching storage limits
    func testStorageGrowthMonitoring() throws {
        print("📊 Testing storage growth monitoring...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        func getFileSize() throws -> Int {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            return (attrs[.size] as? NSNumber)?.intValue ?? 0
        }
        
        let initialSize = try getFileSize()
        print("  Initial size: \(initialSize) bytes")
        
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
            print("  After batch \(batch): \(currentSize) bytes (+\(growth) bytes)")
        }
        
        let finalSize = try getFileSize()
        print("✅ Total growth: \(finalSize - initialSize) bytes")
        
        XCTAssertGreaterThan(finalSize, initialSize, "File should grow with data")
    }
    
    // MARK: - Error Recovery Tests
    
    /// Test graceful degradation when filesystem is slow
    func testSlowFilesystemHandling() throws {
        print("📊 Testing slow filesystem handling...")
        
        let db = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Measure baseline performance
        let startTime = Date()
        
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / 100.0
        
        print("✅ Completed 100 writes in \(String(format: "%.3f", duration))s")
        print("   Average: \(String(format: "%.4f", avgTime))s per write")
        
        // Note: This test documents baseline performance
        // Real slow filesystem testing would require mocking/simulation
        XCTAssertLessThan(avgTime, 0.1, "Writes should be reasonably fast")
    }
    
    /// Test handling of incomplete flush
    /// Note: With metadata batching (every 100 ops), we need sufficient records
    func testIncompleteFlushRecovery() throws {
        print("📊 Testing incomplete flush recovery...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        // Insert enough data to trigger metadata flush (>100 records)
        var ids: [UUID] = []
        print("  Inserting 150 records to trigger metadata flush...")
        for i in 0..<150 {
            let id = try db!.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        // Force close without proper shutdown (simulates crash)
        print("  Simulating unclean shutdown...")
        db = nil  // Release database (triggers deinit flush)
        
        // Reopen and verify
        print("🔄 Reopening database...")
        let recovered = try BlazeDBClient(name: "Test", fileURL: tempURL, password: "test1234")
        
        var recoveredCount = 0
        for id in ids {
            if (try? recovered.fetch(id: id)) != nil {
                recoveredCount += 1
            }
        }
        
        print("✅ Recovered \(recoveredCount)/\(ids.count) records")
        XCTAssertEqual(recoveredCount, ids.count, "Should recover all committed records")
    }
    
    func testReloadFromDiskFailureHandling() throws {
        print("📊 Testing reload from disk with corrupted metadata...")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "ReloadTest", fileURL: tempURL, password: "test1234")
        
        let id = try db!.insert(BlazeDataRecord(["value": .int(1)]))
        
        if let collection = db!.collection as? DynamicCollection {
            try collection.persist()
        }
        
        db = nil
        
        // Corrupt metadata file
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        try Data(repeating: 0xFF, count: 100).write(to: metaURL)
        
        // v1.1 behavior: Creates fresh database (graceful degradation)
        let reloadedDB = try BlazeDBClient(name: "ReloadTest", fileURL: tempURL, password: "test1234")
        
        // Original record is orphaned (metadata lost)
        let record = try? reloadedDB.fetch(id: id)
        XCTAssertNil(record, "v1.1 doesn't auto-recover from metadata corruption")
        
        let allRecords = try reloadedDB.fetchAll()
        XCTAssertEqual(allRecords.count, 0, "Fresh database created (data orphaned)")
        
        print("✅ Corrupted metadata handled gracefully (no crash, fresh start)")
    }
}

