//
//  BlazeRecordEncoder.swift
//  BlazeDB
//
//  Custom Encoder that converts Codable Record types directly to BlazeDataRecord
//  Eliminates JSON intermediate step for better performance!
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Custom Encoder that builds BlazeDataRecord directly from Codable types
/// This eliminates JSON serialization overhead when converting Record to BlazeDataRecord
internal class BlazeRecordEncoder: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    internal var storage: [String: BlazeDocumentField] = [:]
    internal var pendingArrayKey: String? = nil  // Track key for arrays encoded via encode<T>
    internal weak var currentUnkeyedContainer: BlazeRecordUnkeyedEncodingContainer? = nil  // Track current unkeyed container for single value appends
    internal var pendingDictionaryKey: String? = nil  // Track key for dictionary values encoded via single value container
    
    init(codingPath: [CodingKey] = []) {
        self.codingPath = codingPath
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let container = BlazeRecordKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        // At the top level (empty codingPath), structs should use keyed containers, not single value containers
        // If we're at the top level and not in an array or dictionary context, this is likely an error
        // We'll still return the container, but it will throw a helpful error message
        if codingPath.isEmpty && pendingDictionaryKey == nil && currentUnkeyedContainer == nil {
            // This shouldn't happen for structs, but we'll handle it gracefully
            // The error will be thrown when encode<T> is called
        }
        // If we're currently encoding an array (unkeyed container exists) or a dictionary value, use appropriate container
        return BlazeRecordSingleValueEncodingContainer(encoder: self, codingPath: codingPath, unkeyedContainer: currentUnkeyedContainer, dictionaryKey: pendingDictionaryKey)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        // If there's a pending array key, use it; otherwise create container without key
        let key = pendingArrayKey
        pendingArrayKey = nil  // Clear after use
        let container = BlazeRecordUnkeyedEncodingContainer(encoder: self, codingPath: codingPath, parentKey: key)
        currentUnkeyedContainer = container  // Track for single value container access
        return container
    }
    
    /// Get the resulting BlazeDataRecord
    func getBlazeDataRecord() -> BlazeDataRecord {
        return BlazeDataRecord(storage)
    }
}

/// Keyed encoding container for BlazeDataRecord
private struct BlazeRecordKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey]
    
    private let encoder: BlazeRecordEncoder
    
    init(encoder: BlazeRecordEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }
    
    mutating func encodeNil(forKey key: Key) throws {
        encoder.storage[key.stringValue] = .null
    }
    
    mutating func encode(_ value: Bool, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .bool(value)
    }
    
    mutating func encode(_ value: String, forKey key: Key) throws {
        // Set pendingDictionaryKey so if String's encode(to:) requests a single value container,
        // it can store the value directly
        let previousKey = encoder.pendingDictionaryKey
        encoder.pendingDictionaryKey = key.stringValue
        defer { encoder.pendingDictionaryKey = previousKey }
        
        // Try encoding via Codable (String might request single value container)
        do {
            try value.encode(to: encoder)
            
            // Check if value was stored via single value container
            if encoder.storage[key.stringValue] != nil {
                // Value was stored, we're done
                return
            }
        } catch {
            // If encoding fails, fall back to direct storage
        }
        
        // Direct storage (fallback if encode(to:) didn't store it)
        encoder.storage[key.stringValue] = .string(value)
    }
    
    mutating func encode(_ value: Double, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .double(value)
    }
    
    mutating func encode(_ value: Float, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .double(Double(value))
    }
    
    mutating func encode(_ value: Int, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(value)
    }
    
    mutating func encode(_ value: Int8, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: Int16, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: Int32, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: Int64, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: UInt, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .int(Int(value))
    }
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        // Handle UUID
        if let uuid = value as? UUID {
            encoder.storage[key.stringValue] = .uuid(uuid)
            return
        }
        
        // Handle Date
        if let date = value as? Date {
            encoder.storage[key.stringValue] = .date(date)
            return
        }
        
        // Handle Data
        if let data = value as? Data {
            encoder.storage[key.stringValue] = .data(data)
            return
        }
        
        // Try to detect if this is an array by attempting to encode it via unkeyed container
        // Swift's Array encoding will call encoder.unkeyedContainer(), so we set pendingArrayKey
        // and let the array encode itself
        let arrayEncoder = BlazeRecordEncoder(codingPath: codingPath + [key])
        arrayEncoder.pendingArrayKey = key.stringValue
        do {
            try value.encode(to: arrayEncoder)
            
            // Check if array was stored (via unkeyed container's deinit)
            if let arrayValue = arrayEncoder.storage[key.stringValue], case .array = arrayValue {
                encoder.storage[key.stringValue] = arrayValue
                return
            }
        } catch {
            // If encoding fails, it might not be an array - fall through to dictionary encoding
        }
        
        // Handle nested Codable types (recursive encode)
        // Set pendingDictionaryKey so single value containers can store values directly
        let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath + [key])
        nestedEncoder.pendingDictionaryKey = key.stringValue
        try value.encode(to: nestedEncoder)
        
        // Check if value was stored via single value container (for dictionary values)
        if let singleValue = nestedEncoder.storage[key.stringValue] {
            encoder.storage[key.stringValue] = singleValue
            return
        }
        
        // Otherwise, treat as dictionary
        encoder.storage[key.stringValue] = .dictionary(nestedEncoder.storage)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath + [key])
        // Don't set pendingDictionaryKey here - dictionary values should use encode(_ value: T, forKey key: Key)
        // Single value containers in dictionary context will be handled by checking if we're in a keyed container
        let container = BlazeRecordKeyedEncodingContainer<NestedKey>(encoder: nestedEncoder, codingPath: codingPath + [key])
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        // Create a container that will store the array back to this encoder's storage
        let container = BlazeRecordUnkeyedEncodingContainer(encoder: encoder, codingPath: codingPath + [key], parentKey: key.stringValue)
        // Track this container so single value containers can append to it
        encoder.currentUnkeyedContainer = container
        return container
    }
    
    mutating func superEncoder() -> Encoder {
        return encoder
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        return encoder
    }
}

