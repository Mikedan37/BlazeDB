//
//  QueryResult.swift
//  BlazeDB
//
//  Unified query result type that wraps all possible query outcomes.
//  This provides a clean, consistent API while maintaining type safety.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

/// Unified result type for all query operations.
/// This eliminates the need for multiple execute methods and provides a consistent API.
public enum QueryResult {
    /// Standard query returning a list of records
    case records([BlazeDataRecord])
    
    /// JOIN query returning combined records from multiple collections
    case joined([JoinedRecord])
    
    /// Single aggregation result (COUNT, SUM, AVG, MIN, MAX without GROUP BY)
    case aggregation(AggregationResult)
    
    /// Grouped aggregation result (with GROUP BY)
    case grouped(GroupedAggregationResult)
    
    /// Full-text search results with relevance scores
    case search([FullTextSearchResult])
    
    // MARK: - Convenient Accessors
    
    /// Extract records, or throw if not a records result
    public var records: [BlazeDataRecord] {
        get throws {
            guard case .records(let records) = self else {
                throw BlazeDBError.transactionFailed("Expected records result, got \(self.resultType)")
            }
            return records
        }
    }
    
    /// Extract joined records, or throw if not a joined result
    public var joined: [JoinedRecord] {
        get throws {
            guard case .joined(let joined) = self else {
                throw BlazeDBError.transactionFailed("Expected joined result, got \(self.resultType)")
            }
            return joined
        }
    }
    
    /// Extract aggregation result, or throw if not an aggregation
    public var aggregation: AggregationResult {
        get throws {
            guard case .aggregation(let agg) = self else {
                throw BlazeDBError.transactionFailed("Expected aggregation result, got \(self.resultType)")
            }
            return agg
        }
    }
    
    /// Extract grouped aggregation result, or throw if not grouped
    public var grouped: GroupedAggregationResult {
        get throws {
            guard case .grouped(let grouped) = self else {
                throw BlazeDBError.transactionFailed("Expected grouped result, got \(self.resultType)")
            }
            return grouped
        }
    }
    
    
    // MARK: - Safe Accessors (Optional)
    
    /// Safely extract records without throwing
    public var recordsOrNil: [BlazeDataRecord]? {
        guard case .records(let records) = self else { return nil }
        return records
    }
    
    /// Safely extract joined records without throwing
    public var joinedOrNil: [JoinedRecord]? {
        guard case .joined(let joined) = self else { return nil }
        return joined
    }
    
    /// Safely extract aggregation without throwing
    public var aggregationOrNil: AggregationResult? {
        guard case .aggregation(let agg) = self else { return nil }
        return agg
    }
    
    /// Safely extract grouped aggregation without throwing
    public var groupedOrNil: GroupedAggregationResult? {
        guard case .grouped(let grouped) = self else { return nil }
        return grouped
    }
    
    /// Extract search results, or throw if not a search result
    public var searchResults: [FullTextSearchResult] {
        get throws {
            guard case .search(let results) = self else {
                throw BlazeDBError.transactionFailed("Expected search result, got \(self.resultType)")
            }
            return results
        }
    }
    
    /// Safely extract search results without throwing
    public var searchResultsOrNil: [FullTextSearchResult]? {
        guard case .search(let results) = self else { return nil }
        return results
    }
    
    // MARK: - Common Operations
    
    /// Get the count of results (works for all result types)
    public var count: Int {
        switch self {
        case .records(let records):
            return records.count
        case .joined(let joined):
            return joined.count
        case .aggregation:
            return 1
        case .grouped(let grouped):
            return grouped.groups.count
        case .search(let results):
            return results.count
        }
    }
    
    /// Check if the result is empty
    public var isEmpty: Bool {
        return count == 0
    }
    
    /// Get a human-readable description of the result type
    public var resultType: String {
        switch self {
        case .records:
            return "records"
        case .joined:
            return "joined"
        case .aggregation:
            return "aggregation"
        case .grouped:
            return "grouped"
        case .search:
            return "search"
        }
    }
    
    // MARK: - Convenience Conversions
    
    /// Convert joined records to plain records (merging left and right)
    public func flattenJoined() throws -> [BlazeDataRecord] {
        let joinedRecords = try joined
        return joinedRecords.map { $0.merged() }
    }
    
    /// Extract search results as plain records (discarding scores)
    public func searchAsRecords() throws -> [BlazeDataRecord] {
        let searchResults = try searchResults
        return searchResults.map { $0.record }
    }
}

// MARK: - CustomStringConvertible

extension QueryResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .records(let records):
            return "QueryResult.records(\(records.count) records)"
        case .joined(let joined):
            return "QueryResult.joined(\(joined.count) joined records)"
        case .aggregation(let agg):
            return "QueryResult.aggregation(\(agg))"
        case .grouped(let grouped):
            return "QueryResult.grouped(\(grouped.groups.count) groups)"
        case .search(let results):
            return "QueryResult.search(\(results.count) results)"
        }
    }
}

// MARK: - Result Builder Support (Future Enhancement)

extension QueryResult {
    /// Check if this result matches the expected type
    public func isType(_ type: QueryResultType) -> Bool {
        switch (self, type) {
        case (.records, .records): return true
        case (.joined, .joined): return true
        case (.aggregation, .aggregation): return true
        case (.grouped, .grouped): return true
        case (.search, .search): return true
        default: return false
        }
    }
}

/// Enum representing the type of query result
public enum QueryResultType {
    case records
    case joined
    case aggregation
    case grouped
    case search
}

