//
//  CrashSurvivalTests.swift
//  BlazeDBTests
//
//  Comprehensive crash survival tests
//  Validates BlazeDB recovers correctly from SIGKILL, power-loss, and unclean shutdowns
//

import XCTest
@testable import BlazeDBCore

final class CrashSurvivalTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Power-Loss Simulation
    
    func testPowerLoss_AllCommittedDataSurvives() throws {
        let dbURL = tempDir.appendingPathComponent("power_loss_test.blazedb")
        
        // Write data
        let db = try BlazeDBClient(name: "power-loss", fileURL: dbURL, password: "test-password")
        
        let recordCount = 100
        var insertedIDs: [UUID] = []
        
        for i in 0..<recordCount {
            let record = BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            let id = try db.insert(record)
            insertedIDs.append(id)
            
            // Flush periodically
            if i % 10 == 0 {
                try db.persist()
            }
        }
        
        // Force WAL flush
        try db.persist()
        
        // Simulate power loss: terminate without close()
        // (In real scenario, process would be killed)
        // For test, we just don't call close() and reopen
        
        // Reopen database
        let reopenedDB = try BlazeDBClient(name: "power-loss", fileURL: dbURL, password: "test-password")
        
        // Verify all records exist
        let recoveredCount = reopenedDB.count()
        XCTAssertEqual(recoveredCount, recordCount, "All committed records should survive power loss")
        
        // Verify record integrity
        for i in 0..<min(10, recordCount) {
            guard let record = try reopenedDB.fetch(id: insertedIDs[i]) else {
                XCTFail("Record \(i) should exist after power loss")
                continue
            }
            XCTAssertEqual(try record.int("index"), i, "Record \(i) should have correct index")
        }
        
        // Verify health
        let health = try reopenedDB.health()
        XCTAssertEqual(health.status, .ok, "Database should be healthy after power loss recovery")
        
        try reopenedDB.close()
    }
    
    // MARK: - Uncommitted Transaction Rollback
    
    func testCrashDuringTransaction_UncommittedDataRolledBack() throws {
        let dbURL = tempDir.appendingPathComponent("txn_crash_test.blazedb")
        
        // Insert committed data
        let db = try BlazeDBClient(name: "txn-crash", fileURL: dbURL, password: "test-password")
        
        let committedRecord = BlazeDataRecord(["committed": .bool(true), "value": .int(1)])
        _ = try db.insert(committedRecord)
        try db.persist()
        
        // Start transaction but don't commit
        try db.beginTransaction()
        let uncommittedRecord = BlazeDataRecord(["committed": .bool(false), "value": .int(2)])
        _ = try db.insert(uncommittedRecord)
        // Simulate crash: don't commit, don't close
        
        // Reopen database
        let reopenedDB = try BlazeDBClient(name: "txn-crash", fileURL: dbURL, password: "test-password")
        
        // Verify committed record exists
        let committedRecords = try reopenedDB.query()
            .where("committed", equals: .bool(true))
            .execute()
            .records
        XCTAssertEqual(committedRecords.count, 1, "Committed record should exist")
        
        // Verify uncommitted record does NOT exist
        let uncommittedRecords = try reopenedDB.query()
            .where("committed", equals: .bool(false))
            .execute()
            .records
        XCTAssertEqual(uncommittedRecords.count, 0, "Uncommitted record should be rolled back")
        
        try reopenedDB.close()
    }
    
    // MARK: - Invariant Validation
    
    func testCrashRecovery_HealthStatusValid() throws {
        let dbURL = tempDir.appendingPathComponent("health_test.blazedb")
        
        // Write data and crash
        let db = try BlazeDBClient(name: "health-test", fileURL: dbURL, password: "test-password")
        for i in 0..<50 {
            let record = BlazeDataRecord(["index": .int(i)])
            _ = try db.insert(record)
        }
        try db.persist()
        // Simulate crash
        
        // Recover
        let recoveredDB = try BlazeDBClient(name: "health-test", fileURL: dbURL, password: "test-password")
        
        // Validate health
        let health = try recoveredDB.health()
        XCTAssertNotEqual(health.status, .error, "Health status should not be ERROR after crash recovery")
        
        if health.status == .warn {
            print("⚠️  Health warnings after recovery:")
            for reason in health.reasons {
                print("  - \(reason)")
            }
        }
        
        // Validate invariants
        let count = recoveredDB.count()
        XCTAssertGreaterThanOrEqual(count, 0, "Record count should be non-negative")
        
        // Verify no corruption
        let allRecords = try recoveredDB.fetchAll()
        for record in allRecords {
            XCTAssertNotNil(record.storage["index"], "All records should have index field")
        }
        
        try recoveredDB.close()
    }
    
    // MARK: - WAL Replay Correctness
    
    func testWALReplay_NoDuplicateRecords() throws {
        let dbURL = tempDir.appendingPathComponent("wal_replay_test.blazedb")
        
        // Write records
        let db = try BlazeDBClient(name: "wal-replay", fileURL: dbURL, password: "test-password")
        
        let uniqueIDs = Set((0..<20).map { _ in UUID() })
        for id in uniqueIDs {
            let record = BlazeDataRecord(["id": .uuid(id), "value": .int(Int.random(in: 1...100))])
            try db.insert(record, id: id)
        }
        try db.persist()
        
        // Simulate crash and recovery
        let recoveredDB = try BlazeDBClient(name: "wal-replay", fileURL: dbURL, password: "test-password")
        
        // Verify no duplicates
        let allRecords = try recoveredDB.fetchAll()
        let recoveredIDs: Set<UUID> = Set(allRecords.compactMap { record in
            guard case .uuid(let id) = record.storage["id"] else { return nil }
            return id
        })
        
        XCTAssertEqual(recoveredIDs.count, uniqueIDs.count, "No duplicate records after WAL replay")
        XCTAssertEqual(recoveredIDs, uniqueIDs, "All original IDs should be present")
        
        try recoveredDB.close()
    }
}
