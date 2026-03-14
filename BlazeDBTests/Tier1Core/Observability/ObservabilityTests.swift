//
//  ObservabilityTests.swift
//  BlazeDBTests
//
//  Tests for snapshot-based observability.
//  Validates correctness and non-interference.
//
//  Created by Auto on 2025-01-23.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class ObservabilityTests: XCTestCase {
    var tempDir: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try! BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "TestPass123!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Snapshot Tests
    
    func testObserve_ReturnsValidSnapshot() throws {
        let snapshot = try db.observe()
        
        // Verify snapshot structure
        XCTAssertGreaterThanOrEqual(snapshot.uptime, 0)
        XCTAssertEqual(snapshot.health.status, "OK")
        XCTAssertEqual(snapshot.transactions.started, 0)
        XCTAssertEqual(snapshot.transactions.committed, 0)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
        XCTAssertEqual(snapshot.io.pageReads, 0)
        XCTAssertEqual(snapshot.io.pageWrites, 0)
        XCTAssertEqual(snapshot.recovery.state, "completed")
    }
    
    func testObserve_DoesNotMutateState() throws {
        // Get initial state
        let initialCount = try db.count()
        
        // Take snapshot
        _ = try db.observe()
        
        // Verify state unchanged
        let finalCount = try db.count()
        XCTAssertEqual(initialCount, finalCount)
    }
    
    func testObserve_IsDeterministic() throws {
        let snapshot1 = try db.observe()
        Thread.sleep(forTimeInterval: 0.01)
        let snapshot2 = try db.observe()
        
        // Uptime should increase
        XCTAssertGreaterThan(snapshot2.uptime, snapshot1.uptime)
        
        // Other values should be consistent
        XCTAssertEqual(snapshot1.transactions.started, snapshot2.transactions.started)
        XCTAssertEqual(snapshot1.recovery.state, snapshot2.recovery.state)
    }
    
    // MARK: - Transaction Metrics Tests
    
    func testMetrics_TransactionStarted() throws {
        try db.beginTransaction()
        
        let snapshot = try db.observe()
        XCTAssertEqual(snapshot.transactions.started, 1)
        XCTAssertEqual(snapshot.transactions.committed, 0)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
        
        try db.commitTransaction()
    }
    
    func testMetrics_TransactionCommitted() throws {
        try db.beginTransaction()
        try db.insert(BlazeDataRecord(["value": .int(42)]))
        try db.commitTransaction()
        
        let snapshot = try db.observe()
        XCTAssertEqual(snapshot.transactions.started, 1)
        XCTAssertEqual(snapshot.transactions.committed, 1)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
    }
    
    func testMetrics_TransactionAborted() throws {
        try db.beginTransaction()
        try db.insert(BlazeDataRecord(["value": .int(42)]))
        try db.rollbackTransaction()
        
        let snapshot = try db.observe()
        XCTAssertEqual(snapshot.transactions.started, 1)
        XCTAssertEqual(snapshot.transactions.committed, 0)
        XCTAssertEqual(snapshot.transactions.aborted, 1)
    }
    
    func testMetrics_MultipleTransactions() throws {
        // Multiple transactions
        for i in 0..<5 {
            try db.beginTransaction()
            try db.insert(BlazeDataRecord(["value": .int(i)]))
            try db.commitTransaction()
        }
        
        let snapshot = try db.observe()
        XCTAssertEqual(snapshot.transactions.started, 5)
        XCTAssertEqual(snapshot.transactions.committed, 5)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
    }
    
    // MARK: - Recovery Metrics Tests
    
    func testMetrics_RecoveryState() throws {
        let snapshot = try db.observe()
        
        // After initialization, recovery should be completed
        XCTAssertEqual(snapshot.recovery.state, "completed")
    }
    
    // MARK: - Non-Interference Tests
    
    func testObservability_DoesNotImpactPerformance() throws {
        // Measure baseline performance
        let startTime = Date()
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        let baselineDuration = Date().timeIntervalSince(startTime)
        
        // Measure performance with observability
        let startTime2 = Date()
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i + 100)]))
            // Call observe() frequently (worst case)
            _ = try? db.observe()
        }
        let observabilityDuration = Date().timeIntervalSince(startTime2)
        
        // Observability should not significantly impact performance.
        // Allow up to 2x overhead for noisy CI hosts while preserving guardrail value.
        XCTAssertLessThan(observabilityDuration, baselineDuration * 2.0,
                         "Observability should not significantly impact performance")
    }
    
    func testObservability_DoesNotDeadlock() throws {
        // Concurrent operations with observability
        let group = DispatchGroup()
        var errors: [Error] = []
        let lock = NSLock()
        
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                do {
                    // Mix operations and observability
                    _ = try self.db.insert(BlazeDataRecord(["value": .int(Int.random(in: 0..<1000))]))
                    _ = try self.db.observe()
                    _ = try self.db.fetchAll()
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Operations should complete without deadlock")
        XCTAssertTrue(errors.isEmpty || errors.allSatisfy { $0.localizedDescription.contains("locked") },
                      "Only expected errors should occur")
    }
    
    // MARK: - Snapshot Consistency Tests
    
    func testSnapshot_ValuesAreConsistent() throws {
        // Perform operations
        try db.beginTransaction()
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        try db.commitTransaction()
        
        // Take multiple snapshots
        let snapshot1 = try db.observe()
        let snapshot2 = try db.observe()
        
        // Values should be consistent
        XCTAssertEqual(snapshot1.transactions.started, snapshot2.transactions.started)
        XCTAssertEqual(snapshot1.transactions.committed, snapshot2.transactions.committed)
        XCTAssertEqual(snapshot1.transactions.aborted, snapshot2.transactions.aborted)
    }
    
    // MARK: - Health Status Tests
    
    func testSnapshot_HealthStatus() throws {
        let snapshot = try db.observe()
        
        // Health should be valid
        XCTAssertTrue(["OK", "WARN", "ERROR"].contains(snapshot.health.status))
    }
    
    // MARK: - Uptime Tests
    
    func testSnapshot_UptimeIncreases() throws {
        let snapshot1 = try db.observe()
        Thread.sleep(forTimeInterval: 0.1)
        let snapshot2 = try db.observe()
        
        XCTAssertGreaterThan(snapshot2.uptime, snapshot1.uptime)
    }
}
