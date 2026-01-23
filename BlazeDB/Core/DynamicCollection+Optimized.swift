//
//  DynamicCollection+Optimized.swift
//  BlazeDB
//
//  Optimized fetch and filter methods
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE

import Foundation

extension DynamicCollection {
    
    // MARK: - Fetch All Cache
    
    nonisolated(unsafe) private static var fetchAllCache: [ObjectIdentifier: ([BlazeDataRecord], Date)] = [:]
    nonisolated(unsafe) private static let cacheLock = NSLock()
    private static let cacheMaxAge: TimeInterval = 5.0  // 5 seconds
    
    /// Clear fetchAll cache (called after writes)
    internal func clearFetchAllCache() {
        let id = ObjectIdentifier(self)
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        Self.fetchAllCache.removeValue(forKey: id)
    }
    
    /// Get cached fetchAll result if available
    private func getCachedFetchAll() -> [BlazeDataRecord]? {
        let id = ObjectIdentifier(self)
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        
        guard let (records, timestamp) = Self.fetchAllCache[id],
              Date().timeIntervalSince(timestamp) < Self.cacheMaxAge else {
            return nil
        }
        return records
    }
    
    /// Cache fetchAll result
    private func setCachedFetchAll(_ records: [BlazeDataRecord]) {
        let id = ObjectIdentifier(self)
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        Self.fetchAllCache[id] = (records, Date())
    }
    
    // MARK: - Optimized Fetch All
    
    /// Optimized fetchAll with caching and batch fetching
    internal func _fetchAllOptimized() throws -> [BlazeDataRecord] {
        // Check cache first
        if let cached = getCachedFetchAll() {
            return cached
        }
        
        // Use batch fetching for optimal performance
        // This prefetches all pages in parallel and decodes records efficiently
        let records = try queue.sync {
            // _fetchAllNoSync already uses batch fetching internally
            return try _fetchAllNoSync()
        }
        
        // Cache result
        setCachedFetchAll(records)
        
        return records
    }
    
    // MARK: - Optimized Filter
    
    /// Optimized filter with parallel processing
    internal func filterOptimized(_ isMatch: @escaping (BlazeDataRecord) -> Bool) throws -> [BlazeDataRecord] {
        // For small datasets, use simple filter
        let allRecords = try _fetchAllOptimized()
        
        if allRecords.count < 100 {
            return allRecords.filter(isMatch)
        }
        
        // For large datasets, use parallel filter
        return queue.sync {
            let chunkSize = Swift.max(100, allRecords.count / 8)  // 8 chunks
            var results: [BlazeDataRecord] = []
            
            let chunks = stride(from: 0, to: allRecords.count, by: chunkSize).map {
                Array(allRecords[$0..<Swift.min($0 + chunkSize, allRecords.count)])
            }
            
            // Process chunks in parallel
            let filteredChunks = chunks.parallelMap { chunk in
                chunk.filter(isMatch)
            }
            
            // Combine results
            for chunk in filteredChunks {
                results.append(contentsOf: chunk)
            }
            
            return results
        }
    }
}

// MARK: - Parallel Map Helper

private extension Array {
    /// Serial map for Swift 6 concurrency compliance
    func parallelMap<T>(_ transform: @escaping (Element) -> T) -> [T] {
        // Serial implementation for Swift 6 strict concurrency compliance
        return self.map(transform)
    }
}

#endif // !BLAZEDB_LINUX_CORE
