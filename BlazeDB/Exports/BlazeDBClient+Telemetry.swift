//
//  BlazeDBClient+Telemetry.swift
//  BlazeDB
//
//  Telemetry integration with BlazeDBClient
//  Created by Michael Danylchuk on 11/12/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif

// MARK: - Telemetry Manager

/// Telemetry manager for a BlazeDBClient
public final class Telemetry {
    private let collector: MetricsCollector
    private weak var client: BlazeDBClient?
    
    init(client: BlazeDBClient) {
        self.client = client
        self.collector = MetricsCollector()
    }
    
    // MARK: - Configuration
    
    /// Enable telemetry tracking
    ///
    /// - Parameter samplingRate: Sampling rate (0.0-1.0). Default 0.01 (1%)
    ///
    /// ## Example
    /// ```swift
    /// // Enable with 1% sampling (low overhead)
    /// db.telemetry.enable(samplingRate: 0.01)
    ///
    /// // Enable with 100% sampling (for testing)
    /// db.telemetry.enable(samplingRate: 1.0)
    /// ```
    public func enable(samplingRate: Double = 0.01) {
        do {
            try collector.enable(samplingRate: samplingRate)
            BlazeLogger.info("📊 Telemetry enabled for '\(client?.name ?? "unknown")'")
        } catch {
            BlazeLogger.error("Failed to enable telemetry: \(error)")
        }
    }
    
    /// Disable telemetry tracking
    public func disable() {
        collector.disable()
    }
    
    /// Configure telemetry
    public func configure(_ config: TelemetryConfiguration) {
        collector.configure(config)
    }
    
    // MARK: - Recording (Internal)
    
    internal func record(
        operation: String,
        duration: Double,
        success: Bool,
        recordCount: Int? = nil,
        error: Error? = nil
    ) {
        guard let collectionName = client?.name else { return }
        
        collector.record(
            operation: operation,
            duration: duration,
            success: success,
            collectionName: collectionName,
            recordCount: recordCount,
            error: error
        )
    }
    
    // MARK: - Query APIs
    
    /// Get telemetry summary
    ///
    /// Shows performance stats, operation breakdown, and recent operations.
    ///
    /// ## Example
    /// ```swift
    /// let summary = try await db.telemetry.getSummary()
    /// print(summary.description)
    /// // Output:
    /// // Total Operations: 1,234
    /// // Average: 5.2ms ✅
    /// // Success Rate: 99.5%
    /// ```
    public func getSummary() async throws -> TelemetrySummary {
        return try await collector.getSummary()
    }
    
    /// Get slow operations above threshold
    ///
    /// - Parameter threshold: Duration threshold in milliseconds
    ///
    /// ## Example
    /// ```swift
    /// let slowOps = try await db.telemetry.getSlowOperations(threshold: 50)
    /// for op in slowOps {
    ///     print("SLOW: \(op.operation) took \(op.duration)ms")
    /// }
    /// ```
    public func getSlowOperations(threshold: Double) async throws -> [MetricEvent] {
        return try await collector.getSlowOperations(threshold: threshold)
    }
    
    /// Get recent errors
    ///
    /// - Parameter last: Number of recent errors to return
    ///
    /// ## Example
    /// ```swift
    /// let errors = try await db.telemetry.getErrors()
    /// for error in errors {
    ///     print("ERROR: \(error.operation) - \(error.errorMessage)")
    /// }
    /// ```
    public func getErrors(last: Int = 100) async throws -> [ErrorSummary] {
        return try await collector.getErrors(last: last)
    }
    
    /// Get operation breakdown
    ///
    /// Shows percentage and stats for each operation type.
    ///
    /// ## Example
    /// ```swift
    /// let breakdown = try await db.telemetry.getOperationBreakdown()
    /// print(breakdown.description)
    /// // Output:
    /// // queries: 80% (avg 5.2ms)
    /// // inserts: 15% (avg 3.1ms)
    /// ```
    public func getOperationBreakdown() async throws -> OperationBreakdown {
        return try await collector.getOperationBreakdown()
    }
    
    /// Get recent operations
    ///
    /// - Parameter limit: Number of recent operations to return
    ///
    /// ## Example
    /// ```swift
    /// let recent = try await db.telemetry.getRecentOperations(limit: 5)
    /// for op in recent {
    ///     print("\(op.operation): \(op.duration)ms")
    /// }
    /// ```
    public func getRecentOperations(limit: Int = 10) async throws -> [MetricEvent] {
        return try await collector.getRecentOperations(limit: limit)
    }
    
