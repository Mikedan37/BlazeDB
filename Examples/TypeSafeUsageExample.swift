//
//  TypeSafeUsageExample.swift
//  BlazeDB Examples
//
//  Complete examples showing type-safe and dynamic API usage.
//  Demonstrates the three approaches: fully typed, fully dynamic, and hybrid.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation
import SwiftUI
import BlazeDB

// MARK: - Example 1: Fully Type-Safe Approach

/// Type-safe Bug model
struct Bug: BlazeDocument {
    var id: UUID
    var title: String
    var description: String
    var priority: Int
    var status: String
    var assignee: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    
    // Computed properties
    var isHighPriority: Bool {
        priority >= 7
    }
    
    var isOpen: Bool {
        status == "open"
    }
    
    // MARK: - Protocol Conformance
    
    func toStorage() throws -> BlazeDataRecord {
        var fields: [String: BlazeDocumentField] = [
            "id": .uuid(id),
            "title": .string(title),
            "description": .string(description),
            "priority": .int(priority),
            "status": .string(status),
            "tags": .array(tags.map { .string($0) }),
            "createdAt": .date(createdAt),
            "updatedAt": .date(updatedAt)
        ]
        
        if let assignee = assignee {
            fields["assignee"] = .string(assignee)
        }
        
        return BlazeDataRecord(fields)
    }
    
