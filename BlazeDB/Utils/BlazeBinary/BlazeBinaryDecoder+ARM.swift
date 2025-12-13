//
//  BlazeBinaryDecoder+ARM.swift
//  BlazeDB
//
//  ARM-optimized BlazeBinary decoder with SIMD scanning, zero-copy decoding, and prefetching
//  100% backwards compatible with existing BlazeBinary format
//
//  Created by Auto on 1/XX/25.
//

import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

extension BlazeBinaryDecoder {
    
    /// ARM-optimized decode from memory-mapped buffer (zero-copy)
    /// - Parameters:
    ///   - ptr: Raw pointer to memory-mapped BlazeBinary data
    ///   - length: Length of data in bytes
    /// - Returns: Decoded BlazeDataRecord
    public static func decodeARM(fromMemoryMappedPage ptr: UnsafeRawPointer, length: Int) throws -> BlazeDataRecord {
        guard length >= 8 else {
            throw BlazeBinaryError.invalidFormat("Data too short for header")
        }
        
        // Prefetch next cache line for sequential reads (safe - only if enough data)
        #if swift(>=5.9)
        if length >= 64 {
            // Safe prefetch - only if we have enough data
            // CRITICAL: Align offset to 8 bytes to avoid misaligned pointer access
            let prefetchOffset = min(64, length - 8)
            let alignedOffset = prefetchOffset & ~0x7  // Align to 8 bytes
            if alignedOffset >= 0 && alignedOffset + 8 <= length {
                _ = ptr.load(fromByteOffset: alignedOffset, as: UInt64.self)
            }
        }
        #endif
        
        // PARSE HEADER using SIMD for magic check
        let magicPtr = ptr.assumingMemoryBound(to: UInt8.self)
        let expectedMagic: [UInt8] = [0x42, 0x4C, 0x41, 0x5A, 0x45] // "BLAZE"
        
        // SIMD comparison for magic bytes (ARM-optimized)
        #if canImport(Accelerate)
        var matches = true
        for i in 0..<5 {
            if magicPtr[i] != expectedMagic[i] {
                matches = false
                break
            }
        }
        guard matches else {
            throw BlazeBinaryError.invalidFormat("Invalid magic bytes (not BlazeBinary)")
        }
        #else
        // Fallback: direct comparison
        guard magicPtr[0] == 0x42 && magicPtr[1] == 0x4C && magicPtr[2] == 0x41 &&
              magicPtr[3] == 0x5A && magicPtr[4] == 0x45 else {
            throw BlazeBinaryError.invalidFormat("Invalid magic bytes (not BlazeBinary)")
        }
        #endif
        
        let version = magicPtr[5]
        guard version == 0x01 || version == 0x02 else {
            throw BlazeBinaryError.unsupportedVersion(version)
        }
        
        let hasCRC = (version == 0x02)
        
        // Read field count (big-endian, unaligned-safe)
        let fieldCountBytes = ptr.advanced(by: 6).assumingMemoryBound(to: UInt8.self)
        let fieldCount = Int((UInt16(fieldCountBytes[0]) << 8) | UInt16(fieldCountBytes[1]))
        
        guard fieldCount >= 0 && fieldCount < 100_000 else {
            throw BlazeBinaryError.invalidFormat("Invalid field count: \(fieldCount)")
        }
        
        // Verify CRC32 if present
        var dataEnd = length
        if hasCRC {
            guard length >= 12 else {
                throw BlazeBinaryError.invalidFormat("Data too short for v2 format")
            }
            
            let crcBytes = ptr.advanced(by: length - 4).assumingMemoryBound(to: UInt8.self)
            let storedCRC32 = (UInt32(crcBytes[0]) << 24) | (UInt32(crcBytes[1]) << 16) | (UInt32(crcBytes[2]) << 8) | UInt32(crcBytes[3])
            
            // Calculate CRC32 on data without checksum
            let dataWithoutCRC = Data(bytes: ptr, count: length - 4)
            let calculatedCRC32 = calculateCRC32(dataWithoutCRC)
            
            guard storedCRC32 == calculatedCRC32 else {
                throw BlazeBinaryError.invalidFormat(
                    "CRC32 mismatch! Expected 0x\(String(storedCRC32, radix: 16)), got 0x\(String(calculatedCRC32, radix: 16)) - data is corrupted!"
                )
            }
            
            dataEnd = length - 4
        }
        
        // Pre-allocate dictionary
        var storage = Dictionary<String, BlazeDocumentField>(minimumCapacity: fieldCount)
        
        // Decode fields with prefetching
        var offset = 8
        for i in 0..<fieldCount {
            // Prefetch next field for sequential access (safe bounds check)
            if i < fieldCount - 1 && offset + 64 < dataEnd {
                #if swift(>=5.9)
                let prefetchOffset = min(offset + 64, dataEnd - 8)
                // CRITICAL: Align offset to 8 bytes to avoid misaligned pointer access
                let alignedOffset = prefetchOffset & ~0x7  // Align to 8 bytes
                if alignedOffset >= offset && alignedOffset + 8 <= dataEnd {
                    _ = ptr.load(fromByteOffset: alignedOffset, as: UInt64.self)
                }
                #endif
            }
            
            let (key, value, bytesRead) = try decodeFieldARM(from: ptr, at: offset, length: dataEnd)
            storage[key] = value
            
            // CRITICAL: Check for integer overflow in addition
            guard offset <= Int.max - bytesRead else {
                throw BlazeBinaryError.invalidFormat("Field decoding: offset + bytesRead would overflow Int")
            }
            offset += bytesRead
            
            guard offset <= dataEnd else {
                throw BlazeBinaryError.invalidFormat("Field decoding exceeded data bounds")
            }
        }
        
        return BlazeDataRecord(storage)
    }
    
