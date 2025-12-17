//
//  AutomaticGC.swift
//  BlazeDB
//
//  MVCC Phase 4: Automatic garbage collection
//
//  Automatically triggers GC based on memory thresholds,
//  transaction count, and time intervals.
//
//  Created: 2025-11-13
//

import Foundation

/// Configuration for automatic MVCC garbage collection
public struct MVCCGCConfiguration {
    /// Trigger GC after this many committed transactions
    public var transactionThreshold: Int = 100
    
    /// Trigger GC when average versions per record exceeds this
    public var versionThreshold: Double = 3.0
    
    /// Trigger GC at this time interval (seconds)
    public var timeInterval: TimeInterval = 60.0
    
    /// Minimum versions to remove before GC is considered worthwhile
    public var minVersionsToRemove: Int = 10
    
    /// Enable/disable automatic GC
    public var enabled: Bool = true
    
    /// Enable verbose GC logging
    public var verbose: Bool = false
    
    public init() {}
}

/// Automatic garbage collection manager
public class AutomaticGCManager: @unchecked Sendable {
    
    private let versionManager: VersionManager
    private var config: MVCCGCConfiguration
    
    // Tracking
    private var transactionsSinceLastGC: Int = 0
    private var lastGCTime: Date = Date()
    private var totalGCRuns: Int = 0
    private var totalVersionsRemoved: Int = 0
    
    private let lock = NSLock()
    private var gcTimer: Timer?
    
    // MARK: - Initialization
    
    public init(versionManager: VersionManager, config: MVCCGCConfiguration = MVCCGCConfiguration()) {
        self.versionManager = versionManager
        self.config = config
        
        // Start periodic GC timer
        if config.enabled && config.timeInterval > 0 {
            startPeriodicGC()
        }
    }
    
    deinit {
        stopPeriodicGC()
    }
    
    // MARK: - Automatic Triggering
    
    /// Called after each transaction commit
    public func onTransactionCommit() {
        guard config.enabled else { return }
        
        lock.lock()
        transactionsSinceLastGC += 1
        lock.unlock()
        
        // Check if we should trigger GC
        if shouldTriggerGC() {
            triggerGC()
        }
    }
    
    /// Check if GC should be triggered
    private func shouldTriggerGC() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Threshold 1: Transaction count
        if transactionsSinceLastGC >= config.transactionThreshold {
            if config.verbose {
                print("🗑️ GC trigger: Transaction threshold (\(transactionsSinceLastGC) >= \(config.transactionThreshold))")
            }
            return true
        }
        
        // Threshold 2: Version accumulation
        let stats = versionManager.getStats()
        if stats.averageVersionsPerRecord >= config.versionThreshold {
            if config.verbose {
                print("🗑️ GC trigger: Version threshold (\(String(format: "%.2f", stats.averageVersionsPerRecord)) >= \(config.versionThreshold))")
            }
            return true
        }
        
        // Threshold 3: Time-based
        let timeSinceLastGC = Date().timeIntervalSince(lastGCTime)
        if timeSinceLastGC >= config.timeInterval {
            if config.verbose {
                print("🗑️ GC trigger: Time threshold (\(String(format: "%.1f", timeSinceLastGC))s >= \(config.timeInterval)s)")
            }
            return true
        }
        
        return false
    }
    
    /// Trigger garbage collection
    public func triggerGC() {
        lock.lock()
        let shouldRun = config.enabled
        lock.unlock()
        
        guard shouldRun else { return }
        
        let startTime = Date()
        let statsBefore = versionManager.getStats()
        
        // Run GC
        let removed = versionManager.garbageCollect()
        
        let statsAfter = versionManager.getStats()
        let duration = Date().timeIntervalSince(startTime)
        
        lock.lock()
        transactionsSinceLastGC = 0
        lastGCTime = Date()
        totalGCRuns += 1
        totalVersionsRemoved += removed
        lock.unlock()
        
        // Log results
        if config.verbose || removed >= config.minVersionsToRemove {
            print("""
                🗑️ Garbage Collection Complete:
                   Versions before: \(statsBefore.totalVersions)
                   Versions after:  \(statsAfter.totalVersions)
                   Removed:         \(removed)
                   Duration:        \(String(format: "%.3f", duration))s
                   Total GC runs:   \(totalGCRuns)
                """)
        }
    }
    
    /// Force immediate GC (for manual triggering)
    public func forceGC() -> Int {
        let removed = versionManager.garbageCollect()
        
        lock.lock()
        transactionsSinceLastGC = 0
        lastGCTime = Date()
        totalGCRuns += 1
        totalVersionsRemoved += removed
        lock.unlock()
        
        return removed
    }
    
    // MARK: - Periodic GC
    
    /// Start periodic GC timer
    private func startPeriodicGC() {
        stopPeriodicGC()
        
        gcTimer = Timer.scheduledTimer(
            withTimeInterval: config.timeInterval,
            repeats: true
        ) { [weak self] _ in
            self?.triggerGC()
        }
    }
    
    /// Stop periodic GC timer
    private func stopPeriodicGC() {
        gcTimer?.invalidate()
        gcTimer = nil
    }
    
    // MARK: - Configuration
    
    /// Update GC configuration
    public func updateConfig(_ newConfig: MVCCGCConfiguration) {
        lock.lock()
        config = newConfig
        lock.unlock()
        
        // Restart timer if interval changed
        if newConfig.enabled && newConfig.timeInterval > 0 {
            startPeriodicGC()
        } else {
            stopPeriodicGC()
        }
    }
    
    /// Get current configuration
    public func getConfig() -> MVCCGCConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return config
    }
    
    // MARK: - Statistics
    
    /// Get GC statistics
    public func getStats() -> MVCCGCStats {
        lock.lock()
        defer { lock.unlock() }
        
        return MVCCGCStats(
            totalRuns: totalGCRuns,
            totalVersionsRemoved: totalVersionsRemoved,
            transactionsSinceLastGC: transactionsSinceLastGC,
            lastGCTime: lastGCTime,
            averageVersionsPerRun: totalGCRuns > 0 ? Double(totalVersionsRemoved) / Double(totalGCRuns) : 0
        )
    }
}

/// MVCC Garbage collection statistics
public struct MVCCGCStats {
    public let totalRuns: Int
    public let totalVersionsRemoved: Int
    public let transactionsSinceLastGC: Int
    public let lastGCTime: Date
    public let averageVersionsPerRun: Double
    
    public var description: String {
        """
        Automatic GC Stats:
          Total GC runs:       \(totalRuns)
          Versions removed:    \(totalVersionsRemoved)
          Avg per run:         \(String(format: "%.1f", averageVersionsPerRun))
          Last GC:             \(lastGCTime)
          Transactions since:  \(transactionsSinceLastGC)
        """
    }
}

