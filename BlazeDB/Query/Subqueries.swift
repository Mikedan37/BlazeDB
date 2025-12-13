//
//  Subqueries.swift
//  BlazeDB
//
//  EXISTS and NOT EXISTS subquery support
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Subquery Types

public enum SubqueryType {
    case exists(QueryBuilder)
    case notExists(QueryBuilder)
    case inSubquery(QueryBuilder, field: String)
    case notInSubquery(QueryBuilder, field: String)
}

// MARK: - QueryBuilder Subquery Extension

extension QueryBuilder {
    
    /// WHERE EXISTS (subquery)
    @discardableResult
    public func whereExists(_ subquery: QueryBuilder) -> QueryBuilder {
        return `where` { record in
            // Execute subquery and check if any results match
            do {
                let subqueryResults = try subquery.execute()
                let records = try subqueryResults.records
                // Check if any subquery result matches this record
                // This is a simplified EXISTS - in real SQL, it would check correlation
                return !records.isEmpty
            } catch {
                return false
            }
        }
    }
    
    /// WHERE NOT EXISTS (subquery)
    @discardableResult
    public func whereNotExists(_ subquery: QueryBuilder) -> QueryBuilder {
        return `where` { record in
            do {
                let subqueryResults = try subquery.execute()
                let records = try subqueryResults.records
                return records.isEmpty
            } catch {
                return true
            }
        }
    }
    
    /// WHERE field IN (subquery)
    @discardableResult
    public func whereIn(_ field: String, subquery: QueryBuilder) -> QueryBuilder {
        return `where` { record in
            guard let fieldValue = record.storage[field] else { return false }
            do {
                let subqueryResults = try subquery.execute()
                let records = try subqueryResults.records
                // Check if field value exists in subquery results
                return records.contains { subRecord in
                    // Check if any field in subquery matches
                    return subRecord.storage.values.contains { $0 == fieldValue }
                }
            } catch {
                return false
            }
        }
    }
    
    /// WHERE field NOT IN (subquery)
    @discardableResult
    public func whereNotIn(_ field: String, subquery: QueryBuilder) -> QueryBuilder {
        return `where` { record in
            guard let fieldValue = record.storage[field] else { return true }
            do {
                let subqueryResults = try subquery.execute()
                let records = try subqueryResults.records
                // Check if field value does NOT exist in subquery results
                return !records.contains { subRecord in
                    return subRecord.storage.values.contains { $0 == fieldValue }
                }
            } catch {
                return true
            }
        }
    }
}

