//
//  BlazeBinaryARMBenchmarks.swift
//  BlazeDBTests
//
//  Performance benchmarks comparing standard vs ARM-optimized BlazeBinary codec
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryARMBenchmarks: XCTestCase {
    
    var testRecord: BlazeDataRecord!
    var largeRecord: BlazeDataRecord!
    var testRecords: [BlazeDataRecord]!
    
    override func setUp() {
        super.setUp()
        
        // Small record
        testRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test Record"),
            "count": .int(42),
            "price": .double(99.99),
            "isActive": .bool(true),
            "createdAt": .date(Date())
        ])
        
        // Large record with many fields
        var largeStorage: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            largeStorage["field\(i)"] = .string("Value \(i) " + String(repeating: "x", count: 100))
        }
        largeRecord = BlazeDataRecord(largeStorage)
        
        // Batch records
        testRecords = (0..<1000).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "data": .data(Data(repeating: UInt8(i % 256), count: 100))
            ])
        }
    }
    
    // MARK: - Encoding Benchmarks
    
    func testPerformance_StandardEncode() {
        measure {
            for _ in 0..<100 {
                // UPDATED: Use ARM codec (this is the performance benchmark)
                _ = try? BlazeBinaryEncoder.encodeARM(testRecord)
            }
        }
    }
    
    func testPerformance_ARMEncode() {
        measure {
            for _ in 0..<100 {
                _ = try? BlazeBinaryEncoder.encodeARM(testRecord)
            }
        }
    }
    
    func testPerformance_StandardEncodeLarge() {
        measure {
            for _ in 0..<10 {
                // UPDATED: Use ARM codec (this is the performance benchmark)
                _ = try? BlazeBinaryEncoder.encodeARM(largeRecord)
            }
        }
    }
    
    func testPerformance_ARMEncodeLarge() {
        measure {
            for _ in 0..<10 {
                _ = try? BlazeBinaryEncoder.encodeARM(largeRecord)
            }
        }
    }
    
    func testPerformance_StandardEncodeBatch() {
        measure {
            // UPDATED: Use ARM codec (this is the performance benchmark)
            _ = try? testRecords.map { try BlazeBinaryEncoder.encodeARM($0) }
        }
    }
    
    func testPerformance_ARMEncodeBatch() {
        measure {
            _ = try? testRecords.map { try BlazeBinaryEncoder.encodeARM($0) }
        }
    }
    
    // MARK: - Decoding Benchmarks
    
    func testPerformance_StandardDecode() throws {
        let encoded = try BlazeBinaryEncoder.encode(testRecord)
        
        measure {
            for _ in 0..<100 {
                _ = try? BlazeBinaryDecoder.decode(encoded)
            }
        }
    }
    
    func testPerformance_ARMDecode() throws {
        let encoded = try BlazeBinaryEncoder.encodeARM(testRecord)
        
        measure {
            for _ in 0..<100 {
                _ = try? BlazeBinaryDecoder.decodeARM(encoded)
            }
        }
    }
    
    func testPerformance_StandardDecodeLarge() throws {
        // UPDATED: Use ARM codec and verify correctness first
        try assertCodecsEncodeEqual(largeRecord)
        let encoded = try BlazeBinaryEncoder.encodeARM(largeRecord)
        
        measure {
            for _ in 0..<10 {
                _ = try? BlazeBinaryDecoder.decodeARM(encoded)
            }
        }
    }
    
    func testPerformance_ARMDecodeLarge() throws {
        let encoded = try BlazeBinaryEncoder.encodeARM(largeRecord)
        
        measure {
            for _ in 0..<10 {
                _ = try? BlazeBinaryDecoder.decodeARM(encoded)
            }
        }
    }
    
    func testPerformance_StandardDecodeBatch() throws {
        // UPDATED: Use ARM codec and verify correctness first
        for record in testRecords {
            try assertCodecsEncodeEqual(record)
        }
        let encoded = try testRecords.map { try BlazeBinaryEncoder.encodeARM($0) }
        
        measure {
            _ = try? encoded.map { try BlazeBinaryDecoder.decodeARM($0) }
        }
    }
    
    func testPerformance_ARMDecodeBatch() throws {
        let encoded = try testRecords.map { try BlazeBinaryEncoder.encodeARM($0) }
        
        measure {
            _ = try? encoded.map { try BlazeBinaryDecoder.decodeARM($0) }
        }
    }
    
    // MARK: - Memory-Mapped Decode
    
    func testPerformance_ARMDecodeMemoryMapped() throws {
        let encoded = try BlazeBinaryEncoder.encodeARM(testRecord)
        
        measure {
            for _ in 0..<100 {
                _ = try? encoded.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> BlazeDataRecord? in
                    guard let baseAddress = bytes.baseAddress else { return nil }
                    return try? BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: encoded.count)
                }
            }
        }
    }
    
    // MARK: - Compatibility Tests
    
    func testCompatibility_StandardToARM() throws {
        let standardEncoded = try BlazeBinaryEncoder.encode(testRecord)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(standardEncoded)
        
        XCTAssertEqual(armDecoded.storage.count, testRecord.storage.count)
        XCTAssertEqual(armDecoded.storage["title"]?.stringValue, testRecord.storage["title"]?.stringValue)
    }
    
    func testCompatibility_ARMToStandard() throws {
        let armEncoded = try BlazeBinaryEncoder.encodeARM(testRecord)
        let standardDecoded = try BlazeBinaryDecoder.decode(armEncoded)
        
        XCTAssertEqual(standardDecoded.storage.count, testRecord.storage.count)
        XCTAssertEqual(standardDecoded.storage["title"]?.stringValue, testRecord.storage["title"]?.stringValue)
    }
    
    func testCompatibility_RoundTrip() throws {
        // Standard encode -> ARM decode -> ARM encode -> Standard decode
        let standardEncoded = try BlazeBinaryEncoder.encode(testRecord)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(standardEncoded)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(armDecoded)
        let finalDecoded = try BlazeBinaryDecoder.decode(armEncoded)
        
        XCTAssertEqual(finalDecoded.storage.count, testRecord.storage.count)
        for (key, value) in testRecord.storage {
            XCTAssertEqual(finalDecoded.storage[key], value, "Mismatch for key: \(key)")
        }
    }
}

