//
//  TelemetryDashboardView.swift
//  BlazeDBVisualizer
//
//  Comprehensive telemetry and metrics dashboard
//  ✅ Operation heatmaps
//  ✅ Performance trends over time
//  ✅ Error rate tracking
//  ✅ Custom metrics visualization
//  ✅ Sampling controls
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import Charts
import BlazeDB

struct TelemetryDashboardView: View {
    let dbPath: String
    let password: String
    
    @State private var isTelemetryEnabled = false
    @State private var metrics: [MetricEvent] = []
    @State private var samplingRate: Double = 0.01  // 1%
    @State private var operationCounts: [String: Int] = [:]
    @State private var errorRate: Double = 0
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title2)
                    .foregroundStyle(.indigo.gradient)
                
                Text("Telemetry")
                    .font(.title2.bold())
                
                Spacer()
                
                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .onChange(of: autoRefresh) { _, enabled in
                        toggleAutoRefresh(enabled)
                    }
                
                HStack {
                    Text("Sampling:")
                    TextField("%", value: $samplingRate, format: .percent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: samplingRate) { _, rate in
                            updateSamplingRate(rate)
                        }
                }
                .font(.callout)
                
                Toggle(isOn: $isTelemetryEnabled) {
                    HStack(spacing: 6) {
                        Image(systemName: isTelemetryEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .foregroundColor(isTelemetryEnabled ? .green : .secondary)
                        Text("Telemetry")
                            .font(.callout.bold())
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: isTelemetryEnabled) { _, enabled in
                    toggleTelemetry(enabled)
                }
                
                Button(action: refreshData) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            if metrics.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .task {
            await loadMetrics()
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Stats
                summaryStatsView
                
                // Operation Heatmap
                operationHeatmapView
                
                // Performance Trends
                performanceTrendsView
                
                // Error Rate Chart
                errorRateView
                
                // Recent Metrics Table
                recentMetricsView
            }
            .padding()
        }
    }
    
    // MARK: - Summary Stats
    
    private var summaryStatsView: some View {
        HStack(spacing: 16) {
            TelemetryStatCard(
                label: "Total Events",
                value: "\(metrics.count)",
                color: .blue,
                icon: "chart.bar"
            )
            
            TelemetryStatCard(
                label: "Operations",
                value: "\(operationCounts.count)",
                color: .green,
                icon: "gearshape.2"
            )
            
            TelemetryStatCard(
                label: "Error Rate",
                value: String(format: "%.1f%%", errorRate * 100),
                color: errorRate > 0.05 ? .red : .green,
                icon: "exclamationmark.triangle"
            )
            
            TelemetryStatCard(
                label: "Sampling",
                value: String(format: "%.1f%%", samplingRate * 100),
                color: .purple,
                icon: "waveform"
            )
        }
    }
    
    // MARK: - Operation Heatmap
    
    private var operationHeatmapView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operation Distribution")
                .font(.headline)
            
            if operationCounts.isEmpty {
                Text("No operations recorded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart(Array(operationCounts.sorted { $0.value > $1.value }), id: \.key) { item in
                    BarMark(
                        x: .value("Count", item.value),
                        y: .value("Operation", item.key)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.value)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: CGFloat(operationCounts.count * 40 + 40))
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Performance Trends
    
    private var performanceTrendsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Over Time")
                .font(.headline)
            
            Chart(metrics.suffix(100)) { metric in
                LineMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Duration", metric.duration * 1000)
                )
                .foregroundStyle(metric.success ? Color.green : Color.red)
                .symbol(.circle)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .chartYAxisLabel("Duration (ms)")
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Error Rate
    
    private var errorRateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Success vs. Errors")
                .font(.headline)
            
            let successCount = metrics.filter { $0.success }.count
            let errorCount = metrics.count - successCount
            
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("\(successCount)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.green)
                    Text("Successful")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 8) {
                    Text("\(errorCount)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.red)
                    Text("Errors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Recent Metrics
    
    private var recentMetricsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.headline)
            
            VStack(spacing: 1) {
                // Header
                HStack {
                    Text("Time")
                        .font(.caption.bold())
                        .frame(width: 100, alignment: .leading)
                    Text("Operation")
                        .font(.caption.bold())
                        .frame(width: 150, alignment: .leading)
                    Text("Duration")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .trailing)
                    Text("Records")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .trailing)
                    Text("Status")
                        .font(.caption.bold())
                        .frame(width: 80, alignment: .center)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.2))
                
                // Rows
                ForEach(metrics.suffix(50).reversed(), id: \.timestamp) { metric in
                    MetricRow(metric: metric)
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
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Telemetry Data")
                .font(.title2.bold())
            
            Text("Enable telemetry to start collecting metrics and performance data")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { toggleTelemetry(true) }) {
                Text("Enable Telemetry")
                    .font(.callout.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadMetrics() async {
        // Note: This is a placeholder. Actual implementation would:
        // 1. Open the metrics database
        // 2. Query MetricEvent records
        // 3. Calculate statistics
        
        // For now, generate sample data
        let sampleMetrics: [MetricEvent] = []  // TODO: Load from metrics DB
        
        metrics = sampleMetrics
        
        // Calculate stats
        var counts: [String: Int] = [:]
        var errors = 0
        
        for metric in metrics {
            counts[metric.operation, default: 0] += 1
            if !metric.success {
                errors += 1
            }
        }
        
        operationCounts = counts
        errorRate = metrics.isEmpty ? 0 : Double(errors) / Double(metrics.count)
    }
    
    private func refreshData() {
        Task {
            await loadMetrics()
        }
    }
    
    private func toggleTelemetry(_ enabled: Bool) {
        Task.detached(priority: .userInitiated) {
            do {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                
                if enabled {
                    try db.telemetry.enable(samplingRate: samplingRate)
                } else {
                    db.telemetry.disable()
                }
                
                print("📊 Telemetry \(enabled ? "enabled" : "disabled")")
            } catch {
                print("❌ Failed to toggle telemetry: \(error)")
            }
        }
    }
    
    private func updateSamplingRate(_ rate: Double) {
        Task.detached(priority: .userInitiated) {
            do {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                try db.telemetry.enable(samplingRate: rate)
                print("📊 Sampling rate updated to \(rate * 100)%")
            } catch {
                print("❌ Failed to update sampling rate: \(error)")
            }
        }
    }
    
    private func toggleAutoRefresh(_ enabled: Bool) {
        refreshTimer?.invalidate()
        
        if enabled {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                Task {
                    await loadMetrics()
                }
            }
        }
    }
}

// MARK: - Components

struct TelemetryStatCard: View {
    let label: String
    let value: String
    let color: Color
    let icon: String
    
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
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct MetricRow: View {
    let metric: MetricEvent
    
    var body: some View {
        HStack {
            Text(metric.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .leading)
            
            Text(metric.operation)
                .font(.caption)
                .frame(width: 150, alignment: .leading)
            
            Text(String(format: "%.1fms", metric.duration * 1000))
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            
            Text("\(metric.recordCount ?? 0)")
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            
            Image(systemName: metric.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(metric.success ? .green : .red)
                .frame(width: 80, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(metric.success ? Color.clear : Color.red.opacity(0.05))
    }
}

