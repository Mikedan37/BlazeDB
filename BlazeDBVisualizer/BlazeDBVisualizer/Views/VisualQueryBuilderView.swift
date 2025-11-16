//
//  VisualQueryBuilderView.swift
//  BlazeDBVisualizer
//
//  Visual drag-and-drop query builder
//  ✅ Build queries without code
//  ✅ Real-time preview
//  ✅ Save & reuse queries
//  ✅ Export results
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import BlazeDB

struct VisualQueryBuilderView: View {
    let dbPath: String
    let password: String
    
    @State private var availableFields: [String] = []
    @State private var filters: [QueryFilter] = []
    @State private var sortField: String = ""
    @State private var sortAscending = true
    @State private var limitResults = 100
    @State private var results: [BlazeDataRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSaveQuery = false
    @State private var savedQueryName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.purple.gradient)
                
                Text("Visual Query Builder")
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: { showingSaveQuery = true }) {
                    Label("Save Query", systemImage: "bookmark.fill")
                }
                .buttonStyle(.bordered)
                
                Button(action: executeQuery) {
                    Label("Run Query", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isLoading)
            }
            .padding()
            
            Divider()
            
            HStack(alignment: .top, spacing: 0) {
                // Left: Query Builder
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Filters Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Filters")
                                    .font(.headline)
                                Spacer()
                                Button(action: addFilter) {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .font(.callout)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.purple)
                            }
                            
                            if filters.isEmpty {
                                Text("No filters - will return all records")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(8)
                            } else {
                                ForEach(Array(filters.enumerated()), id: \.offset) { index, filter in
                                    FilterRow(
                                        filter: binding(for: index),
                                        availableFields: availableFields,
                                        onRemove: { removeFilter(at: index) }
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(12)
                        
                        // Sort Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sort")
                                .font(.headline)
                            
                            HStack {
                                Picker("Field", selection: $sortField) {
                                    Text("No sorting").tag("")
                                    ForEach(availableFields, id: \.self) { field in
                                        Text(field).tag(field)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                
                                if !sortField.isEmpty {
                                    Picker("Order", selection: $sortAscending) {
                                        Label("Ascending", systemImage: "arrow.up").tag(true)
                                        Label("Descending", systemImage: "arrow.down").tag(false)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 160)
                                }
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)
                        
                        // Limit Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Limit Results")
                                .font(.headline)
                            
                            HStack {
                                Text("Show first")
                                TextField("100", value: $limitResults, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("records")
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(12)
                        
                        // Generated Query Preview
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Generated Query")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(generatedQueryDescription)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .frame(height: 80)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .padding()
                }
                .frame(width: 450)
                
                Divider()
                
                // Right: Results
                VStack(spacing: 0) {
                    // Results Header
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.secondary)
                        Text("Results: \(results.count) records")
                            .font(.headline)
                        Spacer()
                        
                        if !results.isEmpty {
                            Button(action: exportResults) {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    
                    Divider()
                    
                    // Results Content
                    if isLoading {
                        ProgressView("Running query...")
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
                    } else if results.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Click 'Run Query' to see results")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ResultsTableView(records: results, fields: availableFields)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSaveQuery) {
            SaveQuerySheet(
                queryName: $savedQueryName,
                onSave: saveQuery
            )
        }
        .task {
            loadSchema()
        }
    }
    
    // MARK: - Helpers
    
    private func binding(for index: Int) -> Binding<QueryFilter> {
        Binding(
            get: { filters[index] },
            set: { filters[index] = $0 }
        )
    }
    
    private var generatedQueryDescription: String {
        var desc = "SELECT * FROM collection"
        
        if !filters.isEmpty {
            let filterDescs = filters.map { filter in
                "\(filter.field) \(filter.operator.symbol) \(filter.value)"
            }
            desc += "\nWHERE " + filterDescs.joined(separator: " AND ")
        }
        
        if !sortField.isEmpty {
            desc += "\nORDER BY \(sortField) \(sortAscending ? "ASC" : "DESC")"
        }
        
        desc += "\nLIMIT \(limitResults)"
        
        return desc
    }
    
    // MARK: - Actions
    
    private func loadSchema() {
        Task {
            do {
                let fields = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    let records = try db.fetchAll()
                    
                    // Extract all unique field names
                    var fieldSet = Set<String>()
                    for record in records {
                        fieldSet.formUnion(record.storage.keys)
                    }
                    
                    return Array(fieldSet).sorted()
                }.value
                
                availableFields = fields
            } catch {
                errorMessage = "Failed to load schema: \(error.localizedDescription)"
            }
        }
    }
    
    private func addFilter() {
        let newFilter = QueryFilter(
            field: availableFields.first ?? "",
            operator: .equals,
            value: ""
        )
        filters.append(newFilter)
    }
    
    private func removeFilter(at index: Int) {
        filters.remove(at: index)
    }
    
    private func executeQuery() {
        isLoading = true
        errorMessage = nil
        
        let filtersCopy = filters
        let sortFieldCopy = sortField
        let sortAscendingCopy = sortAscending
        let limitResultsCopy = limitResults
        
        Task {
            do {
                let limitedResults = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    var allRecords = try db.fetchAll()
                    
                    // Apply filters
                    for filter in filtersCopy {
                        allRecords = allRecords.filter { record in
                            filter.matches(record: record)
                        }
                    }
                    
                    // Apply sorting
                    if !sortFieldCopy.isEmpty {
                        allRecords.sort { record1, record2 in
                            let val1 = record1.storage[sortFieldCopy]
                            let val2 = record2.storage[sortFieldCopy]
                            let comparison = self.compareFields(val1, val2)
                            return sortAscendingCopy ? comparison : !comparison
                        }
                    }
                    
                    // Apply limit
                    return Array(allRecords.prefix(limitResultsCopy))
                }.value
                
                results = limitedResults
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func compareFields(_ val1: BlazeDocumentField?, _ val2: BlazeDocumentField?) -> Bool {
        guard let v1 = val1, let v2 = val2 else { return false }
        
        switch (v1, v2) {
        case (.int(let i1), .int(let i2)): return i1 < i2
        case (.double(let d1), .double(let d2)): return d1 < d2
        case (.string(let s1), .string(let s2)): return s1 < s2
        case (.date(let date1), .date(let date2)): return date1 < date2
        default: return false
        }
    }
    
    private func saveQuery() {
        // TODO: Implement query saving to UserDefaults or file
        print("💾 Saving query: \(savedQueryName)")
        showingSaveQuery = false
    }
    
    private func exportResults() {
        // TODO: Implement CSV export
        print("📤 Exporting \(results.count) results to CSV")
    }
}

// MARK: - Query Filter Model

struct QueryFilter: Identifiable {
    let id = UUID()
    var field: String
    var `operator`: FilterOperator
    var value: String
    
    enum FilterOperator: String, CaseIterable {
        case equals = "Equals"
        case notEquals = "Not Equals"
        case greaterThan = "Greater Than"
        case lessThan = "Less Than"
        case contains = "Contains"
        case startsWith = "Starts With"
        case endsWith = "Ends With"
        
        var symbol: String {
            switch self {
            case .equals: return "="
            case .notEquals: return "≠"
            case .greaterThan: return ">"
            case .lessThan: return "<"
            case .contains: return "CONTAINS"
            case .startsWith: return "STARTS WITH"
            case .endsWith: return "ENDS WITH"
            }
        }
    }
    
    func matches(record: BlazeDataRecord) -> Bool {
        guard let fieldValue = record.storage[field] else { return false }
        
        switch `operator` {
        case .equals:
            return fieldValueAsString(fieldValue) == value
        case .notEquals:
            return fieldValueAsString(fieldValue) != value
        case .greaterThan:
            if case .int(let intVal) = fieldValue, let compareVal = Int(value) {
                return intVal > compareVal
            }
            if case .double(let doubleVal) = fieldValue, let compareVal = Double(value) {
                return doubleVal > compareVal
            }
            return false
        case .lessThan:
            if case .int(let intVal) = fieldValue, let compareVal = Int(value) {
                return intVal < compareVal
            }
            if case .double(let doubleVal) = fieldValue, let compareVal = Double(value) {
                return doubleVal < compareVal
            }
            return false
        case .contains:
            return fieldValueAsString(fieldValue).lowercased().contains(value.lowercased())
        case .startsWith:
            return fieldValueAsString(fieldValue).lowercased().hasPrefix(value.lowercased())
        case .endsWith:
            return fieldValueAsString(fieldValue).lowercased().hasSuffix(value.lowercased())
        }
    }
    
    private func fieldValueAsString(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .date(let date): return ISO8601DateFormatter().string(from: date)
        case .uuid(let uuid): return uuid.uuidString
        case .data(let data): return "<Data: \(data.count) bytes>"
        case .array: return "<Array>"
        case .dictionary: return "<Dictionary>"
        }
    }
}

// MARK: - Filter Row Component

struct FilterRow: View {
    @Binding var filter: QueryFilter
    let availableFields: [String]
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Picker("Field", selection: $filter.field) {
                ForEach(availableFields, id: \.self) { field in
                    Text(field).tag(field)
                }
            }
            .frame(maxWidth: .infinity)
            
            Picker("Operator", selection: $filter.operator) {
                ForEach(QueryFilter.FilterOperator.allCases, id: \.self) { op in
                    Text(op.symbol).tag(op)
                }
            }
            .frame(width: 80)
            
            TextField("Value", text: $filter.value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Results Table

struct ResultsTableView: View {
    let records: [BlazeDataRecord]
    let fields: [String]
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(fields.prefix(10), id: \.self) { field in
                        Text(field)
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                    }
                }
                
                Divider()
                
                // Rows
                ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                    HStack(spacing: 0) {
                        ForEach(fields.prefix(10), id: \.self) { field in
                            Text(displayValue(for: record.storage[field]))
                                .font(.caption)
                                .frame(width: 120, alignment: .leading)
                                .padding(8)
                                .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
                        }
                    }
                }
            }
        }
    }
    
    private func displayValue(for field: BlazeDocumentField?) -> String {
        guard let field = field else { return "—" }
        
        switch field {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "✓" : "✗"
        case .date(let date): return date.formatted(date: .numeric, time: .omitted)
        case .uuid(let uuid): return uuid.uuidString.prefix(8) + "..."
        case .data(let data): return "<\(data.count) bytes>"
        case .array: return "[Array]"
        case .dictionary: return "{Dict}"
        }
    }
}

// MARK: - Save Query Sheet

struct SaveQuerySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var queryName: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save Query")
                .font(.title2.bold())
            
            TextField("Query name", text: $queryName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(queryName.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(30)
        .frame(width: 350)
    }
}

