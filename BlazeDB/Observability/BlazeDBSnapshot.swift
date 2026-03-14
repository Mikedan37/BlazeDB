//
//  BlazeDBSnapshot.swift
//  BlazeDB
//
//  Immutable snapshot of database state for observability.
//  Cheap to construct, read-only, no computation.
//
//  Created by Auto on 2025-01-23.
//

import Foundation

/// Immutable snapshot of database state for observability.
/// 
/// This snapshot captures current system state without performing any computation.
/// All values are copied from pre-existing state - no derived calculations.
public struct BlazeDBSnapshot: Codable, Sendable {
    /// Database uptime since open
    public let uptime: TimeInterval
    
    /// Health status (computed from existing health() method)
    public let health: SnapshotHealthStatus
    
    /// Transaction statistics
    public let transactions: SnapshotTransactionStats
    
    /// WAL statistics
    public let wal: WALStats
    
    /// I/O statistics
    public let io: IOStats
    
    /// Recovery state
    public let recovery: RecoveryStats
    
    /// Timestamp when snapshot was taken
    public let timestamp: Date
    
    public init(
        uptime: TimeInterval,
        health: SnapshotHealthStatus,
        transactions: SnapshotTransactionStats,
        wal: WALStats,
        io: IOStats,
        recovery: RecoveryStats,
        timestamp: Date = Date()
    ) {
        self.uptime = uptime
        self.health = health
        self.transactions = transactions
        self.wal = wal
        self.io = io
        self.recovery = recovery
        self.timestamp = timestamp
    }
}

/// Transaction statistics snapshot (observability).
/// Distinct from MVCC TransactionStats in ConflictResolution.
public struct SnapshotTransactionStats: Codable, Sendable {
    public let started: UInt64
    public let committed: UInt64
    public let aborted: UInt64
    
    public init(started: UInt64, committed: UInt64, aborted: UInt64) {
        self.started = started
        self.committed = committed
        self.aborted = aborted
    }
}

/// I/O statistics snapshot
public struct IOStats: Codable, Sendable {
    public let pageReads: UInt64
    public let pageWrites: UInt64
    
    public init(pageReads: UInt64, pageWrites: UInt64) {
        self.pageReads = pageReads
        self.pageWrites = pageWrites
    }
}

/// Recovery statistics snapshot
public struct RecoveryStats: Codable, Sendable {
    public let state: String  // "not_started", "in_progress", "completed", "failed"
    
    public init(state: String) {
        self.state = state
    }
}

/// Health status for observability snapshot.
/// Distinct from HealthStatus in BlazeDBClient+HealthCheck (getHealthStatus).
public struct SnapshotHealthStatus: Codable, Sendable {
    public let status: String  // "OK", "WARN", "ERROR"
    public let reasons: [String]
    
    public init(status: String, reasons: [String] = []) {
        self.status = status
        self.reasons = reasons
    }
}
