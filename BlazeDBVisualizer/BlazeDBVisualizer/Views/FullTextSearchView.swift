//
//  FullTextSearchView.swift
//  BlazeDBVisualizer
//
//  Google-style full-text search interface
//  ✅ Multi-field search
//  ✅ Relevance scoring
//  ✅ Search term highlighting
//  ✅ Instant results
//  ✅ Search history
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI
import BlazeDB

struct FullTextSearchView: View {
    let dbPath: String
    let password: String
    
    @State private var searchQuery = ""
    @State private var searchResults: [FullTextSearchResult] = []
    @State private var isSearching = false
    @State private var availableFields: [String] = []
    @State private var selectedFields: Set<String> = []
    @State private var caseSensitive = false
    @State private var minWordLength = 2
    @State private var searchHistory: [String] = []
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Google-style Search Header
            VStack(spacing: 16) {
                // App Title
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.gradient)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BlazeDB Search")
                            .font(.title.bold())
                        Text("Search across all fields")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top)
                
                // Search Box
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search database...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: performSearch) {
                        Text("Search")
                            .font(.callout.bold())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.blue.gradient)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchQuery.isEmpty || isSearching)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                
                // Search Options
                HStack(spacing: 20) {
                    Menu {
                        ForEach(availableFields, id: \.self) { field in
                            Button(action: { toggleField(field) }) {
                                Label(field, systemImage: selectedFields.contains(field) ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack {
                            Text("Fields: \(selectedFields.isEmpty ? "All" : "\(selectedFields.count) selected")")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                    }
                    
                    Toggle("Case sensitive", isOn: $caseSensitive)
                        .toggleStyle(.switch)
                        .font(.caption)
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Results
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                noResultsView
            } else if !searchResults.isEmpty {
                resultsView
            } else {
                searchTipsView
            }
        }
        .task {
            await loadFields()
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Results Header
            HStack {
                Text("About \(searchResults.count) results")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: exportResults) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            
            Divider()
            
            // Results List
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(searchResults, id: \.record.storage) { result in
                        SearchResultCard(result: result, query: searchQuery)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - No Results View
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No results found")
                .font(.title2.bold())
            
            Text("Try different keywords or check your spelling")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if !searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent searches:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    ForEach(searchHistory.prefix(5), id: \.self) { query in
                        Button(action: { searchQuery = query; performSearch() }) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text(query)
                            }
                            .font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Search Tips View
    
    private var searchTipsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Search Tips")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                SearchTipRow(
                    icon: "text.magnifyingglass",
                    title: "Search any field",
                    description: "Enter keywords to search across all fields"
                )
                
                SearchTipRow(
                    icon: "list.bullet",
                    title: "Select specific fields",
                    description: "Use the Fields menu to narrow your search"
                )
                
                SearchTipRow(
                    icon: "sparkles",
                    title: "Relevance ranking",
                    description: "Results are sorted by best match"
                )
                
                SearchTipRow(
                    icon: "highlighter",
                    title: "Term highlighting",
                    description: "Matching terms are highlighted in results"
                )
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
        }
        .frame(maxWidth: 600)
        .padding()
    }
    
    // MARK: - Actions
    
    private func loadFields() async {
        do {
            let fields = try await Task.detached(priority: .userInitiated) {
                let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                let records = try db.fetchAll()
                
                var fieldSet = Set<String>()
                for record in records {
                    fieldSet.formUnion(record.storage.keys)
                }
                
                return Array(fieldSet).sorted()
            }.value
            
            availableFields = fields
        } catch {
            print("❌ Failed to load fields: \(error)")
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        // Add to history
        if !searchHistory.contains(searchQuery) {
            searchHistory.insert(searchQuery, at: 0)
            if searchHistory.count > 10 {
                searchHistory = Array(searchHistory.prefix(10))
            }
        }
        
        isSearching = true
        
        let query = searchQuery
        let fields = selectedFields.isEmpty ? availableFields : Array(selectedFields)
        let caseSens = caseSensitive
        let minLen = minWordLength
        
        Task {
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    let db = try BlazeDBClient(name: "temp", fileURL: URL(fileURLWithPath: dbPath), password: password)
                    let records = try db.fetchAll()
                    
                    let config = SearchConfig(
                        minWordLength: minLen,
                        caseSensitive: caseSens,
                        language: nil,
                        fields: fields
                    )
                    
                    return FullTextSearchEngine.search(
                        records: records,
                        query: query,
                        config: config
                    )
                }.value
                
                searchResults = results
                isSearching = false
            } catch {
                print("❌ Search failed: \(error)")
                isSearching = false
            }
        }
    }
    
    private func toggleField(_ field: String) {
        if selectedFields.contains(field) {
            selectedFields.remove(field)
        } else {
            selectedFields.insert(field)
        }
    }
    
    private func exportResults() {
        print("📤 Exporting \(searchResults.count) search results")
        // TODO: Implement export
    }
}

// MARK: - Components

struct SearchResultCard: View {
    let result: FullTextSearchResult
    let query: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Relevance Score
            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < Int(result.score * 5) ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Text(String(format: "%.1f%% match", result.score * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Record Data
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(result.record.storage.keys.sorted()), id: \.self) { key in
                    if let value = result.record.storage[key] {
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .frame(width: 120, alignment: .leading)
                            
                            Text(displayValue(value))
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            
            // Matched Terms
            if !result.matches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matches:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(result.matches.keys.sorted()), id: \.self) { field in
                        if let terms = result.matches[field] {
                            HStack {
                                Text(field + ":")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(terms, id: \.self) { term in
                                    Text(term)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func displayValue(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "true" : "false"
        case .date(let date): return date.formatted(date: .abbreviated, time: .shortened)
        case .uuid(let uuid): return uuid.uuidString
        case .data(let data): return "<\(data.count) bytes>"
        case .array: return "[Array]"
        case .dictionary: return "{Dictionary}"
        }
    }
}

struct SearchTipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

