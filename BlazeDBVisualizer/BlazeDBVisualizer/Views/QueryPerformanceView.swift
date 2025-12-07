//
//  QueryPerformanceView.swift
//  BlazeDBVisualizer
//
//  Monitor query performance and detect slow queries
//  ✅ Real-time slow query detection
//  ✅ Query execution timeline
//  ✅ Cache hit rate visualization
//  ✅ Performance statistics
//  ✅ Index usage recommendations
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import Charts
import BlazeDB

struct QueryPerformanceView: View {
    let dbPath: String
    let password: String
    
    @State private var isProfilingEnabled = false
    @State private var queryProfiles: [QueryProfile] = []
    @State private var statistics: QueryStatistics?
    @State private var slowQueryThreshold: Double = 0.1  // 100ms
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?
    
    var slowQueries: [QueryProfile] {
        queryProfiles.filter { $0.executionTime > slowQueryThreshold }
            .sorted { $0.executionTime > $1.executionTime }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "speedometer")
                    .font(.title2)
                    .foregroundStyle(.orange.gradient)
                
                Text("Query Performance")
                    .font(.title2.bold())
                
                Spacer()
                
                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .onChange(of: autoRefresh) { _, enabled in
                        toggleAutoRefresh(enabled)
                    }
                
                Toggle(isOn: $isProfilingEnabled) {
                    HStack(spacing: 6) {
                        Image(systemName: isProfilingEnabled ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis")
                            .foregroundColor(isProfilingEnabled ? .green : .secondary)
                        Text("Profiling")
                            .font(.callout.bold())
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: isProfilingEnabled) { _, enabled in
                    toggleProfiling(enabled)
                }
                
                Button(action: refreshData) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button(action: clearData) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            if queryProfiles.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .task {
            await loadData()
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Statistics Cards
                if let stats = statistics {
                    statisticsView(stats)
                }
                
                // Query Timeline Chart
                queryTimelineChart
                
                // Slow Queries
                slowQueriesSection
                
                // All Queries Table
                allQueriesSection
            }
            .padding()
        }
    }
    
    // MARK: - Statistics View
    
    private func statisticsView(_ stats: QueryStatistics) -> some View {
        HStack(spacing: 16) {
            QueryStatCard(
                label: "Total Queries",
                value: "\(stats.totalQueries)",
                color: .blue,
                icon: "number"
            )
            
            QueryStatCard(
                label: "Slow Queries",
                value: "\(stats.slowQueries)",
                color: .red,
                icon: "tortoise.fill",
                subtitle: "\(stats.totalQueries > 0 ? (stats.slowQueries * 100 / stats.totalQueries) : 0)%"
            )
            
            QueryStatCard(
                label: "Cache Hits",
                value: "\(stats.cacheHits)",
                color: .green,
                icon: "bolt.fill",
                subtitle: String(format: "%.1f%%", stats.cacheHitRate * 100)
            )
            
            QueryStatCard(
                label: "Avg Time",
                value: String(format: "%.0fms", stats.averageExecutionTime * 1000),
                color: .purple,
                icon: "clock.fill"
            )
        }
    }
    
    // MARK: - Query Timeline Chart
    
    private var queryTimelineChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Query Execution Timeline")
                .font(.headline)
            
            Chart(queryProfiles.suffix(50)) { profile in
                BarMark(
                    x: .value("Time", profile.timestamp),
                    y: .value("Duration", profile.executionTime * 1000)
                )
                .foregroundStyle(profile.isSlowQuery ? Color.red.gradient : Color.green.gradient)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Slow Queries Section
    
    private var slowQueriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Slow Queries")
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    Text("Threshold:")
                    TextField("ms", value: $slowQueryThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("s")
                }
                .font(.caption)
            }
            
            if slowQueries.isEmpty {
                Text("✅ No slow queries detected!")
                    .font(.callout)
                    .foregroundColor(.green)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(slowQueries.prefix(10), id: \.timestamp) { profile in
                        SlowQueryCard(profile: profile)
                    }
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - All Queries Section
    
    private var allQueriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Queries")
                .font(.headline)
            
            VStack(spacing: 1) {
                // Header
                HStack {
                    Text("Time")
                        .font(.caption.bold())
                        .frame(width: 100, alignment: .leading)
                    Text("Query")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Duration")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .trailing)
                    Text("Records")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .trailing)
                    Text("Index")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .center)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.2))
                
                // Rows
                ForEach(queryProfiles.suffix(20).reversed(), id: \.timestamp) { profile in
                    QueryRow(profile: profile)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "speedometer")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Query Data")
                .font(.title2.bold())
            
            Text("Enable profiling to start monitoring query performance")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { toggleProfiling(true) }) {
                Text("Enable Profiling")
                    .font(.callout.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        do {
            let (profiles, stats) = try await Task.detached(priority: .userInitiated) {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                
                // Check if profiling is enabled
                let enabled = QueryProfiler.shared.isEnabled
                
                // Get profiles and statistics
                let profiles = QueryProfiler.shared.getAllProfiles()
                let stats = QueryProfiler.shared.getStatistics()
                
                return (profiles, stats)
            }.value
            
            queryProfiles = profiles
            statistics = stats
            isProfilingEnabled = QueryProfiler.shared.isEnabled
        } catch {
            print("❌ Failed to load query data: \(error)")
        }
    }
    
    private func refreshData() {
        Task {
            await loadData()
        }
    }
    
    private func toggleProfiling(_ enabled: Bool) {
        Task.detached(priority: .userInitiated) {
            let db = try? BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
            
            if enabled {
                db?.enableProfiling()
            } else {
                db?.disableProfiling()
            }
            
            await MainActor.run {
                Task {
                    await loadData()
                }
            }
        }
    }
    
    private func clearData() {
        Task.detached(priority: .userInitiated) {
            QueryProfiler.shared.clear()
            
            await MainActor.run {
                queryProfiles = []
                statistics = nil
            }
        }
    }
    
    private func toggleAutoRefresh(_ enabled: Bool) {
        refreshTimer?.invalidate()
        
        if enabled {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task {
                    await loadData()
                }
            }
        }
    }
}

// MARK: - Components

struct QueryStatCard: View {
    let label: String
    let value: String
    let color: Color
    let icon: String
    var subtitle: String?
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SlowQueryCard: View {
    let profile: QueryProfile
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.query)
                    .font(.callout.bold())
                
                HStack(spacing: 12) {
                    Label(String(format: "%.0fms", profile.executionTime * 1000), systemImage: "clock.fill")
                    Label("\(profile.recordsReturned) records", systemImage: "doc.text")
                    
                    if let index = profile.indexUsed {
                        Label(index, systemImage: "list.bullet.indent")
                            .foregroundColor(.green)
                    } else {
                        Label("No index", systemImage: "exclamationmark.circle")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(8)
    }
}

struct QueryRow: View {
    let profile: QueryProfile
    
    var body: some View {
        HStack {
            Text(profile.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .leading)
            
            Text(profile.query)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            
            Text(String(format: "%.0fms", profile.executionTime * 1000))
                .font(.caption.monospacedDigit())
                .foregroundColor(profile.isSlowQuery ? .red : .primary)
                .frame(width: 80, alignment: .trailing)
            
            Text("\(profile.recordsReturned)")
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            
            if let index = profile.indexUsed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .frame(width: 80, alignment: .center)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .center)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(profile.isSlowQuery ? Color.red.opacity(0.05) : Color.clear)
    }
}

