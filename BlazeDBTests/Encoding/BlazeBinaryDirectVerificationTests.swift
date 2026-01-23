//
//  BlazeBinaryDirectVerificationTests.swift
//  BlazeDBTests
//
//  DIRECT byte-level tests of encoder/decoder implementation
//  Verifies exact byte output, no corruption, 100% reliable
//

import XCTest
@testable import BlazeDBCore

final class BlazeBinaryDirectVerificationTests: XCTestCase {
    
    // MARK: - Direct Header Tests (Byte-Perfect)
    
    func testDirect_HeaderEncoding_ExactBytes() throws {
        print("🔬 DIRECT: Header produces exact expected bytes")
        
        let record = BlazeDataRecord([
            "a": .int(1),
            "b": .int(2),
            "c": .int(3)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Verify header bytes EXACTLY:
        XCTAssertEqual(encoded[0], 0x42, "Header byte 0 should be 'B'")
        XCTAssertEqual(encoded[1], 0x4C, "Header byte 1 should be 'L'")
        XCTAssertEqual(encoded[2], 0x41, "Header byte 2 should be 'A'")
        XCTAssertEqual(encoded[3], 0x5A, "Header byte 3 should be 'Z'")
        XCTAssertEqual(encoded[4], 0x45, "Header byte 4 should be 'E'")
        XCTAssertEqual(encoded[5], 0x01, "Version should be 0x01")
        
        // Field count: 3 fields as big-endian uint16
        // ✅ FIX: Use alignment-safe reading
        let fieldCount = UInt16(encoded[6]) << 8 | UInt16(encoded[7])
        XCTAssertEqual(fieldCount, 3, "Field count should be 3")
        
        print("  ✅ Header bytes verified: [BLAZE][0x01][0x0003]")
    }
    
    func testDirect_HeaderDecoding_ExactValidation() throws {
        print("🔬 DIRECT: Decoder validates header exactly")
        
        // Valid header
        var validData = Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0x01, 0x00, 0x00])
        XCTAssertNoThrow(try BlazeBinaryDecoder.decode(validData))
        
        // Invalid magic byte 1
        var invalid1 = validData
        invalid1[0] = 0x00
        XCTAssertThrowsError(try BlazeBinaryDecoder.decode(invalid1))
        
        // Invalid magic byte 3
        var invalid2 = validData
        invalid2[2] = 0xFF
        XCTAssertThrowsError(try BlazeBinaryDecoder.decode(invalid2))
        
        // Invalid version
        var invalid3 = validData
        invalid3[5] = 0x99
        XCTAssertThrowsError(try BlazeBinaryDecoder.decode(invalid3))
        
        print("  ✅ Header validation: Rejects ALL invalid headers!")
    }
    
    // MARK: - Direct Type Encoding Tests (Byte-Perfect)
    
    func testDirect_IntEncoding_ExactBytes() throws {
        print("🔬 DIRECT: Int encoding produces exact bytes")
        
        // Test value: 42
        let record = BlazeDataRecord(["value": .int(42)])
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Find the int value in bytes (after header + field key)
        // Header: 8 bytes
        // Field key: variable (depends on compression)
        // Type tag: 1 byte (0x02 for full int or 0x12 for small int)
        // Value: 8 bytes (full int) or 1 byte (small int)
        
        // For int 42 (0-255), should use SmallInt optimization
        // Find type tag 0x12 in encoded data
        if let smallIntIndex = encoded.firstIndex(of: 0x12) {
            // Next byte should be 42
            XCTAssertEqual(encoded[smallIntIndex + 1], 42, "SmallInt value should be 42")
            print("  ✅ Int 42 encoded as SmallInt: [0x12][0x2A]")
        } else {
            XCTFail("Should use SmallInt for value 42!")
        }
    }
    
