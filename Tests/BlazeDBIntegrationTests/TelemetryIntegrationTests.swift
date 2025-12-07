//
//  TelemetryIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests for telemetry in real-world scenarios
//

import XCTest
@testable import BlazeDB

final class TelemetryIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Telemetry-Integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        
        // Clean up metrics database
        let metricsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".blazedb/metrics/telemetry.blazedb")
        try? FileManager.default.removeItem(at: metricsURL)
        
        super.tearDown()
    }
    
    // MARK: - Real-World Scenario 1: Bug Tracker
    
    func testTelemetry_BugTrackerScenario() async throws {
        print("\n🐛 INTEGRATION: Bug Tracker with Telemetry")
        
        let dbURL = tempDir.appendingPathComponent("ashpile.blazedb")
        let db = try BlazeDBClient(name: "AshPile", fileURL: dbURL, password: "test-pass-123456")
        
        // Enable telemetry with 10% sampling
        db.telemetry.enable(samplingRate: 0.10)
        
        print("  📊 Telemetry enabled (10% sampling)")
        
        // Day 1: Create bugs
        print("  📝 Day 1: Creating 20 bugs...")
        for i in 1...20 {
            _ = try await db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string("open"),
                "priority": .string(i % 3 == 0 ? "high" : "normal")
            ]))
        }
        
        // Day 2: Query bugs
        print("  🔍 Day 2: Querying bugs...")
        let openBugs = try await db.query()
            .where("status", equals: .string("open"))
            .execute()
        print("    Found \(openBugs.count) open bugs")
        
        let highPriorityBugs = try await db.query()
            .where("priority", equals: .string("high"))
            .execute()
        print("    Found \(highPriorityBugs.count) high-priority bugs")
        
        // Day 3: Update bugs
        print("  ✏️  Day 3: Updating bugs...")
        let openBugsRecords = try openBugs.records
        if let firstBug = openBugsRecords.first?.storage["id"]?.uuidValue {
            try await db.update(id: firstBug, with: BlazeDataRecord(["status": .string("in-progress")]))
        }
        
        // Allow telemetry to record
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Check telemetry
        print("\n  📊 TELEMETRY RESULTS:")
        let summary = try await db.telemetry.getSummary()
        
        print("    Total operations: \(summary.totalOperations)")
        print("    Success rate: \(String(format: "%.1f", summary.successRate))%")
        print("    Average duration: \(String(format: "%.2f", summary.avgDuration))ms")
        
        XCTAssertGreaterThan(summary.totalOperations, 0, "Should track operations")
        XCTAssertEqual(summary.successRate, 100.0, "All operations should succeed")
        XCTAssertLessThan(summary.avgDuration, 100, "Operations should be fast")
        
        // Check operation breakdown
        let breakdown = try await db.telemetry.getOperationBreakdown()
        print("\n    Operation breakdown:")
        for (op, stats) in breakdown.operations.sorted(by: { $0.key < $1.key }) {
            print("      • \(op): \(stats.count) ops (\(String(format: "%.0f", stats.percentage))%)")
        }
        
        XCTAssertFalse(breakdown.operations.isEmpty, "Should have operation breakdown")
        
        print("\n  ✅ Bug tracker scenario complete")
    }
    
    // MARK: - Real-World Scenario 2: Performance Monitoring
    
    func testTelemetry_PerformanceMonitoring() async throws {
        print("\n⚡ INTEGRATION: Performance Monitoring")
        
        let dbURL = tempDir.appendingPathComponent("perftest.blazedb")
        let db = try BlazeDBClient(name: "PerfTest", fileURL: dbURL, password: "test-pass-123456")
        
        db.telemetry.enable(samplingRate: 1.0)  // 100% for accurate monitoring
        
        print("  📊 Performing operations...")
        
        // Perform various operations
        for i in 0..<50 {
            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        _ = try await db.fetchAll()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check for slow operations
        print("\n  🔍 Checking for slow operations...")
        let slowOps = try await db.telemetry.getSlowOperations(threshold: 10.0)
        
        if slowOps.isEmpty {
            print("    ✅ No slow operations (all < 10ms)")
        } else {
            print("    ⚠️  Found \(slowOps.count) slow operations:")
            for (i, op) in slowOps.prefix(3).enumerated() {
                print("      \(i + 1). \(op.operation): \(String(format: "%.2f", op.duration))ms")
            }
        }
        
        // Get performance summary
        let summary = try await db.telemetry.getSummary()
        
        print("\n  📊 Performance Summary:")
        print("    Average: \(String(format: "%.2f", summary.avgDuration))ms")
        print("    p95: \(String(format: "%.2f", summary.p95Duration))ms")
        print("    p99: \(String(format: "%.2f", summary.p99Duration))ms")
        
        // Verify performance is acceptable
        XCTAssertLessThan(summary.avgDuration, 50, "Average should be < 50ms")
        XCTAssertLessThan(summary.p95Duration, 100, "p95 should be < 100ms")
        
        print("\n  ✅ Performance monitoring complete")
    }
    
    // MARK: - Real-World Scenario 3: Error Tracking
    
    func testTelemetry_ErrorTracking() async throws {
        print("\n❌ INTEGRATION: Error Tracking")
        
        let dbURL = tempDir.appendingPathComponent("errortest.blazedb")
        let db = try BlazeDBClient(name: "ErrorTest", fileURL: dbURL, password: "test-pass-123456")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        print("  📊 Performing operations with errors...")
        
        // Successful operations
        let id1 = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        let id2 = try await db.insert(BlazeDataRecord(["value": .int(2)]))
        
        // Failed operations
        for _ in 0..<3 {
            try? await db.delete(id: UUID())  // Non-existent ID
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check errors
        print("\n  🔍 Checking for errors...")
        let errors = try await db.telemetry.getErrors()
        
        print("    Total errors: \(errors.count)")
        for (i, error) in errors.enumerated() {
            print("      \(i + 1). \(error.operation): \(error.errorMessage)")
        }
        
        XCTAssertEqual(errors.count, 3, "Should track 3 failed operations")
        XCTAssertEqual(errors.first?.operation, "delete")
        
        // Check success rate
        let summary = try await db.telemetry.getSummary()
        print("\n  📊 Success rate: \(String(format: "%.1f", summary.successRate))%")
        
        XCTAssertLessThan(summary.successRate, 100, "Should have some failures")
        XCTAssertGreaterThan(summary.successRate, 0, "Should have some successes")
        
        print("\n  ✅ Error tracking complete")
    }
    
    // MARK: - Real-World Scenario 4: Usage Analytics
    
    func testTelemetry_UsageAnalytics() async throws {
        print("\n📈 INTEGRATION: Usage Analytics")
        
        let dbURL = tempDir.appendingPathComponent("analytics.blazedb")
        let db = try BlazeDBClient(name: "Analytics", fileURL: dbURL, password: "test-pass-123456")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        print("  📊 Simulating user behavior...")
        
        // Simulate: User mostly queries, occasionally inserts
        for _ in 0..<5 {
            _ = try await db.insert(BlazeDataRecord(["data": .string("value")]))
        }
        
        for _ in 0..<20 {
            _ = try await db.fetchAll()
        }
        
        for _ in 0..<3 {
            let all = try await db.fetchAll()
            if let first = all.first?.storage["id"]?.uuidValue {
                try await db.update(id: first, with: BlazeDataRecord(["updated": .bool(true)]))
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Analyze usage
        print("\n  📊 Usage Analysis:")
        let breakdown = try await db.telemetry.getOperationBreakdown()
        
        for (op, stats) in breakdown.operations.sorted(by: { $0.value.count > $1.value.count }) {
            print("    • \(op): \(stats.count) ops (\(String(format: "%.1f", stats.percentage))%)")
        }
        
        // Verify patterns
        let fetchAllCount = breakdown.operations["fetchAll"]?.count ?? 0
        let insertCount = breakdown.operations["insert"]?.count ?? 0
        
        XCTAssertGreaterThan(fetchAllCount, insertCount, "Should have more fetches than inserts")
        
        print("\n  ✅ Usage analytics complete")
    }
    
    // MARK: - Real-World Scenario 5: Optimization Validation
    
    func testTelemetry_OptimizationValidation() async throws {
        print("\n🔧 INTEGRATION: Optimization Validation")
        
        let dbURL = tempDir.appendingPathComponent("optimize.blazedb")
        let db = try BlazeDBClient(name: "Optimize", fileURL: dbURL, password: "test-pass-123456")
        
        db.telemetry.enable(samplingRate: 1.0)
        
        // Phase 1: Without index
        print("  📊 Phase 1: Without index")
        for i in 0..<20 {
            _ = try await db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "value": .int(i)
            ]))
        }
        
        for _ in 0..<5 {
            _ = try await db.query().where("status", equals: .string("open")).execute()
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let beforeStats = try await db.telemetry.getSummary()
        let beforeAvg = beforeStats.avgDuration
        
        print("    Average query time: \(String(format: "%.2f", beforeAvg))ms")
        
        // Clear metrics for phase 2
        try await db.telemetry.clear()
        
        // Phase 2: With index
        print("\n  📊 Phase 2: With index")
        try db.collection.createIndex(on: "status")
        
        for _ in 0..<5 {
            _ = try await db.query().where("status", equals: .string("open")).execute()
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let afterStats = try await db.telemetry.getSummary()
        let afterAvg = afterStats.avgDuration
        
        print("    Average query time: \(String(format: "%.2f", afterAvg))ms")
        
        // Calculate improvement
        if beforeAvg > 0 {
            let improvement = ((beforeAvg - afterAvg) / beforeAvg) * 100
            print("\n  🎉 Improvement: \(String(format: "%.0f", improvement))%")
        }
        
        print("\n  ✅ Optimization validation complete")
    }
    
    // MARK: - Real-World Scenario 6: High-Load Telemetry
    
    func testTelemetry_HighLoadScenario() async throws {
        print("\n⚡ INTEGRATION: High-Load Scenario")
        
        let dbURL = tempDir.appendingPathComponent("highload.blazedb")
        let db = try BlazeDBClient(name: "HighLoad", fileURL: dbURL, password: "test-pass-123456")
        
        // Use 1% sampling for high-load scenarios
        db.telemetry.enable(samplingRate: 0.01)
        
        print("  📊 Performing 500 operations with 1% sampling...")
        
        let startTime = Date()
        
        // High-load: 500 operations
        for i in 0..<500 {
            _ = try await db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("    Completed in \(String(format: "%.2f", duration))s")
        print("    Throughput: \(String(format: "%.0f", 500 / duration)) ops/sec")
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Check telemetry overhead
        let summary = try await db.telemetry.getSummary()
        
        print("\n  📊 Telemetry captured:")
        print("    Operations tracked: \(summary.totalOperations) (~1% of 500)")
        print("    Average duration: \(String(format: "%.2f", summary.avgDuration))ms")
        
        // With 1% sampling, should track ~5 operations (allow variance)
        XCTAssertLessThan(summary.totalOperations, 50, "1% sampling should track < 50 operations")
        
        print("\n  ✅ High-load scenario complete")
    }
    
    // MARK: - Real-World Scenario 7: Multi-Database Telemetry
    
    func testTelemetry_MultiDatabaseScenario() async throws {
        print("\n🗄️  INTEGRATION: Multi-Database Telemetry")
        
        let db1URL = tempDir.appendingPathComponent("db1.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "test-pass-123456")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "test-pass-123456")
        
        // Enable telemetry on both
        db1.telemetry.enable(samplingRate: 1.0)
        db2.telemetry.enable(samplingRate: 1.0)
        
        print("  📊 Operating on DB1...")
        for i in 0..<10 {
            _ = try await db1.insert(BlazeDataRecord(["db": .string("db1"), "value": .int(i)]))
        }
        
        print("  📊 Operating on DB2...")
        for i in 0..<15 {
            _ = try await db2.insert(BlazeDataRecord(["db": .string("db2"), "value": .int(i)]))
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check telemetry for each
        let summary1 = try await db1.telemetry.getSummary()
        let summary2 = try await db2.telemetry.getSummary()
        
        print("\n  📊 DB1 Telemetry:")
        print("    Operations: \(summary1.totalOperations)")
        
        print("\n  📊 DB2 Telemetry:")
        print("    Operations: \(summary2.totalOperations)")
        
        // Each DB should track its own operations
        XCTAssertEqual(summary1.totalOperations, 10)
        XCTAssertEqual(summary2.totalOperations, 15)
        
        print("\n  ✅ Multi-database telemetry working correctly")
    }
}

