//  DetailView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
//
//  ✅ UPGRADED: Now integrates with monitoring dashboard
//  ✅ Password unlock with Face ID support
//  ✅ Live monitoring and management tools
//
import SwiftUI
import AppKit

struct DetailView: View {
    let db: DBRecord
    var onDelete: (() -> Void)? = nil
    
    @State private var showingPasswordPrompt = false
    @State private var isUnlocked = false
    @State private var unlockedPassword: String?
    @State private var showingDeleteAlert = false
    @State private var isDeleted = false
    
    var body: some View {
        ZStack {
            if isDeleted {
                deletedView
            } else if isUnlocked, let password = unlockedPassword {
                // Show monitoring dashboard after unlock
                MonitoringDashboardView(dbRecord: db, password: password)
            } else {
                // Show locked state
                lockedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .center) {
            if showingPasswordPrompt {
                ZStack {
                    // Dimmed background
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Dismiss on background tap
                            showingPasswordPrompt = false
                        }
                    
                    // Password prompt
                    PasswordPromptView(
                        dbRecord: db,
                        onUnlock: { password in
                            unlockedPassword = password
                            isUnlocked = true
                            showingPasswordPrompt = false
                        },
                        onCancel: {
                            showingPasswordPrompt = false
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                .animation(.spring(), value: showingPasswordPrompt)
            }
        }
        .alert("Delete this database?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \(db.name) and all its data. This cannot be undone.")
        }
        .onChange(of: db.id) { _, _ in
            // Reset state when database changes
            isDeleted = false
            isUnlocked = false
            unlockedPassword = nil
            showingPasswordPrompt = false
        }
    }
    
    // MARK: - Locked View
    
    private var lockedView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                // Header with gradient background
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange.gradient)
                    }
                    
                    VStack(spacing: 6) {
                        Text(db.name)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text(db.appName)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Stats Grid (quick overview without password)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    QuickStatCard(icon: "doc.text", label: "Records", value: "\(db.recordCount)")
                    QuickStatCard(icon: "chart.bar", label: "Size", value: db.sizeFormatted)
                    QuickStatCard(icon: "calendar", label: "Modified", value: db.modifiedDate.formatted(date: .numeric, time: .omitted))
                    QuickStatCard(icon: "lock.fill", label: "Encrypted", value: db.isEncrypted ? "Yes" : "No")
                }
                .padding(.horizontal, 40)
                
                // Path (collapsible)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack {
                        Text(db.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(db.path, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal, 40)
                
                // Unlock button (prominent!)
                VStack(spacing: 12) {
                    Button(action: {
                        showingPasswordPrompt = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.open.fill")
                                .font(.title3)
                            Text("Unlock Database")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(width: 280)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.gradient)
                        )
                        .foregroundStyle(.white)
                        .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    
                    Text("Access monitoring, data viewer, queries, charts, and more")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                    .frame(height: 20)
                
                // Delete button (subtle at bottom)
                Button(role: .destructive, action: {
                    showingDeleteAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text("Delete Database")
                            .font(.callout)
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                
                Spacer()
                    .frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Deleted View
    
    private var deletedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Database Deleted")
                .font(.title.bold())
            
            Text("\(db.name) has been permanently removed")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func deleteDatabase() {
        let fileManager = FileManager.default
        
        // Delete main database file
        try? fileManager.removeItem(at: db.fileURL)
        
        // Delete metadata file
        let metaURL = db.fileURL.deletingPathExtension().appendingPathExtension("meta")
        try? fileManager.removeItem(at: metaURL)
        
        // Delete transaction log
        let txnLogURL = db.fileURL.deletingPathExtension().appendingPathExtension("txn_log.json")
        try? fileManager.removeItem(at: txnLogURL)
        
        // Delete stored password
        try? PasswordVaultService.shared.deletePassword(for: db.path)
        
        isDeleted = true
        
        // Notify parent to refresh list
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onDelete?()
        }
    }
}

// MARK: - Quick Stat Card Component

struct QuickStatCard: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
            
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
