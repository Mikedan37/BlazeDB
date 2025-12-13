//
//  LazyBlazeRecord.swift
//  BlazeDB
//
//  Lazy decoding record abstraction
//  Only decodes fields that are accessed
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Lazy record that only decodes fields on-demand
public final class LazyBlazeRecord {
    private let rawData: Data
    private let fieldTable: FieldTable?
    private var decodedFields: [String: BlazeDocumentField] = [:]
    private let lock = NSLock()
    private let recordId: UUID?
    
    /// Initialize with encoded data and optional field table
    public init(rawData: Data, fieldTable: FieldTable? = nil, recordId: UUID? = nil) {
        self.rawData = rawData
        self.fieldTable = fieldTable
        self.recordId = recordId
    }
    
    /// Get field value (lazy decode on-demand)
    public subscript(_ key: String) -> BlazeDocumentField? {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if already decoded
        if let decoded = decodedFields[key] {
            return decoded
        }
        
        // Decode on-demand
        if let field = decodeField(key) {
            decodedFields[key] = field
            return field
        }
        
        return nil
    }
    
    /// Get all fields (forces full decode)
    public func allFields() throws -> [String: BlazeDocumentField] {
        lock.lock()
        defer { lock.unlock() }
        
        // If we have a field table, decode all fields
        if let table = fieldTable {
            for fieldName in table.fields.keys {
                if decodedFields[fieldName] == nil {
                    if let field = decodeField(fieldName) {
                        decodedFields[fieldName] = field
                    }
                }
            }
        } else {
            // No field table, decode full record
            let fullRecord = try BlazeBinaryDecoder.decode(rawData)
            decodedFields = fullRecord.storage
        }
        
        return decodedFields
    }
    
    /// Convert to full BlazeDataRecord
    public func toRecord() throws -> BlazeDataRecord {
        var fields = try allFields()
        // Ensure ID is in storage if we have it
        if let id = recordId {
            fields["id"] = .uuid(id)
        }
        return BlazeDataRecord(fields)
    }
    
    /// Check if field is decoded
    public func isDecoded(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return decodedFields[key] != nil
    }
    
    /// Decode a single field
    private func decodeField(_ key: String) -> BlazeDocumentField? {
        guard let table = fieldTable,
              let info = table.fields[key] else {
            // No field table or field not in table, decode full record
            guard let fullRecord = try? BlazeBinaryDecoder.decode(rawData) else {
                return nil
            }
            return fullRecord.storage[key]
        }
        
        // Decode only this field using offset/length
        let fieldData = rawData.subdata(in: info.offset..<info.offset + info.length)
        
        // Decode the field value based on type tag
        // This is a simplified decoder - in production would use full BlazeBinaryDecoder
        return decodeFieldValue(data: fieldData, typeTag: info.typeTag, key: key)
    }
    
    /// Decode a single field value
    private func decodeFieldValue(data: Data, typeTag: UInt8, key: String) -> BlazeDocumentField? {
        // Simplified decoder - just decode the value portion
        // In production, would properly parse BlazeBinary field encoding
        do {
            // For now, try to decode as if it's a complete field encoding
            // This is a placeholder - proper implementation would parse the BlazeBinary format
            let tempRecord = try BlazeBinaryDecoder.decode(data)
            return tempRecord.storage[key]
        } catch {
            // Fallback: decode full record and extract field
            do {
                let fullRecord = try BlazeBinaryDecoder.decode(rawData)
                return fullRecord.storage[key]
            } catch {
                return nil
            }
        }
    }
}

