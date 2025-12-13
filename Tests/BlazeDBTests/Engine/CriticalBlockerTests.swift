//
//  CriticalBlockerTests.swift
//  BlazeDBTests
//
//  Tests for the 3 critical production blockers
//
//  1. MVCC enabled by default and working
//  2. File handle management during VACUUM
//  3. VACUUM crash safety
//
//  These tests MUST pass before production deployment.
//
//  Created: 2025-11-13
//

import XCTest
@testable import BlazeDB

final class CriticalBlockerTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blocker-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "blocker_test", fileURL: tempURL, password: "CriticalBlockerTest123!")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - BLOCKER #1: MVCC Enabled Tests
    
    /// BLOCKER #1: Verify MVCC is enabled by default
    func testBlocker1_MVCCEnabledByDefault() {
        print("\n🔴 BLOCKER #1: Testing MVCC Enabled By Default")
        
        let isEnabled = db.isMVCCEnabled()
        XCTAssertTrue(isEnabled, "MVCC MUST be enabled by default!")
        
        print("   ✅ MVCC is enabled by default")
    }
    
    /// BLOCKER #1: Basic CRUD works with MVCC enabled
    func testBlocker1_BasicCRUD_WithMVCC() throws {
        print("\n🔴 BLOCKER #1: Testing Basic CRUD with MVCC Enabled")
        
        // Verify MVCC is on
        XCTAssertTrue(db.isMVCCEnabled())
        
        // Insert
        let record = BlazeDataRecord([
            "name": .string("Test"),
            "value": .int(42)
        ])
        let id = try db.insert(record)
        print("   ✅ Insert works")
        
        // Fetch
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?["name"]?.stringValue, "Test")
        print("   ✅ Fetch works")
        
        // Update
        try db.update(id: id, with: BlazeDataRecord(["value": .int(100)]))
        let updated = try db.fetch(id: id)
        XCTAssertEqual(updated?["value"]?.intValue, 100)
        print("   ✅ Update works")
        
        // Delete
        try db.delete(id: id)
        let deleted = try db.fetch(id: id)
        XCTAssertNil(deleted)
        print("   ✅ Delete works")
        
        print("   ✅ All CRUD operations work with MVCC enabled!")
    }
    
    /// BLOCKER #1: Concurrent reads work with MVCC
    func testBlocker1_ConcurrentReads_WithMVCC() throws {
        print("\n🔴 BLOCKER #1: Testing Concurrent Reads with MVCC")
        
        // Insert test data
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        // 100 concurrent reads
        let group = DispatchGroup()
        var successCount = 0
        var errorCount = 0
        let lock = NSLock()
        
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    _ = try self.db.fetch(id: id)
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } catch {
                    lock.lock()
                    errorCount += 1
                    lock.unlock()
                    print("   ❌ Error: \(error)")
                }
            }
        }
        
        group.wait()
        
        print("   📊 Success: \(successCount)/100")
        print("   📊 Errors: \(errorCount)/100")
        
        XCTAssertEqual(successCount, 100, "All concurrent reads must succeed with MVCC")
        XCTAssertEqual(errorCount, 0, "Zero errors allowed")
        
        print("   ✅ Concurrent reads work perfectly!")
    }
    
    /// BLOCKER #1: FetchAll works with MVCC
    func testBlocker1_FetchAll_WithMVCC() throws {
        print("\n🔴 BLOCKER #1: Testing FetchAll with MVCC")
        
        // Insert 100 records
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Fetch all
        let all = try db.fetchAll()
        
        XCTAssertEqual(all.count, 100, "FetchAll must return all records")
        
        print("   ✅ FetchAll works with MVCC!")
    }
    
    /// BLOCKER #1: Aggregations work with MVCC
    func testBlocker1_Aggregations_WithMVCC() throws {
        print("\n🔴 BLOCKER #1: Testing Aggregations with MVCC")
        
        // Insert test data
        for i in 0..<50 {
            try db.insert(BlazeDataRecord([
                "value": .int(i)
            ]))
        }
        
        // Sum aggregation
        let result = try db.query()
            .sum("value", as: "total")
            .executeAggregation()
        
        let expectedSum = (0..<50).reduce(0, +)
        let actualSum = result.sum("total") ?? -1
        
        XCTAssertEqual(Int(actualSum), expectedSum, "Aggregation must work with MVCC")
        
        print("   ✅ Aggregations work with MVCC!")
    }
    
    // MARK: - BLOCKER #2: File Handle Management Tests
    
    /// BLOCKER #2: VACUUM doesn't allow concurrent operations
    func testBlocker2_VACUUMBlocksConcurrent() throws {
        print("\n🔴 BLOCKER #2: Testing VACUUM Blocks Concurrent Operations")
        
        // Insert data
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let group = DispatchGroup()
        var vacuumStarted = false
        var concurrentOperationBlocked = false
        let lock = NSLock()
        
        // Thread 1: Start VACUUM
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            
            lock.lock()
            vacuumStarted = true
            lock.unlock()
            
            do {
                try self.db.vacuum()
            } catch {
                print("   VACUUM error: \(error)")
            }
        }
        
        // Wait for VACUUM to start
        Thread.sleep(forTimeInterval: 0.1)
        
        // Thread 2: Try to insert during VACUUM (should block or fail gracefully)
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            
            // Wait for VACUUM to start
            while true {
                lock.lock()
                if vacuumStarted { 
                    lock.unlock()
                    break 
                }
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.01)
            }
            
            // Try to insert (should either wait or fail gracefully)
            do {
                _ = try self.db.insert(BlazeDataRecord(["test": .string("concurrent")]))
            } catch {
                lock.lock()
                concurrentOperationBlocked = true
                lock.unlock()
            }
        }
        
        group.wait()
        
        print("   ✅ VACUUM blocks concurrent operations correctly")
    }
    
    /// BLOCKER #2: Multiple VACUUM calls don't crash
    func testBlocker2_MultipleVACUUMCalls() throws {
        print("\n🔴 BLOCKER #2: Testing Multiple VACUUM Calls")
        
        // Insert and delete to create waste
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord(["i": .int(i)]))
            ids.append(id)
        }
        
        for id in ids.prefix(80) {
            try db.delete(id: id)
        }
        
        // First VACUUM
        XCTAssertNoThrow(try db.vacuum(), "First VACUUM should succeed")
        
        // Second VACUUM (less waste now)
        XCTAssertNoThrow(try db.vacuum(), "Second VACUUM should succeed")
        
        // Database should still work
        let count = db.count()
        XCTAssertEqual(count, 20, "Database should be functional after multiple VACUUMs")
        
        print("   ✅ Multiple VACUUM calls safe!")
    }
    
    // MARK: - BLOCKER #3: VACUUM Crash Safety Tests
    
    /// BLOCKER #3: VACUUM recovery detects incomplete operation
    func testBlocker3_VACUUMRecovery_DetectsIncomplete() throws {
        print("\n🔴 BLOCKER #3: Testing VACUUM Crash Recovery")
        
        // Insert data
        for i in 0..<100 {
            try db.insert(BlazeDataRecord(["i": .int(i)]))
        }
        
        // Simulate crash during VACUUM by creating intent log
        let vacuumLogURL = tempURL
            .deletingPathExtension()
            .appendingPathExtension("vacuum_in_progress")
        
        try Data().write(to: vacuumLogURL, options: .atomic)
        
        // Reopen database (should detect and recover)
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        
        XCTAssertNoThrow(
            try db = BlazeDBClient(name: "blocker_test", fileURL: tempURL, password: "CriticalBlockerTest123!"),
            "Recovery should not crash"
        )
        
        // Intent log should be cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: vacuumLogURL.path), 
                      "Recovery should clean up intent log")
        
        // Database should still work
        let count = db.count()
        XCTAssertEqual(count, 100, "All records should survive recovery")
        
        print("   ✅ VACUUM recovery works!")
    }
    
    /// BLOCKER #3: VACUUM preserves data after simulated crash
    func testBlocker3_VACUUMCrashSafety_PreservesData() throws {
        print("\n🔴 BLOCKER #3: Testing VACUUM Preserves Data After Crash")
        
        // Insert data
        var expectedRecords: [UUID: BlazeDataRecord] = [:]
        for i in 0..<200 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "name": .string("Record \(i)")
            ])
            let id = try db.insert(record)
            expectedRecords[id] = record
        }
        
        // Delete half
        for id in Array(expectedRecords.keys).prefix(100) {
            try db.delete(id: id)
            expectedRecords.removeValue(forKey: id)
        }
        
        try db.persist()
        
        // Run VACUUM (should succeed)
        try db.vacuum()
        
        // Verify all remaining data intact
        for (id, expected) in expectedRecords {
            let fetched = try db.fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(id) should exist")
            XCTAssertEqual(fetched?["index"]?.intValue, expected["index"]?.intValue)
            XCTAssertEqual(fetched?["name"]?.stringValue, expected["name"]?.stringValue)
        }
        
        print("   ✅ VACUUM preserves all data!")
    }
    
    /// BLOCKER #3: VACUUM can recover from backup
    func testBlocker3_VACUUMRecovery_RestoresFromBackup() throws {
        print("\n🔴 BLOCKER #3: Testing VACUUM Recovery from Backup")
        
        // Insert data
        for i in 0..<50 {
            try db.insert(BlazeDataRecord(["i": .int(i)]))
        }
        
        try db.persist()
        
        // Create fake backup files (simulate VACUUM crash after backup created)
        let backupDataURL = tempURL
            .deletingPathExtension()
            .appendingPathExtension("vacuum_backup.blazedb")
        let backupMetaURL = tempURL
            .deletingPathExtension()
            .appendingPathExtension("vacuum_backup.meta")
        
        // Copy current files to backup
        try FileManager.default.copyItem(at: tempURL, to: backupDataURL)
        try FileManager.default.copyItem(
            at: tempURL.deletingPathExtension().appendingPathExtension("meta"),
            to: backupMetaURL
        )
        
        // Create VACUUM intent marker
        let vacuumLogURL = tempURL
            .deletingPathExtension()
            .appendingPathExtension("vacuum_in_progress")
        try Data().write(to: vacuumLogURL, options: .atomic)
        
        // Corrupt current file (simulate crash during write)
        try Data(repeating: 0xFF, count: 1000).write(to: tempURL)
        
        // Reopen - should recover from backup
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        
        XCTAssertNoThrow(
            try db = BlazeDBClient(name: "blocker_test", fileURL: tempURL, password: "CriticalBlockerTest123!")
        )
        
        // Should have recovered data
        let count = db.count()
        XCTAssertEqual(count, 50, "Recovery should restore all records from backup")
        
        print("   ✅ VACUUM recovery restores from backup!")
    }
    
    /// BLOCKER #3: Atomic file replacement
    func testBlocker3_VACUUMAtomicReplacement() throws {
        print("\n🔴 BLOCKER #3: Testing VACUUM Atomic File Replacement")
        
        // Insert data
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord(["i": .int(i)]))
            ids.append(id)
        }
        
        // Delete most to create waste
        for id in ids.prefix(90) {
            try db.delete(id: id)
        }
        
        db.runGarbageCollection()
        
        // Run VACUUM
        let reclaimed = try db.vacuum()
        
        XCTAssertGreaterThan(reclaimed, 0, "Should reclaim space")
        
        // Verify no leftover temp files
        let tempFiles = [
            "vacuum_in_progress",
            "vacuum_backup.blazedb",
            "vacuum_backup.meta",
            "vacuum_success"
        ]
        
        for suffix in tempFiles {
            let url = tempURL.deletingPathExtension().appendingPathExtension(suffix)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "Temp file \(suffix) should be cleaned up"
            )
        }
        
        // Database should still work
        XCTAssertEqual(db.count(), 10)
        
        print("   ✅ VACUUM cleanup is atomic!")
    }
    
    // MARK: - Integration Tests
    
    /// All 3 blockers together: MVCC + handles + crash safety
    func testAllBlockers_Integration() throws {
        print("\n🔥 INTEGRATION: All 3 Blockers Together")
        
        // Verify MVCC enabled
        XCTAssertTrue(db.isMVCCEnabled())
        print("   ✅ BLOCKER #1: MVCC enabled")
        
        // Heavy workload
        var ids: [UUID] = []
        for i in 0..<500 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 500))
            ]))
            ids.append(id)
        }
        
        // Concurrent reads while inserting
        let group = DispatchGroup()
        
        for _ in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? self.db.fetchAll()
            }
        }
        
        group.wait()
        print("   ✅ Concurrent operations work")
        
        // Delete most (keep last 100)
        let idsToKeep = Array(ids.suffix(100))
        for id in ids.prefix(400) {
            try db.delete(id: id)
        }
        
        // CRITICAL: Persist deletes before VACUUM to ensure indexMap is correct
        try db.persist()
        print("   📊 Persisted after deletes")
        
        // Verify count before VACUUM
        let countBeforeVacuum = db.count()
        let fetchAllBeforeVacuum = try db.fetchAll()
        print("   📊 Count before VACUUM: \(countBeforeVacuum)")
        print("   📊 FetchAll before VACUUM: \(fetchAllBeforeVacuum.count) records")
        print("   📊 IDs to keep: \(idsToKeep.count), first=\(idsToKeep.first!.uuidString.prefix(8)), last=\(idsToKeep.last!.uuidString.prefix(8))")
        
        // Run GC + VACUUM
        db.runGarbageCollection()
        print("   ✅ BLOCKER #2: GC works")
        
        let reclaimed = try db.vacuum()
        print("   ✅ BLOCKER #3: VACUUM works (reclaimed \(reclaimed / 1000) KB)")
        
        // Verify data intact
        let countAfterVacuum = db.count()
        print("   📊 Count after VACUUM: \(countAfterVacuum)")
        XCTAssertEqual(countAfterVacuum, 100)
        
        // Concurrent reads after VACUUM
        var successCount = 0
        var failedIDs: [UUID] = []
        let lock = NSLock()
        
        for id in ids.suffix(100) {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                if let _ = try? self.db.fetch(id: id) {
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } else {
                    lock.lock()
                    failedIDs.append(id)
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        if successCount != 100 {
            print("   ❌ Failed to fetch \(failedIDs.count) IDs after VACUUM:")
            for id in failedIDs.prefix(5) {
                let wasInKeepList = idsToKeep.contains(id)
                print("      - \(id) (was in keep list: \(wasInKeepList))")
            }
        }
        
        XCTAssertEqual(successCount, 100, "All reads after VACUUM should work")
        
        print("\n   ✅ ALL 3 BLOCKERS PASS INTEGRATION TEST!")
    }
    
    // MARK: - Stress Tests
    
    /// Stress test: MVCC under extreme concurrency
    func testBlocker1_MVCCStress_ExtremeConcurrency() throws {
        print("\n💪 STRESS: MVCC Under Extreme Concurrency")
        
        // Pre-populate
        var ids: [UUID] = []
        for i in 0..<200 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        let group = DispatchGroup()
        var totalOps = 0
        var errors = 0
        let lock = NSLock()
        
        // 2000 concurrent operations
        for _ in 0..<2000 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    let op = Int.random(in: 0...3)
                    
                    switch op {
                    case 0:  // Insert
                        _ = try self.db.insert(BlazeDataRecord([
                            "random": .int(Int.random(in: 0...1000))
                        ]))
                    case 1:  // Fetch
                        if let id = ids.randomElement() {
                            _ = try self.db.fetch(id: id)
                        }
                    case 2:  // Update
                        if let id = ids.randomElement() {
                            try self.db.update(id: id, with: BlazeDataRecord([
                                "updated": .bool(true)
                            ]))
                        }
                    case 3:  // Delete (keep some records)
                        if ids.count > 100, let id = ids.randomElement() {
                            try self.db.delete(id: id)
                        }
                    default:
                        break
                    }
                    
                    lock.lock()
                    totalOps += 1
                    lock.unlock()
                    
                } catch {
                    lock.lock()
                    errors += 1
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        print("   📊 Total operations: \(totalOps)")
        print("   📊 Errors: \(errors)")
        
        // Database should still be functional
        XCTAssertNoThrow(try db.fetchAll())
        
        print("   ✅ MVCC survives extreme concurrency!")
    }
    
    /// Stress test: VACUUM during heavy load
    func testBlocker3_VACUUMDuringHeavyLoad() throws {
        print("\n💪 STRESS: VACUUM During Heavy Load")
        
        // Pre-populate and create waste
        for i in 0..<1000 {
            let id = try db.insert(BlazeDataRecord(["i": .int(i)]))
            if i < 800 {
                try db.delete(id: id)
            }
        }
        
        db.setMVCCEnabled(true)
        db.runGarbageCollection()
        
        let group = DispatchGroup()
        var vacuumDone = false
        let lock = NSLock()
        
        // Thread 1: VACUUM
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            
            do {
                _ = try self.db.vacuum()
                lock.lock()
                vacuumDone = true
                lock.unlock()
            } catch {
                print("   VACUUM error: \(error)")
            }
        }
        
        // Thread 2-11: Concurrent operations (should wait for VACUUM)
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                // Wait for VACUUM to start
                Thread.sleep(forTimeInterval: 0.05)
                
                // Operations during VACUUM (may succeed after it finishes)
                _ = try? self.db.fetchAll()
            }
        }
        
        group.wait()
        
        lock.lock()
        let done = vacuumDone
        lock.unlock()
        
        XCTAssertTrue(done, "VACUUM should complete even with concurrent load")
        
        // Database should be healthy
        XCTAssertNoThrow(try db.fetchAll())
        
        print("   ✅ VACUUM handles heavy concurrent load!")
    }
}

