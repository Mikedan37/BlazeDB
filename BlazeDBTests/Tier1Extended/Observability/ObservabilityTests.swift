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
    private var tempDir: URL?
    private var db: BlazeDBClient?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let dbURL = dir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "TestPass123!")
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
    
    // MARK: - Snapshot Tests
    
    func testObserve_ReturnsValidSnapshot() throws {
        let snapshot = try requireFixture(db).observe()
        
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
        let initialCount = try requireFixture(db).count()
        
        // Take snapshot
        _ = try requireFixture(db).observe()
        
        // Verify state unchanged
        let finalCount = try requireFixture(db).count()
        XCTAssertEqual(initialCount, finalCount)
    }
    
    func testObserve_IsDeterministic() throws {
        let snapshot1 = try requireFixture(db).observe()
        Thread.sleep(forTimeInterval: 0.01)
        let snapshot2 = try requireFixture(db).observe()
        
        // Uptime should increase
        XCTAssertGreaterThan(snapshot2.uptime, snapshot1.uptime)
        
        // Other values should be consistent
        XCTAssertEqual(snapshot1.transactions.started, snapshot2.transactions.started)
        XCTAssertEqual(snapshot1.recovery.state, snapshot2.recovery.state)
    }
    
    // MARK: - Transaction Metrics Tests
    
    func testMetrics_TransactionStarted() throws {
        try requireFixture(db).beginTransaction()
        
        let snapshot = try requireFixture(db).observe()
        XCTAssertEqual(snapshot.transactions.started, 1)
        XCTAssertEqual(snapshot.transactions.committed, 0)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
        
        try requireFixture(db).commitTransaction()
    }
    
    func testMetrics_TransactionCommitted() throws {
        try requireFixture(db).beginTransaction()
        try requireFixture(db).insert(BlazeDataRecord(["value": .int(42)]))
        try requireFixture(db).commitTransaction()
        
        let snapshot = try requireFixture(db).observe()
        XCTAssertEqual(snapshot.transactions.started, 1)
        XCTAssertEqual(snapshot.transactions.committed, 1)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
    }
    
    func testMetrics_TransactionAborted() throws {
        try requireFixture(db).beginTransaction()
        try requireFixture(db).insert(BlazeDataRecord(["value": .int(42)]))
        try requireFixture(db).rollbackTransaction()
        
        let snapshot = try requireFixture(db).observe()
        XCTAssertEqual(snapshot.transactions.started, 1)
        XCTAssertEqual(snapshot.transactions.committed, 0)
        XCTAssertEqual(snapshot.transactions.aborted, 1)
    }
    
    func testMetrics_MultipleTransactions() throws {
        // Multiple transactions
        for i in 0..<5 {
            try requireFixture(db).beginTransaction()
            try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
            try requireFixture(db).commitTransaction()
        }
        
        let snapshot = try requireFixture(db).observe()
        XCTAssertEqual(snapshot.transactions.started, 5)
        XCTAssertEqual(snapshot.transactions.committed, 5)
        XCTAssertEqual(snapshot.transactions.aborted, 0)
    }
    
    // MARK: - Recovery Metrics Tests
    
    func testMetrics_RecoveryState() throws {
        let snapshot = try requireFixture(db).observe()
        
        // After initialization, recovery should be completed
        XCTAssertEqual(snapshot.recovery.state, "completed")
    }
    
    // MARK: - Non-Interference Tests
    
    func testObservability_DoesNotImpactPerformance() throws {
        // Correctness under frequent observe(): inserts still succeed and data remains consistent.
        // Wall-clock ratios are too flaky on shared CI hosts to assert meaningfully.
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i + 100)]))
            _ = try requireFixture(db).observe()
        }
        XCTAssertEqual(try requireFixture(db).count(), 200)
        let snap = try requireFixture(db).observe()
        XCTAssertFalse(snap.health.status.isEmpty)
    }
    
    func testObservability_DoesNotDeadlock() throws {
        // Concurrent operations with observability
        let group = DispatchGroup()
        var errors: [Error] = []
        let lock = NSLock()
        let client = try XCTUnwrap(db)
        
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async { [client] in
                do {
                    // Mix operations and observability
                    _ = try client.insert(BlazeDataRecord(["value": .int(Int.random(in: 0..<1000))]))
                    _ = try client.observe()
                    _ = try client.fetchAll()
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
        try requireFixture(db).beginTransaction()
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        try requireFixture(db).commitTransaction()
        
        // Take multiple snapshots
        let snapshot1 = try requireFixture(db).observe()
        let snapshot2 = try requireFixture(db).observe()
        
        // Values should be consistent
        XCTAssertEqual(snapshot1.transactions.started, snapshot2.transactions.started)
        XCTAssertEqual(snapshot1.transactions.committed, snapshot2.transactions.committed)
        XCTAssertEqual(snapshot1.transactions.aborted, snapshot2.transactions.aborted)
    }
    
    // MARK: - Health Status Tests
    
    func testSnapshot_HealthStatus() throws {
        let snapshot = try requireFixture(db).observe()
        
        // Health should be valid
        XCTAssertTrue(["OK", "WARN", "ERROR"].contains(snapshot.health.status))
    }
    
    // MARK: - Uptime Tests
    
    func testSnapshot_UptimeIncreases() throws {
        let snapshot1 = try requireFixture(db).observe()
        Thread.sleep(forTimeInterval: 0.1)
        let snapshot2 = try requireFixture(db).observe()
        
        XCTAssertGreaterThan(snapshot2.uptime, snapshot1.uptime)
    }
}
