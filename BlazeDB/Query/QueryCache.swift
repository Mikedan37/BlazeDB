//  QueryCache.swift
//  BlazeDB
//  Created by Michael Danylchuk on 1/7/25.

import Foundation

// MARK: - Query Cache

/// In-memory cache for query results with TTL support
public final class QueryCache {
    /// Singleton instance
    nonisolated(unsafe) public static let shared = QueryCache()
    
    /// Cache entry with expiration
    private struct CacheEntry {
        let result: Any
        let expiresAt: Date
        
        var isExpired: Bool {
            return Date() > expiresAt
        }
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private var enabled: Bool = true
    
    private init() {}
    
    /// Enable or disable caching globally
    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            enabled = newValue
            if !newValue {
                cache.removeAll()
                BlazeLogger.info("Query cache disabled and cleared")
            }
        }
    }
    
    /// Get cached result for a query key
    func get<T>(key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }
        
        guard enabled else { return nil }
        
        guard let entry = cache[key] else {
            BlazeLogger.trace("Cache miss for key: \(key)")
            return nil
        }
        
        if entry.isExpired {
            cache.removeValue(forKey: key)
            BlazeLogger.trace("Cache expired for key: \(key)")
            return nil
        }
        
        BlazeLogger.debug("Cache hit for key: \(key)")
        return entry.result as? T
    }
    
    /// Store result in cache with TTL
    func set<T>(key: String, value: T, ttl: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        
        guard enabled else { return }
        
        let expiresAt = Date().addingTimeInterval(ttl)
        cache[key] = CacheEntry(result: value, expiresAt: expiresAt)
        BlazeLogger.debug("Cached result for key: \(key) (TTL: \(ttl)s)")
    }
    
    /// Invalidate specific cache key
    public func invalidate(key: String) {
        lock.lock()
        defer { lock.unlock()}
        
        cache.removeValue(forKey: key)
        BlazeLogger.debug("Invalidated cache for key: \(key)")
    }
    
    /// Invalidate all cache entries matching a prefix
    public func invalidatePrefix(_ prefix: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let keysToRemove = cache.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        BlazeLogger.info("Invalidated \(keysToRemove.count) cache entries with prefix: \(prefix)")
    }
    
    /// Clear all cache entries
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        
        let count = cache.count
        cache.removeAll()
        BlazeLogger.info("Cleared \(count) cache entries")
    }
    
    /// Get cache statistics
    public func stats() -> (entries: Int, expired: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        let expired = cache.values.filter { $0.isExpired }.count
        return (cache.count, expired)
    }
    
    /// Clean up expired entries
    public func cleanupExpired() {
        lock.lock()
        defer { lock.unlock() }
        
        let beforeCount = cache.count
        cache = cache.filter { !$0.value.isExpired }
        let cleaned = beforeCount - cache.count
        
        if cleaned > 0 {
            BlazeLogger.debug("Cleaned up \(cleaned) expired cache entries")
        }
    }
}

// MARK: - Query Builder Cache Extension

extension QueryBuilder {
    private var cacheKey: String {
        var components: [String] = []
        components.append("filters:\(filters.count)")
        components.append("joins:\(joinOperations.count)")
        components.append("sorts:\(sortOperations.count)")
        components.append("limit:\(limitValue ?? -1)")
        components.append("offset:\(offsetValue)")
        components.append("groupBy:\(groupByFields.joined(separator:","))")
        components.append("aggs:\(aggregations.count)")
        return components.joined(separator:"|")
    }
    
    /// Execute query with caching (deprecated - use execute(withCache:))
    /// - Parameter ttl: Time-to-live in seconds (default: 60)
    /// - Returns: Cached or fresh results
    @available(*, deprecated, message: "Use execute(withCache:) which returns QueryResult")
    public func executeWithCache(ttl: TimeInterval = 60) throws -> [BlazeDataRecord] {
        let key = cacheKey
        
        // Check cache first
        if let cached: [BlazeDataRecord] = QueryCache.shared.get(key: key) {
            BlazeLogger.info("Returning cached query results (\(cached.count) records)")
            return cached
        }
        
        // Cache miss - execute query
        BlazeLogger.debug("Cache miss, executing query")
        let result = try execute()
        let records = try result.records
        
        // Store in cache
        QueryCache.shared.set(key: key, value: records, ttl: ttl)
        
        return records
    }
    
    /// Execute grouped aggregation with caching
    /// - Parameter ttl: Time-to-live in seconds (default: 60)
    /// - Returns: Cached or fresh aggregation results
    public func executeGroupedAggregationWithCache(ttl: TimeInterval = 60) throws -> GroupedAggregationResult {
        let key = "grouped_agg:" + cacheKey
        
        if let cached: GroupedAggregationResult = QueryCache.shared.get(key: key) {
            BlazeLogger.info("Returning cached aggregation results (\(cached.groups.count) groups)")
            return cached
        }
        
        BlazeLogger.debug("Cache miss, executing grouped aggregation")
        let results = try executeGroupedAggregation()
        
        QueryCache.shared.set(key: key, value: results, ttl: ttl)
        
        return results
    }
}

