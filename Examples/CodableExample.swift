import Foundation
import BlazeDB

// MARK: - Codable Integration Complete Example

/// This example demonstrates BlazeDB's direct Codable support
/// No conversion needed - just use your regular Swift structs!

// MARK: - Define Your Models (Just Regular Codable!)

struct Bug: BlazeStorable {
    var id: UUID
    var title: String
    var description: String
    var priority: Int
    var status: String
    var createdAt: Date
    var tags: [String]
    var assignee: String?
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        priority: Int,
        status: String = "open",
        createdAt: Date = Date(),
        tags: [String] = [],
        assignee: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.createdAt = createdAt
        self.tags = tags
        self.assignee = assignee
    }
}

struct User: BlazeStorable {
    var id: UUID
    var name: String
    var email: String
    var role: String
    
    init(id: UUID = UUID(), name: String, email: String, role: String = "developer") {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
    }
}

// MARK: - Usage Examples

func codableExample() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("codable-example.blazedb")
    
    guard let db = BlazeDBClient(name: "CodableDemo", at: fileURL, password: "password-123") else {
        print("❌ Failed to initialize database")
        return
    }
    
    print("\n🎯 Codable Integration Demo")
    print("=" * 60)
    
    // ============================================
    // 1. CREATE - Just Use Your Structs!
    // ============================================
    
    print("\n📝 Creating records with Codable...")
    
    let bug1 = Bug(
        title: "Login button doesn't work",
        description: "When clicking login, nothing happens",
        priority: 5,
        tags: ["critical", "ui"],
        assignee: "Alice"
    )
    
    let bug2 = Bug(
        title: "Password reset broken",
        description: "Reset email never arrives",
        priority: 8,
        tags: ["critical", "auth"]
    )
    
    // Insert - no conversion needed!
    let id1 = try db.insert(bug1)
    let id2 = try db.insert(bug2)
    
    print("✅ Created bug 1: \(id1)")
    print("✅ Created bug 2: \(id2)")
    
    // Batch insert
    let users = [
        User(name: "Alice", email: "alice@example.com"),
        User(name: "Bob", email: "bob@example.com"),
        User(name: "Charlie", email: "charlie@example.com", role: "admin")
    ]
    
    let userIDs = try db.insertMany(users)
    print("✅ Created \(userIDs.count) users")
    
    // ============================================
    // 2. READ - Type-Safe Access!
    // ============================================
    
    print("\n🔍 Fetching records...")
    
    // Fetch by ID - returns typed object
    if let fetched = try db.fetch(Bug.self, id: id1) {
        print("Fetched: \(fetched.title)")
        print("  Priority: \(fetched.priority)")
        print("  Assignee: \(fetched.assignee ?? "unassigned")")
        print("  Tags: \(fetched.tags.joined(separator: ", "))")
        // No .stringValue, .intValue, etc needed!
    }
    
    // Fetch all
    let allBugs = try db.fetchAll(Bug.self)
    print("\nTotal bugs: \(allBugs.count)")
    
    for bug in allBugs {
        print("  • [\(bug.assignee ?? "unassigned")] P\(bug.priority): \(bug.title)")
    }
    
    // ============================================
    // 3. QUERY - Type-Safe Queries!
    // ============================================
    
    print("\n🔎 Querying with Codable...")
    
    // Query returns typed results
    let criticalBugs = try db.query(Bug.self)
        .where("priority", greaterThan: 5)
        .where("status", equals: "open")
        .orderBy("priority", descending: true)
        .all()
    
    print("\nCritical bugs (priority > 5):")
    for bug in criticalBugs {
        print("  • P\(bug.priority): \(bug.title)")
    }
    
    // Simple queries
    let first = try db.query(Bug.self)
        .where("assignee", equals: "Alice")
        .first()
    
    print("\nFirst bug assigned to Alice: \(first?.title ?? "none")")
    
    // Count
    let openCount = try db.query(Bug.self)
        .where("status", equals: "open")
        .count()
    
    print("Open bugs: \(openCount)")
    
    // ============================================
    // 4. UPDATE - Type-Safe Updates!
    // ============================================
    
    print("\n✏️ Updating records...")
    
    if var bug = try db.fetch(Bug.self, id: id1) {
        bug.status = "in_progress"
        bug.assignee = "Bob"
        bug.tags.append("needs-review")
        
        try db.update(bug)
        print("✅ Updated bug: \(bug.title)")
    }
    
    // Verify update
    let updated = try db.fetch(Bug.self, id: id1)
    print("  New status: \(updated?.status ?? "unknown")")
    print("  New assignee: \(updated?.assignee ?? "unassigned")")
    
    // ============================================
    // 5. ASYNC - All Operations Support Async!
    // ============================================
    
    print("\n⚡ Async operations...")
    
    Task {
        let asyncBug = Bug(
            title: "Async created bug",
            description: "Created with async/await",
            priority: 3
        )
        
        let asyncID = try await db.insert(asyncBug)
        print("✅ Async created: \(asyncID)")
        
        let asyncFetched = try await db.fetch(Bug.self, id: asyncID)
        print("  Fetched: \(asyncFetched?.title ?? "none")")
        
        let asyncBugs = try await db.query(Bug.self)
            .where("priority", lessThan: 5)
            .all()
        
        print("  Low priority bugs: \(asyncBugs.count)")
    }
    
    // ============================================
    // 6. COMPARISON: Codable vs Dynamic
    // ============================================
    
    print("\n📊 Codable vs Dynamic comparison:")
    
    print("\nCodable approach:")
    print("```swift")
    print("let bug = Bug(title: \"Test\", priority: 5)")
    print("try db.insert(bug)")
    print("let fetched = try db.fetch(Bug.self, id: bug.id)")
    print("print(fetched.title)  // Direct access!")
    print("```")
    
    print("\nDynamic approach:")
    print("```swift")
    print("let bug = BlazeDataRecord { \"title\" => \"Test\"; \"priority\" => 5 }")
    print("try db.insert(bug)")
    print("let fetched = try db.fetch(id: bug.id)")
    print("print(fetched.string(\"title\"))  // Helper method")
    print("```")
    
    print("\n✨ Both work! Choose based on your needs:")
    print("  • Codable: Type-safe, autocomplete, refactor-friendly")
    print("  • Dynamic: Flexible, no schema, add fields anytime")
    
    // ============================================
    // 7. MIXED USAGE - Best of Both Worlds!
    // ============================================
    
    print("\n🔥 Mixed usage (Codable + Dynamic):")
    
    // Type-safe for core models
    let typedBug = Bug(title: "Typed bug", priority: 5)
    try db.insert(typedBug)
    
    // Dynamic for flexible data
    let settings = BlazeDataRecord {
        "theme" => "dark"
        "fontSize" => 14
        "customField" => "whatever you want!"
    }
    try db.insert(settings)
    
    print("✅ Same database, both Codable and dynamic records!")
    
    // Cleanup
    try? FileManager.default.removeItem(at: fileURL)
    
    print("\n" + "=" * 60)
    print("🎉 Codable integration complete!")
    print("=" * 60)
}

// Helper
private func * (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}

// Run the example
// try? codableExample()

