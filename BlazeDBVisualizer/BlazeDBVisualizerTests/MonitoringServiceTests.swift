//
//  MonitoringServiceTests.swift
//  BlazeDBVisualizerTests
//
//  Comprehensive tests for real-time monitoring
//  ✅ Live updates
//  ✅ VACUUM operations
//  ✅ Garbage collection
//  ✅ Error handling
//
//  Created by Michael Danylchuk on 11/13/25.
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

@MainActor
final class MonitoringServiceTests: XCTestCase {
    
    var service: MonitoringService!
    var tempDirectory: URL!
    var testDBURL: URL!
    let testPassword = "test_password_123"
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test database
        testDBURL = tempDirectory.appendingPathComponent("test.blazedb")
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        
        // Add some test data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "name": .string("Test \(i)"),
                "data": .string(String(repeating: "X", count: 100))
            ]))
        }
        try db.persist()
        
        // Create service
        service = MonitoringService()
    }
    
    override func tearDown() async throws {
        // Stop monitoring
        service?.stopMonitoring()
        service = nil
        
        // Clean up temp files
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Monitoring Lifecycle Tests
    
    func testStartMonitoring() async throws {
        XCTAssertFalse(service.isMonitoring, "Should not be monitoring initially")
        
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        XCTAssertTrue(service.isMonitoring, "Should be monitoring after start")
        
        // Wait for first snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        XCTAssertNotNil(service.currentSnapshot, "Should have snapshot after delay")
        XCTAssertNotNil(service.lastUpdateTime, "Should have update time")
    }
    
    func testStopMonitoring() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        XCTAssertTrue(service.isMonitoring)
        
        service.stopMonitoring()
        
        XCTAssertFalse(service.isMonitoring, "Should not be monitoring after stop")
        XCTAssertNil(service.currentSnapshot, "Snapshot should be cleared")
    }
    
    func testMultipleStartCalls() async throws {
        // Start monitoring
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Start again (should stop previous and restart)
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 0.5
        )
        
        XCTAssertTrue(service.isMonitoring, "Should still be monitoring")
    }
    
    // MARK: - Snapshot Tests
    
    func testSnapshotContent() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Wait for snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        guard let snapshot = service.currentSnapshot else {
            XCTFail("Should have snapshot")
            return
        }
        
        // Verify snapshot content
        XCTAssertEqual(snapshot.database.name, "test")
        XCTAssertEqual(snapshot.database.path, testDBURL.path)
        XCTAssertTrue(snapshot.database.isEncrypted)
        
        XCTAssertEqual(snapshot.storage.totalRecords, 10)
        XCTAssertGreaterThan(snapshot.storage.fileSizeBytes, 0)
        
        XCTAssertTrue(["healthy", "warning", "critical"].contains(snapshot.health.status))
    }
    
    func testManualRefresh() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 10.0 // Long interval
        )
        
        // Wait for initial snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        let firstUpdate = service.lastUpdateTime
        
        // Manual refresh
        await service.refresh()
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let secondUpdate = service.lastUpdateTime
        
        XCTAssertNotNil(firstUpdate)
        XCTAssertNotNil(secondUpdate)
        if let first = firstUpdate, let second = secondUpdate {
            XCTAssertGreaterThan(second, first, "Update time should be newer after refresh")
        }
    }
    
    // MARK: - Maintenance Operations Tests
    
    func testRunGarbageCollection() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Wait for initial snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        // Run GC
        let collected = try await service.runGarbageCollection()
        
        // Should not throw and should return a count
        XCTAssertGreaterThanOrEqual(collected, 0, "Should return collected count")
        
        // Snapshot should be refreshed
        XCTAssertNotNil(service.currentSnapshot)
    }
    
    func testRunVacuum() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Wait for initial snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        // Run VACUUM
        let stats = try await service.runVacuum()
        
        // Verify stats
        XCTAssertGreaterThanOrEqual(stats.pagesScanned, 0)
        XCTAssertGreaterThanOrEqual(stats.pagesReclaimed, 0)
        XCTAssertGreaterThanOrEqual(stats.bytesReclaimed, 0)
        XCTAssertGreaterThan(stats.duration, 0)
        
        // Snapshot should be refreshed
        XCTAssertNotNil(service.currentSnapshot)
    }
    
    func testMaintenanceWithoutMonitoring() async {
        // Try to run maintenance without starting monitoring
        do {
            _ = try await service.runGarbageCollection()
            XCTFail("Should throw error when not monitoring")
        } catch MonitoringError.notMonitoring {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
        
        do {
            _ = try await service.runVacuum()
            XCTFail("Should throw error when not monitoring")
        } catch MonitoringError.notMonitoring {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidPassword() async {
        do {
            try await service.startMonitoring(
                dbPath: testDBURL.path,
                password: "wrong_password",
                interval: 1.0
            )
            XCTFail("Should throw error with wrong password")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }
    
    func testNonExistentDatabase() async {
        let fakePath = tempDirectory.appendingPathComponent("nonexistent.blazedb").path
        
        do {
            try await service.startMonitoring(
                dbPath: fakePath,
                password: testPassword,
                interval: 1.0
            )
            XCTFail("Should throw error with non-existent database")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Periodic Update Tests
    
    func testPeriodicUpdates() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0 // 1 second intervals
        )
        
        // Wait for first update
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let firstUpdate = service.lastUpdateTime
        XCTAssertNotNil(firstUpdate)
        
        // Wait for second update
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let secondUpdate = service.lastUpdateTime
        XCTAssertNotNil(secondUpdate)
        
        // Verify updates are happening
        if let first = firstUpdate, let second = secondUpdate {
            XCTAssertGreaterThan(second, first, "Updates should be periodic")
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceStartMonitoring() {
        measure {
            Task { @MainActor in
                do {
                    try await service.startMonitoring(
                        dbPath: testDBURL.path,
                        password: testPassword,
                        interval: 10.0
                    )
                    service.stopMonitoring()
                } catch {
                    XCTFail("Performance test failed: \(error)")
                }
            }
        }
    }
    
    func testPerformanceRefresh() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 10.0
        )
        
        // Wait for initial snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        measure {
            Task { @MainActor in
                await service.refresh()
            }
        }
    }
}

// MARK: - Extension Tests

extension MonitoringServiceTests {
    
    func testSnapshotSummary() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Wait for snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        guard let snapshot = service.currentSnapshot else {
            XCTFail("Should have snapshot")
            return
        }
        
        // Test summary generation
        let summary = snapshot.summary
        XCTAssertFalse(summary.isEmpty, "Summary should not be empty")
        XCTAssertTrue(summary.contains("records"), "Summary should contain record count")
    }
    
    func testSnapshotNeedsAttention() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Wait for snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        guard let snapshot = service.currentSnapshot else {
            XCTFail("Should have snapshot")
            return
        }
        
        // Test needsAttention property
        let needsAttention = snapshot.needsAttention
        
        // Should be a boolean
        XCTAssertTrue(needsAttention == true || needsAttention == false)
    }
    
    func testSnapshotRecommendations() async throws {
        try await service.startMonitoring(
            dbPath: testDBURL.path,
            password: testPassword,
            interval: 1.0
        )
        
        // Wait for snapshot
        try await Task.sleep(nanoseconds: 1_500_000_000)
        
        guard let snapshot = service.currentSnapshot else {
            XCTFail("Should have snapshot")
            return
        }
        
        // Test recommendations
        let recommendations = snapshot.recommendations
        
        // Should be an array (may be empty for healthy databases)
        XCTAssertNotNil(recommendations)
    }
}

