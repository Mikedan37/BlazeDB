//
//  ProgressMonitorExample.swift
//  BlazeDB Examples
//
//  Complete example of using MigrationProgressMonitor for UI updates
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB
import SwiftUI

// MARK: - SwiftUI Progress View Example

struct MigrationProgressView: View {
    @StateObject private var monitor = MigrationProgressMonitor()
    @State private var progress: MigrationProgress?
    @State private var isMigrating = false
    
    var body: some View {
        VStack(spacing: 20) {
            if let progress = progress {
                // Status
                Text("Status: \(progress.status.rawValue)")
                    .font(.headline)
                
                // Current table
                if let table = progress.currentTable {
                    Text("Table: \(table) (\(progress.currentTableIndex)/\(progress.totalTables))")
                        .font(.subheadline)
                }
                
                // Progress bar
                ProgressView(value: progress.percentage / 100.0) {
                    Text("\(String(format: "%.1f", progress.percentage))%")
                }
                
                // Records
                if let total = progress.recordsTotal {
                    Text("Records: \(progress.recordsProcessed) / \(total)")
                } else {
                    Text("Records: \(progress.recordsProcessed)")
                }
                
                // Time info
                HStack {
                    Text("Elapsed: \(String(format: "%.1f", progress.elapsedTime))s")
                    if let remaining = progress.estimatedTimeRemaining {
                        Text("• Remaining: \(String(format: "%.0f", remaining))s")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                // Error
                if let error = progress.error {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                }
            } else {
                Text("Ready to migrate")
            }
            
            // Start button
            Button("Start Migration") {
                startMigration()
            }
            .disabled(isMigrating)
        }
        .padding()
        .onAppear {
            // Poll progress every 0.1 seconds
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                progress = monitor.getProgress()
            }
        }
    }
    
    private func startMigration() {
        isMigrating = true
        
        Task {
            do {
                try SQLiteMigrator.importFromSQLite(
                    source: URL(fileURLWithPath: "/path/to/app.sqlite"),
                    destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
                    password: "password",
                    progressMonitor: monitor
                )
            } catch {
                print("Migration failed: \(error)")
            }
            
            isMigrating = false
        }
    }
}

// MARK: - Observer Pattern Example

class MigrationManager: ObservableObject {
    @Published var progress: MigrationProgress?
    private let monitor = MigrationProgressMonitor()
    private var observerID: UUID?
    
    init() {
        // Subscribe to progress updates
        observerID = monitor.addObserver { [weak self] progress in
            DispatchQueue.main.async {
                self?.progress = progress
            }
        }
    }
    
    deinit {
        if let id = observerID {
            monitor.removeObserver(id)
        }
    }
    
    func startMigration() {
        Task {
            try SQLiteMigrator.importFromSQLite(
                source: URL(fileURLWithPath: "/path/to/app.sqlite"),
                destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
                password: "password",
                progressMonitor: monitor
            )
        }
    }
}

// MARK: - Polling Example (Non-SwiftUI)

class MigrationProgressPoller {
    private let monitor = MigrationProgressMonitor()
    private var timer: Timer?
    
    func startMigration() {
        // Start migration in background
        Task {
            try SQLiteMigrator.importFromSQLite(
                source: URL(fileURLWithPath: "/path/to/app.sqlite"),
                destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
                password: "password",
                progressMonitor: monitor
            )
        }
        
        // Poll progress
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let progress = self.monitor.getProgress()
            print("Progress: \(String(format: "%.1f", progress.percentage))%")
            print("Status: \(progress.status.rawValue)")
            print("Records: \(progress.recordsProcessed)/\(progress.recordsTotal ?? 0)")
            
            if progress.status == .completed || progress.status == .failed {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

