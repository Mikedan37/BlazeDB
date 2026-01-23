//
//  MVCCFoundationTests.swift
//  BlazeDBTests
//
//  Tests for MVCC foundation: versioning, snapshots, GC
//
//  Created: 2025-11-13
//

import XCTest
@testable import BlazeDBCore

final class MVCCFoundationTests: XCTestCase {
    
    var versionManager: VersionManager!
    
    override func setUp() {
        super.setUp()
        versionManager = VersionManager()
    }
    
    override func tearDown() {
        versionManager = nil
        super.tearDown()
    }
    
    // MARK: - Version Management Tests
    
    func testVersionNumberIncreases() {
        let v1 = versionManager.nextVersion()
        let v2 = versionManager.nextVersion()
        let v3 = versionManager.nextVersion()
        
        XCTAssertEqual(v1, 1)
        XCTAssertEqual(v2, 2)
        XCTAssertEqual(v3, 3)
    }
    
    func testAddAndRetrieveVersion() {
        let recordID = UUID()
        let version = RecordVersion(
            recordID: recordID,
            version: 1,
            pageNumber: 42,
            createdByTransaction: 1
        )
        
        versionManager.addVersion(version)
        
        let retrieved = versionManager.getVersion(recordID: recordID, snapshot: 1)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.recordID, recordID)
        XCTAssertEqual(retrieved?.version, 1)
        XCTAssertEqual(retrieved?.pageNumber, 42)
    }
    
    func testMultipleVersionsOfSameRecord() {
        let recordID = UUID()
        
        // Version 1
        let v1 = RecordVersion(
            recordID: recordID,
            version: 1,
            pageNumber: 10,
            createdByTransaction: 1
        )
        versionManager.addVersion(v1)
        
        // Version 2
        let v2 = RecordVersion(
            recordID: recordID,
            version: 2,
            pageNumber: 20,
            createdByTransaction: 2
        )
        versionManager.addVersion(v2)
        
        // Version 3
        let v3 = RecordVersion(
            recordID: recordID,
            version: 3,
            pageNumber: 30,
            createdByTransaction: 3
        )
        versionManager.addVersion(v3)
        
        // Snapshot at version 1 sees version 1
        let s1 = versionManager.getVersion(recordID: recordID, snapshot: 1)
        XCTAssertEqual(s1?.version, 1)
        XCTAssertEqual(s1?.pageNumber, 10)
        
        // Snapshot at version 2 sees version 2
        let s2 = versionManager.getVersion(recordID: recordID, snapshot: 2)
        XCTAssertEqual(s2?.version, 2)
        XCTAssertEqual(s2?.pageNumber, 20)
        
        // Snapshot at version 3 sees version 3
        let s3 = versionManager.getVersion(recordID: recordID, snapshot: 3)
        XCTAssertEqual(s3?.version, 3)
        XCTAssertEqual(s3?.pageNumber, 30)
    }
    
    // MARK: - Snapshot Isolation Tests
    
    func testSnapshotIsolation() {
        let recordID = UUID()
        
        // Transaction 1 starts (snapshot at version 0)
        let snapshot1 = versionManager.getCurrentVersion()
        
        // Transaction 2 writes (version 1)
        let v1 = RecordVersion(
            recordID: recordID,
            version: 1,
            pageNumber: 100,
            createdByTransaction: 1
        )
        versionManager.addVersion(v1)
        
        // Transaction 1 reads - should NOT see version 1
        let read1 = versionManager.getVersion(recordID: recordID, snapshot: snapshot1)
        XCTAssertNil(read1, "Old snapshot shouldn't see new version")
        
        // Transaction 3 starts (snapshot at version 1)
        let snapshot3 = versionManager.getCurrentVersion()
        
        // Transaction 3 reads - should see version 1
        let read3 = versionManager.getVersion(recordID: recordID, snapshot: snapshot3)
        XCTAssertNotNil(read3)
        XCTAssertEqual(read3?.version, 1)
    }
    
    func testDeletedVersionNotVisible() {
        let recordID = UUID()
        
        // Create version 1
        let v1 = RecordVersion(
            recordID: recordID,
            version: 1,
            pageNumber: 100,
            createdByTransaction: 1,
            deletedByTransaction: 0  // Not deleted
        )
        versionManager.addVersion(v1)
        
        // Delete it in transaction 2
        try! versionManager.deleteVersion(
            recordID: recordID,
            atSnapshot: 1,
            byTransaction: 2
        )
        
        // Snapshot at version 1 should still see it
        let s1 = versionManager.getVersion(recordID: recordID, snapshot: 1)
        XCTAssertNotNil(s1)
        
        // Snapshot at version 2 should NOT see it
        let s2 = versionManager.getVersion(recordID: recordID, snapshot: 2)
        XCTAssertNil(s2, "Deleted version shouldn't be visible after deletion")
    }
    
    // MARK: - Garbage Collection Tests
    
    func testGarbageCollectionWithNoActiveSnapshots() {
        let recordID = UUID()
        
        // Create 5 versions
        for i in 1...5 {
            let v = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i * 10,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        // GC with no active snapshots - should keep only newest
        let removed = versionManager.garbageCollect()
        
        XCTAssertEqual(removed, 4, "Should remove 4 old versions")
        
        // Should still have version 5
        let latest = versionManager.getVersion(recordID: recordID, snapshot: 5)
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.version, 5)
    }
    
    func testGarbageCollectionWithActiveSnapshots() {
        let recordID = UUID()
        
        // Create versions 1-5
        for i in 1...5 {
            let v = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i * 10,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        // Register snapshot at version 3
        versionManager.registerSnapshot(3)
        
        // GC should keep versions 3+ (visible to active snapshot)
        let removed = versionManager.garbageCollect()
        
        XCTAssertGreaterThanOrEqual(removed, 2, "Should remove old versions")
        
        // Should still have versions 3, 4, 5
        XCTAssertNotNil(versionManager.getVersion(recordID: recordID, snapshot: 3))
        XCTAssertNotNil(versionManager.getVersion(recordID: recordID, snapshot: 5))
        
        // Cleanup
        versionManager.unregisterSnapshot(3)
    }
    
    func testMultipleActiveSnapshots() {
        versionManager.registerSnapshot(1)
        versionManager.registerSnapshot(2)
        versionManager.registerSnapshot(2)  // Same snapshot twice
        versionManager.registerSnapshot(3)
        
        XCTAssertEqual(versionManager.getOldestActiveSnapshot(), 1)
        
        versionManager.unregisterSnapshot(1)
        XCTAssertEqual(versionManager.getOldestActiveSnapshot(), 2)
        
        versionManager.unregisterSnapshot(2)
        XCTAssertEqual(versionManager.getOldestActiveSnapshot(), 2)  // Still one 2 left
        
        versionManager.unregisterSnapshot(2)
        XCTAssertEqual(versionManager.getOldestActiveSnapshot(), 3)
        
        versionManager.unregisterSnapshot(3)
        XCTAssertNil(versionManager.getOldestActiveSnapshot())
    }
    
    // MARK: - Statistics Tests
    
    func testVersionStats() {
        // Add some versions
        for i in 1...10 {
            let recordID = UUID()
            let version = RecordVersion(
                recordID: recordID,
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(version)
        }
        
        let stats = versionManager.getStats()
        
        XCTAssertEqual(stats.totalVersions, 10)
        XCTAssertEqual(stats.uniqueRecords, 10)
        XCTAssertEqual(stats.averageVersionsPerRecord, 1.0, accuracy: 0.01)
    }
    
    func testVersionStatsWithMultipleVersions() {
        let recordID1 = UUID()
        let recordID2 = UUID()
        
        // Record 1: 3 versions
        for i in 1...3 {
            let v = RecordVersion(
                recordID: recordID1,
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        // Record 2: 2 versions
        for i in 4...5 {
            let v = RecordVersion(
                recordID: recordID2,
                version: UInt64(i),
                pageNumber: i,
                createdByTransaction: UInt64(i)
            )
            versionManager.addVersion(v)
        }
        
        let stats = versionManager.getStats()
        
        XCTAssertEqual(stats.totalVersions, 5)
        XCTAssertEqual(stats.uniqueRecords, 2)
        XCTAssertEqual(stats.averageVersionsPerRecord, 2.5, accuracy: 0.01)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentReads() {
        let recordID = UUID()
        let version = RecordVersion(
            recordID: recordID,
            version: 1,
            pageNumber: 100,
            createdByTransaction: 1
        )
        versionManager.addVersion(version)
        
        let group = DispatchGroup()
        var successCount = 0
        let lock = NSLock()
        
        // 100 concurrent reads
        for _ in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                if let _ = self.versionManager.getVersion(recordID: recordID, snapshot: 1) {
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        XCTAssertEqual(successCount, 100, "All concurrent reads should succeed")
    }
    
    func testConcurrentVersionAdds() {
        let recordID = UUID()
        let group = DispatchGroup()
        
        // 50 threads adding versions
        for i in 1...50 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                let version = RecordVersion(
                    recordID: recordID,
                    version: UInt64(i),
                    pageNumber: i,
                    createdByTransaction: UInt64(i)
                )
                self.versionManager.addVersion(version)
            }
        }
        
        group.wait()
        
        let stats = versionManager.getStats()
        XCTAssertEqual(stats.totalVersions, 50)
    }
}

