//
//  DynamicCollection+Optimized.swift
//  BlazeDB
//
//  Optimized fetch and filter methods
//
#if !BLAZEDB_LINUX_CORE

import Foundation

extension DynamicCollection {
    
    // MARK: - Fetch All Cache
    
    /// Cache keyed by DynamicCollection.instanceID (UUID) instead of ObjectIdentifier.
    /// ObjectIdentifier uses the memory address which can be reused after deallocation,
    /// causing stale cache hits when a new collection lands at the same address.
    nonisolated(unsafe) private static var fetchAllCache: [UUID: ([BlazeDataRecord], Date)] = [:]
    private static let cacheLock = NSLock()
    private static let cacheMaxAge: TimeInterval = 5.0  // 5 seconds

    /// Clear fetchAll cache for this instance (called after writes)
    internal func clearFetchAllCache() {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        Self.fetchAllCache.removeValue(forKey: instanceID)
    }

    /// Clear all fetchAll caches globally (used in tests to prevent cross-test leakage)
    internal static func clearAllFetchAllCaches() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        fetchAllCache.removeAll()
    }

    /// Get cached fetchAll result if available
    private func getCachedFetchAll() -> [BlazeDataRecord]? {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        guard let (records, timestamp) = Self.fetchAllCache[instanceID],
              Date().timeIntervalSince(timestamp) < Self.cacheMaxAge else {
            return nil
        }
        return records
    }

    /// Cache fetchAll result
    private func setCachedFetchAll(_ records: [BlazeDataRecord]) {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        Self.fetchAllCache[instanceID] = (records, Date())
    }
    
    // MARK: - Optimized Fetch All
    
    /// Optimized fetchAll with caching and batch fetching
    internal func _fetchAllOptimized() throws -> [BlazeDataRecord] {
        // Check cache first
        if let cached = getCachedFetchAll() {
            return cached
        }

        // Fetch records and cache the result inside the queue.sync block
        // to prevent a stale cache write racing with insertBatch's clearFetchAllCache().
        let records = try queue.sync {
            // Double-check cache (another thread may have populated it while we waited)
            if let cached = getCachedFetchAll() {
                return cached
            }
            let result = try _fetchAllNoSync()
            setCachedFetchAll(result)
            return result
        }

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
