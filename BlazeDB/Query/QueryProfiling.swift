//
//  QueryProfiling.swift
//  BlazeDB
//
//  Query performance profiling and slow query detection
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Query Profile Data

/// Detailed performance profile for a query execution
public struct QueryProfile: Identifiable {
    public let id: UUID
    public let query: String
    public let executionTime: TimeInterval
    public let recordsScanned: Int
    public let recordsReturned: Int
    public let indexUsed: String?
    public let cacheHit: Bool
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        query: String,
        executionTime: TimeInterval,
        recordsScanned: Int,
        recordsReturned: Int,
        indexUsed: String?,
        cacheHit: Bool,
        timestamp: Date
    ) {
        self.id = id
        self.query = query
        self.executionTime = executionTime
        self.recordsScanned = recordsScanned
        self.recordsReturned = recordsReturned
        self.indexUsed = indexUsed
        self.cacheHit = cacheHit
        self.timestamp = timestamp
    }
    
    public var isSlowQuery: Bool {
        return executionTime > 0.1  // > 100ms
    }
    
    public var description: String {
        var result = """
        Query Profile:
          Query: \(query)
          Time: \(String(format: "%.3f", executionTime))s
          Scanned: \(recordsScanned) records
          Returned: \(recordsReturned) records
          Index: \(indexUsed ?? "none (full scan)")
          Cached: \(cacheHit ? "yes" : "no")
          Timestamp: \(timestamp.formatted())
        """
        
        if isSlowQuery {
            result += "\n  ⚠️  SLOW QUERY (> 100ms)"
        }
        
        return result
    }
}

// MARK: - Query Statistics

/// Aggregate query statistics
public struct QueryStatistics {
    public let totalQueries: Int
    public let slowQueries: Int
    public let cacheHits: Int
    public let averageExecutionTime: TimeInterval
    public let totalExecutionTime: TimeInterval
    
    public var cacheHitRate: Double {
        guard totalQueries > 0 else { return 0 }
        return Double(cacheHits) / Double(totalQueries)
    }
    
    public var description: String {
        """
        Query Statistics:
          Total queries: \(totalQueries)
          Slow queries: \(slowQueries) (\(slowQueries * 100 / max(totalQueries, 1))%)
          Cache hits: \(cacheHits) (\(String(format: "%.1f", cacheHitRate * 100))%)
          Avg time: \(String(format: "%.3f", averageExecutionTime))s
          Total time: \(String(format: "%.2f", totalExecutionTime))s
        """
    }
}

// MARK: - Query Profiler

/// Global query profiling manager
public final class QueryProfiler {
    // Swift 6: Protected by NSLock, safe for concurrent access
    nonisolated(unsafe) public static let shared = QueryProfiler()
    
    private var profiles: [QueryProfile] = []
    private let lock = NSLock()
    private var enabled: Bool = false
    private let maxProfiles = 1000  // Keep last 1000 queries
    
    private init() {}
    
    /// Enable query profiling
    public func enable() {
        lock.lock()
        enabled = true
        profiles.removeAll()
        lock.unlock()
        
        BlazeLogger.info("📊 Query profiling enabled")
    }
    
    /// Disable query profiling
    public func disable() {
        lock.lock()
        enabled = false
        lock.unlock()
        
        BlazeLogger.info("📊 Query profiling disabled")
    }
    
