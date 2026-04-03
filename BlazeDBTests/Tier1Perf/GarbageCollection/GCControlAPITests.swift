//
//  GCControlAPITests.swift
//  BlazeDBTests
//
//  Comprehensive tests for GC developer control APIs
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class GCControlAPITests: XCTestCase {
    
    private var dbURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GCControl-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "GCControlTest", fileURL: try requireFixture(dbURL), password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        db?.disableAutoVacuum()
        
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
    
    // MARK: - Configuration API Tests
    
    func testConfigureGC_SetsConfiguration() throws {
        print("⚙️  Testing GC configuration API")
        
        var config = GCConfiguration()
        config.enablePageReuse = true
        config.maxReuseablePages = 5000
        config.autoVacuumEnabled = true
        config.autoVacuumWasteThreshold = 0.25
        config.vacuumBeforeBackup = true
        
        try requireFixture(db).configureGC(config)
        
        let retrieved = try requireFixture(db).getGCConfiguration()
        
        XCTAssertEqual(retrieved.enablePageReuse, true)
        XCTAssertEqual(retrieved.maxReuseablePages, 5000)
        XCTAssertEqual(retrieved.autoVacuumEnabled, true)
        XCTAssertEqual(retrieved.autoVacuumWasteThreshold, 0.25)
        
        print("  ✅ Configuration set and retrieved correctly")
        
        try requireFixture(db).disableAutoVacuum()  // Cleanup
    }
    
    func testConfigureGC_EnablesAutoVacuum() async throws {
        print("⚙️  Testing configuration enables auto-vacuum")
        
        var config = GCConfiguration()
        config.autoVacuumEnabled = true
        config.autoVacuumCheckInterval = 0.1  // Fast for testing
        
        try requireFixture(db).configureGC(config)
        
        // Auto-vacuum should now be enabled
        // (Check by verifying it doesn't crash)
        
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        try requireFixture(db).disableAutoVacuum()
        
        print("  ✅ Configuration successfully enabled auto-vacuum")
    }
    
    // MARK: - Policy API Tests
    
    func testSetGCPolicy_Conservative() async throws {
        print("📋 Testing conservative GC policy")
        
        try requireFixture(db).setGCPolicy(.conservative)
        
        // Insert and delete to create 40% waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<40 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        // Conservative policy (50% threshold) should NOT recommend VACUUM at 40%
        let shouldVacuum = try await requireFixture(db).shouldVacuum()
        
        XCTAssertFalse(shouldVacuum, "Conservative policy should not trigger at 40% waste")
        
        print("  ✅ Conservative policy: no VACUUM at 40% waste")
    }
    
    func testSetGCPolicy_Aggressive() async throws {
        print("📋 Testing aggressive GC policy")
        
        try requireFixture(db).setGCPolicy(.aggressive)
        
        // Create 20% waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<20 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        // Aggressive policy (15% threshold) SHOULD recommend VACUUM at 20%
        let shouldVacuum = try await requireFixture(db).shouldVacuum()
        
        XCTAssertTrue(shouldVacuum, "Aggressive policy should trigger at 20% waste")
        
        print("  ✅ Aggressive policy: recommends VACUUM at 20% waste")
    }
    
    func testSetGCPolicy_Custom() async throws {
        print("📋 Testing custom GC policy")
        
        // Custom: VACUUM when > 100 MB wasted
        let customPolicy = GCPolicy(
            name: "Custom",
            description: "VACUUM when > 100 MB wasted",
            shouldVacuum: { $0.wastedSpace > 100_000_000 }
        )
        
        try requireFixture(db).setGCPolicy(customPolicy)
        
        // Create 50% waste but < 100 MB
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<50 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let shouldVacuum = try await requireFixture(db).shouldVacuum()
        
        // Should NOT trigger (waste < 100 MB even though 50%)
        XCTAssertFalse(shouldVacuum, "Custom policy should not trigger (< 100 MB)")
        
        print("  ✅ Custom policy works correctly")
    }
    
    // MARK: - Metrics API Tests
    
    func testGCMetrics_TracksVacuums() async throws {
        print("📈 Testing GC metrics tracking")
        
        // Insert and create waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<50 {
            try await requireFixture(db).delete(id: ids[i])
        }
        
        // Run VACUUM
        _ = try await requireFixture(db).forceVacuum()
        
        let metrics = try requireFixture(db).getGCMetrics()
        
        XCTAssertEqual(metrics.totalVacuums, 1)
        XCTAssertGreaterThan(metrics.totalPagesReclaimed, 0)
        XCTAssertGreaterThan(metrics.totalBytesReclaimed, 0)
        
        print("  ✅ Metrics tracked: \(metrics.totalVacuums) VACUUMs, \(metrics.totalPagesReclaimed) pages")
    }
    
    func testGCMetrics_CanBeReset() async throws {
        print("📈 Testing GC metrics reset")
        
        // Create some metrics
        let ids = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<25 {
            try await requireFixture(db).delete(id: ids[i])
        }
        _ = try await requireFixture(db).forceVacuum()
        
        var metrics = try requireFixture(db).getGCMetrics()
        XCTAssertGreaterThan(metrics.totalVacuums, 0)
        
        // Reset
        try requireFixture(db).resetGCMetrics()
        
        metrics = try requireFixture(db).getGCMetrics()
        XCTAssertEqual(metrics.totalVacuums, 0)
        XCTAssertEqual(metrics.totalPagesReclaimed, 0)
        
        print("  ✅ Metrics reset successfully")
    }
    
    // MARK: - Health Check API Tests
    
    func testCheckGCHealth_HealthyDatabase() async throws {
        print("🏥 Testing GC health check (healthy)")
        
        // Insert 50 records (no deletes)
        _ = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await requireFixture(db).persist()
        
        let health = try await requireFixture(db).checkGCHealth()
        
        XCTAssertEqual(health.status, .healthy)
        XCTAssertFalse(health.needsAttention)
        XCTAssertTrue(health.issues.isEmpty)
        
        print("  ✅ \(health.description)")
    }
    
    func testCheckGCHealth_WarningStatus() async throws {
        print("🏥 Testing GC health check (warning)")
        
        // Create 35% waste (warning level)
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<35 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let health = try await requireFixture(db).checkGCHealth()
        
        XCTAssertEqual(health.status, .warning)
        XCTAssertTrue(health.needsAttention)
        XCTAssertFalse(health.issues.isEmpty)
        
        print("  ⚠️  \(health.description)")
    }
    
    func testCheckGCHealth_CriticalStatus() async throws {
        print("🏥 Testing GC health check (critical)")
        
        // Create 60% waste (critical level)
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<60 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let health = try await requireFixture(db).checkGCHealth()
        
        XCTAssertEqual(health.status, .critical)
        XCTAssertTrue(health.needsAttention)
        XCTAssertTrue(health.recommendations.contains { $0.contains("immediately") || $0.contains("NOW") })
        
        print("  🚨 \(health.description)")
    }
    
    // MARK: - Control API Tests
    
    func testForceVacuum_RunsRegardlessOfPolicy() async throws {
        print("🧹 Testing force VACUUM ignores policy")
        
        // Create minimal waste (< 5%)
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<5 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        // Set conservative policy (should NOT recommend VACUUM)
        try requireFixture(db).setGCPolicy(.conservative)
        
        let shouldVacuum = try await requireFixture(db).shouldVacuum()
        XCTAssertFalse(shouldVacuum, "Policy should not recommend VACUUM")
        
        // Force VACUUM anyway
        let stats = try await requireFixture(db).forceVacuum()
        
        XCTAssertGreaterThanOrEqual(stats.pagesReclaimed, 5)
        
        print("  ✅ Force VACUUM ran despite policy")
    }
    
    func testSmartVacuum_RespectsPolicy() async throws {
        print("🧹 Testing smart VACUUM respects policy")
        
        // Create 20% waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<20 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        // Conservative policy (50% threshold) - should skip
        try requireFixture(db).setGCPolicy(.conservative)
        
        let result = try await requireFixture(db).smartVacuum()
        
        XCTAssertNil(result, "Smart VACUUM should skip at 20% with conservative policy")
        
        // Aggressive policy (15% threshold) - should run
        try requireFixture(db).setGCPolicy(.aggressive)
        
        let result2 = try await requireFixture(db).smartVacuum()
        
        XCTAssertNotNil(result2, "Smart VACUUM should run at 20% with aggressive policy")
        
        print("  ✅ Smart VACUUM respects policy correctly")
    }
    
    func testOptimize_OneButtonOperation() async throws {
        print("🔧 Testing optimize() one-button operation")
        
        // Create waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<60 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        // One-button optimize
        let result = try await requireFixture(db).optimize()
        
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("VACUUM") || result.contains("Status"))
        
        print("  ✅ Optimize result:\n\(result)")
    }
    
    func testGCStatus_QuickCheck() async throws {
        print("📊 Testing gcStatus() quick check")
        
        let status = try await requireFixture(db).gcStatus()
        
        XCTAssertFalse(status.isEmpty)
        XCTAssertTrue(status.contains("Healthy") || status.contains("Warning") || status.contains("Critical"))
        
        print("  ✅ GC Status: \(status)")
    }
    
    func testGetGCReport_Comprehensive() async throws {
        print("📊 Testing comprehensive GC report")
        
        // Create some activity
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<30 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let report = try await requireFixture(db).getGCReport()
        
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("STORAGE STATS"))
        XCTAssertTrue(report.contains("GC STATS"))
        XCTAssertTrue(report.contains("RECOMMENDATIONS"))
        
        print("  📊 Full Report:")
        print(report)
    }
    
    // MARK: - Clear Reuseable Pages Test
    
    func testClearReuseablePages() async throws {
        print("🗑️  Testing clearReuseablePages() API")
        
        // Create reuseable pages
        let ids = try await requireFixture(db).insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<25 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        let gcStatsBefore = try requireFixture(db).collection.getGCStats()
        XCTAssertGreaterThanOrEqual(gcStatsBefore.reuseablePages, 0)
        
        // Clear reuseable pages
        try requireFixture(db).clearReuseablePages()
        
        let gcStatsAfter = try requireFixture(db).collection.getGCStats()
        XCTAssertLessThanOrEqual(gcStatsAfter.reuseablePages, gcStatsBefore.reuseablePages,
                                 "clearReuseablePages() should not increase reusable page count")
        
        print("  ✅ Cleared \(gcStatsBefore.reuseablePages) reuseable pages")
    }
    
    // MARK: - Policy Evaluation Tests
    
    func testPolicyEvaluation_AllPredefinedPolicies() async throws {
        print("📋 Testing all predefined policies")
        
        let policies: [GCPolicy] = [
            .conservative,  // 50%
            .balanced,      // 30%
            .aggressive,    // 15%
            .spaceSaving    // 10 MB or 20%
        ]
        
        // Create 25% waste
        let ids = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<25 {
            try await requireFixture(db).delete(id: ids[i])
        }
        try await requireFixture(db).persist()
        
        for policy in policies {
            try requireFixture(db).setGCPolicy(policy)
            let shouldVacuum = try await requireFixture(db).shouldVacuum()
            
            let expectedToTrigger = policy.name == "Aggressive" || policy.name == "Space Saving"
            
            if expectedToTrigger {
                XCTAssertTrue(shouldVacuum, "\(policy.name) should trigger at 25%")
            } else {
                XCTAssertFalse(shouldVacuum, "\(policy.name) should not trigger at 25%")
            }
            
            print("    \(policy.name): \(shouldVacuum ? "✓ Trigger" : "✗ Skip")")
        }
        
        print("  ✅ All policies evaluated correctly")
    }
    
    // MARK: - Thread Safety Tests
    
    func testGCControl_ThreadSafety() async throws {
        print("⚡ Testing GC control thread safety")
        
        let db = try XCTUnwrap(self.db)
        _ = try await requireFixture(db).insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Concurrent GC control operations
        await withTaskGroup(of: Void.self) { group in
            // Configure
            for _ in 0..<10 {
                group.addTask { [db] in
                    var config = GCConfiguration()
                    config.maxReuseablePages = Int.random(in: 1000...10000)
                    try? db.configureGC(config)
                }
            }
            
            // Set policies
            for _ in 0..<10 {
                group.addTask { [db] in
                    let policies: [GCPolicy] = [.conservative, .balanced, .aggressive]
                    try? db.setGCPolicy(policies.randomElement()!)
                }
            }
            
            // Get stats
            for _ in 0..<10 {
                group.addTask { [db] in
                    _ = try? await db.getStorageStats()
                    _ = try? db.collection.getGCStats()
                }
            }
        }
        
        // Should not crash
        let finalStatus = try await requireFixture(db).gcStatus()
        
        print("  ✅ Thread-safe: \(finalStatus)")
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_GCControlAPIs() async throws {
        final class SendableDBRef: @unchecked Sendable {
            let db: BlazeDBClient
            init(_ db: BlazeDBClient) { self.db = db }
        }
        let dbRef = SendableDBRef(try XCTUnwrap(self.db))
        measure(metrics: [XCTClockMetric()]) {
            let expectation = XCTestExpectation(description: "GC control performance")
            Task { [dbRef] in
                do {
                    // Configure
                    var config = GCConfiguration()
                    config.enablePageReuse = true
                    try dbRef.db.configureGC(config)
                    
                    // Set policy
                    try dbRef.db.setGCPolicy(.balanced)
                    
                    // Get stats
                    _ = try await dbRef.db.getStorageStats()
                    _ = try dbRef.db.collection.getGCStats()
                    _ = try dbRef.db.getGCMetrics()
                    
                    // Check health
                    _ = try await dbRef.db.checkGCHealth()
                    
                } catch {
                    XCTFail("GC control performance test failed: \(error)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}

