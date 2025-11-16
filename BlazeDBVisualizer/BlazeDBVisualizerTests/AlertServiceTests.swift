//
//  AlertServiceTests.swift
//  BlazeDBVisualizerTests
//
//  Comprehensive tests for alert system
//  ✅ Health monitoring
//  ✅ Threshold configuration
//  ✅ Spam prevention
//  ✅ Notification handling
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class AlertServiceTests: XCTestCase {
    
    var service: AlertService!
    
    override func setUp() {
        super.setUp()
        service = AlertService.shared
        service.recentAlerts.removeAll()
        service.config = .default
    }
    
    override func tearDown() {
        service.clearAlerts()
        super.tearDown()
    }
    
    // MARK: - Health Check Tests
    
    func testHighFragmentationAlert() {
        let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        XCTAssertFalse(service.recentAlerts.isEmpty, "Should create alert for high fragmentation")
        XCTAssertTrue(service.recentAlerts.first?.type == .highFragmentation)
    }
    
    func testLowFragmentationNoAlert() {
        let snapshot = createMockSnapshot(fragmentationPercent: 10.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        let fragmentationAlerts = service.recentAlerts.filter { $0.type == .highFragmentation }
        XCTAssertTrue(fragmentationAlerts.isEmpty, "Should not alert for low fragmentation")
    }
    
    func testDatabaseSizeAlert() {
        service.config.maxDatabaseSize = 1_000_000  // 1 MB
        let snapshot = createMockSnapshot(fileSizeBytes: 2_000_000)  // 2 MB
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        XCTAssertTrue(service.recentAlerts.contains { $0.type == .databaseTooLarge })
    }
    
    func testObsoleteVersionsAlert() {
        service.config.obsoleteVersionsThreshold = 100
        let snapshot = createMockSnapshot(obsoleteVersions: 500)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        XCTAssertTrue(service.recentAlerts.contains { $0.type == .gcNeeded })
    }
    
    func testOrphanedPagesAlert() {
        service.config.orphanedPagesThreshold = 50
        let snapshot = createMockSnapshot(orphanedPages: 150)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        XCTAssertTrue(service.recentAlerts.contains { $0.type == .orphanedPages })
    }
    
    // MARK: - Spam Prevention Tests
    
    func testAlertSpamPrevention() {
        let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
        
        // First alert should go through
        service.checkHealth(snapshot: snapshot, dbName: "test")
        XCTAssertEqual(service.recentAlerts.count, 1)
        
        // Immediate second alert should be blocked
        service.checkHealth(snapshot: snapshot, dbName: "test")
        XCTAssertEqual(service.recentAlerts.count, 1, "Should not send duplicate alert immediately")
    }
    
    func testDifferentDatabasesGetSeparateAlerts() {
        let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "db1")
        service.checkHealth(snapshot: snapshot, dbName: "db2")
        
        XCTAssertEqual(service.recentAlerts.count, 2, "Different databases should get separate alerts")
    }
    
    // MARK: - Alert Severity Tests
    
    func testCriticalSeverityForHighFragmentation() {
        let snapshot = createMockSnapshot(fragmentationPercent: 75.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        let alert = service.recentAlerts.first
        XCTAssertEqual(alert?.severity, .critical, "Very high fragmentation should be critical")
    }
    
    func testWarningSeverityForMediumFragmentation() {
        let snapshot = createMockSnapshot(fragmentationPercent: 35.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        let alert = service.recentAlerts.first
        XCTAssertEqual(alert?.severity, .warning, "Medium fragmentation should be warning")
    }
    
    // MARK: - Configuration Tests
    
    func testDisableNotifications() {
        service.config.notificationsEnabled = false
        let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        // Should still track alerts
        XCTAssertFalse(service.recentAlerts.isEmpty)
        // But shouldn't send notification (can't easily test, but it's in the code)
    }
    
    func testCustomThresholds() {
        service.config.fragmentationThreshold = 20.0  // Lower threshold
        let snapshot = createMockSnapshot(fragmentationPercent: 25.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        XCTAssertFalse(service.recentAlerts.isEmpty, "Should alert with custom threshold")
    }
    
    func testDisabledThreshold() {
        service.config.fragmentationThreshold = 0  // Disabled
        let snapshot = createMockSnapshot(fragmentationPercent: 90.0)
        
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        let fragmentationAlerts = service.recentAlerts.filter { $0.type == .highFragmentation }
        XCTAssertTrue(fragmentationAlerts.isEmpty, "Disabled threshold should not alert")
    }
    
    // MARK: - Alert Management Tests
    
    func testClearAlerts() {
        let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        XCTAssertFalse(service.recentAlerts.isEmpty)
        
        service.clearAlerts()
        
        XCTAssertTrue(service.recentAlerts.isEmpty)
    }
    
    func testDismissAlert() {
        let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
        service.checkHealth(snapshot: snapshot, dbName: "test")
        
        guard let alert = service.recentAlerts.first else {
            XCTFail("Should have alert")
            return
        }
        
        service.dismissAlert(alert)
        
        XCTAssertTrue(service.recentAlerts.isEmpty)
    }
    
    func testAlertHistoryLimit() {
        // Create 100 alerts
        for i in 0..<100 {
            let snapshot = createMockSnapshot(fragmentationPercent: 45.0)
            // Use unique db names to bypass spam prevention
            service.checkHealth(snapshot: snapshot, dbName: "db\(i)")
        }
        
        XCTAssertLessThanOrEqual(service.recentAlerts.count, 50, "Should keep max 50 alerts")
    }
    
    // MARK: - Helper Functions
    
    private func createMockSnapshot(
        fragmentationPercent: Double = 0,
        fileSizeBytes: Int64 = 1000,
        obsoleteVersions: Int = 0,
        orphanedPages: Int = 0
    ) -> DatabaseMonitoringSnapshot {
        let dbInfo = DatabaseInfo(
            name: "test",
            path: "/test.blazedb",
            createdAt: Date(),
            lastModified: Date(),
            isEncrypted: true,
            version: "1.0",
            formatVersion: "blazeBinary"
        )
        
        let storageInfo = StorageInfo(
            totalRecords: 100,
            totalPages: 100,
            orphanedPages: orphanedPages,
            fileSizeBytes: fileSizeBytes,
            metadataSizeBytes: 1000,
            dataFilePath: "/test.blazedb",
            metadataFilePath: "/test.meta",
            fragmentationPercent: fragmentationPercent,
            avgRecordSizeBytes: 1000,
            largestRecordBytes: 2000
        )
        
        let perfInfo = PerformanceInfo(
            mvccEnabled: false,
            activeTransactions: 0,
            totalVersions: 100,
            obsoleteVersions: obsoleteVersions,
            gcRunCount: 0,
            lastGCDuration: nil,
            indexCount: 0,
            indexNames: []
        )
        
        let healthInfo = HealthInfo(
            status: "healthy",
            needsVacuum: false,
            fragmentationHigh: fragmentationPercent > 30,
            orphanedPagesHigh: orphanedPages > 100,
            gcNeeded: obsoleteVersions > 1000,
            warnings: []
        )
        
        let schemaInfo = SchemaInfo(
            totalFields: 3,
            commonFields: ["id", "name"],
            customFields: ["email"],
            inferredTypes: ["id": "int", "name": "string", "email": "string"]
        )
        
        return DatabaseMonitoringSnapshot(
            database: dbInfo,
            storage: storageInfo,
            performance: perfInfo,
            health: healthInfo,
            schema: schemaInfo
        )
    }
}

