//
//  BlazeRecordDecoder.swift
//  BlazeDB
//
//  Custom Decoder that converts BlazeDataRecord directly to Codable types
//  Eliminates JSON intermediate step for better performance!
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Custom Decoder that reads directly from BlazeDataRecord.storage
/// This eliminates JSON serialization overhead when converting BlazeDataRecord to Codable types
internal class BlazeRecordDecoder: Decoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    private let storage: [String: BlazeDocumentField]
    
    init(storage: [String: BlazeDocumentField], codingPath: [CodingKey] = []) {
        self.storage = storage
        self.codingPath = codingPath
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        let container = BlazeRecordKeyedDecodingContainer<Key>(
            decoder: self,
            storage: storage,
            codingPath: codingPath
        )
        return KeyedDecodingContainer(container)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Single value containers not supported for BlazeDataRecord"
            )
        )
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed containers not supported for BlazeDataRecord"
            )
        )
    }
}

/// Keyed decoding container for BlazeDataRecord
private struct BlazeRecordKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey]
    var allKeys: [Key] {
        return storage.keys.compactMap { Key(stringValue: $0) }
    }
    
    private let decoder: BlazeRecordDecoder
    private let storage: [String: BlazeDocumentField]
    
    init(decoder: BlazeRecordDecoder, storage: [String: BlazeDocumentField], codingPath: [CodingKey]) {
        self.decoder = decoder
        self.storage = storage
        self.codingPath = codingPath
    }
    
    func contains(_ key: Key) -> Bool {
        return storage[key.stringValue] != nil
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard let field = storage[key.stringValue] else {
            return true  // Missing key is nil
        }
        if case .null = field {
            return true
        }
        return false
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        guard let field = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        switch field {
        case .bool(let value):
            return value
        case .int(let value):
            // Handle bool stored as int (0/1)
            return value != 0
        default:
            throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Bool, got \(field)"))
        }
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        guard let field = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        switch field {
        case .string(let value):
            return value
        default:
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected String, got \(field)"))
        }
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        guard let field = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        switch field {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Double, got \(field)"))
        }
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return Float(try decode(Double.self, forKey: key))
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        guard let field = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        switch field {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int, got \(field)"))
        }
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return Int8(try decode(Int.self, forKey: key))
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return Int16(try decode(Int.self, forKey: key))
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return Int32(try decode(Int.self, forKey: key))
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try decode(Int.self, forKey: key)
        return Int64(value)  // Safe: Int64 can represent all Int values
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        let value = try decode(Int.self, forKey: key)
        guard value >= 0 else {
            throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert negative Int \(value) to UInt"))
        }
        return UInt(value)
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        let value = try decode(Int.self, forKey: key)
        guard value >= 0 && value <= Int(UInt8.max) else {
            throw DecodingError.typeMismatch(UInt8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Value \(value) out of range for UInt8"))
        }
        return UInt8(value)
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        let value = try decode(Int.self, forKey: key)
        guard value >= 0 && value <= Int(UInt16.max) else {
            throw DecodingError.typeMismatch(UInt16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Value \(value) out of range for UInt16"))
        }
        return UInt16(value)
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        let value = try decode(Int.self, forKey: key)
        guard value >= 0 else {
            throw DecodingError.typeMismatch(UInt32.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert negative Int \(value) to UInt32"))
        }
        return UInt32(value)  // Safe: UInt32.max > Int.max on 64-bit platforms
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        let value = try decode(Int.self, forKey: key)
        guard value >= 0 else {
            throw DecodingError.typeMismatch(UInt64.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert negative Int \(value) to UInt64"))
        }
        return UInt64(value)  // Safe: UInt64.max > Int.max
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        // Handle UUID
        if type == UUID.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .uuid(let value):
                // invariant-protected unwrap - T is UUID (checked above), value is UUID
                guard let typedValue = value as? T else {
                    BlazeLogger.error("❌ BlazeRecordDecoder: Invariant violated - UUID cast failed for type \(T.self)")
                    throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast UUID to \(T.self)"))
                }
                return typedValue
            case .string(let str):
                guard let uuid = UUID(uuidString: str) else {
                    throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid UUID string: \(str)"))
                }
                // invariant-protected unwrap - T is UUID (checked above), uuid is UUID
                guard let typedUUID = uuid as? T else {
                    BlazeLogger.error("❌ BlazeRecordDecoder: Invariant violated - UUID cast failed for type \(T.self)")
                    throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast UUID to \(T.self)"))
                }
                return typedUUID
            default:
                throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UUID, got \(field)"))
            }
        }
        
        // Handle Date
        if type == Date.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .date(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Date to \(T.self)"))
                }
                return result
            case .double(let timestamp):
                // Handle dates stored as TimeInterval
                let date = Date(timeIntervalSinceReferenceDate: timestamp)
                guard let result = date as? T else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Date to \(T.self)"))
                }
                return result
            case .string(let str):
                // Try ISO8601 format
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: str) else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid date string: \(str)"))
                }
                guard let result = date as? T else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Date to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Date, got \(field)"))
            }
        }
        
        // Handle Data
        if type == Data.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .data(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Data to \(T.self)"))
                }
                return result
            case .string(let str):
                // Try base64
                guard let data = Data(base64Encoded: str) else {
                    throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid base64 string"))
                }
                guard let result = data as? T else {
                    throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Data to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Data, got \(field)"))
            }
        }
        
        // Handle String (for dictionary values like [String: String])
        if type == String.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .string(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast String to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected String, got \(field)"))
            }
        }
        
        // Handle Int (for dictionary values like [String: Int])
        if type == Int.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .int(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Int to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int, got \(field)"))
            }
        }
        
        // Handle Bool (for dictionary values like [String: Bool])
        if type == Bool.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .bool(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Bool to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Bool, got \(field)"))
            }
        }
        
        // Handle Double (for dictionary values like [String: Double])
        if type == Double.self {
            guard let field = storage[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
            }
            switch field {
            case .double(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Double to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Double, got \(field)"))
            }
        }
        
        // Handle nested Codable types (recursive decode)
        guard let nestedField = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        switch nestedField {
        case .array(let arr):
            // Handle arrays - create a decoder that provides the unkeyed container
            let arrayDecoder = BlazeRecordArrayDecoder(array: arr, codingPath: codingPath + [key])
            return try T(from: arrayDecoder)
        case .dictionary(let dict):
            // Create nested decoder for dictionary
            let nestedStorage = dict.mapValues { $0 }
            let nestedDecoder = BlazeRecordDecoder(storage: nestedStorage, codingPath: codingPath + [key])
            return try T(from: nestedDecoder)
        default:
            throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected nested Codable type, got \(nestedField)"))
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let field = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        guard case .dictionary(let dict) = field else {
            throw DecodingError.typeMismatch([String: BlazeDocumentField].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected dictionary, got \(field)"))
        }
        
        let nestedStorage = dict.mapValues { $0 }
        let nestedDecoder = BlazeRecordDecoder(storage: nestedStorage, codingPath: codingPath + [key])
        return try nestedDecoder.container(keyedBy: type)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        guard let field = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key \(key.stringValue) not found"))
        }
        
        guard case .array(let array) = field else {
            throw DecodingError.typeMismatch([BlazeDocumentField].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected array, got \(field)"))
        }
        
        return BlazeRecordUnkeyedDecodingContainer(decoder: decoder, array: array, codingPath: codingPath + [key])
    }
    
    func superDecoder() throws -> Decoder {
        return decoder
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        return decoder
    }
}

/// Unkeyed decoding container for arrays
private struct BlazeRecordUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey]
    var count: Int? {
        return array.count
    }
    var isAtEnd: Bool {
        return currentIndex >= array.count
    }
    var currentIndex: Int = 0
    
    private let decoder: BlazeRecordDecoder
    private let array: [BlazeDocumentField]
    
    init(decoder: BlazeRecordDecoder, array: [BlazeDocumentField], codingPath: [CodingKey]) {
        self.decoder = decoder
        self.array = array
        self.codingPath = codingPath
    }
    
    mutating func decodeNil() throws -> Bool {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound(Optional<Any>.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        if case .null = array[currentIndex] {
            currentIndex += 1
            return true
        }
        return false
    }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        switch field {
        case .bool(let value):
            return value
        case .int(let value):
            return value != 0
        default:
            throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Bool, got \(field)"))
        }
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        guard case .string(let value) = field else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected String, got \(field)"))
        }
        return value
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        switch field {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Double, got \(field)"))
        }
    }
    
    mutating func decode(_ type: Float.Type) throws -> Float {
        return Float(try decode(Double.self))
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        switch field {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int, got \(field)"))
        }
    }
    
    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        let value = try decode(Int.self)
        guard value >= Int(Int8.min) && value <= Int(Int8.max) else {
            throw DecodingError.typeMismatch(Int8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Value \(value) out of range for Int8"))
        }
        return Int8(value)
    }
    
    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        let value = try decode(Int.self)
        guard value >= Int(Int16.min) && value <= Int(Int16.max) else {
            throw DecodingError.typeMismatch(Int16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Value \(value) out of range for Int16"))
        }
        return Int16(value)
    }
    
    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        let value = try decode(Int.self)
        return Int32(value)  // Safe: Int32 can represent all Int values on 64-bit platforms
    }
    
    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        let value = try decode(Int.self)
        return Int64(value)  // Safe: Int64 can represent all Int values
    }
    
    mutating func decode(_ type: UInt.Type) throws -> UInt {
        let value = try decode(Int.self)
        guard value >= 0 else {
            throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert negative Int \(value) to UInt"))
        }
        return UInt(value)
    }
    
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        let value = try decode(Int.self)
        guard value >= 0 && value <= Int(UInt8.max) else {
            throw DecodingError.typeMismatch(UInt8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Value \(value) out of range for UInt8"))
        }
        return UInt8(value)
    }
    
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        let value = try decode(Int.self)
        guard value >= 0 && value <= Int(UInt16.max) else {
            throw DecodingError.typeMismatch(UInt16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Value \(value) out of range for UInt16"))
        }
        return UInt16(value)
    }
    
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        let value = try decode(Int.self)
        guard value >= 0 else {
            throw DecodingError.typeMismatch(UInt32.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert negative Int \(value) to UInt32"))
        }
        return UInt32(value)  // Safe: UInt32.max > Int.max on 64-bit platforms
    }
    
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        let value = try decode(Int.self)
        guard value >= 0 else {
            throw DecodingError.typeMismatch(UInt64.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert negative Int \(value) to UInt64"))
        }
        return UInt64(value)  // Safe: UInt64.max > Int.max
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        // Handle UUID
        if type == UUID.self {
            switch field {
            case .uuid(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast UUID to \(T.self)"))
                }
                return result
            case .string(let str):
                guard let uuid = UUID(uuidString: str) else {
                    throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid UUID string: \(str)"))
                }
                guard let result = uuid as? T else {
                    throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast UUID to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UUID, got \(field)"))
            }
        }
        
        // Handle Date
        if type == Date.self {
            switch field {
            case .date(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Date to \(T.self)"))
                }
                return result
            case .double(let timestamp):
                let date = Date(timeIntervalSinceReferenceDate: timestamp)
                guard let result = date as? T else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Date to \(T.self)"))
                }
                return result
            case .string(let str):
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: str) else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid date string: \(str)"))
                }
                guard let result = date as? T else {
                    throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Date to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Date, got \(field)"))
            }
        }
        
        // Handle Data
        if type == Data.self {
            switch field {
            case .data(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Data to \(T.self)"))
                }
                return result
            case .string(let str):
                guard let data = Data(base64Encoded: str) else {
                    throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Invalid base64 string"))
                }
                guard let result = data as? T else {
                    throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Data to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Data, got \(field)"))
            }
        }
        
        // Handle String
        if type == String.self {
            switch field {
            case .string(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast String to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected String, got \(field)"))
            }
        }
        
        // Handle Int
        if type == Int.self {
            switch field {
            case .int(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Int to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int, got \(field)"))
            }
        }
        
        // Handle Bool
        if type == Bool.self {
            switch field {
            case .bool(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Bool to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Bool, got \(field)"))
            }
        }
        
        // Handle Double
        if type == Double.self {
            switch field {
            case .double(let value):
                guard let result = value as? T else {
                    throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Failed to cast Double to \(T.self)"))
                }
                return result
            default:
                throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Double, got \(field)"))
            }
        }
        
        // Handle nested Codable types
        switch field {
        case .dictionary(let dict):
            let nestedStorage = dict.mapValues { $0 }
            let nestedDecoder = BlazeRecordDecoder(storage: nestedStorage, codingPath: codingPath)
            return try T(from: nestedDecoder)
        default:
            throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected nested Codable type, got \(field)"))
        }
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound([String: BlazeDocumentField].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        guard case .dictionary(let dict) = field else {
            throw DecodingError.typeMismatch([String: BlazeDocumentField].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected dictionary, got \(field)"))
        }
        
        let nestedStorage = dict.mapValues { $0 }
        let nestedDecoder = BlazeRecordDecoder(storage: nestedStorage, codingPath: codingPath)
        return try nestedDecoder.container(keyedBy: type)
    }
    
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard currentIndex < array.count else {
            throw DecodingError.valueNotFound([BlazeDocumentField].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Array index out of bounds"))
        }
        let field = array[currentIndex]
        currentIndex += 1
        
        guard case .array(let nestedArray) = field else {
            throw DecodingError.typeMismatch([BlazeDocumentField].self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected array, got \(field)"))
        }
        
        return BlazeRecordUnkeyedDecodingContainer(decoder: decoder, array: nestedArray, codingPath: codingPath)
    }
    
    mutating func superDecoder() throws -> Decoder {
        return decoder
    }
}

/// Decoder that wraps an unkeyed container for array decoding
private class BlazeRecordArrayDecoder: Decoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    private let array: [BlazeDocumentField]
    private let baseDecoder: BlazeRecordDecoder
    
    init(array: [BlazeDocumentField], codingPath: [CodingKey], baseDecoder: BlazeRecordDecoder? = nil) {
        self.array = array
        self.codingPath = codingPath
        self.baseDecoder = baseDecoder ?? BlazeRecordDecoder(storage: [:], codingPath: codingPath)
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode keyed container from array"))
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode single value container from array"))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return BlazeRecordUnkeyedDecodingContainer(decoder: baseDecoder, array: array, codingPath: codingPath)
    }
}

