//
//  QueryBuilder+RangeOptimization.swift
//  BlazeDB
//
//  Range query optimizations for improved performance
//  Uses indexes when available for range queries
//
//  Created by Auto on 2025-11-27.
//

import Foundation

extension QueryBuilder {
    
    /// Optimized range query using indexes when available
    ///
    /// This method attempts to use indexes for range queries (>, <, >=, <=, BETWEEN)
    /// to avoid full table scans. Falls back to sequential scan if no index is available.
    ///
    /// - Parameters:
    ///   - field: Field name for range query
    ///   - min: Minimum value (inclusive)
    ///   - max: Maximum value (inclusive)
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func whereRange(_ field: String, min: BlazeDocumentField?, max: BlazeDocumentField?) -> QueryBuilder {
        guard let collection = collection else {
            return self
        }
        
        // Try to use index if available
        let indexKey = field
        if let index = collection.secondaryIndexes[indexKey], !index.isEmpty {
            // Index available - use it for range query
            BlazeLogger.debug("🚀 Using index '\(indexKey)' for range query on \(field)")
            
            // Get all keys in the index that fall within range
            var matchingIDs: Set<UUID> = []
            
            for (key, ids) in index {
                // Check if key falls within range
                // For compound indexes, we only check the first component
                guard let keyField = key.components.first else { continue }
                
                var inRange = true
                
                // Check minimum bound
                if let min = min {
                    if !compareFieldsDirect(keyField, min, isGreaterThanOrEqual: true) {
                        inRange = false
                    }
                }
                
                // Check maximum bound
                if let max = max {
                    if !compareFieldsDirect(keyField, max, isGreaterThanOrEqual: false) {
                        inRange = false
                    }
                }
                
                if inRange {
                    matchingIDs.formUnion(ids)
                }
            }
            
            // Filter to only records in the range
            if !matchingIDs.isEmpty {
                filters.append { record in
                    guard let id = record.storage["id"]?.uuidValue else { return false }
                    return matchingIDs.contains(id)
                }
                BlazeLogger.debug("✅ Range query using index: \(matchingIDs.count) records match")
            } else {
                BlazeLogger.debug("ℹ️ Range query using index: no records match")
            }
        } else {
            // No index - use sequential filter
            BlazeLogger.debug("ℹ️ No index available for \(field), using sequential scan")
            
            if let min = min, let max = max {
                // BETWEEN query
                self.where(field, greaterThanOrEqual: min)
                self.where(field, lessThanOrEqual: max)
            } else if let min = min {
                // >= query
                self.where(field, greaterThanOrEqual: min)
            } else if let max = max {
                // <= query
                self.where(field, lessThanOrEqual: max)
            }
        }
        
        return self
    }
    
    /// Direct field comparison for range queries
    private func compareFieldsDirect(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField, isGreaterThanOrEqual: Bool) -> Bool {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)):
            return isGreaterThanOrEqual ? a >= b : a <= b
        case (.double(let a), .double(let b)):
            return isGreaterThanOrEqual ? a >= b : a <= b
        case (.int(let a), .double(let b)):
            return isGreaterThanOrEqual ? Double(a) >= b : Double(a) <= b
        case (.double(let a), .int(let b)):
            return isGreaterThanOrEqual ? a >= Double(b) : a <= Double(b)
        case (.date(let a), .date(let b)):
            return isGreaterThanOrEqual ? a >= b : a <= b
        case (.string(let a), .string(let b)):
            return isGreaterThanOrEqual ? a >= b : a <= b
        case (.uuid(let a), .uuid(let b)):
            return isGreaterThanOrEqual ? a.uuidString >= b.uuidString : a.uuidString <= b.uuidString
        default:
            return false
        }
    }
}

