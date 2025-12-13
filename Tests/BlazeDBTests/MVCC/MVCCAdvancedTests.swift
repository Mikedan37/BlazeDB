//
//  MVCCAdvancedTests.swift
//  BlazeDBTests
//
//  Phase 3 & 4: Conflict resolution, retry logic, and automatic GC
//
//  Created: 2025-11-13
//

import XCTest
@testable import BlazeDB

final class MVCCAdvancedTests: XCTestCase {
    
    var versionManager: VersionManager!
    var gcManager: AutomaticGCManager!
    
    override func setUp() {
        super.setUp()
        versionManager = VersionManager()
        gcManager = AutomaticGCManager(versionManager: versionManager)
    }
    
    override func tearDown() {
        versionManager = nil
        gcManager = nil
        super.tearDown()
    }
    
    // MARK: - Phase 3: Conflict Resolution Tests
    
    func testConflictDetection() {
        let recordID = UUID()
        let resolver = ConflictResolver(strategy: .abort, versionManager: versionManager)
        
        // Add version 1
        let v1 = RecordVersion(
            recordID: recordID,
            version: 1,
            pageNumber: 10,
            createdByTransaction: 1
        )
        versionManager.addVersion(v1)
        
        // No conflict at snapshot 1
        let conflict1 = resolver.detectConflict(recordID: recordID, snapshotVersion: 1)
        XCTAssertNil(conflict1, "No conflict when snapshot matches current")
        
        // Add version 2
        let v2 = RecordVersion(
            recordID: recordID,
            version: 2,
            pageNumber: 20,
            createdByTransaction: 2
        )
        versionManager.addVersion(v2)
        
        // Conflict detected at snapshot 1 (version 2 is newer)
        let conflict2 = resolver.detectConflict(recordID: recordID, snapshotVersion: 1)
        XCTAssertNotNil(conflict2, "Should detect conflict when newer version exists")
        XCTAssertEqual(conflict2?.yourVersion, 1)
        XCTAssertEqual(conflict2?.currentVersion, 2)
        
        print("✅ Conflict detection works!")
    }
    
    func testConflictResolutionAbort() {
        let resolver = ConflictResolver(strategy: .abort, versionManager: versionManager)
        
        let conflict = WriteConflict(
            recordID: UUID(),
            yourVersion: 1,
            currentVersion: 2,
            conflictingFields: ["name"]
        )
        
        let yourRecord = BlazeDataRecord(["name": .string("Alice")])
        let currentRecord = BlazeDataRecord(["name": .string("Bob")])
        
        // Abort strategy should throw
        XCTAssertThrowsError(
            try resolver.resolve(conflict: conflict, yourRecord: yourRecord, currentRecord: currentRecord)
        )
        
        print("✅ Abort strategy works!")
    }
    
    func testConflictResolutionLastWriteWins() {
        let resolver = ConflictResolver(strategy: .lastWriteWins, versionManager: versionManager)
        
        let conflict = WriteConflict(
            recordID: UUID(),
            yourVersion: 1,
            currentVersion: 2,
            conflictingFields: ["name"]
        )
        
        let yourRecord = BlazeDataRecord(["name": .string("Alice")])
        let currentRecord = BlazeDataRecord(["name": .string("Bob")])
        
        // Last write wins strategy returns your record
        let resolved = try! resolver.resolve(conflict: conflict, yourRecord: yourRecord, currentRecord: currentRecord)
        XCTAssertEqual(resolved["name"]?.stringValue, "Alice")
        
        print("✅ Last-write-wins strategy works!")
    }
    
    // MARK: - Phase 4: Automatic GC Tests
    
