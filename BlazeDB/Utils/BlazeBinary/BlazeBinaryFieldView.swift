//
//  BlazeBinaryFieldView.swift
//  BlazeDB
//
//  Zero-copy field view for lazy decoding from memory-mapped buffers
//  ARM-optimized with direct pointer access
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Zero-copy view into a BlazeBinary field stored in a memory-mapped buffer
/// Fields are decoded lazily on first access
public struct BlazeBinaryFieldView {
    /// Raw pointer to the field data in the buffer
    private let basePointer: UnsafeRawPointer
    
    /// Type tag byte
    private let typeTag: UInt8
    
    /// Offset from basePointer where value data starts
    private let valueOffset: Int
    
    /// Total bytes consumed by this field
    private let totalBytes: Int
    
    /// Cached decoded value (lazy)
    private var _cachedValue: BlazeDocumentField?
    
    internal init(basePointer: UnsafeRawPointer, typeTag: UInt8, valueOffset: Int, totalBytes: Int) {
        self.basePointer = basePointer
        self.typeTag = typeTag
        self.valueOffset = valueOffset
        self.totalBytes = totalBytes
        self._cachedValue = nil
    }
    
    /// Decode the field value (lazy - only decodes on first access)
    public var value: BlazeDocumentField {
        mutating get {
            if let cached = _cachedValue {
                return cached
            }
            
            let decoded = decodeValue()
            _cachedValue = decoded
            return decoded
        }
    }
    
    /// Check if value has been decoded
    public var isDecoded: Bool {
        return _cachedValue != nil
    }
    
    /// Total bytes consumed by this field
    public var bytesConsumed: Int {
        return totalBytes
    }
    
    /// Decode the value from the buffer
    private func decodeValue() -> BlazeDocumentField {
        let valuePtr = basePointer.advanced(by: valueOffset)
        
        // Check for inline small strings (0x20-0x2F)
        if typeTag >= 0x20 && typeTag <= 0x2F {
            let length = Int(typeTag & 0x0F)
            let stringData = Data(bytes: valuePtr, count: length)
            return .string(String(data: stringData, encoding: .utf8) ?? "")
        }
        
        guard let tag = TypeTag(rawValue: typeTag) else {
            return .string("") // Fallback
        }
        
        switch tag {
        case .emptyString:
            return .string("")
            
        case .smallInt:
            return .int(Int(valuePtr.load(as: UInt8.self)))
            
        case .int:
            let intBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            var value: Int64 = 0
            for i in 0..<8 {
                value = (value << 8) | Int64(intBytes[i])
            }
            return .int(Int(value))
            
        case .double:
            let doubleBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            var bits: UInt64 = 0
            for i in 0..<8 {
                bits = (bits << 8) | UInt64(doubleBytes[i])
            }
            return .double(Double(bitPattern: bits))
            
        case .bool:
            return .bool(valuePtr.load(as: UInt8.self) != 0)
            
        case .uuid:
            let uuidBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            return .uuid(UUID(uuid: (
                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
            )))
            
        case .date:
            let dateBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            var timestampBits: UInt64 = 0
            for i in 0..<8 {
                timestampBits = (timestampBits << 8) | UInt64(dateBytes[i])
            }
            return .date(Date(timeIntervalSinceReferenceDate: Double(bitPattern: timestampBits)))
            
        case .string:
            let strLenBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            let length = Int((UInt32(strLenBytes[0]) << 24) | (UInt32(strLenBytes[1]) << 16) | (UInt32(strLenBytes[2]) << 8) | UInt32(strLenBytes[3]))
            let stringData = Data(bytes: valuePtr.advanced(by: 4), count: length)
            return .string(String(data: stringData, encoding: .utf8) ?? "")
            
        case .data:
            let dataLenBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            let length = Int((UInt32(dataLenBytes[0]) << 24) | (UInt32(dataLenBytes[1]) << 16) | (UInt32(dataLenBytes[2]) << 8) | UInt32(dataLenBytes[3]))
            return .data(Data(bytes: valuePtr.advanced(by: 4), count: length))
            
        case .array, .dictionary, .emptyArray, .emptyDict:
            // Complex types need full decoding - fallback to standard decode
            // This is a limitation of zero-copy views for nested structures
            return .string("") // Placeholder - would need full decode
            
        case .vector:
            // Vector decoding - read length and then float values
            let vecLenBytes = valuePtr.assumingMemoryBound(to: UInt8.self)
            let vecLength = Int((UInt32(vecLenBytes[0]) << 24) | (UInt32(vecLenBytes[1]) << 16) | (UInt32(vecLenBytes[2]) << 8) | UInt32(vecLenBytes[3]))
            var vectorValues: [Double] = []
            var offset = 4
            for _ in 0..<vecLength {
                let floatBytes = valuePtr.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                var bits: UInt32 = 0
                for i in 0..<4 {
                    bits = (bits << 8) | UInt32(floatBytes[i])
                }
                // Convert Float to Double
                vectorValues.append(Double(Float(bitPattern: bits)))
                offset += 4
            }
            return .vector(vectorValues)
            
        case .null:
            return .null
        }
    }
}

