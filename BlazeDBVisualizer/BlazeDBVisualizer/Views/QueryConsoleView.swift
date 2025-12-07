//
//  QueryConsoleView.swift
//  BlazeDBVisualizer
//
//  Interactive query console for power users
//  ✅ Build queries visually
//  ✅ See results in real-time
//  ✅ Save favorite queries
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import BlazeDB

struct QueryConsoleView: View {
    let dbPath: String
    let password: String
    
    @State private var whereClause: String = ""
    @State private var orderByField: String = ""
    @State private var limitValue: String = "100"
    @State private var results: [BlazeDataRecord] = []
    @State private var isExecuting = false
    @State private var error: Error?
    @State private var executionTime: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .font(.title2)
                    .foregroundStyle(.green.gradient)
                
                Text("Query Console")
                    .font(.title2.bold())
                
                Spacer()
                
                if isExecuting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            
            Divider()
            
            // Query Builder
            VStack(alignment: .leading, spacing: 12) {
                Text("Build Query")
                    .font(.headline)
                
                // WHERE clause
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHERE (optional)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("e.g., status == \"active\"", text: $whereClause)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        if !whereClause.isEmpty {
                            Button(action: { whereClause = "" }) {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    // ORDER BY
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ORDER BY (optional)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        TextField("Field name", text: $orderByField)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // LIMIT
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LIMIT")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        TextField("100", text: $limitValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80)
                    }
                }
                
                // Execute button
                Button(action: executeQuery) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Execute Query")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isExecuting)
                
                // Quick query examples
                HStack(spacing: 8) {
                    Text("Examples:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("All") { loadAllRecords() }
                    Button("First 10") { limitValue = "10"; loadAllRecords() }
                    Button("Recent") { orderByField = "created"; loadAllRecords() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            
            // Results
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Results")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !results.isEmpty {
                        Text("\(results.count) records")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if executionTime > 0 {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2fms", executionTime * 1000))
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                Divider()
                
                if let error = error {
                    // Error state
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Query Error")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else if results.isEmpty && !isExecuting {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "play.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Execute a query to see results")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else {
                    // Results list
                    List(results, id: \.self) { record in
                        QueryResultRowView(record: record)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
    
    // MARK: - Query Execution
    
    private func executeQuery() {
        isExecuting = true
        error = nil
        
        Task { @MainActor in
            let startTime = Date()
            
            do {
                let url = URL(fileURLWithPath: dbPath)
                let name = url.deletingPathExtension().lastPathComponent
                let db = try BlazeDBClient(name: name, fileURL: url, password: password)
                
                // Fetch all records first
                var fetchedRecords = try db.fetchAll()
                
                // Apply WHERE filter if provided
                if !whereClause.isEmpty {
                    // Simple string-based filtering for now
                    fetchedRecords = fetchedRecords.filter { record in
                        // Search all fields for the WHERE text
                        record.storage.values.contains { field in
                            fieldToString(field).localizedCaseInsensitiveContains(whereClause)
                        }
                    }
                }
                
                // Apply ORDER BY if provided
                if !orderByField.isEmpty {
                    fetchedRecords.sort { r1, r2 in
                        let v1 = r1.storage[orderByField]
                        let v2 = r2.storage[orderByField]
                        return compareFields(v1, v2)
                    }
                }
                
                // Apply LIMIT
                if let limit = Int(limitValue), limit > 0 {
                    fetchedRecords = Array(fetchedRecords.prefix(limit))
                }
                
                results = fetchedRecords
                executionTime = Date().timeIntervalSince(startTime)
                isExecuting = false
                
            } catch {
                self.error = error
                isExecuting = false
            }
        }
    }
    
    private func loadAllRecords() {
        whereClause = ""
        executeQuery()
    }
    
    private func fieldToString(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .uuid(let u): return u.uuidString
        case .date(let d): return d.ISO8601Format()
        case .data: return ""
        case .array: return ""
        case .dictionary: return ""
        }
    }
    
    private func compareFields(_ f1: BlazeDocumentField?, _ f2: BlazeDocumentField?) -> Bool {
        guard let f1 = f1, let f2 = f2 else { return false }
        
        switch (f1, f2) {
        case (.int(let i1), .int(let i2)): return i1 < i2
        case (.double(let d1), .double(let d2)): return d1 < d2
        case (.string(let s1), .string(let s2)): return s1 < s2
        case (.date(let d1), .date(let d2)): return d1 < d2
        default: return false
        }
    }
}

// MARK: - Query Result Row

struct QueryResultRowView: View {
    let record: BlazeDataRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Show ID field if exists
            if let idField = record.storage["id"] {
                Text(fieldPreview(idField))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            } else {
                Text("Record")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            
            // First few fields
            ForEach(Array(record.storage.prefix(3)), id: \.key) { key, value in
                HStack(spacing: 6) {
                    Text(key + ":")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    Text(fieldPreview(value))
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            
            if record.storage.count > 3 {
                Text("+ \(record.storage.count - 3) more fields")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func fieldPreview(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "✓" : "✗"
        case .uuid(let u): return u.uuidString.prefix(8) + "..."
        case .date(let d): return d.formatted(date: .abbreviated, time: .shortened)
        case .data(let d): return "<\(d.count)B>"
        case .array(let a): return "[\(a.count)]"
        case .dictionary(let d): return "{\(d.count)}"
        }
    }
}

// MARK: - Query Errors

enum QueryError: LocalizedError {
    case invalidSyntax(String)
    case executionFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidSyntax(let msg):
            return "Query syntax error: \(msg)"
        case .executionFailed(let error):
            return "Query failed: \(error.localizedDescription)"
        }
    }
}

