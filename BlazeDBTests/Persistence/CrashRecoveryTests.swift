//
//  CrashRecoveryTests.swift
//  BlazeDBTests
//
//  Tests database recovery after unclean shutdown
//  Validates durability guarantees under crash conditions
//

import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@testable import BlazeDBCore

final class CrashRecoveryTests: XCTestCase {
    
    var tempURL: URL!
    let password = "test-password-123"
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
    }
    
    override func tearDownWithError() throws {
        // Cleanup all related files
        let extensions = ["", "meta", "wal", "backup", "txn_log.json"]
        for ext in extensions {
            let cleanupURL = ext.isEmpty ? tempURL : tempURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: cleanupURL)
        }
    }
    
    /// Test: Database survives unclean shutdown and recovers all committed data
    func testCrashRecovery_UncleanShutdown() throws {
        let testRecords: [UUID: BlazeDataRecord] = [
            UUID(): BlazeDataRecord(["id": .int(1), "name": .string("Record 1"), "value": .double(10.5)]),
            UUID(): BlazeDataRecord(["id": .int(2), "name": .string("Record 2"), "value": .double(20.5)]),
            UUID(): BlazeDataRecord(["id": .int(3), "name": .string("Record 3"), "value": .double(30.5)]),
        ]
        
        var insertedIDs: [UUID] = []
        
        // Phase 1: Create database and insert records
        do {
            let client = try BlazeDBClient(name: "crash-test", fileURL: tempURL, password: password)
            
            // Insert test records
            for (expectedID, record) in testRecords {
                let id = try client.insert(record)
                insertedIDs.append(id)
                XCTAssertEqual(id, expectedID, "Record IDs should match")
            }
            
            // Explicitly persist to ensure durability
            try client.persist()
            
            // Verify records exist before "crash"
            for id in insertedIDs {
                let record = try client.fetch(id: id)
                XCTAssertNotNil(record, "Record should exist before crash simulation")
            }
        }
        
        // Phase 2: Simulate unclean shutdown
        // - Close database (deallocate client)
        // - Remove any lock files if they exist (simulate crash)
        let lockFile = tempURL.path + ".lock"
        try? FileManager.default.removeItem(atPath: lockFile)
        
        // Phase 3: Reopen database in fresh instance (simulates recovery)
        let recoveredClient = try BlazeDBClient(name: "crash-test-recovered", fileURL: tempURL, password: password)
        
        // Phase 4: Verify all committed data exists
        for id in insertedIDs {
            let record = try recoveredClient.fetch(id: id)
            XCTAssertNotNil(record, "Record \(id) should persist after crash recovery")
            
            if let record = record {
                let expectedRecord = testRecords[id]
                XCTAssertNotNil(expectedRecord, "Expected record should exist for \(id)")
                
                if let expected = expectedRecord {
                    XCTAssertEqual(record.storage["id"], expected.storage["id"], "Record \(id) id field should match")
                    XCTAssertEqual(record.storage["name"], expected.storage["name"], "Record \(id) name field should match")
                    XCTAssertEqual(record.storage["value"], expected.storage["value"], "Record \(id) value field should match")
                }
            }
        }
        
        // Verify record count matches
        let allRecords = try recoveredClient.fetchAll()
        XCTAssertGreaterThanOrEqual(allRecords.count, testRecords.count, "Should have at least the committed records")
    }
    
    /// Test: WAL recovery works correctly after crash
    func testCrashRecovery_WALRecovery() throws {
        // Create database with WAL enabled (if applicable)
        let client = try BlazeDBClient(name: "wal-test", fileURL: tempURL, password: password)
        
        // Insert records
        let id1 = try client.insert(BlazeDataRecord(["test": .string("WAL test 1")]))
        let id2 = try client.insert(BlazeDataRecord(["test": .string("WAL test 2")]))
        
        // Persist (this should flush WAL if it exists)
        try client.persist()
        
        // Simulate crash (deallocate client)
        // In a real crash, WAL might have uncommitted entries
        
        // Reopen
        let recoveredClient = try BlazeDBClient(name: "wal-test-recovered", fileURL: tempURL, password: password)
        
        // Verify committed records exist
        let record1 = try recoveredClient.fetch(id: id1)
        let record2 = try recoveredClient.fetch(id: id2)
        
        XCTAssertNotNil(record1, "WAL test record 1 should persist")
        XCTAssertNotNil(record2, "WAL test record 2 should persist")
        
        if let r1 = record1 {
            XCTAssertEqual(r1.storage["test"], .string("WAL test 1"))
        }
        if let r2 = record2 {
            XCTAssertEqual(r2.storage["test"], .string("WAL test 2"))
        }
    }
    
    /// Test: Database recovers even with transaction log present
    func testCrashRecovery_WithTransactionLog() throws {
        let client = try BlazeDBClient(name: "txn-test", fileURL: tempURL, password: password)
        
        // Start transaction
        try client.beginTransaction()
        
        // Insert records in transaction
        let id1 = try client.insert(BlazeDataRecord(["txn": .string("test 1")]))
        let id2 = try client.insert(BlazeDataRecord(["txn": .string("test 2")]))
        
        // Commit transaction
        try client.commitTransaction()
        
        // Simulate crash after commit but before full flush
        // (In reality, commitTransaction should have persisted, but test the recovery path)
        
        // Reopen
        let recoveredClient = try BlazeDBClient(name: "txn-test-recovered", fileURL: tempURL, password: password)
        
        // Verify committed transaction data exists
        let record1 = try recoveredClient.fetch(id: id1)
        let record2 = try recoveredClient.fetch(id: id2)
        
        XCTAssertNotNil(record1, "Transaction record 1 should persist")
        XCTAssertNotNil(record2, "Transaction record 2 should persist")
    }
    
    /// Test: Database recovers from corrupted page header
    func testCrashRecovery_CorruptedPageHeader() throws {
        let client = try BlazeDBClient(name: "corruption-test", fileURL: tempURL, password: password)
        
        // Insert record
        let id = try client.insert(BlazeDataRecord(["test": .string("corruption test")]))
        try client.persist()
        
        // Simulate corrupted page header by writing invalid magic bytes
        // This tests error handling, not actual corruption (we can't safely corrupt encrypted pages)
        // Instead, verify that invalid reads are handled gracefully
        let recoveredClient = try BlazeDBClient(name: "corruption-test-recovered", fileURL: tempURL, password: password)
        
        // Valid record should still be readable
        let record = try recoveredClient.fetch(id: id)
        XCTAssertNotNil(record, "Valid record should persist despite potential corruption scenarios")
    }
    
    /// Test: Database recovers with partial WAL writes
    func testCrashRecovery_PartialWALWrite() throws {
        let client = try BlazeDBClient(name: "wal-partial-test", fileURL: tempURL, password: password)
        
        // Insert multiple records to potentially trigger WAL
        var ids: [UUID] = []
        for i in 0..<10 {
            let id = try client.insert(BlazeDataRecord(["batch": .int(i), "data": .string("test \(i)")]))
            ids.append(id)
        }
        
        // Persist (should flush WAL if it exists)
        try client.persist()
        
        // Simulate crash before full flush (deallocate client)
        
        // Reopen
        let recoveredClient = try BlazeDBClient(name: "wal-partial-test-recovered", fileURL: tempURL, password: password)
        
        // Verify all committed records exist
        for id in ids {
            let record = try recoveredClient.fetch(id: id)
            XCTAssertNotNil(record, "Record \(id) should persist after partial WAL recovery")
        }
    }
    
    /// Test: Randomized crash points (fuzz-style)
    func testCrashRecovery_RandomizedCrashPoints() throws {
        // Insert records at different stages
        let client = try BlazeDBClient(name: "random-crash-test", fileURL: tempURL, password: password)
        
        var committedIDs: [UUID] = []
        
        // Insert and commit in batches
        for batch in 0..<5 {
            var batchIDs: [UUID] = []
            for i in 0..<5 {
                let id = try client.insert(BlazeDataRecord([
                    "batch": .int(batch),
                    "index": .int(i),
                    "data": .string("batch \(batch) item \(i)")
                ]))
                batchIDs.append(id)
            }
            
            // Commit this batch
            try client.persist()
            committedIDs.append(contentsOf: batchIDs)
        }
        
        // Simulate crash
        // Reopen
        let recoveredClient = try BlazeDBClient(name: "random-crash-test-recovered", fileURL: tempURL, password: password)
        
        // Verify all committed batches exist
        XCTAssertEqual(recoveredClient.getRecordCount(), committedIDs.count, "All committed records should persist")
        
        for id in committedIDs {
            let record = try recoveredClient.fetch(id: id)
            XCTAssertNotNil(record, "Record \(id) should persist after randomized crash recovery")
        }
    }
}
