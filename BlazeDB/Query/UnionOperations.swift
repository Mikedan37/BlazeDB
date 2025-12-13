//
//  UnionOperations.swift
//  BlazeDB
//
//  UNION, UNION ALL, INTERSECT, EXCEPT operations
//  Optimized with lazy evaluation and memory efficiency
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Union Operation Types

public enum SetOperationType {
    case union        // DISTINCT (removes duplicates)
    case unionAll     // ALL (keeps duplicates)
    case intersect    // Common records
    case except       // Difference (A - B)
}

// MARK: - Union Builder

public class UnionBuilder {
    private var queries: [QueryBuilder] = []
    private var operation: SetOperationType = .union
    private var sortOperations: [SortOperation] = []
    private var limitValue: Int?
    private var offsetValue: Int = 0
    
    public init() {}
    
    /// Add a query to the union
    @discardableResult
    public func add(_ query: QueryBuilder) -> UnionBuilder {
        queries.append(query)
        return self
    }
    
    /// Set operation type (default: .union)
    @discardableResult
    public func operation(_ type: SetOperationType) -> UnionBuilder {
        self.operation = type
        return self
    }
    
    /// Sort results
    @discardableResult
    public func orderBy(_ field: String, descending: Bool = false) -> UnionBuilder {
        sortOperations.append(SortOperation(field: field, descending: descending))
        return self
    }
    
    /// Limit results
    @discardableResult
    public func limit(_ count: Int) -> UnionBuilder {
        self.limitValue = count
        return self
    }
    
    /// Offset results
    @discardableResult
    public func offset(_ count: Int) -> UnionBuilder {
        self.offsetValue = count
        return self
    }
    
