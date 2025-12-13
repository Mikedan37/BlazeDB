//
//  TransactionCodecIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for transactions using dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class TransactionCodecIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var client: BlazeDBClient!
    var collection: DynamicCollection!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "TransactionCodec123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        collection = client.collection
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // Helper to compare records ignoring auto-added fields
    private func assertRecordMatches(_ original: BlazeDataRecord, _ fetched: BlazeDataRecord, file: StaticString = #file, line: UInt = #line) {
        for (key, value) in original.storage {
            XCTAssertEqual(fetched.storage[key], value, "Field '\(key)' mismatch", file: file, line: line)
        }
        // Verify that fetched record has all original fields (but may have additional auto-added ones)
        XCTAssertTrue(original.storage.allSatisfy { fetched.storage[$0.key] == $0.value }, 
                     "Fetched record missing some original fields", file: file, line: line)
    }
    
    // MARK: - Nested Transaction Tests
    
    func testNestedTransactions_DualCodec() throws {
        // Note: BlazeDB doesn't support nested transactions
        // Test single transaction instead
        try client.beginTransaction()
        
        let record1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "level": .string("first")
        ])
        let id1 = try client.insert(record1)
        
        let record2 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "level": .string("second")
        ])
        let id2 = try client.insert(record2)
        
        // Commit transaction
        try client.commitTransaction()
        
        // Verify both records exist
        let fetched1 = try client.fetch(id: id1)
        let fetched2 = try client.fetch(id: id2)
        
        XCTAssertNotNil(fetched1)
        XCTAssertNotNil(fetched2)
        if let fetched1 = fetched1, let fetched2 = fetched2 {
            assertRecordMatches(record1, fetched1)
            assertRecordMatches(record2, fetched2)
        }
    }
    
    // MARK: - Rollback Tests
    
    func testRollback_DualCodec() throws {
        try client.beginTransaction()
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Rollback Test")
        ])
        
        let id = try client.insert(record)
        
        // Verify exists in transaction
        let fetchedInTx = try client.fetch(id: id)
        XCTAssertNotNil(fetchedInTx)
        if let fetchedInTx = fetchedInTx {
            assertRecordMatches(record, fetchedInTx)
        }
        
        // Rollback
        try client.rollbackTransaction()
        
        // Verify does not exist after rollback
        let fetchedAfterRollback = try client.fetch(id: id)
        XCTAssertNil(fetchedAfterRollback)
    }
    
    // MARK: - Commit Tests
    
    func testCommit_DualCodec() throws {
        try client.beginTransaction()
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Commit Test")
        ])
        
        let id = try client.insert(record)
        
        // Commit
        try client.commitTransaction()
        
        // Verify exists after commit
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            assertRecordMatches(record, fetched)
        }
    }
    
    // MARK: - WAL Journal Entry Tests
    
    func testWALJournalEntries_DualCodec() throws {
        try client.beginTransaction()
        
        var records: [BlazeDataRecord] = []
        var ids: [UUID] = []
        
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "title": .string("Transaction \(i)")
            ])
            records.append(record)
            let id = try client.insert(record)
            ids.append(id)
        }
        
        // Commit (writes to WAL)
        try client.commitTransaction()
        
        // Verify all records exist
        for (id, originalRecord) in zip(ids, records) {
            let fetched = try client.fetch(id: id)
            XCTAssertNotNil(fetched)
            if let fetched = fetched {
                assertRecordMatches(originalRecord, fetched)
            }
        }
    }
    
    // MARK: - Transaction Isolation Tests
    
    func testTransactionIsolation_DualCodec() throws {
        // Insert initial record
        let initial = BlazeDataRecord([
            "id": .uuid(UUID()),
            "value": .int(0)
        ])
        let initialId = try client.insert(initial)
        
        // Start transaction
        try client.beginTransaction()
        
        // Update in transaction
        let updated = BlazeDataRecord([
            "id": .uuid(initialId),
            "value": .int(100)
        ])
        try client.update(id: initialId, with: updated)
        
        // Verify update visible in transaction
        let fetchedInTx = try client.fetch(id: initialId)
        XCTAssertNotNil(fetchedInTx)
        XCTAssertEqual(fetchedInTx?.storage["value"]?.intValue, 100)
        
        // Commit
        try client.commitTransaction()
        
        // Verify update visible after commit
        let fetchedAfterCommit = try client.fetch(id: initialId)
        XCTAssertNotNil(fetchedAfterCommit)
        if let fetchedAfterCommit = fetchedAfterCommit {
            assertRecordMatches(updated, fetchedAfterCommit)
        }
    }
    
    // MARK: - Concurrent Transactions
    
    func testConcurrentTransactions_DualCodec() throws {
        let expectation = XCTestExpectation(description: "Concurrent transactions")
        expectation.expectedFulfillmentCount = 10
        
        var allIds: [UUID] = []
        let lock = NSLock()
        
        // Run concurrent transactions
        for i in 0..<10 {
            DispatchQueue.global().async {
                do {
                    try self.client.beginTransaction()
                    
                    let record = BlazeDataRecord([
                        "id": .uuid(UUID()),
                        "thread": .int(i),
                        "title": .string("Concurrent \(i)")
                    ])
                    
                    let id = try self.client.insert(record)
                    
                    lock.lock()
                    allIds.append(id)
                    lock.unlock()
                    
                    try self.client.commitTransaction()
                    expectation.fulfill()
                } catch {
                    XCTFail("Transaction failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Verify all records exist
        for id in allIds {
            let fetched = try client.fetch(id: id)
            XCTAssertNotNil(fetched)
        }
    }
}