/// Single value encoding container
private struct BlazeRecordSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey]
    
    private let encoder: BlazeRecordEncoder
    private weak var unkeyedContainer: BlazeRecordUnkeyedEncodingContainer?
    private let dictionaryKey: String?
    
    init(encoder: BlazeRecordEncoder, codingPath: [CodingKey], unkeyedContainer: BlazeRecordUnkeyedEncodingContainer? = nil, dictionaryKey: String? = nil) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.unkeyedContainer = unkeyedContainer
        self.dictionaryKey = dictionaryKey
    }
    
    mutating func encodeNil() throws {
        // If we're in an unkeyed container (array), append to it
        if let container = unkeyedContainer {
            try container.encodeNil()
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .null
            return
        }
        throw EncodingError.invalidValue(NSNull(), EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Bool) throws {
        // If we're in an unkeyed container (array), append to it
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .bool(value)
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: String) throws {
        // If we're in an unkeyed container (array), append to it
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .string(value)
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Double) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .double(value)
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Float) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .double(Double(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Int) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(value)
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Int8) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Int16) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Int32) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: Int64) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: UInt) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: UInt8) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: UInt16) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: UInt32) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode(_ value: UInt64) throws {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, store it directly
        if let key = dictionaryKey {
            encoder.storage[key] = .int(Int(value))
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        if let container = unkeyedContainer {
            try container.encode(value)
            return
        }
        // If we're encoding a dictionary value, handle special types
        if let key = dictionaryKey {
            if let uuid = value as? UUID {
                encoder.storage[key] = .uuid(uuid)
                return
            }
            if let date = value as? Date {
                encoder.storage[key] = .date(date)
                return
            }
            if let data = value as? Data {
                encoder.storage[key] = .data(data)
                return
            }
            // For other Codable types, encode recursively
            let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath)
            try value.encode(to: nestedEncoder)
            encoder.storage[key] = .dictionary(nestedEncoder.storage)
            return
        }
        // If we're at the top level (empty codingPath), this is likely a struct that should use a keyed container
        // Try to encode it as a dictionary instead of throwing an error
        if codingPath.isEmpty {
            // Create a new encoder and try to encode the value as a keyed container
            // This handles cases where Swift's Codable synthesis might incorrectly request a single value container
            let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath)
            try value.encode(to: nestedEncoder)
            // If the nested encoder has storage, merge it into this encoder's storage
            // This allows structs to be encoded even if they request a single value container
            for (key, field) in nestedEncoder.storage {
                encoder.storage[key] = field
            }
            return
        }
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "Single value containers not supported"))
    }
}

/// Unkeyed encoding container for arrays
internal class BlazeRecordUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey]
    var count: Int {
        return array.count
    }
    
    private let encoder: BlazeRecordEncoder
    private var array: [BlazeDocumentField] = []
    private let parentKey: String?
    
    init(encoder: BlazeRecordEncoder, codingPath: [CodingKey], parentKey: String? = nil) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.parentKey = parentKey
    }
    
    // Store array back to encoder when container is deallocated
    deinit {
        if let key = parentKey {
            encoder.storage[key] = .array(array)
        }
    }
    
    func encodeNil() throws {
        array.append(.null)
    }
    
    func encode(_ value: Bool) throws {
        array.append(.bool(value))
    }
    
    func encode(_ value: String) throws {
        array.append(.string(value))
    }
    
    func encode(_ value: Double) throws {
        array.append(.double(value))
    }
    
    func encode(_ value: Float) throws {
        array.append(.double(Double(value)))
    }
    
    func encode(_ value: Int) throws {
        array.append(.int(value))
    }
    
    func encode(_ value: Int8) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: Int16) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: Int32) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: Int64) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: UInt) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: UInt8) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: UInt16) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: UInt32) throws {
        array.append(.int(Int(value)))
    }
    
    func encode(_ value: UInt64) throws {
        array.append(.int(Int(value)))
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        // Handle UUID
        if let uuid = value as? UUID {
            array.append(.uuid(uuid))
            return
        }
        
        // Handle Date
        if let date = value as? Date {
            array.append(.date(date))
            return
        }
        
        // Handle Data
        if let data = value as? Data {
            array.append(.data(data))
            return
        }
        
        // Handle nested Codable types
        // If the nested type requests a single value container (like String in an array),
        // we want it to append to this array, not create a dictionary
        let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath)
        nestedEncoder.currentUnkeyedContainer = self  // Allow nested types to append to this array
        try value.encode(to: nestedEncoder)
        
        // Check if the nested encoder stored a value in the array (via single value container)
        // If not, treat it as a dictionary
        if nestedEncoder.storage.isEmpty {
            // Value was encoded via single value container and appended to our array
            // Nothing to do - it's already in the array
        } else {
            // Value was encoded as a dictionary
            array.append(.dictionary(nestedEncoder.storage))
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath)
        let container = BlazeRecordKeyedEncodingContainer<NestedKey>(encoder: nestedEncoder, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }
    
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let nestedEncoder = BlazeRecordEncoder(codingPath: codingPath)
        return BlazeRecordUnkeyedEncodingContainer(encoder: nestedEncoder, codingPath: codingPath)
    }
    
    func superEncoder() -> Encoder {
        // Ensure the encoder knows about this container for single value container access
        encoder.currentUnkeyedContainer = self
        return encoder
    }
}

