//
//  SpatialIndexTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for geospatial queries and spatial indexing.
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class SpatialIndexTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.db")
        do {
            db = try BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "SpatialIndexTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        db = nil
        tempDir = nil
        super.tearDown()
    }
    
    // MARK: - Spatial Point Tests
    
    func testSpatialPointDistance() {
        let sf = SpatialPoint(latitude: 37.7749, longitude: -122.4194)
        let oakland = SpatialPoint(latitude: 37.8044, longitude: -122.2711)
        
        let distance = sf.distance(to: oakland)
        
        // San Francisco to Oakland is ~15km
        XCTAssertGreaterThan(distance, 10_000, "Should be > 10km")
        XCTAssertLessThan(distance, 20_000, "Should be < 20km")
    }
    
    func testBoundingBoxFromCenter() {
        let center = SpatialPoint(latitude: 37.7749, longitude: -122.4194)
        let box = BoundingBox.from(center: center, radiusMeters: 1000)
        
        XCTAssertTrue(box.contains(center), "Bounding box should contain center")
        XCTAssertGreaterThan(box.maxLat, box.minLat)
        XCTAssertGreaterThan(box.maxLon, box.minLon)
    }
    
    func testBoundingBoxContains() {
        let box = BoundingBox(minLat: 37.7, maxLat: 37.8, minLon: -122.5, maxLon: -122.4)
        let inside = SpatialPoint(latitude: 37.75, longitude: -122.45)
        let outside = SpatialPoint(latitude: 38.0, longitude: -122.0)
        
        XCTAssertTrue(box.contains(inside), "Point should be inside")
        XCTAssertFalse(box.contains(outside), "Point should be outside")
    }
    
    // MARK: - Spatial Index Tests
    
    func testEnableSpatialIndex() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        XCTAssertTrue(db.isSpatialIndexEnabled(), "Spatial index should be enabled")
        
        let stats = db.getSpatialIndexStats()
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.totalRecords, 0, "Should have 0 records initially")
    }
    
    func testSpatialIndexInsert() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("San Francisco"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        let stats = db.getSpatialIndexStats()
        XCTAssertEqual(stats?.totalRecords, 1, "Should have 1 record indexed")
    }
    
    func testSpatialIndexUpdate() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("Location 1"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        // Update location
        try db.update(id: id, with: BlazeDataRecord([
            "name": .string("Location 1"),
            "latitude": .double(37.8044),
            "longitude": .double(-122.2711)
        ]))
        
        let stats = db.getSpatialIndexStats()
        XCTAssertEqual(stats?.totalRecords, 1, "Should still have 1 record")
    }
    
    func testSpatialIndexDelete() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("Location 1"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        try db.delete(id: id)
        
        let stats = db.getSpatialIndexStats()
        XCTAssertEqual(stats?.totalRecords, 0, "Should have 0 records after delete")
    }
    
    // MARK: - Geospatial Query Tests
    
    func testWithinRadius() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert locations around San Francisco
        let sf = try db.insert(BlazeDataRecord([
            "name": .string("San Francisco"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        let oakland = try db.insert(BlazeDataRecord([
            "name": .string("Oakland"),
            "latitude": .double(37.8044),
            "longitude": .double(-122.2711)
        ]))
        
        let nyc = try db.insert(BlazeDataRecord([
            "name": .string("New York"),
            "latitude": .double(40.7128),
            "longitude": .double(-74.0060)
        ]))
        
        // Query within 20km of SF
        let nearby = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 20_000)
            .execute()
        
        let records = try nearby.records
        let names = records.map { $0.storage["name"]?.stringValue ?? "" }
        XCTAssertTrue(names.contains("San Francisco"), "Should find SF")
        XCTAssertTrue(names.contains("Oakland"), "Should find Oakland")
        XCTAssertFalse(names.contains("New York"), "Should not find NYC")
    }
    
    func testWithinBoundingBox() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        let sf = try db.insert(BlazeDataRecord([
            "name": .string("San Francisco"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        let oakland = try db.insert(BlazeDataRecord([
            "name": .string("Oakland"),
            "latitude": .double(37.8044),
            "longitude": .double(-122.2711)
        ]))
        
        let nyc = try db.insert(BlazeDataRecord([
            "name": .string("New York"),
            "latitude": .double(40.7128),
            "longitude": .double(-74.0060)
        ]))
        
        // Query Bay Area bounding box
        let inArea = try db.query()
            .withinBoundingBox(
                minLat: 37.7, maxLat: 37.9,
                minLon: -122.5, maxLon: -122.2
            )
            .execute()
        
        let records = try inArea.records
        let names = records.map { $0.storage["name"]?.stringValue ?? "" }
        XCTAssertTrue(names.contains("San Francisco"), "Should find SF")
        XCTAssertTrue(names.contains("Oakland"), "Should find Oakland")
        XCTAssertFalse(names.contains("New York"), "Should not find NYC")
    }
    
    func testWithinRadiusWithoutIndex() throws {
        // Don't enable index - should fall back to full scan
        let sf = try db.insert(BlazeDataRecord([
            "name": .string("San Francisco"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        let oakland = try db.insert(BlazeDataRecord([
            "name": .string("Oakland"),
            "latitude": .double(37.8044),
            "longitude": .double(-122.2711)
        ]))
        
        // Query should still work (full scan)
        let nearby = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 20_000)
            .execute()
        
        XCTAssertEqual(nearby.count, 2, "Should find both locations")
    }
    
    func testNearQuery() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert multiple locations
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Far"),
            "latitude": .double(38.0),
            "longitude": .double(-122.0)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Near"),
            "latitude": .double(37.7750),
            "longitude": .double(-122.4195)
        ]))
        
        // Query near SF
        let nearby = try db.query()
            .near(latitude: 37.7749, longitude: -122.4194, radiusMeters: 10_000)
            .limit(1)
            .execute()
        
        let records = try nearby.records
        XCTAssertEqual(records.count, 1, "Should find 1 nearby location")
        XCTAssertEqual(records.first?.storage["name"]?.stringValue, "Near", "Should find nearest")
    }
    
    // MARK: - Performance Tests
    
    func testSpatialIndexPerformance() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert 1000 locations
        for i in 0..<1000 {
            let lat = 37.7749 + Double.random(in: -0.1...0.1)
            let lon = -122.4194 + Double.random(in: -0.1...0.1)
            _ = try db.insert(BlazeDataRecord([
                "name": .string("Location \(i)"),
                "latitude": .double(lat),
                "longitude": .double(lon)
            ]))
        }
        
        // Query should be fast with index
        let startTime = Date()
        let results = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 5000)
            .execute()
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertGreaterThan(results.count, 0, "Should find some results")
        XCTAssertLessThan(duration, 1.0, "Query should be fast (< 1s)")
    }
    
    // MARK: - Edge Cases
    
    func testSpatialIndexWithMissingFields() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert record without coordinates
        _ = try db.insert(BlazeDataRecord([
            "name": .string("No Location")
        ]))
        
        // Insert record with coordinates
        _ = try db.insert(BlazeDataRecord([
            "name": .string("With Location"),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194)
        ]))
        
        let stats = db.getSpatialIndexStats()
        XCTAssertEqual(stats?.totalRecords, 1, "Should only index records with coordinates")
    }
    
    func testRebuildSpatialIndex() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert some records
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "name": .string("Location \(i)"),
                "latitude": .double(37.7749 + Double(i) * 0.01),
                "longitude": .double(-122.4194 + Double(i) * 0.01)
            ]))
        }
        
        // Rebuild
        try db.rebuildSpatialIndex()
        
        let stats = db.getSpatialIndexStats()
        XCTAssertEqual(stats?.totalRecords, 10, "Should have 10 records after rebuild")
    }
    
    func testDisableSpatialIndex() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        XCTAssertTrue(db.isSpatialIndexEnabled())
        
        db.disableSpatialIndex()
        XCTAssertFalse(db.isSpatialIndexEnabled())
    }
    
    // MARK: - Distance Sorting Tests
    
    func testOrderByDistance() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert locations at varying distances
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
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Medium"),
            "latitude": .double(37.78),
            "longitude": .double(-122.41)
        ]))
        
        // Query and sort by distance
        let results = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 50_000)
            .orderByDistance(latitude: 37.7749, longitude: -122.4194)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "Should find results")
        
        // Check that results are sorted by distance
        var lastDistance: Double = 0
        for record in records {
            if let distance = record.distance {
                XCTAssertGreaterThanOrEqual(distance, lastDistance, "Results should be sorted by distance")
                lastDistance = distance
            }
        }
        
        // Nearest should be first
        XCTAssertEqual(records.first?.storage["name"]?.stringValue, "Near", "Nearest should be first")
    }
    
    func testNearAutoSortsByDistance() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
        // Insert locations
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
        
        // Use .near() which auto-sorts
        let results = try db.query()
            .near(latitude: 37.7749, longitude: -122.4194, radiusMeters: 50_000)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0)
        
        // Check distance is included
        XCTAssertNotNil(records.first?.distance, "Distance should be included in results")
        
        // Check sorting
        var lastDistance: Double = 0
        for record in records {
            if let distance = record.distance {
                XCTAssertGreaterThanOrEqual(distance, lastDistance)
                lastDistance = distance
            }
        }
    }
    
    func testNearestQuery() throws {
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        
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
        XCTAssertEqual(records.count, 5, "Should find 5 nearest")
        
        // Check all have distance
        for record in records {
            XCTAssertNotNil(record.distance, "All results should have distance")
        }
        
        // Check sorted by distance
        var lastDistance: Double = 0
        for record in records {
            if let distance = record.distance {
                XCTAssertGreaterThanOrEqual(distance, lastDistance)
                lastDistance = distance
            }
        }
    }
}

