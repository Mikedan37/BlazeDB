//
//  NewRecordSheet.swift
//  BlazeDBVisualizer
//
//  Modal sheet for creating new database records
//  ✅ Field name + type + value input
//  ✅ Type picker (string, int, bool, date, etc.)
//  ✅ Type validation
//  ✅ Preview before creation
//  ✅ Add multiple fields
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct NewRecordSheet: View {
    let dbPath: String
    let password: String
    let onRecordCreated: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editingService = EditingService()
    
    @State private var fields: [(String, FieldType, String)] = []
    @State private var fieldName = ""
    @State private var fieldType: FieldType = .string
    @State private var fieldValue = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    enum FieldType: String, CaseIterable, Identifiable {
        case string = "String"
        case int = "Integer"
        case double = "Double"
        case bool = "Boolean"
        case date = "Date"
        case uuid = "UUID"
        
        var id: String { rawValue }
        
        var placeholder: String {
            switch self {
            case .string: return "Enter text"
            case .int: return "e.g., 42"
            case .double: return "e.g., 3.14"
            case .bool: return "true or false"
            case .date: return "YYYY-MM-DD or ISO8601"
            case .uuid: return "Auto-generated"
            }
        }
        
        var icon: String {
            switch self {
            case .string: return "textformat"
            case .int: return "number"
            case .double: return "number.circle"
            case .bool: return "switch.2"
            case .date: return "calendar"
            case .uuid: return "building.columns"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Add field section
                    addFieldSection
                    
                    // Fields preview
                    if !fields.isEmpty {
                        fieldsPreviewSection
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        errorView(error)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Create New Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createRecord()
                    }
                    .disabled(fields.isEmpty || isCreating)
                }
            }
            .task {
                do {
                    try editingService.connect(dbPath: dbPath, password: password)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Add Field Section
    
    private var addFieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Field")
                .font(.headline)
            
            HStack(spacing: 12) {
                // Field name
                TextField("Field name", text: $fieldName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                
                // Field type picker
                Picker("Type", selection: $fieldType) {
                    ForEach(FieldType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                
                // Field value
                TextField(fieldType.placeholder, text: $fieldValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
                    .disabled(fieldType == .uuid)
                
                // Add button
                Button(action: addField) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(fieldName.isEmpty || (fieldValue.isEmpty && fieldType != .uuid))
            }
            
            Text("Add one or more fields to create a record")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Fields Preview Section
    
    private var fieldsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Preview (\(fields.count) fields)")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                    HStack {
                        Image(systemName: field.1.icon)
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        Text(field.0)
                            .font(.callout.bold())
                            .frame(width: 120, alignment: .leading)
                        
                        Text("(\(field.1.rawValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        
                        Text(field.2.isEmpty ? "auto" : field.2)
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: { removeField(at: index) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func addField() {
        guard !fieldName.isEmpty else { return }
        
        let value = fieldType == .uuid ? UUID().uuidString : fieldValue
        fields.append((fieldName, fieldType, value))
        
        // Reset inputs
        fieldName = ""
        fieldValue = ""
        errorMessage = nil
    }
    
    private func removeField(at index: Int) {
        fields.remove(at: index)
    }
    
    private func createRecord() {
        guard !fields.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                // Convert fields to BlazeDataRecord
                var storage: [String: BlazeDocumentField] = [:]
                
                for (name, type, value) in fields {
                    let field = try convertToField(value: value, type: type)
                    storage[name] = field
                }
                
                let record = BlazeDataRecord(storage)
                
                // Insert record
                _ = try await editingService.insertRecord(record)
                
                // Success!
                await MainActor.run {
                    onRecordCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
    
    private func convertToField(value: String, type: FieldType) throws -> BlazeDocumentField {
        switch type {
        case .string:
            return .string(value)
            
        case .int:
            guard let int = Int(value) else {
                throw EditingError.invalidFieldType(field: "value", expectedType: "int", actualValue: value)
            }
            return .int(int)
            
        case .double:
            guard let double = Double(value) else {
                throw EditingError.invalidFieldType(field: "value", expectedType: "double", actualValue: value)
            }
            return .double(double)
            
        case .bool:
            let normalized = value.lowercased()
            guard ["true", "false", "1", "0"].contains(normalized) else {
                throw EditingError.invalidFieldType(field: "value", expectedType: "bool", actualValue: value)
            }
            return .bool(normalized == "true" || normalized == "1")
            
        case .date:
            // Try ISO8601 first
            if let date = ISO8601DateFormatter().date(from: value) {
                return .date(date)
            }
            // Try simple date format
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: value) {
                return .date(date)
            }
            throw EditingError.invalidFieldType(field: "value", expectedType: "date", actualValue: value)
            
        case .uuid:
            guard let uuid = UUID(uuidString: value) else {
                throw EditingError.invalidFieldType(field: "value", expectedType: "uuid", actualValue: value)
            }
            return .uuid(uuid)
        }
    }
}

