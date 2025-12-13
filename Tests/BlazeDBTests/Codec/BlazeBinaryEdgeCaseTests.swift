//
//  BlazeBinaryEdgeCaseTests.swift
//  BlazeDBTests
//
//  Edge case tests for BlazeBinary: unlimited fields, deep nesting, huge data
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryEdgeCaseTests: XCTestCase {
    
    // MARK: - Unlimited Fields Test
    
    func testEdgeCase_1000Fields() throws {
        print("🧪 Testing 1,000 fields (way beyond 127 common fields limit)")
        
        // Create record with 1000 custom fields
        var storage: [String: BlazeDocumentField] = [:]
        
        for i in 0..<1000 {
            storage["customField\(i)"] = .int(i)
        }
        
        let record = BlazeDataRecord(storage)
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        print("  📦 1,000 fields encoded: \(encoded.count) bytes")
        
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Verify all 1000 fields preserved
        XCTAssertEqual(decoded.storage.count, 1000, "All 1000 fields should be preserved!")
        
        for i in 0..<1000 {
            XCTAssertEqual(decoded.storage["customField\(i)"]?.intValue, i)
        }
        
        print("  ✅ All 1,000 custom fields preserved (no 127 limit!)")
    }
    
    func testEdgeCase_MixedCommonAndCustomFields() throws {
        print("🧪 Testing mix of common (compressed) and custom (full name) fields")
        
        var storage: [String: BlazeDocumentField] = [:]
        
        // 10 common fields (compressed to 1 byte each)
        storage["id"] = .uuid(UUID())
        storage["createdAt"] = .date(Date())
        storage["updatedAt"] = .date(Date())
        storage["userId"] = .uuid(UUID())
        storage["teamId"] = .uuid(UUID())
        storage["title"] = .string("Test")
        storage["description"] = .string("Test description")
        storage["status"] = .string("open")
        storage["priority"] = .int(5)
        storage["assignedTo"] = .uuid(UUID())
        
        // 500 custom fields (full name encoding)
        for i in 0..<500 {
            storage["myCustomApplicationSpecificField\(i)"] = .string("Value \(i)")
        }
        
        let record = BlazeDataRecord(storage)
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        print("  📦 510 fields (10 common + 500 custom): \(encoded.count) bytes")
        
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage.count, 510)
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Test")
        XCTAssertEqual(decoded.storage["myCustomApplicationSpecificField42"]?.stringValue, "Value 42")
        
        print("  ✅ Mixed common and custom fields work perfectly!")
    }
    
    // MARK: - Deep Nesting
    
    func testEdgeCase_DeepNesting() throws {
        print("🧪 Testing deeply nested structures (100 levels)")
        
        // Build 100-level deep nesting
        var deepDict: BlazeDocumentField = .string("bottom")
        
        for level in 0..<100 {
            deepDict = .dictionary(["level\(level)": deepDict])
        }
        
        let record = BlazeDataRecord(["deep": deepDict])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        print("  📦 100-level nesting encoded: \(encoded.count) bytes")
        
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Traverse down to verify
        var current = decoded.storage["deep"]
        for level in (0..<100).reversed() {
            guard let dict = current?.dictionaryValue else {
                XCTFail("Failed at level \(level)")
                return
            }
            current = dict["level\(level)"]
        }
        
        XCTAssertEqual(current?.stringValue, "bottom")
        print("  ✅ 100-level nesting works!")
    }
    
    // MARK: - Large Data
    
    func testEdgeCase_VeryLongFieldName() throws {
        print("🧪 Testing very long field names (1000 chars)")
        
        let longFieldName = String(repeating: "verylongfieldname", count: 60)  // ~1000 chars
        
        let record = BlazeDataRecord([
            longFieldName: .string("Value with long key")
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage[longFieldName]?.stringValue, "Value with long key")
        print("  ✅ Long field names supported (1000+ chars)")
    }
    
    func testEdgeCase_HugeString() throws {
        print("🧪 Testing huge string (100,000 chars)")
        
        let hugeString = String(repeating: "A", count: 100_000)
        
        let record = BlazeDataRecord([
            "huge": .string(hugeString)
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        print("  📦 100K char string: \(encoded.count) bytes")
        
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage["huge"]?.stringValue?.count, 100_000)
        print("  ✅ Huge strings work!")
    }
    
    func testEdgeCase_LargeArray() throws {
        print("🧪 Testing large array (10,000 items)")
        
        let largeArray = (0..<10_000).map { BlazeDocumentField.int($0) }
        
        let record = BlazeDataRecord([
            "array": .array(largeArray)
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        print("  📦 10K item array: \(encoded.count / 1024) KB")
        
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage["array"]?.arrayValue?.count, 10_000)
        XCTAssertEqual(decoded.storage["array"]?.arrayValue?[5000].intValue, 5000)
        print("  ✅ Large arrays work!")
    }
    
    // MARK: - Unicode & Special Characters
    
    func testEdgeCase_UnicodeFieldNames() throws {
        print("🧪 Testing Unicode field names")
        
        let record = BlazeDataRecord([
            "用户名": .string("Chinese field"),
            "имя": .string("Russian field"),
            "الاسم": .string("Arabic field"),
            "🔥emoji🚀": .string("Emoji field"),
            "field.with.dots": .string("Dotted field"),
            "field-with-dashes": .string("Dashed field"),
            "field_with_underscores": .string("Underscored field")
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage["用户名"]?.stringValue, "Chinese field")
        XCTAssertEqual(decoded.storage["имя"]?.stringValue, "Russian field")
        XCTAssertEqual(decoded.storage["الاسم"]?.stringValue, "Arabic field")
        XCTAssertEqual(decoded.storage["🔥emoji🚀"]?.stringValue, "Emoji field")
        
        print("  ✅ Unicode field names fully supported!")
    }
    
    func testEdgeCase_UnicodeValues() throws {
        print("🧪 Testing Unicode string values")
        
        let record = BlazeDataRecord([
            "message": .string("Hello 世界! 🌍 Привет! مرحبا! שלום! 🔥")
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage["message"]?.stringValue, "Hello 世界! 🌍 Привет! مرحبا! שלום! 🔥")
        print("  ✅ Unicode strings fully supported!")
    }
    
    // MARK: - Special Values
    
    func testEdgeCase_SpecialDoubles() throws {
        print("🧪 Testing special double values")
        
        let record = BlazeDataRecord([
            "infinity": .double(Double.infinity),
            "negInfinity": .double(-Double.infinity),
            "nan": .double(Double.nan),
            "zero": .double(0.0),
            "negZero": .double(-0.0),
            "verySmall": .double(Double.leastNonzeroMagnitude),
            "veryLarge": .double(Double.greatestFiniteMagnitude)
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage["infinity"]?.doubleValue, Double.infinity)
        XCTAssertEqual(decoded.storage["negInfinity"]?.doubleValue, -Double.infinity)
        XCTAssertTrue(decoded.storage["nan"]?.doubleValue?.isNaN ?? false)
        XCTAssertEqual(decoded.storage["verySmall"]?.doubleValue, Double.leastNonzeroMagnitude)
        XCTAssertEqual(decoded.storage["veryLarge"]?.doubleValue, Double.greatestFiniteMagnitude)
        
        print("  ✅ Special doubles (infinity, NaN, extremes) work!")
    }
    
    func testEdgeCase_ExtremeInts() throws {
        print("🧪 Testing extreme integer values")
        
        let record = BlazeDataRecord([
            "min": .int(Int.min),
            "max": .int(Int.max),
            "zero": .int(0),
            "negOne": .int(-1),
            "large": .int(9_223_372_036_854_775_807)
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        XCTAssertEqual(decoded.storage["min"]?.intValue, Int.min)
        XCTAssertEqual(decoded.storage["max"]?.intValue, Int.max)
        XCTAssertEqual(decoded.storage["zero"]?.intValue, 0)
        XCTAssertEqual(decoded.storage["negOne"]?.intValue, -1)
        
        print("  ✅ Extreme ints (Int.min, Int.max) work!")
    }
    
    // MARK: - Error Recovery
    
    func testEdgeCase_CorruptedData_Recovery() throws {
        print("🧪 Testing corrupted data recovery")
        
        let record = BlazeDataRecord(["title": .string("Test")])
        
        var encoded = try BlazeBinaryEncoder.encodeARM(record)
        
        print("  📊 Encoded size: \(encoded.count) bytes")
        
        // Corrupt the data (change a byte in the middle)
        // Make sure we're within bounds!
        guard encoded.count > 10 else {
            XCTFail("Encoded data too short for corruption test")
            return
        }
        
        let corruptIndex = min(10, encoded.count - 1)  // Corrupt byte 10 or last byte
        print("  🔨 Corrupting byte \(corruptIndex)")
        encoded[corruptIndex] = 0xFF
        
        // UPDATED: Use dual-codec error validation
        assertCodecsErrorEqual(encoded)
        
        print("  ✅ Corruption detected properly!")
    }
    
    // MARK: - Performance Under Stress
    
    func testPerformance_ManyFields() throws {
        print("🧪 Performance test: 500 fields per record")
        
        var storage: [String: BlazeDocumentField] = [:]
        for i in 0..<500 {
            storage["field\(i)"] = .string("Value \(i)")
        }
        
        let record = BlazeDataRecord(storage)
        
        // UPDATED: Use dual-codec validation first
        try assertCodecsEqual(record)
        
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<10 {
                _ = try? BlazeBinaryEncoder.encodeARM(record)
            }
        }
        
        print("  ✅ 500 fields perform well!")
    }
    
    func testPerformance_VeryLargeRecord() throws {
        print("🧪 Performance test: Record with 1MB of data")
        
        let largeString = String(repeating: "A", count: 1_000_000)
        let record = BlazeDataRecord(["large": .string(largeString)])
        
        // UPDATED: Use dual-codec validation first
        try assertCodecsEqual(record)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = try? BlazeBinaryEncoder.encodeARM(record)
        }
        
        print("  ✅ 1MB records perform well!")
    }
}
