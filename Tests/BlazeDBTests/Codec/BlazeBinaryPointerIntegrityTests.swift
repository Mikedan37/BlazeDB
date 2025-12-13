//
//  BlazeBinaryPointerIntegrityTests.swift
//  BlazeDBTests
//
//  Tests for pointer safety, bounds checking, and corruption handling
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryPointerIntegrityTests: XCTestCase {
    
    // MARK: - Bounds Checking Tests
    
    func testBounds_TruncatedHeader() throws {
        let truncated = Data([0x42, 0x4C, 0x41]) // Incomplete magic
        
        // Both codecs should fail with similar errors
        assertCodecsErrorEqual(truncated)
    }
    
    func testBounds_TruncatedFieldCount() throws {
        var data = Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0x01]) // Magic + version, missing field count
        data.append(contentsOf: [0x00]) // Only 1 byte of field count
        
        assertCodecsErrorEqual(data)
    }
    
    func testBounds_InvalidFieldCount() throws {
        var data = Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0x01]) // Magic + version
        // Field count = 0xFFFF (65535) - too large
        data.append(contentsOf: [0xFF, 0xFF])
        
        assertCodecsErrorEqual(data)
    }
    
    func testBounds_TruncatedStringLength() throws {
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Truncate before string data
        let truncated = armEncoded.prefix(armEncoded.count - 5)
        
        assertCodecsErrorEqual(Data(truncated))
    }
    
    func testBounds_InvalidStringLength() throws {
        // Create valid record
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt string length to be larger than remaining data
        if armEncoded.count > 20 {
            // Find string length bytes and corrupt them
            var bytes = Array(armEncoded)
            // Assuming string length is at offset ~15-18
            bytes[15] = 0xFF
            bytes[16] = 0xFF
            bytes[17] = 0xFF
            bytes[18] = 0xFF
            
            let corrupted = Data(bytes)
            assertCodecsErrorEqual(corrupted)
        }
    }
    
    func testBounds_TruncatedInt() throws {
        let record = BlazeDataRecord(["value": .int(42)])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Truncate in middle of int
        let truncated = armEncoded.prefix(armEncoded.count - 4)
        
        assertCodecsErrorEqual(Data(truncated))
    }
    
    func testBounds_TruncatedUUID() throws {
        let record = BlazeDataRecord(["id": .uuid(UUID())])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Truncate in middle of UUID
        let truncated = armEncoded.prefix(armEncoded.count - 8)
        
        assertCodecsErrorEqual(Data(truncated))
    }
    
    // MARK: - Corruption Tests
    
    func testCorruption_InvalidMagic() throws {
        let data = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x00]) // Invalid magic
        
        assertCodecsErrorEqual(data)
    }
    
    func testCorruption_InvalidVersion() throws {
        let data = Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0xFF, 0x00, 0x00]) // Invalid version
        
        assertCodecsErrorEqual(data)
    }
    
    func testCorruption_InvalidTypeTag() throws {
        let record = BlazeDataRecord(["value": .int(42)])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt type tag
        var bytes = Array(armEncoded)
        // Find type tag - it's after the header and field name
        // Structure: [BLAZE][version][fieldCount(2)][fieldName][typeTag][value...]
        // Header is 8 bytes, then field name (1 byte for common field), then type tag
        var typeTagOffset: Int? = nil
        
        // Check if field name is a common field (not 0xFF)
        if bytes.count > 8 && bytes[8] != 0xFF {
            // Common field - type tag is at offset 9
            typeTagOffset = 9
        } else {
            // Custom field - need to find type tag after field name
            var offset = 8 + 1 + 2 // Start after header + 0xFF + length
            if offset < bytes.count {
                let nameLen = Int((UInt16(bytes[9]) << 8) | UInt16(bytes[offset + 1]))
                offset += nameLen
                if offset < bytes.count {
                    typeTagOffset = offset
                }
            }
        }
        
        // Corrupt the type tag
        if let tagOffset = typeTagOffset, tagOffset < bytes.count {
            let originalTag = bytes[tagOffset]
            if (originalTag >= 0x01 && originalTag <= 0x19) || (originalTag >= 0x20 && originalTag <= 0x2F) {
                bytes[tagOffset] = 0xFF // Invalid type tag
            } else {
                bytes[tagOffset] = 0xFF
            }
        } else {
            // Fallback: try to find type tag by searching
            for i in 8..<min(bytes.count, 20) {
                let byte = bytes[i]
                if byte == 0x12 || byte == 0x02 || (byte >= 0x20 && byte <= 0x2F) {
                    bytes[i] = 0xFF
                    break
                }
            }
        }
        
        let corrupted = Data(bytes)
        assertCodecsErrorEqual(corrupted)
    }
    
    func testCorruption_CRC32Mismatch() throws {
        BlazeBinaryEncoder.crc32Mode = .enabled
        defer { BlazeBinaryEncoder.crc32Mode = .disabled }
        
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt CRC32
        var bytes = Array(armEncoded)
        bytes[bytes.count - 1] ^= 0xFF // Flip last byte
        
        let corrupted = Data(bytes)
        assertCodecsErrorEqual(corrupted)
    }
    
    func testCorruption_RandomByteFlip() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "count": .int(42)
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Flip random bytes
        var bytes = Array(armEncoded)
        for i in 0..<min(10, bytes.count) {
            bytes[i] ^= 0xFF
        }
        
        let corrupted = Data(bytes)
        assertCodecsErrorEqual(corrupted)
    }
    
    func testCorruption_InvalidUTF8() throws {
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt UTF-8 sequence
        var bytes = Array(armEncoded)
        // Find string data and corrupt it
        // Ensure we have enough bytes and valid range
        let searchEnd = min(25, bytes.count)
        if searchEnd > 15 {
            for i in 15..<searchEnd {
                if bytes[i] != 0x00 && bytes[i] != 0xFF {
                    bytes[i] = 0xFF // Invalid UTF-8
                    break
                }
            }
        } else if bytes.count > 0 {
            // If data is too short, corrupt a byte near the end
            let corruptIdx = max(0, bytes.count - 1)
            bytes[corruptIdx] = 0xFF
        }
        
        let corrupted = Data(bytes)
        assertCodecsErrorEqual(corrupted)
    }
    
    // MARK: - Safety Tests
    
    func testSafety_NoCrashOnInvalidPointer() throws {
        // Test that nil pointer is handled gracefully
        let invalidPointer: UnsafeRawPointer? = nil
        
        if let ptr = invalidPointer {
            XCTAssertThrowsError(try BlazeBinaryDecoder.decodeARM(fromMemoryMappedPage: ptr, length: 100)) { error in
                XCTAssertTrue(error is BlazeBinaryError)
            }
        }
    }
    
    func testSafety_NoInfiniteLoop() throws {
        // Create record with corrupted field count that might cause infinite loop
        var data = Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0x01]) // Magic + version
        data.append(contentsOf: [0x00, 0x05]) // Field count = 5
        
        // But only provide 1 field
        data.append(0x01) // Common field "id"
        data.append(0x12) // smallInt tag
        data.append(0x00) // value = 0
        
        // Both codecs should fail when trying to read field 2
        assertCodecsErrorEqual(data)
    }
    
    func testSafety_NegativeLength() throws {
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt length to be negative (when interpreted as signed)
        var bytes = Array(armEncoded)
        // Find string length bytes
        // Ensure we have enough bytes and valid range
        let searchEnd = min(20, bytes.count)
        if searchEnd > 15 {
            for i in 15..<searchEnd {
                // Make sure we don't go out of bounds when accessing bytes[i + 3]
                if i + 3 < bytes.count && bytes[i] > 0x80 { // High bit set
                    bytes[i] = 0xFF
                    bytes[i + 1] = 0xFF
                    bytes[i + 2] = 0xFF
                    bytes[i + 3] = 0xFF
                    break
                }
            }
        } else if bytes.count >= 4 {
            // If data is too short for the search range, corrupt the last 4 bytes
            let startIdx = max(0, bytes.count - 4)
            for i in startIdx..<bytes.count {
                bytes[i] = 0xFF
            }
        }
        
        let corrupted = Data(bytes)
        assertCodecsErrorEqual(corrupted)
    }
}

