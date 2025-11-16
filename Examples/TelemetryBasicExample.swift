//
//  TelemetryBasicExample.swift
//  BlazeDB Examples
//
//  How to use and verify basic telemetry (Option 1: Query APIs)
//

import Foundation
import BlazeDB

// MARK: - Example: How to Verify Telemetry Works

func verifyTelemetryWorks() async throws {
    print("\n🧪 TELEMETRY VERIFICATION TEST")
    print("================================\n")
    
    // Step 1: Create main database
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_app.blazedb")
    
    let db = try BlazeDBClient(name: "TestApp", fileURL: dbURL, password: "test123456")
    
    // Step 2: Enable telemetry
    db.telemetry.enable()
    print("✅ Telemetry enabled\n")
    
    // Step 3: Perform some operations
    print("📝 Performing test operations...\n")
    
    // Insert 5 records
    for i in 1...5 {
        _ = try await db.insert(BlazeDataRecord([
            "title": .string("Bug \(i)"),
            "status": .string("open")
        ]))
        print("  • Inserted bug \(i)")
    }
    
    // Query records
    let results = try await db.query()
        .where("status", equals: .string("open"))
        .execute()
    print("  • Queried \(results.count) bugs")
    
    // Update a record
    if let firstID = results.first?.storage["id"]?.uuidValue {
        try await db.update(id: firstID, with: [
            "status": .string("in-progress")
        ])
        print("  • Updated bug status")
    }
    
    // Delete a record (this will fail - no bug with this ID)
    do {
        try await db.delete(id: UUID())
        print("  • Deleted bug")
    } catch {
        print("  • Delete failed (expected)")
    }
    
    print("\n" + String(repeating: "─", count: 50) + "\n")
    
    // Step 4: CHECK TELEMETRY - This is what you'd use in real app!
    print("📊 TELEMETRY RESULTS:\n")
    
    // Method 1: Quick summary (easiest)
    print("METHOD 1: Quick Summary")
    print(String(repeating: "─", count: 50))
    let summary = try await db.telemetry.getSummary()
    print(summary.description)
    
    print("\n" + String(repeating: "─", count: 50) + "\n")
    
    // Method 2: Find slow operations
    print("METHOD 2: Slow Operations")
    print(String(repeating: "─", count: 50))
    let slowOps = try await db.telemetry.getSlowOperations(threshold: 5.0)
    if slowOps.isEmpty {
        print("✅ No slow operations (all < 5ms)")
    } else {
        for op in slowOps {
            print("⚠️  SLOW: \(op.operation) on '\(op.collectionName)' took \(String(format: "%.2f", op.duration))ms")
        }
    }
    
    print("\n" + String(repeating: "─", count: 50) + "\n")
    
    // Method 3: Check errors
    print("METHOD 3: Error Summary")
    print(String(repeating: "─", count: 50))
    let errors = try await db.telemetry.getErrors()
    print("Total errors: \(errors.count)")
    for error in errors {
        print("  ❌ \(error.operation): \(error.errorMessage ?? "Unknown error")")
    }
    
    print("\n" + String(repeating: "─", count: 50) + "\n")
    
    // Method 4: Operation breakdown
    print("METHOD 4: Operation Breakdown")
    print(String(repeating: "─", count: 50))
    let breakdown = try await db.telemetry.getOperationBreakdown()
    print(breakdown.description)
    
    print("\n" + String(repeating: "─", count: 50) + "\n")
    
    // Method 5: Recent operations
    print("METHOD 5: Recent Operations (Last 5)")
    print(String(repeating: "─", count: 50))
    let recent = try await db.telemetry.getRecentOperations(limit: 5)
    for (index, op) in recent.enumerated() {
        let icon = op.success ? "✅" : "❌"
        print("\(index + 1). \(icon) \(op.operation) - \(String(format: "%.2f", op.duration))ms")
    }
    
    print("\n" + String(repeating: "═", count: 50))
    print("✅ TELEMETRY VERIFICATION COMPLETE!")
    print("═" + String(repeating: "═", count: 50) + "\n")
    
    // Cleanup
    try? FileManager.default.removeItem(at: dbURL)
}

// MARK: - Example: Using Telemetry in Real App

