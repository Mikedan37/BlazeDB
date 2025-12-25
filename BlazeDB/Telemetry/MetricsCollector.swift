//
//  MetricsCollector.swift
//  BlazeDB
//
//  Collects and stores telemetry metrics
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Collects and stores performance metrics
/// Thread-safe via actor isolation
public actor MetricsCollector {
    private var config: TelemetryConfiguration
    private var metricsDB: BlazeDBClient?
    private var cleanupTask: Task<Void, Never>?
    
    /// Random number generator for sampling
    private let rng = SystemRandomNumberGenerator()
    
    init(config: TelemetryConfiguration = TelemetryConfiguration()) {
        self.config = config
    }
    
    deinit {
        cleanupTask?.cancel()
    }
    
    // MARK: - Configuration
    
    /// Enable telemetry
    func enable(samplingRate: Double = 0.01) throws {
        config.enabled = true
        config.samplingRate = samplingRate
        
        // Initialize metrics database
        if metricsDB == nil {
            // Create directory if needed
            let dir = config.metricsURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            
            metricsDB = try BlazeDBClient(
                name: "BlazeDB_Metrics",
                fileURL: config.metricsURL,
                password: "metrics-telemetry-blazedb"
            )
            
            // Create indexes for fast queries
            try? metricsDB?.collection.createIndex(on: "timestamp")
            try? metricsDB?.collection.createIndex(on: "operation")
            try? metricsDB?.collection.createIndex(on: "success")
            
            BlazeLogger.info("📊 Telemetry enabled (sampling: \(samplingRate * 100)%)")
        }
        
        // Start auto-cleanup if configured
        if config.autoCleanup {
            startAutoCleanup()
        }
    }
    
    /// Disable telemetry
    func disable() {
        config.enabled = false
        cleanupTask?.cancel()
        cleanupTask = nil
        
        BlazeLogger.info("📊 Telemetry disabled")
    }
    
    /// Update configuration
    func configure(_ newConfig: TelemetryConfiguration) {
        config = newConfig
    }
    
    // MARK: - Recording
    
    /// Record a metric event
    func record(
        operation: String,
        duration: Double,
        success: Bool,
        collectionName: String,
        recordCount: Int? = nil,
        error: Error? = nil
    ) {
        let isEnabled = config.enabled
        let samplingRate = config.samplingRate
        let slowThreshold = config.slowOperationThreshold
        let db = metricsDB
        
        guard isEnabled else { return }
        
        // Sampling: only record samplingRate% of operations
        if samplingRate < 1.0 {
            let random = Double.random(in: 0..<1)
            if random > samplingRate {
                return  // Skip this operation (not sampled)
            }
        }
        
        // Log slow operations
        if duration > slowThreshold {
            BlazeLogger.warn("⚠️  Slow operation: \(operation) on '\(collectionName)' took \(String(format: "%.2f", duration))ms")
        }
        
        // Create event
        let event = MetricEvent(
            operation: operation,
            duration: duration,
            success: success,
            collectionName: collectionName,
            recordCount: recordCount,
            errorMessage: error?.localizedDescription
        )
        
        // Store asynchronously (non-blocking)
        Task.detached {
            do {
                try await db?.insert(event.toRecord())
            } catch {
                BlazeLogger.error("Failed to record metric: \(error)")
            }
        }
    }
    
    // MARK: - Querying
    
    /// Get summary of all metrics
    func getSummary() async throws -> TelemetrySummary {
        guard let db = metricsDB else {
            throw BlazeDBError.invalidData(reason: "Telemetry not enabled")
        }
        
        // Fetch all metrics
        let allRecords = try await db.fetchAll()
        let events = try allRecords.compactMap { try? MetricEvent.from(record: $0) }
        
        guard !events.isEmpty else {
            // Empty summary
            return TelemetrySummary(
                totalOperations: 0,
                successRate: 0,
                avgDuration: 0,
                p50Duration: 0,
                p95Duration: 0,
                p99Duration: 0,
                errorCount: 0,
                operationBreakdown: [:],
                recentOperations: []
            )
        }
        
        // Calculate metrics
        let total = events.count
        let successCount = events.filter { $0.success }.count
        let successRate = (Double(successCount) / Double(total)) * 100
        
        let durations = events.map { $0.duration }.sorted()
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let p50Duration = percentile(durations, 0.50)
        let p95Duration = percentile(durations, 0.95)
        let p99Duration = percentile(durations, 0.99)
        
        let errorCount = events.filter { !$0.success }.count
        
        // Operation breakdown
        var breakdown: [String: Int] = [:]
        for event in events {
            breakdown[event.operation, default: 0] += 1
        }
        
        // Recent operations (last 10)
        let recent = events.sorted { $0.timestamp > $1.timestamp }.prefix(10)
        
        return TelemetrySummary(
            totalOperations: total,
            successRate: successRate,
            avgDuration: avgDuration,
            p50Duration: p50Duration,
            p95Duration: p95Duration,
            p99Duration: p99Duration,
            errorCount: errorCount,
            operationBreakdown: breakdown,
            recentOperations: Array(recent)
        )
    }
    
    /// Get slow operations
    func getSlowOperations(threshold: Double) async throws -> [MetricEvent] {
        guard let db = metricsDB else {
            throw BlazeDBError.invalidData(reason: "Telemetry not enabled")
        }
        
        let allRecords = try await db.fetchAll()
        let events = try allRecords.compactMap { try? MetricEvent.from(record: $0) }
        
        return events
            .filter { $0.duration > threshold }
            .sorted { $0.duration > $1.duration }
    }
    
    /// Get errors
    func getErrors(last: Int = 100) async throws -> [ErrorSummary] {
        guard let db = metricsDB else {
            throw BlazeDBError.invalidData(reason: "Telemetry not enabled")
        }
        
        let allRecords = try await db.fetchAll()
        let events = try allRecords.compactMap { try? MetricEvent.from(record: $0) }
        
        return events
            .filter { !$0.success }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(last)
            .map { ErrorSummary(
                operation: $0.operation,
                errorMessage: $0.errorMessage ?? "Unknown error",
                timestamp: $0.timestamp,
                duration: $0.duration
            )}
    }
    
    /// Get operation breakdown
    func getOperationBreakdown() async throws -> OperationBreakdown {
        guard let db = metricsDB else {
            throw BlazeDBError.invalidData(reason: "Telemetry not enabled")
        }
        
        let allRecords = try await db.fetchAll()
        let events = try allRecords.compactMap { try? MetricEvent.from(record: $0) }
        
        guard !events.isEmpty else {
            return OperationBreakdown(operations: [:])
        }
        
        var stats: [String: (count: Int, totalDuration: Double)] = [:]
        
        for event in events {
            let current = stats[event.operation, default: (0, 0.0)]
            stats[event.operation] = (current.count + 1, current.totalDuration + event.duration)
        }
        
        let total = Double(events.count)
        let operations = stats.mapValues { (count, totalDuration) in
            OperationStats(
                count: count,
                percentage: (Double(count) / total) * 100,
                avgDuration: totalDuration / Double(count),
                totalDuration: totalDuration
            )
        }
        
        return OperationBreakdown(operations: operations)
    }
    
    /// Get recent operations
    func getRecentOperations(limit: Int = 10) async throws -> [MetricEvent] {
        guard let db = metricsDB else {
            throw BlazeDBError.invalidData(reason: "Telemetry not enabled")
        }
        
        let allRecords = try await db.fetchAll()
        let events = try allRecords.compactMap { try? MetricEvent.from(record: $0) }
        
        return events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Maintenance
    
    /// Clear all metrics
    func clear() async throws {
        guard let db = metricsDB else {
            throw BlazeDBError.invalidData(reason: "Telemetry not enabled")
        }
        
        let allRecords = try await db.fetchAll()
        for record in allRecords {
            if let id = record.storage["id"]?.uuidValue {
                try await db.delete(id: id)
            }
        }
        
        BlazeLogger.info("📊 Cleared all telemetry metrics")
    }
    
    /// Cleanup old metrics
    func cleanup() async throws -> Int {
        guard let db = metricsDB else {
            return 0
        }
        
        let retentionDays = config.retentionDays
        
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        
        let allRecords = try await db.fetchAll()
        var deleted = 0
        
        for record in allRecords {
            if let timestamp = record.storage["timestamp"]?.dateValue,
               timestamp < cutoff,
               let id = record.storage["id"]?.uuidValue {
                try await db.delete(id: id)
                deleted += 1
            }
        }
        
        if deleted > 0 {
            BlazeLogger.info("📊 Cleaned up \(deleted) old metrics (> \(retentionDays) days)")
        }
        
        return deleted
    }
    
    // MARK: - Auto-cleanup
    
    private func startAutoCleanup() {
        cleanupTask?.cancel()
        
        cleanupTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                // Wait for cleanup interval
                try? await Task.sleep(nanoseconds: UInt64(self.config.cleanupInterval * 1_000_000_000))
                
                if Task.isCancelled { return }
                
                // Run cleanup
                _ = try? await self.cleanup()
            }
        }
    }
    
    // MARK: - Helper
    
    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count) * p)
        return sorted[min(index, sorted.count - 1)]
    }
}

