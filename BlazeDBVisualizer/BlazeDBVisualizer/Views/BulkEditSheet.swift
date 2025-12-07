//
//  BulkEditSheet.swift
//  BlazeDBVisualizer
//
//  Bulk edit modal for updating multiple records
//  ✅ Select field to update
//  ✅ Enter new value
//  ✅ Preview changes
//  ✅ Type validation
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct BulkEditSheet: View {
    let selectedIDs: [UUID]
    let records: [BlazeDataRecord]
    let onUpdate: (String, BlazeDocumentField) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedField: String = ""
    @State private var newValue: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    private var availableFields: [String] {
        guard let firstRecord = records.first else { return [] }
        return Array(firstRecord.storage.keys).sorted()
    }
    
    private var fieldType: NewRecordSheet.FieldType {
        guard !selectedField.isEmpty,
              let firstRecord = records.first,
              let value = firstRecord.storage[selectedField] else {
            return .string
        }
        
        switch value {
        case .string: return .string
        case .int: return .int
        case .double: return .double
        case .bool: return .bool
        case .date: return .date
        case .uuid: return .uuid
        default: return .string
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)
                    
                    Text("Bulk Edit \(selectedIDs.count) Records")
                        .font(.title2.bold())
                    
                    Text("Update a single field across all selected records")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Field selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Field")
                        .font(.headline)
                    
                    Picker("Field", selection: $selectedField) {
                        Text("Choose field...").tag("")
                        ForEach(availableFields, id: \.self) { field in
                            Text(field).tag(field)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                // Value input
                if !selectedField.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("New Value")
                                .font(.headline)
                            
                            Spacer()
                            
                            Label(fieldType.rawValue, systemImage: fieldType.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        TextField(fieldType.placeholder, text: $newValue)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("This value will be applied to all \(selectedIDs.count) records")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                
                // Preview section
                if !selectedField.isEmpty && !newValue.isEmpty {
                    previewSection
                }
                
                // Error message
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyUpdate()
                    }
                    .disabled(selectedField.isEmpty || newValue.isEmpty || isProcessing)
                }
            }
        }
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview Changes")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(records.prefix(5).enumerated()), id: \.offset) { index, record in
                        previewRow(for: record, index: index)
                    }
                    
                    if records.count > 5 {
                        Text("...and \(records.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func previewRow(for record: BlazeDataRecord, index: Int) -> some View {
        HStack {
            // Get record ID from storage
            let recordID: String = {
                if case .uuid(let uuid) = record.storage["id"] {
                    return String(uuid.uuidString.prefix(8))
                }
                return "unknown"
            }()
            
            Text(recordID)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text("\(selectedField) = ")
                .font(.callout)
            
            Text("\"\(newValue)\"")
                .font(.callout.bold())
                .foregroundColor(.blue)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(4)
    }
    
    // MARK: - Actions
    
    private func applyUpdate() {
        guard !selectedField.isEmpty, !newValue.isEmpty else { return }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                // Parse value based on type
                let field = try parseValue(newValue, as: fieldType)
                
                // Call update
                await MainActor.run {
                    onUpdate(selectedField, field)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
    
    private func parseValue(_ value: String, as type: NewRecordSheet.FieldType) throws -> BlazeDocumentField {
        switch type {
        case .string:
            return .string(value)
            
        case .int:
            guard let int = Int(value) else {
                throw EditingError.invalidFieldType(field: selectedField, expectedType: "int", actualValue: value)
            }
            return .int(int)
            
        case .double:
            guard let double = Double(value) else {
                throw EditingError.invalidFieldType(field: selectedField, expectedType: "double", actualValue: value)
            }
            return .double(double)
            
        case .bool:
            let normalized = value.lowercased()
            guard ["true", "false", "1", "0"].contains(normalized) else {
                throw EditingError.invalidFieldType(field: selectedField, expectedType: "bool", actualValue: value)
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
            throw EditingError.invalidFieldType(field: selectedField, expectedType: "date", actualValue: value)
            
        case .uuid:
            guard let uuid = UUID(uuidString: value) else {
                throw EditingError.invalidFieldType(field: selectedField, expectedType: "uuid", actualValue: value)
            }
            return .uuid(uuid)
        }
    }
}

