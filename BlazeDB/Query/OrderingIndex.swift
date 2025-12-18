//
//  OrderingIndex.swift
//  BlazeDB
//
//  Optional fractional ordering system for BlazeDB records.
//  Completely optional and off by default - zero breaking changes.
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Ordering Index Utilities

/// Utility functions for fractional index calculation (Notion/Linear-style ordering)
///
/// These functions help calculate safe fractional indices for inserting records
/// between existing records without reordering other items.
///
/// **Default value:** 1000.0
/// **Insert between:** (a + b) / 2
/// **Handles nil gracefully:** nil values sort last
public enum OrderingIndex {
    
    /// Default ordering index for new records
    public static let `default`: Double = 1000.0
    
    /// Calculate index between two existing indices
    /// - Parameters:
    ///   - a: First index (nil = before start)
    ///   - b: Second index (nil = after end)
    /// - Returns: Index between a and b, or default if both nil
    public static func between(_ a: Double?, _ b: Double?) -> Double {
        let result: Double
        switch (a, b) {
        case (nil, nil):
            // Both nil: return default
            BlazeLogger.debug("OrderingIndex.between: both nil, using default \(`default`)")
            result = `default`
        case (let aValue?, nil):
            // Only a exists: insert after it
            result = after(aValue)
            BlazeLogger.debug("OrderingIndex.between: after \(aValue) = \(result)")
        case (nil, let bValue?):
            // Only b exists: insert before it
            result = before(bValue)
            BlazeLogger.debug("OrderingIndex.between: before \(bValue) = \(result)")
        case (let aValue?, let bValue?):
            // Both exist: insert between them
            if aValue < bValue {
                result = (aValue + bValue) / 2.0
                BlazeLogger.debug("OrderingIndex.between: \(aValue) and \(bValue) = \(result)")
            } else if aValue > bValue {
                // Handle reverse order (shouldn't happen, but be safe)
                result = (bValue + aValue) / 2.0
                BlazeLogger.warn("OrderingIndex.between: reverse order detected (\(aValue) > \(bValue)), using \(result)")
            } else {
                // Equal values: add small increment
                result = aValue + 0.1
                BlazeLogger.debug("OrderingIndex.between: equal values (\(aValue)), incrementing to \(result)")
            }
        }
        return result
    }
    
    /// Calculate index before an existing index
    /// - Parameter index: Existing index
    /// - Returns: Index before the given index
    public static func before(_ index: Double) -> Double {
        // Subtract 1.0 (negative values are allowed for moving before first item)
        let result = index - 1.0
        BlazeLogger.debug("OrderingIndex.before: \(index) -> \(result)")
        return result
    }
    
    /// Calculate index after an existing index
    /// - Parameter index: Existing index
    /// - Returns: Index after the given index
    public static func after(_ index: Double) -> Double {
        // Add 1.0
        let result = index + 1.0
        BlazeLogger.debug("OrderingIndex.after: \(index) -> \(result)")
        return result
    }
    
    /// Extract ordering index from a record
    /// - Parameter record: BlazeDataRecord
    /// - Parameter fieldName: Field name for ordering index (default: "orderingIndex")
    /// - Returns: Ordering index value, or nil if not present
    public static func getIndex(from record: BlazeDataRecord, fieldName: String = "orderingIndex") -> Double? {
        guard let field = record.storage[fieldName] else {
            let recordID = record.storage["id"]?.uuidValue?.uuidString ?? "unknown"
            BlazeLogger.trace("OrderingIndex.getIndex: field '\(fieldName)' not found in record \(recordID)")
            return nil
        }
        
        let result: Double?
        switch field {
        case .int(let value):
            result = Double(value)
            BlazeLogger.trace("OrderingIndex.getIndex: extracted int \(value) -> double \(result!)")
        case .double(let value):
            result = value
            BlazeLogger.trace("OrderingIndex.getIndex: extracted double \(value)")
        default:
            BlazeLogger.warn("OrderingIndex.getIndex: field '\(fieldName)' has unsupported type, expected int/double")
            result = nil
        }
        return result
    }
    
