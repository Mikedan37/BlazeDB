//
//  BlazeDBMetrics.swift
//  BlazeDB
//
//  Lightweight metrics container for snapshot-based observability.
//  Thread-safe via NSLock, zero cost if unused.
//
//  Created by Auto on 2025-01-23.
//

import Foundation

/// Lightweight metrics container for snapshot-based observability.
/// 
/// All counters are thread-safe and updated opportunistically where data already exists.
/// No allocations, no blocking, no derived calculations.
/// 
/// **Design Principles:**
/// - Fire-and-forget updates (no error handling)
/// - Simple counters only (no complex state)
/// - Zero cost if never accessed
internal final class BlazeDBMetrics: @unchecked Sendable {
    // MARK: - Transaction Metrics
    
    private var _transactionsStarted: UInt64 = 0
    private let transactionsLock = NSLock()
    
    var transactionsStarted: UInt64 {
        transactionsLock.lock()
        defer { transactionsLock.unlock() }
        return _transactionsStarted
    }
    
    private var _transactionsCommitted: UInt64 = 0
    var transactionsCommitted: UInt64 {
        transactionsLock.lock()
        defer { transactionsLock.unlock() }
        return _transactionsCommitted
    }
    
    private var _transactionsAborted: UInt64 = 0
    var transactionsAborted: UInt64 {
        transactionsLock.lock()
        defer { transactionsLock.unlock() }
        return _transactionsAborted
    }
    
    // MARK: - WAL Metrics
    
    private var _walBytesWritten: UInt64 = 0
    private let walLock = NSLock()
    
    var walBytesWritten: UInt64 {
        walLock.lock()
        defer { walLock.unlock() }
        return _walBytesWritten
    }
    
    private var _checkpointCount: UInt64 = 0
    var checkpointCount: UInt64 {
        walLock.lock()
        defer { walLock.unlock() }
        return _checkpointCount
    }
    
    private var _fsyncCount: UInt64 = 0
    var fsyncCount: UInt64 {
        walLock.lock()
        defer { walLock.unlock() }
        return _fsyncCount
    }
    
    private var _lastCheckpointTime: Date?
    var lastCheckpointTime: Date? {
        walLock.lock()
        defer { walLock.unlock() }
        return _lastCheckpointTime
    }
    
    // MARK: - I/O Metrics
    
    private var _pageReads: UInt64 = 0
    private let ioLock = NSLock()
    
    var pageReads: UInt64 {
        ioLock.lock()
        defer { ioLock.unlock() }
        return _pageReads
    }
    
    private var _pageWrites: UInt64 = 0
    var pageWrites: UInt64 {
        ioLock.lock()
        defer { ioLock.unlock() }
        return _pageWrites
    }
    
    // MARK: - Recovery State
    
    /// Recovery state enum
    internal enum RecoveryState: String, Codable {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case completed = "completed"
        case failed = "failed"
    }
    
    private var _recoveryState: RecoveryState = .notStarted
    private let recoveryLock = NSLock()
    
    var recoveryState: RecoveryState {
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        return _recoveryState
    }
    
    private let _openTime: Date = Date()
    var openTime: Date {
        return _openTime  // Immutable, no lock needed
    }
    
    // MARK: - Update Methods (Fire-and-Forget)
    
    func incrementTransactionsStarted() {
        transactionsLock.lock()
        defer { transactionsLock.unlock() }
        _transactionsStarted += 1
    }
    
    func incrementTransactionsCommitted() {
        transactionsLock.lock()
        defer { transactionsLock.unlock() }
        _transactionsCommitted += 1
    }
    
    func incrementTransactionsAborted() {
        transactionsLock.lock()
        defer { transactionsLock.unlock() }
        _transactionsAborted += 1
    }
    
    func addWALBytes(_ bytes: Int) {
        walLock.lock()
        defer { walLock.unlock() }
        _walBytesWritten += UInt64(bytes)
    }
    
    func incrementCheckpoint() {
        walLock.lock()
        defer { walLock.unlock() }
        _checkpointCount += 1
        _lastCheckpointTime = Date()
    }
    
    func incrementFsync() {
        walLock.lock()
        defer { walLock.unlock() }
        _fsyncCount += 1
    }
    
    func incrementPageRead() {
        ioLock.lock()
        defer { ioLock.unlock() }
        _pageReads += 1
    }
    
    func incrementPageWrite() {
        ioLock.lock()
        defer { ioLock.unlock() }
        _pageWrites += 1
    }
    
    func setRecoveryState(_ state: RecoveryState) {
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        _recoveryState = state
    }
}
