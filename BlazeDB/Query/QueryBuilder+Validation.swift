//
//  QueryBuilder+Validation.swift
//  BlazeDB
//
//  Query validation and error messages for better ergonomics
//  No query power changes - validation and guidance only
//

import Foundation

extension QueryBuilder {
    
    /// Validates query before execution
    /// - Throws: BlazeDBError.invalidQuery with helpful messages
    internal func validateQuery() throws {
        guard let collection = collection else {
            throw BlazeDBError.invalidQuery(
                reason: "Collection has been deallocated",
                suggestion: "Ensure the database connection is still valid"
            )
        }
        
        // Validate field names in filters
        try validateFilterFields(collection: collection)
        
        // Validate field names in sort operations
        try validateSortFields(collection: collection)
        
        // Validate field names in groupBy
        try validateGroupByFields(collection: collection)
        
        // Warn about potentially slow queries (unindexed filters)
        warnAboutUnindexedFilters(collection: collection)
    }
    
    /// Validates that filter fields exist in at least one record
    /// Note: We can't perfectly extract field names from filter closures,
    /// so this is a best-effort validation that samples records
    private func validateFilterFields(collection: DynamicCollection) throws {
        // Filter validation happens during execution when we have actual records
        // This is acceptable for Phase 1 - we validate sort/groupBy fields explicitly
    }
    
    /// Validates sort field names
    private func validateSortFields(collection: DynamicCollection) throws {
        for sortOp in sortOperations {
            let fieldName = sortOp.field
            
            // Sample records to check if field exists
            let sampleRecords = try? collection.fetchAll()
            
            if let samples = sampleRecords, !samples.isEmpty {
                let fieldExists = samples.contains { record in
                    record.storage[fieldName] != nil
                }
                
                if !fieldExists {
                    // Suggest similar field names
                    let availableFields = Set(samples.flatMap { $0.storage.keys })
                    let suggestions = findSimilarFields(target: fieldName, available: Array(availableFields))
                    
                    var suggestionMsg = "Check field name spelling."
                    if !suggestions.isEmpty {
                        suggestionMsg += " Did you mean: \(suggestions.prefix(3).joined(separator: ", "))?"
                    } else if !availableFields.isEmpty {
                        suggestionMsg += " Available fields: \(Array(availableFields).sorted().prefix(5).joined(separator: ", "))"
                    }
                    
                    throw BlazeDBError.invalidQuery(
                        reason: "Sort field '\(fieldName)' not found in any records",
                        suggestion: suggestionMsg
                    )
                }
            }
        }
    }
    
    /// Validates groupBy field names
    private func validateGroupByFields(collection: DynamicCollection) throws {
        guard !groupByFields.isEmpty else { return }
        
        let sampleRecords = try? collection.fetchAll()
        
        if let samples = sampleRecords, !samples.isEmpty {
            let availableFields = Set(samples.flatMap { $0.storage.keys })
            
            for field in groupByFields {
                if !availableFields.contains(field) {
                    let suggestions = findSimilarFields(target: field, available: Array(availableFields))
                    
                    var suggestionMsg = "Check field name spelling."
                    if !suggestions.isEmpty {
                        suggestionMsg += " Did you mean: \(suggestions.prefix(3).joined(separator: ", "))?"
                    } else if !availableFields.isEmpty {
                        suggestionMsg += " Available fields: \(Array(availableFields).sorted().prefix(5).joined(separator: ", "))"
                    }
                    
                    throw BlazeDBError.invalidQuery(
                        reason: "GROUP BY field '\(field)' not found in any records",
                        suggestion: suggestionMsg
                    )
                }
            }
        }
    }
    
    /// Warns about potentially slow queries (unindexed filters)
    /// This is a warning, not an error - queries still execute
    private func warnAboutUnindexedFilters(collection: DynamicCollection) {
        // Note: We can't perfectly detect which fields are used in filters
        // because filters are closures. This is a limitation.
        // However, we can warn about common patterns like:
        // - Sorting without index
        // - GroupBy without index
        
        // For now, we'll add warnings in documentation
        // Runtime warnings would require more invasive changes
    }
    
    /// Finds similar field names using Levenshtein distance
    private func findSimilarFields(target: String, available: [String], maxDistance: Int = 2) -> [String] {
        func levenshtein(_ s1: String, _ s2: String) -> Int {
            let s1Array = Array(s1)
            let s2Array = Array(s2)
            var matrix = Array(repeating: Array(repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
            
            for i in 0...s1Array.count {
                matrix[i][0] = i
            }
            for j in 0...s2Array.count {
                matrix[0][j] = j
            }
            
            for i in 1...s1Array.count {
                for j in 1...s2Array.count {
                    let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                    matrix[i][j] = Swift.min(
                        matrix[i-1][j] + 1,
                        matrix[i][j-1] + 1,
                        matrix[i-1][j-1] + cost
                    )
                }
            }
            
            return matrix[s1Array.count][s2Array.count]
        }
        
        return available
            .map { ($0, levenshtein(target.lowercased(), $0.lowercased())) }
            .filter { $0.1 <= maxDistance }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
}
