//
//  CodecDualPathTestSuite.swift
//  BlazeDBTests
//
//  Top-level CI test suite ensuring Standard and ARM codecs remain in lockstep
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

/// Top-level test suite that validates both codecs produce identical results
/// This ensures long-term stability and prevents divergence
final class CodecDualPathTestSuite: XCTestCase {
    
    // MARK: - Comprehensive Field Type Tests
    
    func testDualPath_AllFieldTypes() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "count": .int(42),
            "price": .double(99.99),
            "isActive": .bool(true),
            "createdAt": .date(Date()),
            "data": .data(Data([1, 2, 3, 4, 5])),
            "tags": .array([.string("tag1"), .string("tag2")]),
            "metadata": .dictionary(["key": .string("value")])
        ])
        
        try assertCodecsEqual(record)
    }
    
    // MARK: - Edge Cases
    
    func testDualPath_EdgeCases() throws {
        // Empty values
        try assertCodecsEqual(BlazeDataRecord([
            "emptyString": .string(""),
            "emptyArray": .array([]),
            "emptyDict": .dictionary([:])
        ]))
        
        // Small ints (0-255)
        for i in [0, 1, 255, 256] {
            try assertCodecsEqual(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Large ints
        for i in [Int.min, -1, 0, 1, Int.max] {
            try assertCodecsEqual(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Inline strings (0-15 bytes)
        for length in [0, 1, 15, 16] {
            let str = String(repeating: "x", count: length)
            try assertCodecsEqual(BlazeDataRecord(["str": .string(str)]))
        }
    }
    
    // MARK: - Round-Trip Validation
    
    func testDualPath_RoundTrip() throws {
        let original = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Round Trip"),
            "count": .int(12345)
        ])
        
        // Standard encode -> Both decode
        let stdEncoded = try BlazeBinaryEncoder.encode(original)
        try assertCodecsDecodeEqual(stdEncoded)
        
        // ARM encode -> Both decode
        let armEncoded = try BlazeBinaryEncoder.encodeARM(original)
        try assertCodecsDecodeEqual(armEncoded)
        
        // Full round-trip
        try assertCodecsEqual(original)
    }
    
    // MARK: - Memory-Mapped Decode
    
    func testDualPath_MMapDecode() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("MMap Test")
        ])
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        
        // Decode standard way
        let stdDecoded = try BlazeBinaryDecoder.decode(encoded)
        
        // Decode memory-mapped way
        let armDecoded = try encoded.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw BlazeBinaryError.invalidFormat("Invalid buffer")
            }
            return try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: encoded.count)
        }
        
        assertRecordsEqual(stdDecoded, armDecoded)
    }
    
    // MARK: - Error Behavior
    
    func testDualPath_ErrorBehavior() throws {
        let corruptions: [Data] = [
            Data([0xFF, 0xFF, 0xFF, 0xFF]),
            Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0xFF, 0xFF, 0xFF]),
            Data(repeating: 0x00, count: 10)
        ]
        
        for corrupted in corruptions {
            assertCodecsErrorEqual(corrupted)
        }
    }
    
    // MARK: - Performance Baseline
    
    func testDualPath_PerformanceBaseline() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string(String(repeating: "x", count: 100)),
            "count": .int(42)
        ])
        
        // Verify correctness first
        try assertCodecsEqual(record)
        
        // Measure performance
        let (stdTime, armTime) = measureCodecPerformanceHelper(record, iterations: 1000)
        
        // ARM should not be significantly slower
        XCTAssertLessThanOrEqual(armTime, stdTime * 1.1, "ARM encoder should not be significantly slower than standard")
        
        print("📊 Dual-Path Performance: Standard=\(String(format: "%.3f", stdTime))s, ARM=\(String(format: "%.3f", armTime))s")
    }
    
    // MARK: - Large Records
    
    func testDualPath_LargeRecords() throws {
        // 100 fields
        var storage: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            storage["field\(i)"] = .string("Value \(i)")
        }
        try assertCodecsEqual(BlazeDataRecord(storage))
        
        // Large array
        var items: [BlazeDocumentField] = []
        for i in 0..<1000 {
            items.append(.int(i))
        }
        try assertCodecsEqual(BlazeDataRecord(["items": .array(items)]))
        
        // Large data blob
        let largeData = Data(repeating: 0xFF, count: 100_000)
        try assertCodecsEqual(BlazeDataRecord(["data": .data(largeData)]))
    }
    
    // MARK: - CRC32
    
    func testDualPath_CRC32() throws {
        BlazeBinaryEncoder.crc32Mode = .enabled
        defer { BlazeBinaryEncoder.crc32Mode = .disabled }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("CRC Test")
        ])
        
        try assertCodecsEqual(record)
    }
    
    // MARK: - Helper Methods
    
    private func measureCodecPerformanceHelper(_ record: BlazeDataRecord, iterations: Int) -> (TimeInterval, TimeInterval) {
        let standardTime = measureTime {
            for _ in 0..<iterations {
                _ = try? BlazeBinaryEncoder.encode(record)
            }
        }
        
        let armTime = measureTime {
            for _ in 0..<iterations {
                _ = try? BlazeBinaryEncoder.encodeARM(record)
            }
        }
        
        return (standardTime, armTime)
    }
    
    private func measureTime(_ block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }
}
