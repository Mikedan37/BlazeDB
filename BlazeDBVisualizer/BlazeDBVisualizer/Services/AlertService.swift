//
//  AlertService.swift
//  BlazeDBVisualizer
//
//  Auto-notify users about database health issues
//  ✅ macOS notifications
//  ✅ Configurable thresholds
//  ✅ Smart alerting (no spam!)
//
//  Created by Michael Danylchuk on 11/14/25.
//

import Foundation
import SwiftUI
import UserNotifications
import BlazeDB

final class AlertService: ObservableObject {
    
    static let shared = AlertService()
    
    @Published var config: AlertConfiguration = .default
    @Published var recentAlerts: [Alert] = []
    
    private var lastAlertTimes: [String: Date] = [:]  // Prevent spam
    private let minAlertInterval: TimeInterval = 300  // 5 minutes between same alerts
    
    private init() {
        requestNotificationPermissions()
    }
    
    // MARK: - Permission
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permissions granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error)")
            }
        }
    }
    
    // MARK: - Health Monitoring
    
    /// Check database health and send alerts if needed
    func checkHealth(snapshot: DatabaseMonitoringSnapshot, dbName: String) {
        var alerts: [Alert] = []
        
        // Check fragmentation
        if config.fragmentationThreshold > 0 &&
           snapshot.storage.fragmentationPercent > config.fragmentationThreshold {
            let alert = Alert(
                type: .highFragmentation,
                title: "High Fragmentation Detected",
                message: "\(dbName): \(String(format: "%.1f", snapshot.storage.fragmentationPercent))% fragmentation. Consider running VACUUM.",
                severity: snapshot.storage.fragmentationPercent > 50 ? .critical : .warning,
                databaseName: dbName
            )
            alerts.append(alert)
        }
        
        // Check database size
        if config.maxDatabaseSize > 0 &&
           snapshot.storage.fileSizeBytes > config.maxDatabaseSize {
            let sizeMB = Double(snapshot.storage.fileSizeBytes) / 1_000_000
            let alert = Alert(
                type: .databaseTooLarge,
                title: "Database Size Alert",
                message: "\(dbName) is \(String(format: "%.1f", sizeMB)) MB. Consider archiving old data.",
                severity: .warning,
                databaseName: dbName
            )
            alerts.append(alert)
        }
        
        // Check obsolete versions (GC needed)
        if config.obsoleteVersionsThreshold > 0 &&
           snapshot.performance.obsoleteVersions > config.obsoleteVersionsThreshold {
            let alert = Alert(
                type: .gcNeeded,
                title: "Garbage Collection Needed",
                message: "\(dbName): \(snapshot.performance.obsoleteVersions) obsolete versions. Run GC to free memory.",
                severity: .info,
                databaseName: dbName
            )
            alerts.append(alert)
        }
        
        // Check orphaned pages
        if config.orphanedPagesThreshold > 0 &&
           snapshot.storage.orphanedPages > config.orphanedPagesThreshold {
            let alert = Alert(
                type: .orphanedPages,
                title: "Orphaned Pages Detected",
                message: "\(dbName): \(snapshot.storage.orphanedPages) orphaned pages. Run VACUUM to reclaim space.",
                severity: .info,
                databaseName: dbName
            )
            alerts.append(alert)
        }
        
        // Send alerts
        for alert in alerts {
            sendAlert(alert)
        }
    }
    
    // MARK: - Alert Sending
    
    private func sendAlert(_ alert: Alert) {
        // Check if we recently sent this alert (prevent spam)
        let alertKey = "\(alert.databaseName)_\(alert.type)"
        if let lastTime = lastAlertTimes[alertKey],
           Date().timeIntervalSince(lastTime) < minAlertInterval {
            return  // Too soon, skip
        }
        
        // Send notification
        if config.notificationsEnabled {
            sendNotification(alert: alert)
        }
        
        // Add to recent alerts
        DispatchQueue.main.async {
            self.recentAlerts.insert(alert, at: 0)
            
            // Keep only last 50
            if self.recentAlerts.count > 50 {
                self.recentAlerts = Array(self.recentAlerts.prefix(50))
            }
        }
        
        // Update last alert time
        lastAlertTimes[alertKey] = Date()
    }
    
    private func sendNotification(alert: Alert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        
        // Set badge based on severity
        switch alert.severity {
        case .critical:
            content.badge = NSNumber(value: recentAlerts.filter { $0.severity == .critical }.count + 1)
        default:
            break
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error)")
            }
        }
    }
    
    // MARK: - Alert Management
    
    func clearAlerts() {
        recentAlerts.removeAll()
    }
    
    func dismissAlert(_ alert: Alert) {
        recentAlerts.removeAll { $0.id == alert.id }
    }
}

// MARK: - Alert Model

struct Alert: Identifiable {
    let id = UUID()
    let type: AlertType
    let title: String
    let message: String
    let severity: AlertSeverity
    let databaseName: String
    let timestamp = Date()
}

enum AlertType {
    case highFragmentation
    case databaseTooLarge
    case gcNeeded
    case orphanedPages
    case healthStatusChanged
}

enum AlertSeverity {
    case info
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Configuration

struct AlertConfiguration {
    var notificationsEnabled: Bool = true
    var fragmentationThreshold: Double = 30.0  // %
    var maxDatabaseSize: Int64 = 1_000_000_000  // 1 GB
    var obsoleteVersionsThreshold: Int = 1000
    var orphanedPagesThreshold: Int = 100
    
    static let `default` = AlertConfiguration()
}

