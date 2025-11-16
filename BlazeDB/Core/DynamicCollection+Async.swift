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

/// Caches query results for faster repeated queries
private actor QueryCache {
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
        activeOperations -= 1
        
        // Wake up next waiting operation
        if !waitingOperations.isEmpty {
            let continuation = waitingOperations.removeFirst()
            continuation.resume()
        }
    }
    
    var currentLoad: Int {
        activeOperations
    }
}

// MARK: - DynamicCollection Async Extension

extension DynamicCollection {
    
    // MARK: - Async Infrastructure
    
    private static var queryCaches: [ObjectIdentifier: QueryCache] = [:]
    private static var operationPools: [ObjectIdentifier: OperationPool] = [:]
    private static let cacheLock = NSLock()
    
    private var queryCache: QueryCache {
        let id = ObjectIdentifier(self)
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        
        if let cache = Self.queryCaches[id] {
            return cache
        }
        
        let cache = QueryCache(maxCacheSize: 1000, cacheTTL: 60.0)
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
        defer { await operationPool.release() }
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            return try self.insert(data)
        }.value
    }
    
    /// Insert multiple records asynchronously (non-blocking, parallel)
    public func insertBatchAsync(_ records: [BlazeDataRecord]) async throws -> [UUID] {
        await operationPool.acquire()
        defer { await operationPool.release() }
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            return try self.insertBatch(records)
        }.value
    }
    
    // MARK: - Async Fetch
    
    /// Fetch a record by ID asynchronously (non-blocking)
    public func fetchAsync(id: UUID) async throws -> BlazeDataRecord? {
        await operationPool.acquire()
        defer { await operationPool.release() }
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            return try self.fetch(id: id)
        }.value
    }
    
    /// Fetch all records asynchronously (non-blocking)
    public func fetchAllAsync() async throws -> [BlazeDataRecord] {
        await operationPool.acquire()
        defer { await operationPool.release() }
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            return try self.fetchAll()
        }.value
    }
    
    /// Fetch a page of records asynchronously (non-blocking)
    public func fetchPageAsync(offset: Int, limit: Int) async throws -> [BlazeDataRecord] {
        await operationPool.acquire()
        defer { await operationPool.release() }
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            return try self.fetchPage(offset: offset, limit: limit)
        }.value
    }
    
    // MARK: - Async Update
    
    /// Update a record asynchronously (non-blocking)
    public func updateAsync(id: UUID, with data: BlazeDataRecord) async throws {
        await operationPool.acquire()
        defer { await operationPool.release() }
        
        // Invalidate cache for this record
        await queryCache.invalidate(pattern: id.uuidString)
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            try self.update(id: id, with: data)
        }.value
    }
    
    // MARK: - Async Delete
    
    /// Delete a record asynchronously (non-blocking)
    public func deleteAsync(id: UUID) async throws {
        await operationPool.acquire()
        defer { await operationPool.release() }
        
        // Invalidate cache for this record
        await queryCache.invalidate(pattern: id.uuidString)
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            try self.delete(id: id)
        }.value
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
        defer { await operationPool.release() }
        
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
            return cached
        }
        
        // Execute query
        let results = try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw BlazeDBError.transactionFailed("Collection deallocated")
            }
            
            let queryBuilder = self.query()
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
        
        return results
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
}

