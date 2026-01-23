//
//  DatabaseStats+Interpretation.swift
//  BlazeDB
//
//  Stats interpretation: making numbers meaningful
//  No new metrics - only interpretation
//

import Foundation

extension DatabaseStats {
    
    /// Human-readable interpretation of statistics
    public var interpretation: String {
        var output = ""
        
        // Record count interpretation
        output += "Records: \(recordCount)"
        if recordCount == 0 {
            output += " (empty database)"
        } else if recordCount < 100 {
            output += " (small database)"
        } else if recordCount < 10_000 {
            output += " (moderate size)"
        } else if recordCount < 1_000_000 {
            output += " (large database)"
        } else {
            output += " (very large database)"
        }
        output += "\n"
        
        // Page count interpretation
        output += "Pages: \(pageCount)"
        if pageCount > 0 && recordCount > 0 {
            let recordsPerPage = Double(recordCount) / Double(pageCount)
            output += String(format: " (~%.1f records/page", recordsPerPage)
            if recordsPerPage < 10 {
                output += " - possible fragmentation)"
            } else {
                output += ")"
            }
        }
        output += "\n"
        
        // Database size interpretation
        output += "Database size: \(formatBytes(databaseSize))"
        if recordCount > 0 {
            let avgRecordSize = Double(databaseSize) / Double(recordCount)
            output += String(format: " (~%.0f bytes/record", avgRecordSize)
            if avgRecordSize > 10_000 {
                output += " - large records)"
            } else {
                output += ")"
            }
        }
        output += "\n"
        
        // WAL size interpretation
        if let walSize = walSize {
            output += "WAL size: \(formatBytes(walSize))"
            if databaseSize > 0 {
                let walRatio = Double(walSize) / Double(databaseSize)
                if walRatio > 0.5 {
                    output += " (large - consider checkpoint)"
                } else if walRatio > 0.2 {
                    output += " (moderate)"
                } else {
                    output += " (normal)"
                }
            }
            output += "\n"
        }
        
        // Cache hit rate interpretation
        if cacheHitRate > 0 {
            output += String(format: "Cache hit rate: %.1f%%", cacheHitRate * 100)
            if cacheHitRate >= 0.9 {
                output += " (excellent)"
            } else if cacheHitRate >= 0.7 {
                output += " (good)"
            } else if cacheHitRate >= 0.5 {
                output += " (moderate - expect slower reads)"
            } else {
                output += " (low - expect slower reads)"
            }
            output += "\n"
        }
        
        // Index count interpretation
        output += "Indexes: \(indexCount)"
        if indexCount == 0 {
            output += " (no indexes - queries may be slow)"
        } else if indexCount < 5 {
            output += " (few indexes)"
        } else {
            output += " (well-indexed)"
        }
        output += "\n"
        
        return output
    }
    
    /// Expected vs concerning thresholds
    public struct Thresholds {
        public static let walSizeRatioWarn: Double = 0.2
        public static let walSizeRatioError: Double = 0.5
        public static let cacheHitRateWarn: Double = 0.7
        public static let cacheHitRateError: Double = 0.5
        public static let recordsPerPageWarn: Double = 10.0
        public static let largeDatabaseSize: Int64 = 10_000_000_000 // 10 GB
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
