//
//  GCControl.swift
//  BlazeDB
//
//  Comprehensive garbage collection control APIs for developers
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - GC Configuration

/// Complete configuration for garbage collection behavior
public struct GCConfiguration {
    // Page Reuse Settings
    public var enablePageReuse: Bool = true
    public var maxReuseablePages: Int = 10_000  // Cap to prevent unbounded memory
    public var reuseStrategy: ReuseStrategy = .fifo
    
    // Manual VACUUM Settings
    public var vacuumOnClose: Bool = false  // Run VACUUM when database closes
    public var vacuumBeforeBackup: Bool = true  // Auto-VACUUM before backup
    
    // Auto-VACUUM Settings
    public var autoVacuumEnabled: Bool = false
    public var autoVacuumWasteThreshold: Double = 0.30  // 30%
    public var autoVacuumMinWasteBytes: Int64 = 50_000_000  // 50 MB
    public var autoVacuumCheckInterval: TimeInterval = 3600  // 1 hour
    public var autoVacuumPriority: AutoVacuumPriority = .background
    
    // Monitoring Settings
    public var enableGCLogging: Bool = true
    public var logLevel: GCLogLevel = .info
    public var trackGCMetrics: Bool = true
    
    public enum ReuseStrategy {
        case fifo  // First-in-first-out (better locality)
        case lifo  // Last-in-first-out (simpler)
        case random  // Random selection (testing)
    }
    
    public enum AutoVacuumPriority {
        case background  // Low priority (default)
        case utility     // Medium priority
        case userInitiated  // High priority (not recommended)
    }
    
    public enum GCLogLevel {
        case silent  // No GC logs
        case error   // Only errors
        case warn    // Warnings + errors
        case info    // Important events
        case debug   // Detailed info
        case trace   // Everything
    }
    
    public init() {}
}

// MARK: - GC Policy

/// Garbage collection policy for fine-grained control
public struct GCPolicy {
    public var name: String
    public var shouldVacuum: (StorageStats) -> Bool
    public var description: String
    
    public init(name: String, description: String, shouldVacuum: @escaping (StorageStats) -> Bool) {
        self.name = name
        self.description = description
        self.shouldVacuum = shouldVacuum
    }
    
    // Predefined policies
    nonisolated(unsafe) public static let conservative = GCPolicy(
        name: "Conservative",
        description: "Only VACUUM when > 50% wasted",
        shouldVacuum: { $0.wastePercentage > 50 }
    )
    
    nonisolated(unsafe) public static let balanced = GCPolicy(
        name: "Balanced",
        description: "VACUUM when > 30% wasted",
        shouldVacuum: { $0.wastePercentage > 30 }
    )
    
    nonisolated(unsafe) public static let aggressive = GCPolicy(
        name: "Aggressive",
        description: "VACUUM when > 15% wasted",
        shouldVacuum: { $0.wastePercentage > 15 }
    )
    
    nonisolated(unsafe) public static let spaceSaving = GCPolicy(
        name: "Space Saving",
        description: "VACUUM when > 10 MB wasted OR > 20% wasted",
        shouldVacuum: { $0.wastedSpace > 10_000_000 || $0.wastePercentage > 20 }
    )
}

// MARK: - GC Metrics

/// Tracks GC performance over time
public struct GCMetrics {
    public var totalVacuums: Int = 0
    public var totalPagesReclaimed: Int = 0
    public var totalBytesReclaimed: Int64 = 0
    public var totalVacuumDuration: TimeInterval = 0
    public var pagesReused: Int = 0
    public var autoVacuumsTriggered: Int = 0
    
    public var averageVacuumDuration: TimeInterval {
        guard totalVacuums > 0 else { return 0 }
        return totalVacuumDuration / Double(totalVacuums)
    }
    
