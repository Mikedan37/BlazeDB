//
//  MonitoringDashboardView.swift
//  BlazeDBVisualizer
//
//  Real-time monitoring dashboard with charts and stats
//  ✅ Live updates every 5 seconds
//  ✅ Health status indicators
//  ✅ Performance metrics
//  ✅ Maintenance tools (VACUUM, GC)
//
//  Created by Michael Danylchuk on 11/13/25.
//

import SwiftUI
import BlazeDB
import Charts

struct MonitoringDashboardView: View {
    @StateObject private var monitoringService = MonitoringService()
    @StateObject private var alertService = AlertService.shared
    
    let dbRecord: DBRecord
    let password: String
    
    @State private var isRunningVacuum = false
    @State private var isRunningGC = false
    @State private var maintenanceMessage: String?
    @State private var selectedTab: DashboardTab = .monitoring
    
    var snapshot: DatabaseMonitoringSnapshot? {
        monitoringService.currentSnapshot
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sexy Tab Bar with smooth animations
            SexyTabPicker(
                selection: $selectedTab,
                tabs: [
                    (.monitoring, "Monitor", "chart.xyaxis.line"),
                    (.data, "Data", "doc.text"),
                    (.queryBuilder, "Query Builder", "slider.horizontal.3"),
                    (.visualize, "Visualize", "chart.bar.xaxis"),
                    (.query, "Console", "terminal"),
                    (.charts, "Charts", "chart.line.uptrend.xyaxis"),
                    (.schema, "Schema", "square.grid.3x3"),
                    (.access, "Access", "lock.shield.fill"),
                    (.permissions, "Permissions", "shield.checkered"),
                    (.performance, "Performance", "speedometer"),
                    (.search, "Search", "magnifyingglass"),
                    (.relations, "Relations", "link.circle"),
                    (.telemetry, "Telemetry", "chart.bar.doc.horizontal"),
                    (.backup, "Backup", "folder.badge.gearshape"),
                    (.tests, "Tests", "checklist")
                ]
            )
            .padding(.horizontal)
            .background(Color(NSColor.windowBackgroundColor))
            .zIndex(100)  // Keep tab bar above content
            
            Divider()
            
            // Tab Content with smooth transitions
            Group {
                switch selectedTab {
                case .monitoring:
                    monitoringTabContent
                case .data:
                    EditableDataViewerView(dbPath: dbRecord.path, password: password)
                case .queryBuilder:
                    VisualQueryBuilderView(dbPath: dbRecord.path, password: password)
                case .visualize:
                    DataVisualizationView(dbPath: dbRecord.path, password: password)
                case .query:
                    QueryConsoleView(dbPath: dbRecord.path, password: password)
                case .charts:
                    PerformanceChartsView(dbPath: dbRecord.path, password: password)
                case .backup:
                    BackupRestoreView(dbPath: dbRecord.path, password: password)
                case .schema:
                    SchemaEditorView(dbPath: dbRecord.path, password: password)
                case .access:
                    AccessControlView(dbPath: dbRecord.path, password: password)
                case .permissions:
                    PermissionTesterView(dbPath: dbRecord.path, password: password)
                case .performance:
                    QueryPerformanceView(dbPath: dbRecord.path, password: password)
                case .search:
                    FullTextSearchView(dbPath: dbRecord.path, password: password)
                case .relations:
                    RelationshipVisualizerView(dbPath: dbRecord.path, password: password)
                case .telemetry:
                    TelemetryDashboardView(dbPath: dbRecord.path, password: password)
                case .tests:
                    TestRunnerView()
                }
            }
            .id(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()  // Prevent content from overlapping tab bar
            .transition(.opacity.combined(with: .scale(scale: 0.98)).animation(BlazeAnimation.smooth))
            .animation(BlazeAnimation.smooth, value: selectedTab)
            .zIndex(1)  // Content below tab bar
        }
        .task {
            // Start monitoring when view appears
            try? await monitoringService.startMonitoring(
                dbPath: dbRecord.path,
                password: password,
                interval: 5.0
            )
        }
        .onDisappear {
            // Stop monitoring when view disappears
            monitoringService.stopMonitoring()
        }
        .onChange(of: snapshot) { _, newSnapshot in
            // Check health and send alerts
            if let snapshot = newSnapshot {
                alertService.checkHealth(snapshot: snapshot, dbName: dbRecord.name)
            }
        }
    }
    