    /// Set ordering index on a record
    /// - Parameters:
    ///   - record: BlazeDataRecord (will be modified)
    ///   - index: Ordering index value
    ///   - fieldName: Field name for ordering index (default: "orderingIndex")
    /// - Returns: Modified record with ordering index set
    public static func setIndex(_ index: Double, on record: BlazeDataRecord, fieldName: String = "orderingIndex") -> BlazeDataRecord {
        let recordID = record.storage["id"]?.uuidValue?.uuidString ?? "unknown"
        BlazeLogger.debug("OrderingIndex.setIndex: setting \(fieldName) = \(index) for record \(recordID)")
        var storage = record.storage
        storage[fieldName] = .double(index)
        // Preserve the ID if it exists
        if record.storage["id"] != nil {
            storage["id"] = record.storage["id"]
        }
        return BlazeDataRecord(storage)
    }
}

// MARK: - Ordering Support Check

extension DynamicCollection {
    /// Check if ordering is enabled for this collection
    /// - Returns: true if ordering is supported, false otherwise
    internal func supportsOrdering() -> Bool {
        #if !BLAZEDB_LINUX_CORE
        // Check metadata flag (default: false)
        do {
            let meta = try fetchMeta()
            let enabled = meta["supportsOrdering"]?.boolValue ?? false
            BlazeLogger.trace("DynamicCollection.supportsOrdering: \(enabled)")
            return enabled
        } catch {
            BlazeLogger.warn("DynamicCollection.supportsOrdering: failed to fetch metadata: \(error)")
            return false
        }
        #else
        // Linux: MetaStore not available, return false
        return false
        #endif
    }
    
    /// Get the ordering field name for this collection
    /// - Returns: Field name for ordering index (default: "orderingIndex")
    internal func orderingFieldName() -> String {
        #if !BLAZEDB_LINUX_CORE
        do {
            let meta = try fetchMeta()
            let fieldName = meta["orderingFieldName"]?.stringValue ?? "orderingIndex"
            BlazeLogger.trace("DynamicCollection.orderingFieldName: \(fieldName)")
            return fieldName
        } catch {
            BlazeLogger.warn("DynamicCollection.orderingFieldName: failed to fetch metadata: \(error), using default")
            return "orderingIndex"
        }
        #else
        // Linux: MetaStore not available, return default
        return "orderingIndex"
        #endif
    }
    
    /// Enable ordering support for this collection
    /// - Parameters:
    ///   - fieldName: Field name for ordering index (default: "orderingIndex")
    /// - Throws: Error if metadata update fails
    internal func enableOrdering(fieldName: String = "orderingIndex") throws {
        #if !BLAZEDB_LINUX_CORE
        BlazeLogger.debug("🔧 [ENABLEORDERING] Starting - fieldName: \(fieldName)")
        var meta = try fetchMeta()
        BlazeLogger.debug("🔧 [ENABLEORDERING] Fetched metadata: \(meta.count) keys")
        meta["supportsOrdering"] = BlazeDocumentField.bool(true)
        meta["orderingFieldName"] = BlazeDocumentField.string(fieldName)
        BlazeLogger.debug("🔧 [ENABLEORDERING] Updated metadata, now has: \(meta.count) keys")
        try updateMeta(meta)
        BlazeLogger.info("✅ [ENABLEORDERING] Ordering enabled for collection with field: \(fieldName)")
        
        // Verify it was saved
        let verifyMeta = try fetchMeta()
        let isEnabled = verifyMeta["supportsOrdering"]?.boolValue ?? false
        BlazeLogger.debug("🔧 [ENABLEORDERING] Verification - supportsOrdering: \(isEnabled), fieldName: \(verifyMeta["orderingFieldName"]?.stringValue ?? "nil")")
        if !isEnabled {
            BlazeLogger.error("❌ [ENABLEORDERING] CRITICAL: Metadata was not persisted correctly!")
        }
        #else
        // Linux: MetaStore not available, ordering not supported
        throw BlazeDBError.transactionFailed("Ordering support requires MetaStore (not available on Linux)")
        #endif
    }
}

