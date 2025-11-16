//
//  MonitoringService.swift
//  BlazeDBVisualizer
//
//  Real-time database monitoring service
//  ✅ Live updates every 5 seconds
//  ✅ Automatic health checks
//  ✅ Background refresh
//
//  Created by Michael Danylchuk on 11/13/25.
//

import Foundation
import BlazeDB
import Combine

/// Real-time monitoring service for active databases
/// Provides live updates for dashboard UI
@MainActor
final class MonitoringService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentSnapshot: DatabaseMonitoringSnapshot?
    @Published var isMonitoring = false
    @Published var lastUpdateTime: Date?
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private var monitoringTask: Task<Void, Never>?
    private var refreshInterval: TimeInterval = 5.0  // 5 seconds
    private var dbClient: BlazeDBClient?
    
    // MARK: - Lifecycle
    
    init() {}
    
    deinit {
        // Cancel monitoring task
        monitoringTask?.cancel()
        monitoringTask = nil
        dbClient = nil
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring a database
    /// - Parameters:
    ///   - dbPath: Path to the database file
    ///   - password: Database password
    ///   - interval: Refresh interval (default: 5 seconds)
    func startMonitoring(dbPath: String, password: String, interval: TimeInterval = 5.0) async throws {
        // Stop existing monitoring
        stopMonitoring()
        
        // Open database
        let url = URL(fileURLWithPath: dbPath)
        let name = url.deletingPathExtension().lastPathComponent
        self.dbClient = try BlazeDBClient(name: name, fileURL: url, password: password)
        
        self.refreshInterval = interval
        self.isMonitoring = true
        self.error = nil
        
        // Start monitoring loop
        monitoringTask = Task { [weak self] in
            await self?.monitoringLoop()
        }
    }
    
    /// Stop monitoring and close database
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        dbClient = nil
        isMonitoring = false
        currentSnapshot = nil
    }
    
    /// Manually refresh snapshot (for user-triggered refresh)
    func refresh() async {
        await fetchSnapshot()
    }
    
    /// Run VACUUM operation on the database
    func runVacuum() async throws -> Int {
        guard let db = dbClient else {
            throw MonitoringError.notMonitoring
        }
        
        let bytesReclaimed = try await Task.detached {
            try db.vacuum()
        }.value
        
        // Refresh snapshot immediately after vacuum
        await fetchSnapshot()
        
        return bytesReclaimed
    }
    
    /// Run garbage collection
    func runGarbageCollection() async throws -> Int {
        guard let db = dbClient else {
            throw MonitoringError.notMonitoring
        }
        
        let collected = await Task.detached {
            db.runGarbageCollection()
        }.value
        
        // Refresh snapshot immediately after GC
        await fetchSnapshot()
        
        return collected
    }
    
    // MARK: - Private Methods
    
    private func monitoringLoop() async {
        while !Task.isCancelled && isMonitoring {
            await fetchSnapshot()
            
            // Wait for next refresh interval
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
            } catch {
                // Task was cancelled, exit loop
                break
            }
        }
    }
    
    private func fetchSnapshot() async {
        guard let db = dbClient else {
            return
        }
        
        do {
            let snapshot = try await Task.detached {
                try db.getMonitoringSnapshot()
            }.value
            
            await MainActor.run {
                self.currentSnapshot = snapshot
                self.lastUpdateTime = Date()
                self.error = nil
            }
        } catch {
            await MainActor.run {
                self.error = error
            }
        }
    }
}

// MARK: - Errors

enum MonitoringError: LocalizedError {
    case notMonitoring
    case databaseClosed
    
    var errorDescription: String? {
        switch self {
        case .notMonitoring:
            return "Database is not being monitored"
        case .databaseClosed:
            return "Database connection has been closed"
        }
    }
}

// MARK: - Helper Extensions

extension DatabaseMonitoringSnapshot {
    
    /// Human-readable summary of the database
    var summary: String {
        let health = health.status.uppercased()
        let records = storage.totalRecords
        let size = ByteCountFormatter.string(fromByteCount: storage.fileSizeBytes, countStyle: .file)
        return "\(health) | \(records) records | \(size)"
    }
    
    /// Quick health check result
    var needsAttention: Bool {
        health.status != "healthy" || health.needsVacuum || health.gcNeeded
    }
    
    /// List of recommended actions
    var recommendations: [String] {
        var actions: [String] = []
        
        if health.needsVacuum {
            actions.append("Run VACUUM to reclaim space")
        }
        
        if health.gcNeeded {
            actions.append("Run garbage collection")
        }
        
        if storage.fragmentationPercent > 30 {
            actions.append("High fragmentation detected")
        }
        
        if performance.obsoleteVersions > 1000 {
            actions.append("Clean up old MVCC versions")
        }
        
        return actions
    }
}

