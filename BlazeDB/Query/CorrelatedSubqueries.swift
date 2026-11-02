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
            
            // Cache by type-tagged value. Display strings alias .int(1) with
            // .string("1"), and second-resolution ISO8601 aliases distinct dates.
            let cacheKey = self.correlationCacheKey(correlationValue)
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
            
            // Snapshot first. `subquery.subquery` is a class, and `where` appends
            // to it. Running that on the shared builder ANDs every outer correlation
            // value together, so the second distinct key matches nothing.
            guard let correlatedQuery = self.correlatedSnapshot(of: subquery, correlationValue: correlationValue),
                  let result = try? correlatedQuery.execute().records,
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
            
            guard let correlatedQuery = self.correlatedSnapshot(of: subquery, correlationValue: correlationValue),
                  let result = try? correlatedQuery.execute().records,
                  let subqueryValue = result.first?.storage[field] else {
                return false
            }
            
            guard let fieldValue = outerRecord.storage[field] else {
                return false
            }
            
            return fieldValue == subqueryValue
        }
    }

    /// A fresh builder with the subquery's execution state plus one correlation
    /// predicate. Does not mutate `subquery.subquery`.
    private func correlatedSnapshot(
        of subquery: CorrelatedSubquery,
        correlationValue: BlazeDocumentField
    ) -> QueryBuilder? {
        guard let collection = subquery.subquery.collection else { return nil }
        let snapshot = QueryBuilder(collection: collection)
        snapshot.filters = subquery.subquery.filters
        snapshot.joinOperations = subquery.subquery.joinOperations
        snapshot.sortOperations = subquery.subquery.sortOperations
        snapshot.limitValue = subquery.subquery.limitValue
        snapshot.offsetValue = subquery.subquery.offsetValue
        snapshot.groupByFields = subquery.subquery.groupByFields
        snapshot.aggregations = subquery.subquery.aggregations
        snapshot.havingPredicate = subquery.subquery.havingPredicate
        snapshot.`where`(subquery.subqueryField, equals: correlationValue)
        return snapshot
    }

    private func correlationCacheKey(_ value: BlazeDocumentField) -> String {
        switch value {
        case .string(let v):
            return "s\(v.utf8.count):\(v)"
        case .int(let v):
            return "i\(v)"
        case .double(let v):
            return "d\(v.bitPattern)"
        case .bool(let v):
            return v ? "b1" : "b0"
        case .uuid(let v):
            return "u\(v.uuidString)"
        case .date(let v):
            return "t\(v.timeIntervalSince1970.bitPattern)"
        case .data(let v):
            return "D\(v.base64EncodedString())"
        case .array(let items):
            return "a\(items.count)[\(items.map { correlationCacheKey($0) }.joined(separator: ","))]"
        case .dictionary(let dict):
            let parts = dict.keys.sorted().map { key in
                "\(key.count):\(key)=\(correlationCacheKey(dict[key] ?? .null))"
            }
            return "m\(parts.joined(separator: "|"))"
        case .vector(let values):
            return "v\(values.map { String($0.bitPattern) }.joined(separator: ","))"
        case .null:
            return "n"
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

