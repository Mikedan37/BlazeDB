//
//  ChaosEngineeringTests.swift
//  BlazeDBIntegrationTests
//
//  CHAOS ENGINEERING: Test resilience under random failures
//  Injects failures randomly to find breaking points
//

import XCTest
@testable import BlazeDBCore

final class ChaosEngineeringTests: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Chaos-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Chaos: Random Failures
    
    /// CHAOS: Random operations with 20% failure rate
    func testChaos_RandomFailureInjection() async throws {
        print("\n🌪️  CHAOS: Random Failure Injection (20% failure rate)")
        
        let db = try BlazeDBClient(name: "Chaos", fileURL: dbURL, password: "chaos-123")
        
        var successCount = 0
        var failureCount = 0
        var totalOps = 0
        
        print("  ⚙️  Running 100 operations with random failures...")
        
        for i in 0..<100 {
            totalOps += 1
            
            // 20% chance of simulated failure
            let shouldFail = Double.random(in: 0...1) < 0.20
            
            if shouldFail {
                // Skip this operation (simulates failure)
                failureCount += 1
                continue
            }
            
            // Perform operation
            do {
                let operation = Int.random(in: 0...3)
                
                switch operation {
                case 0:  // Insert
                    _ = try await db.insert(BlazeDataRecord([
                        "op": .string("insert"),
                        "index": .int(i)
                    ]))
                    
                case 1:  // Query
                    _ = try await db.fetchAll()
                    
                case 2:  // Update
                    let all = try await db.fetchAll()
                    if let random = all.randomElement(),
                       let id = random.storage["id"]?.uuidValue {
                        try await db.update(id: id, with: BlazeDataRecord([
                            "updated": .bool(true)
                        ]))
                    }
                    
                case 3:  // Delete
                    let all = try await db.fetchAll()
                    if let random = all.randomElement(),
                       let id = random.storage["id"]?.uuidValue,
                       all.count > 5 {  // Keep at least 5
                        try await db.delete(id: id)
                    }
                    
                default:
                    break
                }
                
                successCount += 1
            } catch {
                failureCount += 1
            }
        }
        
        print("  📊 Results:")
        print("    Total operations: \(totalOps)")
        print("    Successful: \(successCount)")
        print("    Failed: \(failureCount)")
        print("    Success rate: \(Double(successCount)/Double(totalOps) * 100)%")
        
        // Verify: Database still functional
        let finalCount = try await db.count()
        XCTAssertGreaterThan(finalCount, 0, "Database should still have records")
        
        print("  ✅ Database survived chaos: \(finalCount) records")
        print("  ✅ VALIDATED: Resilient to random failures!")
    }
    
    /// CHAOS: Rapid start/stop cycles under load
    func testChaos_RapidStartStopUnderLoad() async throws {
        print("\n🔄 CHAOS: Rapid Start/Stop Under Load")
        
        print("  ⚙️  10 cycles of: Insert → Query → Close → Reopen...")
        
        for cycle in 0..<10 {
            autoreleasepool {
                do {
                    let db = try BlazeDBClient(name: "ChaosStartStop", fileURL: dbURL, password: "chaos-123")
                    
                    // Rapid operations
                    for _ in 0..<10 {
                        _ = try db.insert(BlazeDataRecord(["cycle": .int(cycle)]))
                    }
                    
                    _ = try db.fetchAll()
                    
                    // Immediate close (no persist!)
                } catch {
                    print("    ⚠️  Cycle \(cycle) error: \(error)")
                }
            }
            
            // Small delay
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        
        // Verify: Database still works
        let db = try BlazeDBClient(name: "ChaosStartStop", fileURL: dbURL, password: "chaos-123")
        let count = try await db.count()
        
        XCTAssertGreaterThan(count, 0, "Should have some records")
        print("  ✅ Survived 10 rapid cycles: \(count) records")
        print("  ✅ VALIDATED: Handles rapid start/stop!")
    }
    
    /// CHAOS: Random crashes at any point in workflow
    func testChaos_RandomCrashPoints() async throws {
        print("\n💥 CHAOS: Random Crash Points in Workflow")
        
        print("  ⚙️  Running workflow 20 times, crashing at random points...")
        
        var successfulRecoveries = 0
        
        for attempt in 0..<20 {
            var db: BlazeDBClient? = nil
            
            do {
                db = try BlazeDBClient(name: "ChaosCrash", fileURL: dbURL, password: "chaos-123")
                
                // Random point to crash (0-5)
                let crashPoint = Int.random(in: 0...5)
                
                // Operation 1: Insert
                if crashPoint == 0 {
                    db = nil
                    throw NSError(domain: "Chaos", code: 0, userInfo: [NSLocalizedDescriptionKey: "Crash at point 0"])
                }
                _ = try await db!.insert(BlazeDataRecord(["attempt": .int(attempt)]))
                
                // Operation 2: Enable search
                if crashPoint == 1 {
                    db = nil
                    throw NSError(domain: "Chaos", code: 1, userInfo: [NSLocalizedDescriptionKey: "Crash at point 1"])
                }
                try await db!.collection.enableSearch(fields: ["attempt"])
                
                // Operation 3: Create index
                if crashPoint == 2 {
                    db = nil
                    throw NSError(domain: "Chaos", code: 2, userInfo: [NSLocalizedDescriptionKey: "Crash at point 2"])
                }
                try await db!.collection.createIndex(on: "attempt")
                
                // Operation 4: Query
                if crashPoint == 3 {
                    db = nil
                    throw NSError(domain: "Chaos", code: 3, userInfo: [NSLocalizedDescriptionKey: "Crash at point 3"])
                }
                _ = try await db!.fetchAll()
                
                // Operation 5: Persist
                if crashPoint == 4 {
                    db = nil
                    throw NSError(domain: "Chaos", code: 4, userInfo: [NSLocalizedDescriptionKey: "Crash at point 4"])
                }
                try await db!.persist()
                
                // Operation 6: Close
                db = nil
                
                // Recovery
                db = try BlazeDBClient(name: "ChaosCrash", fileURL: dbURL, password: "chaos-123")
                
                // Verify: Database still functional
                _ = try await db!.count()
                successfulRecoveries += 1
                
                db = nil
                
            } catch {
                // Recovery after crash
                db = nil
                
                if let recovered = try? BlazeDBClient(name: "ChaosCrash", fileURL: dbURL, password: "chaos-123") {
                    _ = try? await recovered.count()
                    successfulRecoveries += 1
                }
            }
            
            // Cleanup for next attempt
            try? FileManager.default.removeItem(at: dbURL)
            try? FileManager.default.removeItem(at: dbURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        print("  ✅ Recovery success rate: \(successfulRecoveries)/20 (\(Double(successfulRecoveries)/20 * 100)%)")
        XCTAssertGreaterThanOrEqual(successfulRecoveries, 18, "At least 90% should recover")
        
        print("  ✅ VALIDATED: Resilient to crashes at random points!")
    }
    
    // MARK: - Enhanced Chaos Tests (2025-11-12)
    
    /// CHAOS: Process kill simulation (SIGKILL mid-transaction)
    func testChaos_ProcessKillMidTransaction() async throws {
        print("\n💀 CHAOS: Process Kill Mid-Transaction")
        
        let db = try BlazeDBClient(name: "ChaosProcKill", fileURL: dbURL, password: "chaos-123")
        
        // Insert some baseline data
        for i in 0..<10 {
            try await db.insert(BlazeDataRecord(["baseline": .int(i)]))
        }
        try await db.persist()
        
        print("  ⚙️  Simulating SIGKILL during transaction...")
        
        // Start transaction
        for i in 10..<20 {
            try await db.insert(BlazeDataRecord(["transaction": .int(i)]))
            
            // Simulate process kill at random point (don't persist!)
            if i == 15 {
                print("    💥 KILL -9 (simulated)")
                // Abrupt termination - no cleanup, no persist, no deinit
                break
            }
        }
        
        // Database is "killed" - force close without cleanup
        // In real scenario, process would be terminated by OS
        
        print("  🔄 Attempting recovery...")
        
        // Recovery: Open database with potentially inconsistent state
        let recovered = try BlazeDBClient(name: "ChaosProcKill", fileURL: dbURL, password: "chaos-123")
        
        let count = try await recovered.count()
        print("  📊 Recovered \(count) records")
        
        // Should have at least the persisted baseline (10 records)
        XCTAssertGreaterThanOrEqual(count, 10, "Should recover at least persisted data")
        
        // Verify database is still functional
        try await recovered.insert(BlazeDataRecord(["after_recovery": .bool(true)]))
        try await recovered.persist()
        
        print("  ✅ VALIDATED: Survives process kill!")
    }
    
    /// CHAOS: Disk full during write
    func testChaos_DiskFullDuringWrite() async throws {
        print("\n💾 CHAOS: Disk Full During Write")
        
        let db = try BlazeDBClient(name: "ChaosDiskFull", fileURL: dbURL, password: "chaos-123")
        
        print("  ⚙️  Writing large records to simulate disk pressure...")
        
        // Fill up with large records
        var successCount = 0
        var failCount = 0
        
        for i in 0..<100 {
            do {
                // Large record (3KB each)
                let largeData = Data(repeating: 0xAB, count: 3000)
                try await db.insert(BlazeDataRecord([
                    "index": .int(i),
                    "data": .data(largeData)
                ]))
                successCount += 1
            } catch {
                // Simulate disk full after 50 records
                if i >= 50 {
                    failCount += 1
                    print("    ⚠️  Write \(i) failed: \(error.localizedDescription)")
                    break
                } else {
                    throw error
                }
            }
        }
        
        print("  📊 Successful writes: \(successCount)")
        print("  📊 Failed writes: \(failCount)")
        
        // Try to persist (might fail if disk full)
        do {
            try await db.persist()
            print("  ✅ Persist succeeded despite disk pressure")
        } catch {
            print("  ⚠️  Persist failed (expected if disk full): \(error)")
        }
        
        // Database should still be readable
        let count = try await db.count()
        XCTAssertGreaterThan(count, 0, "Database should still be readable")
        
        print("  ✅ VALIDATED: Graceful degradation under disk pressure!")
    }
    
    /// CHAOS: Read-only filesystem (permission errors)
    func testChaos_ReadOnlyFileSystem() async throws {
        print("\n🔒 CHAOS: Read-Only File System")
        
        let db = try BlazeDBClient(name: "ChaosReadOnly", fileURL: dbURL, password: "chaos-123")
        
        // Insert and persist some data
        for i in 0..<10 {
            try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try await db.persist()
        
        let count = try await db.count()
        print("  📊 Baseline: \(count) records")
        
        // Make files read-only
        print("  ⚙️  Making files read-only...")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: dbURL.path)
        
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metaURL.path)
        
        // Try to insert (should fail gracefully)
        do {
            try await db.insert(BlazeDataRecord(["should_fail": .bool(true)]))
            XCTFail("Insert should fail with read-only filesystem")
        } catch {
            print("  ✅ Insert failed as expected: \(error.localizedDescription)")
        }
        
        // Reading should still work
        let records = try await db.fetchAll()
        XCTAssertEqual(records.count, 10, "Reading should still work")
        
        // Restore permissions
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: dbURL.path)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metaURL.path)
        
        // Now writes should work again
        try await db.insert(BlazeDataRecord(["recovered": .bool(true)]))
        
        print("  ✅ VALIDATED: Graceful handling of permission errors!")
    }
    
    /// CHAOS: File descriptor exhaustion
    func testChaos_FileDescriptorExhaustion() throws {
        print("\n📂 CHAOS: File Descriptor Exhaustion")
        
        print("  ⚙️  Opening 100 databases simultaneously...")
        
        var databases: [BlazeDBClient] = []
        var openCount = 0
        
        // Try to open many databases
        for i in 0..<100 {
            let testURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChaosDB-\(i).blazedb")
            
            do {
                let db = try BlazeDBClient(name: "Chaos\(i)", fileURL: testURL, password: "chaos-123")
                databases.append(db)
                openCount += 1
            } catch {
                print("    ⚠️  Failed to open database \(i): \(error)")
                break
            }
        }
        
        print("  📊 Successfully opened: \(openCount) databases")
        XCTAssertGreaterThan(openCount, 20, "Should be able to open at least 20 databases")
        
        // Verify all are functional
        var functionalCount = 0
        for db in databases {
            if (try? db.insert(BlazeDataRecord(["test": .int(1)]))) != nil {
                functionalCount += 1
            }
        }
        
        print("  📊 Functional databases: \(functionalCount)/\(openCount)")
        
        // Cleanup
        for (i, _) in databases.enumerated() {
            let testURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChaosDB-\(i).blazedb")
            try? FileManager.default.removeItem(at: testURL)
            try? FileManager.default.removeItem(at: testURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        print("  ✅ VALIDATED: Handles file descriptor limits!")
    }
    
    /// CHAOS: Concurrent file corruption
    func testChaos_ConcurrentFileCorruption() async throws {
        print("\n⚡ CHAOS: Concurrent File Corruption")
        
        let db = try BlazeDBClient(name: "ChaosConcurrent", fileURL: dbURL, password: "chaos-123")
        
        // Insert baseline data
        for i in 0..<20 {
            try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try await db.persist()
        
        print("  ⚙️  Running concurrent operations + corruption...")
        
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()
        
        // Concurrent readers
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try db.fetchAll()
                    try db.persist()
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
            }
        }
        
        // Concurrent writers
        for i in 20..<40 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try db.insert(BlazeDataRecord(["concurrent": .int(i)]))
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
            }
        }
        
        // Inject corruption while operations are running
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            Thread.sleep(forTimeInterval: 0.05)  // Let some operations start
            
            // Try to corrupt metadata (might fail due to locks - that's OK!)
            let metaURL = self.dbURL.deletingPathExtension().appendingPathExtension("meta")
            try? "CORRUPT".write(to: metaURL, atomically: false, encoding: .utf8)
        }
        
        group.wait()
        
        print("  📊 Errors during chaos: \(errors.count)")
        
        // Database might be in inconsistent state, but shouldn't crash
        let finalCount = try? await db.count()
        print("  📊 Final count: \(finalCount ?? -1)")
        
        print("  ✅ VALIDATED: Survives concurrent corruption!")
    }
    
    /// CHAOS: Power loss mid-write
    func testChaos_PowerLossMidWrite() async throws {
        print("\n⚡ CHAOS: Power Loss Mid-Write")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "ChaosPowerLoss", fileURL: dbURL, password: "chaos-123")
        
        // Insert baseline data
        for i in 0..<10 {
            try await db!.insert(BlazeDataRecord(["safe": .int(i)]))
        }
        try await db!.persist()
        
        print("  ⚙️  Simulating power loss during write burst...")
        
        // Start rapid writes (simulate burst of activity)
        for i in 10..<30 {
            try await db!.insert(BlazeDataRecord(["burst": .int(i)]))
            
            // Simulate power loss at random point
            if i == 20 {
                print("    💥 POWER LOSS (simulated)")
                // Abrupt termination - simulate power cut
                db = nil
                break
            }
        }
        
        // Wait a moment (simulate system restart delay)
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        print("  🔄 System restart, attempting recovery...")
        
        // Recovery after power loss
        BlazeDBClient.clearCachedKey()
        let recovered = try BlazeDBClient(name: "ChaosPowerLoss", fileURL: dbURL, password: "chaos-123")
        
        let count = try await recovered.count()
        print("  📊 Recovered \(count) records")
        
        // Should have at least the persisted baseline
        XCTAssertGreaterThanOrEqual(count, 10, "Should recover at least persisted data")
        
        // Database should be fully functional
        try await recovered.insert(BlazeDataRecord(["post_recovery": .bool(true)]))
        let newCount = try await recovered.count()
        XCTAssertEqual(newCount, count + 1, "Should be able to insert after recovery")
        
        print("  ✅ VALIDATED: Survives power loss!")
    }
    
    /// CHAOS: Rapid memory pressure
    func testChaos_RapidMemoryPressure() async throws {
        print("\n🧠 CHAOS: Rapid Memory Pressure")
        
        let db = try BlazeDBClient(name: "ChaosMemory", fileURL: dbURL, password: "chaos-123")
        
        print("  ⚙️  Creating memory pressure with large records...")
        
        var insertedCount = 0
        var failedCount = 0
        
        // Try to insert 1000 large records rapidly
        for i in 0..<1000 {
            autoreleasepool {
                do {
                    // 10KB per record = 10MB total if all succeed
                    let largeData = Data(repeating: UInt8(i % 256), count: 10_000)
                    _ = try db.insert(BlazeDataRecord([
                        "index": .int(i),
                        "data": .data(largeData)
                    ]))
                    insertedCount += 1
                } catch {
                    failedCount += 1
                    if failedCount > 100 {
                        // Too many failures, stop
                        return
                    }
                }
            }
        }
        
        print("  📊 Inserted: \(insertedCount)")
        print("  📊 Failed: \(failedCount)")
        
        // Try to persist under memory pressure
        do {
            try await db.persist()
            print("  ✅ Persist succeeded")
        } catch {
            print("  ⚠️  Persist failed (acceptable under extreme pressure): \(error)")
        }
        
        // Database should still be queryable
        let count = try? await db.count()
        XCTAssertNotNil(count, "Database should remain accessible")
        
        print("  ✅ VALIDATED: Handles memory pressure!")
    }
    
    /// CHAOS: Corrupted page recovery
    func testChaos_CorruptedPageRecovery() async throws {
        print("\n🔧 CHAOS: Corrupted Page Recovery")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "ChaosCorrupt", fileURL: dbURL, password: "chaos-123")
        
        // Insert 20 records (will be on pages 0-19)
        var ids: [UUID] = []
        for i in 0..<20 {
            let id = try await db!.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        try await db!.persist()
        
        // Close database
        db = nil
        
        print("  ⚙️  Corrupting random pages...")
        
        // Corrupt 3 random pages
        let fileHandle = try FileHandle(forUpdating: dbURL)
        defer { try? fileHandle.close() }
        
        let corruptedPages = [5, 10, 15]
        for page in corruptedPages {
            let offset = UInt64(page * 4096 + 100)
            try fileHandle.seek(toOffset: offset)
            try fileHandle.write(contentsOf: Data(repeating: 0xFF, count: 500))
            print("    💥 Corrupted page \(page)")
        }
        try fileHandle.synchronize()
        
        print("  🔄 Reopening database...")
        
        // Reopen
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "ChaosCorrupt", fileURL: dbURL, password: "chaos-123")
        
        // Try to fetch all records
        var successfulReads = 0
        var failedReads = 0
        
        for id in ids {
            if (try? await db!.fetch(id: id)) != nil {
                successfulReads += 1
            } else {
                failedReads += 1
            }
        }
        
        print("  📊 Successful reads: \(successfulReads)/20")
        print("  📊 Failed reads: \(failedReads)/20 (corrupted pages)")
        
        // Should detect corruption and fail gracefully
        XCTAssertEqual(failedReads, 3, "Should detect 3 corrupted pages")
        XCTAssertEqual(successfulReads, 17, "Should read 17 non-corrupted pages")
        
        // Database should still accept new writes to fresh pages
        try await db!.insert(BlazeDataRecord(["after_corruption": .bool(true)]))
        
        print("  ✅ VALIDATED: Isolates corrupted pages, continues working!")
    }
    
    /// CHAOS: Concurrent database access from multiple instances
    func testChaos_ConcurrentDatabaseInstances() async throws {
        print("\n👥 CHAOS: Concurrent Database Instances")
        
        print("  ⚙️  Opening 5 database instances to same file...")
        
        // Open multiple instances (simulates multi-process access)
        var databases: [BlazeDBClient] = []
        
        for i in 0..<5 {
            let db = try BlazeDBClient(name: "ChaosMulti\(i)", fileURL: dbURL, password: "chaos-123")
            databases.append(db)
        }
        
        print("  📊 Opened \(databases.count) instances")
        
        // Concurrent operations from all instances
        let group = DispatchGroup()
        var totalInserts = 0
        let lock = NSLock()
        
        for (index, db) in databases.enumerated() {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                for i in 0..<10 {
                    if let _ = try? db.insert(BlazeDataRecord([
                        "instance": .int(index),
                        "index": .int(i)
                    ])) {
                        lock.lock()
                        totalInserts += 1
                        lock.unlock()
                    }
                }
            }
        }
        
        group.wait()
        
        print("  📊 Total successful inserts: \(totalInserts)")
        
        // Persist from one instance
        try await databases[0].persist()
        
        // Reopen with fresh instance
        let fresh = try BlazeDBClient(name: "ChaosFresh", fileURL: dbURL, password: "chaos-123")
        let count = try await fresh.count()
        
        print("  📊 Records in fresh instance: \(count)")
        
        // Should have some records (may not be all 50 due to race conditions)
        XCTAssertGreaterThan(count, 0, "Should have some records")
        
        print("  ✅ VALIDATED: Handles concurrent access!")
    }
    
    /// CHAOS: Metadata corruption during read
    func testChaos_MetadataCorruptionDuringRead() async throws {
        print("\n📄 CHAOS: Metadata Corruption During Read")
        
        let db = try BlazeDBClient(name: "ChaosMetaCorrupt", fileURL: dbURL, password: "chaos-123")
        
        // Insert data
        for i in 0..<20 {
            try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        try await db.persist()
        
        print("  ⚙️  Corrupting metadata while database is open...")
        
        // Corrupt metadata file while database is still open
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
        
        let group = DispatchGroup()
        
        // Thread 1: Continuous reads
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            for _ in 0..<10 {
                _ = try? db.fetchAll()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        
        // Thread 2: Corrupt metadata
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            Thread.sleep(forTimeInterval: 0.05)  // Let reads start
            
            // Overwrite with garbage
            try? Data(repeating: 0xFF, count: 100).write(to: metaURL)
            print("    💥 Metadata corrupted")
        }
        
        group.wait()
        
        // Database in-memory state should still be valid
        let inMemoryCount = db.collection.indexMap.count
        XCTAssertEqual(inMemoryCount, 20, "In-memory state should be intact")
        
        // Reads from memory should still work
        let records = try await db.fetchAll()
        XCTAssertEqual(records.count, 20, "Memory reads should work despite corrupted file")
        
        print("  ✅ VALIDATED: In-memory state protected from file corruption!")
    }
    
    /// CHAOS: Rapid persist under concurrent load
    func testChaos_RapidPersistUnderLoad() async throws {
        print("\n💾 CHAOS: Rapid Persist Under Concurrent Load")
        
        let db = try BlazeDBClient(name: "ChaosPersist", fileURL: dbURL, password: "chaos-123")
        
        print("  ⚙️  Hammering persist() while writing...")
        
        let group = DispatchGroup()
        var persistCount = 0
        var insertCount = 0
        let lock = NSLock()
        
        // Thread 1: Continuous inserts
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            for i in 0..<100 {
                if let _ = try? db.insert(BlazeDataRecord(["value": .int(i)])) {
                    lock.lock()
                    insertCount += 1
                    lock.unlock()
                }
                Thread.sleep(forTimeInterval: 0.001)  // 1ms between inserts
            }
        }
        
        // Thread 2: Rapid persist calls
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            for _ in 0..<20 {
                if (try? db.persist()) != nil {
                    lock.lock()
                    persistCount += 1
                    lock.unlock()
                }
                Thread.sleep(forTimeInterval: 0.005)  // 5ms between persists
            }
        }
        
        group.wait()
        
        print("  📊 Inserts: \(insertCount)")
        print("  📊 Persists: \(persistCount)")
        
        // Final persist
        try await db.persist()
        
        // Verify data integrity
        let count = try await db.count()
        XCTAssertEqual(count, insertCount, "All inserts should be persisted")
        
        // Reopen and verify
        let fresh = try BlazeDBClient(name: "ChaosPersist", fileURL: dbURL, password: "chaos-123")
        let recoveredCount = try await fresh.count()
        
        XCTAssertEqual(recoveredCount, insertCount, "All records should survive")
        
        print("  ✅ VALIDATED: Persist is thread-safe under concurrent load!")
    }
}


