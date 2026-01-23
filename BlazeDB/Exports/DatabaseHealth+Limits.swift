//
//  DatabaseHealth+Limits.swift
//  BlazeDB
//
//  Resource bounds and warnings: guardrails for WAL growth, page count, disk usage
//  Detects resource exhaustion and warns before failures occur
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension DatabaseHealth {
    
    /// Resource limit configuration
    public struct ResourceLimits {
        /// Maximum WAL size as ratio of database size (default: 0.5 = 50%)
        public var maxWALSizeRatio: Double = 0.5
        
        /// Maximum page count before warning (default: 1,000,000 pages = ~4GB)
        public var maxPageCount: Int = 1_000_000
        
        /// Maximum disk usage in bytes before warning (default: 10GB)
        public var maxDiskUsageBytes: Int64 = 10_000_000_000
        
        /// Whether to refuse writes when limits are exceeded (default: false = warn only)
        public var refuseWritesOnLimit: Bool = false
        
        public init(
            maxWALSizeRatio: Double = 0.5,
            maxPageCount: Int = 1_000_000,
            maxDiskUsageBytes: Int64 = 10_000_000_000,
            refuseWritesOnLimit: Bool = false
        ) {
            self.maxWALSizeRatio = maxWALSizeRatio
            self.maxPageCount = maxPageCount
            self.maxDiskUsageBytes = maxDiskUsageBytes
            self.refuseWritesOnLimit = refuseWritesOnLimit
        }
    }
    
    /// Check resource limits and return warnings if exceeded
    ///
    /// - Parameters:
    ///   - stats: Current database statistics
    ///   - limits: Resource limit configuration
    /// - Returns: Array of warning messages if limits are exceeded
    public static func checkResourceLimits(
        stats: DatabaseStats,
        limits: ResourceLimits = ResourceLimits()
    ) -> [String] {
        var warnings: [String] = []
        
        // Check WAL size ratio
        if let walSize = stats.walSize, stats.databaseSize > 0 {
            let walRatio = Double(walSize) / Double(stats.databaseSize)
            if walRatio > limits.maxWALSizeRatio {
                warnings.append(
                    "WAL size (\(formatBytes(walSize))) exceeds \(Int(limits.maxWALSizeRatio * 100))% of database size. " +
                    "Consider running a checkpoint or vacuum operation."
                )
            }
        }
        
        // Check page count
        if stats.pageCount > limits.maxPageCount {
            warnings.append(
                "Page count (\(stats.pageCount)) exceeds limit (\(limits.maxPageCount)). " +
                "Database may be fragmented. Consider running vacuum operation."
            )
        }
        
        // Check disk usage
        if stats.databaseSize > limits.maxDiskUsageBytes {
            warnings.append(
                "Database size (\(formatBytes(stats.databaseSize))) exceeds limit (\(formatBytes(limits.maxDiskUsageBytes))). " +
                "Consider archiving old data or increasing disk space."
            )
        }
        
        return warnings
    }
    
    /// Check if resource limits are exceeded (for write refusal)
    ///
    /// - Parameters:
    ///   - stats: Current database statistics
    ///   - limits: Resource limit configuration
    /// - Returns: `true` if limits are exceeded and writes should be refused
    public static func shouldRefuseWrites(
        stats: DatabaseStats,
        limits: ResourceLimits
    ) -> Bool {
        guard limits.refuseWritesOnLimit else { return false }
        
        // Check WAL size ratio
        if let walSize = stats.walSize, stats.databaseSize > 0 {
            let walRatio = Double(walSize) / Double(stats.databaseSize)
            if walRatio > limits.maxWALSizeRatio {
                return true
            }
        }
        
        // Check page count
        if stats.pageCount > limits.maxPageCount {
            return true
        }
        
        // Check disk usage
        if stats.databaseSize > limits.maxDiskUsageBytes {
            return true
        }
        
        return false
    }
    
    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
