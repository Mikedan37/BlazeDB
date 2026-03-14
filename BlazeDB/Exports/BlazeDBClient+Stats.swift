//
//  BlazeDBClient+Stats.swift
//  BlazeDB
//
//  Diagnostics API - exposes database statistics
//  Read-only, no mutations, safe for monitoring
//

import Foundation

/// Database statistics for diagnostics and monitoring
public struct DatabaseStats: Codable {
    public let pageCount: Int
    public let walSize: Int64?
    public let lastCheckpoint: Date?
    public let cacheHitRate: Double
    public let cacheHitRateAvailable: Bool
    public let indexCount: Int
    public let recordCount: Int
    public let databaseSize: Int64
    
    public init(
        pageCount: Int,
        walSize: Int64?,
        lastCheckpoint: Date?,
        cacheHitRate: Double,
        cacheHitRateAvailable: Bool = true,
        indexCount: Int,
        recordCount: Int,
        databaseSize: Int64
    ) {
        self.pageCount = pageCount
        self.walSize = walSize
        self.lastCheckpoint = lastCheckpoint
        self.cacheHitRate = cacheHitRate
        self.cacheHitRateAvailable = cacheHitRateAvailable
        self.indexCount = indexCount
        self.recordCount = recordCount
        self.databaseSize = databaseSize
    }
}

extension DatabaseStats {
    
    /// Pretty-print formatted statistics
    public func prettyPrint() -> String {
        var output = "📊 Database Statistics\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        output += "Records: \(recordCount)\n"
        output += "Pages: \(pageCount)\n"
        output += "Indexes: \(indexCount)\n"
        output += "Database Size: \(formatBytes(databaseSize))\n"
        
        if let walSize = walSize {
            output += "WAL Size: \(formatBytes(walSize))\n"
        }
        
        if let checkpoint = lastCheckpoint {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            output += "Last Checkpoint: \(formatter.string(from: checkpoint))\n"
        }
        
        if cacheHitRateAvailable {
            output += String(format: "Cache Hit Rate: %.1f%%\n", cacheHitRate * 100)
        } else {
            output += "Cache Hit Rate: unavailable\n"
        }
        
        return output
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// DatabaseStats is already Codable via struct properties

extension BlazeDBClient {
    
    /// Get database statistics for diagnostics
    /// 
    /// Read-only operation - no mutations performed.
    /// Safe to call frequently for monitoring.
    ///
    /// ## Example
    /// ```swift
    /// let stats = try db.stats()
    /// print(stats.prettyPrint())
    /// // Or get JSON:
    /// let json = try JSONEncoder().encode(stats)
    /// ```
    public func stats() throws -> DatabaseStats {
        // Get record count
        let recordCount = getRecordCount()
        
        // Get database size
        let databaseSize = try getTotalDiskUsage()
        
        // Get page count and index count from monitoring snapshot
        var pageCount = 0
        var indexCount = 0
        do {
            let snapshot = try getMonitoringSnapshot()
            pageCount = snapshot.storage.totalPages
            indexCount = snapshot.performance.indexCount
        } catch {
            // Fallback: estimate from file size
            BlazeLogger.debug("Stats: Monitoring snapshot failed, estimating from file size: \(error)")
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = (attrs?[.size] as? NSNumber)?.int64Value {
                pageCount = Int(fileSize / 4096) // Approximate
            }
            // Fallback index count from collection (read-only access)
            indexCount = collection.secondaryIndexes.count
        }
        
        // Get WAL size if exists
        let walURL = fileURL.deletingPathExtension().appendingPathExtension("wal")
        var walSize: Int64? = nil
        if FileManager.default.fileExists(atPath: walURL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: walURL.path)
            walSize = (attrs?[.size] as? NSNumber)?.int64Value
        }
        
        // Get last checkpoint time (from WAL if available)
        var lastCheckpoint: Date? = nil
        if let walAttrs = try? FileManager.default.attributesOfItem(atPath: walURL.path) {
            lastCheckpoint = walAttrs[.modificationDate] as? Date
        }
        
        // Cache hit rate instrumentation not yet wired — report as unavailable
        let cacheHitRate = 0.0
        let cacheHitRateAvailable = false
        
        return DatabaseStats(
            pageCount: pageCount,
            walSize: walSize,
            lastCheckpoint: lastCheckpoint,
            cacheHitRate: cacheHitRate,
            cacheHitRateAvailable: cacheHitRateAvailable,
            indexCount: indexCount,
            recordCount: recordCount,
            databaseSize: databaseSize
        )
    }
}
