//
//  BlazeEncoderMigrationTests.swift
//  BlazeDBTests
//
//  Tests for automatic JSON → CBOR migration
//

import XCTest
@testable import BlazeDBCore

final class BlazeEncoderMigrationTests: XCTestCase {
    
    // MARK: - Format Detection Tests
    
    func testFormatDetection_JSON() {
        let jsonData = "{\"name\":\"test\"}".data(using: .utf8)!
        let format = BlazeEncoder.detectFormat(jsonData)
        XCTAssertEqual(format, .json)
    }
    
    func testFormatDetection_CBOR() {
        // CBOR map starts with 0xA1-0xBF
        let unknownData = Data([0xA1, 0x64, 0x6E, 0x61, 0x6D, 0x65])  // Unknown format
        let format = BlazeEncoder.detectFormat(unknownData)
        XCTAssertEqual(format, .blazeBinary)  // Defaults to BlazeBinary
    }
    
    func testFormatDetection_EmptyData() {
        let emptyData = Data()
        let format = BlazeEncoder.detectFormat(emptyData)
        XCTAssertEqual(format, .blazeBinary)  // Defaults to BlazeBinary
    }
    
    // MARK: - Encoding Tests
    
    func testEncode_ProducesBlazeBinary() throws {
        let record = BlazeDataRecord([
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        let encoded = try BlazeEncoder.encode(record)
        
        // Check it's BlazeBinary format
        let format = BlazeEncoder.detectFormat(encoded)
        XCTAssertEqual(format, .blazeBinary)
    }
    
    // MARK: - Decoding Tests
    
    func testDecode_CBOR_Success() throws {
        let original = BlazeDataRecord([
            "title": .string("CBOR Test"),
            "count": .int(100)
        ])
        
        // Encode to CBOR
        let encoded = try BlazeEncoder.encode(original)
        
        // Decode from CBOR
        let decoded = try BlazeEncoder.decode(encoded, as: BlazeDataRecord.self)
        
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "CBOR Test")
        XCTAssertEqual(decoded.storage["count"]?.intValue, 100)
    }
    
    func testDecode_JSON_FallbackWorks() throws {
        // Create JSON data (legacy format)
        let jsonDict: [String: Any] = [
            "storage": [
                "title": "JSON Test",
                "count": 50
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
        
        // Should decode via JSON fallback
        let decoded = try BlazeEncoder.decode(jsonData, as: BlazeDataRecord.self)
        
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "JSON Test")
        XCTAssertEqual(decoded.storage["count"]?.intValue, 50)
    }
    
    // MARK: - Migration Tests
    
    func testNeedsMigration_JSON() throws {
        let jsonData = "{\"test\":\"data\"}".data(using: .utf8)!
        XCTAssertTrue(BlazeEncoder.needsMigration(jsonData))
    }
    
    func testNeedsMigration_CBOR() throws {
        let record = BlazeDataRecord(["test": .string("data")])
        let cborData = try BlazeEncoder.encode(record)
        XCTAssertFalse(BlazeEncoder.needsMigration(cborData))
    }
    
    func testMigrate_JSONtoCBOR() throws {
        let original = BlazeDataRecord([
            "title": .string("Migration Test"),
            "priority": .int(5),
            "completed": .bool(false)
        ])
        
        // Encode to JSON (legacy)
        let jsonData = try JSONEncoder().encode(original)
        
        // Verify it's JSON
        XCTAssertTrue(BlazeEncoder.needsMigration(jsonData))
        
        // Migrate to CBOR
        let migrated = try BlazeEncoder.migrate(jsonData, as: BlazeDataRecord.self)
        
        // Verify it's now CBOR
        XCTAssertFalse(BlazeEncoder.needsMigration(migrated))
        
        // Verify data preserved
        let decoded = try BlazeEncoder.decode(migrated, as: BlazeDataRecord.self)
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Migration Test")
        XCTAssertEqual(decoded.storage["priority"]?.intValue, 5)
        XCTAssertEqual(decoded.storage["completed"]?.boolValue, false)
    }
    
    // MARK: - Storage Size Comparison
    
    func testStorageSize_CBORSmaller() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test record with some content"),
            "description": .string("This is a longer description field"),
            "priority": .int(3),
            "completed": .bool(false),
            "tags": .array([.string("bug"), .string("critical")])
        ])
        
        // JSON size
        let jsonData = try JSONEncoder().encode(record)
        
        // CBOR size
        let cborData = try BlazeEncoder.encode(record)
        
        // CBOR should be smaller
        let savings = Double(jsonData.count - cborData.count) / Double(jsonData.count) * 100
        
        print("JSON: \(jsonData.count) bytes")
        print("CBOR: \(cborData.count) bytes")
        print("Savings: \(String(format: "%.1f", savings))%")
        
        XCTAssertLessThan(cborData.count, jsonData.count, "CBOR should be smaller than JSON")
        XCTAssertGreaterThan(savings, 20, "Should save at least 20%")
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_CBOREncoding() {
        let record = BlazeDataRecord([
            "title": .string("Performance test"),
            "value": .int(42),
            "timestamp": .date(Date())
        ])
        
        measure {
            for _ in 0..<1000 {
                _ = try? BlazeEncoder.encode(record)
            }
        }
    }
    
    func testPerformance_CBORDecoding() throws {
        let record = BlazeDataRecord([
            "title": .string("Performance test"),
            "value": .int(42)
        ])
        
        let encoded = try BlazeEncoder.encode(record)
        
        measure {
            for _ in 0..<1000 {
                _ = try? BlazeEncoder.decode(encoded, as: BlazeDataRecord.self)
            }
        }
    }
}