    init(from storage: BlazeDataRecord) throws {
        self.id = try storage.uuid("id")
        self.title = try storage.string("title")
        self.description = try storage.string("description")
        self.priority = try storage.int("priority")
        self.status = try storage.string("status")
        self.assignee = storage.stringOptional("assignee")
        
        let tagsArray = try storage.array("tags")
        self.tags = tagsArray.stringValues
        
        self.createdAt = try storage.date("createdAt")
        self.updatedAt = try storage.date("updatedAt")
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        priority: Int,
        status: String,
        assignee: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.assignee = assignee
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// Usage: Fully Type-Safe
func exampleFullyTypeSafe() async throws {
    let db = try BlazeDBClient(fileURL: URL(fileURLWithPath: "/tmp/bugs.blazedb"), project: "bugs")
    
    // CREATE - type-safe!
    let bug = Bug(
        title: "Fix login bug",
        description: "Users can't log in with special characters",
        priority: 8,
        status: "open",
        assignee: "Alice",
        tags: ["auth", "critical"]
    )
    try await db.insert(bug)
    
    // READ - type-safe!
    if let fetched = try await db.fetch(Bug.self, id: bug.id) {
        print(fetched.title)      // Direct access! ✅
        print(fetched.priority)   // No .intValue! ✅
        
        // Computed properties
        if fetched.isHighPriority {
            print("HIGH PRIORITY!")
        }
    }
    
    // UPDATE - type-safe!
    var updated = bug
    updated.priority = 10
    updated.status = "in-progress"
    updated.assignee = "Bob"
    updated.updatedAt = Date()
    try await db.update(updated)
    
    // QUERY - type-safe!
    let result = try await db.query()
        .where("status", equals: .string("open"))
        .where("priority", greaterThanOrEqual: .int(7))
        .orderBy("priority", descending: true)
        .execute()
    
    let highPriorityBugs = try result.records(as: Bug.self)
    for bug in highPriorityBugs {
        print("\(bug.title): P\(bug.priority)")  // Clean! ✅
    }
    
    // SWIFTUI - type-safe!
    struct BugListView: View {
        @BlazeQueryTyped(
            db: db,
            type: Bug.self,
            where: "status", equals: .string("open"),
            sortBy: "priority", descending: true
        )
        var bugs: [Bug]  // Type-safe! ✅
        
        var body: some View {
            List(bugs) { bug in
                VStack(alignment: .leading) {
                    Text(bug.title)  // No optional unwrapping! ✅
                    Text("P\(bug.priority)")  // Direct access! ✅
                }
            }
        }
    }
}

// MARK: - Example 2: Fully Dynamic Approach

func exampleFullyDynamic() async throws {
    let db = try BlazeDBClient(fileURL: URL(fileURLWithPath: "/tmp/bugs.blazedb"), project: "bugs")
    
    // CREATE - dynamic
    let bug = BlazeDataRecord([
        "title": .string("Fix login bug"),
        "priority": .int(8),
        "status": .string("open")
    ])
    let id = try await db.insert(bug)
    
    // READ - dynamic
    if let fetched = try await db.fetch(id: id) {
        let title = fetched["title"]?.stringValue ?? ""
        let priority = fetched["priority"]?.intValue ?? 0
        print("\(title): P\(priority)")
    }
    
    // UPDATE - dynamic
    var updated = try await db.fetch(id: id)!
    updated["priority"] = .int(10)
    updated["status"] = .string("in-progress")
    try await db.update(id: id, data: updated)
    
    // QUERY - dynamic
    let result = try await db.query()
        .where("status", equals: .string("open"))
        .execute()
    
    let records = try result.records
    for record in records {
        let title = record["title"]?.stringValue ?? ""
        print(title)
    }
    
    // SWIFTUI - dynamic
    struct BugListView: View {
        @BlazeQuery(
            db: db,
            where: "status", equals: .string("open")
        )
        var bugs: [BlazeDataRecord]
        
        var body: some View {
            List(bugs, id: \.id) { bug in
                Text(bug["title"]?.stringValue ?? "")
            }
        }
    }
}

// MARK: - Example 3: Hybrid Approach (BEST!)

/// Hybrid Bug model with both type-safe and dynamic fields
struct HybridBug: BlazeDocument {
    // Type-safe core fields
    var id: UUID
    var title: String
    var priority: Int
    
    // Access to underlying storage for dynamic fields
    private var _storage: BlazeDataRecord
    
    // Dynamic field accessor
    subscript(key: String) -> BlazeDocumentField? {
        get { _storage.storage[key] }
        set { _storage.storage[key] = newValue }
    }
    
    // Custom metadata accessor
    var customMetadata: [String: BlazeDocumentField] {
        get {
            return _storage.storage.filter { key, _ in
                !["id", "title", "priority"].contains(key)
            }
        }
    }
    
    // MARK: - Protocol Conformance
    
    func toStorage() throws -> BlazeDataRecord {
        return _storage
    }
    
    init(from storage: BlazeDataRecord) throws {
        self._storage = storage
        self.id = try storage.uuid("id")
        self.title = try storage.string("title")
        self.priority = try storage.int("priority")
    }
    
    init(id: UUID = UUID(), title: String, priority: Int) {
        self.id = id
        self.title = title
        self.priority = priority
        
        self._storage = BlazeDataRecord([
            "id": .uuid(id),
            "title": .string(title),
            "priority": .int(priority)
        ])
    }
}

// Usage: Hybrid Approach
func exampleHybrid() async throws {
    let db = try BlazeDBClient(fileURL: URL(fileURLWithPath: "/tmp/bugs.blazedb"), project: "bugs")
    
    // CREATE - with type-safe and dynamic fields
    var bug = HybridBug(title: "Fix login", priority: 8)
    bug["assignee"] = .string("Alice")          // Dynamic!
    bug["tags"] = .array([.string("auth")])     // Dynamic!
    bug["metadata"] = .dictionary([             // Dynamic!
        "severity": .string("critical"),
        "team": .string("Backend")
    ])
    try await db.insert(bug)
    
    // READ - access both types
    if let fetched = try await db.fetch(HybridBug.self, id: bug.id) {
        // Type-safe access
        print(fetched.title)      // ✅
        print(fetched.priority)   // ✅
        
        // Dynamic access
        let assignee = fetched["assignee"]?.stringValue ?? "Unassigned"
        let tags = fetched["tags"]?.arrayValue?.stringValues ?? []
        print("Assignee: \(assignee)")
        print("Tags: \(tags)")
        
        // Custom metadata
        for (key, value) in fetched.customMetadata {
            print("\(key): \(value)")
        }
    }
    
    // UPDATE - mix both
    var updated = bug
    updated.priority = 10                       // Type-safe!
    updated["status"] = .string("closed")       // Dynamic!
    try await db.update(updated)
}

// MARK: - Example 4: Real-World Bug Tracker (Type-Safe)

class BugTrackerService {
    let db: BlazeDBClient
    
    init(db: BlazeDBClient) {
        self.db = db
    }
    
    // CREATE
    func createBug(
        title: String,
        description: String,
        priority: Int,
        assignee: String?
    ) async throws -> Bug {
        let bug = Bug(
            title: title,
            description: description,
            priority: priority,
            status: "open",
            assignee: assignee
        )
        try await db.insert(bug)
        return bug
    }
    
    // READ
    func getBug(id: UUID) async throws -> Bug? {
        return try await db.fetch(Bug.self, id: id)
    }
    
    func getOpenBugs() async throws -> [Bug] {
        let result = try await db.query()
            .where("status", equals: .string("open"))
            .orderBy("priority", descending: true)
            .execute()
        return try result.records(as: Bug.self)
    }
    
    func getHighPriorityBugs() async throws -> [Bug] {
        let result = try await db.query()
            .where("priority", greaterThanOrEqual: .int(7))
            .where("status", equals: .string("open"))
            .execute()
        return try result.records(as: Bug.self)
    }
    
    func getBugsByAssignee(_ assignee: String) async throws -> [Bug] {
        let result = try await db.query()
            .where("assignee", equals: .string(assignee))
            .execute()
        return try result.records(as: Bug.self)
    }
    
    // UPDATE
    func assignBug(id: UUID, to assignee: String) async throws {
        guard var bug = try await db.fetch(Bug.self, id: id) else {
            throw BlazeDBError.recordNotFound
        }
        bug.assignee = assignee
        bug.updatedAt = Date()
        try await db.update(bug)
    }
    
    func updatePriority(id: UUID, priority: Int) async throws {
        guard var bug = try await db.fetch(Bug.self, id: id) else {
            throw BlazeDBError.recordNotFound
        }
        bug.priority = priority
        bug.updatedAt = Date()
        try await db.update(bug)
    }
    
    func closeBug(id: UUID) async throws {
        guard var bug = try await db.fetch(Bug.self, id: id) else {
            throw BlazeDBError.recordNotFound
        }
        bug.status = "closed"
        bug.updatedAt = Date()
        try await db.update(bug)
    }
    
    // DELETE
    func deleteBug(id: UUID) async throws {
        try await db.delete(id: id)
    }
    
    // BATCH
    func createMultipleBugs(_ bugs: [Bug]) async throws {
        try await db.insertMany(bugs)
    }
    
    func closeAllByAssignee(_ assignee: String) async throws -> Int {
        let result = try await db.query()
            .where("assignee", equals: .string(assignee))
            .execute()
        
        let bugs = try result.records(as: Bug.self)
        var closedCount = 0
        
        for var bug in bugs where bug.isOpen {
            bug.status = "closed"
            bug.updatedAt = Date()
            try await db.update(bug)
            closedCount += 1
        }
        
        return closedCount
    }
}

// SwiftUI Views with Type-Safe Models
struct TypeSafeBugListView: View {
    @BlazeQueryTyped(
        db: AppDatabase.shared.db,
        type: Bug.self,
        where: "status", equals: .string("open"),
        sortBy: "priority", descending: true
    )
    var openBugs: [Bug]
    
    var body: some View {
        NavigationStack {
            List(openBugs) { bug in
                BugRowView(bug: bug)
            }
            .navigationTitle("Open Bugs (\(openBugs.count))")
            .refreshable(query: $openBugs)
        }
    }
}

struct BugRowView: View {
    let bug: Bug
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bug.title)
                .font(.headline)
            
            Text(bug.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                PriorityBadge(priority: bug.priority)
                
                if let assignee = bug.assignee {
                    Text(assignee)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if bug.isHighPriority {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
                
                ForEach(bug.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PriorityBadge: View {
    let priority: Int
    
    var body: some View {
        Text("P\(priority)")
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(priorityColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    var priorityColor: Color {
        switch priority {
        case 1...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }
}

// MARK: - Example 5: Mix Type-Safe and Dynamic in Same App

class AppService {
    let db: BlazeDBClient
    
    init(db: BlazeDBClient) {
        self.db = db
    }
    
    // Use type-safe for core models
    func createUser(name: String, email: String) async throws -> UUID {
        struct User: BlazeDocument {
            var id: UUID
            var name: String
            var email: String
            
            func toStorage() throws -> BlazeDataRecord {
                return BlazeDataRecord([
                    "id": .uuid(id),
                    "name": .string(name),
                    "email": .string(email)
                ])
            }
            
            init(from storage: BlazeDataRecord) throws {
                self.id = try storage.uuid("id")
                self.name = try storage.string("name")
                self.email = try storage.string("email")
            }
            
            init(id: UUID = UUID(), name: String, email: String) {
                self.id = id
                self.name = name
                self.email = email
            }
        }
        
        let user = User(name: name, email: email)
        return try await db.insert(user)
    }
    
    // Use dynamic for flexible data
    func logEvent(name: String, properties: [String: BlazeDocumentField]) async throws {
        let event = BlazeDataRecord([
            "id": .uuid(UUID()),
            "event": .string(name),
            "timestamp": .date(Date()),
            "properties": .dictionary(properties)
        ])
        try await db.insert(event)
    }
    
    // Mix both!
    func createBugWithMetadata(
        title: String,
        priority: Int,
        customMetadata: [String: BlazeDocumentField]
    ) async throws -> UUID {
        // Create typed bug
        let bug = Bug(
            title: title,
            description: "",
            priority: priority,
            status: "open"
        )
        
        // Convert to storage and add custom metadata
        var storage = try bug.toStorage()
        for (key, value) in customMetadata {
            storage.storage[key] = value
        }
        
        // Insert with both typed and dynamic fields!
        return try await db.insert(storage)
    }
}

// MARK: - Example 6: Migration from Dynamic to Type-Safe

class MigrationExample {
    let db: BlazeDBClient
    
    init(db: BlazeDBClient) {
        self.db = db
    }
    
    // Old code (dynamic) - still works!
    func oldWay_CreateBug() async throws {
        let bug = BlazeDataRecord([
            "title": .string("Old way"),
            "priority": .int(1),
            "status": .string("open")
        ])
        try await db.insert(bug)
    }
    
    // New code (type-safe) - also works!
    func newWay_CreateBug() async throws {
        let bug = Bug(
            title: "New way",
            description: "",
            priority: 1,
            status: "open"
        )
        try await db.insert(bug)
    }
    
    // Fetch old data with new API
    func fetchOldDataWithNewAPI(id: UUID) async throws -> Bug? {
        // Old dynamic record can be fetched as typed!
        return try await db.fetch(Bug.self, id: id)
    }
    
    // Mix both in same function
    func mixedApproach() async throws {
        // Insert dynamic
        let dynamicBug = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Dynamic"),
            "description": .string(""),
            "priority": .int(1),
            "status": .string("open"),
            "tags": .array([]),
            "createdAt": .date(Date()),
            "updatedAt": .date(Date())
        ])
        let id1 = try await db.insert(dynamicBug)
        
        // Insert typed
        let typedBug = Bug(title: "Typed", description: "", priority: 2, status: "open")
        let id2 = try await db.insert(typedBug)
        
        // Fetch both
        let dynamic = try await db.fetch(Bug.self, id: id1)  // Typed API
        let typed = try await db.fetch(Bug.self, id: id2)    // Typed API
        
        // Both work!
        print(dynamic?.title ?? "")  // "Dynamic"
        print(typed?.title ?? "")    // "Typed"
    }
}

// MARK: - Example 7: Complex Nested Data

struct Project: BlazeDocument {
    var id: UUID
    var name: String
    var settings: ProjectSettings
    var members: [ProjectMember]
    
    struct ProjectSettings: Codable {
        var theme: String
        var isPublic: Bool
        var tags: [String]
    }
    
    struct ProjectMember: Codable, Identifiable {
        var id: UUID
        var name: String
        var role: String
    }
    
    func toStorage() throws -> BlazeDataRecord {
        // Encode nested structures as JSON Data
        let encoder = JSONEncoder()
        let settingsData = try encoder.encode(settings)
        let membersData = try encoder.encode(members)
        
        return BlazeDataRecord([
            "id": .uuid(id),
            "name": .string(name),
            "settings": .data(settingsData),
            "members": .data(membersData)
        ])
    }
    
    init(from storage: BlazeDataRecord) throws {
        self.id = try storage.uuid("id")
        self.name = try storage.string("name")
        
        let decoder = JSONDecoder()
        let settingsData = try storage.data("settings")
        self.settings = try decoder.decode(ProjectSettings.self, from: settingsData)
        
        let membersData = try storage.data("members")
        self.members = try decoder.decode([ProjectMember].self, from: membersData)
    }
    
    init(id: UUID = UUID(), name: String, settings: ProjectSettings, members: [ProjectMember]) {
        self.id = id
        self.name = name
        self.settings = settings
        self.members = members
    }
}

// Usage of nested model
func exampleNestedData() async throws {
    let db = try BlazeDBClient(fileURL: URL(fileURLWithPath: "/tmp/projects.blazedb"), project: "projects")
    
    let project = Project(
        name: "BlazeDB",
        settings: Project.ProjectSettings(
            theme: "dark",
            isPublic: true,
            tags: ["database", "swift", "ios"]
        ),
        members: [
            Project.ProjectMember(id: UUID(), name: "Alice", role: "Lead"),
            Project.ProjectMember(id: UUID(), name: "Bob", role: "Developer")
        ]
    )
    
    try await db.insert(project)
    
    // Fetch and access nested data
    if let fetched = try await db.fetch(Project.self, id: project.id) {
        print(fetched.name)
        print(fetched.settings.theme)
        print(fetched.settings.isPublic)
        print(fetched.members.count)
        
        for member in fetched.members {
            print("\(member.name): \(member.role)")
        }
    }
}

// MARK: - App Database Singleton

class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient
    
    private init() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.blazedb")
        
        do {
            db = try BlazeDBClient(fileURL: url, project: "app")
        } catch {
            // Log error instead of crashing
            print("❌ Failed to initialize database: \(error)")
            // In a real app, you might want to show an alert or handle this gracefully
            // For this example, we'll just log and leave db as nil
        }
    }
}

