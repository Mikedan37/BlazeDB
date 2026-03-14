//
//  LazyQueryIterator.swift
//  BlazeDB
//
//  True lazy query execution - fetches records on-demand without
//  loading entire result set into memory.
//
//  Created by BlazeDB Architecture Sprint.
//

import Foundation

/// Lazy query iterator that fetches records on-demand
/// This provides true lazy execution - records are only read from
/// storage as they are consumed, minimizing memory usage.
public final class LazyQueryIterator: IteratorProtocol, Sequence {
    public typealias Element = BlazeDataRecord
    
    private let collection: DynamicCollection
    private let filters: [(BlazeDataRecord) -> Bool]
    private let limit: Int?
    private let sortKey: String?
    private let sortAscending: Bool
    
    private var allIDs: [UUID]
    private var currentIndex: Int = 0
    private var emittedCount: Int = 0
    private var exhausted: Bool = false
    
    internal init(
        collection: DynamicCollection,
        filters: [(BlazeDataRecord) -> Bool],
        limit: Int?,
        sortKey: String?,
        sortAscending: Bool
    ) {
        self.collection = collection
        self.filters = filters
        self.limit = limit
        self.sortKey = sortKey
        self.sortAscending = sortAscending
        
        // Get all record IDs from the collection
        // For truly lazy execution with sorting, we need all IDs upfront
        // For unsorted queries, we could potentially stream IDs as well
        self.allIDs = Array(collection.indexMap.keys)
        
        // If sorting is required, we need to sort IDs first
        // This requires reading all records (not fully lazy, but necessary for sorting)
        if sortKey != nil {
            sortIDsLazily()
        }
    }
    
    private func sortIDsLazily() {
        guard let sortKey = sortKey else { return }
        
        // Load sort keys without full record decode
        var idWithSortValue: [(UUID, BlazeDocumentField?)] = []
        
        for id in allIDs {
            if let record = try? collection.fetch(id: id) {
                idWithSortValue.append((id, record.storage[sortKey]))
            } else {
                idWithSortValue.append((id, nil))
            }
        }
        
        // Sort by the sort key
        idWithSortValue.sort { lhs, rhs in
            guard let lVal = lhs.1, let rVal = rhs.1 else {
                return lhs.1 != nil  // nil values last
            }
            
            return compareFields(lVal, rVal, ascending: sortAscending)
        }
        
        allIDs = idWithSortValue.map { $0.0 }
    }
    
