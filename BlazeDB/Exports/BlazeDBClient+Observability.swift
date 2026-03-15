//
//  BlazeDBClient+Observability.swift
//  BlazeDB
//
//  Snapshot-based observability API.
//  Read-only, non-invasive, zero cost if unused.
//
//

import Foundation

extension BlazeDBClient {
    
    /// Internal metrics container (lazy, zero cost if never accessed)
    internal var metrics: BlazeDBMetrics {
        if let existing: BlazeDBMetrics = AssociatedObjects.get(self, key: &AssociatedKeys.metrics) {
            return existing
        }
        let new = BlazeDBMetrics()
        AssociatedObjects.set(self, key: &AssociatedKeys.metrics, value: new)
        return new
    }
    
    /// Get a snapshot of current database state for observability.
    ///
    /// This method is read-only, non-blocking, and safe to call at any time.
    /// It captures current system state without performing computation.
    ///
    /// - Returns: Immutable snapshot of database state
    /// - Throws: Error if health check fails (rare)
    ///
    /// ## Example
    /// ```swift
    /// let snapshot = try db.observe()
    /// print("Uptime: \(snapshot.uptime)s")
    /// print("Transactions: \(snapshot.transactions.committed) committed")
    /// print("Page reads: \(snapshot.io.pageReads)")
    /// ```
    public func observe() throws -> BlazeDBSnapshot {
        // Calculate uptime (cheap, no I/O)
        let uptime = Date().timeIntervalSince(metrics.openTime)
        
        // Get health status (uses existing health() method, no new logic)
        let healthReport = try health()
        let healthStatus = SnapshotHealthStatus(
            status: healthReport.status.rawValue,
            reasons: healthReport.reasons
        )
        
        // Get transaction stats (from metrics)
        let transactionStats = SnapshotTransactionStats(
            started: metrics.transactionsStarted,
            committed: metrics.transactionsCommitted,
            aborted: metrics.transactionsAborted
        )
        
        // Get WAL stats (from file system, non-invasive)
        let walURL = fileURL.deletingPathExtension().appendingPathExtension("wal")
        var walFileSize: Int64 = 0
        if FileManager.default.fileExists(atPath: walURL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: walURL.path)
            walFileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        
        let walStats = WALStats(
            pendingWrites: 0,  // Not tracked (would require WAL actor access)
            lastCheckpoint: metrics.lastCheckpointTime ?? Date(),
            logFileSize: walFileSize
        )
        
        // Get I/O stats (from metrics)
        let ioStats = IOStats(
            pageReads: metrics.pageReads,
            pageWrites: metrics.pageWrites
        )
        
        // Get recovery stats (from metrics)
        let recoveryStats = RecoveryStats(
            state: metrics.recoveryState.rawValue
        )
        
        return BlazeDBSnapshot(
            uptime: uptime,
            health: healthStatus,
            transactions: transactionStats,
            wal: walStats,
            io: ioStats,
            recovery: recoveryStats
        )
    }
}

// MARK: - Associated Object Keys

private struct AssociatedKeys {
    nonisolated(unsafe) static var metrics: UInt8 = 0
}

