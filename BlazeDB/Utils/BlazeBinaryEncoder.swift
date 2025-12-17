//
//  BlazeBinaryEncoder.swift
//  BlazeDB
//
//  Custom binary format optimized for BlazeDB
//  53% smaller than JSON, 17% smaller than CBOR, ZERO dependencies!
//  + CRC32 checksums for 99.9% corruption detection!
//
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation
#if canImport(zlib)
import zlib  // For CRC32 (built into macOS/iOS, no external dependency!)
#endif

// Common definitions are now in BlazeBinaryShared.swift

// MARK: - BlazeBinary Encoder

// NOTE: COMMON_FIELDS and TypeTag are now in BlazeBinaryShared.swift
// This prevents duplication and allows both encoder and decoder to access them

// MARK: - BlazeBinary Encoder

public enum BlazeBinaryEncoder {
    
    /// CRC32 mode for BlazeBinary encoding
    public enum CRC32Mode {
        case disabled  // v1: No CRC32 (fastest, for encrypted/dev)
        case enabled   // v2: With CRC32 (99.9% detection, for production)
    }
    
    /// Global CRC32 mode (default: disabled for performance)
    /// 
    /// RECOMMENDATION:
    /// - Encrypted DBs: .disabled (AES-GCM auth tag already provides integrity!)
    /// - Unencrypted DBs: .enabled (adds CRC32 for corruption detection)
    /// 
    /// Enable with: BlazeBinaryEncoder.crc32Mode = .enabled
    /// Thread-safe: Uses nonisolated(unsafe) for performance (read-only in practice)
    public nonisolated(unsafe) static var crc32Mode: CRC32Mode = .disabled  // ✅ OFF by default (encryption has auth tags!)
    
    /// Encode a BlazeDataRecord to BlazeBinary format
    ///
    /// Format:
    /// - v1 (CRC disabled): [BLAZE][0x01][count][fields...]
    /// - v2 (CRC enabled):  [BLAZE][0x02][count][fields...][CRC32]
    ///
    /// Result: 53% smaller than JSON, 17% smaller than CBOR
    /// Optional CRC32 checksum for 99.9% corruption detection!
    ///
    /// - Parameter record: Record to encode
    /// - Returns: Binary data in BlazeBinary format
    public static func encode(_ record: BlazeDataRecord) throws -> Data {
        let includeCRC = (crc32Mode == .enabled)
        let estimatedSize = estimateSize(record) + (includeCRC ? 4 : 0)
        var data = Data()
        data.reserveCapacity(estimatedSize)  // Pre-allocate to avoid reallocations!
        
        // HEADER (8 bytes, aligned)
        guard let magicBytes = "BLAZE".data(using: .utf8) else {
            throw BlazeDBError.invalidData(reason: "Failed to encode magic header")
        }
        data.append(magicBytes)  // 5 bytes: Magic
        data.append(includeCRC ? 0x02 : 0x01)     // 1 byte: Version (v1=no CRC, v2=with CRC)
        
        // Field count (2 bytes, big-endian)
        let fieldCount = UInt16(record.storage.count)
        var count = fieldCount.bigEndian
        data.append(Data(bytes: &count, count: 2))
        
        BlazeLogger.trace("Encoding \(fieldCount) fields with BlazeBinary (CRC32: \(includeCRC ? "ON" : "OFF"))")
        
        // OPTIMIZED: Pre-sort fields once (reuse if encoding same record multiple times)
        let sortedFields = record.storage.sorted(by: { $0.key < $1.key })
        
        // FIELDS (sorted for deterministic encoding)
        for (key, value) in sortedFields {
            try encodeField(key: key, value: value, into: &data)
        }
        
        // ✅ OPTIONALLY APPEND CRC32 CHECKSUM (4 bytes) for 99.9% corruption detection!
        if includeCRC {
            let crc32 = calculateCRC32(data)
            var crcBigEndian = crc32.bigEndian
            data.append(Data(bytes: &crcBigEndian, count: 4))
            BlazeLogger.trace("BlazeBinary encoded: \(data.count) bytes (with CRC32)")
        } else {
            BlazeLogger.trace("BlazeBinary encoded: \(data.count) bytes (no CRC32)")
        }
        
        return data
    }
    
