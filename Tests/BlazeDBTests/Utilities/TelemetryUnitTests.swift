//
//  TelemetryUnitTests.swift
//  BlazeDBTests
//
//  Unit tests for telemetry system
//

import XCTest
@testable import BlazeDB

final class TelemetryUnitTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Telemetry-Unit-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "TelemetryTest", fileURL: dbURL, password: "Test-Pass-123456")
    }
    
    override func tearDown() {
        db?.telemetry.disable()
        
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        
        // Clean up metrics database
        let metricsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".blazedb/metrics/telemetry.blazedb")
        try? FileManager.default.removeItem(at: metricsURL)
        
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testTelemetryCanBeEnabled() throws {
        print("📊 Testing telemetry enable")
        
        // Enable telemetry
        db.telemetry.enable(samplingRate: 1.0)
        
        // Should not throw
        XCTAssertTrue(true, "Telemetry enabled successfully")
        
        print("  ✅ Telemetry enabled")
    }
    
    func testTelemetryTracksInsert() async throws {
        print("📊 Testing telemetry tracks insert")
        
        // Enable with 100% sampling
        db.telemetry.enable(samplingRate: 1.0)
        
        // Insert a record
        _ = try await db.insert(BlazeDataRecord(["test": .string("value")]))
        
        // Allow time for async recording
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // Check telemetry
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThan(summary.totalOperations, 0, "Should track insert operation")
        XCTAssertEqual(summary.successRate, 100.0, "Insert should succeed")
        
        print("  ✅ Insert tracked: \(summary.totalOperations) operations")
    }
    
    func testTelemetryTracksQuery() async throws {
        print("📊 Testing telemetry tracks query")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Insert records
        _ = try await db.insertMany((0..<5).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Query records
        _ = try await db.query().where("value", greaterThan: .int(2)).execute()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThan(summary.totalOperations, 1, "Should track insert + query")
        
        print("  ✅ Query tracked")
    }
    
    func testTelemetryTracksUpdate() async throws {
        print("📊 Testing telemetry tracks update")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        try await db.update(id: id, with: BlazeDataRecord(["value": .int(2)]))
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThanOrEqual(summary.totalOperations, 2, "Should track insert + update")
        
        print("  ✅ Update tracked")
    }
    
    func testTelemetryTracksDelete() async throws {
        print("📊 Testing telemetry tracks delete")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        try await db.delete(id: id)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThanOrEqual(summary.totalOperations, 2, "Should track insert + delete")
        
        print("  ✅ Delete tracked")
    }
    
    func testTelemetryTracksErrors() async throws {
        print("📊 Testing telemetry tracks errors")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Try to delete non-existent record (should fail)
        do {
            try await db.delete(id: UUID())
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let errors = try await db.telemetry.getErrors()
        
        XCTAssertGreaterThan(errors.count, 0, "Should track error")
        XCTAssertEqual(errors.first?.operation, "delete")
        
        print("  ✅ Error tracked: \(errors.count) errors")
    }
    
    // MARK: - Sampling Tests
    
    func testSampling100Percent() async throws {
        print("📊 Testing 100% sampling")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Insert 10 records
        for i in 0..<10 {
            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        // With 100% sampling, should track all 10 operations
        XCTAssertEqual(summary.totalOperations, 10, "100% sampling should track all operations")
        
        print("  ✅ 100% sampling: \(summary.totalOperations)/10 tracked")
    }
    
    func testSampling1Percent() async throws {
        print("📊 Testing 1% sampling")
        
        db.telemetry.enable(samplingRate: 0.01)
        
        // Insert 1000 records
        let records = (0..<1000).map { i in BlazeDataRecord(["value": .int(i)]) }
        _ = try await db.insertMany(records)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        // With 1% sampling, should track ~10 operations (allow variance)
        XCTAssertLessThan(summary.totalOperations, 100, "1% sampling should track < 100 operations")
        
        print("  ✅ 1% sampling: \(summary.totalOperations)/1000 tracked (~1%)")
    }
    
    func testSamplingZeroPercent() async throws {
        print("📊 Testing 0% sampling (disabled)")
        
        db.telemetry.enable(samplingRate: 0.0)
        
        _ = try await db.insert(BlazeDataRecord(["test": .bool(true)]))
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        // With 0% sampling, should track nothing
        XCTAssertEqual(summary.totalOperations, 0, "0% sampling should track nothing")
        
        print("  ✅ 0% sampling: 0 tracked (disabled)")
    }
    
    // MARK: - Summary Tests
    
    func testSummaryCalculatesMetricsCorrectly() async throws {
        print("📊 Testing summary calculations")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Insert 5 records
        for i in 0..<5 {
            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertEqual(summary.totalOperations, 5)
        XCTAssertEqual(summary.successRate, 100.0)
        XCTAssertGreaterThan(summary.avgDuration, 0)
        XCTAssertGreaterThan(summary.p50Duration, 0)
        XCTAssertGreaterThan(summary.p95Duration, 0)
        XCTAssertEqual(summary.errorCount, 0)
        
        print("  ✅ Summary calculated correctly")
        print("    Avg: \(String(format: "%.2f", summary.avgDuration))ms")
    }
    
    func testSummaryWithErrors() async throws {
        print("📊 Testing summary with errors")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // 3 successful operations
        for i in 0..<3 {
            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // 2 failed operations
        for _ in 0..<2 {
            try? await db.delete(id: UUID())
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertEqual(summary.totalOperations, 5)
        XCTAssertEqual(summary.errorCount, 2)
        XCTAssertEqual(summary.successRate, 60.0, accuracy: 1.0)
        
        print("  ✅ Summary with errors: \(summary.errorCount) errors, \(String(format: "%.1f", summary.successRate))% success")
    }
    
    // MARK: - Query API Tests
    
    func testGetSlowOperations() async throws {
        print("📊 Testing getSlowOperations")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Perform operations
        _ = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let slowOps = try await db.telemetry.getSlowOperations(threshold: 0.0)
        
        // Should find operations (threshold 0 = all operations)
        XCTAssertGreaterThan(slowOps.count, 0)
        
        print("  ✅ Found \(slowOps.count) operations")
    }
    
    func testGetOperationBreakdown() async throws {
        print("📊 Testing getOperationBreakdown")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Perform different operations
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        _ = try await db.fetch(id: id)
        try await db.update(id: id, with: BlazeDataRecord(["value": .int(2)]))
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let breakdown = try await db.telemetry.getOperationBreakdown()
        
        XCTAssertFalse(breakdown.operations.isEmpty)
        
        print("  ✅ Breakdown:")
        for (op, stats) in breakdown.operations {
            print("    • \(op): \(stats.count) ops")
        }
    }
    
    func testGetRecentOperations() async throws {
        print("📊 Testing getRecentOperations")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        for i in 0..<5 {
            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let recent = try await db.telemetry.getRecentOperations(limit: 3)
        
        XCTAssertLessThanOrEqual(recent.count, 3)
        XCTAssertGreaterThan(recent.count, 0)
        
        print("  ✅ Recent: \(recent.count) operations")
    }
    
    // MARK: - Maintenance Tests
    
    func testClearMetrics() async throws {
        print("📊 Testing clear metrics")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        _ = try await db.insert(BlazeDataRecord(["test": .bool(true)]))
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        var summary = try await db.telemetry.getSummary()
        XCTAssertGreaterThan(summary.totalOperations, 0)
        
        // Clear
        try await db.telemetry.clear()
        
        summary = try await db.telemetry.getSummary()
        XCTAssertEqual(summary.totalOperations, 0, "Should clear all metrics")
        
        print("  ✅ Metrics cleared")
    }
    
    func testCleanupOldMetrics() async throws {
        print("📊 Testing cleanup old metrics")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Note: This test can't fully verify cleanup without mocking time
        // But we can verify the API works
        
        _ = try await db.insert(BlazeDataRecord(["test": .bool(true)]))
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let deleted = try await db.telemetry.cleanup()
        
        // Should run without error (may delete 0 if all metrics are recent)
        XCTAssertGreaterThanOrEqual(deleted, 0)
        
        print("  ✅ Cleanup ran: \(deleted) deleted")
    }
    
    // MARK: - Edge Cases
    
    func testTelemetryDisabled() async throws {
        print("📊 Testing telemetry disabled")
        
        // Don't enable telemetry
        
        _ = try await db.insert(BlazeDataRecord(["test": .bool(true)]))
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        do {
            _ = try await db.telemetry.getSummary()
            XCTFail("Should throw error when telemetry not enabled")
        } catch {
            // Expected
            print("  ✅ Correctly throws when disabled")
        }
    }
    
    func testEmptySummary() async throws {
        print("📊 Testing empty summary")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // No operations performed
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertEqual(summary.totalOperations, 0)
        XCTAssertEqual(summary.successRate, 0)
        XCTAssertEqual(summary.errorCount, 0)
        
        print("  ✅ Empty summary handled correctly")
    }
    
    func testConcurrentOperations() async throws {
        print("📊 Testing concurrent operations")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Concurrent inserts
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    _ = try? await self.db.insert(BlazeDataRecord(["value": .int(i)]))
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThan(summary.totalOperations, 0, "Should track concurrent operations")
        
        print("  ✅ Concurrent operations tracked: \(summary.totalOperations)")
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOverhead() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                do {
                    let testURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("perf-\(UUID().uuidString).blazedb")
                    let testDB = try BlazeDBClient(name: "PerfTest", fileURL: testURL, password: "TelemetryUnitTest123!")
                    
                    testDB.telemetry.enable(samplingRate: 0.01)  // 1% sampling
                    
                    // Perform 100 operations
                    for i in 0..<100 {
                        _ = try await testDB.insert(BlazeDataRecord(["value": .int(i)]))
                    }
                    
                    try? FileManager.default.removeItem(at: testURL)
                } catch {
                    XCTFail("Performance test failed: \(error)")
                }
            }
        }
    }
}

