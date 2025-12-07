//
//  QueryPerformanceTests.swift
//  BlazeDBVisualizerTests
//
//  Test query performance monitoring
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class QueryPerformanceTests: XCTestCase {
    var tempDir: URL!
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test123")
        
        // Clear any existing profiling data
        QueryProfiler.shared.clear()
        
        // Add test data
        for i in 0..<50 {
            try db.insert(BlazeDataRecord( [
                "name": .string("User \(i)"),
                "age": .int(20 + i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ]))
        }
        try db.persist()
    }
    
    override func tearDown() async throws {
        QueryProfiler.shared.disable()
        QueryProfiler.shared.clear()
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testEnableProfiling() throws {
        db.enableProfiling()
        XCTAssertTrue(QueryProfiler.shared.isEnabled)
    }
    
    func testDisableProfiling() throws {
        db.enableProfiling()
        db.disableProfiling()
        XCTAssertFalse(QueryProfiler.shared.isEnabled)
    }
    
    // MARK: - Query Profiling Tests
    
    func testQueryIsProfiled() throws {
        db.enableProfiling()
        
        // Execute query
        _ = try db.fetchAll()
        
        // Should have profiling data
        let profiles = QueryProfiler.shared.getAllProfiles()
        XCTAssertFalse(profiles.isEmpty, "Query should be profiled")
    }
    
    func testSlowQueryDetection() throws {
        db.enableProfiling()
        
        // Execute queries
        for _ in 0..<10 {
            _ = try db.fetchAll()
        }
        
        // Get slow queries
        let slowQueries = QueryProfiler.shared.getSlowQueries(threshold: 0.0)  // All queries
        XCTAssertFalse(slowQueries.isEmpty)
    }
    
    func testQueryStatistics() throws {
        db.enableProfiling()
        
        // Execute multiple queries
        for _ in 0..<20 {
            _ = try db.fetchAll()
        }
        
        let stats = QueryProfiler.shared.getStatistics()
        XCTAssertEqual(stats.totalQueries, 20)
        XCTAssertGreaterThan(stats.averageExecutionTime, 0)
    }
    
    func testProfilingReport() throws {
        db.enableProfiling()
        
        _ = try db.fetchAll()
        
        let report = db.getProfilingReport()
        XCTAssertTrue(report.contains("QUERY PROFILING REPORT"))
        XCTAssertTrue(report.contains("Total queries:"))
    }
    
    // MARK: - Performance Tests
    
    func testProfilingOverhead() throws {
        // Without profiling
        let startWithout = Date()
        for _ in 0..<100 {
            _ = try db.fetchAll()
        }
        let durationWithout = Date().timeIntervalSince(startWithout)
        
        // With profiling
        db.enableProfiling()
        let startWith = Date()
        for _ in 0..<100 {
            _ = try db.fetchAll()
        }
        let durationWith = Date().timeIntervalSince(startWith)
        
        // Overhead should be minimal (< 5%)
        let overhead = (durationWith - durationWithout) / durationWithout
        XCTAssertLessThan(overhead, 0.05, "Profiling overhead should be < 5%")
    }
    
    func testMaxProfilesLimit() throws {
        db.enableProfiling()
        
        // Execute 1500 queries (more than max 1000)
        for _ in 0..<1500 {
            _ = try db.fetchAll()
        }
        
        let profiles = QueryProfiler.shared.getAllProfiles()
        XCTAssertLessThanOrEqual(profiles.count, 1000, "Should keep max 1000 profiles")
    }
    
    // MARK: - Cache Hit Tests
    
    func testCacheHitTracking() throws {
        db.enableProfiling()
        
        // First query - cache miss
        _ = try db.fetchAll()
        
        // Second query - might be cache hit
        _ = try db.fetchAll()
        
        let stats = QueryProfiler.shared.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.totalQueries, 2)
    }
    
    // MARK: - Clear Tests
    
    func testClearProfiles() throws {
        db.enableProfiling()
        
        _ = try db.fetchAll()
        XCTAssertFalse(QueryProfiler.shared.getAllProfiles().isEmpty)
        
        QueryProfiler.shared.clear()
        XCTAssertTrue(QueryProfiler.shared.getAllProfiles().isEmpty)
    }
    
    // MARK: - Edge Cases
    
    func testProfilingWhenDisabled() throws {
        db.disableProfiling()
        
        _ = try db.fetchAll()
        
        let profiles = QueryProfiler.shared.getAllProfiles()
        XCTAssertTrue(profiles.isEmpty, "Should not profile when disabled")
    }
    
    func testSlowQueryWithCustomThreshold() throws {
        db.enableProfiling()
        
        _ = try db.fetchAll()
        
        let slowQueries1 = QueryProfiler.shared.getSlowQueries(threshold: 0.001)  // 1ms
        let slowQueries2 = QueryProfiler.shared.getSlowQueries(threshold: 10.0)   // 10s
        
        XCTAssertGreaterThanOrEqual(slowQueries1.count, slowQueries2.count)
    }
}

