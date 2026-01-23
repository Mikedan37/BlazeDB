//
//  SwiftUIExample.swift
//  BlazeDB Examples
//
//  Real-world examples of using BlazeDB with SwiftUI.
//  Shows the power of @BlazeQuery property wrapper for reactive database views.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import SwiftUI
import BlazeDB

// MARK: - Example 1: Simple Bug List

struct BugListView: View {
    // Auto-fetches and updates! No manual state management! 🔥
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "status", equals: .string("open"),
        sortBy: "priority", descending: true
    )
    var openBugs
    
    var body: some View {
        NavigationView {
            List(openBugs, id: \.id) { bug in
                BugRowView(bug: bug)
            }
            .navigationTitle("Open Bugs (\(openBugs.count))")
            .refreshable(query: $openBugs)  // Pull to refresh!
        }
    }
}

struct BugRowView: View {
    let bug: BlazeDataRecord
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(bug["title"]?.stringValue ?? "")
                .font(.headline)
            
            HStack {
                PriorityBadge(priority: bug["priority"]?.intValue ?? 0)
                Text(bug["assignee"]?.stringValue ?? "Unassigned")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PriorityBadge: View {
    let priority: Int
    
    var body: some View {
        Text("P\(priority)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(priorityColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    var priorityColor: Color {
        switch priority {
        case 1...3: return .red
        case 4...6: return .orange
        default: return .gray
        }
    }
}

// MARK: - Example 2: Filtered Views with Tabs

struct BugDashboardView: View {
    @State private var selectedTab = 0
    let db = AppDatabase.shared.db
    
    var body: some View {
        TabView(selection: $selectedTab) {
            OpenBugsTab(db: db)
                .tabItem {
                    Label("Open", systemImage: "circle")
                }
                .tag(0)
            
            ClosedBugsTab(db: db)
                .tabItem {
                    Label("Closed", systemImage: "checkmark.circle")
                }
                .tag(1)
            
            HighPriorityTab(db: db)
                .tabItem {
                    Label("High Priority", systemImage: "exclamationmark.triangle")
                }
                .tag(2)
        }
    }
}

struct OpenBugsTab: View {
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "status", equals: .string("open")
    )
    var bugs
    
    let db: BlazeDBClient
    
    var body: some View {
        List(bugs, id: \.id) { bug in
            BugRowView(bug: bug)
        }
    }
}

struct ClosedBugsTab: View {
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "status", equals: .string("closed"),
        sortBy: "closedAt", descending: true,
        limit: 50
    )
    var bugs
    
    let db: BlazeDBClient
    
    var body: some View {
        List(bugs, id: \.id) { bug in
            BugRowView(bug: bug)
                .opacity(0.7)
        }
    }
}

struct HighPriorityTab: View {
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "priority",
        .greaterThanOrEqual,
        .int(7),
        sortBy: "priority",
        descending: true
    )
    var bugs
    
    let db: BlazeDBClient
    
    var body: some View {
        List(bugs, id: \.id) { bug in
            BugRowView(bug: bug)
        }
        .navigationTitle("High Priority (\(bugs.count))")
    }
}

// MARK: - Example 3: Search with Dynamic Filtering

struct BugSearchView: View {
    @State private var searchText = ""
    @BlazeQuery(db: AppDatabase.shared.db)
    var allBugs
    
    var filteredBugs: [BlazeDataRecord] {
        if searchText.isEmpty {
            return allBugs
        }
        return $allBugs.filtered { bug in
            bug["title"]?.stringValue?.lowercased().contains(searchText.lowercased()) ?? false
        }
    }
    
    var body: some View {
        NavigationView {
            List(filteredBugs, id: \.id) { bug in
                BugRowView(bug: bug)
            }
            .searchable(text: $searchText, prompt: "Search bugs")
            .navigationTitle("Search")
        }
    }
}

// MARK: - Example 4: Detail View with Auto-Refresh

struct BugDetailView: View {
    let bugID: UUID
    @BlazeQuery(db: AppDatabase.shared.db)
    var allBugs
    
    var bug: BlazeDataRecord? {
        $allBugs.record(withID: bugID)
    }
    
