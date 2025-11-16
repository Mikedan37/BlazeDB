//  MenuExtraView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
//
//  ✅ Simple menu bar dropdown for quick access
//  ✅ Click "Open Window" for full features
//
import SwiftUI
import BlazeDB

struct MenuExtraView: View {
    @State private var databases: [DBRecord] = []
    @State private var searchText: String = ""
    @State private var showingCreateDatabase = false
    @State private var hoveredButton: String?
    @Environment(\.openWindow) private var openWindow
    
    var filteredDatabases: [DBRecord] {
        if searchText.isEmpty {
            return databases
        } else {
            return databases.filter { db in
                db.name.localizedCaseInsensitiveContains(searchText) ||
                db.path.localizedCaseInsensitiveContains(searchText) ||
                db.appName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.orange.gradient)
                    
                    Text("BlazeDB Manager")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Spacer()
                    
                    Button(action: { showingCreateDatabase = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Create New Database")
                }
                
                Text("\(databases.count) \(databases.count == 1 ? "database" : "databases") found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .padding(.bottom, 8)
            
            // Search Bar
            if !databases.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Search databases...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            
            // Scrollable Database List
            if !filteredDatabases.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(filteredDatabases.enumerated()), id: \.element.id) { index, db in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(healthColor(db.healthStatus))
                                        .frame(width: 8, height: 8)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(db.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        Text("\(db.recordCount) records • \(db.sizeFormatted)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer(minLength: 0)
                                }
                                
                                // Path/Location
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    
                                    Text(extractDirectory(from: db.path))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.leading, 18)  // Align with text above
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.05))
                            )
                            .scaleEffect(hoveredButton == db.id.uuidString ? 1.02 : 1.0)
                            .animation(BlazeAnimation.quick, value: hoveredButton)
                            .onHover { hovering in
                                withAnimation(BlazeAnimation.quick) {
                                    hoveredButton = hovering ? db.id.uuidString : nil
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity).animation(BlazeAnimation.smooth.delay(BlazeAnimation.staggerDelay(index: index))),
                                removal: .opacity.animation(BlazeAnimation.quick)
                            ))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .animation(.default, value: filteredDatabases.count)
                .frame(maxHeight: 220)
                .padding(.bottom, 8)
            } else if !databases.isEmpty {
                // Show "No results" when searching
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.bottom, 8)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Actions
            VStack(spacing: 8) {
                // CREATE DATABASE - Big prominent button
                Button(action: { 
                    withAnimation(BlazeAnimation.bouncy) {
                        showingCreateDatabase = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.callout)
                            .rotationEffect(.degrees(hoveredButton == "create" ? 90 : 0))
                        Text("Create New Database")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.gradient)
                    )
                    .foregroundStyle(.white)
                    .scaleEffect(hoveredButton == "create" ? 1.05 : 1.0)
                    .shadow(
                        color: .green.opacity(hoveredButton == "create" ? 0.4 : 0),
                        radius: hoveredButton == "create" ? 8 : 0
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(BlazeAnimation.quick) {
                        hoveredButton = hovering ? "create" : nil
                    }
                    NSCursor.pointingHand.set()
                }
                
                HStack(spacing: 8) {
                    // Open Dashboard button
                    Button(action: {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "macwindow.badge.plus")
                                .font(.callout)
                            Text("Dashboard")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.8, green: 0.6, blue: 0.2))  // Darker yellow/gold
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        NSCursor.pointingHand.set()
                    }
                    
                    // Refresh button
                    Button(action: {
                        databases = ScanService.scanAllBlazeDBs()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.callout)
                            Text("Refresh")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.8, green: 0.6, blue: 0.2))  // Same darker yellow/gold
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        NSCursor.pointingHand.set()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Quit button (subtle)
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Quit")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .sheet(isPresented: $showingCreateDatabase) {
            CreateDatabaseSheet(onDatabaseCreated: {
                // Refresh database list
                databases = ScanService.scanAllBlazeDBs()
            })
        }
        .onAppear {
            databases = ScanService.scanAllBlazeDBs()
        }
    }
    
    // MARK: - Helper Functions
    
    private func healthColor(_ status: String) -> Color {
        switch status {
        case "healthy": return .green
        case "ready": return .green
        case "active": return .blue
        case "empty": return .gray
        case "large": return .purple
        case "warning": return .orange
        case "critical": return .red
        case "unknown": return .gray
        default: return .gray
        }
    }
    
    private func extractDirectory(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent().path
        
        // Replace home directory with ~
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if directory.hasPrefix(home) {
            return "~" + directory.dropFirst(home.count)
        }
        
        return directory
    }
}
