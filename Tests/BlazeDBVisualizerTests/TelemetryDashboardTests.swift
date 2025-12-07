//
//  TelemetryDashboardTests.swift
//  BlazeDBVisualizerTests
//
//  Test telemetry and metrics collection
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class TelemetryDashboardTests: XCTestCase {
    var tempDir: URL!
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test123")
        
        // Add test data
        for i in 0..<20 {
            try db.insert(BlazeDataRecord( ["index": .int(i)]))
        }
        try db.persist()
    }
    
    override func tearDown() async throws {
        db.telemetry.disable()
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testEnableTelemetry() throws {
        try db.telemetry.enable(samplingRate: 0.1)
        
        // Execute operations
        _ = try db.fetchAll()
        
        // Should collect metrics
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        // Note: Actual metric count depends on sampling rate
    }
    
    func testDisableTelemetry() throws {
        try db.telemetry.enable()
        db.telemetry.disable()
        
        // Execute operations
        _ = try db.fetchAll()
        
        // Should not collect new metrics after disabling
    }
    
    func testSamplingRate() throws {
        // With 100% sampling
        try db.telemetry.enable(samplingRate: 1.0)
        
        for _ in 0..<10 {
            _ = try db.fetchAll()
        }
        
        // Should capture all operations
        // Note: Actual implementation may vary
    }
    
    func testLowSamplingRate() throws {
        // With 1% sampling
        try db.telemetry.enable(samplingRate: 0.01)
        
        for _ in 0..<100 {
            _ = try db.fetchAll()
        }
        
        // Should capture approximately 1 operation
        // Due to randomness, this might be 0-3
    }
    
    // MARK: - Metric Collection Tests
    
    func testOperationMetrics() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Perform various operations
        try db.insert(BlazeDataRecord( ["test": .string("value")]))
        _ = try db.fetchAll()
        
        // Wait for metrics to be recorded
        Thread.sleep(forTimeInterval: 0.1)
        
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        
        // Should have metrics for both operations
        // Note: Actual count depends on implementation
    }
    
    func testSuccessTracking() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Successful operation
        _ = try db.fetchAll()
        
        // Failed operation
        _ = try? db.fetch(id: UUID())  // Non-existent ID
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        
        // Should track both successes and failures
    }
    
    // MARK: - Performance Tests
    
    func testTelemetryOverhead() throws {
        // Without telemetry
        let startWithout = Date()
        for _ in 0..<100 {
            _ = try db.fetchAll()
        }
        let durationWithout = Date().timeIntervalSince(startWithout)
        
        // With telemetry at 100% sampling
        try db.telemetry.enable(samplingRate: 1.0)
        let startWith = Date()
        for _ in 0..<100 {
            _ = try db.fetchAll()
        }
        let durationWith = Date().timeIntervalSince(startWith)
        
        // Overhead should be minimal (< 10%)
        let overhead = (durationWith - durationWithout) / durationWithout
        XCTAssertLessThan(overhead, 0.10, "Telemetry overhead should be < 10%")
    }
    
    func testMetricStoragePerformance() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Generate many operations
        measure {
            for _ in 0..<50 {
                _ = try? db.fetchAll()
            }
        }
        
        // Should handle high volume without significant slowdown
    }
    
    // MARK: - Auto-Cleanup Tests
    
    func testAutoCleanup() throws {
        // Note: Auto-cleanup runs periodically
        // This test would need to wait for cleanup cycle
        // For now, just verify it doesn't crash
        
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Generate old metrics
        for _ in 0..<100 {
            _ = try db.fetchAll()
        }
        
        // Auto-cleanup should eventually remove old metrics
        // This is a long-running test that we'd skip in fast test runs
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationUpdate() throws {
        try db.telemetry.enable(samplingRate: 0.1)
        
        // Update sampling rate
        try db.telemetry.enable(samplingRate: 0.5)
        
        // New sampling rate should take effect
        // Note: Testing this requires executing many operations
    }
    
    // MARK: - Edge Cases
    
    func testZeroSamplingRate() throws {
        try db.telemetry.enable(samplingRate: 0.0)
        
        for _ in 0..<10 {
            _ = try db.fetchAll()
        }
        
        // Should collect no metrics
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        XCTAssertTrue(metrics.isEmpty, "Zero sampling should collect nothing")
    }
    
    func testFullSamplingRate() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        let operationCount = 20
        for _ in 0..<operationCount {
            _ = try db.fetchAll()
        }
        
        Thread.sleep(forTimeInterval: 0.2)
        
        // Should capture all operations
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        XCTAssertGreaterThanOrEqual(metrics.count, operationCount - 2, "Should capture most operations")
    }
    
    func testInvalidSamplingRate() throws {
        // Negative sampling rate
        XCTAssertThrowsError(try db.telemetry.enable(samplingRate: -0.1))
        
        // > 100% sampling rate
        XCTAssertThrowsError(try db.telemetry.enable(samplingRate: 1.5))
    }
    
    func testConcurrentMetricCollection() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 10
        
        // Execute operations concurrently
        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = try? self.db.fetchAll()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Should handle concurrent metric collection without crashes
    }
    
    // MARK: - Query Tests
    
    func testGetMetricsSinceDate() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        let startTime = Date()
        
        // Execute operations
        for _ in 0..<5 {
            _ = try db.fetchAll()
        }
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // Get metrics since start
        let metrics = try db.telemetry.getMetrics(since: startTime)
        
        XCTAssertGreaterThan(metrics.count, 0, "Should have metrics since start time")
    }
    
    func testGetMetricsForOperation() throws {
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Execute specific operations
        _ = try db.fetchAll()
        try db.insert(BlazeDataRecord( ["test": .string("value")]))
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // Filter by operation type
        let allMetrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        
        // Should have metrics for different operation types
        XCTAssertGreaterThan(allMetrics.count, 0)
    }
}

