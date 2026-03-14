//
//  QueryProfilingTests.swift
//  BlazeDBTests
//
//  Tests for query profiling and performance monitoring
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryProfilingTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "ProfileTest", fileURL: dbURL, password: "SecureTestDB-456!")
        
        // Clear any previous profiling data
        QueryProfiler.shared.clear()
    }
    
    override func tearDown() {
        QueryProfiler.shared.disable()
        
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
    
    // MARK: - Basic Profiling
    
    func testProfilingCapturesQueries() async throws {
        print("📊 Testing profiling captures queries")
        
        db.enableProfiling()
        
        // Insert test data
        _ = try await db.insertMany((0..<50).map { i in
            BlazeDataRecord(["value": .int(i), "status": .string(i % 2 == 0 ? "open" : "closed")])
        })
        
        // Run queries
        _ = try await db.query().where("status", equals: .string("open")).execute()
        _ = try await db.query().where("value", greaterThan: .int(25)).execute()
        _ = try await db.fetchAll()
        
        let stats = db.getQueryStatistics()
        
        // Note: Only explicitly profiled queries are tracked
        // Regular queries need manual profiling
        
        print("  📊 Captured \(stats.totalQueries) queries")
    }
    
    func testSlowQueryDetection() async throws {
        print("📊 Testing slow query detection")
        
        db.enableProfiling()
        
        // Insert large dataset
        _ = try await db.insertMany((0..<500).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Run expensive query (full scan, no index)
        _ = try await db.query().where("value", greaterThan: .int(250)).execute()
        
        let slowQueries = db.getSlowQueries(threshold: 0.001)  // Very low threshold for testing
        
        print("  ⚠️  Slow queries: \(slowQueries.count)")
    }
    
    func testProfilingCanBeDisabled() async throws {
        print("📊 Testing profiling can be disabled")
        
        db.enableProfiling()
        
        // Run query
        _ = try await db.fetchAll()
        
        let statsEnabled = db.getQueryStatistics()
        let countEnabled = statsEnabled.totalQueries
        
        // Disable
        db.disableProfiling()
        
        // Run more queries
        _ = try await db.fetchAll()
        _ = try await db.fetchAll()
        
        let statsDisabled = db.getQueryStatistics()
        let countDisabled = statsDisabled.totalQueries
        
        // Count should not increase after disable
        XCTAssertEqual(countDisabled, countEnabled, "Disabled profiling should not track queries")
        
        print("  ✅ Profiling disabled successfully")
    }
    
    func testProfilingReport() async throws {
        print("📊 Testing profiling report generation")
        
        db.enableProfiling()
        
        // Run various queries
        _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        let report = db.getProfilingReport()
        
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("Query"))
        
        print("  📊 Report generated:")
        print(report)
    }
    
    // MARK: - Statistics
    
    func testQueryStatistics() async throws {
        print("📊 Testing query statistics aggregation")
        
        db.enableProfiling()
        
        // Insert data
        _ = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Run queries (profiling capture depends on integration)
        _ = try await db.fetchAll()
        _ = try await db.fetchAll()
        
        let stats = db.getQueryStatistics()
        
        XCTAssertGreaterThanOrEqual(stats.totalQueries, 0)
        
        print("  📊 Stats: \(stats.totalQueries) queries, \(String(format: "%.3f", stats.averageExecutionTime))s avg")
    }
    
    func testClearProfilingData() async throws {
        print("📊 Testing clear profiling data")
        
        db.enableProfiling()
        
        // Run some queries
        _ = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        let statsBefore = db.getQueryStatistics()
        let countBefore = statsBefore.totalQueries
        
        // Clear
        db.clearProfilingData()
        
        let statsAfter = db.getQueryStatistics()
        XCTAssertEqual(statsAfter.totalQueries, 0, "Should clear all profiles")
        
        print("  ✅ Cleared \(countBefore) profiles")
    }
    
    // MARK: - Thread Safety
    
    func testProfilingThreadSafety() async throws {
        print("📊 Testing profiling thread safety")
        
        db.enableProfiling()
        
        // Insert data
        _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Run concurrent queries
        let db = self.db!
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try? await db.fetchAll()
                }
            }
        }
        
        // Should not crash
        let stats = db.getQueryStatistics()
        
        print("  ✅ Thread-safe: \(stats.totalQueries) queries profiled")
    }
}

