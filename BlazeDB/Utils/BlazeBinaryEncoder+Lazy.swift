//
//  BlazeBinaryEncoder+Lazy.swift
//  BlazeDB
//
//  BlazeBinary v3 format with field table for lazy decoding
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension BlazeBinaryEncoder {
    
    /// Encode with field table (v3 format) for lazy decoding support
    ///
    /// Format:
    /// - v3 (0x03): [BLAZE][0x03][fieldCount][fieldTable][fields...][CRC32]
    ///
    /// Field table format:
    /// - [count: UInt16][fieldName: String][offset: UInt32][length: UInt32][typeTag: UInt8]...
    ///
    /// - Parameter record: Record to encode
    /// - Returns: Binary data in BlazeBinary v3 format with field table
    public static func encodeWithFieldTable(_ record: BlazeDataRecord) throws -> Data {
        // v3 format always includes CRC32 for data integrity
        let includeCRC = true
        let estimatedSize = estimateSize(record) + 1000 // Extra space for field table
        var data = Data()
        data.reserveCapacity(estimatedSize)
        
        // HEADER (8 bytes)
        guard let magicData = "BLAZE".data(using: .utf8) else {
            throw BlazeBinaryError.invalidFormat("Failed to encode magic bytes as UTF-8")
        }
        data.append(magicData)  // 5 bytes: Magic
        data.append(0x03)  // 1 byte: Version v3 (with field table)
        
        // Field count (2 bytes, big-endian)
        let fieldCount = UInt16(record.storage.count)
        var count = fieldCount.bigEndian
        data.append(Data(bytes: &count, count: 2))
        
        BlazeLogger.trace("Encoding \(fieldCount) fields with BlazeBinary v3 (field table + CRC32)")
        
        // Encode fields first, tracking positions
        let fieldsStartOffset = data.count
        var fieldTableEntries: [String: FieldInfo] = [:]
        let sortedFields = record.storage.sorted(by: { $0.key < $1.key })
        
        // ENCODE FIELDS and track positions
        for (key, value) in sortedFields {
            let fieldStartOffset = data.count - fieldsStartOffset
            
            // Encode field
            try encodeField(key: key, value: value, into: &data)
            
            let fieldEndOffset = data.count - fieldsStartOffset
            let fieldLength = fieldEndOffset - fieldStartOffset
            
            // Determine type tag
            let typeTag: UInt8 = {
                switch value {
                case .string: return TypeTag.string.rawValue
                case .int: return TypeTag.int.rawValue
                case .double: return TypeTag.double.rawValue
                case .bool: return TypeTag.bool.rawValue
                case .uuid: return TypeTag.uuid.rawValue
                case .date: return TypeTag.date.rawValue
                case .data: return TypeTag.data.rawValue
                case .array: return TypeTag.array.rawValue
                case .dictionary: return TypeTag.dictionary.rawValue
                case .vector: return TypeTag.vector.rawValue
                case .null: return TypeTag.null.rawValue
                }
            }()
            
            fieldTableEntries[key] = FieldInfo(offset: fieldStartOffset, length: fieldLength, typeTag: typeTag)
        }
        
        // Build field table
        let fieldTable = FieldTable(fields: fieldTableEntries)
        let fieldTableData = try fieldTable.encode()
        let fieldTableSize = UInt16(fieldTableData.count)
        var fieldTableSizeBE = fieldTableSize.bigEndian
        
        // Insert field table after header (before fields)
        data.insert(contentsOf: fieldTableData, at: fieldsStartOffset)
        data.insert(contentsOf: Data(bytes: &fieldTableSizeBE, count: 2), at: fieldsStartOffset)
        
        // Adjust all field offsets (they're now after the field table)
        let adjustment = Int(fieldTableSize) + 2
        var adjustedEntries: [String: FieldInfo] = [:]
        for (key, info) in fieldTableEntries {
            adjustedEntries[key] = FieldInfo(offset: info.offset + adjustment, length: info.length, typeTag: info.typeTag)
        }
        
        // Rebuild field table with adjusted offsets
        let adjustedFieldTable = FieldTable(fields: adjustedEntries)
        let adjustedFieldTableData = try adjustedFieldTable.encode()
        let adjustedFieldTableSize = UInt16(adjustedFieldTableData.count)
        var adjustedFieldTableSizeBE = adjustedFieldTableSize.bigEndian
        
        // Replace field table with adjusted version
        let fieldTableStart = fieldsStartOffset + 2
        let oldFieldTableEnd = fieldTableStart + Int(fieldTableSize)
        
        // Validate range before replacement
        guard fieldTableStart < data.count && oldFieldTableEnd <= data.count else {
            throw NSError(domain: "BlazeBinaryEncoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid field table range: start=\(fieldTableStart), end=\(oldFieldTableEnd), data.count=\(data.count)"])
        }
        
        // Replace size field first (2 bytes at fieldsStartOffset)
        data.replaceSubrange(fieldsStartOffset..<fieldTableStart, with: Data(bytes: &adjustedFieldTableSizeBE, count: 2))
        
        // Replace field table data - handle size differences
        if adjustedFieldTableData.count == Int(fieldTableSize) {
            // Same size - simple replacement
            data.replaceSubrange(fieldTableStart..<oldFieldTableEnd, with: adjustedFieldTableData)
        } else {
            // Different size - remove old, insert new
            data.removeSubrange(fieldTableStart..<oldFieldTableEnd)
            data.insert(contentsOf: adjustedFieldTableData, at: fieldTableStart)
            
            // Adjust all field offsets again (they shifted by the size difference)
            let sizeDifference = adjustedFieldTableData.count - Int(fieldTableSize)
            var finalEntries: [String: FieldInfo] = [:]
            for (key, info) in adjustedEntries {
                finalEntries[key] = FieldInfo(offset: info.offset + sizeDifference, length: info.length, typeTag: info.typeTag)
            }
            let finalFieldTable = FieldTable(fields: finalEntries)
            let finalFieldTableData = try finalFieldTable.encode()
            
            // Replace with final field table (should be same size as adjusted now)
            let newFieldTableEnd = fieldTableStart + adjustedFieldTableData.count
            guard newFieldTableEnd <= data.count else {
                throw NSError(domain: "BlazeBinaryEncoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid final field table range"])
            }
            data.replaceSubrange(fieldTableStart..<newFieldTableEnd, with: finalFieldTableData)
        }
        
        // Append CRC32 if enabled
        if includeCRC {
            let crc32 = calculateCRC32(data)
            var crcBigEndian = crc32.bigEndian
            data.append(Data(bytes: &crcBigEndian, count: 4))
        }
        
        BlazeLogger.trace("BlazeBinary v3 encoded: \(data.count) bytes (with field table)")
        return data
    }
}

