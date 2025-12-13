//
//  BlazeBinaryDecoder+Lazy.swift
//  BlazeDB
//
//  BlazeBinary v3 decoder with field table support for lazy decoding
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension BlazeBinaryDecoder {
    
    /// Decode BlazeBinary v3 format with field table
    ///
    /// Format:
    /// - v3 (0x03): [BLAZE][0x03][fieldCount][fieldTableSize][fieldTable][fields...][CRC32]
    ///
    /// - Parameter data: BlazeBinary v3 encoded data
    /// - Returns: Decoded BlazeDataRecord and optional FieldTable
    /// - Throws: If data is invalid or corrupted
    public static func decodeWithFieldTable(_ inputData: Data) throws -> (record: BlazeDataRecord, fieldTable: FieldTable?) {
        // Convert to Data if it's a Data.SubSequence (avoids crashes)
        // This ensures we have a proper Data instance, not a subsequence
        let data = Data(inputData)
        
        guard data.count >= 8 else {
            throw BlazeBinaryError.invalidFormat("Data too short for header")
        }
        
        // Read magic bytes directly from the buffer to avoid any subsequence issues
        let magicBytes = data.prefix(5)
        let magic = String(data: magicBytes, encoding: .utf8) ?? ""
        guard magic == "BLAZE" else {
            throw BlazeBinaryError.invalidFormat("Invalid magic bytes")
        }
        
        let version = data[5]
        guard version == 0x03 else {
            // Not v3 format, fall back to standard decode
            let record = try decode(data)
            return (record, nil)
        }
        
        _ = true  // v3 always has CRC
        
        // Verify CRC32
        guard data.count >= 12 else {
            throw BlazeBinaryError.invalidFormat("Data too short for v3 format")
        }
        
        let storedCRC32 = try readUInt32(from: data, at: data.count - 4)
        let dataWithoutCRC = data.prefix(data.count - 4)
        let calculatedCRC32 = calculateCRC32(dataWithoutCRC)
        
        guard storedCRC32 == calculatedCRC32 else {
            throw BlazeBinaryError.invalidFormat("CRC32 mismatch - data corrupted")
        }
        
        var offset = 6  // After version byte
        
        // Read field count
        let fieldCount = Int(try readUInt16(from: data, at: offset))
        offset += 2
        
        // Read field table size
        let fieldTableSize = Int(try readUInt16(from: data, at: offset))
        offset += 2
        
        // Read field table
        let (fieldTable, consumed) = try FieldTable.decode(from: data, startingAt: offset)
        offset += consumed
        
        guard consumed == fieldTableSize else {
            throw BlazeBinaryError.invalidFormat("Field table size mismatch")
        }
        
        // Decode fields (can use lazy decoding with field table)
        var storage = Dictionary<String, BlazeDocumentField>(minimumCapacity: fieldCount)
        
        for _ in 0..<fieldCount {
            let (key, value, bytesRead) = try decodeField(from: data, at: offset)
            storage[key] = value
            offset += bytesRead
        }
        
        BlazeLogger.trace("BlazeBinary v3 decoded: \(storage.count) fields with field table")
        return (BlazeDataRecord(storage), fieldTable)
    }
    
    /// Decode a single field using field table (lazy decoding)
    ///
    /// - Parameters:
    ///   - data: Full encoded data
    ///   - fieldTable: Field table with offsets
    ///   - fieldName: Name of field to decode
    /// - Returns: Decoded field value
    public static func decodeFieldLazy(data: Data, fieldTable: FieldTable, fieldName: String) throws -> BlazeDocumentField? {
        guard let fieldInfo = fieldTable.fields[fieldName] else {
            return nil
        }
        
        // Extract field data using offset and length
        let fieldStart = fieldInfo.offset
        let fieldEnd = fieldStart + fieldInfo.length
        
        guard fieldEnd <= data.count else {
            throw BlazeBinaryError.invalidFormat("Field offset/length out of bounds")
        }
        
        // Decode just this field
        // Note: This is simplified - in production would properly parse the field encoding
        let fieldData = data.subdata(in: fieldStart..<fieldEnd)
        
        // Try to decode as a complete field (key + value)
        // For proper implementation, would need to parse BlazeBinary field format
        do {
            let (key, value, _) = try decodeField(from: fieldData, at: 0)
            if key == fieldName {
                return value
            }
        } catch {
            // Fall back to full decode
        }
        
        // Fallback: decode full record and extract field
        let fullRecord = try decode(data)
        return fullRecord.storage[fieldName]
    }
}

