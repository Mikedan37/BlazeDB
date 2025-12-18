//
//  OrderingIndex+Performance.swift
//  BlazeDB
//
//  Performance optimizations for ordering: index-based sorting, caching
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Sorted Index Cache

/// Cached sorted order for efficient repeated queries
internal final class OrderingIndexCache {
    private var cache: [String: [UUID]] = [:] // fieldName -> sorted UUIDs
    private var cacheTimestamps: [String: Date] = [:]
    private let lock = NSLock()
    private let ttl: TimeInterval = 60.0 // Cache for 60 seconds
    
    nonisolated(unsafe) static let shared = OrderingIndexCache()
    
    private init() {}
    
    /// Get cached sorted order
    func getSortedOrder(fieldName: String) -> [UUID]? {
        let key = cacheKey(for: fieldName)
        lock.lock()
        defer { lock.unlock() }
        
        guard let cached = cache[key],
              let timestamp = cacheTimestamps[key],
              Date().timeIntervalSince(timestamp) < ttl else {
            return nil
        }
        
        BlazeLogger.trace("OrderingIndexCache: cache HIT for field '\(fieldName)'")
        return cached
    }
    
    /// Store sorted order in cache
    func setSortedOrder(_ uuids: [UUID], fieldName: String) {
        let key = cacheKey(for: fieldName)
        lock.lock()
        defer { lock.unlock() }
        
        cache[key] = uuids
        cacheTimestamps[key] = Date()
        BlazeLogger.trace("OrderingIndexCache: cached \(uuids.count) UUIDs for field '\(fieldName)'")
    }
    
    /// Invalidate cache for a field
    func invalidate(fieldName: String) {
        let key = cacheKey(for: fieldName)
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeValue(forKey: key)
        cacheTimestamps.removeValue(forKey: key)
        BlazeLogger.debug("OrderingIndexCache: invalidated cache for field '\(fieldName)'")
    }
    
    /// Clear all caches
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        cacheTimestamps.removeAll()
        BlazeLogger.info("OrderingIndexCache: cleared all caches")
    }
    
    private func cacheKey(for fieldName: String) -> String {
        return "ordering_\(fieldName)"
    }
}

// MARK: - Index-Based Sorting (for large datasets)

extension OrderingIndex {
    /// Sort records using index-based approach (optimized for 1000+ records)
    /// - Parameters:
    ///   - records: Records to sort
    ///   - fieldName: Ordering field name
    /// - Returns: Sorted records
    internal static func sortWithIndex(
        _ records: [BlazeDataRecord],
        fieldName: String
    ) -> [BlazeDataRecord] {
        let startTime = Date()
        
        // For small datasets, use standard sort
        if records.count < 1000 {
            return sortStandard(records, fieldName: fieldName)
        }
        
        // For large datasets, use index-based approach
        BlazeLogger.debug("OrderingIndex.sortWithIndex: using index-based sort for \(records.count) records")
        
        // Build index map: index -> [records]
        var indexMap: [Double: [BlazeDataRecord]] = [:]
        var nilRecords: [BlazeDataRecord] = []
        
        for record in records {
            if let index = getIndex(from: record, fieldName: fieldName) {
                indexMap[index, default: []].append(record)
            } else {
                nilRecords.append(record)
            }
        }
        
        // Sort indices (ascending order)
        let sortedIndices = indexMap.keys.sorted()
        
        // Validate: Check for any duplicate indices (shouldn't happen but be safe)
        let duplicateCount = indexMap.values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count - 1 }
        if duplicateCount > 0 {
            BlazeLogger.warn("OrderingIndex.sortWithIndex: Found \(duplicateCount) records with duplicate indices (will use stable sort by ID)")
        }
        
        // Build result array
        var result: [BlazeDataRecord] = []
        result.reserveCapacity(records.count)
        
        for index in sortedIndices {
            guard let recordsWithSameIndex = indexMap[index] else {
                continue
            }
            // CRITICAL: Sort records with the same index by ID for stable ordering
            // This ensures deterministic results when multiple records have the same orderingIndex
            // Also handles edge cases where floating point precision might cause duplicates
            let sortedRecords = recordsWithSameIndex.sorted { (left, right) -> Bool in
                let leftID = left.storage["id"]?.uuidValue ?? UUID()
                let rightID = right.storage["id"]?.uuidValue ?? UUID()
                return leftID.uuidString < rightID.uuidString
            }
            result.append(contentsOf: sortedRecords)
        }
        
        // Append nil records at the end
        result.append(contentsOf: nilRecords)
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        BlazeLogger.debug("OrderingIndex.sortWithIndex: sorted \(records.count) records in \(String(format: "%.2f", duration))ms")
        
        // Debug: Verify first few records are sorted
        if result.count >= 2 {
            let firstIndex = getIndex(from: result[0], fieldName: fieldName)
            let secondIndex = getIndex(from: result[1], fieldName: fieldName)
            if let first = firstIndex, let second = secondIndex {
                if first >= second {
                    BlazeLogger.warn("OrderingIndex.sortWithIndex: WARNING - First two records not sorted correctly: \(first) >= \(second)")
                    // Log first 10 indices for debugging
                    let first10Indices = result.prefix(10).enumerated().map { (i, record) -> String in
                        let idx = getIndex(from: record, fieldName: fieldName)
                        let id = record.storage["id"]?.uuidValue?.uuidString.prefix(8) ?? "no-id"
                        return "[\(i)] idx=\(idx?.description ?? "nil"), id=\(id)"
                    }
                    BlazeLogger.warn("OrderingIndex.sortWithIndex: First 10 records: \(first10Indices.joined(separator: ", "))")
                    
                    // Also check for duplicate indices
                    var indexCounts: [Double: Int] = [:]
                    for record in result {
                        if let idx = getIndex(from: record, fieldName: fieldName) {
                            indexCounts[idx, default: 0] += 1
                        }
                    }
                    let duplicates = indexCounts.filter { $0.value > 1 }
                    if !duplicates.isEmpty {
                        let duplicateStrings = duplicates.keys.sorted().prefix(5).compactMap { key -> String? in
                            guard let count = indexCounts[key] else {
                                return nil
                            }
                            return "\(key):\(count)"
                        }
                        BlazeLogger.warn("OrderingIndex.sortWithIndex: Found \(duplicates.count) duplicate indices: \(duplicateStrings.joined(separator: ", "))")
                    }
                }
            } else {
                // Log if indices are missing
                if firstIndex == nil {
                    BlazeLogger.warn("OrderingIndex.sortWithIndex: First record missing orderingIndex field '\(fieldName)'")
                }
                if secondIndex == nil {
                    BlazeLogger.warn("OrderingIndex.sortWithIndex: Second record missing orderingIndex field '\(fieldName)'")
                }
            }
        }
        
        return result
    }
    
    /// Standard sorting (for small datasets)
    internal static func sortStandard(
        _ records: [BlazeDataRecord],
        fieldName: String
    ) -> [BlazeDataRecord] {
        return records.sorted { (left, right) -> Bool in
            let leftIndex = getIndex(from: left, fieldName: fieldName)
            let rightIndex = getIndex(from: right, fieldName: fieldName)
            
            if leftIndex == nil && rightIndex == nil { return false }
            if leftIndex == nil { return false }
            if rightIndex == nil { return true }
            
            return leftIndex! < rightIndex!
        }
    }
}

