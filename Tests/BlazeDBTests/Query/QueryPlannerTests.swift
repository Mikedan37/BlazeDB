//
//  QueryPlannerTests.swift
//  BlazeDBTests
//
//  Tests for query planner and EXPLAIN
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class QueryPlannerTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            db = try BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "QueryPlannerTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testExplainSpatialQuery() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        let explanation = try db.explain {
            db.query()
                .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
        }
        
        XCTAssertTrue(explanation.strategy.contains("Spatial"), "Should use spatial index")
        XCTAssertGreaterThan(explanation.estimatedCost, 0, "Should have cost estimate")
    }
    
    func testExplainWithIndex() async throws {
        // Create index
        try await db.createIndex(on: "status")
        
        // Insert some records
        for i in 0..<10 {
            _ = try await db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        
        let explanation = try db.explain {
            db.query()
                .where("status", equals: .string("open"))
        }
        
        XCTAssertTrue(explanation.strategy.contains("Index") || explanation.strategy.contains("Sequential"), "Should have a strategy")
        XCTAssertGreaterThan(explanation.estimatedRows, 0, "Should estimate rows")
    }
    
    func testExplainHybridQuery() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        let explanation = try db.explain {
            db.query()
                .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
                .where("category", equals: .string("restaurant"))
        }
        
        XCTAssertTrue(explanation.executionOrder.count > 0, "Should have execution order")
        XCTAssertGreaterThan(explanation.estimatedCost, 0, "Should have cost estimate")
    }
}

