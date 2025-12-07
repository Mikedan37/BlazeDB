//
//  MainWindowView.swift
//  BlazeDBVisualizer
//
//  Main window with full database management UI
//  ✅ Beautiful list view
//  ✅ Interactive dashboard
//  ✅ Full monitoring features
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI

struct MainWindowView: View {
    @State private var databases: [DBRecord] = []
    @State private var selectedDatabase: DBRecord?
    @State private var isRefreshing = false
    @State private var showingCreateDatabase = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - Database List
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.title)
                        .foregroundStyle(.orange.gradient)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BlazeDB Manager")
                            .font(.title2.bold())
                        Text("\(databases.count) databases")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { showingCreateDatabase = true }) {
                        Label("New", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .help("Create new database")
                    
                    Button(action: refreshDatabases) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing)
                    .help("Refresh database list")
                }
                .padding()
                
                Divider()
                
                // Database List
                if databases.isEmpty {
                    EmptyStateView()
                } else {
                    DBListView(
                        records: databases,
                        onSelect: { db in
                            selectedDatabase = db
                        }
                    )
                }
            }
            .frame(minWidth: 300)
            .background(Color(NSColor.windowBackgroundColor))
            
        } detail: {
            // Detail - Database Dashboard
            if let selected = selectedDatabase {
                DetailView(db: selected, onDelete: {
                    // Database was deleted, refresh list and clear selection
                    selectedDatabase = nil
                    refreshDatabases()
                })
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Select a database")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Choose a database from the list to view its monitoring dashboard")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingCreateDatabase) {
            CreateDatabaseSheet(onDatabaseCreated: {
                refreshDatabases()
            })
        }
        .onAppear {
            refreshDatabases()
        }
    }
    
    // MARK: - Actions
    
    private func refreshDatabases() {
        isRefreshing = true
        
        Task { @MainActor in
            // Scan for databases
            databases = ScanService.scanAllBlazeDBs()
            
            // Add delay to show refresh state
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            isRefreshing = false
        }
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .frame(width: 1000, height: 700)
}

