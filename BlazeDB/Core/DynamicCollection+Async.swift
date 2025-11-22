//
//  DynamicCollection+Async.swift
//  BlazeDB
//
//  True async/await operations for DynamicCollection
//  Provides non-blocking, concurrent operations with query caching and operation pooling
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation

// MARK: - Query Cache

/// Caches query results for faster repeated queries (actor-based for async safety)
private actor AsyncQueryCache {
    private var cache: [String: (results: [BlazeDataRecord], timestamp: Date)] = [:]
    private let maxCacheSize: Int
    private let cacheTTL: TimeInterval
    
    init(maxCacheSize: Int = 1000, cacheTTL: TimeInterval = 60.0) {
        self.maxCacheSize = maxCacheSize
        self.cacheTTL = cacheTTL
    }
    
    func get(key: String) -> [BlazeDataRecord]? {
        guard let entry = cache[key] else { return nil }
        
        // Check if expired
        if Date().timeIntervalSince(entry.timestamp) > cacheTTL {
            cache.removeValue(forKey: key)
            return nil
        }
        
        return entry.results
    }
    
    func set(key: String, results: [BlazeDataRecord]) {
        // Evict oldest if cache is full
        if cache.count >= maxCacheSize {
            let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key
            if let oldestKey = oldestKey {
                cache.removeValue(forKey: oldestKey)
            }
        }
        
        cache[key] = (results: results, timestamp: Date())
    }
    
    func invalidate() {
        cache.removeAll()
    }
    
    func invalidate(pattern: String) {
        cache = cache.filter { !$0.key.contains(pattern) }
    }
}

// MARK: - Operation Pool

/// Manages concurrent operations with limits
private actor OperationPool {
    private var activeOperations: Int = 0
    private let maxConcurrentOperations: Int
    private var waitingOperations: [CheckedContinuation<Void, Never>] = []
    
    init(maxConcurrentOperations: Int = 100) {
        self.maxConcurrentOperations = maxConcurrentOperations
    }
    
    func acquire() async {
        if activeOperations < maxConcurrentOperations {
            activeOperations += 1
            return
        }
        
        // Wait for slot to become available
        await withCheckedContinuation { continuation in
            waitingOperations.append(continuation)
        }
        
        activeOperations += 1
    }
    
    func release() {
        // CRITICAL: Prevent underflow - ensure activeOperations never goes negative
        // This can happen if release() is called more times than acquire() (e.g., error paths)
        if activeOperations > 0 {
            activeOperations -= 1
            
            // CRITICAL: Only wake up waiting operations when a slot is actually freed
            // Waking up operations without freeing a slot causes resource exhaustion
            // and incorrect concurrency behavior
            if !waitingOperations.isEmpty {
                let continuation = waitingOperations.removeFirst()
                continuation.resume()
            }
        } else {
            BlazeLogger.warn("⚠️ OperationPool.release() called when activeOperations is already 0 (possible double-release)")
            // Don't wake up waiting operations - no slot was freed
        }
    }
    
    var currentLoad: Int {
        activeOperations
    }
}

// MARK: - DynamicCollection Async Extension

extension DynamicCollection {
    
    // MARK: - Async Infrastructure
    
    private static var queryCaches: [ObjectIdentifier: AsyncQueryCache] = [:]
    private static var operationPools: [ObjectIdentifier: OperationPool] = [:]
    private static let cacheLock = NSLock()
    
    private var queryCache: AsyncQueryCache {
        let id = ObjectIdentifier(self)
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        
        if let cache = Self.queryCaches[id] {
            return cache
        }
        
        let cache = AsyncQueryCache(maxCacheSize: 1000, cacheTTL: 60.0)
        Self.queryCaches[id] = cache
        return cache
    }
    
    private var operationPool: OperationPool {
        let id = ObjectIdentifier(self)
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        
        if let pool = Self.operationPools[id] {
            return pool
        }
        
        let pool = OperationPool(maxConcurrentOperations: 100)
        Self.operationPools[id] = pool
        return pool
    }
    
    // MARK: - Async Insert
    