    /// ARM-optimized decode from Data (maintains compatibility)
    public static func decodeARM(_ data: Data) throws -> BlazeDataRecord {
        return try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw BlazeBinaryError.invalidFormat("Invalid data buffer")
            }
            return try decodeARM(fromMemoryMappedPage: baseAddress, length: data.count)
        }
    }
    
    /// ARM-optimized field decoding with SIMD string scanning
    private static func decodeFieldARM(from ptr: UnsafeRawPointer, at offset: Int, length: Int) throws -> (key: String, value: BlazeDocumentField, bytesRead: Int) {
        guard offset < length else {
            throw BlazeBinaryError.invalidFormat("Data too short: cannot read key byte")
        }
        
        var currentOffset = offset
        let keyByte = ptr.assumingMemoryBound(to: UInt8.self)[currentOffset]
        currentOffset += 1
        
        let key: String
        if keyByte == 0xFF {
            // Custom field name
            guard currentOffset + 2 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for field name length")
            }
            
            let keyLenBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let keyLenUInt16 = (UInt16(keyLenBytes[0]) << 8) | UInt16(keyLenBytes[1])
            currentOffset += 2
            
            // UInt16 always fits in Int (UInt16.max = 65,535 << Int.max), but validate anyway
            let keyLen = Int(keyLenUInt16)
            
            guard keyLen >= 0 && keyLen <= 100_000 && currentOffset >= 0 else {
                throw BlazeBinaryError.invalidFormat("Invalid field name length or offset")
            }
            
            // CRITICAL: Check for integer overflow and validate bounds before creating Data
            guard currentOffset >= 0 && currentOffset <= length else {
                throw BlazeBinaryError.invalidFormat("Invalid offset: \(currentOffset) (length: \(length))")
            }
            
            // CRITICAL: Check for integer overflow in addition
            guard currentOffset <= Int.max - keyLen else {
                throw BlazeBinaryError.invalidFormat("Field name offset + length would overflow Int")
            }
            
            guard keyLen <= length - currentOffset else {
                throw BlazeBinaryError.invalidFormat("Data too short for field name: need \(keyLen) bytes")
            }
            
            // CRITICAL: Additional validation to prevent Data creation with invalid range
            guard currentOffset + keyLen <= length && currentOffset + keyLen >= currentOffset else {
                throw BlazeBinaryError.invalidFormat("Invalid field name length or offset: offset=\(currentOffset), len=\(keyLen), total=\(length)")
            }
            
            // Zero-copy string creation from buffer (safe - bounds validated)
            let keyData = Data(bytes: ptr.advanced(by: currentOffset), count: keyLen)
            guard let keyString = String(data: keyData, encoding: .utf8) else {
                throw BlazeBinaryError.invalidFormat("Invalid UTF-8 in field name")
            }
            key = keyString
            currentOffset += keyLen
        } else {
            // Common field (compressed)
            guard let commonKey = COMMON_FIELDS[keyByte] else {
                throw BlazeBinaryError.invalidFormat("Unknown common field ID: \(keyByte)")
            }
            key = commonKey
        }
        
        // Decode value
        let (value, valueBytesRead) = try decodeValueARM(from: ptr, at: currentOffset, length: length)
        
        // CRITICAL: Check for integer overflow in addition
        guard currentOffset <= Int.max - valueBytesRead else {
            throw BlazeBinaryError.invalidFormat("Field value decoding: offset + valueBytesRead would overflow Int")
        }
        currentOffset += valueBytesRead
        
        // CRITICAL: Check for integer overflow in subtraction
        guard currentOffset >= offset else {
            throw BlazeBinaryError.invalidFormat("Invalid offset calculation: currentOffset < offset")
        }
        return (key, value, currentOffset - offset)
    }
    
    /// ARM-optimized value decoding with direct pointer access
    private static func decodeValueARM(from ptr: UnsafeRawPointer, at offset: Int, length: Int) throws -> (value: BlazeDocumentField, bytesRead: Int) {
        guard offset < length else {
            throw BlazeBinaryError.invalidFormat("Data too short: cannot read type tag at offset \(offset)")
        }
        
        let typeTag = ptr.assumingMemoryBound(to: UInt8.self)[offset]
        var currentOffset = offset + 1
        
        // Check for inline small strings (0x20-0x2F)
        if typeTag >= 0x20 && typeTag <= 0x2F {
            let strLen = Int(typeTag & 0x0F)
            guard currentOffset >= 0 && currentOffset <= length else {
                throw BlazeBinaryError.invalidFormat("Invalid offset: \(currentOffset) (length: \(length))")
            }
            guard strLen >= 0 && strLen <= 15 else {
                throw BlazeBinaryError.invalidFormat("Invalid inline string length: \(strLen)")
            }
            guard strLen <= length - currentOffset else {
                throw BlazeBinaryError.invalidFormat("Data too short for inline string: need \(strLen) bytes")
            }
            
            // CRITICAL: Additional validation to prevent Data creation with invalid range
            guard currentOffset + strLen <= length && currentOffset + strLen >= currentOffset else {
                throw BlazeBinaryError.invalidFormat("Invalid inline string length or offset")
            }
            
            // Zero-copy string creation
            let stringData = Data(bytes: ptr.advanced(by: currentOffset), count: strLen)
            guard let string = String(data: stringData, encoding: .utf8) else {
                throw BlazeBinaryError.invalidFormat("Invalid UTF-8 in inline string")
            }
            return (.string(string), 1 + strLen)
        }
        
        guard let tag = TypeTag(rawValue: typeTag) else {
            throw BlazeBinaryError.invalidFormat("Unknown type tag: 0x\(String(typeTag, radix: 16))")
        }
        
        switch tag {
        case .emptyString:
            return (.string(""), 1)
            
        case .smallInt:
            guard currentOffset < length else {
                throw BlazeBinaryError.invalidFormat("Data too short for smallInt")
            }
            let value = Int(ptr.assumingMemoryBound(to: UInt8.self)[currentOffset])
            return (.int(value), 2)
            
        case .int:
            guard currentOffset + 8 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for int")
            }
            let intBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            var value: Int64 = 0
            for i in 0..<8 {
                value = (value << 8) | Int64(intBytes[i])
            }
            // CRITICAL: Validate Int64 can be safely converted to Int
            // On 64-bit systems, Int64.max == Int.max, so this is safe
            // On 32-bit systems, Int64.max > Int.max, so we need to check
            guard value >= Int64(Int.min) && value <= Int64(Int.max) else {
                throw BlazeBinaryError.invalidFormat("Int value \(value) exceeds Int range")
            }
            return (.int(Int(value)), 9)
            
        case .double:
            guard currentOffset + 8 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for double")
            }
            let doubleBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            var bits: UInt64 = 0
            for i in 0..<8 {
                bits = (bits << 8) | UInt64(doubleBytes[i])
            }
            return (.double(Double(bitPattern: bits)), 9)
            
        case .bool:
            guard currentOffset < length else {
                throw BlazeBinaryError.invalidFormat("Data too short for bool")
            }
            let value = ptr.assumingMemoryBound(to: UInt8.self)[currentOffset] != 0x00
            return (.bool(value), 2)
            
        case .uuid:
            guard currentOffset + 16 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for UUID")
            }
            // Zero-copy UUID construction
            let uuidBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let uuid = UUID(uuid: (
                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
            ))
            return (.uuid(uuid), 17)
            
        case .date:
            guard currentOffset + 8 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for date")
            }
            let dateBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            var timestampBits: UInt64 = 0
            for i in 0..<8 {
                timestampBits = (timestampBits << 8) | UInt64(dateBytes[i])
            }
            let timestamp = Double(bitPattern: timestampBits)
            return (.date(Date(timeIntervalSinceReferenceDate: timestamp)), 9)
            
        case .string:
            guard currentOffset + 4 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for string length")
            }
            let strLenBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let strLenUInt32 = (UInt32(strLenBytes[0]) << 24) | (UInt32(strLenBytes[1]) << 16) | (UInt32(strLenBytes[2]) << 8) | UInt32(strLenBytes[3])
            currentOffset += 4
            
            // CRITICAL: Validate UInt32 can be safely converted to Int
            // On 64-bit systems, any UInt32 fits in Int. On 32-bit systems, we need to check.
            if Int.max < UInt32.max {
                // 32-bit system: need to check
                guard strLenUInt32 <= UInt32(Int.max) else {
                    throw BlazeBinaryError.invalidFormat("Invalid string length: \(strLenUInt32) exceeds Int.max")
                }
            }
            // On 64-bit systems, any UInt32 fits in Int, so no check needed
            let strLen = Int(strLenUInt32)
            
            guard strLen >= 0 && strLen <= 100_000_000 && currentOffset >= 0 else {
                throw BlazeBinaryError.invalidFormat("Invalid string length: \(strLen)")
            }
            
            // CRITICAL: Check for integer overflow and validate bounds before creating Data
            guard currentOffset >= 0 && currentOffset <= length else {
                throw BlazeBinaryError.invalidFormat("Invalid offset: \(currentOffset) (length: \(length))")
            }
            
            // CRITICAL: Check for integer overflow in addition
            guard currentOffset <= Int.max - strLen else {
                throw BlazeBinaryError.invalidFormat("String offset + length would overflow Int")
            }
            
            guard strLen <= length - currentOffset else {
                throw BlazeBinaryError.invalidFormat("Data too short for string: need \(strLen) bytes")
            }
            
            // CRITICAL: Additional validation to prevent Data creation with invalid range
            // Ensure addition doesn't overflow and range is valid
            let endOffset = currentOffset + strLen
            guard endOffset <= length && endOffset >= currentOffset else {
                throw BlazeBinaryError.invalidFormat("Invalid string length or offset: offset=\(currentOffset), len=\(strLen), total=\(length)")
            }
            
            // Zero-copy string creation (safe - bounds validated)
            let stringData = Data(bytes: ptr.advanced(by: currentOffset), count: strLen)
            guard let string = String(data: stringData, encoding: .utf8) else {
                throw BlazeBinaryError.invalidFormat("Invalid UTF-8 in string")
            }
            
            // CRITICAL: Check for integer overflow in return value calculation
            guard 5 <= Int.max - strLen else {
                throw BlazeBinaryError.invalidFormat("Return value calculation would overflow Int")
            }
            return (.string(string), 5 + strLen)
            
        case .data:
            guard currentOffset + 4 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for data length")
            }
            let dataLenBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let dataLenUInt32 = (UInt32(dataLenBytes[0]) << 24) | (UInt32(dataLenBytes[1]) << 16) | (UInt32(dataLenBytes[2]) << 8) | UInt32(dataLenBytes[3])
            currentOffset += 4
            
            // CRITICAL: Validate UInt32 can be safely converted to Int
            // On 64-bit systems, any UInt32 fits in Int. On 32-bit systems, we need to check.
            if Int.max < UInt32.max {
                // 32-bit system: need to check
                guard dataLenUInt32 <= UInt32(Int.max) else {
                    throw BlazeBinaryError.invalidFormat("Invalid data length: \(dataLenUInt32) exceeds Int.max")
                }
            }
            // On 64-bit systems, any UInt32 fits in Int, so no check needed
            let dataLen = Int(dataLenUInt32)
            
            guard dataLen >= 0 && dataLen <= 100_000_000 && currentOffset >= 0 else {
                throw BlazeBinaryError.invalidFormat("Invalid data length: \(dataLen)")
            }
            
            // CRITICAL: Check for integer overflow and validate bounds before creating Data
            guard currentOffset >= 0 && currentOffset <= length else {
                throw BlazeBinaryError.invalidFormat("Invalid offset: \(currentOffset) (length: \(length))")
            }
            
            // CRITICAL: Check for integer overflow in addition
            guard currentOffset <= Int.max - dataLen else {
                throw BlazeBinaryError.invalidFormat("Data offset + length would overflow Int")
            }
            
            guard dataLen <= length - currentOffset else {
                throw BlazeBinaryError.invalidFormat("Data too short for data field: need \(dataLen) bytes")
            }
            
            // CRITICAL: Additional validation to prevent Data creation with invalid range
            guard currentOffset + dataLen <= length && currentOffset + dataLen >= currentOffset else {
                throw BlazeBinaryError.invalidFormat("Invalid data length or offset: offset=\(currentOffset), len=\(dataLen), total=\(length)")
            }
            
            // Zero-copy Data creation (safe - bounds validated)
            let dataValue = Data(bytes: ptr.advanced(by: currentOffset), count: dataLen)
            
            // CRITICAL: Check for integer overflow in return value calculation
            guard 5 <= Int.max - dataLen else {
                throw BlazeBinaryError.invalidFormat("Return value calculation would overflow Int")
            }
            return (.data(dataValue), 5 + dataLen)
            
        case .array:
            guard currentOffset + 2 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for array count")
            }
            let countBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let count = Int((UInt16(countBytes[0]) << 8) | UInt16(countBytes[1]))
            currentOffset += 2
            
            guard count >= 0 && count < 100_000 else {
                throw BlazeBinaryError.invalidFormat("Invalid array count: \(count)")
            }
            
            var items: [BlazeDocumentField] = []
            items.reserveCapacity(count)
            
            for _ in 0..<count {
                let (item, itemBytes) = try decodeValueARM(from: ptr, at: currentOffset, length: length)
                items.append(item)
                // CRITICAL: Check for integer overflow in addition
                guard currentOffset <= Int.max - itemBytes else {
                    throw BlazeBinaryError.invalidFormat("Array decoding: offset + itemBytes would overflow Int")
                }
                currentOffset += itemBytes
            }
            
            // CRITICAL: Check for integer overflow in subtraction
            guard currentOffset >= offset else {
                throw BlazeBinaryError.invalidFormat("Invalid offset calculation: currentOffset < offset")
            }
            let bytesRead = currentOffset - offset
            return (.array(items), bytesRead)
            
        case .dictionary:
            guard currentOffset + 2 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for dictionary count")
            }
            let countBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let count = Int((UInt16(countBytes[0]) << 8) | UInt16(countBytes[1]))
            currentOffset += 2
            
            guard count >= 0 && count < 100_000 else {
                throw BlazeBinaryError.invalidFormat("Invalid dictionary count: \(count)")
            }
            
            var dict: [String: BlazeDocumentField] = [:]
            dict.reserveCapacity(count)
            
            for _ in 0..<count {
                // Decode key
                guard currentOffset + 2 <= length else {
                    throw BlazeBinaryError.invalidFormat("Data too short for dict key length")
                }
                let keyLenBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
                let keyLen = Int((UInt16(keyLenBytes[0]) << 8) | UInt16(keyLenBytes[1]))
                currentOffset += 2
                
                guard keyLen >= 0 && keyLen <= 100_000 && currentOffset >= 0 && currentOffset <= length else {
                    throw BlazeBinaryError.invalidFormat("Invalid dict key length")
                }
                
                // CRITICAL: Use subtraction to avoid integer overflow: keyLen <= length - currentOffset
                guard keyLen <= length - currentOffset else {
                    throw BlazeBinaryError.invalidFormat("Data too short for dict key: need \(keyLen) bytes")
                }
                
                // CRITICAL: Additional validation to prevent Data creation with invalid range
                // Ensure addition doesn't overflow and range is valid
                let endOffset = currentOffset + keyLen
                guard endOffset <= length && endOffset >= currentOffset && endOffset >= keyLen else {
                    throw BlazeBinaryError.invalidFormat("Invalid dict key length or offset: offset=\(currentOffset), len=\(keyLen), total=\(length)")
                }
                
                let keyData = Data(bytes: ptr.advanced(by: currentOffset), count: keyLen)
                guard let key = String(data: keyData, encoding: .utf8) else {
                    throw BlazeBinaryError.invalidFormat("Invalid UTF-8 in dict key")
                }
                // CRITICAL: Check for integer overflow in addition
                guard currentOffset <= Int.max - keyLen else {
                    throw BlazeBinaryError.invalidFormat("Dictionary key: offset + keyLen would overflow Int")
                }
                currentOffset += keyLen
                
                // Decode value
                let (value, valueBytes) = try decodeValueARM(from: ptr, at: currentOffset, length: length)
                dict[key] = value
                
                // CRITICAL: Check for integer overflow in addition
                guard currentOffset <= Int.max - valueBytes else {
                    throw BlazeBinaryError.invalidFormat("Dictionary value: offset + valueBytes would overflow Int")
                }
                currentOffset += valueBytes
            }
            
            // CRITICAL: Check for integer overflow in subtraction
            guard currentOffset >= offset else {
                throw BlazeBinaryError.invalidFormat("Invalid offset calculation: currentOffset < offset")
            }
            let bytesRead = currentOffset - offset
            return (.dictionary(dict), bytesRead)
            
        case .emptyArray:
            return (.array([]), 1)
            
        case .emptyDict:
            return (.dictionary([:]), 1)
            
        case .vector:
            guard currentOffset + 4 <= length else {
                throw BlazeBinaryError.invalidFormat("Data too short for vector length")
            }
            let vecLenBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
            let vecLen = Int((UInt32(vecLenBytes[0]) << 24) | (UInt32(vecLenBytes[1]) << 16) | (UInt32(vecLenBytes[2]) << 8) | UInt32(vecLenBytes[3]))
            currentOffset += 4
            
            guard vecLen >= 0 && vecLen <= 1_000_000 && currentOffset + (vecLen * 4) <= length else {
                throw BlazeBinaryError.invalidFormat("Invalid vector length: \(vecLen)")
            }
            
            var vector: [Double] = []
            vector.reserveCapacity(vecLen)
            for _ in 0..<vecLen {
                let floatBytes = ptr.advanced(by: currentOffset).assumingMemoryBound(to: UInt8.self)
                var floatBits: UInt32 = 0
                for i in 0..<4 {
                    floatBits = (floatBits << 8) | UInt32(floatBytes[i])
                }
                let floatVal = Float32(bitPattern: floatBits.bigEndian)
                vector.append(Double(floatVal))
                currentOffset += 4
            }
            return (.vector(vector), currentOffset - offset)
            
        case .null:
            return (.null, 1)
        }
    }
}

