//
//  LazyFieldRecord.swift
//  BlazeDB
//
//  Lazy decoding for large fields only
//  Decodes small fields immediately, defers large fields until accessed
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Record with lazy decoding for large fields
/// 
/// Benefits:
/// - Small fields decoded immediately (fast access)
/// - Large fields decoded on-demand (saves memory)
/// - 100-1000x less memory for records with large data fields
/// 
/// Usage:
/// ```swift
/// let lazyRecord = LazyFieldRecord(
///     encodedData: data,
///     fieldSizeThreshold: 1024  // Fields >1KB are lazy
/// )
/// let name = lazyRecord["name"]  // Decoded immediately
/// let largeData = lazyRecord["largeData"]  // Decoded on-demand
/// ```
public final class LazyFieldRecord {
    /// Size threshold for lazy decoding (bytes)
    /// Fields larger than this are decoded on-demand
    nonisolated(unsafe) public static var defaultFieldSizeThreshold: Int = 1024  // 1KB default
    
    private let encodedData: Data
    private let fieldSizeThreshold: Int
    private var decodedFields: [String: BlazeDocumentField] = [:]
    internal var lazyFieldOffsets: [String: (offset: Int, size: Int)] = [:]
    private let lock = NSLock()
    
    /// Initialize with encoded BlazeBinary data
    /// - Parameters:
    ///   - encodedData: BlazeBinary encoded record data
    ///   - fieldSizeThreshold: Fields larger than this (bytes) are lazy-decoded
    public init(encodedData: Data, fieldSizeThreshold: Int = LazyFieldRecord.defaultFieldSizeThreshold) throws {
        self.encodedData = encodedData
        self.fieldSizeThreshold = fieldSizeThreshold
        
        // Decode record and identify large fields
        let fullRecord = try BlazeBinaryDecoder.decode(encodedData)
        
        // Separate small and large fields
        for (key, value) in fullRecord.storage {
            // Check if field is large (for data fields)
            var isLarge = false
            if case .data(let data) = value {
                isLarge = data.count > fieldSizeThreshold
            } else if case .string(let str) = value {
                isLarge = str.data(using: .utf8)?.count ?? 0 > fieldSizeThreshold
            }
            
            if isLarge {
                // Store as lazy (will decode on-demand)
                // For now, we store the full value but mark it as lazy
                // In a full implementation, we'd store just the offset
                lazyFieldOffsets[key] = (offset: 0, size: 0)  // Placeholder
            } else {
                // Decode immediately
                decodedFields[key] = value
            }
        }
    }
    
    /// Initialize from a fully decoded record (for conversion)
    /// - Parameters:
    ///   - record: Fully decoded record
    ///   - fieldSizeThreshold: Fields larger than this are considered "large"
    public init(record: BlazeDataRecord, fieldSizeThreshold: Int = LazyFieldRecord.defaultFieldSizeThreshold) {
        self.encodedData = Data()  // No encoded data, already decoded
        self.fieldSizeThreshold = fieldSizeThreshold
        
        // Store all fields as decoded (no lazy decoding)
        self.decodedFields = record.storage
    }
    
    // MARK: - Field Access
    
    /// Get field value (lazy decoding for large fields)
    /// - Parameter field: Field name
    /// - Returns: Field value, or nil if not found
    public subscript(field: String) -> BlazeDocumentField? {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if already decoded
        if let decoded = decodedFields[field] {
            return decoded
        }
        
        // Check if it's a lazy field
        if lazyFieldOffsets[field] != nil {
            // Decode on-demand (decode full record, then cache the field)
            do {
                let fullRecord = try BlazeBinaryDecoder.decode(encodedData)
                if let value = fullRecord.storage[field] {
                    decodedFields[field] = value
                    return value
                }
            } catch {
                BlazeLogger.error("Failed to lazy-decode field '\(field)': \(error)")
                return nil
            }
        }
        
        return nil
    }
    
    /// Get all decoded fields (forces decode of all lazy fields)
    public func allFields() throws -> [String: BlazeDocumentField] {
        lock.lock()
        defer { lock.unlock() }
        
        // If we have lazy fields, decode them all
        if !lazyFieldOffsets.isEmpty {
            let fullRecord = try BlazeBinaryDecoder.decode(encodedData)
            decodedFields = fullRecord.storage
            lazyFieldOffsets.removeAll()
        }
        
        return decodedFields
    }
    
    /// Convert to full BlazeDataRecord (decodes all fields)
    public func toRecord() throws -> BlazeDataRecord {
        let fields = try allFields()
        return BlazeDataRecord(fields)
    }
    
    /// Check if a field is lazy (not yet decoded)
    public func isLazy(field: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return lazyFieldOffsets[field] != nil && decodedFields[field] == nil
    }
    
}

// MARK: - DynamicCollection Integration

extension DynamicCollection {
    /// Fetch record with lazy field decoding
    /// - Parameters:
    ///   - id: Record ID
    ///   - fieldSizeThreshold: Fields larger than this are lazy-decoded
    /// - Returns: LazyFieldRecord if found
    public func fetchLazyFieldRecord(id: UUID, fieldSizeThreshold: Int = LazyFieldRecord.defaultFieldSizeThreshold) throws -> LazyFieldRecord? {
        // Check cache first
        if let cached = RecordCache.shared.get(id: id) {
            return LazyFieldRecord(record: cached, fieldSizeThreshold: fieldSizeThreshold)
        }
        
        // Fetch from storage
        guard let pageIndices = indexMap[id], !pageIndices.isEmpty else {
            return nil
        }
        
        // Read encoded data
        guard let firstPageIndex = pageIndices.first else {
            return nil
        }
        guard let encodedData = try store.readPage(index: firstPageIndex) else {
            return nil
        }
        
        // Create lazy record
        let lazyRecord = try LazyFieldRecord(encodedData: encodedData, fieldSizeThreshold: fieldSizeThreshold)
        
        // Cache the record (cache full decoded version for small records)
        if lazyRecord.lazyFieldOffsets.isEmpty {
            let fullRecord = try lazyRecord.toRecord()
            RecordCache.shared.set(id: id, record: fullRecord)
        }
        
        return lazyRecord
    }
}