    /// Check if profiling is enabled
    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }
    
    /// Record a query execution
    internal func record(profile: QueryProfile) {
        lock.lock()
        defer { lock.unlock() }
        
        guard enabled else { return }
        
        profiles.append(profile)
        
        // Keep only last N profiles
        if profiles.count > maxProfiles {
            profiles.removeFirst(profiles.count - maxProfiles)
        }
        
        if profile.isSlowQuery {
            BlazeLogger.warn("⚠️  Slow query detected: \(String(format: "%.3f", profile.executionTime))s - \(profile.query)")
        } else {
            BlazeLogger.trace("Query profiled: \(String(format: "%.3f", profile.executionTime))s")
        }
    }
    
    /// Get slow queries (execution time > threshold)
    ///
    /// - Parameter threshold: Minimum execution time (default 0.1s = 100ms)
    /// - Returns: Array of slow query profiles, sorted by execution time
    ///
    /// ## Example
    /// ```swift
    /// QueryProfiler.shared.enable()
    ///
    /// // ... run queries ...
    ///
    /// let slowQueries = QueryProfiler.shared.getSlowQueries(threshold: 0.1)
    /// for query in slowQueries {
    ///     print("Slow: \(query.description)")
    /// }
    /// ```
    public func getSlowQueries(threshold: TimeInterval = 0.1) -> [QueryProfile] {
        lock.lock()
        defer { lock.unlock() }
        
        return profiles.filter { $0.executionTime > threshold }
            .sorted { $0.executionTime > $1.executionTime }  // Slowest first
    }
    
    /// Get all recorded profiles
    public func getAllProfiles() -> [QueryProfile] {
        lock.lock()
        defer { lock.unlock() }
        return profiles
    }
    
    /// Get aggregate statistics
    public func getStatistics() -> QueryStatistics {
        lock.lock()
        defer { lock.unlock() }
        
        let totalQueries = profiles.count
        let slowQueries = profiles.filter { $0.isSlowQuery }.count
        let cacheHits = profiles.filter { $0.cacheHit }.count
        let totalTime = profiles.reduce(0.0) { $0 + $1.executionTime }
        let avgTime = totalQueries > 0 ? totalTime / Double(totalQueries) : 0
        
        return QueryStatistics(
            totalQueries: totalQueries,
            slowQueries: slowQueries,
            cacheHits: cacheHits,
            averageExecutionTime: avgTime,
            totalExecutionTime: totalTime
        )
    }
    
    /// Clear all recorded profiles
    public func clear() {
        lock.lock()
        profiles.removeAll()
        lock.unlock()
        
        BlazeLogger.debug("📊 Query profiles cleared")
    }
    
    /// Get profiling report
    public func getReport() -> String {
        let stats = getStatistics()
        let slowQueries = getSlowQueries(threshold: 0.1)
        
        var report = """
        📊 QUERY PROFILING REPORT
        ═══════════════════════════════════════
        
        \(stats.description)
        
        """
        
        if slowQueries.isEmpty {
            report += "\n✅ No slow queries detected!"
        } else {
            report += "\n⚠️  SLOW QUERIES (\(slowQueries.count)):\n"
            for (index, query) in slowQueries.prefix(10).enumerated() {
                report += "\n\(index + 1). \(String(format: "%.3f", query.executionTime))s - \(query.query)"
                if let index = query.indexUsed {
                    report += "\n   Index: \(index)"
                } else {
                    report += "\n   ⚠️  NO INDEX (full scan)"
                }
            }
        }
        
        return report
    }
}

// MARK: - BlazeDBClient Profiling Extension

extension BlazeDBClient {
    
    /// Enable query profiling for this database
    ///
    /// Tracks all query executions and provides performance insights.
    ///
    /// ## Example
    /// ```swift
    /// db.enableProfiling()
    ///
    /// // Run queries...
    /// try await db.query().where("status", equals: .string("open")).execute()
    ///
    /// // Get report
    /// let report = db.getProfilingReport()
    /// print(report)
    /// ```
    public func enableProfiling() {
        QueryProfiler.shared.enable()
        BlazeLogger.info("📊 Profiling enabled for '\(name)'")
    }
    
    /// Disable query profiling
    public func disableProfiling() {
        QueryProfiler.shared.disable()
        BlazeLogger.info("📊 Profiling disabled for '\(name)'")
    }
    
    /// Get slow queries for this database
    ///
    /// - Parameter threshold: Minimum execution time (default 0.1s)
    /// - Returns: Array of slow query profiles
    public func getSlowQueries(threshold: TimeInterval = 0.1) -> [QueryProfile] {
        return QueryProfiler.shared.getSlowQueries(threshold: threshold)
    }
    
    /// Get query statistics
    public func getQueryStatistics() -> QueryStatistics {
        return QueryProfiler.shared.getStatistics()
    }
    
    /// Get profiling report as formatted string
    public func getProfilingReport() -> String {
        return QueryProfiler.shared.getReport()
    }
    
    /// Clear all profiling data
    public func clearProfilingData() {
        QueryProfiler.shared.clear()
    }
}

// MARK: - Query Builder Profiling Extension

extension QueryBuilder {
    
    /// Execute query with profiling
    ///
    /// - Returns: Query results
    /// - Throws: BlazeDBError if execution fails
    ///
    /// ## Example
    /// ```swift
    /// QueryProfiler.shared.enable()
    ///
    /// let results = try await db.query()
    ///     .where("status", equals: .string("open"))
    ///     .execute()  // Automatically profiled!
    ///
    /// let slowQueries = QueryProfiler.shared.getSlowQueries()
    /// ```
    func executeWithProfiling() throws -> [BlazeDataRecord] {
        guard QueryProfiler.shared.isEnabled else {
            // Profiling disabled, use normal execution
            return try self.execute().records
        }
        
        let startTime = Date()
        let queryDescription = "Query with \(filters.count) filters, \(joinOperations.count) joins"
        
        // Execute query
        let result = try self.execute()
        let records = try result.records
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Create profile
        // NOTE: Detailed query profiling metrics intentionally not fully implemented.
        // recordsScanned, indexUsed, and cacheHit require instrumentation throughout
        // the query execution pipeline, which adds overhead. Basic timing is provided.
        let profile = QueryProfile(
            query: queryDescription,
            executionTime: duration,
            recordsScanned: -1,  // Not tracked (requires execution instrumentation)
            recordsReturned: records.count,
            indexUsed: nil,  // Not tracked (requires planner instrumentation)
            cacheHit: false,  // Not tracked (requires cache instrumentation)
            timestamp: Date()
        )
        
        // Record profile
        QueryProfiler.shared.record(profile: profile)
        
        return records
    }
}

