//
//  AshPileDebugMenu.swift
//  AshPile Debug Menu Integration
//
//  How to add telemetry debug menu to AshPile
//

#if os(macOS)
import SwiftUI
import BlazeDB

// MARK: - Debug Menu for AshPile

struct AshPileApp_WithTelemetry: App {
    @StateObject private var database = DatabaseManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(database)
        }
        .commands {
            // Add Debug menu
            DebugCommands(database: database.db)
        }
    }
}

// MARK: - Debug Menu Commands

struct DebugCommands: Commands {
    let database: BlazeDBClient?
    
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Show Performance Stats") {
                Task {
                    await showPerformanceStats()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            
            Button("Show Slow Operations") {
                Task {
                    await showSlowOperations()
                }
            }
            
            Button("Show Recent Errors") {
                Task {
                    await showErrors()
                }
            }
            
            Divider()
            
            Button("Clear Telemetry Data") {
                Task {
                    await clearTelemetry()
                }
            }
            
            Button("Export Telemetry Report") {
                Task {
                    await exportTelemetryReport()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    func showPerformanceStats() async {
        guard let db = database else { return }
        
        do {
            let summary = try await db.telemetry.getSummary()
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "📊 BlazeDB Performance"
                alert.informativeText = summary.description
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            showError("Failed to get telemetry: \(error.localizedDescription)")
        }
    }
    
    func showSlowOperations() async {
        guard let db = database else { return }
        
        do {
            let slowOps = try await db.telemetry.getSlowOperations(threshold: 20.0)
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "⚠️  Slow Operations (> 20ms)"
                
                if slowOps.isEmpty {
                    alert.informativeText = "✅ No slow operations found!\nAll operations are fast."
                } else {
                    var text = "Found \(slowOps.count) slow operations:\n\n"
                    for (i, op) in slowOps.prefix(10).enumerated() {
                        text += "\(i + 1). \(op.operation) on '\(op.collectionName)': \(String(format: "%.2f", op.duration))ms\n"
                    }
                    if slowOps.count > 10 {
                        text += "\n... and \(slowOps.count - 10) more"
                    }
                    alert.informativeText = text
                    alert.alertStyle = .warning
                }
                
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            showError("Failed to get slow operations: \(error.localizedDescription)")
        }
    }
    
    func showErrors() async {
        guard let db = database else { return }
        
        do {
            let errors = try await db.telemetry.getErrors(last: 20)
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "❌ Recent Errors"
                
                if errors.isEmpty {
                    alert.informativeText = "✅ No errors found!\nDatabase is operating normally."
                    alert.alertStyle = .informational
                } else {
                    var text = "Found \(errors.count) recent errors:\n\n"
                    for (i, error) in errors.prefix(10).enumerated() {
                        text += "\(i + 1). \(error.operation): \(error.errorMessage)\n"
                    }
                    alert.informativeText = text
                    alert.alertStyle = .critical
                }
                
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            showError("Failed to get errors: \(error.localizedDescription)")
        }
    }
    
    func clearTelemetry() async {
        guard let db = database else { return }
        
        do {
            try await db.telemetry.clear()
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "✅ Telemetry Cleared"
                alert.informativeText = "All telemetry data has been deleted."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            showError("Failed to clear telemetry: \(error.localizedDescription)")
        }
    }
    
    func exportTelemetryReport() async {
        guard let db = database else { return }
        
        do {
            let summary = try await db.telemetry.getSummary()
            let breakdown = try await db.telemetry.getOperationBreakdown()
            let slowOps = try await db.telemetry.getSlowOperations(threshold: 20.0)
            let errors = try await db.telemetry.getErrors()
            
            // Generate report
            var report = """
            ═══════════════════════════════════════════════════
            📊 BLAZEDB TELEMETRY REPORT
            ═══════════════════════════════════════════════════
            Generated: \(Date())
            
            \(summary.description)
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            \(breakdown.description)
            
            """
            
            if !slowOps.isEmpty {
                report += """
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                ⚠️  SLOW OPERATIONS (> 20ms):
                
                """
                for (i, op) in slowOps.prefix(20).enumerated() {
                    report += "\(i + 1). \(op.operation) on '\(op.collectionName)': \(String(format: "%.2f", op.duration))ms\n"
                }
            }
            
            if !errors.isEmpty {
                report += """
                
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                ❌ RECENT ERRORS:
                
                """
                for (i, error) in errors.prefix(20).enumerated() {
                    report += "\(i + 1). \(error.operation): \(error.errorMessage)\n"
                }
            }
            
            report += """
            
            ═══════════════════════════════════════════════════
            END OF REPORT
            ═══════════════════════════════════════════════════
            """
            
            // Save to file
            DispatchQueue.main.async {
                let savePanel = NSSavePanel()
                savePanel.title = "Export Telemetry Report"
                savePanel.nameFieldStringValue = "BlazeDB_Telemetry_\(Date().timeIntervalSince1970).txt"
                savePanel.canCreateDirectories = true
                
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        do {
                            try report.write(to: url, atomically: true, encoding: .utf8)
                            
                            let alert = NSAlert()
                            alert.messageText = "✅ Report Exported"
                            alert.informativeText = "Telemetry report saved to:\n\(url.path)"
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        } catch {
                            self.showError("Failed to save report: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            showError("Failed to generate report: \(error.localizedDescription)")
        }
    }
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Database Manager (Singleton)

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    @Published var db: BlazeDBClient?
    
    private init() {
        do {
            let dbURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ashpile")
                .appendingPathComponent("ashpile.blazedb")
            
            // Create directory if needed
            let dir = dbURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            
            // Initialize database
            db = try BlazeDBClient(name: "AshPile", fileURL: dbURL, password: "your-secure-password")
            
            // Enable telemetry with 1% sampling
            db?.telemetry.enable(samplingRate: 0.01)
            
            print("✅ AshPile database initialized with telemetry")
        } catch {
            print("❌ Failed to initialize database: \(error)")
        }
    }
}

// MARK: - SwiftUI View with Telemetry Status

struct TelemetryStatusView: View {
    let database: BlazeDBClient?
    @State private var summary: TelemetrySummary?
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📊 Performance")
                    .font(.headline)
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadTelemetry()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            if let summary = summary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Operations:")
                        Spacer()
                        Text("\(summary.totalOperations)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Avg Duration:")
                        Spacer()
                        Text("\(String(format: "%.2f", summary.avgDuration))ms")
                            .foregroundColor(summary.avgDuration < 10 ? .green : summary.avgDuration < 50 ? .orange : .red)
                    }
                    
                    HStack {
                        Text("Success Rate:")
                        Spacer()
                        Text("\(String(format: "%.1f", summary.successRate))%")
                            .foregroundColor(summary.successRate > 95 ? .green : .orange)
                    }
                    
                    if summary.errorCount > 0 {
                        HStack {
                            Text("Errors:")
                            Spacer()
                            Text("\(summary.errorCount)")
                                .foregroundColor(.red)
                        }
                    }
                }
                .font(.caption)
                .padding(.top, 4)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Text("No telemetry data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .task {
            await loadTelemetry()
        }
    }
    
    func loadTelemetry() async {
        guard let db = database else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let loadedSummary = try await db.telemetry.getSummary()
            await MainActor.run {
                self.summary = loadedSummary
            }
        } catch {
            print("Failed to load telemetry: \(error)")
        }
    }
}

// MARK: - Example: Telemetry in Settings View

struct SettingsView_WithTelemetry: View {
    let database: BlazeDBClient?
    
    var body: some View {
        Form {
            Section("Database") {
                // ... other settings ...
            }
            
            Section("Performance") {
                TelemetryStatusView(database: database)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Stub ContentView for Example

struct ContentView: View {
    var body: some View {
        Text("AshPile with Telemetry")
    }
}

#endif

