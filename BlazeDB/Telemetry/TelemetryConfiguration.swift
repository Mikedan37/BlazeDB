//
//  TelemetryConfiguration.swift
//  BlazeDB
//
//  Telemetry configuration
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Configuration for telemetry tracking
public struct TelemetryConfiguration {
    /// Whether telemetry is enabled
    public var enabled: Bool = false
    
    /// Sampling rate (0.0 - 1.0)
    /// 0.01 = 1% of operations tracked
    /// 1.0 = 100% of operations tracked
    public var samplingRate: Double = 0.01
    
    /// Retention period in days (delete metrics older than this)
    public var retentionDays: Int = 30
    
    /// Auto-cleanup (automatically delete old metrics)
    public var autoCleanup: Bool = true
    
    /// Cleanup interval in seconds (how often to run cleanup)
    public var cleanupInterval: TimeInterval = 86400  // 24 hours
    
    /// Slow operation threshold (ms) - log warnings for operations slower than this
    public var slowOperationThreshold: Double = 100.0
    
    /// Metrics database URL (where to store metrics).
    ///
    /// Default when `nil`: `<Application Support>/BlazeDB/metrics/telemetry.blazedb` on Apple platforms
    /// (macOS: under `~/Library/...`; iOS: app sandbox). Legacy layouts used `~/.blazedb/metrics/`; see
    /// `Docs/GettingStarted/DEFAULT_STORAGE_PATHS.md`.
    public var metricsURL: URL
    
    public init(metricsURL: URL? = nil) {
        if let url = metricsURL {
            self.metricsURL = url
        } else {
            // Default: Application Support/BlazeDB/metrics/ (macOS + iOS sandbox; avoid homeDirectoryForCurrentUser on iOS)
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.metricsURL = base
                .appendingPathComponent("BlazeDB", isDirectory: true)
                .appendingPathComponent("metrics", isDirectory: true)
                .appendingPathComponent("telemetry.blazedb")
        }
    }
}