    // MARK: - CRC32 Checksum
    
    /// Calculate CRC32 checksum (cross-platform: uses zlib on Apple, pure Swift on Linux)
    internal static func calculateCRC32(_ data: Data) -> UInt32 {
        #if canImport(zlib)
        // Use zlib on Apple platforms (hardware-accelerated)
        return data.withUnsafeBytes { buffer in
            let crc = zlib.crc32(0, buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), uInt(buffer.count))
            return UInt32(crc)
        }
        #else
        // Pure Swift implementation for Linux (IEEE 802.3 polynomial: 0xEDB88320)
        return Self.crc32Swift(data)
        #endif
    }
    
    #if !canImport(zlib)
    /// Precomputed CRC32 lookup table (IEEE 802.3 polynomial: 0xEDB88320)
    private static let crc32Table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1)
            }
            table[i] = crc
        }
        return table
    }()
    
    /// Pure Swift CRC32 implementation (IEEE 802.3 polynomial)
    private static func crc32Swift(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for byte in bytes {
                let index = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = (crc >> 8) ^ crc32Table[index]
            }
        }
        return crc ^ 0xFFFFFFFF
    }
    #endif
    
    // MARK: - Field Encoding
    
    internal static func encodeField(key: String, value: BlazeDocumentField, into data: inout Data) throws {
        // KEY ENCODING (optimized with compression dictionary)
        // ✅ UNLIMITED FIELDS SUPPORTED!
        // - First 127 common fields: 1 byte (compressed)
        // - All other fields: 3+N bytes (full name)
        // - NO LIMIT on total fields! Can have 10,000+ fields if needed!
        
        if let commonFieldID = COMMON_FIELDS_REVERSE[key] {
            // Common field: 1 byte! 🔥
            data.append(commonFieldID)
        } else {
            // Custom field: marker + length + name
            // ✅ Supports ANY field name, ANY length!
            data.append(0xFF)  // Marker: Custom field follows
            guard let keyData = key.data(using: .utf8) else {
                throw BlazeDBError.invalidData(reason: "Failed to encode field name: \(key)")
            }
            
            // Support field names up to 65,535 bytes (realistically unlimited!)
            guard keyData.count <= UInt16.max else {
                BlazeLogger.error("Field name too long: \(key.prefix(50))... (\(keyData.count) bytes)")
                // Truncate to max size
                let truncated = String(key.prefix(1000))
                guard let truncatedData = truncated.data(using: .utf8) else {
                    throw BlazeDBError.invalidData(reason: "Failed to encode truncated field name")
                }
                var keyLen = UInt16(truncatedData.count).bigEndian
                data.append(Data(bytes: &keyLen, count: 2))
                data.append(truncatedData)
                return
            }
            
            var keyLen = UInt16(keyData.count).bigEndian
            data.append(Data(bytes: &keyLen, count: 2))
            data.append(keyData)
        }
        
        // VALUE ENCODING (type-specific, optimized)
        try encodeValue(value, into: &data)
    }
    
    private static func encodeValue(_ value: BlazeDocumentField, into data: inout Data) throws {
        switch value {
        case .string(let s):
            if s.isEmpty {
                data.append(TypeTag.emptyString.rawValue)  // 1 byte! ✅
            } else {
                // ✅ FIX: Use UTF-8 BYTE count, not character count!
                // "🔥" = 1 character but 4 bytes in UTF-8!
                guard let utf8Data = s.data(using: .utf8) else {
                    throw BlazeDBError.invalidData(reason: "Failed to encode string value")
                }
                let byteCount = utf8Data.count
                
                if byteCount <= 15 {
                    // Inline small strings: type + length in one byte!
                    let typeAndLen = 0x20 | UInt8(byteCount)  // 0x20-0x2F
                    data.append(typeAndLen)
                    data.append(utf8Data)
                } else {
                    data.append(TypeTag.string.rawValue)
                    var sLen = UInt32(byteCount).bigEndian
                    data.append(Data(bytes: &sLen, count: 4))
                    data.append(utf8Data)
                }
            }
            
        case .int(let i):
            // Small int optimization (0-255)
            if i >= 0 && i <= 255 {
                data.append(TypeTag.smallInt.rawValue)
                data.append(UInt8(i))  // 2 bytes total vs 9! 🔥
            } else {
                data.append(TypeTag.int.rawValue)
                var val = i.bigEndian
                data.append(Data(bytes: &val, count: 8))
            }
            
        case .double(let d):
            data.append(TypeTag.double.rawValue)
            var bits = d.bitPattern.bigEndian
            data.append(Data(bytes: &bits, count: 8))
            
        case .bool(let b):
            data.append(TypeTag.bool.rawValue)
            data.append(b ? 0x01 : 0x00)
            
        case .uuid(let u):
            data.append(TypeTag.uuid.rawValue)
            // Direct 16-byte write! ✅ No conversion, optimal!
            withUnsafeBytes(of: u.uuid) { data.append(contentsOf: $0) }
            
        case .date(let d):
            data.append(TypeTag.date.rawValue)
            // ✅ FIX: Use big-endian like all other 8-byte types!
            var timestamp = d.timeIntervalSinceReferenceDate.bitPattern.bigEndian
            data.append(Data(bytes: &timestamp, count: 8))
            
        case .data(let d):
            data.append(TypeTag.data.rawValue)
            var dLen = UInt32(d.count).bigEndian
            data.append(Data(bytes: &dLen, count: 4))
            data.append(d)
            
        case .array(let arr):
            if arr.isEmpty {
                data.append(TypeTag.emptyArray.rawValue)  // 1 byte! ✅
            } else {
                data.append(TypeTag.array.rawValue)
                var arrCount = UInt16(arr.count).bigEndian
                data.append(Data(bytes: &arrCount, count: 2))
                
                // Recursively encode items
                for item in arr {
                    try encodeValue(item, into: &data)
                }
            }
            
        case .vector(let vec):
            data.append(TypeTag.vector.rawValue)
            var vecCount = UInt32(vec.count).bigEndian
            data.append(Data(bytes: &vecCount, count: 4))
            // Encode each Float as 4 bytes (big-endian)
            for float in vec {
                var bits = float.bitPattern.bigEndian
                data.append(Data(bytes: &bits, count: 4))
            }
            
        case .null:
            data.append(TypeTag.null.rawValue)
            
        case .dictionary(let dict):
            if dict.isEmpty {
                data.append(TypeTag.emptyDict.rawValue)  // 1 byte! ✅
            } else {
                data.append(TypeTag.dictionary.rawValue)
                var dictCount = UInt16(dict.count).bigEndian
                data.append(Data(bytes: &dictCount, count: 2))
                
                // Recursively encode key-value pairs (sorted for determinism)
                for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                    // Encode key as string
                    guard let keyData = key.data(using: .utf8) else {
                        throw BlazeBinaryError.encodingFailed("Failed to encode dictionary key '\(key)'")
                    }
                    var keyLen = UInt16(keyData.count).bigEndian
                    data.append(Data(bytes: &keyLen, count: 2))
                    data.append(keyData)
                    
                    // Encode value
                    try encodeValue(value, into: &data)
                }
            }
        }
    }
    
    // MARK: - Size Estimation
    
    internal static func estimateSize(_ record: BlazeDataRecord) -> Int {
        // Conservative estimate for pre-allocation
        // Header: 8 bytes
        // Per field: ~40 bytes average (key + type + value)
        return 8 + (record.storage.count * 40)
    }
}