    public var description: String {
        """
        GC Metrics:
          Total VACUUMs: \(totalVacuums)
          Pages reclaimed: \(totalPagesReclaimed)
          Bytes reclaimed: \(totalBytesReclaimed / 1024 / 1024) MB
          Total VACUUM time: \(String(format: "%.2f", totalVacuumDuration))s
          Avg VACUUM time: \(String(format: "%.2f", averageVacuumDuration))s
          Pages reused: \(pagesReused)
          Auto-VACUUMs: \(autoVacuumsTriggered)
        """
    }
}

// MARK: - GC Manager

/// Central garbage collection manager
public final class GCManager {
    private var configuration: GCConfiguration
    private var policy: GCPolicy?
    private var metrics = GCMetrics()
    private weak var database: BlazeDBClient?
    private let lock = NSLock()
    
    init(database: BlazeDBClient, configuration: GCConfiguration = GCConfiguration()) {
        self.database = database
        self.configuration = configuration
    }
    
    // MARK: - Configuration
    
    public func updateConfiguration(_ config: GCConfiguration) {
        lock.lock()
        configuration = config
        lock.unlock()
        
        BlazeLogger.info("🔧 GC configuration updated")
    }
    
    public func getConfiguration() -> GCConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }
    
    // MARK: - Policy
    
    public func setPolicy(_ policy: GCPolicy) {
        lock.lock()
        self.policy = policy
        lock.unlock()
        
        BlazeLogger.info("📋 GC policy set: \(policy.name)")
    }
    
    public func getPolicy() -> GCPolicy? {
        lock.lock()
        defer { lock.unlock() }
        return policy
    }
    
    // MARK: - Metrics
    
    internal func recordVacuum(stats: VacuumStats) {
        lock.lock()
        metrics.totalVacuums += 1
        metrics.totalPagesReclaimed += stats.pagesReclaimed
        metrics.totalBytesReclaimed += stats.sizeReclaimed
        metrics.totalVacuumDuration += stats.duration
        lock.unlock()
    }
    
    internal func recordPageReuse() {
        lock.lock()
        metrics.pagesReused += 1
        lock.unlock()
    }
    
    internal func recordAutoVacuum() {
        lock.lock()
        metrics.autoVacuumsTriggered += 1
        lock.unlock()
    }
    
    public func getMetrics() -> GCMetrics {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }
    
    public func resetMetrics() {
        lock.lock()
        metrics = GCMetrics()
        lock.unlock()
        
        BlazeLogger.debug("🔄 GC metrics reset")
    }
    
    // MARK: - Policy Evaluation
    
    public func shouldVacuum(stats: StorageStats) -> Bool {
        lock.lock()
        let currentPolicy = policy
        lock.unlock()
        
        if let policy = currentPolicy {
            return policy.shouldVacuum(stats)
        }
        
        // Default: balanced policy
        return stats.wastePercentage > 30
    }
}

// MARK: - BlazeDBClient GC Control Extension

extension BlazeDBClient {
    
    nonisolated(unsafe) private static var gcManagers: [String: GCManager] = [:]
    private static let gcManagerLock = NSLock()
    
    /// Get or create GC manager for this database
    private var gcManager: GCManager {
        let key = "\(name)-\(fileURL.path)"
        
        Self.gcManagerLock.lock()
        defer { Self.gcManagerLock.unlock() }
        
        if let existing = Self.gcManagers[key] {
            return existing
        }
        
        let manager = GCManager(database: self)
        Self.gcManagers[key] = manager
        return manager
    }
    
    // MARK: - Configuration API
    
    /// Configure garbage collection behavior
    ///
    /// - Parameter configuration: GC configuration
    ///
    /// ## Example
    /// ```swift
    /// var config = GCConfiguration()
    /// config.enablePageReuse = true  // Default
    /// config.maxReuseablePages = 5000  // Cap reuse pool
    /// config.autoVacuumEnabled = true
    /// config.autoVacuumWasteThreshold = 0.20  // 20%
    /// config.vacuumBeforeBackup = true
    ///
    /// db.configureGC(config)
    /// ```
    public func configureGC(_ configuration: GCConfiguration) {
        gcManager.updateConfiguration(configuration)
        
        // Apply auto-vacuum setting
        if configuration.autoVacuumEnabled {
            enableAutoVacuum(
                wasteThreshold: configuration.autoVacuumWasteThreshold,
                checkInterval: configuration.autoVacuumCheckInterval
            )
        } else {
            disableAutoVacuum()
        }
        
        BlazeLogger.info("🔧 GC configured for '\(name)'")
    }
    
