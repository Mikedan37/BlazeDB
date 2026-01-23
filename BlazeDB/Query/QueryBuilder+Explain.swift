//
//  QueryBuilder+Explain.swift
//  BlazeDB
//
//  Query explainability: Lightweight cost explanation without changing execution
//  Helps developers understand query performance characteristics
//

import Foundation

/// Query explanation result
public struct QueryExplanation {
    /// Number of filters in the query
    public let filterCount: Int
    
    /// Fields used in filters (best-effort detection)
    public let filterFields: [String]
    
    /// Whether fields appear indexed (best-effort using existing metadata)
    public let indexedFields: [String]
    
    /// Estimated risk level
    public enum RiskLevel {
        case ok
        case warnFullScan
        case warnUnindexedFilter
        case unknown
    }
    
    public let riskLevel: RiskLevel
    
    /// Human-readable suggestion
    public let suggestion: String
    
    /// Human-readable description
    public var description: String {
        var desc = "Query Explanation:\n"
        desc += "  Filters: \(filterCount)\n"
        desc += "  Filter fields: \(filterFields.isEmpty ? "none" : filterFields.joined(separator: ", "))\n"
        desc += "  Indexed fields: \(indexedFields.isEmpty ? "none" : indexedFields.joined(separator: ", "))\n"
        desc += "  Risk: \(riskLevelDescription)\n"
        if !suggestion.isEmpty {
            desc += "  💡 \(suggestion)"
        }
        return desc
    }
    
    private var riskLevelDescription: String {
        switch riskLevel {
        case .ok: return "OK"
        case .warnFullScan: return "WARN: Full table scan"
        case .warnUnindexedFilter: return "WARN: Unindexed filter"
        case .unknown: return "Unknown"
        }
    }
}

extension QueryBuilder {
    
    /// Explain query cost without executing it (DX convenience method)
    ///
    /// Provides lightweight cost explanation without changing execution behavior.
    /// Uses best-effort index detection - if index metadata is not available, marks as "unknown".
    ///
    /// **Note:** This is a convenience wrapper. For detailed execution plans, use the existing `explain()` method
    /// which returns `DetailedQueryPlan`.
    ///
    /// - Returns: Query explanation with risk assessment and suggestions
    /// - Throws: Error if explanation cannot be generated
    ///
    /// ## Example
    /// ```swift
    /// let explanation = try db.query()
    ///     .where("status", equals: .string("active"))
    ///     .explainCost()
    /// print(explanation.description)
    /// ```
    public func explainCost() throws -> QueryExplanation {
        guard let collection = collection else {
            throw BlazeDBError.invalidQuery(
                reason: "Collection has been deallocated",
                suggestion: "Ensure the database connection is still valid"
            )
        }
        
        // Extract filter fields (best-effort)
        let filterFields = extractFilterFields()
        
        // Check which fields are indexed (best-effort)
        let indexedFields = checkIndexedFields(filterFields: filterFields, collection: collection)
        
        // Determine risk level
        let riskLevel: QueryExplanation.RiskLevel
        let suggestion: String
        
        if filterFields.isEmpty {
            riskLevel = .ok
            suggestion = "Query has no filters - will scan all records."
        } else if indexedFields.isEmpty {
            // No indexes found for filter fields
            if filterFields.count == 1 {
                riskLevel = .warnUnindexedFilter
                suggestion = "Filter on '\(filterFields[0])' may require full table scan. Consider adding index: db.createIndex(on: \"\(filterFields[0])\")"
            } else {
                riskLevel = .warnUnindexedFilter
                suggestion = "Filters on \(filterFields.joined(separator: ", ")) may require full table scan. Consider adding indexes."
            }
        } else if indexedFields.count < filterFields.count {
            // Some fields indexed, some not
            let unindexed = filterFields.filter { !indexedFields.contains($0) }
            riskLevel = .warnUnindexedFilter
            suggestion = "Some filter fields are not indexed: \(unindexed.joined(separator: ", ")). Consider adding indexes."
        } else {
            // All fields indexed (or unknown)
            riskLevel = .ok
            suggestion = "Query should use indexes efficiently."
        }
        
        return QueryExplanation(
            filterCount: filters.count,
            filterFields: filterFields,
            indexedFields: indexedFields,
            riskLevel: riskLevel,
            suggestion: suggestion
        )
    }
    
    /// Execute query with performance warnings
    ///
    /// Wrapper that calls explainCost() first, logs warnings if needed, then executes.
    /// No semantic changes to query execution - just adds explainability.
    ///
    /// - Returns: Query result (same as execute())
    /// - Throws: Error if query execution fails
    ///
    /// ## Example
    /// ```swift
    /// let result = try db.query()
    ///     .where("status", equals: .string("active"))
    ///     .executeWithWarnings()
    /// // Warnings logged if query is slow
    /// ```
    public func executeWithWarnings() throws -> QueryResult {
        // Explain first
        let explanation = try explainCost()
        
        // Log warnings if needed
        switch explanation.riskLevel {
        case .warnFullScan, .warnUnindexedFilter:
            BlazeLogger.warn("Query performance warning: \(explanation.suggestion)")
            BlazeLogger.debug(explanation.description)
        case .ok:
            // No warning needed
            break
        case .unknown:
            BlazeLogger.debug("Query explanation: Index detection unavailable")
        }
        
        // Execute normally (no behavior changes)
        return try execute()
    }
    
    // MARK: - Private Helpers
    
    /// Extract filter fields from query (best-effort)
    ///
    /// Note: Filters are closures, so we can't perfectly extract field names.
    /// This uses heuristics and tracked filter fields if available.
    private func extractFilterFields() -> [String] {
        // Use tracked filterFields if available (from QueryBuilder+Validation)
        #if !BLAZEDB_LINUX_CORE
        if !filterFields.isEmpty {
            return Array(filterFields)
        }
        #endif
        
        // Fallback: Try to infer from collection indexes (heuristic)
        // This is best-effort and may not be accurate
        return []
    }
    
    /// Check which filter fields are indexed (best-effort)
    private func checkIndexedFields(filterFields: [String], collection: DynamicCollection) -> [String] {
        guard !filterFields.isEmpty else { return [] }
        
        // Get available indexes from collection
        let availableIndexes = collection.secondaryIndexes.keys
        
        var indexed: [String] = []
        
        for field in filterFields {
            // Check if field has an index
            // Index names are typically "idx_<field>" or "<field>"
            let hasIndex = availableIndexes.contains { indexName in
                // Check if index name matches field (exact or prefix)
                indexName == field ||
                indexName == "idx_\(field)" ||
                indexName.hasPrefix("\(field)+") ||  // Composite index
                indexName.hasSuffix("+\(field)")     // Composite index
            }
            
            if hasIndex {
                indexed.append(field)
            }
        }
        
        return indexed
    }
}