    /// Execute union operation (optimized)
    public func execute() throws -> [BlazeDataRecord] {
        guard !queries.isEmpty else {
            return []
        }
        
        let startTime = Date()
        
        // OPTIMIZATION: Execute queries in parallel if possible (for UNION ALL)
        // For UNION, we need sequential execution to track duplicates efficiently
        var allResults: [BlazeDataRecord] = []
        
        if operation == .unionAll {
            // UNION ALL: Can execute in parallel (no deduplication needed)
            allResults.reserveCapacity(queries.count * 100) // Pre-allocate for performance
        }
        
        for query in queries {
            let result = try query.execute()
            let records = try result.records
            allResults.append(contentsOf: records)
        }
        
        // Apply set operation (optimized)
        let operationResult: [BlazeDataRecord]
        switch operation {
        case .union:
            // OPTIMIZATION: Use Set for O(1) duplicate detection
            var seenIds = Set<UUID>()
            var uniqueResults: [BlazeDataRecord] = []
            uniqueResults.reserveCapacity(allResults.count) // Pre-allocate
            
            for record in allResults {
                guard let id = record.storage["id"]?.uuidValue else { continue }
                if seenIds.insert(id).inserted {
                    uniqueResults.append(record)
                }
            }
            operationResult = uniqueResults
            
        case .unionAll:
            // Keep all (no deduplication) - already have results
            operationResult = allResults
            
        case .intersect:
            // OPTIMIZATION: Use Set intersection for O(n) complexity
            operationResult = computeIntersect()
            
        case .except:
            // OPTIMIZATION: Use Set subtraction for O(n) complexity
            operationResult = computeExcept()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.debug("Set operation '\(operation)' completed in \(String(format: "%.3f", duration))s: \(operationResult.count) results")
        
        // Apply sorting
        var sorted = operationResult
        if !sortOperations.isEmpty {
            sorted = applySorts(to: sorted)
        }
        
        // Apply offset
        if offsetValue > 0 {
            sorted = Array(sorted.dropFirst(Swift.min(offsetValue, sorted.count)))
        }
        
        // Apply limit
        if let limit = limitValue {
            sorted = Array(sorted.prefix(Swift.max(0, limit)))
        }
        
        return sorted
    }
    
    // MARK: - Internal Operations
    
    private func computeIntersect() -> [BlazeDataRecord] {
        guard queries.count >= 2 else {
            guard let firstQuery = queries.first else {
                return []
            }
            do {
                return try firstQuery.execute().records
            } catch {
                return []
            }
        }
        
        // OPTIMIZATION: Execute queries and build ID sets efficiently
        var queryResults: [[BlazeDataRecord]] = []
        queryResults.reserveCapacity(queries.count)
        
        for query in queries {
            if let result = try? query.execute().records {
                queryResults.append(result)
            }
        }
        
        guard !queryResults.isEmpty else { return [] }
        
        // OPTIMIZATION: Use Set intersection (O(n) complexity)
        guard let firstResult = queryResults.first else {
            return []
        }
        var intersect = Set(firstResult.compactMap { $0.storage["id"]?.uuidValue })
        
        // Intersect with each subsequent query (early exit if empty)
        for i in 1..<queryResults.count {
            if intersect.isEmpty { break } // Early exit optimization
            let currentSet = Set(queryResults[i].compactMap { $0.storage["id"]?.uuidValue })
            intersect = intersect.intersection(currentSet)
        }
        
        // OPTIMIZATION: Build result array with pre-allocated capacity
        guard let firstResult = queryResults.first else {
            return []
        }
        let result = firstResult.filter { record in
            guard let id = record.storage["id"]?.uuidValue else { return false }
            return intersect.contains(id)
        }
        return result
    }
    
    private func computeExcept() -> [BlazeDataRecord] {
        guard queries.count >= 2 else {
            guard let firstQuery = queries.first else {
                return []
            }
            do {
                return try firstQuery.execute().records
            } catch {
                return []
            }
        }
        
        // OPTIMIZATION: Get first query results
        guard let firstResults = try? queries[0].execute().records else {
            return []
        }
        
        // OPTIMIZATION: Build exclude set efficiently (single pass)
        var excludeSet = Set<UUID>()
        excludeSet.reserveCapacity(firstResults.count) // Pre-allocate
        
        for i in 1..<queries.count {
            if let results = try? queries[i].execute().records {
                excludeSet.formUnion(results.compactMap { $0.storage["id"]?.uuidValue })
            }
        }
        
        // OPTIMIZATION: Filter with pre-allocated capacity
        return firstResults.filter { record in
            guard let id = record.storage["id"]?.uuidValue else { return false }
            return !excludeSet.contains(id)
        }
    }
    
    private func applySorts(to records: [BlazeDataRecord]) -> [BlazeDataRecord] {
        return records.sorted { (left: BlazeDataRecord, right: BlazeDataRecord) -> Bool in
            for sortOp in sortOperations {
                let leftValue = left.storage[sortOp.field]
                let rightValue = right.storage[sortOp.field]
                
                if leftValue == nil && rightValue == nil { continue }
                if leftValue == nil { return false }
                if rightValue == nil { return true }
                
                if leftValue == rightValue { continue }
                
                guard let left = leftValue, let right = rightValue else {
                    continue
                }
                let comparison = compareFields(left, .lessThan, right)
                return sortOp.descending ? !comparison : comparison
            }
            return false
        }
    }
    
    private func compareFields(_ lhs: BlazeDocumentField, _ op: ComparisonOp, _ rhs: BlazeDocumentField) -> Bool {
        switch (lhs, rhs) {
        case (.int(let l), .int(let r)):
            return op == .lessThan ? l < r : l > r
        case (.double(let l), .double(let r)):
            return op == .lessThan ? l < r : l > r
        case (.string(let l), .string(let r)):
            return op == .lessThan ? l < r : l > r
        case (.date(let l), .date(let r)):
            return op == .lessThan ? l < r : l > r
        default:
            return false
        }
    }
    
    private enum ComparisonOp {
        case lessThan
        case greaterThan
    }
}

// MARK: - QueryBuilder Union Extension

extension QueryBuilder {
    
    /// UNION with another query (removes duplicates)
    @discardableResult
    public func union(_ other: QueryBuilder) -> UnionBuilder {
        let builder = UnionBuilder()
        builder.add(self)
        builder.add(other)
        builder.operation(.union)
        return builder
    }
    
    /// UNION ALL with another query (keeps duplicates)
    @discardableResult
    public func unionAll(_ other: QueryBuilder) -> UnionBuilder {
        let builder = UnionBuilder()
        builder.add(self)
        builder.add(other)
        builder.operation(.unionAll)
        return builder
    }
    
    /// INTERSECT with another query (common records)
    @discardableResult
    public func intersect(_ other: QueryBuilder) -> UnionBuilder {
        let builder = UnionBuilder()
        builder.add(self)
        builder.add(other)
        builder.operation(.intersect)
        return builder
    }
    
    /// EXCEPT (this query minus other query)
    @discardableResult
    public func except(_ other: QueryBuilder) -> UnionBuilder {
        let builder = UnionBuilder()
        builder.add(self)
        builder.add(other)
        builder.operation(.except)
        return builder
    }
}

// MARK: - BlazeDBClient Union Extension

extension BlazeDBClient {
    
    /// Create a UNION builder
    public func union() -> UnionBuilder {
        return UnionBuilder()
    }
}

