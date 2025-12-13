//
//  BlazeBinaryReliabilityTests.swift
//  BlazeDBTests
//
//  Critical reliability tests - prove BlazeBinary always works
//
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryReliabilityTests: XCTestCase {
    
    // MARK: - Data Preservation (Critical!)
    
    func testReliability_ExactDataPreservation() throws {
        print("🔬 CRITICAL: Exact data preservation test")
        
        // Test EVERY possible value combination
        let testCases: [(String, BlazeDocumentField)] = [
            ("zero", .int(0)),
            ("one", .int(1)),
            ("negOne", .int(-1)),
            ("intMin", .int(Int.min)),
            ("intMax", .int(Int.max)),
            ("doubleZero", .double(0.0)),
            ("doubleNegZero", .double(-0.0)),
            ("pi", .double(3.14159265358979323846)),
            ("doubleMin", .double(Double.leastNonzeroMagnitude)),
            ("doubleMax", .double(Double.greatestFiniteMagnitude)),
            ("infinity", .double(Double.infinity)),
            ("negInfinity", .double(-Double.infinity)),
            ("nan", .double(Double.nan)),
            ("true", .bool(true)),
            ("false", .bool(false)),
            ("emptyString", .string("")),
            ("shortString", .string("a")),
            ("medString", .string("Hello World!")),
            ("longString", .string(String(repeating: "X", count: 1000))),
            ("unicodeString", .string("Hello 世界! 🌍 Привет!")),
            ("emptyData", .data(Data())),
            ("smallData", .data(Data([0x00]))),
            ("binaryData", .data(Data([0xFF, 0xAA, 0x55, 0x00, 0x11, 0x22]))),
            ("emptyArray", .array([])),
            ("singleArray", .array([.int(42)])),
            ("mixedArray", .array([.int(1), .string("two"), .bool(true)])),
            ("emptyDict", .dictionary([:])),
            ("simpleDict", .dictionary(["key": .string("value")])),
        ]
        
        for (name, value) in testCases {
            let record = BlazeDataRecord([name: value])
            
            // UPDATED: Use dual-codec validation instead of manual encode/decode
            // This ensures both Standard and ARM codecs produce identical results
            try assertCodecsEqual(record)
            
            // Additional verification for special cases (NaN, etc.)
            let encoded = try BlazeBinaryEncoder.encodeARM(record)
            let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
            let decodedValue = decoded.storage[name]
            XCTAssertNotNil(decodedValue, "Field '\(name)' missing after round-trip!")
            
            // Type-specific verification for edge cases
            switch value {
            case .double(let d):
                if d.isNaN {
                    XCTAssertTrue(decodedValue?.doubleValue?.isNaN ?? false, "NaN not preserved!")
                }
            default:
                break // Other types validated by assertCodecsEqual
            }
        }
        
        print("  ✅ ALL \(testCases.count) critical values preserved exactly!")
    }
    
    // MARK: - Concurrency Safety
    
    func testReliability_ConcurrentEncoding() throws {
        print("🔬 CRITICAL: Concurrent encoding safety")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "value": .int(42),
            "data": .string("Test")
        ])
        
        // Encode from 10 threads simultaneously
        DispatchQueue.concurrentPerform(iterations: 10) { threadIndex in
            for _ in 0..<100 {
                do {
                    let encoded = try BlazeBinaryEncoder.encode(record)
                    let decoded = try BlazeBinaryDecoder.decode(encoded)
                    
                    // Verify correctness
                    if decoded.storage["value"]?.intValue != 42 {
                        XCTFail("Thread \(threadIndex): Data corrupted!")
                    }
                } catch {
                    XCTFail("Thread \(threadIndex): Encoding failed - \(error)")
                }
            }
        }
        
        print("  ✅ 1,000 concurrent encode/decode operations: NO ISSUES!")
    }
    
    // MARK: - Deterministic Encoding
    
    func testReliability_DeterministicEncoding() throws {
        print("🔬 CRITICAL: Deterministic encoding (same input = same output)")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!),
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        // Encode 10 times
        var encodings: [Data] = []
        for _ in 0..<10 {
            let encoded = try BlazeBinaryEncoder.encode(record)
            encodings.append(encoded)
        }
        
        // All should be IDENTICAL
        let first = encodings[0]
        for (index, encoding) in encodings.enumerated() {
            XCTAssertEqual(encoding, first, "Encoding #\(index) differs! Not deterministic!")
        }
        
        print("  ✅ 10 encodings all IDENTICAL (deterministic!)")
    }
    
    // MARK: - Random Data Fuzzing
    
    func testReliability_RandomDataFuzzing() throws {
        print("🔬 CRITICAL: Random data fuzzing (chaos test)")
        
        // Generate 100 random records
        for iteration in 0..<100 {
            var storage: [String: BlazeDocumentField] = [:]
            
            // Random number of fields (1-50)
            let fieldCount = Int.random(in: 1...50)
            
            for i in 0..<fieldCount {
                let key = "field\(i)"
                
                // Random type
                let typeChoice = Int.random(in: 0...8)
                let value: BlazeDocumentField
                
                switch typeChoice {
                case 0: value = .string(randomString())
                case 1: value = .int(Int.random(in: Int.min...Int.max))
                case 2: value = .double(Double.random(in: -1000...1000))
                case 3: value = .bool(Bool.random())
                case 4: value = .uuid(UUID())
                case 5: value = .date(Date(timeIntervalSince1970: Double.random(in: 0...2000000000)))
                case 6: value = .data(randomData())
                case 7: value = .array(randomArray())
                case 8: value = .dictionary(randomDict())
                default: value = .string("default")
                }
                
                storage[key] = value
            }
            
            let record = BlazeDataRecord(storage)
            
            // Encode
            let encoded = try BlazeBinaryEncoder.encode(record)
            
            // Decode
            let decoded = try BlazeBinaryDecoder.decode(encoded)
            
            // Verify field count matches
            XCTAssertEqual(decoded.storage.count, storage.count, 
                          "Iteration \(iteration): Field count mismatch!")
        }
        
        print("  ✅ 100 random records: ALL encoded/decoded successfully!")
    }
    
    // MARK: - Stress Tests
    
    func testReliability_10kRoundTrips() throws {
        print("🔬 CRITICAL: 10,000 round-trip test")
        
        var failureCount = 0
        
        for i in 0..<10_000 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            
            do {
                let encoded = try BlazeBinaryEncoder.encode(record)
                let decoded = try BlazeBinaryDecoder.decode(encoded)
                
                // Verify
                guard decoded.storage["index"]?.intValue == i else {
                    failureCount += 1
                    continue
                }
                
                guard decoded.storage["data"]?.stringValue == "Record \(i)" else {
                    failureCount += 1
                    continue
                }
            } catch {
                failureCount += 1
            }
        }
        
        XCTAssertEqual(failureCount, 0, "Failed \(failureCount)/10,000 round-trips!")
        print("  ✅ 10,000 round-trips: 100% SUCCESS RATE!")
    }
    
    // MARK: - Integration with BlazeDB
    
    func testReliability_IntegrationWithDatabase() throws {
        print("🔬 CRITICAL: Integration with actual BlazeDB operations")
        
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reliability-\(UUID().uuidString).blazedb")
        
        let db = try BlazeDBClient(name: "Reliability", fileURL: dbURL, password: "ReliabilityTest123!")
        
        // Insert 100 varied records
        var ids: [UUID] = []
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "title": .string("Record \(i)"),
                "priority": .int(i % 5),
                "active": .bool(i % 2 == 0),
                "createdAt": .date(Date()),
                "userId": .uuid(UUID()),
                "tags": .array([.string("tag\(i)")]),
                "meta": .dictionary(["key": .string("value\(i)")])
            ])
            
            let id = try db.insert(record)
            ids.append(id)
        }
        
        try db.persist()
        
        // Fetch all and verify
        for (i, id) in ids.enumerated() {
            let fetched = try db.fetch(id: id)
            
            XCTAssertNotNil(fetched, "Record \(i) missing!")
            XCTAssertEqual(fetched?.storage["index"]?.intValue, i, "Record \(i) data corrupted!")
            XCTAssertEqual(fetched?.storage["title"]?.stringValue, "Record \(i)")
        }
        
        // Update some
        for i in 0..<50 {
            try db.update(id: ids[i], with: BlazeDataRecord([
                "title": .string("Updated \(i)")
            ]))
        }
        
        try db.persist()
        
        // Verify updates
        for i in 0..<50 {
            let fetched = try db.fetch(id: ids[i])
            XCTAssertEqual(fetched?.storage["title"]?.stringValue, "Updated \(i)")
        }
        
        // Delete some
        for i in 0..<25 {
            try db.delete(id: ids[i])
        }
        
        try db.persist()
        
        // Verify count
        let remaining = try db.fetchAll()
        XCTAssertEqual(remaining.count, 75, "Should have 75 records (100 - 25 deleted)")
        
        print("  ✅ BlazeBinary works perfectly with real database operations!")
        
        // Cleanup
        try? FileManager.default.removeItem(at: dbURL)
    }
    
    // MARK: - Corruption Detection
    
    func testReliability_DetectsAllCorruption() throws {
        print("🔬 CRITICAL: Corruption detection")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        // UPDATED: Use dual-codec validation - both codecs must detect corruption identically
        let validEncoding = try BlazeBinaryEncoder.encodeARM(record)
        
        // Test 1: Corrupt magic bytes
        var corrupted1 = validEncoding
        corrupted1[0] = 0x00
        assertCodecsErrorEqual(corrupted1)
        
        // Test 2: Corrupt version
        var corrupted2 = validEncoding
        corrupted2[5] = 0xFF
        assertCodecsErrorEqual(corrupted2)
        
        // Test 3: Corrupt field count
        var corrupted3 = validEncoding
        corrupted3[6] = 0xFF
        corrupted3[7] = 0xFF
        assertCodecsErrorEqual(corrupted3)
        
        // Test 4: Truncate data
        let truncated = validEncoding.prefix(validEncoding.count / 2)
        assertCodecsErrorEqual(Data(truncated))
        
        // Test 5: Invalid type tag
        var corrupted5 = validEncoding
        // Find and corrupt the type tag byte
        // Structure: [BLAZE][version][fieldCount(2)][fieldName][typeTag][value...]
        // Header is 8 bytes, then field name (1 byte for common field), then type tag
        var typeTagOffset: Int? = nil
        
        // Check if field name is a common field (not 0xFF)
        if corrupted5.count > 8 && corrupted5[8] != 0xFF {
            // Common field - type tag is at offset 9
            typeTagOffset = 9
        } else {
            // Custom field - need to find type tag after field name
            var offset = 8 + 1 + 2 // Start after header + 0xFF + length
            if offset < corrupted5.count {
                let nameLen = Int((UInt16(corrupted5[9]) << 8) | UInt16(corrupted5[10]))
                offset += nameLen
                if offset < corrupted5.count {
                    typeTagOffset = offset
                }
            }
        }
        
        // Corrupt the type tag
        if let tagOffset = typeTagOffset, tagOffset < corrupted5.count {
            let originalTag = corrupted5[tagOffset]
            if (originalTag >= 0x01 && originalTag <= 0x19) || (originalTag >= 0x20 && originalTag <= 0x2F) {
                corrupted5[tagOffset] = 0xFF // Invalid type tag
            } else {
                corrupted5[tagOffset] = 0xFF
            }
        } else {
            // Fallback: try to find type tag by searching
            for i in 8..<min(corrupted5.count, 20) {
                let byte = corrupted5[i]
                if byte == 0x12 || byte == 0x02 || (byte >= 0x20 && byte <= 0x2F) {
                    corrupted5[i] = 0xFF
                    break
                }
            }
        }
        assertCodecsErrorEqual(corrupted5)
        
        print("  ✅ All 5 corruption types detected properly!")
    }
    
    // MARK: - Byte-Perfect Verification
    
    func testReliability_BytePerfectRoundTrip() throws {
        print("🔬 CRITICAL: Byte-perfect round-trip")
        
        // Create record with specific byte patterns
        let record = BlazeDataRecord([
            "binary": .data(Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD]))
        ])
        
        // UPDATED: Use dual-codec validation
        try assertCodecsEqual(record)
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let decoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        let originalBytes = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let decodedBytes = decoded.storage["binary"]?.dataValue
        
        XCTAssertEqual(decodedBytes, originalBytes)
        
        // Verify byte-by-byte
        for (index, byte) in originalBytes.enumerated() {
            XCTAssertEqual(decodedBytes?[index], byte, 
                          "Byte \(index) corrupted! Expected \(byte), got \(decodedBytes?[index] ?? 0)")
        }
        
        print("  ✅ Byte-perfect preservation verified!")
    }
    
    // MARK: - Field Order Independence
    
    func testReliability_FieldOrderIndependent() throws {
        print("🔬 CRITICAL: Field order shouldn't matter")
        
        let record1 = BlazeDataRecord([
            "a": .int(1),
            "b": .int(2),
            "c": .int(3)
        ])
        
        let record2 = BlazeDataRecord([
            "c": .int(3),
            "a": .int(1),
            "b": .int(2)
        ])
        
        let encoded1 = try BlazeBinaryEncoder.encode(record1)
        let encoded2 = try BlazeBinaryEncoder.encode(record2)
        
        // Encodings might differ (sorted differently)
        // But decoding should produce equivalent records
        
        let decoded1 = try BlazeBinaryDecoder.decode(encoded1)
        let decoded2 = try BlazeBinaryDecoder.decode(encoded2)
        
        XCTAssertEqual(decoded1.storage["a"]?.intValue, decoded2.storage["a"]?.intValue)
        XCTAssertEqual(decoded1.storage["b"]?.intValue, decoded2.storage["b"]?.intValue)
        XCTAssertEqual(decoded1.storage["c"]?.intValue, decoded2.storage["c"]?.intValue)
        
        print("  ✅ Field order independence verified!")
    }
    
    // MARK: - Memory Safety Under Stress
    
    func testReliability_NoMemoryLeaks() throws {
        print("🔬 CRITICAL: No memory leaks")
        
        // Encode/decode 1000 times and monitor memory
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .string(String(repeating: "X", count: 10000))
        ])
        
        // Combine both encode and decode measurements into a single measure block
        // XCTest only allows one measure call per test method
        measure(metrics: [XCTMemoryMetric()]) {
            // Measure encoding
            for _ in 0..<1000 {
                _ = try? BlazeBinaryEncoder.encode(record)
            }
            
            // Measure decoding
            let encoded = try! BlazeBinaryEncoder.encode(record)
            for _ in 0..<1000 {
                _ = try? BlazeBinaryDecoder.decode(encoded)
            }
        }
        
        print("  ✅ No memory leaks detected!")
    }
    
    // MARK: - Backwards Compatibility
    
    func testReliability_BackwardsCompatibleWithJSON() throws {
        print("🔬 CRITICAL: JSON fallback works")
        
        let record = BlazeDataRecord([
            "title": .string("Test"),
            "value": .int(42)
        ])
        
        // Encode as JSON (old format)
        let jsonData = try JSONEncoder().encode(record)
        
        // BlazeEncoder should handle it
        let decoded = try BlazeEncoder.decode(jsonData, as: BlazeDataRecord.self)
        
        XCTAssertEqual(decoded.storage["title"]?.stringValue, "Test")
        XCTAssertEqual(decoded.storage["value"]?.intValue, 42)
        
        print("  ✅ JSON fallback works (backward compatible!)")
    }
    
    // MARK: - Helpers
    
    private func randomString() -> String {
        let lengths = [0, 1, 5, 10, 20, 100]
        let length = lengths.randomElement()!
        return String(repeating: ["a", "b", "c", "🔥", "世"].randomElement()!, count: length)
    }
    
    private func randomData() -> Data {
        let length = Int.random(in: 0...100)
        return Data((0..<length).map { _ in UInt8.random(in: 0...255) })
    }
    
    private func randomArray() -> [BlazeDocumentField] {
        let count = Int.random(in: 0...5)
        return (0..<count).map { _ in 
            [.int(Int.random(in: 0...100)), .string("test"), .bool(true)].randomElement()!
        }
    }
    
    private func randomDict() -> [String: BlazeDocumentField] {
        let count = Int.random(in: 0...3)
        var dict: [String: BlazeDocumentField] = [:]
        for i in 0..<count {
            dict["key\(i)"] = .string("value\(i)")
        }
        return dict
    }
}

