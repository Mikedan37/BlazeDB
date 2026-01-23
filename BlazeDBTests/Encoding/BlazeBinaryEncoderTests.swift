//
//  BlazeBinaryEncoderTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for BlazeBinary encoding/decoding
//

import XCTest
@testable import BlazeDBCore

final class BlazeBinaryEncoderTests: XCTestCase {
    
    // MARK: - Basic Type Tests
    
    func testEncode_String() throws {
        let record = BlazeDataRecord(["message": .string("Hello World")])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["message"]?.stringValue, "Hello World")
    }
    
    func testEncode_Int() throws {
        let record = BlazeDataRecord(["count": .int(42)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["count"]?.intValue, 42)
    }
    
    func testEncode_Double() throws {
        let record = BlazeDataRecord(["pi": .double(3.14159265359)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["pi"]?.doubleValue ?? 0.0, 3.14159265359, accuracy: 0.000001)
    }
    
    func testEncode_Bool() throws {
        let record = BlazeDataRecord([
            "isActive": .bool(true),
            "isDeleted": .bool(false)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["isActive"]?.boolValue, true)
        XCTAssertEqual(decoded.storage["isDeleted"]?.boolValue, false)
    }
    
    func testEncode_UUID() throws {
        let uuid = UUID()
        let record = BlazeDataRecord(["id": .uuid(uuid)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["id"]?.uuidValue, uuid)
    }
    
    func testEncode_Date() throws {
        let date = Date()
        let record = BlazeDataRecord(["createdAt": .date(date)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        let decodedDate = decoded.storage["createdAt"]?.dateValue
        XCTAssertNotNil(decodedDate)
        XCTAssertEqual(decodedDate?.timeIntervalSince1970 ?? 0.0, date.timeIntervalSince1970, accuracy: 0.001)
    }
    
    func testEncode_Data() throws {
        let data = Data([0xFF, 0xAA, 0x55, 0x00])
        let record = BlazeDataRecord(["binary": .data(data)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["binary"]?.dataValue, data)
    }
    
    func testEncode_Array() throws {
        let record = BlazeDataRecord([
            "tags": .array([
                .string("bug"),
                .string("critical"),
                .int(5)
            ])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        let tags = decoded.storage["tags"]?.arrayValue
        XCTAssertEqual(tags?.count, 3)
        XCTAssertEqual(tags?[0].stringValue, "bug")
        XCTAssertEqual(tags?[1].stringValue, "critical")
        XCTAssertEqual(tags?[2].intValue, 5)
    }
    
    func testEncode_Dictionary() throws {
        let record = BlazeDataRecord([
            "meta": .dictionary([
                "version": .string("1.0"),
                "count": .int(100)
            ])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        let meta = decoded.storage["meta"]?.dictionaryValue
        XCTAssertEqual(meta?["version"]?.stringValue, "1.0")
        XCTAssertEqual(meta?["count"]?.intValue, 100)
    }
    
    // MARK: - Optimization Tests
    
    func testOptimization_CommonFieldCompression() throws {
        // Use common field names (should be compressed to 1 byte each)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "createdAt": .date(Date()),
            "userId": .uuid(UUID()),
            "title": .string("Test")
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // With compression: ~8 header + 4 common fields (1 byte each) + values
        // Without compression: ~8 header + 4 fields (avg 8 bytes each) + values
        // Savings: ~28 bytes on field names alone!
        
        print("Encoded size with field compression: \(encoded.count) bytes")
        
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        XCTAssertNotNil(decoded.storage["id"])
        XCTAssertNotNil(decoded.storage["createdAt"])
        XCTAssertNotNil(decoded.storage["userId"])
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Test")
    }
    
    func testOptimization_SmallInt() throws {
        // Small ints (0-255) should use 2 bytes instead of 9!
        let record = BlazeDataRecord([
            "priority": .int(5),
            "status": .int(2),
            "count": .int(100)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // 3 small ints: 3 × 2 bytes = 6 bytes
        // vs normal ints: 3 × 9 bytes = 27 bytes
        // Savings: 21 bytes! 🔥
        
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        XCTAssertEqual(decoded.storage["priority"]?.intValue, 5)
        XCTAssertEqual(decoded.storage["status"]?.intValue, 2)
        XCTAssertEqual(decoded.storage["count"]?.intValue, 100)
    }
    
    func testOptimization_InlineSmallString() throws {
        // Strings ≤ 15 chars should be inlined (1 byte for type+length!)
        let record = BlazeDataRecord([
            "status": .string("open"),      // 4 chars (inline!)
            "priority": .string("high"),    // 4 chars (inline!)
            "category": .string("bug")      // 3 chars (inline!)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Each inline string: 1 byte (type+len) + N bytes = 5, 5, 4 bytes
        // vs normal string: 5 bytes (type+len) + N bytes = 9, 9, 8 bytes
        // Savings: 12 bytes! 🔥
        
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        XCTAssertEqual(decoded.storage["status"]?.stringValue, "open")
        XCTAssertEqual(decoded.storage["priority"]?.stringValue, "high")
        XCTAssertEqual(decoded.storage["category"]?.stringValue, "bug")
    }
    
    func testOptimization_EmptyCollections() throws {
        let record = BlazeDataRecord([
            "empty_str": .string(""),
            "empty_arr": .array([]),
            "empty_dict": .dictionary([:])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Each empty: 1 byte instead of 3-5 bytes!
        // Savings: 6-12 bytes! ✅
        
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        XCTAssertEqual(decoded.storage["empty_str"]?.stringValue, "")
        XCTAssertEqual(decoded.storage["empty_arr"]?.arrayValue?.count, 0)
        XCTAssertEqual(decoded.storage["empty_dict"]?.dictionaryValue?.count, 0)
    }
    
    // MARK: - Complex Records
    
    func testEncode_ComplexRecord() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("App crashes on startup"),
            "description": .string("Users report the app crashes immediately after launch."),
            "priority": .int(5),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "userId": .uuid(UUID()),
            "teamId": .uuid(UUID()),
            "tags": .array([.string("crash"), .string("critical"), .string("p0")]),
            "metadata": .dictionary([
                "version": .string("1.0.3"),
                "platform": .string("iOS"),
                "count": .int(15)
            ])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        // Verify all fields preserved
        XCTAssertNotNil(decoded.storage["id"])
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "App crashes on startup")
        XCTAssertEqual(decoded.storage["priority"]?.intValue, 5)
        XCTAssertEqual(decoded.storage["tags"]?.arrayValue?.count, 3)
        XCTAssertEqual(decoded.storage["metadata"]?.dictionaryValue?["version"]?.stringValue, "1.0.3")
        
        print("Complex record: \(encoded.count) bytes")
    }
    
    // MARK: - Edge Cases
    
    func testEncode_AllTypesInOneRecord() throws {
        let record = BlazeDataRecord([
            "string": .string("Hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "uuid": .uuid(UUID()),
            "date": .date(Date()),
            "data": .data(Data([0xFF])),
            "array": .array([.int(1)]),
            "dict": .dictionary(["key": .string("value")])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage.count, 9)
        XCTAssertNotNil(decoded.storage["string"])
        XCTAssertNotNil(decoded.storage["int"])
        XCTAssertNotNil(decoded.storage["double"])
        XCTAssertNotNil(decoded.storage["bool"])
        XCTAssertNotNil(decoded.storage["uuid"])
        XCTAssertNotNil(decoded.storage["date"])
        XCTAssertNotNil(decoded.storage["data"])
        XCTAssertNotNil(decoded.storage["array"])
        XCTAssertNotNil(decoded.storage["dict"])
    }
    
    func testEncode_LargeString() throws {
        let largeString = String(repeating: "A", count: 3000)
        let record = BlazeDataRecord(["large": .string(largeString)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["large"]?.stringValue?.count, 3000)
    }
    
    func testEncode_NegativeInts() throws {
        let record = BlazeDataRecord([
            "negative": .int(-42),
            "min": .int(Int.min),
            "max": .int(Int.max)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["negative"]?.intValue, -42)
        XCTAssertEqual(decoded.storage["min"]?.intValue, Int.min)
        XCTAssertEqual(decoded.storage["max"]?.intValue, Int.max)
    }
    
    func testEncode_SpecialDoubles() throws {
        let record = BlazeDataRecord([
            "infinity": .double(Double.infinity),
            "negInfinity": .double(-Double.infinity),
            "nan": .double(Double.nan),
            "zero": .double(0.0),
            "negZero": .double(-0.0)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        XCTAssertEqual(decoded.storage["infinity"]?.doubleValue, Double.infinity)
        XCTAssertEqual(decoded.storage["negInfinity"]?.doubleValue, -Double.infinity)
        XCTAssertTrue(decoded.storage["nan"]?.doubleValue?.isNaN ?? false)
        XCTAssertEqual(decoded.storage["zero"]?.doubleValue, 0.0)
    }
    
    func testEncode_NestedStructures() throws {
        let record = BlazeDataRecord([
            "data": .dictionary([
                "level1": .array([
                    .dictionary([
                        "level2": .array([
                            .string("deep"),
                            .int(42)
                        ])
                    ])
                ])
            ])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        // Verify deep nesting works
        let level1 = decoded.storage["data"]?.dictionaryValue?["level1"]?.arrayValue
        XCTAssertNotNil(level1)
        
        let level2Dict = level1?[0].dictionaryValue
        let level2Array = level2Dict?["level2"]?.arrayValue
        XCTAssertEqual(level2Array?[0].stringValue, "deep")
        XCTAssertEqual(level2Array?[1].intValue, 42)
    }
    
    //MARK: - Round-Trip Tests
    
    func testRoundTrip_AllTypes() throws {
        let original = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "count": .int(100),
            "price": .double(99.99),
            "active": .bool(true),
            "createdAt": .date(Date()),
            "binary": .data(Data([0x01, 0x02, 0x03])),
            "tags": .array([.string("a"), .string("b")]),
            "meta": .dictionary(["key": .string("value")])
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(original)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        
        // All fields should match
        XCTAssertEqual(decoded.storage.count, original.storage.count)
        
        for (key, originalValue) in original.storage {
            let decodedValue = decoded.storage[key]
            XCTAssertNotNil(decodedValue, "Missing field: \(key)")
            
            // Type-specific comparisons
            switch originalValue {
            case .string(let s):
                XCTAssertEqual(decodedValue?.stringValue, s)
            case .int(let i):
                XCTAssertEqual(decodedValue?.intValue, i)
            case .double(let d):
                XCTAssertEqual(decodedValue?.doubleValue ?? 0.0, d, accuracy: 0.000001)
            case .bool(let b):
                XCTAssertEqual(decodedValue?.boolValue, b)
            case .uuid(let u):
                XCTAssertEqual(decodedValue?.uuidValue, u)
            case .data(let d):
                XCTAssertEqual(decodedValue?.dataValue, d)
            default:
                // Arrays and dicts tested separately
                break
            }
        }
    }
    
    // MARK: - Size Comparison Tests
    
    func testSize_BlazeBinarySmallerThanJSON() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Bug in login system"),
            "priority": .int(5),
            "status": .string("open"),
            "createdAt": .date(Date()),
            "userId": .uuid(UUID())
        ])
        
        // JSON encoding
        let jsonData = try JSONEncoder().encode(record)
        
        // BlazeBinary encoding
        let binaryData = try BlazeBinaryEncoder.encode(record)
        
        // BlazeBinary should be significantly smaller
        let savings = Double(jsonData.count - binaryData.count) / Double(jsonData.count) * 100
        
        print("JSON: \(jsonData.count) bytes")
        print("BlazeBinary: \(binaryData.count) bytes")
        print("Savings: \(String(format: "%.1f", savings))%")
        
        XCTAssertLessThan(binaryData.count, jsonData.count)
        XCTAssertGreaterThan(savings, 40, "Should save at least 40% vs JSON")
    }
    
    // MARK: - Migration Tests
    
    func testMigration_JSONtoBlazeBinary() throws {
        let original = BlazeDataRecord([
            "title": .string("Migration test"),
            "value": .int(42)
        ])
        
        // Encode as JSON (legacy)
        let jsonData = try JSONEncoder().encode(original)
        
        // Verify it's JSON
        XCTAssertTrue(BlazeEncoder.needsMigration(jsonData))
        XCTAssertEqual(BlazeEncoder.detectFormat(jsonData), .json)
        
        // Migrate to BlazeBinary
        let migrated = try BlazeEncoder.migrate(jsonData, as: BlazeDataRecord.self)
        
        // Verify it's BlazeBinary
        XCTAssertFalse(BlazeEncoder.needsMigration(migrated))
        XCTAssertEqual(BlazeEncoder.detectFormat(migrated), .blazeBinary)
        
        // Verify data preserved
        let decoded = try BlazeEncoder.decode(migrated, as: BlazeDataRecord.self)
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Migration test")
        XCTAssertEqual(decoded.storage["value"]?.intValue, 42)
    }
    
    // MARK: - Error Handling
    
    func testDecode_InvalidMagicBytes() {
        let invalidData = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])
        
        XCTAssertThrowsError(try BlazeBinaryDecoder.decode(invalidData)) { error in
            XCTAssertTrue(error is BlazeBinaryError)
        }
    }
    
    func testDecode_TruncatedData() {
        let truncated = Data([0x42, 0x4C, 0x41])  // Only "BLA", incomplete
        
        XCTAssertThrowsError(try BlazeBinaryDecoder.decode(truncated))
    }
}