func realAppExample() async throws {
    print("\n📱 REAL APP EXAMPLE: AshPile Bug Tracker")
    print("==========================================\n")
    
    let db = try BlazeDBClient(name: "AshPile", at: FileManager.default.homeDirectory)
    
    // Enable telemetry with 1% sampling
    db.telemetry.enable(samplingRate: 0.01)
    
    // Normal app operations (telemetry tracked automatically)
    _ = try await db.insert(BlazeDataRecord([
        "title": .string("Memory leak in login"),
        "priority": .string("high")
    ]))
    
    let bugs = try await db.query()
        .where("priority", equals: .string("high"))
        .execute()
    
    print("Found \(bugs.count) high-priority bugs\n")
    
    // Check performance occasionally (e.g., in debug menu)
    print("🔍 Performance Check:\n")
    let summary = try await db.telemetry.getSummary()
    
    if summary.avgDuration > 50 {
        print("⚠️  WARNING: Average operation time is \(String(format: "%.2f", summary.avgDuration))ms (slow!)")
        
        // Investigate slow operations
        let slowOps = try await db.telemetry.getSlowOperations(threshold: 50)
        print("\nSlow operations:")
        for op in slowOps {
            print("  • \(op.operation) on '\(op.collectionName)': \(String(format: "%.2f", op.duration))ms")
        }
    } else {
        print("✅ Performance looks good! Avg: \(String(format: "%.2f", summary.avgDuration))ms")
    }
    
    print()
}

// MARK: - Example: Debug Menu Integration

#if os(macOS)
import AppKit

extension NSMenu {
    /// Add telemetry debug menu to your app
    static func createTelemetryDebugMenu(db: BlazeDBClient) -> NSMenu {
        let menu = NSMenu(title: "Telemetry")
        
        // Show summary
        menu.addItem(NSMenuItem(
            title: "Show Performance Summary",
            action: #selector(showTelemetrySummary),
            keyEquivalent: ""
        ))
        
        // Show slow operations
        menu.addItem(NSMenuItem(
            title: "Show Slow Operations",
            action: #selector(showSlowOperations),
            keyEquivalent: ""
        ))
        
        // Show errors
        menu.addItem(NSMenuItem(
            title: "Show Errors",
            action: #selector(showErrors),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Clear metrics
        menu.addItem(NSMenuItem(
            title: "Clear Metrics",
            action: #selector(clearMetrics),
            keyEquivalent: ""
        ))
        
        return menu
    }
    
    @objc func showTelemetrySummary() {
        Task {
            // Get DB from app delegate or singleton
            guard let db = (NSApp.delegate as? AppDelegate)?.database else { return }
            
            let summary = try await db.telemetry.getSummary()
            
            let alert = NSAlert()
            alert.messageText = "📊 BlazeDB Performance"
            alert.informativeText = summary.description
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
    
    @objc func showSlowOperations() {
        Task {
            guard let db = (NSApp.delegate as? AppDelegate)?.database else { return }
            
            let slowOps = try await db.telemetry.getSlowOperations(threshold: 20)
            
            let alert = NSAlert()
            alert.messageText = "⚠️  Slow Operations"
            
            if slowOps.isEmpty {
                alert.informativeText = "✅ No slow operations found (all < 20ms)"
            } else {
                let text = slowOps.map { op in
                    "\(op.operation) on '\(op.collectionName)': \(String(format: "%.2f", op.duration))ms"
                }.joined(separator: "\n")
                alert.informativeText = text
            }
            
            alert.runModal()
        }
    }
    
    @objc func showErrors() {
        Task {
            guard let db = (NSApp.delegate as? AppDelegate)?.database else { return }
            
            let errors = try await db.telemetry.getErrors()
            
            let alert = NSAlert()
            alert.messageText = "❌ Recent Errors"
            
            if errors.isEmpty {
                alert.informativeText = "✅ No errors"
            } else {
                let text = errors.map { error in
                    "\(error.operation): \(error.errorMessage ?? "Unknown")"
                }.joined(separator: "\n")
                alert.informativeText = text
            }
            
            alert.runModal()
        }
    }
    
    @objc func clearMetrics() {
        Task {
            guard let db = (NSApp.delegate as? AppDelegate)?.database else { return }
            
            try await db.telemetry.clear()
            
            let alert = NSAlert()
            alert.messageText = "✅ Metrics Cleared"
            alert.informativeText = "All telemetry data has been deleted."
            alert.runModal()
        }
    }
}

// Stub for example
class AppDelegate: NSObject, NSApplicationDelegate {
    var database: BlazeDBClient?
}
#endif

// MARK: - Run Examples

// To verify telemetry works, run:
// Task {
//     try await verifyTelemetryWorks()
// }

// To see real app usage:
// Task {
//     try await realAppExample()
// }

