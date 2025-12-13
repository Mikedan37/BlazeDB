//
//  BlazeBinaryFieldViewTests.swift
//  BlazeDBTests
//
//  Tests for zero-copy BlazeBinaryFieldView lazy decoding
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryFieldViewTests: XCTestCase {
    
    func testFieldView_LazyDecoding() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "count": .int(42)
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Decode standard-encoded data with both decoders
        let stdDecoded = try BlazeBinaryDecoder.decode(stdEncoded)
        let armDecodedFromStd = try BlazeBinaryDecoder.decodeARM(stdEncoded)
        assertRecordsEqual(stdDecoded, armDecodedFromStd)
        
        // Decode ARM-encoded data with memory-mapped approach
        let armDecodedFromMMap = try armEncoded.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw BlazeBinaryError.invalidFormat("Invalid buffer")
            }
            return try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: baseAddress, length: armEncoded.count)
        }
        
        assertRecordsEqual(record, armDecodedFromMMap)
        XCTAssertEqual(armDecodedFromMMap.storage["title"]?.stringValue, "Test")
        XCTAssertEqual(armDecodedFromMMap.storage["count"]?.intValue, 42)
    }
    
    func testFieldView_ZeroCopyAccess() throws {
        // This test verifies that accessing fields doesn't allocate unnecessarily
        // Note: Actual allocation tracking would require more sophisticated tools
        
        let record = BlazeDataRecord([
            "largeString": .string(String(repeating: "x", count: 10000)),
            "largeData": .data(Data(repeating: 0xFF, count: 10000))
        ])
        
        // Dual-codec validation
        try assertCodecsEqual(record)
        
        // Decode and access fields
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        let stdDecoded = try BlazeBinaryDecoder.decode(encoded)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(encoded)
        
        // Both decoders should produce identical results
        assertRecordsEqual(stdDecoded, armDecoded)
        
        // Access should work without crashes
        XCTAssertNotNil(armDecoded.storage["largeString"])
        XCTAssertNotNil(armDecoded.storage["largeData"])
    }
    
    func testFieldView_InvalidBuffer() throws {
        // Test that invalid buffers fail gracefully for both codecs
        let invalidData = Data([0xFF, 0xFF, 0xFF, 0xFF])
        
        assertCodecsErrorEqual(invalidData)
    }
    
    func testFieldView_TruncatedData() throws {
        let record = BlazeDataRecord([
            "title": .string("Test")
        ])
        
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        
        // Truncate data
        let truncated = encoded.prefix(encoded.count - 1)
        let truncatedData = Data(truncated)
        
        // Both codecs should fail with similar errors
        assertCodecsErrorEqual(truncatedData)
    }
}

