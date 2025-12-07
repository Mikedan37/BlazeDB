//
//  GeospatialEnhancementTests.swift
//  BlazeDBTests
//
//  Tests for geospatial enhancements (distance sorting, k-NN)
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class GeospatialEnhancementTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.geospatial.blazedb")
        db = try! BlazeDBClient(name: "TestGeospatial", fileURL: dbURL, password: "GeospatialTest123!")
        try! db.enableSpatialIndex(on: "latitude", lonField: "longitude")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testDistanceSorting() throws {
        // Insert locations at varying distances
        let center = SpatialPoint(latitude: 37.7749, longitude: -122.4194)
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Far"),
            "latitude": .double(37.8),
            "longitude": .double(-122.3)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Near"),
            "latitude": .double(37.7750),
            "longitude": .double(-122.4195)
        ]))
        
        // Query with distance sorting
        let results = try db.query()
            .withinRadius(latitude: center.latitude, longitude: center.longitude, radiusMeters: 50_000)
            .orderByDistance(latitude: center.latitude, longitude: center.longitude)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0)
        
        // Check sorting (nearest first)
        var lastDistance: Double = 0
        for record in records {
            if let distance = record.distance {
                XCTAssertGreaterThanOrEqual(distance, lastDistance)
                lastDistance = distance
            }
        }
        
        // Nearest should be first
        XCTAssertEqual(records.first?.storage["name"]?.stringValue, "Near")
    }
    
    func testKNearestNeighbor() throws {
        // Insert 10 locations
        for i in 0..<10 {
            let lat = 37.7749 + Double.random(in: -0.1...0.1)
            let lon = -122.4194 + Double.random(in: -0.1...0.1)
            _ = try db.insert(BlazeDataRecord([
                "name": .string("Location \(i)"),
                "latitude": .double(lat),
                "longitude": .double(lon)
            ]))
        }
        
        // Find nearest 5
        let results = try db.query()
            .nearest(to: SpatialPoint(latitude: 37.7749, longitude: -122.4194), limit: 5)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 5)
        
        // All should have distance
        for record in records {
            XCTAssertNotNil(record.distance)
        }
        
        // Should be sorted by distance
        var lastDistance: Double = 0
        for record in records {
            if let distance = record.distance {
                XCTAssertGreaterThanOrEqual(distance, lastDistance)
                lastDistance = distance
            }
        }
    }
    
    func testDistanceInResults() throws {
        let center = SpatialPoint(latitude: 37.7749, longitude: -122.4194)
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Test"),
            "latitude": .double(37.7750),
            "longitude": .double(-122.4195)
        ]))
        
        // Query with .near() (auto-sorts and includes distance)
        let results = try db.query()
            .near(latitude: center.latitude, longitude: center.longitude, radiusMeters: 10_000)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0)
        
        // Distance should be included
        XCTAssertNotNil(records.first?.distance)
        if let distance = records.first?.distance {
            XCTAssertGreaterThan(distance, 0)
            XCTAssertLessThan(distance, 10_000)  // Within radius
        }
    }
}

