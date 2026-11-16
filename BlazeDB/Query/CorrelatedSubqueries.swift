//
//  CorrelatedSubqueries.swift
//  BlazeDB
//
//  Correlated subqueries (subqueries that reference outer query)
//  Optimized with caching and lazy evaluation
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
            
            // Cache by type and full value. String(int) collides with the
            // string "1", and ISO8601 drops subsecond precision, so two
            // different correlation values were sharing one subquery result.
            let cacheKey = Self.correlatedSubqueryCacheKey(correlationValue)
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

    /// Identity for the per-query correlation cache. Equal values must share a
    /// key, and values that are not equal must not.
    fileprivate static func correlatedSubqueryCacheKey(_ value: BlazeDocumentField) -> String {
        switch value {
        case .string(let v):
            return "s:\(v.utf8.count):\(v)"
        case .int(let v):
            return "i:\(v)"
        case .double(let v):
            return "d:\(v.bitPattern)"
        case .bool(let v):
            return "b:\(v ? 1 : 0)"
        case .uuid(let v):
            return "u:\(v.uuidString)"
        case .date(let v):
            return "t:\(v.timeIntervalSinceReferenceDate.bitPattern)"
        case .data(let v):
            return "D:\(v.base64EncodedString())"
        case .null:
            return "n"
        case .vector(let v):
            return "v:\(v.map { String($0.bitPattern) }.joined(separator: ","))"
        case .array(let items):
            return "a:[\(items.map { correlatedSubqueryCacheKey($0) }.joined(separator: "|"))]"
        case .dictionary(let fields):
            let parts = fields.keys.sorted().map { key in
                "\(key.utf8.count):\(key)=\(correlatedSubqueryCacheKey(fields[key] ?? .null))"
            }
            return "m:{\(parts.joined(separator: "|"))}"
        }
    }
    
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

