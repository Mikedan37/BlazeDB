//
//  MigrationProgressMonitorTests.swift
//  BlazeDBTests
//
//  Tests for MigrationProgressMonitor
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class MigrationProgressMonitorTests: XCTestCase {
    
    var monitor: MigrationProgressMonitor!
    
    override func setUp() {
        super.setUp()
        monitor = MigrationProgressMonitor()
    }
    
    override func tearDown() {
        monitor = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        let progress = monitor.getProgress()
        
        XCTAssertNil(progress.currentTable)
        XCTAssertEqual(progress.currentTableIndex, 0)
        XCTAssertEqual(progress.totalTables, 0)
        XCTAssertEqual(progress.recordsProcessed, 0)
        XCTAssertNil(progress.recordsTotal)
        XCTAssertEqual(progress.bytesProcessed, 0)
        XCTAssertNil(progress.bytesTotal)
        XCTAssertEqual(progress.status, .notStarted)
        XCTAssertNil(progress.error)
    }
    
    func testReset() {
        // Set some state
        monitor.update(
            currentTable: "users",
            currentTableIndex: 1,
            totalTables: 5,
            recordsProcessed: 100,
            recordsTotal: 500,
            status: .migrating
        )
        
        // Reset
        monitor.reset()
        
        let progress = monitor.getProgress()
        XCTAssertNil(progress.currentTable)
        XCTAssertEqual(progress.currentTableIndex, 0)
        XCTAssertEqual(progress.totalTables, 0)
        XCTAssertEqual(progress.recordsProcessed, 0)
        XCTAssertNil(progress.recordsTotal)
        XCTAssertEqual(progress.status, .notStarted)
    }
    
    // MARK: - Progress Update Tests
    
    func testStart() {
        monitor.start(totalTables: 3, recordsTotal: 1000, bytesTotal: 5000)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.totalTables, 3)
        XCTAssertEqual(progress.recordsTotal, 1000)
        XCTAssertEqual(progress.bytesTotal, 5000)
        XCTAssertEqual(progress.status, .preparing)
    }
    
    func testUpdateTable() {
        monitor.start(totalTables: 3, recordsTotal: 1000)
        monitor.updateTable("users", index: 1, recordsProcessed: 0)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.currentTable, "users")
        XCTAssertEqual(progress.currentTableIndex, 1)
        XCTAssertEqual(progress.totalTables, 3)
        XCTAssertEqual(progress.status, .migrating)
    }
    
    func testUpdateRecordsProcessed() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        monitor.update(recordsProcessed: 50)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.recordsProcessed, 50)
        XCTAssertEqual(progress.recordsTotal, 100)
        XCTAssertEqual(progress.percentage, 50.0, accuracy: 0.1)
    }
    
    func testComplete() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        monitor.complete(recordsProcessed: 100)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.recordsProcessed, 100)
        XCTAssertEqual(progress.status, .completed)
    }
    
    func testFail() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        monitor.fail(error)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.status, .failed)
        XCTAssertNotNil(progress.error)
    }
    
    func testCancel() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        monitor.cancel()
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.status, .cancelled)
    }
    
    // MARK: - Percentage Calculation Tests
    
    func testPercentageWithRecords() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        monitor.update(recordsProcessed: 25)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.percentage, 25.0, accuracy: 0.1)
    }
    
    func testPercentageWithBytes() {
        monitor.start(totalTables: 1, bytesTotal: 1000)
        monitor.update(bytesProcessed: 750)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.percentage, 75.0, accuracy: 0.1)
    }
    
    func testPercentageNoTotal() {
        monitor.update(recordsProcessed: 50)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.percentage, 0.0)
    }
    
    func testPercentageComplete() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        monitor.update(recordsProcessed: 100)
        
        let progress = monitor.getProgress()
        XCTAssertEqual(progress.percentage, 100.0, accuracy: 0.1)
    }
    
    // MARK: - Time Calculation Tests
    
    func testElapsedTime() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        
        let startTime = monitor.getProgress().startTime
        Thread.sleep(forTimeInterval: 0.1)
        
        let progress = monitor.getProgress()
        XCTAssertGreaterThan(progress.elapsedTime, 0.0)
        XCTAssertLessThan(progress.elapsedTime, 1.0)
    }
    
    func testEstimatedTimeRemaining() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        
        // Process 50 records in 1 second
        Thread.sleep(forTimeInterval: 0.1)
        monitor.update(recordsProcessed: 50)
        
        let progress = monitor.getProgress()
        if let remaining = progress.estimatedTimeRemaining {
            XCTAssertGreaterThan(remaining, 0.0)
            XCTAssertLessThan(remaining, 10.0)  // Should be around 1 second
        }
    }
    
    func testEstimatedTimeRemainingNoProgress() {
        monitor.start(totalTables: 1, recordsTotal: 100)
        
        let progress = monitor.getProgress()
        XCTAssertNil(progress.estimatedTimeRemaining)  // No progress yet
    }
    
    // MARK: - Thread Safety Tests
    
    func testThreadSafety() {
        monitor.start(totalTables: 1, recordsTotal: 1000)
        
        let expectation = XCTestExpectation(description: "Concurrent updates")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                self.monitor.update(recordsProcessed: (i + 1) * 100)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Should not crash and should have valid progress
        let progress = monitor.getProgress()
        XCTAssertGreaterThanOrEqual(progress.recordsProcessed, 0)
        XCTAssertLessThanOrEqual(progress.recordsProcessed, 1000)
    }
    
    // MARK: - Observer Tests
    
    func testObserver() {
        var receivedProgress: MigrationProgress?
        let expectation = XCTestExpectation(description: "Observer called")
        
        let observerID = monitor.addObserver { progress in
            receivedProgress = progress
            expectation.fulfill()
        }
        
        monitor.start(totalTables: 1, recordsTotal: 100)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(receivedProgress)
        XCTAssertEqual(receivedProgress?.status, .preparing)
        
        monitor.removeObserver(observerID)
    }
    
    func testMultipleObservers() {
        var callCount = 0
        let expectation = XCTestExpectation(description: "All observers called")
        expectation.expectedFulfillmentCount = 3
        
        let observer1 = monitor.addObserver { _ in
            callCount += 1
            expectation.fulfill()
        }
        
        let observer2 = monitor.addObserver { _ in
            callCount += 1
            expectation.fulfill()
        }
        
        let observer3 = monitor.addObserver { _ in
            callCount += 1
            expectation.fulfill()
        }
        
        monitor.start(totalTables: 1, recordsTotal: 100)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(callCount, 3)
        
        monitor.removeObserver(observer1)
        monitor.removeObserver(observer2)
        monitor.removeObserver(observer3)
    }
    
    func testRemoveObserver() {
        var callCount = 0
        
        let observerID = monitor.addObserver { _ in
            callCount += 1
        }
        
        monitor.start(totalTables: 1, recordsTotal: 100)
        Thread.sleep(forTimeInterval: 0.1)
        
        monitor.removeObserver(observerID)
        
        let initialCount = callCount
        monitor.update(recordsProcessed: 50)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should not have increased
        XCTAssertEqual(callCount, initialCount)
    }
    
    // MARK: - Status Transition Tests
    
    func testStatusTransitions() {
        XCTAssertEqual(monitor.getProgress().status, .notStarted)
        
        monitor.start(totalTables: 1, recordsTotal: 100)
        XCTAssertEqual(monitor.getProgress().status, .preparing)
        
        monitor.updateTable("users", index: 1, recordsProcessed: 0)
        XCTAssertEqual(monitor.getProgress().status, .migrating)
        
        monitor.update(status: .creatingIndexes)
        XCTAssertEqual(monitor.getProgress().status, .creatingIndexes)
        
        monitor.complete(recordsProcessed: 100)
        XCTAssertEqual(monitor.getProgress().status, .completed)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        monitor.start(totalTables: 2, recordsTotal: 100)
        monitor.updateTable("users", index: 1, recordsProcessed: 50)
        
        let description = monitor.getProgress().description
        
        XCTAssertTrue(description.contains("Migration Progress"))
        XCTAssertTrue(description.contains("users"))
        XCTAssertTrue(description.contains("50"))
        XCTAssertTrue(description.contains("100"))
    }
    
    func testDescriptionWithError() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        monitor.fail(error)
        
        let description = monitor.getProgress().description
        
        XCTAssertTrue(description.contains("Failed"))
        XCTAssertTrue(description.contains("Test error"))
    }
}

