//
//  BackupRestoreView.swift
//  BlazeDBVisualizer
//
//  Backup and restore databases
//  ✅ Create named backups
//  ✅ Browse backup history
//  ✅ One-click restore
//  ✅ Auto-backup before VACUUM
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI

struct BackupRestoreView: View {
    let dbPath: String
    let password: String
    
    @State private var backups: [BackupInfo] = []
    @State private var isLoading = false
    @State private var isCreatingBackup = false
    @State private var backupName: String = ""
    @State private var selectedBackup: BackupInfo?
    @State private var showingRestoreConfirm = false
    @State private var statusMessage: String?
    
    private let backupService = BackupRestoreService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(.cyan.gradient)
                
                Text("Backup & Restore")
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: loadBackups) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            .padding()
            
            Divider()
            
            // Scrollable content area
            ScrollView {
                VStack(spacing: 16) {
                    // Create Backup Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Create Backup")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            TextField("Backup name (optional)", text: $backupName)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: createBackup) {
                                HStack {
                                    if isCreatingBackup {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                    }
                                    Text("Create")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(isCreatingBackup)
                        }
                        
                        Text("Creates a snapshot you can restore later")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Status Message
                    if let message = statusMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(message)
                                .font(.callout)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Backup List Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Backup History")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("\(backups.count) backups")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if backups.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No backups yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Create your first backup to protect your data")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            
                        } else {
                            VStack(spacing: 8) {
                                ForEach(backups) { backup in
                                    Button(action: { selectedBackup = backup }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(backup.name)
                                                    .font(.callout.bold())
                                                    .foregroundColor(.primary)
                                                
                                                HStack(spacing: 12) {
                                                    Label(backup.sizeFormatted, systemImage: "doc")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    
                                                    Label(backup.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if selectedBackup?.id == backup.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.cyan)
                                            }
                                        }
                                        .padding()
                                        .background(selectedBackup?.id == backup.id ? Color.cyan.opacity(0.1) : Color.secondary.opacity(0.05))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Action buttons (when backup selected)
                    if let selected = selectedBackup {
                        HStack(spacing: 12) {
                            Button(role: .destructive, action: { deleteBackup(selected) }) {
                                Label("Delete Backup", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Button(action: { showingRestoreConfirm = true }) {
                                Label("Restore Database", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                        .frame(height: 20)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Restore Backup?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                if let selected = selectedBackup {
                    restoreBackup(selected)
                }
            }
        } message: {
            Text("This will replace the current database with the backup. The current database will be backed up first for safety.")
        }
        .task {
            loadBackups()
        }
    }
    
    // MARK: - Actions
    
    private func loadBackups() {
        isLoading = true
        
        Task { @MainActor in
            do {
                backups = try backupService.listBackups(for: dbPath)
                isLoading = false
            } catch {
                print("❌ Error loading backups: \(error)")
                isLoading = false
            }
        }
    }
    
    private func createBackup() {
        isCreatingBackup = true
        statusMessage = nil
        
        Task { @MainActor in
            do {
                let backupURL = try backupService.createBackup(
                    dbPath: dbPath,
                    name: backupName.isEmpty ? nil : backupName
                )
                
                statusMessage = "Backup created: \(backupURL.lastPathComponent)"
                backupName = ""
                
                // Refresh list
                loadBackups()
                
                // Clear message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                statusMessage = nil
                
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
            
            isCreatingBackup = false
        }
    }
    
    private func restoreBackup(_ backup: BackupInfo) {
        Task { @MainActor in
            do {
                try backupService.restoreFromBackup(backupURL: backup.url, to: dbPath)
                statusMessage = "Restored from: \(backup.name)"
                
                // Clear message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                statusMessage = nil
                
            } catch {
                statusMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteBackup(_ backup: BackupInfo) {
        Task { @MainActor in
            do {
                try backupService.deleteBackup(backupURL: backup.url)
                loadBackups()
                selectedBackup = nil
                statusMessage = "Backup deleted"
                
                // Clear message after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                statusMessage = nil
                
            } catch {
                statusMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }
}


