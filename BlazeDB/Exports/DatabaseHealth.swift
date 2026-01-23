//
//  DatabaseHealth.swift
//  BlazeDB
//
//  Operational confidence: health verdicts and interpretation
//  Tooling only - no engine changes
//

import Foundation

/// Database health status
public enum DatabaseHealth: String, Codable {
    case ok = "OK"
    case warn = "WARN"
    case error = "ERROR"
}

/// Health report with actionable guidance
public struct HealthReport: Codable {
    /// Health status
    public let status: DatabaseHealth
    
    /// Reasons for this status
    public let reasons: [String]
    
    /// Suggested actions
    public let suggestedActions: [String]
    
    /// Human-readable summary
    public var summary: String {
        var output = "Health: \(status.rawValue)\n"
        if !reasons.isEmpty {
            output += "Reasons:\n"
            for reason in reasons {
                output += "- \(reason)\n"
            }
        }
        if !suggestedActions.isEmpty {
            output += "Suggested actions:\n"
            for action in suggestedActions {
                output += "- \(action)\n"
            }
        }
        return output
    }
    
    public init(status: DatabaseHealth, reasons: [String] = [], suggestedActions: [String] = []) {
        self.status = status
        self.reasons = reasons
        self.suggestedActions = suggestedActions
    }
}

/// Health analyzer
/// 
/// Derives health verdicts from database statistics.
/// No background monitoring - computes on-demand.
public struct HealthAnalyzer {
    
    /// Analyze database health from stats
    ///
    /// - Parameter stats: Database statistics
    /// - Returns: Health report with verdict and guidance
    public static func analyze(_ stats: DatabaseStats) -> HealthReport {
        var reasons: [String] = []
        var suggestedActions: [String] = []
        var status: DatabaseHealth = .ok
        
        // Check WAL size relative to database size
        if let walSize = stats.walSize, stats.databaseSize > 0 {
            let walRatio = Double(walSize) / Double(stats.databaseSize)
            if walRatio > 0.5 {
                status = .warn
                reasons.append("WAL size (\(formatBytes(walSize))) is large relative to database size (\(formatBytes(stats.databaseSize)))")
                suggestedActions.append("Consider running checkpoint to reduce WAL size")
            } else if walRatio > 0.2 {
                status = status == .ok ? .warn : status
                reasons.append("WAL size is growing (\(formatBytes(walSize)))")
            }
        }
        
        // Check cache hit rate
        if stats.cacheHitRate > 0 {
            if stats.cacheHitRate < 0.5 {
                status = status == .error ? .error : .warn
                reasons.append("Cache hit rate is low (\(Int(stats.cacheHitRate * 100))%)")
                suggestedActions.append("Expect slower read performance. Consider increasing cache size if possible.")
            } else if stats.cacheHitRate < 0.7 {
                status = status == .ok ? .warn : status
                reasons.append("Cache hit rate is moderate (\(Int(stats.cacheHitRate * 100))%)")
            }
        }
        
        // Check page count vs record count ratio (fragmentation indicator)
        if stats.pageCount > 0 && stats.recordCount > 0 {
            let recordsPerPage = Double(stats.recordCount) / Double(stats.pageCount)
            if recordsPerPage < 10 {
                status = status == .error ? .error : .warn
                reasons.append("Low records per page (\(String(format: "%.1f", recordsPerPage))) - possible fragmentation")
                suggestedActions.append("Consider running vacuum to reclaim space")
            }
        }
        
        // Check database size (warn if very large)
        if stats.databaseSize > 10_000_000_000 { // 10 GB
            status = status == .ok ? .warn : status
            reasons.append("Database size is large (\(formatBytes(stats.databaseSize)))")
            suggestedActions.append("Monitor disk space usage")
        }
        
        // If no issues found, confirm OK
        if reasons.isEmpty {
            reasons.append("All checks passed")
        }
        
        // Add general guidance if warnings
        if status == .warn && suggestedActions.isEmpty {
            suggestedActions.append("Run `blazedb doctor` for detailed diagnostics")
        }
        
        return HealthReport(status: status, reasons: reasons, suggestedActions: suggestedActions)
    }
    
    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
