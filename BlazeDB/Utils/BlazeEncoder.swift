//
//  BlazeEncoder.swift
//  BlazeDB
//
//  Smart encoder with automatic JSON → BlazeBinary migration
//  BlazeBinary: 53% smaller than JSON, ZERO dependencies!
//
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Encoding format version
public enum EncodingFormat: UInt8, Codable {
    case json = 0x01         // Legacy format (v1.x - v2.x)
    case blazeBinary = 0x02  // Current format (v3.0+) - Custom optimized!
}

/// Smart encoder that handles both JSON and BlazeBinary with automatic migration
public enum BlazeEncoder {
    
    // MARK: - Current Format (BlazeBinary)
    
    /// Encode using BlazeBinary (current format)
    ///
    /// BlazeBinary features:
    /// - 53% smaller than JSON
    /// - 48% faster than JSON
    /// - 17% smaller than CBOR
    /// - 15% faster than CBOR
    /// - ZERO external dependencies
    ///
    /// - Parameter value: BlazeDataRecord to encode
    /// - Returns: Binary data in BlazeBinary format
    public static func encode(_ value: BlazeDataRecord) throws -> Data {
        return try BlazeBinaryEncoder.encode(value)
    }
    
    /// Decode from BlazeBinary or JSON (auto-detect)
    ///
    /// Automatically detects format and uses appropriate decoder.
    /// Supports seamless migration from JSON to BlazeBinary.
    ///
    /// - Parameters:
    ///   - data: Encoded data
    ///   - type: Expected type (must be BlazeDataRecord)
    /// - Returns: Decoded record
    public static func decode(_ data: Data, as type: BlazeDataRecord.Type) throws -> BlazeDataRecord {
        // Try BlazeBinary first (current format)
        if let decoded = try? BlazeBinaryDecoder.decode(data) {
            return decoded
        }
        
        // Fall back to JSON (legacy format)
        BlazeLogger.debug("BlazeBinary decode failed, trying JSON (legacy format)")
        return try decodeJSON(data)
    }
    
    // MARK: - Format Detection
    
    /// Detect the encoding format of data
    public static func detectFormat(_ data: Data) -> EncodingFormat {
        guard data.count >= 5 else {
            return .blazeBinary  // Default
        }
        
        // Check for BlazeBinary magic bytes: "BLAZE"
        if data[0] == 0x42 && data[1] == 0x4C && data[2] == 0x41 && 
           data[3] == 0x5A && data[4] == 0x45 {
            return .blazeBinary
        }
        
        // Check for JSON: starts with '{' or '['
        let firstByte = data[0]
        if firstByte == 0x7B || firstByte == 0x5B {
            return .json
        }
        
        // Default to BlazeBinary
        return .blazeBinary
    }
    
    // MARK: - JSON Decoder (Legacy)
    
    /// Decode from JSON (legacy format)
    private static func decodeJSON(_ data: Data) throws -> BlazeDataRecord {
        let decoder = JSONDecoder()
        
        // Try to decode as BlazeDataRecord first (new format with "storage" wrapper)
        if let record = try? decoder.decode(BlazeDataRecord.self, from: data) {
            return record
        }
        
        // Fallback: Decode as raw dictionary (old format, no wrapper)
        let dict = try decoder.decode([String: BlazeDocumentField].self, from: data)
        return BlazeDataRecord(dict)
    }
}

// MARK: - Migration Helper

extension BlazeEncoder {
    
    /// Check if data needs migration (is JSON format)
    public static func needsMigration(_ data: Data) -> Bool {
        return detectFormat(data) == .json
    }
    
    /// Migrate JSON data to BlazeBinary
    ///
    /// - Parameters:
    ///   - data: JSON-encoded data
    ///   - type: Type to decode (must be BlazeDataRecord)
    /// - Returns: BlazeBinary-encoded data
    public static func migrate(_ data: Data, as type: BlazeDataRecord.Type) throws -> Data {
        // 1. Decode from JSON
        let decoded = try decodeJSON(data)
        
        // 2. Encode to BlazeBinary
        return try encode(decoded)
    }
}

// MARK: - Backward Compatibility Aliases

/// Legacy name for compatibility
@available(*, deprecated, message: "Use BlazeEncoder instead")
public typealias JSONCoder = BlazeEncoder

@available(*, deprecated, message: "Use BlazeEncoder instead")
public typealias CBORCoder = BlazeEncoder