    var body: some View {
        Group {
            if let bug = bug {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        Text(bug["title"]?.stringValue ?? "")
                            .font(.title)
                        
                        // Metadata
                        HStack {
                            PriorityBadge(priority: bug["priority"]?.intValue ?? 0)
                            StatusBadge(status: bug["status"]?.stringValue ?? "")
                        }
                        
                        // Description
                        if let description = bug["description"]?.stringValue {
                            Text(description)
                                .font(.body)
                        }
                        
                        // Assignee
                        if let assignee = bug["assignee"]?.stringValue {
                            HStack {
                                Text("Assignee:")
                                    .font(.headline)
                                Text(assignee)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            } else {
                Text("Bug not found")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Bug Details")
        .refreshOnAppear($allBugs)  // Auto-refresh when view appears
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    var statusColor: Color {
        switch status {
        case "open": return .blue
        case "closed": return .green
        case "pending": return .orange
        default: return .gray
        }
    }
}

// MARK: - Example 5: Form with Database Updates

struct CreateBugView: View {
    @Environment(\.dismiss) var dismiss
    let db = AppDatabase.shared.db
    
    @State private var title = ""
    @State private var description = ""
    @State private var priority = 5
    @State private var assignee = ""
    
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "status", equals: .string("open")
    )
    var openBugs  // Will auto-update after we insert!
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(5...)
                }
                
                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        ForEach(1...10, id: \.self) { i in
                            Text("P\(i)").tag(i)
                        }
                    }
                    TextField("Assignee", text: $assignee)
                }
                
                Section {
                    Button("Create Bug") {
                        createBug()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .navigationTitle("New Bug")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    func createBug() {
        Task {
            do {
                let bug = BlazeDataRecord([
                    "title": .string(title),
                    "description": .string(description),
                    "priority": .int(priority),
                    "assignee": .string(assignee),
                    "status": .string("open"),
                    "createdAt": .date(Date())
                ])
                
                try await db.insert(bug)
                
                // @BlazeQuery will auto-refresh and show the new bug!
                dismiss()
            } catch {
                print("Error creating bug: \(error)")
            }
        }
    }
}

// MARK: - Example 6: Stats Dashboard with Auto-Refresh

struct StatsDashboardView: View {
    @BlazeQuery(db: AppDatabase.shared.db)
    var allBugs
    
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "status", equals: .string("open")
    )
    var openBugs
    
    @BlazeQuery(
        db: AppDatabase.shared.db,
        where: "priority",
        .greaterThanOrEqual,
        .int(7)
    )
    var highPriorityBugs
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats Cards
                HStack(spacing: 15) {
                    StatCard(
                        title: "Total Bugs",
                        value: "\(allBugs.count)",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "Open",
                        value: "\(openBugs.count)",
                        color: .orange
                    )
                    
                    StatCard(
                        title: "High Priority",
                        value: "\(highPriorityBugs.count)",
                        color: .red
                    )
                }
                .padding()
                
                // Recent High Priority Bugs
                VStack(alignment: .leading) {
                    Text("Recent High Priority")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(highPriorityBugs.prefix(5), id: \.id) { bug in
                        BugRowView(bug: bug)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle("Dashboard")
        .onAppear {
            // Enable auto-refresh every 10 seconds
            $allBugs.enableAutoRefresh(interval: 10)
            $openBugs.enableAutoRefresh(interval: 10)
            $highPriorityBugs.enableAutoRefresh(interval: 10)
        }
        .onDisappear {
            // Disable when view disappears
            $allBugs.disableAutoRefresh()
            $openBugs.disableAutoRefresh()
            $highPriorityBugs.disableAutoRefresh()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - App Database Singleton

class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient
    
    private init() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bugs.blazedb")
        
        do {
            db = try BlazeDBClient(fileURL: url, project: "bugs")
        } catch {
            // Log error instead of crashing
            print("❌ Failed to initialize database: \(error)")
            // In a real SwiftUI app, you might want to show an alert or handle this gracefully
            // For this example, we'll just log and leave db as nil
        }
    }
}

// MARK: - Example 7: Advanced - Multiple Filters in UI

struct AdvancedFilterView: View {
    @State private var selectedStatus: String? = nil
    @State private var minPriority: Int = 1
    
    let db = AppDatabase.shared.db
    
    // Build filters dynamically
    var filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)] {
        var result: [(String, BlazeQueryComparison, BlazeDocumentField)] = []
        
        if let status = selectedStatus {
            result.append(("status", .equals, .string(status)))
        }
        
        if minPriority > 1 {
            result.append(("priority", .greaterThanOrEqual, .int(minPriority)))
        }
        
        return result
    }
    
    var body: some View {
        VStack {
            // Filters UI
            Form {
                Section("Filters") {
                    Picker("Status", selection: $selectedStatus) {
                        Text("All").tag(nil as String?)
                        Text("Open").tag("open" as String?)
                        Text("Closed").tag("closed" as String?)
                        Text("Pending").tag("pending" as String?)
                    }
                    
                    Stepper("Min Priority: \(minPriority)", value: $minPriority, in: 1...10)
                }
            }
            .frame(height: 200)
            
            // Filtered Results
            FilteredBugsList(db: db, filters: filters)
        }
        .navigationTitle("Advanced Filters")
    }
}

struct FilteredBugsList: View {
    let db: BlazeDBClient
    let filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]
    
    init(db: BlazeDBClient, filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]) {
        self.db = db
        self.filters = filters
        _query = BlazeQuery(db: db, filters: filters, sortBy: "priority", descending: true)
    }
    
    @BlazeQuery var query: [BlazeDataRecord]
    
    var body: some View {
        List(query, id: \.id) { bug in
            BugRowView(bug: bug)
        }
    }
}

