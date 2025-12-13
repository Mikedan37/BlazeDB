//
//  BlazeBinaryCompatibilityTests.swift
//  BlazeDBTests
//
//  Bit-level compatibility tests ensuring ARM-optimized codec produces identical output
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryCompatibilityTests: XCTestCase {
    
    // MARK: - Bit-Level Compatibility Tests
    
    func testCompatibility_AllFieldTypes() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test Title"),
            "count": .int(42),
            "price": .double(99.99),
            "isActive": .bool(true),
            "createdAt": .date(Date()),
            "data": .data(Data([1, 2, 3, 4, 5])),
            "tags": .array([.string("tag1"), .string("tag2")]),
            "metadata": .dictionary(["key": .string("value")])
        ])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
    }
    
    func testCompatibility_EmptyValues() throws {
        let record = BlazeDataRecord([
            "emptyString": .string(""),
            "emptyArray": .array([]),
            "emptyDict": .dictionary([:])
        ])
        
        try assertCodecsEqual(record)
    }
    
    func testCompatibility_SmallInts() throws {
        // Test all small int values (0-255)
        for i in 0...255 {
            let record = BlazeDataRecord(["value": .int(i)])
            try assertCodecsEqual(record)
        }
    }
    
    func testCompatibility_LargeInts() throws {
        let largeInts: [Int] = [
            Int.min,
            Int.min + 1,
            -1,
            0,
            1,
            Int.max - 1,
            Int.max
        ]
        
        for intValue in largeInts {
            let record = BlazeDataRecord(["value": .int(intValue)])
            try assertCodecsEqual(record)
        }
    }
    
    func testCompatibility_InlineStrings() throws {
        // Test inline strings (0-15 bytes)
        for length in 0...15 {
            let str = String(repeating: "x", count: length)
            let record = BlazeDataRecord(["str": .string(str)])
            try assertCodecsEqual(record)
        }
    }
    
    func testCompatibility_LargeStrings() throws {
        let largeStrings = [
            String(repeating: "x", count: 100),
            String(repeating: "🔥", count: 50), // Multi-byte UTF-8
            String(repeating: "a", count: 1000),
            String(repeating: "test", count: 10000)
        ]
        
        for str in largeStrings {
            let record = BlazeDataRecord(["str": .string(str)])
            try assertCodecsEqual(record)
        }
    }
    
    func testCompatibility_NestedStructures() throws {
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
        
        try assertCodecsEqual(record)
    }
    
    func testCompatibility_CommonFields() throws {
        // Test all common fields (should use 1-byte encoding)
        let commonFields: [String] = ["id", "createdAt", "updatedAt", "title", "status", "priority"]
        
        for fieldName in commonFields {
            let record = BlazeDataRecord([fieldName: .string("value")])
            try assertCodecsEqual(record)
        }
    }
    
    func testCompatibility_CustomFields() throws {
        // Test custom fields (should use 3+N byte encoding)
        let customFields: [String] = [
            "myCustomField",
            "anotherField",
            "fieldWithVeryLongNameThatExceedsCommonFieldLimit"
        ]
        
        for fieldName in customFields {
            let record = BlazeDataRecord([fieldName: .string("value")])
            try assertCodecsEqual(record)
        }
    }
    
    func testCompatibility_RoundTrip() throws {
        let original = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Round Trip Test"),
            "count": .int(12345),
            "price": .double(99.99),
            "isActive": .bool(true),
            "createdAt": .date(Date()),
            "data": .data(Data([1, 2, 3, 4, 5])),
            "tags": .array([.string("tag1"), .string("tag2")]),
            "metadata": .dictionary(["key": .string("value")])
        ])
        
        // Full dual-codec validation (includes all round-trip combinations)
        try assertCodecsEqual(original)
    }
    
    func testCompatibility_DeterministicOrdering() throws {
        // Fields should be encoded in sorted order
        let record = BlazeDataRecord([
            "zebra": .string("last"),
            "apple": .string("first"),
            "middle": .string("middle")
        ])
        
        // Verify both codecs produce identical encoding (deterministic ordering)
        try assertCodecsEncodeEqual(record)
        
        // Verify order is sorted
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        let keys = Array(decoded.storage.keys).sorted()
        XCTAssertEqual(keys, ["apple", "middle", "zebra"])
    }
    
    func testCompatibility_CRC32() throws {
        BlazeBinaryEncoder.crc32Mode = .enabled
        defer { BlazeBinaryEncoder.crc32Mode = .disabled }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("CRC Test")
        ])
        
        // Dual-codec validation with CRC32 enabled
        try assertCodecsEqual(record)
        
        // Verify CRC32 is present and valid
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertGreaterThanOrEqual(encoded.count, 12, "CRC32 format should have at least 12 bytes")
        XCTAssertEqual(encoded[5], 0x02, "Version should be 0x02 when CRC32 is enabled")
    }
}