    /// Get current GC configuration
    public func getGCConfiguration() -> GCConfiguration {
        return gcManager.getConfiguration()
    }
    
    // MARK: - Policy API
    
    /// Set garbage collection policy
    ///
    /// - Parameter policy: GC policy (or use predefined policies)
    ///
    /// ## Example
    /// ```swift
    /// // Use predefined policy
    /// db.setGCPolicy(.balanced)  // VACUUM at 30% waste
    ///
    /// // Or create custom policy
    /// let customPolicy = GCPolicy(
    ///     name: "Custom",
    ///     description: "VACUUM when > 100 MB wasted",
    ///     shouldVacuum: { $0.wastedSpace > 100_000_000 }
    /// )
    /// db.setGCPolicy(customPolicy)
    /// ```
    public func setGCPolicy(_ policy: GCPolicy) {
        gcManager.setPolicy(policy)
    }
    
    /// Check if VACUUM is recommended based on current policy
    ///
    /// - Returns: True if policy recommends VACUUM
    ///
    /// ## Example
    /// ```swift
    /// if try await db.shouldVacuum() {
    ///     print("Running recommended VACUUM...")
    ///     try await db.vacuum()
    /// }
    /// ```
    public func shouldVacuum() async throws -> Bool {
        let stats = try await getStorageStats()
        return gcManager.shouldVacuum(stats: stats)
    }
    
    // MARK: - Metrics API
    
    /// Get garbage collection metrics
    ///
    /// - Returns: GC performance metrics
    ///
    /// ## Example
    /// ```swift
    /// let metrics = db.getGCMetrics()
    /// print(metrics.description)
    /// // Shows: VACUUMs run, pages reclaimed, performance
    /// ```
    public func getGCMetrics() -> GCMetrics {
        return gcManager.getMetrics()
    }
    
    /// Reset GC metrics
    public func resetGCMetrics() {
        gcManager.resetMetrics()
    }
    
    // MARK: - Control API
    
    /// Manually trigger page reuse cleanup
    ///
    /// Clears the reuseable pages pool (for testing or manual control).
    /// Use with caution - may increase disk usage.
    ///
    /// ## Example
    /// ```swift
    /// // Force fresh page allocation
    /// db.clearReuseablePages()
    /// ```
    public func clearReuseablePages() throws {
        BlazeLogger.warn("⚠️  Clearing reuseable pages pool")
        
        var layout = try StorageLayout.load(from: metaURL)
        layout.deletedPages.removeAll()
        try layout.save(to: metaURL)
        
        BlazeLogger.info("✅ Reuseable pages cleared")
    }
    
    /// Force immediate VACUUM (ignores policy)
    ///
    /// - Returns: VACUUM statistics
    ///
    /// ## Example
    /// ```swift
    /// let stats = try await db.forceVacuum()
    /// print("Force VACUUM: \(stats.sizeReclaimed / 1024 / 1024) MB reclaimed")
    /// ```
    public func forceVacuum() async throws -> VacuumStats {
        BlazeLogger.info("🧹 Force VACUUM requested")
        
        let stats = try await vacuum()
        gcManager.recordVacuum(stats: stats)
        
        return stats
    }
    