    private func compareFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField, ascending: Bool) -> Bool {
        let result: Bool
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)):
            result = a < b
        case (.double(let a), .double(let b)):
            result = a < b
        case (.string(let a), .string(let b)):
            result = a < b
        case (.date(let a), .date(let b)):
            result = a < b
        case (.bool(let a), .bool(let b)):
            result = !a && b
        default:
            result = false
        }
        return ascending ? result : !result
    }
    
    /// Get the next record that matches all filters
    public func next() -> BlazeDataRecord? {
        // Check if we've hit the limit
        if let limit = limit, emittedCount >= limit {
            exhausted = true
            return nil
        }
        
        // Iterate through IDs and find next matching record
        while currentIndex < allIDs.count {
            let id = allIDs[currentIndex]
            currentIndex += 1
            
            // Lazy load the record
            guard let record = try? collection.fetch(id: id) else {
                continue
            }
            
            // Apply filters
            var matches = true
            for filter in filters {
                if !filter(record) {
                    matches = false
                    break
                }
            }
            
            if matches {
                emittedCount += 1
                return record
            }
        }
        
        exhausted = true
        return nil
    }
    
    /// Reset the iterator to start from the beginning
    public func reset() {
        currentIndex = 0
        emittedCount = 0
        exhausted = false
    }
    
    /// Check if there might be more records
    public var hasMore: Bool {
        return !exhausted
    }
    
    /// Total number of records that could potentially match (before filtering)
    public var potentialCount: Int {
        return allIDs.count
    }
    
    /// Number of records emitted so far
    public var currentCount: Int {
        return emittedCount
    }
    
    // MARK: - Sequence conformance
    
    public func makeIterator() -> LazyQueryIterator {
        return self
    }
    
    // MARK: - Convenience methods
    
    /// Take up to n records
    public func take(_ n: Int) -> [BlazeDataRecord] {
        var results: [BlazeDataRecord] = []
        results.reserveCapacity(n)
        
        for _ in 0..<n {
            guard let record = next() else { break }
            results.append(record)
        }
        
        return results
    }
    
    /// Skip n records
    @discardableResult
    public func skip(_ n: Int) -> LazyQueryIterator {
        for _ in 0..<n {
            _ = next()
        }
        return self
    }
    
    /// Collect all remaining records into an array
    public func collect() -> [BlazeDataRecord] {
        var results: [BlazeDataRecord] = []
        while let record = next() {
            results.append(record)
        }
        return results
    }
    
    /// Process each record with a closure
    public func forEach(_ body: (BlazeDataRecord) throws -> Void) rethrows {
        while let record = next() {
            try body(record)
        }
    }
    
    /// Find first record matching a predicate
    public func first(where predicate: (BlazeDataRecord) -> Bool) -> BlazeDataRecord? {
        while let record = next() {
            if predicate(record) {
                return record
            }
        }
        return nil
    }
    
    /// Map records lazily
    public func map<T>(_ transform: @escaping (BlazeDataRecord) -> T) -> LazyMapSequence<LazyQueryIterator, T> {
        reset()
        return self.lazy.map(transform)
    }
    
    /// Filter records lazily (adds to existing filters)
    public func filter(_ isIncluded: @escaping (BlazeDataRecord) -> Bool) -> LazyFilterSequence<LazyQueryIterator> {
        reset()
        return self.lazy.filter(isIncluded)
    }
}

// MARK: - QueryBuilder Extension for Lazy Execution

extension QueryBuilder {
    
    /// Execute query lazily - records are fetched on-demand
    /// 
    /// This is more memory-efficient than `execute()` for large result sets
    /// because records are only loaded from storage as they are consumed.
    ///
    /// ## Example
    /// ```swift
    /// let iterator = try db.query()
    ///     .where("status", equals: .string("active"))
    ///     .lazy()
    ///
    /// // Process records one at a time
    /// for record in iterator {
    ///     process(record)
    /// }
    ///
    /// // Or take just what you need
    /// let first10 = iterator.take(10)
    /// ```
    ///
    /// - Returns: A lazy iterator for on-demand record fetching
    /// - Throws: BlazeDBError.invalidData if collection is deallocated
    public func lazy() throws -> LazyQueryIterator {
        guard let collection = collection else {
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        // Get first sort operation if any
        let firstSort = sortOperations.first
        
        return LazyQueryIterator(
            collection: collection,
            filters: filters,
            limit: limitValue,
            sortKey: firstSort?.field,
            sortAscending: !(firstSort?.descending ?? false)
        )
    }
    
    /// Execute query lazily and process each record
    /// Memory-efficient for large datasets - only one record in memory at a time
    ///
    /// - Parameter handler: Closure called for each matching record
    /// - Throws: BlazeDBError if collection is not available
    public func forEachLazy(_ handler: (BlazeDataRecord) throws -> Void) throws {
        try lazy().forEach(handler)
    }
    
    /// Execute query lazily and take first n records
    /// More efficient than `execute().records.prefix(n)` for large datasets
    ///
    /// - Parameter n: Maximum number of records to return
    /// - Returns: Up to n matching records
    /// - Throws: BlazeDBError if collection is not available
    public func takeLazy(_ n: Int) throws -> [BlazeDataRecord] {
        return try lazy().take(n)
    }
    
    /// Execute query lazily and find first matching record
    /// Stops as soon as first match is found
    ///
    /// - Returns: First matching record, or nil if none found
    /// - Throws: BlazeDBError if collection is not available
    public func firstLazy() throws -> BlazeDataRecord? {
        return try lazy().next()
    }
}

