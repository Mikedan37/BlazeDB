//
//  SchemaEditorView.swift
//  BlazeDBVisualizer
//
//  Manage database schema
//  ✅ View all fields and types
//  ✅ Add new fields to existing records
//  ✅ Detect field types automatically
//  ✅ Show field usage statistics
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct SchemaEditorView: View {
    let dbPath: String
    let password: String
    
    @State private var schema: [FieldInfo] = []
    @State private var isLoading = true
    @State private var showingAddFieldSheet = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.grid.3x3")
                    .font(.title2)
                    .foregroundStyle(.indigo.gradient)
                
                Text("Schema Editor")
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: { showingAddFieldSheet = true }) {
                    Label("Add Field", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button(action: loadSchema) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView("Analyzing schema...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if schema.isEmpty {
                emptyStateView
            } else {
                schemaTableView
            }
        }
        .sheet(isPresented: $showingAddFieldSheet) {
            AddFieldToSchemaSheet(
                dbPath: dbPath,
                password: password,
                existingFields: schema.map { $0.name },
                onFieldAdded: {
                    loadSchema()
                }
            )
        }
        .task {
            loadSchema()
        }
    }
    
    // MARK: - Schema Table View
    
    private var schemaTableView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary
                HStack(spacing: 20) {
                    StatBadge(
                        value: "\(schema.count)",
                        label: "Fields",
                        color: .blue,
                        icon: "square.grid.3x3"
                    )
                    
                    StatBadge(
                        value: "\(schema.filter { $0.usagePercent >= 90 }.count)",
                        label: "Common",
                        color: .green,
                        icon: "star.fill"
                    )
                    
                    StatBadge(
                        value: "\(schema.filter { $0.usagePercent < 50 }.count)",
                        label: "Sparse",
                        color: .orange,
                        icon: "chart.bar.fill"
                    )
                }
                .padding()
                
                // Field list
                VStack(spacing: 8) {
                    ForEach(schema.sorted(by: { $0.usagePercent > $1.usagePercent })) { field in
                        FieldInfoCard(field: field)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                    .frame(height: 20)
            }
            .padding()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Schema Detected")
                .font(.title2.bold())
            
            Text("This database has no records yet")
                .foregroundColor(.secondary)
            
            Button(action: { showingAddFieldSheet = true }) {
                Label("Add First Field", systemImage: "plus.circle.fill")
                    .font(.callout.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadSchema() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Offload synchronous BlazeDB operations to background
                let fieldInfos = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    let records = try db.fetchAll()
                    
                    // Analyze schema from records
                    var fieldMap: [String: FieldAnalysis] = [:]
                    
                    for record in records {
                        for (key, value) in record.storage {
                            if fieldMap[key] == nil {
                                fieldMap[key] = FieldAnalysis(name: key)
                            }
                            
                            fieldMap[key]?.addOccurrence(type: self.typeOf(value))
                        }
                    }
                    
                    // Convert to FieldInfo
                    let totalRecords = records.count
                    return fieldMap.values.map { analysis in
                        FieldInfo(
                            name: analysis.name,
                            type: analysis.mostCommonType,
                            occurrences: analysis.count,
                            totalRecords: totalRecords,
                            typeVariations: analysis.types.count
                        )
                    }
                }.value
                
                schema = fieldInfos
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func typeOf(_ value: BlazeDocumentField) -> String {
        switch value {
        case .string: return "String"
        case .int: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .date: return "Date"
        case .uuid: return "UUID"
        case .data: return "Data"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        }
    }
}

// MARK: - Field Info

struct FieldInfo: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let occurrences: Int
    let totalRecords: Int
    let typeVariations: Int
    
    var usagePercent: Double {
        totalRecords > 0 ? (Double(occurrences) / Double(totalRecords)) * 100 : 0
    }
}

// MARK: - Field Analysis Helper

class FieldAnalysis {
    let name: String
    var count = 0
    var types: [String: Int] = [:]
    
    init(name: String) {
        self.name = name
    }
    
    func addOccurrence(type: String) {
        count += 1
        types[type, default: 0] += 1
    }
    
    var mostCommonType: String {
        types.max(by: { $0.value < $1.value })?.key ?? "Unknown"
    }
}

// MARK: - Field Info Card

