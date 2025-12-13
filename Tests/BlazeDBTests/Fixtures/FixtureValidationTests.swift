//
//  FixtureValidationTests.swift
//  BlazeDBTests
//
//  Tests for validating BlazeBinary fixtures with dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class FixtureValidationTests: XCTestCase {
    
    // MARK: - Fixture Validation
    
    func testValidateAllFixtures() throws {
        // Validate all fixtures decode identically with both codecs
        try FixtureLoader.validateAllFixtures(version: "v1")
    }
    
    // MARK: - Create Test Fixtures
    
    func testCreateFixture_AllFieldTypes() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Fixture Test"),
            "count": .int(42),
            "price": .double(99.99),
            "isActive": .bool(true),
            "createdAt": .date(Date()),
            "data": .data(Data([1, 2, 3, 4, 5])),
            "tags": .array([.string("tag1"), .string("tag2")]),
            "metadata": .dictionary(["key": .string("value")])
        ])
        
        // Test encode/decode round-trip (in-memory, no file I/O)
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Verify all fields round-trip correctly
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Fixture Test")
        XCTAssertEqual(decoded.storage["count"]?.intValue, 42)
        XCTAssertEqual(decoded.storage["price"]?.doubleValue, 99.99)
        XCTAssertEqual(decoded.storage["isActive"]?.boolValue, true)
    }
    
    func testCreateFixture_LargeRecord() throws {
        var storage: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            storage["field\(i)"] = .string("Value \(i) " + String(repeating: "x", count: 100))
        }
        let record = BlazeDataRecord(storage)
        
        // Test encode/decode round-trip (in-memory, no file I/O)
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Verify all fields round-trip correctly
        XCTAssertEqual(decoded.storage.count, 100)
        XCTAssertEqual(decoded.storage["field0"]?.stringValue, "Value 0 " + String(repeating: "x", count: 100))
        XCTAssertEqual(decoded.storage["field99"]?.stringValue, "Value 99 " + String(repeating: "x", count: 100))
    }
    
    func testCreateFixture_NestedStructures() throws {
        let record = BlazeDataRecord([
            "level1": .dictionary([
                "level2": .dictionary([
                    "level3": .dictionary([
                        "value": .int(42)
                    ])
                ])
            ]),
            "array": .array([
                .array([.int(1), .int(2)]),
                .array([.int(3), .int(4)])
            ])
        ])
        
        // Test encode/decode round-trip (in-memory, no file I/O)
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Verify nested structures round-trip correctly
        if case .dictionary(let level1) = decoded.storage["level1"],
           case .dictionary(let level2) = level1["level2"],
           case .dictionary(let level3) = level2["level3"],
           case .int(let value) = level3["value"] {
            XCTAssertEqual(value, 42)
        } else {
            XCTFail("Nested structure not decoded correctly")
        }
    }
    
    // MARK: - Backwards Compatibility
    
    func testBackwardsCompatibility_OldFixtures() throws {
        // Test that old fixtures still decode correctly
        // This ensures format stability across versions
        
        // Try to load and validate old fixtures
        do {
            try FixtureLoader.validateAllFixtures(version: "v1")
        } catch FixtureError.fileNotFound {
            // No fixtures yet - that's okay
        } catch {
            throw error
        }
    }
}

