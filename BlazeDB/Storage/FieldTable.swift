//
//  FieldTable.swift
//  BlazeDB
//
//  Field table for lazy decoding support
//  Maps field names to (offset, length, type) for partial decoding
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Field metadata for lazy decoding
public struct FieldInfo {
    public let offset: Int      // Byte offset in encoded data
    public let length: Int       // Byte length
    public let typeTag: UInt8    // BlazeBinary type tag
    
    public init(offset: Int, length: Int, typeTag: UInt8) {
        self.offset = offset
        self.length = length
        self.typeTag = typeTag
    }
}

/// Field table for lazy decoding
/// Maps field names to their location in encoded data
public struct FieldTable {
    public let fields: [String: FieldInfo]
    
    public init(fields: [String: FieldInfo]) {
        self.fields = fields
    }
    
    /// Encode field table to binary format
    /// Format: [count: UInt16][fieldName: String][offset: UInt32][length: UInt32][typeTag: UInt8]...
    public func encode() throws -> Data {
        var data = Data()
        let count = UInt16(fields.count)
        var countBE = count.bigEndian
        data.append(Data(bytes: &countBE, count: 2))
        
        for (name, info) in fields.sorted(by: { $0.key < $1.key }) {
            // Field name
            guard let nameData = name.data(using: .utf8) else {
                throw BlazeBinaryError.invalidFormat("Failed to encode field name as UTF-8")
            }
            var nameLen = UInt16(nameData.count).bigEndian
            data.append(Data(bytes: &nameLen, count: 2))
            data.append(nameData)
            
            // Offset (UInt32)
            var offsetBE = UInt32(info.offset).bigEndian
            data.append(Data(bytes: &offsetBE, count: 4))
            
            // Length (UInt32)
            var lengthBE = UInt32(info.length).bigEndian
            data.append(Data(bytes: &lengthBE, count: 4))
            
            // Type tag (UInt8)
            data.append(info.typeTag)
        }
        
        return data
    }
    
    /// Decode field table from binary format
    public static func decode(from data: Data, startingAt offset: Int) throws -> (table: FieldTable, consumed: Int) {
        var pos = offset
        
        // Read count (use subdata to ensure alignment)
        guard pos + 2 <= data.count else {
            throw BlazeBinaryError.invalidFormat("Field table: data too short for count")
        }
        let countBytes = data.subdata(in: pos..<pos + 2)
        let count = UInt16(bigEndian: countBytes.withUnsafeBytes { $0.load(as: UInt16.self) })
        pos += 2
        
        var fields: [String: FieldInfo] = [:]
        
        for _ in 0..<count {
            // Read field name length (use subdata to ensure alignment)
            guard pos + 2 <= data.count else {
                throw BlazeBinaryError.invalidFormat("Field table: data too short for name length")
            }
            let nameLenBytes = data.subdata(in: pos..<pos + 2)
            let nameLen = UInt16(bigEndian: nameLenBytes.withUnsafeBytes { $0.load(as: UInt16.self) })
            pos += 2
            
            guard pos + Int(nameLen) <= data.count else {
                throw BlazeBinaryError.invalidFormat("Field table: data too short for name")
            }
            let nameData = data.subdata(in: pos..<pos + Int(nameLen))
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw BlazeBinaryError.invalidFormat("Field table: invalid UTF-8 in name")
            }
            pos += Int(nameLen)
            
            // Read offset (use subdata to ensure alignment)
            guard pos + 4 <= data.count else {
                throw BlazeBinaryError.invalidFormat("Field table: data too short for offset")
            }
            let offsetBytes = data.subdata(in: pos..<pos + 4)
            let fieldOffset = UInt32(bigEndian: offsetBytes.withUnsafeBytes { $0.load(as: UInt32.self) })
            pos += 4
            
            // Read length (use subdata to ensure alignment)
            guard pos + 4 <= data.count else {
                throw BlazeBinaryError.invalidFormat("Field table: data too short for length")
            }
            let lengthBytes = data.subdata(in: pos..<pos + 4)
            let fieldLength = UInt32(bigEndian: lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self) })
            pos += 4
            
            // Read type tag
            guard pos < data.count else {
                throw BlazeBinaryError.invalidFormat("Field table: data too short for type tag")
            }
            let typeTag = data[pos]
            pos += 1
            
            fields[name] = FieldInfo(offset: Int(fieldOffset), length: Int(fieldLength), typeTag: typeTag)
        }
        
        return (FieldTable(fields: fields), pos - offset)
    }
}

