//  QuerySubqueries.swift
//  BlazeDB
//  Created by Michael Danylchuk on 1/7/25.

import Foundation

// MARK: - Subquery Support

/// Represents a subquery that can be used in WHERE clauses
public struct Subquery {
    let builder: QueryBuilder
    let field: String
    
    internal init(builder: QueryBuilder, field: String) {
        self.builder = builder
        self.field = field
    }
    
    /// Execute subquery and return field values
    func executeForValues() throws -> [BlazeDocumentField] {
        let result = try builder.execute()
        let records = try result.records
        return records.compactMap { $0.storage[field] }
    }
    
    /// Execute subquery and return record IDs
    func executeForIDs() throws -> [UUID] {
        let result = try builder.execute()
        let records = try result.records
        return records.compactMap { $0.storage["id"]?.uuidValue }
    }
}

// MARK: - QueryBuilder Subquery Extension

extension QueryBuilder {
    /// Create a subquery for use in WHERE IN clauses
    /// - Parameter field: Field to extract from subquery results
    /// - Returns: Subquery that can be used with whereIn()
    public func asSubquery(extracting field: String = "id") -> Subquery {
        BlazeLogger.debug("Creating subquery for field '\(field)'")
        return Subquery(builder: self, field: field)
    }
    
    /// Filter where field value is in subquery results
    /// - Parameters:
    ///   - field: Field name to check
    ///   - subquery: Subquery that returns values to match
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func `where`(_ field: String, inSubquery subquery: Subquery) throws -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) IN (subquery)")
        
        // Execute subquery to get values
        let subqueryValues = try subquery.executeForValues()
        
        // Add as IN filter
        return self.where(field, in: subqueryValues)
    }
    
    /// Filter where record ID is in subquery results
    /// - Parameter subquery: Subquery that returns record IDs
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func whereIDInSubquery(_ subquery: Subquery) throws -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE id IN (subquery)")
        
        // Execute subquery to get IDs
        let subqueryIDs = try subquery.executeForIDs()
        
        // Convert to UUID set for efficient lookup
        let idSet = Set(subqueryIDs)
        
        // Add as filter
        filters.append { record in
            guard let id = record.storage["id"]?.uuidValue else { return false }
            return idSet.contains(id)
        }
        
        return self
    }
    
    /// Filter where field value is NOT in subquery results
    @discardableResult
    public func `where`(_ field: String, notInSubquery subquery: Subquery) throws -> QueryBuilder {
        BlazeLogger.debug("Query: WHERE \(field) NOT IN (subquery)")
        
        let subqueryValues = try subquery.executeForValues()
        let valueSet = Set(subqueryValues)
        
        filters.append { record in
            guard let fieldValue = record.storage[field] else { return false }
            return !valueSet.contains(fieldValue)
        }
        
        return self
    }
}