    // MARK: - Maintenance
    
    /// Clear all telemetry metrics
    ///
    /// ## Example
    /// ```swift
    /// try await db.telemetry.clear()
    /// print("Metrics cleared")
    /// ```
    public func clear() async throws {
        try await collector.clear()
    }
    
    /// Cleanup old metrics
    ///
    /// Deletes metrics older than retention period.
    ///
    /// ## Example
    /// ```swift
    /// let deleted = try await db.telemetry.cleanup()
    /// print("Deleted \(deleted) old metrics")
    /// ```
    @discardableResult
    public func cleanup() async throws -> Int {
        return try await collector.cleanup()
    }
    
    // MARK: - Convenience
    
    /// Print summary to console (for debugging)
    ///
    /// ## Example
    /// ```swift
    /// try await db.telemetry.printSummary()
    /// ```
    public func printSummary() async {
        do {
            let summary = try await getSummary()
            print(summary.description)
        } catch {
            print("Failed to get telemetry summary: \(error)")
        }
    }
}

// MARK: - BlazeDBClient Extension

extension BlazeDBClient {
    
    nonisolated(unsafe) private static var telemetryManagers: [String: Telemetry] = [:]
    private static let telemetryLock = NSLock()
    
    /// Telemetry manager for this database
    public var telemetry: Telemetry {
        let key = "\(name)-\(fileURL.path)"
        
        Self.telemetryLock.lock()
        defer { Self.telemetryLock.unlock() }
        
        if let existing = Self.telemetryManagers[key] {
            return existing
        }
        
        let manager = Telemetry(client: self)
        Self.telemetryManagers[key] = manager
        return manager
    }
    
    // MARK: - Tracked Operations
    
    /// Insert with telemetry tracking
    internal func insertTracked(_ data: BlazeDataRecord) async throws -> UUID {
        let start = Date()
        
        do {
            let id = try await insert(data)
            
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "insert", duration: duration, success: true, recordCount: 1)
            
            return id
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "insert", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Insert many with telemetry tracking
    internal func insertManyTracked(_ records: [BlazeDataRecord]) async throws -> [UUID] {
        let start = Date()
        
        do {
            let ids = try await insertMany(records)
            
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "insertMany", duration: duration, success: true, recordCount: ids.count)
            
            return ids
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "insertMany", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Fetch with telemetry tracking
    internal func fetchTracked(id: UUID) async throws -> BlazeDataRecord? {
        let start = Date()
        
        do {
            let record = try await fetch(id: id)
            
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "fetch", duration: duration, success: true, recordCount: record == nil ? 0 : 1)
            
            return record
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "fetch", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Fetch all with telemetry tracking
    internal func fetchAllTracked() async throws -> [BlazeDataRecord] {
        let start = Date()
        
        do {
            let records = try await fetchAll()
            
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "fetchAll", duration: duration, success: true, recordCount: records.count)
            
            return records
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "fetchAll", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Update with telemetry tracking
    internal func updateTracked(id: UUID, with fields: [String: BlazeDocumentField]) async throws {
        let start = Date()
        
        do {
            let record = BlazeDataRecord(fields)
            try await update(id: id, with: record)
            
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "update", duration: duration, success: true, recordCount: 1)
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "update", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Delete with telemetry tracking
    internal func deleteTracked(id: UUID) async throws {
        let start = Date()
        
        do {
            try await delete(id: id)
            
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "delete", duration: duration, success: true, recordCount: 1)
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            telemetry.record(operation: "delete", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
}

// MARK: - QueryBuilder Telemetry

extension QueryBuilder {
    /// Execute query with telemetry tracking
    internal func executeTracked() async throws -> QueryResult {
        let start = Date()
        
        do {
            let result = try await execute()
            
            let duration = Date().timeIntervalSince(start) * 1000
            // Note: Telemetry tracking would need access to collection's telemetry
            // For now, just execute without tracking
            
            return result
        } catch {
            let duration = Date().timeIntervalSince(start) * 1000
            // Note: Can't access telemetry from QueryBuilder directly
            throw error
        }
    }
}
#endif // !BLAZEDB_LINUX_CORE