    /// Smart VACUUM (only runs if policy recommends)
    ///
    /// - Returns: VACUUM statistics if run, nil if skipped
    ///
    /// ## Example
    /// ```swift
    /// if let stats = try await db.smartVacuum() {
    ///     print("VACUUM ran: \(stats.description)")
    /// } else {
    ///     print("VACUUM skipped (not needed)")
    /// }
    /// ```
    public func smartVacuum() async throws -> VacuumStats? {
        let stats = try await getStorageStats()
        
        if gcManager.shouldVacuum(stats: stats) {
            BlazeLogger.info("🧹 Smart VACUUM: triggered by policy")
            let vacuumStats = try await vacuum()
            gcManager.recordVacuum(stats: vacuumStats)
            return vacuumStats
        } else {
            BlazeLogger.debug("🧹 Smart VACUUM: skipped (policy not met)")
            return nil
        }
    }
    
    // MARK: - Monitoring API
    
    /// Get comprehensive GC report
    ///
    /// - Returns: Formatted report with stats, metrics, and recommendations
    ///
    /// ## Example
    /// ```swift
    /// let report = try await db.getGCReport()
    /// print(report)
    /// ```
    public func getGCReport() async throws -> String {
        let storageStats = try await getStorageStats()
        let gcStats = try collection.getGCStats()
        let metrics = gcManager.getMetrics()
        let config = gcManager.getConfiguration()
        let policy = gcManager.getPolicy()
        
        var report = """
        ═══════════════════════════════════════════════════════════
        🧹 GARBAGE COLLECTION REPORT
        ═══════════════════════════════════════════════════════════
        
        DATABASE: \(name)
        
        📊 STORAGE STATS:
        \(storageStats.description)
        
        ♻️  GC STATS:
        \(gcStats.description)
        
        📈 GC METRICS:
        \(metrics.description)
        
        ⚙️  CONFIGURATION:
          Page reuse: \(config.enablePageReuse ? "✅ Enabled" : "❌ Disabled")
          Auto-VACUUM: \(config.autoVacuumEnabled ? "✅ Enabled" : "❌ Disabled")
          VACUUM on close: \(config.vacuumOnClose ? "✅ Yes" : "❌ No")
          VACUUM before backup: \(config.vacuumBeforeBackup ? "✅ Yes" : "❌ No")
        
        """
        
        if let policy = policy {
            report += """
            📋 POLICY: \(policy.name)
              \(policy.description)
            
            """
        }
        
        // Recommendations
        report += """
        💡 RECOMMENDATIONS:
        
        """
        
        if storageStats.wastePercentage > 50 {
            report += "  ⚠️  HIGH WASTE (\(String(format: "%.1f", storageStats.wastePercentage))%): Run vacuum() NOW!\n"
        } else if storageStats.wastePercentage > 30 {
            report += "  ⚠️  MODERATE WASTE (\(String(format: "%.1f", storageStats.wastePercentage))%): Consider running vacuum()\n"
        } else if storageStats.wastePercentage > 10 {
            report += "  ✅ LOW WASTE (\(String(format: "%.1f", storageStats.wastePercentage))%): VACUUM optional\n"
        } else {
            report += "  ✅ MINIMAL WASTE (\(String(format: "%.1f", storageStats.wastePercentage))%): No action needed\n"
        }
        
        if !config.enablePageReuse {
            report += "  ⚠️  Page reuse is DISABLED: Enable for better efficiency\n"
        }
        
        if !config.autoVacuumEnabled && storageStats.wastePercentage > 20 {
            report += "  💡 Consider enabling auto-VACUUM for hands-off maintenance\n"
        }
        
        if gcStats.reuseablePages > 1000 {
            report += "  📊 \(gcStats.reuseablePages) reuseable pages: Page reuse working well!\n"
        }
        
        report += """
        
        ═══════════════════════════════════════════════════════════
        """
        
        return report
    }
    
    // MARK: - Health Check API
    
