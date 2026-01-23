//
//  BlazeDBClient+Health.swift
//  BlazeDB
//
//  Health reporting API
//  Uses existing stats - no new data collection
//

import Foundation

extension BlazeDBClient {
    
    /// Get database health report
    ///
    /// Analyzes current statistics and returns a health verdict with guidance.
    /// - Returns: Health report with status (OK/WARN/ERROR) and actionable suggestions
    /// - Throws: Error if stats cannot be retrieved
    ///
    /// ## Example
    /// ```swift
    /// let health = try db.health()
    /// print(health.summary)
    /// if health.status == .warn {
    ///     for action in health.suggestedActions {
    ///         print("  - \(action)")
    ///     }
    /// }
    /// ```
    public func health() throws -> HealthReport {
        let stats = try self.stats()
        var report = HealthAnalyzer.analyze(stats)
        
        // Add resource limit warnings
        let resourceWarnings = DatabaseHealth.checkResourceLimits(stats: stats)
        if !resourceWarnings.isEmpty {
            // Upgrade status if needed
            if report.status == .ok {
                report = HealthReport(
                    status: .warn,
                    reasons: report.reasons + resourceWarnings,
                    suggestedActions: report.suggestedActions
                )
            } else {
                report = HealthReport(
                    status: report.status,
                    reasons: report.reasons + resourceWarnings,
                    suggestedActions: report.suggestedActions
                )
            }
        }
        
        return report
    }
}
