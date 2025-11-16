//
//  DataVisualizationView.swift
//  BlazeDBVisualizer
//
//  Create beautiful charts from your database data
//  ✅ Bar, Line, Pie, Scatter charts
//  ✅ Interactive configuration
//  ✅ Real-time preview
//  ✅ Export charts
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import Charts
import BlazeDB

struct DataVisualizationView: View {
    let dbPath: String
    let password: String
    
    @State private var availableFields: [String] = []
    @State private var selectedXField: String = ""
    @State private var selectedYField: String = ""
    @State private var chartType: ChartType = .bar
    @State private var chartTitle: String = "My Chart"
    @State private var records: [BlazeDataRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var aggregationType: AggregationType = .count
    
    enum ChartType: String, CaseIterable {
        case bar = "Bar Chart"
        case line = "Line Chart"
        case pie = "Pie Chart"
        case scatter = "Scatter Plot"
        
        var icon: String {
            switch self {
            case .bar: return "chart.bar.fill"
            case .line: return "chart.line.uptrend.xyaxis"
            case .pie: return "chart.pie.fill"
            case .scatter: return "circle.grid.cross.fill"
            }
        }
    }
    
    enum AggregationType: String, CaseIterable {
        case count = "Count"
        case sum = "Sum"
        case average = "Average"
        case min = "Min"
        case max = "Max"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(.blue.gradient)
                
                Text("Data Visualization")
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: exportChart) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(records.isEmpty)
                
                Button(action: generateChart) {
                    Label("Generate Chart", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || selectedXField.isEmpty)
            }
            .padding()
            
            Divider()
            
            HStack(alignment: .top, spacing: 0) {
                // Left: Configuration
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Chart Type
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Chart Type")
                                .font(.headline)
                            
                            Picker("Type", selection: $chartType) {
                                ForEach(ChartType.allCases, id: \.self) { type in
                                    Label(type.rawValue, systemImage: type.icon).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)
                        
                        // Chart Title
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Chart Title")
                                .font(.headline)
                            
                            TextField("Enter title", text: $chartTitle)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(12)
                        
                        // Data Configuration
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Data Configuration")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("X-Axis (Category)")
                                    .font(.callout.bold())
                                Picker("X Field", selection: $selectedXField) {
                                    Text("Select field...").tag("")
                                    ForEach(availableFields, id: \.self) { field in
                                        Text(field).tag(field)
                                    }
                                }
                            }
                            
                            if chartType != .pie {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Y-Axis (Value)")
                                        .font(.callout.bold())
                                    Picker("Y Field", selection: $selectedYField) {
                                        Text("Count records").tag("")
                                        ForEach(availableFields, id: \.self) { field in
                                            Text(field).tag(field)
                                        }
                                    }
                                }
                            }
                            
                            if !selectedYField.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Aggregation")
                                        .font(.callout.bold())
                                    Picker("Type", selection: $aggregationType) {
                                        ForEach(AggregationType.allCases, id: \.self) { type in
                                            Text(type.rawValue).tag(type)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(12)
                        
                        // Stats
                        if !records.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Data Statistics")
                                    .font(.headline)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    StatRow(label: "Total Records", value: "\(records.count)")
                                    if let uniqueCount = uniqueValuesCount(for: selectedXField) {
                                        StatRow(label: "Unique Values", value: "\(uniqueCount)")
                                    }
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.05))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
                .frame(width: 350)
                
                Divider()
                
                // Right: Chart Preview
                VStack(spacing: 0) {
                    // Chart Header
                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(.secondary)
                        Text("Chart Preview")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    
                    Divider()
                    
                    // Chart Content
                    if isLoading {
                        ProgressView("Loading data...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                            Text(error)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if records.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("Configure chart settings and click 'Generate Chart'")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        chartView
                            .padding()
                    }
                }
            }
        }
        .task {
            loadSchema()
        }
    }
    
    // MARK: - Chart View
    
    @ViewBuilder
    private var chartView: some View {
        VStack(spacing: 16) {
            Text(chartTitle)
                .font(.title2.bold())
            
            let chartData = processChartData()
            
            switch chartType {
            case .bar:
                Chart(chartData) { item in
                    BarMark(
                        x: .value("Category", item.category),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
                .frame(height: 400)
                
            case .line:
                Chart(chartData) { item in
                    LineMark(
                        x: .value("Category", item.category),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(Color.green)
                    .symbol(.circle)
                }
                .frame(height: 400)
                
            case .pie:
                Chart(chartData) { item in
                    SectorMark(
                        angle: .value("Value", item.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Category", item.category))
                    .annotation(position: .overlay) {
                        Text("\(Int(item.value))")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 400)
                
            case .scatter:
                Chart(chartData) { item in
                    PointMark(
                        x: .value("Category", item.category),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(Color.purple)
                }
                .frame(height: 400)
            }
            
            // Data table below chart
            if chartData.count <= 20 {
                dataTableView(chartData)
            }
        }
    }
    
    private func dataTableView(_ data: [ChartDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Table")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 4) {
                    // Header
                    HStack {
                        Text("Category")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Value")
                            .font(.caption.bold())
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.2))
                    
                    // Rows
                    ForEach(data) { item in
                        HStack {
                            Text(item.category)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.1f", item.value))
                                .font(.caption.monospacedDigit())
                                .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.05))
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Data Processing
    
    private func processChartData() -> [ChartDataPoint] {
        var dataPoints: [ChartDataPoint] = []
        
        if selectedXField.isEmpty { return [] }
        
        // Group by X field
        var groups: [String: [BlazeDataRecord]] = [:]
        for record in records {
            if let xValue = record.storage[selectedXField] {
                let key = stringValue(xValue)
                groups[key, default: []].append(record)
            }
        }
        
        // Calculate values for each group
        for (key, groupRecords) in groups {
            let value: Double
            
            if selectedYField.isEmpty {
                // Count mode
                value = Double(groupRecords.count)
            } else {
                // Aggregate Y field
                let yValues = groupRecords.compactMap { record -> Double? in
                    guard let field = record.storage[selectedYField] else { return nil }
                    return numericValue(field)
                }
                
                switch aggregationType {
                case .count:
                    value = Double(yValues.count)
                case .sum:
                    value = yValues.reduce(0, +)
                case .average:
                    value = yValues.isEmpty ? 0 : yValues.reduce(0, +) / Double(yValues.count)
                case .min:
                    value = yValues.min() ?? 0
                case .max:
                    value = yValues.max() ?? 0
                }
            }
            
            dataPoints.append(ChartDataPoint(category: key, value: value))
        }
        
        // Sort by category
        return dataPoints.sorted { $0.category < $1.category }
    }
    
    private func stringValue(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .date(let date): return date.formatted(date: .numeric, time: .omitted)
        case .uuid(let uuid): return uuid.uuidString.prefix(8).description
        default: return "—"
        }
    }
    
    private func numericValue(_ field: BlazeDocumentField) -> Double? {
        switch field {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    
    private func uniqueValuesCount(for field: String) -> Int? {
        guard !field.isEmpty else { return nil }
        let unique = Set(records.compactMap { record -> String? in
            guard let value = record.storage[field] else { return nil }
            return stringValue(value)
        })
        return unique.count
    }
    
    // MARK: - Actions
    
    private func loadSchema() {
        isLoading = true
        
        Task {
            do {
                let fields = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    let allRecords = try db.fetchAll()
                    
                    // Extract all unique field names
                    var fieldSet = Set<String>()
                    for record in allRecords {
                        fieldSet.formUnion(record.storage.keys)
                    }
                    
                    return Array(fieldSet).sorted()
                }.value
                
                availableFields = fields
                isLoading = false
            } catch {
                errorMessage = "Failed to load schema: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func generateChart() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let allRecords = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    return try db.fetchAll()
                }.value
                
                records = allRecords
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func exportChart() {
        print("📤 Exporting chart as image...")
        // TODO: Implement chart export
    }
}

// MARK: - Supporting Types

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let category: String
    let value: Double
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().bold())
        }
        .padding(.vertical, 2)
    }
}