    /// Check GC health and get recommendations
    ///
    /// - Returns: Health status and actionable recommendations
    ///
    /// ## Example
    /// ```swift
    /// let health = try await db.checkGCHealth()
    /// if health.needsAttention {
    ///     print("⚠️  \(health.recommendation)")
    /// }
    /// ```
    public func checkGCHealth() async throws -> GCHealthReport {
        let storageStats = try await getStorageStats()
        let gcStats = try collection.getGCStats()
        let config = gcManager.getConfiguration()
        
        var status: GCHealthStatus = .healthy
        var issues: [String] = []
        var recommendations: [String] = []
        
        // Check waste percentage
        if storageStats.wastePercentage > 50 {
            status = .critical
            issues.append("HIGH waste: \(String(format: "%.1f", storageStats.wastePercentage))%")
            recommendations.append("Run db.vacuum() immediately")
        } else if storageStats.wastePercentage > 30 {
            status = .warning
            issues.append("MODERATE waste: \(String(format: "%.1f", storageStats.wastePercentage))%")
            recommendations.append("Consider running db.vacuum()")
        }
        
        // Check if page reuse is working
        if storageStats.wastePercentage > 20 && gcStats.reuseablePages == 0 {
            status = status == .critical ? .critical : .warning
            issues.append("Page reuse not tracking deleted pages")
            recommendations.append("Check if deletedPages is being persisted")
        }
        
        // Check reuseable page pool size
        if gcStats.reuseablePages > 5000 {
            issues.append("Large reuse pool: \(gcStats.reuseablePages) pages")
            recommendations.append("Run VACUUM to compact reuse pool")
        }
        
        // Check if auto-vacuum would help
        if storageStats.wastePercentage > 20 && !config.autoVacuumEnabled {
            recommendations.append("Enable auto-VACUUM for automatic maintenance")
        }
        
        return GCHealthReport(
            status: status,
            wastePercentage: storageStats.wastePercentage,
            reuseablePages: gcStats.reuseablePages,
            issues: issues,
            recommendations: recommendations
        )
    }
}

// MARK: - GC Health Report

public struct GCHealthReport {
    public let status: GCHealthStatus
    public let wastePercentage: Double
    public let reuseablePages: Int
    public let issues: [String]
    public let recommendations: [String]
    
    public var needsAttention: Bool {
        return status != .healthy
    }
    
    public var description: String {
        var report = """
        GC Health: \(status.emoji) \(status.rawValue.uppercased())
        Waste: \(String(format: "%.1f", wastePercentage))%
        Reuseable pages: \(reuseablePages)
        
        """
        
        if !issues.isEmpty {
            report += "Issues:\n"
            for issue in issues {
                report += "  • \(issue)\n"
            }
            report += "\n"
        }
        
        if !recommendations.isEmpty {
            report += "Recommendations:\n"
            for rec in recommendations {
                report += "  → \(rec)\n"
            }
        }
        
        return report
    }
}

public enum GCHealthStatus: String {
    case healthy
    case warning
    case critical
    
    var emoji: String {
        switch self {
        case .healthy: return "✅"
        case .warning: return "⚠️"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Convenience APIs

extension BlazeDBClient {
    
    /// Quick GC status check
    ///
    /// ## Example
    /// ```swift
    /// let status = try await db.gcStatus()
    /// print(status)  // "✅ Healthy: 5.2% waste"
    /// ```
    public func gcStatus() async throws -> String {
        let health = try await checkGCHealth()
        return "\(health.status.emoji) \(health.status.rawValue.capitalized): \(String(format: "%.1f", health.wastePercentage))% waste"
    }
    
    /// Optimize database (smart VACUUM + cleanup)
    ///
    /// ## Example
    /// ```swift
    /// // One-button optimization
    /// let result = try await db.optimize()
    /// print(result)
    /// ```
    public func optimize() async throws -> String {
        BlazeLogger.info("🔧 Optimizing database '\(name)'...")
        
        var results: [String] = []
        
        // Check if VACUUM is needed
        if let vacuumStats = try await smartVacuum() {
            results.append("VACUUM: Reclaimed \(vacuumStats.sizeReclaimed / 1024 / 1024) MB")
        } else {
            results.append("VACUUM: Skipped (not needed)")
        }
        
        // Get final status
        let health = try await checkGCHealth()
        results.append("Status: \(health.status.emoji) \(health.status.rawValue)")
        
        return results.joined(separator: "\n")
    }
}

