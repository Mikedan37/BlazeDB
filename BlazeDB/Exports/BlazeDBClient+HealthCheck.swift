//
//  BlazeDBClient+HealthCheck.swift
//  BlazeDB
//
//  Health check and monitoring API
//  Uses existing MetricsCollector for telemetry
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Health Status

public struct HealthStatus {
    public let isHealthy: Bool
    public let issues: [String]
    public let uptime: TimeInterval
    public let lastBackup: Date?
    public let databaseSize: Int64
    public let recordCount: Int
    
    public var description: String {
        var desc = "Health Status: \(isHealthy ? "✅ Healthy" : "⚠️ Issues Found")\n"
        desc += "  Uptime: \(String(format: "%.1f", uptime))s\n"
        desc += "  Database Size: \(databaseSize / 1024 / 1024) MB\n"
        desc += "  Records: \(recordCount)\n"
        if let lastBackup = lastBackup {
            desc += "  Last Backup: \(lastBackup.formatted())\n"
        }
        if !issues.isEmpty {
            desc += "  Issues:\n"
            for issue in issues {
                desc += "    - \(issue)\n"
            }
        }
        return desc
    }
}

// MARK: - BlazeDBClient Health Check Extension

extension BlazeDBClient {
    nonisolated(unsafe) private static var startTimeKey: UInt8 = 0
    nonisolated(unsafe) private static var lastBackupTimeKey: UInt8 = 0
    
    private var startTime: Date {
        #if canImport(ObjectiveC)
        if let time = objc_getAssociatedObject(self, &Self.startTimeKey) as? Date {
            return time
        }
        let time = Date()
        objc_setAssociatedObject(self, &Self.startTimeKey, time, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return time
        #else
        if let time: Date = AssociatedObjects.getValue(self, key: &Self.startTimeKey) {
            return time
        }
        let time = Date()
        AssociatedObjects.setValue(self, key: &Self.startTimeKey, value: time)
        return time
        #endif
    }
    
    /// Get health status
    public func getHealthStatus() throws -> HealthStatus {
        var issues: [String] = []
        
        // Check database file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            issues.append("Database file not found")
            return HealthStatus(
                isHealthy: false,
                issues: issues,
                uptime: Date().timeIntervalSince(startTime),
                lastBackup: getLastBackupTime(),
                databaseSize: 0,
                recordCount: 0
            )
        }
        
        // Check database size
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let databaseSize = (attributes?[.size] as? Int64) ?? 0
        
        // Check if database is too large (warning at 1GB)
        if databaseSize > 1_000_000_000 {
            issues.append("Database size is large: \(databaseSize / 1024 / 1024) MB")
        }
        
        // Get record count
        let recordCount = count()
        
        // Check telemetry for slow queries (if enabled) - async check
        // Note: This is a sync method, so we can't await telemetry here
        // Telemetry checks are handled in getMonitoringSnapshot() which is async
        
        return HealthStatus(
            isHealthy: issues.isEmpty,
            issues: issues,
            uptime: Date().timeIntervalSince(startTime),
            lastBackup: getLastBackupTime(),
            databaseSize: databaseSize,
            recordCount: recordCount
        )
    }
    
    private func getLastBackupTime() -> Date? {
        #if canImport(ObjectiveC)
        return objc_getAssociatedObject(self, &Self.lastBackupTimeKey) as? Date
        #else
        return AssociatedObjects.getValue(self, key: &Self.lastBackupTimeKey)
        #endif
    }
    
    internal func setLastBackupTime(_ date: Date) {
        #if canImport(ObjectiveC)
        objc_setAssociatedObject(self, &Self.lastBackupTimeKey, date, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        #else
        AssociatedObjects.setValue(self, key: &Self.lastBackupTimeKey, value: date)
        #endif
    }
}