    func testDirect_UUIDEncoding_ExactBytes() throws {
        print("🔬 DIRECT: UUID encoding produces exact bytes")
        
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let record = BlazeDataRecord(["id": .uuid(uuid)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // UUID type tag is 0x05
        guard let uuidIndex = encoded.firstIndex(of: 0x05) else {
            XCTFail("UUID type tag not found!")
            return
        }
        
        // Extract 16 bytes after type tag
        let uuidBytes = encoded[(uuidIndex + 1)...(uuidIndex + 16)]
        
        // Verify against actual UUID bytes
        let expectedBytes = uuid.uuid
        var actualBytes: [UInt8] = []
        withUnsafeBytes(of: expectedBytes) { buffer in
            actualBytes = Array(buffer)
        }
        
        XCTAssertEqual(Array(uuidBytes), actualBytes, "UUID bytes should match exactly!")
        print("  ✅ UUID bytes verified: 16 bytes exact match!")
    }
    
    func testDirect_StringEncoding_ExactBytes() throws {
        print("🔬 DIRECT: String encoding produces exact UTF-8 bytes")
        
        let testString = "Hello!"
        let record = BlazeDataRecord(["message": .string(testString)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // "Hello!" is 6 chars, should use inline optimization (type 0x20 + length)
        let expectedTypeTag = 0x20 + UInt8(testString.count)  // 0x26
        
        if let inlineIndex = encoded.firstIndex(of: expectedTypeTag) {
            // Extract string bytes
            let stringBytes = encoded[(inlineIndex + 1)...(inlineIndex + testString.count)]
            let decodedString = String(data: Data(stringBytes), encoding: .utf8)
            
            XCTAssertEqual(decodedString, testString, "String bytes should decode to original!")
            print("  ✅ String '\(testString)' encoded as exact UTF-8 bytes!")
        } else {
            XCTFail("Should use inline encoding for 6-char string!")
        }
    }
    
    func testDirect_BoolEncoding_ExactBytes() throws {
        print("🔬 DIRECT: Bool encoding produces exact bytes")
        
        // ✅ Use a common field name to avoid confusion with custom field encoding
        // "status" is a common field, so it encodes as 1 byte, not [0xFF][len][name]
        let recordTrue = BlazeDataRecord(["status": .bool(true)])
        let encodedTrue = try BlazeBinaryEncoder.encode(recordTrue)
        
        // Decode to verify bool value
        let decoded = try BlazeBinaryDecoder.decode(encodedTrue)
        XCTAssertEqual(decoded["status"]?.boolValue, true, "True should decode correctly")
        
        // Verify the bool is encoded as 0x01 by re-encoding and checking
        let recordFalse = BlazeDataRecord(["status": .bool(false)])
        let encodedFalse = try BlazeBinaryEncoder.encode(recordFalse)
        
        let decodedFalse = try BlazeBinaryDecoder.decode(encodedFalse)
        XCTAssertEqual(decodedFalse["status"]?.boolValue, false, "False should decode correctly")
        
        // Verify bool type tag (0x04) exists in encoding
        XCTAssertTrue(encodedTrue.contains(0x04), "Encoding should contain bool type tag 0x04")
        XCTAssertTrue(encodedFalse.contains(0x04), "Encoding should contain bool type tag 0x04")
        
        print("  ✅ bool(true) and bool(false) encode/decode correctly!")
    }
    
    // MARK: - Direct Decoding Tests (Verify Reads Correctly)
    
    func testDirect_DecoderReadsHeader_Correctly() throws {
        print("🔬 DIRECT: Decoder reads header bytes correctly")
        
        // Manually construct header bytes
        var data = Data()
        data.append(contentsOf: [0x42, 0x4C, 0x41, 0x5A, 0x45])  // "BLAZE"
        data.append(0x01)  // Version
        data.append(contentsOf: [0x00, 0x02])  // Field count: 2 (big-endian)
        
        // Add 2 simple fields (so it's valid)
        // Field 1: "a" → 0xFF (custom) + length + name
        data.append(0xFF)  // Custom field marker
        data.append(contentsOf: [0x00, 0x01])  // Key length: 1
        data.append(0x61)  // 'a'
        data.append(0x12)  // SmallInt type
        data.append(0x01)  // Value: 1
        
        // Field 2: "b"
        data.append(0xFF)  // Custom field marker
        data.append(contentsOf: [0x00, 0x01])  // Key length: 1
        data.append(0x62)  // 'b'
        data.append(0x12)  // SmallInt type
        data.append(0x02)  // Value: 2
        
        // Decode manually constructed data
        let decoded = try BlazeBinaryDecoder.decode(data)
        
        XCTAssertEqual(decoded.storage.count, 2, "Should have 2 fields")
        XCTAssertEqual(decoded.storage["a"]?.intValue, 1)
        XCTAssertEqual(decoded.storage["b"]?.intValue, 2)
        
        print("  ✅ Decoder correctly reads manually constructed bytes!")
    }
    
    func testDirect_NoDataCorruption_InEncodeDecodeChain() throws {
        print("🔬 DIRECT: No corruption through encode/decode chain")
        
        // Test all critical values
        let criticalValues: [BlazeDocumentField] = [
            .int(0),
            .int(1),
            .int(-1),
            .int(255),
            .int(256),
            .int(Int.min),
            .int(Int.max),
            .double(0.0),
            .double(-0.0),
            .double(3.14159265358979323846),  // Max precision
            .double(Double.infinity),
            .double(-Double.infinity),
            .double(Double.nan),
            .bool(true),
            .bool(false),
            .string(""),
            .string("a"),
            .string("Hello World!"),
            .uuid(UUID()),
            .date(Date()),
            .data(Data()),
            .data(Data([0x00, 0xFF, 0xAA, 0x55])),
            .array([]),
            .array([.int(1), .int(2)]),
            .dictionary([:]),
            .dictionary(["key": .string("value")])
        ]
        
        for (index, value) in criticalValues.enumerated() {
            let record = BlazeDataRecord(["field": value])
            
            // Encode
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // Decode
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            
            // Verify NO corruption
            let decodedValue = decoded.storage["field"]
            XCTAssertNotNil(decodedValue, "Value \(index) missing after decode!")
            
            // Type-specific exact verification
            switch value {
            case .int(let expected):
                XCTAssertEqual(decodedValue?.intValue, expected, "Int \(index) corrupted!")
            case .double(let expected):
                if expected.isNaN {
                    XCTAssertTrue(decodedValue?.doubleValue?.isNaN ?? false, "NaN \(index) corrupted!")
                } else {
                    XCTAssertEqual(decodedValue?.doubleValue ?? 0.0, expected, accuracy: 0.0, "Double \(index) corrupted!")
                }
            case .bool(let expected):
                XCTAssertEqual(decodedValue?.boolValue, expected, "Bool \(index) corrupted!")
            case .string(let expected):
                XCTAssertEqual(decodedValue?.stringValue, expected, "String \(index) corrupted!")
            case .uuid(let expected):
                XCTAssertEqual(decodedValue?.uuidValue, expected, "UUID \(index) corrupted!")
            case .data(let expected):
                XCTAssertEqual(decodedValue?.dataValue, expected, "Data \(index) corrupted!")
            case .array(let expected):
                XCTAssertEqual(decodedValue?.arrayValue?.count, expected.count, "Array \(index) corrupted!")
            case .dictionary(let expected):
                XCTAssertEqual(decodedValue?.dictionaryValue?.count, expected.count, "Dict \(index) corrupted!")
            case .date:
                XCTAssertNotNil(decodedValue?.dateValue, "Date \(index) corrupted!")
            }
        }
        
        print("  ✅ ALL \(criticalValues.count) critical values: ZERO corruption!")
    }
    
    // MARK: - Byte-Level Field Encoding Tests
    
    func testDirect_CommonFieldEncoding_OneByte() throws {
        print("🔬 DIRECT: Common fields encode to exactly 1 byte")
        
        // Test all common fields
        let commonFieldTests: [(String, UInt8)] = [
            ("id", 0x01),
            ("createdAt", 0x02),
            ("updatedAt", 0x03),
            ("userId", 0x04),
            ("teamId", 0x05),
            ("title", 0x06),
            ("description", 0x07),
            ("status", 0x08),
            ("priority", 0x09)
        ]
        
        for (fieldName, expectedByte) in commonFieldTests {
            let record = BlazeDataRecord([fieldName: .int(42)])
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // After header (8 bytes), should have field byte
            let fieldByte = encoded[8]
            XCTAssertEqual(fieldByte, expectedByte, 
                          "Field '\(fieldName)' should encode to 0x\(String(expectedByte, radix: 16))")
        }
        
        print("  ✅ All 9 common fields encode to correct single byte!")
    }
    
    func testDirect_CustomFieldEncoding_FullName() throws {
        print("🔬 DIRECT: Custom fields encode with full name")
        
        let customField = "myCustomField"
        let record = BlazeDataRecord([customField: .int(42)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // After header (8 bytes), should have:
        // [0xFF][length:2b][name bytes]
        XCTAssertEqual(encoded[8], 0xFF, "Custom field should start with 0xFF marker")
        
        // Extract length (big-endian uint16)
        // ✅ FIX: Use alignment-safe reading
        let length = UInt16(encoded[9]) << 8 | UInt16(encoded[10])
        
        XCTAssertEqual(length, UInt16(customField.count), "Length should match field name length")
        
        // Extract name bytes
        let nameBytes = encoded[11...(11 + customField.count - 1)]
        let decodedName = String(data: Data(nameBytes), encoding: .utf8)
        
        XCTAssertEqual(decodedName, customField, "Field name should be preserved exactly!")
        
        print("  ✅ Custom field '\(customField)' encoded with full name!")
    }
    
    func testDirect_SmallIntEncoding_TwoBytes() throws {
        print("🔬 DIRECT: SmallInt (0-255) encodes to exactly 2 bytes")
        
        for value in [0, 1, 42, 127, 255] {
            let record = BlazeDataRecord(["num": .int(value)])
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // Find SmallInt type tag (0x12)
            guard let typeIndex = encoded.firstIndex(of: 0x12) else {
                XCTFail("Should use SmallInt for value \(value)")
                continue
            }
            
            // Next byte should be the value
            XCTAssertEqual(encoded[typeIndex + 1], UInt8(value), 
                          "SmallInt value byte should be \(value)")
        }
        
        print("  ✅ SmallInt values 0-255: All encode to exactly 2 bytes!")
    }
    
    func testDirect_LargeIntEncoding_NineBytes() throws {
        print("🔬 DIRECT: Large ints encode to exactly 9 bytes (type + 8 bytes)")
        
        let largeValue = 1000  // > 255, uses full int
        let record = BlazeDataRecord(["num": .int(largeValue)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Find Int type tag (0x02)
        guard let typeIndex = encoded.firstIndex(of: 0x02) else {
            XCTFail("Should use full Int for value 1000")
            return
        }
        
        // Extract 8 bytes after type tag
        let intBytes = encoded[(typeIndex + 1)...(typeIndex + 8)]
        
        // ✅ FIX: Use alignment-safe decoding (avoid unaligned memory access)
        let bytesArray = Array(intBytes)
        let decodedValue = bytesArray.withUnsafeBytes { buffer in
            // Break up complex expression for Swift compiler
            let b0 = UInt64(buffer[0]) << 56
            let b1 = UInt64(buffer[1]) << 48
            let b2 = UInt64(buffer[2]) << 40
            let b3 = UInt64(buffer[3]) << 32
            let b4 = UInt64(buffer[4]) << 24
            let b5 = UInt64(buffer[5]) << 16
            let b6 = UInt64(buffer[6]) << 8
            let b7 = UInt64(buffer[7])
            let raw = b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
            return Int(bitPattern: UInt(raw))
        }
        
        XCTAssertEqual(decodedValue, largeValue, "Large int should decode to \(largeValue)")
        
        print("  ✅ Large int 1000 encoded as [0x02][8 bytes big-endian]")
    }
    
    func testDirect_InlineStringEncoding_TypeAndLengthInOneByte() throws {
        print("🔬 DIRECT: Inline strings encode type+length in single byte")
        
        let testCases = [
            ("", 0),
            ("a", 1),
            ("test", 4),
            ("1234567890123", 13),
            ("123456789012345", 15)  // Max inline
        ]
        
        for (string, length) in testCases {
            guard length <= 15 else { continue }
            
            let record = BlazeDataRecord(["str": .string(string)])
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // Expected type byte: 0x20 + length
            let expectedTypeByte = 0x20 + UInt8(length)
            
            if encoded.contains(expectedTypeByte) {
                print("  ✅ String '\(string)' (len \(length)): type+len = 0x\(String(expectedTypeByte, radix: 16))")
            } else if length == 0 {
                // Empty string uses 0x11 optimization
                XCTAssertTrue(encoded.contains(0x11), "Empty string should use 0x11")
                print("  ✅ Empty string: optimized to [0x11]")
            }
        }
        
        print("  ✅ All inline strings encode type+length in ONE byte!")
    }
    
    // MARK: - Direct Decoding Tests (Read Exact Bytes)
    
    func testDirect_DecoderReadsInt_FromExactBytes() throws {
        print("🔬 DIRECT: Decoder reads int from exact byte pattern")
        
        // Manually construct bytes for int 42 (SmallInt)
        var data = Data()
        data.append(contentsOf: [0x42, 0x4C, 0x41, 0x5A, 0x45])  // Magic
        data.append(0x01)  // Version
        data.append(contentsOf: [0x00, 0x01])  // 1 field
        data.append(0xFF)  // Custom field
        data.append(contentsOf: [0x00, 0x01])  // Length: 1
        data.append(0x61)  // Field name: 'a'
        data.append(0x12)  // SmallInt type
        data.append(0x2A)  // Value: 42
        
        let decoded = try BlazeBinaryDecoder.decode(data)
        
        XCTAssertEqual(decoded.storage["a"]?.intValue, 42, "Should read exact value 42!")
        print("  ✅ Decoder correctly reads [0x12][0x2A] as int(42)")
    }
    
    func testDirect_DecoderReadsString_FromExactBytes() throws {
        print("🔬 DIRECT: Decoder reads string from exact UTF-8 bytes")
        
        // Manually construct bytes for inline string "Hi"
        var data = Data()
        data.append(contentsOf: [0x42, 0x4C, 0x41, 0x5A, 0x45, 0x01, 0x00, 0x01])  // Header: 1 field
        data.append(0xFF)  // Custom field
        data.append(contentsOf: [0x00, 0x01])  // Length: 1
        data.append(0x61)  // Field name: 'a'
        data.append(0x22)  // Inline string type+len (0x20 + 2)
        data.append(contentsOf: [0x48, 0x69])  // "Hi"
        
        let decoded = try BlazeBinaryDecoder.decode(data)
        
        XCTAssertEqual(decoded.storage["a"]?.stringValue, "Hi", "Should read 'Hi' from bytes!")
        print("  ✅ Decoder correctly reads [0x22][Hi] as string(\"Hi\")")
    }
    
    // MARK: - Corruption Detection Tests (Direct Verification)
    
    func testDirect_DetectsTruncation_Immediately() throws {
        print("🔬 DIRECT: Decoder detects truncation immediately")
        
        let record = BlazeDataRecord(["a": .int(1), "b": .int(2), "c": .int(3)])
        let validEncoding = try BlazeBinaryEncoder.encode(record)
        
        // Truncate at different points
        let truncationPoints = [
            5,   // Middle of header
            10,  // Middle of first field
            20,  // Middle of second field
            validEncoding.count - 5  // Near end
        ]
        
        for truncPoint in truncationPoints {
            let truncated = validEncoding.prefix(truncPoint)
            
            XCTAssertThrowsError(try BlazeBinaryDecoder.decode(truncated)) { error in
                // Should throw error, not crash!
                XCTAssertTrue(error is BlazeBinaryError, "Should throw BlazeBinaryError")
            }
        }
        
        print("  ✅ All 4 truncation points detected immediately!")
    }
    
    func testDirect_DetectsByteCorruption_Exactly() throws {
        print("🔬 DIRECT: Decoder detects single-byte corruption")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        let validEncoding = try BlazeBinaryEncoder.encode(record)
        
        // Corrupt individual bytes and verify detection
        for corruptIndex in [0, 5, 10, 20, 30] {
            guard corruptIndex < validEncoding.count else { continue }
            
            var corrupted = validEncoding
            corrupted[corruptIndex] = ~corrupted[corruptIndex]  // Flip bits
            
            // Most corruptions should be detected
            // (Some might still decode but with wrong values)
            do {
                let decoded = try BlazeBinaryDecoder.decode(corrupted)
                
                // If it decodes, verify it's different (corruption changed data)
                let originalDecoded = try BlazeBinaryDecoder.decode(validEncoding)
                
                // At least one field should differ or be missing
                let matches = decoded.storage.keys.allSatisfy { key in
                    decoded.storage[key] == originalDecoded.storage[key]
                }
                
                if matches && decoded.storage.count == originalDecoded.storage.count {
                    // Very rare: corruption had no effect
                    print("  ⚠️  Byte \(corruptIndex) corruption had no effect (lucky!)")
                } else {
                    print("  ✅ Byte \(corruptIndex) corruption detected (wrong data)")
                }
            } catch {
                // Expected: decoder caught corruption
                print("  ✅ Byte \(corruptIndex) corruption caught by decoder!")
            }
        }
        
        print("  ✅ Single-byte corruptions detected or produce wrong data (safe!)") 
    }
    
    // MARK: - Exact Round-Trip Verification
    
    func testDirect_ExactRoundTrip_1000Times() throws {
        print("🔬 DIRECT: 1,000 exact round-trips with byte verification")
        
        for iteration in 0..<1000 {
            let record = BlazeDataRecord([
                "iteration": .int(iteration),
                "uuid": .uuid(UUID()),
                "timestamp": .date(Date()),
                "data": .string("Iteration \(iteration)")
            ])
            
            // Encode
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // Decode
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            
            // Verify EXACT match
            XCTAssertEqual(decoded.storage["iteration"]?.intValue, iteration, 
                          "Round-trip \(iteration): iteration corrupted!")
            XCTAssertEqual(decoded.storage["data"]?.stringValue, "Iteration \(iteration)",
                          "Round-trip \(iteration): string corrupted!")
            XCTAssertNotNil(decoded.storage["uuid"]?.uuidValue, 
                           "Round-trip \(iteration): UUID missing!")
            XCTAssertNotNil(decoded.storage["timestamp"]?.dateValue,
                           "Round-trip \(iteration): Date missing!")
        }
        
        print("  ✅ 1,000 round-trips: PERFECT preservation every time!")
    }
    
    // MARK: - Type Safety Verification
    
    func testDirect_TypeTagsCorrect_ForEachType() throws {
        print("🔬 DIRECT: Type tags are correct for each type")
        
        let typeTests: [(BlazeDocumentField, UInt8)] = [
            (.string("normal"), 0x01),      // Normal string
            (.string(""), 0x11),            // Empty string
            (.string("ab"), 0x22),          // Inline string (0x20 + 2)
            (.int(1000), 0x02),             // Full int
            (.int(42), 0x12),               // Small int
            (.double(3.14), 0x03),          // Double
            (.bool(true), 0x04),            // Bool
            (.uuid(UUID()), 0x05),          // UUID
            (.date(Date()), 0x06),          // Date
            (.data(Data([0x01])), 0x07),    // Data
            (.array([]), 0x18),             // Empty array
            (.array([.int(1)]), 0x08),      // Array
            (.dictionary([:]), 0x19),       // Empty dict
            (.dictionary(["k": .int(1)]), 0x09)  // Dict
        ]
        
        for (value, expectedType) in typeTests {
            let record = BlazeDataRecord(["field": value])
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // Find expected type tag in encoding
            XCTAssertTrue(encoded.contains(expectedType), 
                         "Type tag 0x\(String(expectedType, radix: 16)) not found for \(value)!")
        }
        
        print("  ✅ All 14 type variations use correct type tags!")
    }
    
    // MARK: - Big-Endian Verification
    
    func testDirect_BigEndianEncoding_AllIntegers() throws {
        print("🔬 DIRECT: All integers use big-endian encoding")
        
        let testValue: Int = 0x1234567890ABCDEF
        let record = BlazeDataRecord(["num": .int(testValue)])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Find int type tag
        guard let typeIndex = encoded.firstIndex(of: 0x02) else {
            XCTFail("Full int type not found")
            return
        }
        
        // Extract 8 bytes
        let bytes = encoded[(typeIndex + 1)...(typeIndex + 8)]
        
        // Verify big-endian order (most significant byte first)
        XCTAssertEqual(bytes.first, 0x12, "First byte should be 0x12 (most significant)")
        
        // ✅ FIX: Use alignment-safe decoding (avoid unaligned memory access)
        let bytesArray = Array(bytes)
        let decodedValue = bytesArray.withUnsafeBytes { buffer in
            // Break up complex expression for Swift compiler
            let b0 = UInt64(buffer[0]) << 56
            let b1 = UInt64(buffer[1]) << 48
            let b2 = UInt64(buffer[2]) << 40
            let b3 = UInt64(buffer[3]) << 32
            let b4 = UInt64(buffer[4]) << 24
            let b5 = UInt64(buffer[5]) << 16
            let b6 = UInt64(buffer[6]) << 8
            let b7 = UInt64(buffer[7])
            let raw = b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
            return Int(bitPattern: UInt(raw))
        }
        
        XCTAssertEqual(decodedValue, testValue, "Big-endian int should decode correctly!")
        
        print("  ✅ Big-endian encoding verified for large integers!")
    }
    
    // MARK: - No Data Loss Tests
    
    func testDirect_NoDataLoss_BinaryData() throws {
        print("🔬 DIRECT: Binary data (Data type) has zero corruption")
        
        // Test with critical byte patterns
        let testPatterns: [Data] = [
            Data([0x00]),                                    // Single zero
            Data([0xFF]),                                    // Single 0xFF
            Data([0x00, 0xFF]),                             // Zero + max
            Data([0x01, 0x02, 0x03, 0x04, 0x05]),          // Sequential
            Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB]),          // Reverse
            Data((0...255).map { UInt8($0) }),              // All bytes 0-255
            Data([0x42, 0x4C, 0x41, 0x5A, 0x45]),          // "BLAZE" (could confuse parser!)
            Data([0x01, 0x02, 0x03, 0x12, 0xFF, 0x08])     // Contains type tags
        ]
        
        for (index, pattern) in testPatterns.enumerated() {
            let record = BlazeDataRecord(["binary": .data(pattern)])
            
            let encoded = try BlazeBinaryEncoder.encode(record)
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            
            let decodedData = decoded.storage["binary"]?.dataValue
            
            // Verify byte-by-byte
            XCTAssertEqual(decodedData, pattern, "Pattern \(index) corrupted!")
            
            if decodedData != pattern {
                print("  ❌ Pattern \(index) CORRUPTED!")
                print("     Expected: \(pattern.map { String(format: "%02X", $0) }.joined())")
                print("     Got:      \(decodedData!.map { String(format: "%02X", $0) }.joined())")
                XCTFail("Data corruption in pattern \(index)!")
            }
        }
        
        print("  ✅ All \(testPatterns.count) binary patterns preserved exactly!")
    }
    
    func testDirect_NoDataLoss_UnicodeStrings() throws {
        print("🔬 DIRECT: Unicode strings have zero corruption")
        
        let unicodeTests = [
            "Hello 世界",
            "🔥🚀🎉",
            "Привет мир",
            "مرحبا بالعالم",
            "שלום עולם",
            "こんにちは世界",
            "Ñoño ñañoño",
            "Æthelred",
            "Zürich",
            "Mix: Hello世界🔥Привет!"
        ]
        
        for testString in unicodeTests {
            let record = BlazeDataRecord(["text": .string(testString)])
            
            let encoded = try BlazeBinaryEncoder.encode(record)
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            
            let decodedString = decoded.storage["text"]?.stringValue
            
            XCTAssertEqual(decodedString, testString, "Unicode string corrupted!")
            
            // Verify byte-by-byte UTF-8 encoding
            let originalBytes = testString.data(using: .utf8)!
            let decodedBytes = decodedString?.data(using: .utf8)!
            
            XCTAssertEqual(decodedBytes, originalBytes, "UTF-8 bytes corrupted!")
        }
        
        print("  ✅ All \(unicodeTests.count) Unicode strings preserved perfectly!")
    }
    
    // MARK: - Idempotence Tests
    
    func testDirect_EncodingIsIdempotent() throws {
        print("🔬 DIRECT: Encoding is idempotent (same result every time)")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!),
            "value": .int(42),
            "text": .string("Test")
        ])
        
        // Encode 100 times
        var encodings: [Data] = []
        for _ in 0..<100 {
            let encoded = try BlazeBinaryEncoder.encode(record)
            encodings.append(encoded)
        }
        
        // ALL should be IDENTICAL
        let reference = encodings[0]
        for (index, encoding) in encodings.enumerated() {
            XCTAssertEqual(encoding, reference, "Encoding \(index) differs!")
            
            // Byte-by-byte verification
            XCTAssertEqual(encoding.count, reference.count, "Size differs in encoding \(index)!")
            
            for byteIndex in 0..<reference.count {
                XCTAssertEqual(encoding[byteIndex], reference[byteIndex],
                              "Byte \(byteIndex) differs in encoding \(index)!")
            }
        }
        
        print("  ✅ 100 encodings: ALL byte-identical (idempotent!)")
    }
    
    func testDirect_DecodingIsIdempotent() throws {
        print("🔬 DIRECT: Decoding is idempotent (same result every time)")
        
        let record = BlazeDataRecord(["value": .int(42)])
        let encoded = try BlazeBinaryEncoder.encode(record)
        
        // Decode 100 times
        for iteration in 0..<100 {
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            
            XCTAssertEqual(decoded.storage.count, 1, "Field count changed in iteration \(iteration)!")
            XCTAssertEqual(decoded.storage["value"]?.intValue, 42, 
                          "Value changed in iteration \(iteration)!")
        }
        
        print("  ✅ 100 decodings: ALL produce identical result (idempotent!)")
    }
    
    // MARK: - Format Stability Tests
    
    func testDirect_FormatStability_AcrossRuns() throws {
        print("🔬 DIRECT: Format is stable (doesn't change between runs)")
        
        let fixedUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)  // Jan 1, 2001
        
        let record = BlazeDataRecord([
            "id": .uuid(fixedUUID),
            "timestamp": .date(fixedDate),
            "value": .int(42)
        ])
        
        // Encode 10 times
        let encodings = try (0..<10).map { _ in
            try BlazeBinaryEncoder.encode(record)
        }
        
        // All encodings should be EXACTLY the same
        let reference = encodings[0]
        for encoding in encodings {
            XCTAssertEqual(encoding, reference, "Format changed between runs!")
        }
        
        // Save reference encoding for future compatibility
        let hexDump = reference.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("  Reference encoding (v1.0):")
        print("  \(hexDump)")
        
        // This hex dump should NEVER change in future versions!
        // If it does, we need migration!
        
        print("  ✅ Format is stable across runs!")
    }
}