    func testAutomaticGC_TransactionThreshold() {
        var config = MVCCGCConfiguration()
        config.transactionThreshold = 5  // Trigger after 5 transactions
        config.verbose = true
        gcManager.updateConfig(config)
        
        // Add multiple versions for the SAME record (so GC can actually remove old ones)
        let recordID = UUID()
        for i in 1...10 {
            let v = RecordVersion(
                recordID: recordID,  // Same record ID for all versions
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        let statsBefore = versionManager.getStats()
        print("Versions before GC: \(statsBefore.totalVersions)")
        
        // Trigger transactions
        for _ in 0..<5 {
            gcManager.onTransactionCommit()
        }
        
        let statsAfter = versionManager.getStats()
        print("Versions after GC: \(statsAfter.totalVersions)")
        
        // GC should have run at least once
        let gcStats = gcManager.getStats()
        XCTAssertGreaterThan(gcStats.totalRuns, 0, "GC should have run")
        
        print("✅ Automatic GC triggered by transaction threshold!")
    }
    
    func testAutomaticGC_VersionThreshold() {
        var config = MVCCGCConfiguration()
        config.versionThreshold = 2.5  // Trigger when avg > 2.5 versions/record
        config.transactionThreshold = 1000  // Disable transaction trigger
        config.verbose = true
        gcManager.updateConfig(config)
        
        let recordID = UUID()
        
        // Create 5 versions of same record (avg = 5.0)
        for i in 1...5 {
            let v = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        let statsBefore = versionManager.getStats()
        print("Avg versions/record before: \(String(format: "%.2f", statsBefore.averageVersionsPerRecord))")
        
        // Trigger GC check
        gcManager.onTransactionCommit()
        
        let statsAfter = versionManager.getStats()
        print("Avg versions/record after: \(String(format: "%.2f", statsAfter.averageVersionsPerRecord))")
        
        // GC should have reduced versions
        XCTAssertLessThan(statsAfter.averageVersionsPerRecord, statsBefore.averageVersionsPerRecord)
        
        print("✅ Automatic GC triggered by version threshold!")
    }
    
    func testAutomaticGC_ManualTrigger() {
        // Add multiple versions for the SAME record (so GC can actually remove old ones)
        let recordID = UUID()
        for i in 1...20 {
            let v = RecordVersion(
                recordID: recordID,  // Same record ID for all versions
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        let statsBefore = versionManager.getStats()
        
        // Manual GC trigger (with no active snapshots, it should keep only the newest version)
        let removed = gcManager.forceGC()
        
        let statsAfter = versionManager.getStats()
        
        print("Versions removed: \(removed)")
        print("Before: \(statsBefore.totalVersions), After: \(statsAfter.totalVersions)")
        
        // With aggressive GC (no active snapshots), it should remove 19 old versions, keeping only version 20
        XCTAssertGreaterThan(removed, 0, "Should remove old versions")
        XCTAssertLessThan(statsAfter.totalVersions, statsBefore.totalVersions)
        XCTAssertEqual(statsAfter.totalVersions, 1, "Should keep only the newest version")
        
        print("✅ Manual GC trigger works!")
    }
    
    func testAutomaticGC_Statistics() {
        var config = MVCCGCConfiguration()
        config.transactionThreshold = 3
        gcManager.updateConfig(config)
        
        // Add multiple versions for the SAME record (so GC can actually remove old ones)
        let recordID = UUID()
        for i in 1...10 {
            let v = RecordVersion(
                recordID: recordID,  // Same record ID for all versions
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        // Trigger GC multiple times
        for _ in 0..<9 {  // 3 transactions × 3 = 9, should trigger 3 GC runs
            gcManager.onTransactionCommit()
        }
        
        let stats = gcManager.getStats()
        print(stats.description)
        
        XCTAssertGreaterThan(stats.totalRuns, 0, "GC should have run")
        XCTAssertGreaterThan(stats.totalVersionsRemoved, 0, "Should have removed old versions")
        
        print("✅ GC statistics tracking works!")
    }
    
    func testGCConfiguration() {
        var config = MVCCGCConfiguration()
        config.transactionThreshold = 50
        config.versionThreshold = 5.0
        config.timeInterval = 120.0
        config.enabled = true
        config.verbose = true
        
        gcManager.updateConfig(config)
        
        let retrieved = gcManager.getConfig()
        XCTAssertEqual(retrieved.transactionThreshold, 50)
        XCTAssertEqual(retrieved.versionThreshold, 5.0)
        XCTAssertEqual(retrieved.timeInterval, 120.0)
        XCTAssertTrue(retrieved.enabled)
        XCTAssertTrue(retrieved.verbose)
        
        print("✅ GC configuration works!")
    }
    
    // MARK: - Integration Tests
    
    func testMVCC_With_AutoGC_Integration() {
        var config = MVCCGCConfiguration()
        config.transactionThreshold = 10
        config.verbose = true
        gcManager.updateConfig(config)
        
        let recordID = UUID()
        
        // Create many versions
        for i in 1...30 {
            let v = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
            
            // Trigger transaction commit
            gcManager.onTransactionCommit()
        }
        
        let stats = versionManager.getStats()
        let gcStats = gcManager.getStats()
        
        print("Final versions: \(stats.totalVersions)")
        print("GC runs: \(gcStats.totalRuns)")
        print("Versions removed: \(gcStats.totalVersionsRemoved)")
        
        // GC should have run multiple times
        XCTAssertGreaterThan(gcStats.totalRuns, 2, "GC should run multiple times")
        
        // Should have cleaned up old versions
        XCTAssertLessThan(stats.totalVersions, 30, "GC should have reduced version count")
        
        print("✅ MVCC + Auto GC integration works!")
    }
    
    func testGC_MemoryEfficiency() {
        print("\n💾 Testing GC Memory Efficiency")
        
        var config = MVCCGCConfiguration()
        config.transactionThreshold = 50
        config.versionThreshold = 3.0
        gcManager.updateConfig(config)
        
        // Simulate heavy update workload
        let recordID = UUID()
        
        // 100 updates to same record
        for i in 1...100 {
            let v = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
            gcManager.onTransactionCommit()
        }
        
        let stats = versionManager.getStats()
        let gcStats = gcManager.getStats()
        
        print("  Final versions: \(stats.totalVersions)")
        print("  GC runs: \(gcStats.totalRuns)")
        print("  Removed: \(gcStats.totalVersionsRemoved)")
        
        // Without GC: would have 100 versions
        // With GC: should have ~1-5 versions
        XCTAssertLessThan(stats.totalVersions, 10, "GC should keep version count low")
        XCTAssertGreaterThan(gcStats.totalVersionsRemoved, 90, "GC should have removed most old versions")
        
        print("  ✅ GC prevents memory bloat!")
    }
}

