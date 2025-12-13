//
//  CorrelatedSubqueries.swift
//  BlazeDB
//
//  Correlated subqueries (subqueries that reference outer query)
//  Optimized with caching and lazy evaluation
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Correlated Subquery

public struct CorrelatedSubquery {
    public let subquery: QueryBuilder
    public let correlationField: String  // Field in outer query
    public let subqueryField: String    // Field in subquery to match
    
    public init(subquery: QueryBuilder, correlationField: String, subqueryField: String) {
        self.subquery = subquery
        self.correlationField = correlationField
        self.subqueryField = subqueryField
    }
}

// MARK: - QueryBuilder Correlated Subquery Extension

extension QueryBuilder {
    
    /// WHERE field > (SELECT field FROM ... WHERE correlation_field = outer.correlation_field)
    @discardableResult
    public func `where`(_ field: String, greaterThanCorrelated subquery: CorrelatedSubquery) -> QueryBuilder {
        // OPTIMIZATION: Cache subquery results per correlation value
        var subqueryCache: [String: BlazeDocumentField?] = [:]
        
        return `where` { outerRecord in
            guard let correlationValue = outerRecord.storage[subquery.correlationField] else {
                return false
            }
            
            // OPTIMIZATION: Check cache first
            let cacheKey: String
            switch correlationValue {
            case .string(let v): cacheKey = v
            case .int(let v): cacheKey = String(v)
            case .double(let v): cacheKey = String(v)
            case .uuid(let v): cacheKey = v.uuidString
            case .date(let v): cacheKey = ISO8601DateFormatter().string(from: v)
            default: cacheKey = String(describing: correlationValue)
            }
            if let cachedValue = subqueryCache[cacheKey] {
                guard let subqueryValue = cachedValue,
                      let fieldValue = outerRecord.storage[field] else {
                    return false
                }
                return self.compareFields(fieldValue, subqueryValue, isGreaterThan: true)
            }
            
            // Build subquery with correlation
            guard let subqueryCollection = subquery.subquery.collection else {
                return false
            }
            let correlatedQuery = QueryBuilder(collection: subqueryCollection)
            // Copy filters from original subquery
            for filter in subquery.subquery.filters {
                correlatedQuery.filters.append(filter)
            }
            correlatedQuery.`where`(subquery.subqueryField, equals: correlationValue)
            
            // Execute subquery
            guard let result = try? correlatedQuery.execute().records,
                  let subqueryValue = result.first?.storage[field] else {
                subqueryCache[cacheKey] = nil
                return false
            }
            
            // OPTIMIZATION: Cache result
            subqueryCache[cacheKey] = subqueryValue
            
            // Compare
            guard let fieldValue = outerRecord.storage[field] else {
                return false
            }
            
            return self.compareFields(fieldValue, subqueryValue, isGreaterThan: true)
        }
    }
    
    /// WHERE field < (SELECT field FROM ... WHERE correlation_field = outer.correlation_field)
    @discardableResult
    public func `where`(_ field: String, lessThanCorrelated subquery: CorrelatedSubquery) -> QueryBuilder {
        return `where` { outerRecord in
            guard let correlationValue = outerRecord.storage[subquery.correlationField] else {
                return false
            }
            
            let correlatedQuery = subquery.subquery
            correlatedQuery.`where`(subquery.subqueryField, equals: correlationValue)
            
            guard let result = try? correlatedQuery.execute().records,
                  let subqueryValue = result.first?.storage[field] else {
                return false
            }
            
            guard let fieldValue = outerRecord.storage[field] else {
                return false
            }
            
            return self.compareFields(fieldValue, subqueryValue, isLessThan: true)
        }
    }
    
    /// WHERE field = (SELECT field FROM ... WHERE correlation_field = outer.correlation_field)
    @discardableResult
    public func `where`(_ field: String, equalsCorrelated subquery: CorrelatedSubquery) -> QueryBuilder {
        return `where` { outerRecord in
            guard let correlationValue = outerRecord.storage[subquery.correlationField] else {
                return false
            }
            
            let correlatedQuery = subquery.subquery
            correlatedQuery.`where`(subquery.subqueryField, equals: correlationValue)
            
            guard let result = try? correlatedQuery.execute().records,
                  let subqueryValue = result.first?.storage[field] else {
                return false
            }
            
            guard let fieldValue = outerRecord.storage[field] else {
                return false
            }
            
            return fieldValue == subqueryValue
        }
    }
    
    // MARK: - Helper
    
    private func compareFields(_ f1: BlazeDocumentField, _ f2: BlazeDocumentField, isGreaterThan: Bool) -> Bool {
        switch (f1, f2) {
        case (.int(let v1), .int(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        case (.double(let v1), .double(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        case (.string(let v1), .string(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        case (.date(let v1), .date(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        default:
            return false
        }
    }
    
    private func compareFields(_ f1: BlazeDocumentField, _ f2: BlazeDocumentField, isLessThan: Bool) -> Bool {
        return compareFields(f1, f2, isGreaterThan: !isLessThan)
    }
}

