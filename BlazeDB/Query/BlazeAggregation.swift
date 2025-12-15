//  BlazeAggregation.swift
//  BlazeDB
//  Created by Michael Danylchuk on 1/7/25.

import Foundation

// MARK: - Aggregation Types

/// Defines the types of aggregation operations supported
public enum AggregationType {
    /// Count the number of records
    case count(as: String?)
    
    /// Sum values of a numeric field
    case sum(String, as: String?)
    
    /// Calculate average of a numeric field
    case avg(String, as: String?)
    
    /// Find minimum value
    case min(String, as: String?)
    
    /// Find maximum value
    case max(String, as: String?)
}

// MARK: - Aggregation Result

/// Result of an aggregation operation
public struct AggregationResult: Codable, Equatable {
    public var values: [String: BlazeDocumentField]
    
    public init(values: [String: BlazeDocumentField] = [:]) {
        self.values = values
    }
    
    /// Access aggregation results by name
    public subscript(key: String) -> BlazeDocumentField? {
        get { return values[key] }
        set { values[key] = newValue }
    }
    
    /// Get count value
    public var count: Int? {
        return values["count"]?.intValue
    }
    
    /// Get sum value
    public func sum(_ field: String) -> Double? {
        return values[field]?.doubleValue
    }
    
    /// Get average value
    public func avg(_ field: String) -> Double? {
        return values[field]?.doubleValue
    }
    
    /// Get minimum value
    public func min(_ field: String) -> BlazeDocumentField? {
        return values[field]
    }
    
    /// Get maximum value
    public func max(_ field: String) -> BlazeDocumentField? {
        return values[field]
    }
}

// MARK: - Grouped Aggregation Result

/// Result of a grouped aggregation (GROUP BY)
public struct GroupedAggregationResult: Codable, Equatable {
    public var groups: [String: AggregationResult]
    
    public init(groups: [String: AggregationResult] = [:]) {
        self.groups = groups
    }
    
    /// Access groups by key
    public subscript(key: String) -> AggregationResult? {
        get { return groups[key] }
        set { groups[key] = newValue }
    }
    
    /// Get all group keys
    public var keys: [String] {
        return Array(groups.keys)
    }
    
    /// Total count across all groups
    public var totalCount: Int {
        return groups.values.compactMap { $0.count }.reduce(0, +)
    }
}

// MARK: - Aggregation Engine

/// Performs aggregation operations on records
internal struct AggregationEngine {
    
    /// Perform aggregations without grouping
    static func aggregate(
        records: [BlazeDataRecord],
        operations: [AggregationType]
    ) -> AggregationResult {
        var result = AggregationResult()
        
        for operation in operations {
            switch operation {
            case .count(let alias):
                let name = alias ?? "count"
                result.values[name] = .int(records.count)
                
            case .sum(let field, let alias):
                let name = alias ?? "sum_\(field)"
                let sum = records.compactMap { record -> Double? in
                    guard let value = record.storage[field] else { return nil }
                    switch value {
                    case .int(let v): return Double(v)
                    case .double(let v): return v
                    default: return nil
                    }
                }.reduce(0, +)
                result.values[name] = .double(sum)
                
            case .avg(let field, let alias):
                let name = alias ?? "avg_\(field)"
                let values = records.compactMap { record -> Double? in
                    guard let value = record.storage[field] else { return nil }
                    switch value {
                    case .int(let v): return Double(v)
                    case .double(let v): return v
                    default: return nil
                    }
                }
                let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                result.values[name] = .double(avg)
                
            case .min(let field, let alias):
                let name = alias ?? "min_\(field)"
                if let minRecord = records.min(by: { r1, r2 in
                    compareFields(r1.storage[field], r2.storage[field]) == .orderedAscending
                }) {
                    result.values[name] = minRecord.storage[field] ?? .int(0)
                }
                
            case .max(let field, let alias):
                let name = alias ?? "max_\(field)"
                if let maxRecord = records.max(by: { r1, r2 in
                    compareFields(r1.storage[field], r2.storage[field]) == .orderedAscending
                }) {
                    result.values[name] = maxRecord.storage[field] ?? .int(0)
                }
            }
        }
        
        return result
    }
    
    /// Perform aggregations with grouping
    static func aggregateGrouped(
        records: [BlazeDataRecord],
        groupByFields: [String],
        operations: [AggregationType]
    ) -> GroupedAggregationResult {
        var result = GroupedAggregationResult()
        
        // Group records by field values
        let groups = Dictionary(grouping: records) { record -> String in
            let values = groupByFields.map { field -> String in
                guard let value = record.storage[field] else { return "null" }
                return fieldToString(value)
            }
            return values.joined(separator: "+")
        }
        
        // Aggregate each group
        for (groupKey, groupRecords) in groups {
            result.groups[groupKey] = aggregate(records: groupRecords, operations: operations)
        }
        
        return result
    }
    
    /// Compare two fields for min/max operations
    private static func compareFields(_ lhs: BlazeDocumentField?, _ rhs: BlazeDocumentField?) -> ComparisonResult {
        guard let lhs = lhs, let rhs = rhs else {
            if lhs == nil && rhs == nil { return .orderedSame }
            if lhs == nil { return .orderedDescending }
            return .orderedAscending
        }
        
        switch (lhs, rhs) {
        case (.int(let l), .int(let r)):
            return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        case (.double(let l), .double(let r)):
            return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        case (.int(let l), .double(let r)):
            return Double(l) < r ? .orderedAscending : (Double(l) > r ? .orderedDescending : .orderedSame)
        case (.double(let l), .int(let r)):
            return l < Double(r) ? .orderedAscending : (l > Double(r) ? .orderedDescending : .orderedSame)
        case (.date(let l), .date(let r)):
            return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        case (.string(let l), .string(let r)):
            return l.compare(r)
        default:
            return .orderedSame
        }
    }
    
    /// Convert field to string for grouping
    private static func fieldToString(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let v): 
            // For grouping, treat strings as strings (not base64 data)
            // This prevents false positives like "open" being treated as base64
            return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .date(let v): return ISO8601DateFormatter().string(from: v)
        case .uuid(let v): return v.uuidString
        case .data(let v): 
            // Use base64 encoding to distinguish Data values with same size but different content
            return "data:" + v.base64EncodedString()
        case .array: return "array"
        case .dictionary: return "dict"
        case .vector(let v): return "vector[\(v.count)]"
        case .null: return "null"
        }
    }
}

