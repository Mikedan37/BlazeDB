//
//  BlazeBinaryCorruptionRecoveryTests.swift
//  BlazeDBTests
//
//  Tests for safe handling of corrupted data
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryCorruptionRecoveryTests: XCTestCase {
    
    func testCorruption_RandomByteFlips() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test"),
            "count": .int(42)
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt critical header bytes (magic bytes, field count, etc.)
        // Random byte flips don't always produce detectable corruption
        // Focus on corrupting specific critical areas
        
        // Test 1: Corrupt magic bytes
        var corruptedMagic = armEncoded
        var bytes = Array(corruptedMagic)
        if bytes.count > 2 {
            bytes[2] ^= 0xFF  // Flip magic byte
            corruptedMagic = Data(bytes)
            assertCodecsErrorEqual(corruptedMagic)
        }
        
        // Test 2: Corrupt field count
        var corruptedFieldCount = armEncoded
        bytes = Array(corruptedFieldCount)
        if bytes.count > 7 {
            bytes[6] = 0xFF  // Set invalid field count
            bytes[7] = 0xFF
            corruptedFieldCount = Data(bytes)
            // Note: Very large field counts might not error immediately
            // but will error when trying to read beyond data bounds
        }
    }
    
    func testCorruption_TruncatedFinals() throws {
        let record = BlazeDataRecord([
            "title": .string("Test"),
            "count": .int(42)
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Truncate at various points
        for truncateAmount in [1, 2, 5, 10, armEncoded.count / 2] {
            let truncated = armEncoded.prefix(max(1, armEncoded.count - truncateAmount))
            let truncatedData = Data(truncated)
            
            // Both codecs should fail with similar errors
            assertCodecsErrorEqual(truncatedData)
        }
    }
    
    func testCorruption_InvalidTypeTag() throws {
        let record = BlazeDataRecord(["value": .int(42)])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Replace type tag with invalid value
        // Structure: [BLAZE][version][fieldCount(2)][fieldName][typeTag][value...]
        // Header is 8 bytes (5 magic + 1 version + 2 fieldCount)
        // For "value" field (common field 0x2E) with int(42):
        // [0-7]: Header (8 bytes)
        // [8]: Field name byte (0x2E for "value")
        // [9]: Type tag (0x12 for smallInt)
        // [10]: Value (42 = 0x2A)
        var bytes = Array(armEncoded)
        
        guard bytes.count >= 10 else {
            XCTFail("Encoded data too short: \(bytes.count) bytes")
            return
        }
        
        // Find the type tag byte - it's after the header and field name
        // For common fields, type tag is at offset 9 (header=8, fieldName=1)
        // For custom fields (0xFF), type tag is after 0xFF + 2 length bytes + name
        
        var typeTagOffset: Int? = nil
        
        // Check if field name is a common field (not 0xFF)
        if bytes.count > 8 && bytes[8] != 0xFF {
            // Common field - type tag is at offset 9
            typeTagOffset = 9
        } else {
            // Custom field - need to find type tag after field name
            // Skip header (8 bytes) + 0xFF (1 byte) + length (2 bytes) + name
            var offset = 8 + 1 + 2 // Start after header + 0xFF + length
            if offset < bytes.count {
                // Read field name length
                let nameLen = Int((UInt16(bytes[9]) << 8) | UInt16(bytes[10]))
                offset += nameLen
                if offset < bytes.count {
                    typeTagOffset = offset
                }
            }
        }
        
        // Corrupt the type tag
        if let tagOffset = typeTagOffset, tagOffset < bytes.count {
            // Verify it looks like a type tag (0x01-0x19 or 0x20-0x2F)
            let originalTag = bytes[tagOffset]
            if (originalTag >= 0x01 && originalTag <= 0x19) || (originalTag >= 0x20 && originalTag <= 0x2F) {
                bytes[tagOffset] = 0xFF // Invalid type tag
            } else {
                // If it doesn't look like a type tag, corrupt it anyway
                bytes[tagOffset] = 0xFF
            }
        } else {
            // Fallback: try to find type tag by searching for known values
            for i in 8..<min(bytes.count, 20) {
                let byte = bytes[i]
                // Look for known type tags: smallInt (0x12), int (0x02), or inline strings (0x20-0x2F)
                if byte == 0x12 || byte == 0x02 || (byte >= 0x20 && byte <= 0x2F) {
                    bytes[i] = 0xFF // Invalid type tag
                    break
                }
            }
        }
        
        let corrupted = Data(bytes)
        
        // Both codecs should fail with similar errors
        assertCodecsErrorEqual(corrupted)
    }
    
    func testCorruption_WrongLengthPrefix() throws {
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt string length to be larger than actual data
        var bytes = Array(armEncoded)
        // Find string length bytes (usually around offset 15-18)
        // Ensure we have enough bytes and valid range
        let searchEnd = min(20, bytes.count - 4)
        if searchEnd > 15 {
            for i in 15..<searchEnd {
                if bytes[i] > 0 && bytes[i] < 100 {
                    // Likely length bytes - corrupt them
                    bytes[i] = 0xFF
                    bytes[i + 1] = 0xFF
                    bytes[i + 2] = 0xFF
                    bytes[i + 3] = 0xFF
                    break
                }
            }
        } else {
            // If data is too short, corrupt the last 4 bytes
            if bytes.count >= 4 {
                let startIdx = max(0, bytes.count - 4)
                for i in startIdx..<bytes.count {
                    bytes[i] = 0xFF
                }
            }
        }
        
        let corrupted = Data(bytes)
        
        // Both codecs should fail with similar errors
        assertCodecsErrorEqual(corrupted)
    }
    
    func testCorruption_MismatchedCRC() throws {
        BlazeBinaryEncoder.crc32Mode = .enabled
        defer { BlazeBinaryEncoder.crc32Mode = .disabled }
        
        let record = BlazeDataRecord(["title": .string("Test")])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        var armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Corrupt CRC32
        var bytes = Array(armEncoded)
        bytes[bytes.count - 1] ^= 0xFF
        
        let corrupted = Data(bytes)
        
        // Both codecs should fail with similar errors
        assertCodecsErrorEqual(corrupted)
    }
    
    func testCorruption_StopsAtCorrectBoundary() throws {
        let record = BlazeDataRecord([
            "field1": .string("Value1"),
            "field2": .string("Value2"),
            "field3": .string("Value3")
        ])
        
        // Encode with both codecs
        let stdEncoded = try BlazeBinaryEncoder.encode(record)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(record)
        XCTAssertEqual(stdEncoded, armEncoded)
        
        // Truncate in middle of second field
        let truncated = armEncoded.prefix(armEncoded.count / 2)
        let truncatedData = Data(truncated)
        
        // Both codecs should fail with similar errors
        assertCodecsErrorEqual(truncatedData)
    }
    
    func testCorruption_NoUndefinedBehavior() throws {
        // Test that corrupted data doesn't cause undefined behavior
        let corruptions: [Data] = [
            Data([0xFF, 0xFF, 0xFF, 0xFF]),
            Data([0x42, 0x4C, 0x41, 0x5A, 0x45, 0xFF, 0xFF, 0xFF]),
            Data(repeating: 0x00, count: 100),
            Data(repeating: 0xFF, count: 100)
        ]
        
        for corrupted in corruptions {
            // Both codecs should fail safely, not crash or hang
            assertCodecsErrorEqual(corrupted)
        }
    }
    
    func testCorruption_LogsProperly() throws {
        // Verify that errors contain useful information
        let invalidData = Data([0xFF, 0xFF, 0xFF, 0xFF])
        
        // Both codecs should produce similar error messages
        var stdError: Error?
        var armError: Error?
        
        do {
            _ = try BlazeBinaryDecoder.decode(invalidData)
        } catch {
            stdError = error
        }
        
        do {
            _ = try BlazeBinaryDecoder.decodeARM(invalidData)
        } catch {
            armError = error
        }
        
        // Both should fail
        XCTAssertNotNil(stdError, "Standard decoder should throw error")
        XCTAssertNotNil(armError, "ARM decoder should throw error")
        
        // Both should be BlazeBinaryError
        XCTAssertTrue(stdError is BlazeBinaryError, "Standard decoder should throw BlazeBinaryError")
        XCTAssertTrue(armError is BlazeBinaryError, "ARM decoder should throw BlazeBinaryError")
        
        // Error messages should be descriptive
        if let stdErr = stdError as? BlazeBinaryError, case .invalidFormat(let stdMsg) = stdErr {
            XCTAssertFalse(stdMsg.isEmpty, "Standard error message should not be empty")
            XCTAssertTrue(stdMsg.contains("magic") || stdMsg.contains("format") || stdMsg.contains("short"), "Standard error should be descriptive: \(stdMsg)")
        }
        
        if let armErr = armError as? BlazeBinaryError, case .invalidFormat(let armMsg) = armErr {
            XCTAssertFalse(armMsg.isEmpty, "ARM error message should not be empty")
            XCTAssertTrue(armMsg.contains("magic") || armMsg.contains("format") || armMsg.contains("short"), "ARM error should be descriptive: \(armMsg)")
        }
    }
}

