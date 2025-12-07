//
//  DataViewerView.swift
//  BlazeDBVisualizer
//
//  Browse database records with pagination
//  ✅ Read-only (safe!)
//  ✅ Paginated (fast!)
//  ✅ Search & filter
//  ✅ Copy to clipboard
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct DataViewerView: View {
    let dbPath: String
    let password: String
    
    @State private var records: [BlazeDataRecord] = []
    @State private var currentPage = 0
    @State private var totalRecords = 0
    @State private var isLoading = false
    @State private var error: Error?
    @State private var searchText = ""
    @State private var selectedRecord: BlazeDataRecord?
    
    let pageSize = 50
    
    private var totalPages: Int {
        max(1, Int(ceil(Double(totalRecords) / Double(pageSize))))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.blue.gradient)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Viewer")
                        .font(.title2.bold())
                    
                    Text("\(totalRecords) records")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search fields...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .padding()
            
            Divider()
            
            if isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading records...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if let error = error {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Error loading records")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if records.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No records found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                // Records table
                HSplitView {
                    // Record list
                    VStack(spacing: 0) {
                        List(records, id: \.self, selection: $selectedRecord) { record in
                            RecordRowView(record: record)
                        }
                        .listStyle(.sidebar)
                        
                        // Pagination controls
                        paginationControls
                    }
                    .frame(minWidth: 300)
                    
                    // Detail view
                    if let selected = selectedRecord {
                        RecordDetailView(record: selected)
                            .frame(minWidth: 400)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.largeTitle)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Select a record to view details")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task {
            await loadRecords()
        }
    }
    
    // MARK: - Pagination Controls
    
    private var paginationControls: some View {
        HStack {
            Button(action: { currentPage = max(0, currentPage - 1) }) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage == 0)
            
            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            
            Button(action: { currentPage = min(totalPages - 1, currentPage + 1) }) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages - 1)
            
            Spacer()
            
            Text("Showing \(records.count) of \(totalRecords)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
    }
    
    // MARK: - Data Loading
    
    private func loadRecords() async {
        isLoading = true
        error = nil
        
        do {
            let url = URL(fileURLWithPath: dbPath)
            let name = url.deletingPathExtension().lastPathComponent
            let db = try BlazeDBClient(name: name, fileURL: url, password: password)
            
            // Get total count (use async version)
            totalRecords = try await db.count()
            
            // Fetch page of records (use async version)
            let allRecords = try await db.fetchAll()
            let startIdx = currentPage * pageSize
            let endIdx = min(startIdx + pageSize, allRecords.count)
            
            if startIdx < allRecords.count {
                records = Array(allRecords[startIdx..<endIdx])
            } else {
                records = []
            }
            
            isLoading = false
            
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Record Row View

struct RecordRowView: View {
    let record: BlazeDataRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                if let idField = record.storage["id"] {
                    Text(fieldPreview(idField))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                } else {
                    Text("Record")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            
            // Show first few fields
            if let firstField = record.storage.first {
                Text("\(firstField.key): \(fieldPreview(firstField.value))")
                    .font(.callout)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func fieldPreview(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "true" : "false"
        case .uuid(let u): return u.uuidString
        case .date(let d): return d.formatted(date: .abbreviated, time: .shortened)
        case .data(let d): return "<\(d.count) bytes>"
        case .array(let a): return "[\(a.count) items]"
        case .dictionary(let d): return "{\(d.count) fields}"
        }
    }
}

// MARK: - Record Detail View

struct RecordDetailView: View {
    let record: BlazeDataRecord
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Record Details")
                            .font(.headline)
                        
                        Text("Fields: \(record.storage.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        copyToClipboard()
                    }) {
                        Label("Copy JSON", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                // Fields
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(record.storage.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            FieldValueView(value: value)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
    }
    
    private func copyToClipboard() {
        let json = try? JSONSerialization.data(
            withJSONObject: record.storage.mapValues { $0.toJSON() },
            options: [.prettyPrinted, .sortedKeys]
        )
        
        if let json = json, let string = String(data: json, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }
}

// MARK: - Field Value View

struct FieldValueView: View {
    let value: BlazeDocumentField
    
    var body: some View {
        switch value {
        case .string(let s):
            Text(s)
                .font(.body.monospaced())
                .textSelection(.enabled)
            
        case .int(let i):
            HStack {
                Image(systemName: "number")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("\(i)")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            
        case .double(let d):
            HStack {
                Image(systemName: "number")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(String(format: "%.6f", d))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            
        case .bool(let b):
            HStack {
                Image(systemName: b ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(b ? .green : .red)
                Text(b ? "true" : "false")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            
        case .uuid(let u):
            HStack {
                Image(systemName: "key")
                    .font(.caption)
                    .foregroundColor(.purple)
                Text(u.uuidString)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            
        case .date(let d):
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                        .textSelection(.enabled)
                    Text(d.ISO8601Format())
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            
        case .data(let d):
            HStack {
                Image(systemName: "doc.badge.gearshape")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("<Data: \(d.count) bytes>")
                    .font(.body.monospaced())
                    .foregroundColor(.secondary)
            }
            
        case .array(let arr):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Array (\(arr.count) items)")
                        .font(.body.bold())
                }
                
                ForEach(Array(arr.prefix(10).enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("[\(idx)]")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        FieldValueView(value: item)
                    }
                    .padding(.leading, 12)
                }
                
                if arr.count > 10 {
                    Text("... and \(arr.count - 10) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
            }
            
        case .dictionary(let dict):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "curlybraces")
                        .font(.caption)
                        .foregroundColor(.purple)
                    Text("Dictionary (\(dict.count) fields)")
                        .font(.body.bold())
                }
                
                ForEach(Array(dict.sorted(by: { $0.key < $1.key }).prefix(10)), id: \.key) { key, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key)
                            .font(.caption.bold().monospaced())
                            .foregroundColor(.secondary)
                        FieldValueView(value: value)
                            .padding(.leading, 12)
                    }
                }
                
                if dict.count > 10 {
                    Text("... and \(dict.count - 10) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
            }
        }
    }
}

// MARK: - Helper Extension

extension BlazeDocumentField {
    func toJSON() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .uuid(let u): return u.uuidString
        case .date(let d): return d.ISO8601Format()
        case .data(let d): return d.base64EncodedString()
        case .array(let a): return a.map { $0.toJSON() }
        case .dictionary(let d): return d.mapValues { $0.toJSON() }
        }
    }
}

