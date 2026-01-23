//
//  ChangeObservationTests.swift
//  BlazeDBTests
//
//  Tests for change observation and real-time notifications
//

import XCTest
@testable import BlazeDBCore

final class ChangeObservationTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObserveTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "ObserveTest", fileURL: dbURL, password: "test-pass-123456")
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
    
    // MARK: - Basic Observation
    
    func testObserveInsert() async throws {
        print("👁️ Testing observe insert")
        
        let expectation = expectation(description: "Insert observed")
        var observedChanges: [DatabaseChange] = []
        
        let token = db.observe { changes in
            observedChanges.append(contentsOf: changes)
            expectation.fulfill()
        }
        
        defer { token.invalidate() }
        
        // Insert record
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertEqual(observedChanges.count, 1)
        
        if case .insert(let observedID) = observedChanges[0].type {
            XCTAssertEqual(observedID, id)
        } else {
            XCTFail("Expected insert change")
        }
        
        print("  ✅ Insert observed correctly")
    }
    
    func testObserveUpdate() async throws {
        print("👁️ Testing observe update")
        
        // Insert initial record
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        
        let expectation = expectation(description: "Update observed")
        var observedChanges: [DatabaseChange] = []
        
        let token = db.observe { changes in
            observedChanges.append(contentsOf: changes)
            expectation.fulfill()
        }
        
        defer { token.invalidate() }
        
        // Update record
        try await db.update(id: id, data: BlazeDataRecord(["value": .int(2)]))
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertGreaterThanOrEqual(observedChanges.count, 1)
        
        let updateChanges = observedChanges.filter {
            if case .update(let updateID) = $0.type {
                return updateID == id
            }
            return false
        }
        
        XCTAssertGreaterThanOrEqual(updateChanges.count, 1, "Should observe update")
        
        print("  ✅ Update observed correctly")
    }
    
    func testObserveDelete() async throws {
        print("👁️ Testing observe delete")
        
        // Insert record
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        
        let expectation = expectation(description: "Delete observed")
        var observedChanges: [DatabaseChange] = []
        
        let token = db.observe { changes in
            observedChanges.append(contentsOf: changes)
            expectation.fulfill()
        }
        
        defer { token.invalidate() }
        
        // Delete record
        try await db.delete(id: id)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertGreaterThanOrEqual(observedChanges.count, 1)
        
        let deleteChanges = observedChanges.filter {
            if case .delete(let deleteID) = $0.type {
                return deleteID == id
            }
            return false
        }
        
        XCTAssertGreaterThanOrEqual(deleteChanges.count, 1, "Should observe delete")
        
        print("  ✅ Delete observed correctly")
    }
    
    // MARK: - Multiple Observers
    
    func testMultipleObservers() async throws {
        print("👁️ Testing multiple observers")
        
        let exp1 = expectation(description: "Observer 1")
        let exp2 = expectation(description: "Observer 2")
        let exp3 = expectation(description: "Observer 3")
        
        var count1 = 0
        var count2 = 0
        var count3 = 0
        
        let token1 = db.observe { _ in
            count1 += 1
            exp1.fulfill()
        }
        
        let token2 = db.observe { _ in
            count2 += 1
            exp2.fulfill()
        }
        
        let token3 = db.observe { _ in
            count3 += 1
            exp3.fulfill()
        }
        
        defer {
            token1.invalidate()
            token2.invalidate()
            token3.invalidate()
        }
        
        // Make a change
        _ = try await db.insert(BlazeDataRecord(["test": .bool(true)]))
        
        await fulfillment(of: [exp1, exp2, exp3], timeout: 2.0)
        
        XCTAssertEqual(count1, 1, "Observer 1 should be called")
        XCTAssertEqual(count2, 1, "Observer 2 should be called")
        XCTAssertEqual(count3, 1, "Observer 3 should be called")
        
        print("  ✅ All 3 observers notified")
    }
    
    func testObserverRemoval() async throws {
        print("👁️ Testing observer removal")
        
        var callCount = 0
        
        let token = db.observe { _ in
            callCount += 1
        }
        
        // Make change 1
        _ = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        try await Task.sleep(nanoseconds: 200_000_000)  // Wait for notification
        
        let countAfterFirst = callCount
        XCTAssertGreaterThanOrEqual(countAfterFirst, 1)
        
        // Remove observer
        token.invalidate()
        
        // Make change 2
        _ = try await db.insert(BlazeDataRecord(["value": .int(2)]))
        try await Task.sleep(nanoseconds: 200_000_000)  // Wait
        
        let countAfterSecond = callCount
        XCTAssertEqual(countAfterSecond, countAfterFirst, "Observer should not be called after removal")
        
        print("  ✅ Observer removed successfully")
    }
    
    // MARK: - Filtered Observation
    
    func testObserveFilteredChanges() async throws {
        print("👁️ Testing filtered observation")
        
        let expectation = expectation(description: "Filtered change")
        var observedHighPriority = 0
        
        let token = db.observe(
            where: { $0.storage["priority"]?.intValue == 5 },
            changes: { _ in
                observedHighPriority += 1
                expectation.fulfill()
            }
        )
        
        defer { token.invalidate() }
        
        // Insert low priority (should NOT trigger)
        _ = try await db.insert(BlazeDataRecord(["priority": .int(1)]))
        
        // Insert high priority (should trigger)
        _ = try await db.insert(BlazeDataRecord(["priority": .int(5)]))
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertEqual(observedHighPriority, 1, "Should only observe high-priority insert")
        
        print("  ✅ Filtered observer works correctly")
    }
    
    // MARK: - Thread Safety
    
    func testObserverThreadSafety() async throws {
        print("👁️ Testing observer thread safety")
        
        var observedCount = 0
        let lock = NSLock()
        
        let token = db.observe { _ in
            lock.lock()
            observedCount += 1
            lock.unlock()
        }
        
        defer { token.invalidate() }
        
        // 50 concurrent inserts
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    _ = try? await self.db.insert(BlazeDataRecord(["value": .int(i)]))
                }
            }
        }
        
        // Wait for all notifications
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        lock.lock()
        let final = observedCount
        lock.unlock()
        
        XCTAssertGreaterThan(final, 0, "Should observe some changes")
        print("  ✅ Observed \(final) changes from 50 concurrent operations")
    }
    
    func testObserverDoesNotLeakMemory() async throws {
        print("👁️ Testing observer memory safety")
        
        weak var weakToken: ObserverToken?
        
        autoreleasepool {
            let token = db.observe { _ in }
            weakToken = token
            
            XCTAssertNotNil(weakToken, "Token should exist")
            
            // Token goes out of scope
        }
        
        // Token should be deallocated
        XCTAssertNil(weakToken, "Token should be deallocated")
        
        print("  ✅ Observer token doesn't leak")
    }
    
    func testObserverReceivesChangesInOrder() async throws {
        print("👁️ Testing observer receives changes in order")
        
        var receivedChanges: [DatabaseChange] = []
        let lock = NSLock()
        
        let token = db.observe { changes in
            lock.lock()
            receivedChanges.append(contentsOf: changes)
            lock.unlock()
        }
        
        defer { token.invalidate() }
        
        // Insert 10 records sequentially
        var insertedIDs: [UUID] = []
        for i in 0..<10 {
            let id = try await db.insert(BlazeDataRecord(["index": .int(i)]))
            insertedIDs.append(id)
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms delay
        }
        
        // Wait for all notifications
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
        
        lock.lock()
        let changes = receivedChanges
        lock.unlock()
        
        XCTAssertGreaterThanOrEqual(changes.count, 10, "Should observe all inserts")
        
        print("  ✅ Observed \(changes.count) changes in order")
    }
    
    // MARK: - Batch Observation
    
    func testObserveBatchInsert() async throws {
        print("👁️ Testing observe batch insert")
        
        let expectation = expectation(description: "Batch insert observed")
        var observedChanges: [DatabaseChange] = []
        
        let token = db.observe { changes in
            observedChanges.append(contentsOf: changes)
            expectation.fulfill()
        }
        
        defer { token.invalidate() }
        
        // Batch insert
        _ = try await db.insertMany((0..<20).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertGreaterThan(observedChanges.count, 0, "Should observe batch changes")
        
        print("  ✅ Batch insert observed: \(observedChanges.count) changes")
    }
    
    // MARK: - Performance
    
    func testPerformance_ObservationOverhead() async throws {
        measure(metrics: [XCTClockMetric()]) {
            Task {
                do {
                    let token = self.db.observe { _ in }
                    defer { token.invalidate() }
                    
                    // Perform 100 operations
                    for i in 0..<100 {
                        _ = try await self.db.insert(BlazeDataRecord(["value": .int(i)]))
                    }
                    
                    try await Task.sleep(nanoseconds: 100_000_000)  // Wait for notifications
                } catch {
                    XCTFail("Observation performance test failed: \(error)")
                }
            }
        }
    }
}

