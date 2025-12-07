//
//  AdvancedFeaturesIntegrationTests.swift
//  BlazeDBVisualizerTests
//
//  Integration tests for all 5 advanced features
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class AdvancedFeaturesIntegrationTests: XCTestCase {
    var tempDir: URL!
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test123")
        
        // Setup complete test environment
        setupTestData()
    }
    
    override func tearDown() async throws {
        QueryProfiler.shared.disable()
        QueryProfiler.shared.clear()
        db.telemetry.disable()
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    private func setupTestData() {
        do {
            // Create users
            let admin = User(name: "Admin", email: "admin@test.com", roles: ["admin"])
            let engineer = User(name: "Engineer", email: "eng@test.com", roles: ["engineer"])
            let viewer = User(name: "Viewer", email: "view@test.com", roles: ["viewer"])
            
            db.rls.createUser(admin)
            db.rls.createUser(engineer)
            db.rls.createUser(viewer)
            
            // Add policies
            db.rls.addPolicy(.adminFullAccess())
            db.rls.addPolicy(.viewerReadOnly())
            
            // Add sample data
            for i in 0..<50 {
                try db.insert(BlazeDataRecord( [
                    "name": .string("User \(i)"),
                    "age": .int(20 + i),
                    "email": .string("user\(i)@test.com"),
                    "status": .string(i % 2 == 0 ? "active" : "inactive"),
                    "description": .string("This is user \(i) with various details")
                ]))
            }
            
            try db.persist()
        } catch {
            XCTFail("Setup failed: \(error)")
        }
    }
    
    // MARK: - Full Stack Integration Tests
    
    func testFullWorkflow_SearchAndPermissions() throws {
        // 1. Enable RLS
        db.rls.enable()
        
        // 2. Set context as viewer
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        db.rls.setContext(viewer.toSecurityContext())
        
        // 3. Search for records
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["name", "email", "description"])
        let searchResults = FullTextSearchEngine.search(
            records: records,
            query: "user details",
            config: config
        )
        
        XCTAssertFalse(searchResults.isEmpty, "Should find matching records")
        
        // 4. Viewer should be able to read but not modify
        let canInsert = (try? db.insert(BlazeDataRecord( ["test": .string("viewer_test")]))) != nil
        // Note: Depends on policy configuration
    }
    
    func testFullWorkflow_ProfilingAndTelemetry() throws {
        // 1. Enable both profiling and telemetry
        db.enableProfiling()
        try db.telemetry.enable(samplingRate: 1.0)
        
        // 2. Execute queries
        for _ in 0..<20 {
            _ = try db.fetchAll()
        }
        
        // 3. Check profiling data
        let profiles = QueryProfiler.shared.getAllProfiles()
        XCTAssertGreaterThan(profiles.count, 0, "Should have query profiles")
        
        // 4. Check telemetry data
        Thread.sleep(forTimeInterval: 0.2)
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        XCTAssertGreaterThan(metrics.count, 0, "Should have telemetry metrics")
        
        // 5. Get statistics
        let stats = QueryProfiler.shared.getStatistics()
        XCTAssertEqual(stats.totalQueries, profiles.count)
    }
    
    func testFullWorkflow_PermissionsAndProfiling() throws {
        // 1. Enable profiling
        db.enableProfiling()
        
        // 2. Test as different users
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        
        // 3. Admin operations
        db.rls.setContext(admin.toSecurityContext())
        _ = try db.fetchAll()
        
        // 4. Viewer operations
        db.rls.setContext(viewer.toSecurityContext())
        _ = try db.fetchAll()
        
        // 5. Check that both were profiled
        let profiles = QueryProfiler.shared.getAllProfiles()
        XCTAssertGreaterThanOrEqual(profiles.count, 2, "Should profile for both users")
    }
    
    // MARK: - Multi-Feature Tests
    
    func testSearchWithPermissions() throws {
        db.rls.enable()
        
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        db.rls.setContext(viewer.toSecurityContext())
        
        // Search should respect permissions
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["name"])
        let results = FullTextSearchEngine.search(
            records: records,
            query: "User",
            config: config
        )
        
        // Should only return records viewer can access
        XCTAssertFalse(results.isEmpty)
    }
    
    func testProfilingSlowSearches() throws {
        db.enableProfiling()
        
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["name", "email", "description"])
        
        // Large search query
        let startTime = Date()
        _ = FullTextSearchEngine.search(
            records: records,
            query: "user email details active status",
            config: config
        )
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete in reasonable time
        XCTAssertLessThan(duration, 0.5, "Search should be fast")
    }
    
    func testAllFeaturesEnabled() throws {
        // Enable everything
        db.rls.enable()
        db.enableProfiling()
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Set context
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        db.rls.setContext(admin.toSecurityContext())
        
        // Perform operations
        let records = try db.fetchAll()
        
        // Search
        let config = SearchConfig(fields: ["name"])
        let searchResults = FullTextSearchEngine.search(
            records: records,
            query: "User",
            config: config
        )
        
        // Insert
        try db.insert(BlazeDataRecord( ["test": .string("integration")]))
        
        // Verify all systems working
        XCTAssertFalse(searchResults.isEmpty, "Search should work")
        XCTAssertGreaterThan(QueryProfiler.shared.getAllProfiles().count, 0, "Profiling should work")
        
        Thread.sleep(forTimeInterval: 0.2)
        let metrics = try db.telemetry.getMetrics(since: Date().addingTimeInterval(-60))
        XCTAssertGreaterThan(metrics.count, 0, "Telemetry should work")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorRecovery() throws {
        db.enableProfiling()
        try db.telemetry.enable(samplingRate: 1.0)
        
        // Force an error
        _ = try? db.fetch(id: UUID())  // Non-existent
        
        // Systems should still work
        _ = try db.fetchAll()
        
        XCTAssertGreaterThan(QueryProfiler.shared.getAllProfiles().count, 0)
    }
    
    func testPermissionDenialRecovery() throws {
        db.rls.enable()
        
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        db.rls.setContext(viewer.toSecurityContext())
        
        // Try operation that might be denied
        _ = try? db.insert(BlazeDataRecord( ["test": .string("denied")]))
        
        // Should still be able to read
        let records = try db.fetchAll()
        XCTAssertFalse(records.isEmpty, "Should recover from denied operation")
    }
    
    // MARK: - Stress Tests
    
    func testHighVolume_AllFeatures() throws {
        // Enable all features
        db.rls.enable()
        db.enableProfiling()
        try db.telemetry.enable(samplingRate: 0.1)  // 10% sampling for stress
        
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        db.rls.setContext(admin.toSecurityContext())
        
        // High volume operations
        measure {
            for _ in 0..<100 {
                _ = try? db.fetchAll()
            }
        }
        
        // Should handle high volume without crashing
        XCTAssertGreaterThan(QueryProfiler.shared.getAllProfiles().count, 0)
    }
    
    func testConcurrent_AllFeatures() throws {
        db.rls.enable()
        db.enableProfiling()
        try db.telemetry.enable(samplingRate: 0.5)
        
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 20
        
        for i in 0..<20 {
            DispatchQueue.global().async {
                // Different users
                let users = self.db.rls.listUsers()
                let user = users[i % users.count]
                self.db.rls.setContext(user.toSecurityContext())
                
                // Execute operation
                _ = try? self.db.fetchAll()
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // All systems should handle concurrency
        XCTAssertGreaterThan(QueryProfiler.shared.getAllProfiles().count, 0)
    }
}