    /// Insert a record asynchronously (non-blocking)
    public func insertAsync(_ data: BlazeDataRecord) async throws -> UUID {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Wrapping release() in a Task doesn't guarantee it completes before function returns
        // This causes resource leaks where pool slots are never released
        // Use do-catch pattern to ensure release happens before return
        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                return try self.insert(data)
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return result
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    /// Insert multiple records asynchronously (non-blocking, parallel)
    public func insertBatchAsync(_ records: [BlazeDataRecord]) async throws -> [UUID] {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                return try self.insertBatch(records)
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return result
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    // MARK: - Async Fetch
    
    /// Fetch a record by ID asynchronously (non-blocking)
    public func fetchAsync(id: UUID) async throws -> BlazeDataRecord? {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                return try self.fetch(id: id)
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return result
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    /// Fetch all records asynchronously (non-blocking)
    public func fetchAllAsync() async throws -> [BlazeDataRecord] {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                return try self.fetchAll()
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return result
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    /// Fetch all record IDs asynchronously (non-blocking, much faster than fetchAllAsync)
    public func fetchAllIDsAsync() async throws -> [UUID] {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                return try self.fetchAllIDs()
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return result
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    /// Fetch a page of records asynchronously (non-blocking)
    public func fetchPageAsync(offset: Int, limit: Int) async throws -> [BlazeDataRecord] {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                return try self.fetchPage(offset: offset, limit: limit)
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return result
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    // MARK: - Async Update
    
    /// Update a record asynchronously (non-blocking)
    public func updateAsync(id: UUID, with data: BlazeDataRecord) async throws {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            // Invalidate entire query cache since we can't know which queries might be affected
            await queryCache.invalidate()
            
            try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                try self.update(id: id, with: data)
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    // MARK: - Async Delete
    
    /// Delete a record asynchronously (non-blocking)
    public func deleteAsync(id: UUID) async throws {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            // Invalidate entire query cache since we can't know which queries might be affected
            await queryCache.invalidate()
            
            try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                try self.delete(id: id)
            }.value
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    // MARK: - Async Query with Caching
    
    /// Execute a query asynchronously with caching
    public func queryAsync(
        where field: String? = nil,
        equals value: BlazeDocumentField? = nil,
        orderBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil,
        useCache: Bool = true
    ) async throws -> [BlazeDataRecord] {
        await operationPool.acquire()
        // CRITICAL: Ensure release is called before returning, not in a background Task
        // Use do-catch pattern to ensure release happens before return
        do {
            // Generate cache key
            let valueStr: String
            if let value = value {
                valueStr = value.serializedString()
            } else {
                valueStr = "none"
            }
            let cacheKey = "query:\(field ?? "all"):\(valueStr):\(orderBy ?? "none"):\(descending):\(limit ?? -1)"
            
            // Check cache
            if useCache, let cached = await queryCache.get(key: cacheKey) {
                // CRITICAL: Release before returning cached result
                await operationPool.release()
                return cached
            }
            
            // Execute query
            let results = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    throw BlazeDBError.transactionFailed("Collection deallocated")
                }
                
                let queryBuilder: QueryBuilder = self.query()
                var query = queryBuilder
                
                if let field = field, let value = value {
                    query = query.where(field, equals: value)
                }
                
                if let orderBy = orderBy {
                    query = query.orderBy(orderBy, descending: descending)
                }
                
                if let limit = limit {
                    query = query.limit(limit)
                }
                
                let result = try query.execute()
                // Extract records from QueryResult
                switch result {
                case .records(let records):
                    return records
                case .joined(let joined):
                    return joined.map { $0.left }
                case .aggregation, .grouped, .search:
                    // Aggregations and search not supported in simple queryAsync
                    throw BlazeDBError.invalidQuery(reason: "Aggregation/search queries not supported in queryAsync. Use query().execute() directly.")
                }
            }.value
            
            // Cache results
            if useCache {
                await queryCache.set(key: cacheKey, results: results)
            }
            
            // CRITICAL: Release before returning to ensure pool slot is freed immediately
            await operationPool.release()
            return results
        } catch {
            // CRITICAL: Release on error to prevent resource leak
            await operationPool.release()
            throw error
        }
    }
    
    // MARK: - Cache Management
    
    /// Invalidate query cache
    public func invalidateQueryCache() async {
        await queryCache.invalidate()
    }
    
    /// Get current operation pool load
    public func getOperationPoolLoad() async -> Int {
        await operationPool.currentLoad
    }
    
    // MARK: - Static Cleanup (for testing)
    
    /// Clean up async resources for a specific DynamicCollection instance
    /// Called from deinit to prevent memory leaks
    internal static func cleanupAsyncResources(for id: ObjectIdentifier) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        // Remove query cache (allows actor to be deallocated)
        queryCaches.removeValue(forKey: id)
        
        // Remove operation pool (allows actor to be deallocated)
        operationPools.removeValue(forKey: id)
        
        BlazeLogger.debug("🧹 Cleaned up async resources for DynamicCollection \(id)")
    }
    
    /// Clear all async query caches and operation pools (for test isolation)
    /// This should be called in test tearDown to prevent test interference
    /// Note: This clears the dictionaries, which will cause caches to be recreated on next use
    public static func clearAllAsyncCaches() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        // Clear all query caches (removing from dictionary allows them to be deallocated)
        queryCaches.removeAll()
        
        // Clear all operation pools (they don't need explicit cleanup, but we clear the dictionary)
        operationPools.removeAll()
    }
}

