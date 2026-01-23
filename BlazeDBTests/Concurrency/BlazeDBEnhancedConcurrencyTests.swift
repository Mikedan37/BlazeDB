//  BlazeDBEnhancedConcurrencyTests.swift
//  Advanced Concurrency, Race Condition, and Deadlock Testing

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

final class BlazeDBEnhancedConcurrencyTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeConcurrency-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "ConcurrencyTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDownWithError() throws {
        if let collection = db?.collection as? DynamicCollection {
            try? collection.persist()
        }
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - Concurrent Write Tests
    
    /// Test 50 concurrent inserts
    func testHighVolumeConcurrentInserts() throws {
        let expectation = expectation(description: "50 concurrent inserts")
        expectation.expectedFulfillmentCount = 50
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        var insertedIDs = ThreadSafeArray<UUID>()
        
        for i in 0..<50 {
            queue.async {
                let record = BlazeDataRecord([
                    "thread": .int(i),
                    "timestamp": .date(Date()),
                    "data": .string("Concurrent \(i)")
                ])
                
                do {
                    let id = try self.db.insert(record)
                    insertedIDs.append(id)
                    expectation.fulfill()
                } catch {
                    XCTFail("Insert failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Verify all inserts succeeded
        XCTAssertEqual(insertedIDs.count, 50, "All 50 inserts should succeed")
        
        // Verify no duplicates
        let allIDs = insertedIDs.values
        let uniqueIDs = Set(allIDs)
        XCTAssertEqual(uniqueIDs.count, 50, "All IDs should be unique (no race condition)")
    }
    
    /// Test concurrent updates to same records
    func testConcurrentUpdates() throws {
        // Insert 10 records
        var ids: [UUID] = []
        for i in 0..<10 {
            let record = BlazeDataRecord(["counter": .int(0), "index": .int(i)])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let expectation = expectation(description: "100 concurrent updates")
        expectation.expectedFulfillmentCount = 100
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        // 10 threads updating 10 records each
        for _ in 0..<100 {
            queue.async {
                guard let randomID = ids.randomElement() else {
                    expectation.fulfill()
                    return
                }
                let record = BlazeDataRecord([
                    "counter": .int(Int.random(in: 0..<1000)),
                    "timestamp": .date(Date())
                ])
                
                do {
                    try self.db.update(id: randomID, with: record)
                    expectation.fulfill()
                } catch {
                    XCTFail("Update failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 15.0)
        
        // Verify all records still exist and are valid
        for id in ids {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record, "Record should still exist after concurrent updates")
        }
    }
    
    /// Test concurrent deletes don't cause corruption
    func testConcurrentDeletes() throws {
        // Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let expectation = expectation(description: "100 concurrent deletes")
        expectation.expectedFulfillmentCount = 100
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for id in ids {
            queue.async {
                do {
                    try self.db.delete(id: id)
                    expectation.fulfill()
                } catch {
                    // Deleting already-deleted record is OK
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Verify all records are deleted
        let remaining = try db.fetchAll()
        XCTAssertEqual(remaining.count, 0, "All records should be deleted")
    }
    
    // MARK: - Race Condition Tests
    
    /// Test for race conditions in index updates
    func testIndexUpdateRaceCondition() throws {
        let collection = db.collection as! DynamicCollection
        try collection.createIndex(on: "category")
        
        let expectation = expectation(description: "50 concurrent indexed inserts")
        expectation.expectedFulfillmentCount = 50
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for i in 0..<50 {
            queue.async {
                let record = BlazeDataRecord([
                    "category": .string("cat_\(i % 5)"),
                    "data": .int(i)
                ])
                
                do {
                    _ = try self.db.insert(record)
                    expectation.fulfill()
                } catch {
                    XCTFail("Indexed insert failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Reopen to trigger index rebuild
        db = nil
        db = try BlazeDBClient(name: "ConcurrencyTest", fileURL: tempURL, password: "test-password-123")
        let rebuiltCollection = db.collection as! DynamicCollection
        
        // Verify index integrity
        let results = try rebuiltCollection.fetch(byIndexedField: "category", value: "cat_2")
        XCTAssertEqual(results.count, 10, "Index should be consistent after concurrent inserts")
    }
    
    /// Test for counter increment race condition
    func testCounterRaceCondition() throws {
        // Insert a counter record
        let counterID = try db.insert(BlazeDataRecord(["counter": .int(0)]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let expectation = expectation(description: "100 concurrent increments")
        expectation.expectedFulfillmentCount = 100
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let lock = NSLock()
        
        for _ in 0..<100 {
            queue.async {
                do {
                    // Read-modify-write with lock to prevent race
                    lock.lock()
                    guard let current = try? self.db.fetch(id: counterID),
                          let value = current.storage["counter"]?.intValue else {
                        lock.unlock()
                        XCTFail("Failed to read counter")
                        return
                    }
                    
                    let updated = BlazeDataRecord(["counter": .int(value + 1)])
                    try self.db.update(id: counterID, with: updated)
                    lock.unlock()
                    
                    expectation.fulfill()
                } catch {
                    lock.unlock()
                    XCTFail("Counter increment failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 20.0)
        
        // Verify final count
        let final = try db.fetch(id: counterID)
        let finalCount = final?.storage["counter"]?.intValue
        XCTAssertEqual(finalCount, 100, "Counter should reach 100 (no race condition)")
    }
    
    // MARK: - Deadlock Prevention Tests
    
    /// Test that concurrent transactions don't deadlock
    func testConcurrentTransactionsNoDeadlock() throws {
        let expectation = expectation(description: "20 concurrent transactions")
        expectation.expectedFulfillmentCount = 20
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for i in 0..<20 {
            queue.async {
                do {
                    // Use database insert (which is transactional internally)
                    let record = BlazeDataRecord([
                        "transaction": .int(i),
                        "data": .string("TX \(i)")
                    ])
                    _ = try self.db.insert(record)
                    
                    // Small delay to increase chance of interleaving (optimized for tests)
                    let maxDelay = ProcessInfo.processInfo.environment["TEST_SLOW_CONCURRENCY"] == "1" ? 1000 : 200
                    usleep(UInt32.random(in: UInt32(10)...UInt32(maxDelay)))
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Transaction failed: \(error)")
                }
            }
        }
        
        // Should complete without deadlock
        wait(for: [expectation], timeout: 30.0)
        
        // Verify all transactions succeeded
        let records = try db.fetchAll()
        XCTAssertEqual(records.count, 20, "All 20 transactions should succeed")
    }
    
    /// Test mixed operations don't deadlock
    func testMixedOperationsNoDeadlock() throws {
        // Pre-populate with records
        var ids: [UUID] = []
        for i in 0..<50 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let expectation = expectation(description: "100 mixed operations")
        expectation.expectedFulfillmentCount = 100
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for i in 0..<100 {
            queue.async {
                let operation = i % 4
                
                do {
                    switch operation {
                    case 0:  // Insert
                        let record = BlazeDataRecord(["new": .int(i)])
                        _ = try self.db.insert(record)
                    case 1:  // Read
                        if let randomID = ids.randomElement() {
                            _ = try self.db.fetch(id: randomID)
                        }
                    case 2:  // Update
                        if let randomID = ids.randomElement() {
                            let updated = BlazeDataRecord(["updated": .int(i)])
                            try self.db.update(id: randomID, with: updated)
                        }
                    case 3:  // Delete then re-insert
                        if let randomID = ids.randomElement() {
                            try? self.db.delete(id: randomID)
                        }
                        let newRecord = BlazeDataRecord(["reinserted": .int(i)])
                        _ = try self.db.insert(newRecord)
                    default:
                        break
                    }
                    expectation.fulfill()
                } catch {
                    // Some failures are OK (e.g., deleting already-deleted record)
                    expectation.fulfill()
                }
            }
        }
        
        // Should complete without deadlock
        wait(for: [expectation], timeout: 30.0)
        
        print("✅ Mixed operations completed without deadlock")
    }
    
    // MARK: - Thread Safety Validation
    
    /// Test database remains consistent under extreme concurrency
    func testDatabaseConsistencyUnderLoad() throws {
        let iterations = 100
        let expectation = expectation(description: "\(iterations) operations")
        expectation.expectedFulfillmentCount = iterations
        
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        var successCount = ThreadSafeCounter()
        
        for i in 0..<iterations {
            queue.async {
                do {
                    let record = BlazeDataRecord([
                        "index": .int(i),
                        "data": .string("Load \(i)")
                    ])
                    _ = try self.db.insert(record)
                    successCount.increment()
                    expectation.fulfill()
                } catch {
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Verify database is still valid
        let records = try db.fetchAll()
        XCTAssertEqual(records.count, successCount.value, "Record count should match successful inserts")
        
        // Verify each record is valid
        for record in records {
            XCTAssertNotNil(record.storage["index"], "Each record should have valid data")
        }
        
        print("✅ Database remained consistent under load: \(successCount.value)/\(iterations) successful")
    }
}

// MARK: - Helper Classes

class ThreadSafeArray<T> {
    private var _array: [T] = []
    private let lock = NSLock()
    
    func append(_ element: T) {
        lock.lock()
        _array.append(element)
        lock.unlock()
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _array.count
    }
    
    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return _array
    }
}

class ThreadSafeCounter {
    private var _value: Int = 0
    private let lock = NSLock()
    
    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
    
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}

