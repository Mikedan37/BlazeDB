//
//  BlazeDBClient+MVCC.swift
//  BlazeDB
//
//  Public API for MVCC features and configuration
//
//  Created: 2025-11-13
//

import Foundation

extension BlazeDBClient {
    
    // MARK: - MVCC Control
    
    /// Enable MVCC for concurrent access (EXPERIMENTAL)
    ///
    /// When enabled, BlazeDB uses Multi-Version Concurrency Control for:
    /// - Concurrent reads (10-100x faster!)
    /// - Snapshot isolation (consistent views)
    /// - Optimistic locking (conflict detection)
    /// - Automatic garbage collection
    ///
    /// Performance impact:
    /// - Concurrent reads: 10-100x faster
    /// - Single-threaded: ~5-10% overhead
    /// - Memory: +50-100% (managed by GC)
    ///
    /// - Parameter enabled: true to enable MVCC, false for legacy mode
    public func setMVCCEnabled(_ enabled: Bool) {
        collection.queue.sync(flags: .barrier) {
            let previous = collection.mvccEnabled
            collection.mvccEnabled = enabled

            if enabled, previous == false {
                // Enabling MVCC on an existing database: rebuild version state from authoritative indexMap.
                // This ensures records persisted before MVCC was enabled remain visible under MVCC.
                BlazeLogger.info("🚀 MVCC ENABLED: Concurrent access active — rebuilding MVCC state from indexMap")
                collection.versionManager.reset()
                collection.rebuildMVCCFromIndexMapIfNeeded()
            } else if !enabled, previous == true {
                BlazeLogger.info("⚠️  MVCC DISABLED: Using legacy serial mode")
            }
        }
    }
    
    /// Check if MVCC is currently enabled
    public func isMVCCEnabled() -> Bool {
        return collection.queue.sync {
            collection.mvccEnabled
        }
    }
    
    // MARK: - GC Configuration
    
    /// Configure automatic garbage collection
    ///
    /// - Parameter config: MVCC GC configuration
    public func configureGC(_ config: MVCCGCConfiguration) {
        collection.queue.sync(flags: .barrier) {
            collection.gcManager.updateConfig(config)
        }
    }
    
    /// Manually trigger garbage collection
    ///
    /// - Returns: Number of versions removed
    @discardableResult
    public func runGarbageCollection() -> Int {
        return collection.queue.sync(flags: .barrier) {
            let removed = collection.gcManager.forceGC()
            BlazeLogger.info("🗑️ Manual GC: Removed \(removed) old versions")
            return removed
        }
    }
    
    // MARK: - Statistics
    
    /// Get MVCC version statistics
    public func getMVCCStats() -> VersionStats {
        return collection.queue.sync {
            collection.versionManager.getStats()
        }
    }
    
    /// Get garbage collection statistics
    public func getGCStats() -> MVCCGCStats {
        return collection.queue.sync {
            collection.gcManager.getStats()
        }
    }
    
    /// Returns a formatted MVCC status string for diagnostics
    public func mvccStatusDescription() -> String {
        let mvccEnabled = isMVCCEnabled()
        let versionStats = getMVCCStats()
        let gcStats = getGCStats()

        return """
        MVCC Status
        ───────────────────────────────────────
        MVCC Enabled: \(mvccEnabled ? "YES" : "NO")

        \(versionStats.description)

        \(gcStats.description)
        ───────────────────────────────────────
        """
    }

    /// Print comprehensive MVCC status
    @available(*, deprecated, message: "Use mvccStatusDescription() instead — printMVCCStatus() writes directly to stdout")
    public func printMVCCStatus() {
        print(mvccStatusDescription())
    }
}