struct FieldInfoCard: View {
    let field: FieldInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconFor(field.type))
                    .foregroundColor(.indigo)
                    .frame(width: 24)
                
                Text(field.name)
                    .font(.callout.bold())
                
                Text("(\(field.type))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(field.occurrences) / \(field.totalRecords)")
                        .font(.caption.monospacedDigit())
                    
                    Text("\(String(format: "%.1f", field.usagePercent))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(colorForUsage(field.usagePercent))
                }
            }
            
            // Usage bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    
                    Capsule()
                        .fill(colorForUsage(field.usagePercent).gradient)
                        .frame(width: geometry.size.width * (field.usagePercent / 100))
                }
            }
            .frame(height: 6)
            
            if field.typeVariations > 1 {
                Label("Mixed types detected", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func iconFor(_ type: String) -> String {
        switch type {
        case "String": return "textformat"
        case "Int": return "number"
        case "Double": return "number.circle"
        case "Bool": return "switch.2"
        case "Date": return "calendar"
        case "UUID": return "building.columns"
        case "Array": return "list.bullet"
        case "Dictionary": return "doc.text"
        default: return "questionmark"
        }
    }
    
    private func colorForUsage(_ percent: Double) -> Color {
        if percent >= 90 { return .green }
        if percent >= 70 { return .blue }
        if percent >= 50 { return .orange }
        return .red
    }
}

// MARK: - Add Field Sheet

struct AddFieldToSchemaSheet: View {
    let dbPath: String
    let password: String
    let existingFields: [String]
    let onFieldAdded: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var fieldName = ""
    @State private var fieldType: NewRecordSheet.FieldType = .string
    @State private var defaultValue = ""
    @State private var applyToExisting = true
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Add Field to Schema")
                        .font(.title2.bold())
                    
                    Text("This will add a new field to all existing records")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Field definition
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Field Name")
                            .font(.headline)
                        TextField("e.g., status", text: $fieldName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Field Type")
                            .font(.headline)
                        Picker("Type", selection: $fieldType) {
                            ForEach(NewRecordSheet.FieldType.allCases) { type in
                                Label(type.rawValue, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Value")
                            .font(.headline)
                        TextField(fieldType.placeholder, text: $defaultValue)
                            .textFieldStyle(.roundedBorder)
                        Text("This value will be added to all existing records")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                Toggle(isOn: $applyToExisting) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apply to Existing Records")
                            .font(.callout.bold())
                        Text("Adds this field to all current records with the default value")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
                
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.callout)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Field")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Field") {
                        addField()
                    }
                    .disabled(fieldName.isEmpty || defaultValue.isEmpty || isProcessing)
                }
            }
        }
    }
    
    private func addField() {
        guard !fieldName.isEmpty, !defaultValue.isEmpty else { return }
        
        // Check if field already exists
        if existingFields.contains(fieldName) {
            errorMessage = "Field '\(fieldName)' already exists"
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        let fieldNameCopy = fieldName
        let fieldTypeCopy = fieldType
        let defaultValueCopy = defaultValue
        let applyToExistingCopy = applyToExisting
        
        Task {
            do {
                // Offload synchronous operations to background
                try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    
                    if applyToExistingCopy {
                        // Parse default value
                        let value = try AddFieldToSchemaSheet.parseValue(defaultValueCopy, as: fieldTypeCopy, fieldName: fieldNameCopy)
                        
                        // Get all records
                        let records = try db.fetchAll()
                        
                        // Update each record with new field
                        for record in records {
                            if let uuid = record.storage["id"], case .uuid(let id) = uuid {
                                try db.updateFields(id: id, fields: [fieldNameCopy: value])
                            }
                        }
                        
                        try db.persist()
                        
                        print("✅ Added field '\(fieldNameCopy)' to \(records.count) records")
                    }
                }.value
                
                onFieldAdded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
    
    private static func parseValue(_ value: String, as type: NewRecordSheet.FieldType, fieldName: String = "value") throws -> BlazeDocumentField {
        switch type {
        case .string:
            return .string(value)
        case .int:
            guard let int = Int(value) else {
                throw EditingError.invalidFieldType(field: fieldName, expectedType: "int", actualValue: value)
            }
            return .int(int)
        case .double:
            guard let double = Double(value) else {
                throw EditingError.invalidFieldType(field: fieldName, expectedType: "double", actualValue: value)
            }
            return .double(double)
        case .bool:
            let normalized = value.lowercased()
            guard ["true", "false", "1", "0"].contains(normalized) else {
                throw EditingError.invalidFieldType(field: fieldName, expectedType: "bool", actualValue: value)
            }
            return .bool(normalized == "true" || normalized == "1")
        case .date:
            if let date = ISO8601DateFormatter().date(from: value) {
                return .date(date)
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: value) {
                return .date(date)
            }
            throw EditingError.invalidFieldType(field: fieldName, expectedType: "date", actualValue: value)
        case .uuid:
            guard let uuid = UUID(uuidString: value) else {
                throw EditingError.invalidFieldType(field: fieldName, expectedType: "uuid", actualValue: value)
            }
            return .uuid(uuid)
        }
    }
}
