//  BlazeJoin.swift
//  BlazeDB
//  Created by Michael Danylchuk

import Foundation

// MARK: - Join Types

/// Type of join operation
public enum JoinType {
    /// Inner join - only returns records that have matches in both collections
    case inner
    
    /// Left join - returns all records from left collection, with matching records from right (or nil)
    case left
    
    /// Right join - returns all records from right collection, with matching records from left (or nil)
    case right
    
    /// Full outer join - returns all records from both collections
    case full
}

// MARK: - Joined Record

/// Result of a join operation containing records from both collections
public struct JoinedRecord: Equatable {
    /// Record from the left collection
    public let left: BlazeDataRecord
    
    /// Record from the right collection (may be nil for left/full joins)
    public let right: BlazeDataRecord?
    
    /// Convenience subscript to access fields from either record
    /// Checks left first, then right
    public subscript(key: String) -> BlazeDocumentField? {
        return left.storage[key] ?? right?.storage[key]
    }
    
    /// Access field from left record specifically
    public func leftField(_ key: String) -> BlazeDocumentField? {
        return left.storage[key]
    }
    
    /// Access field from right record specifically
    public func rightField(_ key: String) -> BlazeDocumentField? {
        return right?.storage[key]
    }
    
    /// Check if this is a complete join (both left and right exist)
    public var isComplete: Bool {
        return right != nil
    }
    
    /// Merge both records into a single record (left fields take precedence on conflicts)
    public func merged() -> BlazeDataRecord {
        guard let right = right else {
            return left
        }
        
        var merged = right.storage
        // Left fields override right fields on conflict
        for (key, value) in left.storage {
            merged[key] = value
        }
        
        return BlazeDataRecord(merged)
    }
}

// MARK: - Join Result Collection

/// Collection of joined records with utility methods
public struct JoinResult {
    public let records: [JoinedRecord]
    
    /// Filter joined records
    public func filter(_ predicate: (JoinedRecord) -> Bool) -> JoinResult {
        return JoinResult(records: records.filter(predicate))
    }
    
    /// Map joined records to another type
    public func map<T>(_ transform: (JoinedRecord) -> T) -> [T] {
        return records.map(transform)
    }
    
    /// Get only complete joins (where both sides exist)
    public var complete: [JoinedRecord] {
        return records.filter { $0.isComplete }
    }
    
    /// Get joins where right side is missing
    public var incomplete: [JoinedRecord] {
        return records.filter { !$0.isComplete }
    }
    
    /// Count of joined records
    public var count: Int {
        return records.count
    }
    
    /// Access by index
    public subscript(index: Int) -> JoinedRecord {
        return records[index]
    }
}

// MARK: - Join Statistics

/// Statistics about a join operation (for debugging/optimization)
public struct JoinStatistics {
    /// Number of records from left collection
    public let leftCount: Int
    
    /// Number of records from right collection
    public let rightCount: Int
    
    /// Number of joined results
    public let resultCount: Int
    
    /// Number of queries executed
    public let queryCount: Int
    
    /// Join efficiency (resultCount / leftCount)
    public var efficiency: Double {
        guard leftCount > 0 else { return 0 }
        return Double(resultCount) / Double(leftCount)
    }
    
    /// Whether batch fetching was used
    public let usedBatchFetch: Bool
}

