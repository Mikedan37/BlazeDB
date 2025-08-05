//  DetailView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI
import AppKit

struct DetailView: View {
    let db: DBRecord
    @State private var searchText: String = ""
    @State private var isDeleted: Bool = false
    @State private var showingDeleteAlert = false
    @State private var recordCountText: String = "—"

    // Simulate loading records from the DB
    @State private var records: [BlazeDataRecord] = [] // Replace with your fetch

    var filteredRecords: [BlazeDataRecord] {
        if searchText.isEmpty {
            return records
        } else {
            return records.filter { $0.prettyString.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text(db.appName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .alert("Delete this DB?", isPresented: $showingDeleteAlert) {
                    Button("Delete", role: .destructive) { isDeleted = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently remove this database file.")
                }
            }
            .padding(.bottom, 6)
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Path
            HStack(spacing: 8) {
                Text(db.fileURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(db.fileURL.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy path")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            // Metrics
            HStack(spacing: 18) {
                MetricView(title: "Records", value: recordCountText)
                MetricView(title: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(db.sizeInBytes), countStyle: .file))
                MetricView(title: "Modified", value: db.modifiedDate.formatted(date: .abbreviated, time: .shortened))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            // Search + records
            if !isDeleted {
                SearchBar(text: $searchText)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                if filteredRecords.isEmpty {
                    Spacer()
                    Text("No records found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(filteredRecords, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.prettyString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            // You can add record details/expanders here if you want
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            } else {
                Spacer()
                Label("Database deleted", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                Spacer()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .padding()
    }
}

struct MetricView: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(minWidth: 64)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search records", text: $text)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
        }
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
        .cornerRadius(8)
    }
}

// Replace this with your real record model
struct BlazeDataRecord: Identifiable {
    let id = UUID()
    let prettyString: String
}