    // MARK: - Monitoring Tab Content
    
    private var monitoringTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                header
                
                if let snapshot = snapshot {
                    // Health Status Card
                    healthCard(snapshot)
                    
                    // Storage Stats
                    storageCard(snapshot)
                    
                    // Performance Stats
                    performanceCard(snapshot)
                    
                    // Schema Info
                    schemaCard(snapshot)
                    
                    // Maintenance Tools
                    maintenanceCard(snapshot)
                    
                } else if let error = monitoringService.error {
                    errorCard(error)
                } else {
                    loadingCard
                }
            }
            .padding()
        }
        .task {
            // Start monitoring when view appears
            try? await monitoringService.startMonitoring(
                dbPath: dbRecord.path,
                password: password,
                interval: 5.0
            )
        }
        .onDisappear {
            // Stop monitoring when view disappears
            monitoringService.stopMonitoring()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(.orange.gradient)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Monitoring")
                    .font(.title.bold())
                
                if let lastUpdate = monitoringService.lastUpdateTime {
                    Text("Updated \(lastUpdate, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Refresh button
            Button(action: {
                Task { await monitoringService.refresh() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh now")
        }
    }
    
    // MARK: - Health Card
    
    private func healthCard(_ snapshot: DatabaseMonitoringSnapshot) -> some View {
        DashboardCard(
            title: "Health Status",
            icon: healthIcon(snapshot.health.status),
            iconColor: healthColor(snapshot.health.status)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Status badge
                HStack {
                    Circle()
                        .fill(healthColor(snapshot.health.status))
                        .frame(width: 12, height: 12)
                    
                    Text(snapshot.health.status.uppercased())
                        .font(.headline)
                        .foregroundColor(healthColor(snapshot.health.status))
                }
                
                // Warnings
                if !snapshot.health.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.health.warnings, id: \.self) { warning in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                
                                Text(warning)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("All systems nominal")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Storage Card
    
    private func storageCard(_ snapshot: DatabaseMonitoringSnapshot) -> some View {
        DashboardCard(title: "Storage", icon: "internaldrive", iconColor: .blue) {
            VStack(spacing: 16) {
                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatBox(
                        title: "Records",
                        value: "\(snapshot.storage.totalRecords)",
                        icon: "doc.text"
                    )
                    
                    StatBox(
                        title: "Size",
                        value: ByteCountFormatter.string(
                            fromByteCount: snapshot.storage.fileSizeBytes,
                            countStyle: .file
                        ),
                        icon: "chart.bar"
                    )
                    
                    StatBox(
                        title: "Pages",
                        value: "\(snapshot.storage.totalPages)",
                        icon: "square.stack.3d.up"
                    )
                    
                    StatBox(
                        title: "Orphaned",
                        value: "\(snapshot.storage.orphanedPages)",
                        icon: "exclamationmark.octagon",
                        valueColor: snapshot.storage.orphanedPages > 100 ? .orange : nil
                    )
                }
                
                // Fragmentation bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fragmentation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%%", snapshot.storage.fragmentationPercent))
                            .font(.caption.bold())
                            .foregroundColor(
                                snapshot.storage.fragmentationPercent > 30 ? .orange : .green
                            )
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                            
                            // Fill
                            Capsule()
                                .fill(
                                    snapshot.storage.fragmentationPercent > 30
                                    ? Color.orange.gradient
                                    : Color.green.gradient
                                )
                                .frame(
                                    width: geometry.size.width * CGFloat(min(snapshot.storage.fragmentationPercent / 100, 1.0))
                                )
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
    
    // MARK: - Performance Card
    
    private func performanceCard(_ snapshot: DatabaseMonitoringSnapshot) -> some View {
        DashboardCard(title: "Performance", icon: "speedometer", iconColor: .purple) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatBox(
                    title: "MVCC",
                    value: snapshot.performance.mvccEnabled ? "ON" : "OFF",
                    icon: "lock.rotation",
                    valueColor: snapshot.performance.mvccEnabled ? .green : .gray
                )
                
                StatBox(
                    title: "Indexes",
                    value: "\(snapshot.performance.indexCount)",
                    icon: "list.bullet.indent"
                )
                
                StatBox(
                    title: "Versions",
                    value: "\(snapshot.performance.totalVersions)",
                    icon: "clock.arrow.circlepath"
                )
                
                StatBox(
                    title: "Obsolete",
                    value: "\(snapshot.performance.obsoleteVersions)",
                    icon: "trash",
                    valueColor: snapshot.performance.obsoleteVersions > 1000 ? .orange : nil
                )
                
                StatBox(
                    title: "GC Runs",
                    value: "\(snapshot.performance.gcRunCount)",
                    icon: "arrow.3.trianglepath"
                )
                
                if let gcDuration = snapshot.performance.lastGCDuration {
                    StatBox(
                        title: "Last GC",
                        value: String(format: "%.2fs", gcDuration),
                        icon: "timer"
                    )
                }
            }
        }
    }
    
    // MARK: - Schema Card
    
    private func schemaCard(_ snapshot: DatabaseMonitoringSnapshot) -> some View {
        DashboardCard(title: "Schema", icon: "tablecells", iconColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(snapshot.schema.totalFields) fields")
                        .font(.headline)
                    Spacer()
                    Text("\(snapshot.performance.indexCount) indexes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Field types
                if !snapshot.schema.inferredTypes.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Field Types")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        ForEach(Array(snapshot.schema.inferredTypes.prefix(8)), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(value)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        
                        if snapshot.schema.inferredTypes.count > 8 {
                            Text("+ \(snapshot.schema.inferredTypes.count - 8) more...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Maintenance Card
    
    private func maintenanceCard(_ snapshot: DatabaseMonitoringSnapshot) -> some View {
        DashboardCard(title: "Maintenance", icon: "wrench.and.screwdriver", iconColor: .orange) {
            VStack(spacing: 12) {
                // VACUUM button
                Button(action: runVacuum) {
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Run VACUUM")
                                .font(.headline)
                            Text("Reclaim space and optimize storage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if snapshot.health.needsVacuum {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRunningVacuum || isRunningGC)
                .controlSize(.large)
                
                // GC button
                Button(action: runGarbageCollection) {
                    HStack {
                        Image(systemName: "trash.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Run Garbage Collection")
                                .font(.headline)
                            Text("Clean up obsolete MVCC versions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if snapshot.health.gcNeeded {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRunningVacuum || isRunningGC)
                .controlSize(.large)
                
                // Status message
                if let message = maintenanceMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(message)
                            .font(.callout)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
    
    // MARK: - Loading & Error States
    
    private var loadingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading database...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func errorCard(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            
            Text("Connection Error")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func runVacuum() {
        isRunningVacuum = true
        maintenanceMessage = nil
        
        Task { @MainActor in
            do {
                let bytesReclaimed = try await monitoringService.runVacuum()
                let reclaimed = ByteCountFormatter.string(
                    fromByteCount: Int64(bytesReclaimed),
                    countStyle: .file
                )
                maintenanceMessage = "VACUUM complete! Reclaimed \(reclaimed)"
            } catch {
                maintenanceMessage = "VACUUM failed: \(error.localizedDescription)"
            }
            isRunningVacuum = false
            
            // Clear message after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            maintenanceMessage = nil
        }
    }
    
    private func runGarbageCollection() {
        isRunningGC = true
        maintenanceMessage = nil
        
        Task { @MainActor in
            do {
                let collected = try await monitoringService.runGarbageCollection()
                maintenanceMessage = "GC complete! Collected \(collected) obsolete versions"
            } catch {
                maintenanceMessage = "GC failed: \(error.localizedDescription)"
            }
            isRunningGC = false
            
            // Clear message after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            maintenanceMessage = nil
        }
    }
    
    // MARK: - Helper Functions
    
    private func healthIcon(_ status: String) -> String {
        switch status {
        case "healthy": return "checkmark.seal.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "critical": return "xmark.seal.fill"
        default: return "questionmark.circle"
        }
    }
    
    private func healthColor(_ status: String) -> Color {
        switch status {
        case "healthy": return .green
        case "warning": return .orange
        case "critical": return .red
        default: return .gray
        }
    }
}

// MARK: - Dashboard Tab

enum DashboardTab {
    case monitoring
    case data
    case queryBuilder
    case visualize
    case query
    case charts
    case backup
    case schema
    case access
    case permissions
    case performance
    case search
    case relations
    case telemetry
    case tests
}

// MARK: - Dashboard Card Component

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
            }
            
            // Content
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Stat Box Component

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    var valueColor: Color?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2.bold())
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

