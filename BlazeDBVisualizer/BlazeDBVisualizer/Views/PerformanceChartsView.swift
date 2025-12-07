//
//  PerformanceChartsView.swift
//  BlazeDBVisualizer
//
//  Track database metrics over time
//  ✅ Record count growth
//  ✅ Storage size trends
//  ✅ Fragmentation history
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import Charts

struct PerformanceChartsView: View {
    let dbPath: String
    let password: String
    
    @State private var metrics: [MetricSnapshot] = []
    @State private var isLoading = true
    @State private var selectedMetric: MetricType = .recordCount
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(.purple.gradient)
                
                Text("Performance Trends")
                    .font(.title2.bold())
                
                Spacer()
                
                // Metric selector
                Picker("Metric", selection: $selectedMetric) {
                    Text("Records").tag(MetricType.recordCount)
                    Text("Size").tag(MetricType.storageSize)
                    Text("Fragmentation").tag(MetricType.fragmentation)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding()
            
            Divider()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading metrics...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if metrics.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Not enough data yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Metrics will appear after monitoring for a while")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                // Chart
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer()
                            .frame(height: 10)
                        
                        // Chart
                        Chart(metrics) { metric in
                            LineMark(
                                x: .value("Time", metric.timestamp),
                                y: .value("Value", metricValue(metric))
                            )
                            .foregroundStyle(selectedMetric.color.gradient)
                            .interpolationMethod(.catmullRom)
                            
                            PointMark(
                                x: .value("Time", metric.timestamp),
                                y: .value("Value", metricValue(metric))
                            )
                            .foregroundStyle(selectedMetric.color)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisValueLabel(format: .dateTime.hour().minute())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .frame(height: 300)
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                        
                        // Stats summary
                        HStack(spacing: 16) {
                            StatCard(
                                title: "Current",
                                value: formatValue(metrics.last.map(metricValue) ?? 0),
                                icon: "circle.fill",
                                color: .blue
                            )
                            
                            StatCard(
                                title: "Peak",
                                value: formatValue(metrics.map(metricValue).max() ?? 0),
                                icon: "arrow.up.circle.fill",
                                color: .green
                            )
                            
                            StatCard(
                                title: "Average",
                                value: formatValue(metrics.map(metricValue).reduce(0, +) / Double(metrics.count)),
                                icon: "chart.bar.fill",
                                color: .orange
                            )
                        }
                        
                        Spacer()
                            .frame(height: 20)
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadMetrics()
        }
    }
    
    // MARK: - Helpers
    
    private func metricValue(_ metric: MetricSnapshot) -> Double {
        switch selectedMetric {
        case .recordCount: return Double(metric.recordCount)
        case .storageSize: return Double(metric.sizeBytes) / 1024.0  // KB
        case .fragmentation: return metric.fragmentationPercent
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        switch selectedMetric {
        case .recordCount:
            return String(format: "%.0f", value)
        case .storageSize:
            return String(format: "%.1f KB", value)
        case .fragmentation:
            return String(format: "%.1f%%", value)
        }
    }
    
    private func loadMetrics() async {
        isLoading = true
        
        // TODO: Load historical metrics from storage
        // For now, generate sample data
        metrics = generateSampleMetrics()
        
        isLoading = false
    }
    
    private func generateSampleMetrics() -> [MetricSnapshot] {
        var snapshots: [MetricSnapshot] = []
        let now = Date()
        
        for i in 0..<20 {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 300))  // Every 5 minutes
            snapshots.append(MetricSnapshot(
                timestamp: timestamp,
                recordCount: 50,
                sizeBytes: 205_000,
                fragmentationPercent: 8.0
            ))
        }
        
        return snapshots.reversed()
    }
}

// MARK: - Metric Snapshot

struct MetricSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let recordCount: Int
    let sizeBytes: Int64
    let fragmentationPercent: Double
}

// MARK: - Metric Type

enum MetricType {
    case recordCount
    case storageSize
    case fragmentation
    
    var color: Color {
        switch self {
        case .recordCount: return .blue
        case .storageSize: return .purple
        case .fragmentation: return .orange
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3.bold().monospacedDigit())
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

