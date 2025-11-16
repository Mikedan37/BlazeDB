import Foundation
import BlazeDB

// MARK: - Developer Experience: Before vs After

/// This example demonstrates the DX improvements in BlazeDB v2.4
func improvedDXExamples() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("dx-example.blazedb")
    
    guard let db = BlazeDBClient(name: "DXExample", at: fileURL, password: "password-123") else {
        print("Failed to initialize database")
        return
    }
    
    // ============================================
    // IMPROVEMENT 1: Cleaner Record Creation
    // ============================================
    
    print("\n📝 Record Creation (Before vs After)")
    print("=" * 50)
    
    // ❌ OLD WAY (Verbose)
    let oldBug = BlazeDataRecord([
        "title": .string("Login button broken"),
        "description": .string("When clicking login, nothing happens"),
        "priority": .int(3),
        "status": .string("open"),
        "createdAt": .date(Date()),
        "tags": .array([.string("ui"), .string("critical")])
    ])
    
    // ✅ NEW WAY 1: DSL with => operator
    let newBug1 = BlazeDataRecord {
        "title" => "Login button broken"
        "description" => "When clicking login, nothing happens"
        "priority" => 3
        "status" => "open"
        "createdAt" => Date()
        "tags" => ["ui", "critical"]
    }
    
    // ✅ NEW WAY 2: Fluent builder
    let newBug2 = BlazeDataRecord()
        .set("title", to: "Login button broken")
        .set("description", to: "When clicking login, nothing happens")
        .set("priority", to: 3)
        .set("status", to: "open")
        .set("createdAt", to: Date())
        .set("tags", to: ["ui", "critical"])
    
    // ✅ NEW WAY 3: Builder pattern with closure
    let id1 = try db.insert { record in
        record.storage["title"] = .string("Password reset broken")
        record.storage["priority"] = .int(5)
        record.storage["status"] = .string("open")
    }
    
    print("✅ Created bug (DSL): \(try db.insert(newBug1))")
    print("✅ Created bug (Fluent): \(try db.insert(newBug2))")
    print("✅ Created bug (Builder): \(id1)")
    
    // ============================================
    // IMPROVEMENT 2: Cleaner Field Access
    // ============================================
    
    print("\n🔍 Field Access (Before vs After)")
    print("=" * 50)
    
    let bug = try db.fetch(id: id1)!
    
    // ❌ OLD WAY (Optional hell)
    let oldTitle = bug["title"]?.stringValue ?? "No title"
    let oldPriority = bug["priority"]?.intValue ?? 0
    let oldCreatedAt = bug["createdAt"]?.dateValue ?? Date()
    
    // ✅ NEW WAY (Clean with defaults)
    let newTitle = bug.string("title")
    let newPriority = bug.int("priority")
    let newCreatedAt = bug.date("createdAt")
    
    // ✅ NEW WAY (Explicit optionals when needed)
    let assignee = bug.stringOptional("assignee")  // nil if not exists
    
    print("Old way: \(oldTitle) - P\(oldPriority)")
    print("New way: \(newTitle) - P\(newPriority)")
    print("Assignee: \(assignee ?? "unassigned")")
    
    // ============================================
    // IMPROVEMENT 3: Simpler Queries
    // ============================================
    
    print("\n🔎 Queries (Before vs After)")
    print("=" * 50)
    
    // Insert more test data
    for i in 1...5 {
        _ = try db.insert {
            "title" => "Bug #\(i)"
            "priority" => i
            "status" => (i % 2 == 0) ? "open" : "closed"
        }
    }
    
    // ❌ OLD WAY (Two steps)
    let oldResult = try db.query()
        .where("status", equals: .string("open"))
        .where("priority", greaterThan: .int(2))
        .execute()
    let oldRecords = try oldResult.records
    
    // ✅ NEW WAY 1: Direct records with auto-wrapping
    let newRecords1 = try db.query()
        .where("status", equals: "open")  // No .string() wrapper!
        .where("priority", greaterThan: 2)  // No .int() wrapper!
        .all()  // Returns records directly!
    
    // ✅ NEW WAY 2: Quick helper
    let newRecords2 = try db.find { record in
        record.string("status") == "open" && record.int("priority") > 2
    }
    
    // ✅ NEW WAY 3: Find one
    let firstOpen = try db.findOne { $0.string("status") == "open" }
    
    // ✅ NEW WAY 4: Check existence
    let hasHighPriority = try db.query()
        .where("priority", greaterThan: 8)
        .exists()
    
    // ✅ NEW WAY 5: Quick count
    let openCount = try db.query()
        .where("status", equals: "open")
        .quickCount()
    
    print("Old way found: \(oldRecords.count) records")
    print("New way 1 found: \(newRecords1.count) records")
    print("New way 2 found: \(newRecords2.count) records")
    print("First open bug: \(firstOpen?.string("title") ?? "none")")
    print("Has high priority bugs: \(hasHighPriority)")
    print("Open bugs count: \(openCount)")
    
    // ============================================
    // IMPROVEMENT 4: Cleaner Updates
    // ============================================
    
    print("\n✏️ Updates (Before vs After)")
    print("=" * 50)
    
    // ❌ OLD WAY (Fetch, modify, update)
    if let oldBug = try db.fetch(id: id1) {
        var modified = oldBug
        modified.storage["status"] = .string("closed")
        modified.storage["closedAt"] = .date(Date())
        try db.update(id: id1, with: modified)
    }
    
    // ✅ NEW WAY 1: Builder pattern
    try db.update(id: id1) { record in
        record.storage["status"] = .string("open")
        record.storage["reopenedAt"] = .date(Date())
    }
    
    // ✅ NEW WAY 2: Fluent (using existing updateFields)
    try db.updateFields(id: id1, fields: [
        "status": .string("closed"),
        "closedAt": .date(Date())
    ])
    
    print("✅ Updated bug status")
    
    // ============================================
    // IMPROVEMENT 5: QueryResult Convenience
    // ============================================
    
    print("\n📊 Result Handling (Before vs After)")
    print("=" * 50)
    
    // ❌ OLD WAY (Try needed)
    let oldAggResult = try db.query()
        .groupBy("status")
        .count()
        .execute()
    let oldGroups = try oldAggResult.grouped
    
    // ✅ NEW WAY 1: OrEmpty helpers
    let newGroups = db.query()
        .groupBy("status")
        .count()
        .execute()
        .recordsOrEmpty  // Never throws, returns [] on wrong type
    
    // ✅ NEW WAY 2: Check if empty
    let isEmpty = try db.query()
        .where("status", equals: "archived")
        .execute()
        .isEmpty
    
    // ✅ NEW WAY 3: Get count
    let resultCount = try db.query()
        .where("status", equals: "open")
        .execute()
        .count
    
    print("Old way groups: \(oldGroups.count)")
    print("Result is empty: \(isEmpty)")
    print("Result count: \(resultCount)")
    
    // ============================================
    // IMPROVEMENT 6: Async/Await Improvements
    // ============================================
    
    print("\n⚡ Async (Before vs After)")
    print("=" * 50)
    
    Task {
        // ❌ OLD WAY
        let oldAsyncResult = try await db.query()
            .where("status", equals: .string("open"))
            .execute()
        let oldAsyncRecords = try oldAsyncResult.records
        
        // ✅ NEW WAY (Direct)
        let newAsyncRecords = try await db.query()
            .where("status", equals: "open")  // Auto-wrapped!
            .all()  // Returns records directly!
        
        // ✅ NEW WAY (Find helper)
        let asyncBugs = try await db.find { $0.string("status") == "open" }
        
        // ✅ NEW WAY (Builder insert)
        let asyncId = try await db.insert { record in
            record.storage["title"] = .string("Async bug")
            record.storage["priority"] = .int(1)
        }
        
        print("Old async found: \(oldAsyncRecords.count)")
        print("New async found: \(newAsyncRecords.count)")
        print("Async helper found: \(asyncBugs.count)")
        print("Async created: \(asyncId)")
    }
    
    // ============================================
    // COMPLETE EXAMPLE: Bug Tracker
    // ============================================
    
    print("\n🐛 Complete Bug Tracker Example")
    print("=" * 50)
    
    // Create bugs with clean DSL
    let bugs = [
        BlazeDataRecord {
            "title" => "Login broken"
            "description" => "Cannot login to app"
            "priority" => 5
            "status" => "open"
            "assignee" => "Alice"
            "tags" => ["critical", "auth"]
            "createdAt" => Date()
        },
        BlazeDataRecord {
            "title" => "UI glitch on iPad"
            "description" => "Button is cut off"
            "priority" => 2
            "status" => "open"
            "assignee" => "Bob"
            "tags" => ["ui", "ipad"]
            "createdAt" => Date()
        },
        BlazeDataRecord {
            "title" => "Crash on iOS 17"
            "description" => "App crashes on launch"
            "priority" => 10
            "status" => "open"
            "assignee" => "Alice"
            "tags" => ["critical", "crash"]
            "createdAt" => Date()
        }
    ]
    
    let bugIDs = try db.insertMany(bugs)
    print("Created \(bugIDs.count) bugs")
    
    // Query with clean syntax
    let criticalBugs = try db.query()
        .where("priority", greaterThan: 5)
        .where("status", equals: "open")
        .orderBy("priority", descending: true)
        .all()
    
    print("\nCritical Bugs:")
    for bug in criticalBugs {
        let title = bug.string("title")
        let priority = bug.int("priority")
        let assignee = bug.string("assignee", default: "unassigned")
        print("  • [\(assignee)] P\(priority): \(title)")
    }
    
    // Group by assignee with clean syntax
    let byAssignee = try db.query()
        .where("status", equals: "open")
        .groupBy("assignee")
        .count()
        .execute()
        .grouped
    
    print("\nBugs by Assignee:")
    for (assignee, agg) in byAssignee {
        print("  • \(assignee): \(agg.count ?? 0) bugs")
    }
    
    // Search with clean syntax
    let searchResults = try db.query()
        .search("login crash", in: ["title", "description"])
        .execute()
        .searchResultsOrEmpty
    
    print("\nSearch Results for 'login crash':")
    for result in searchResults {
        let title = result.record.string("title")
        print("  • \(title) (score: \(result.score))")
    }
    
    // Update with builder
    if let bugToClose = criticalBugs.first {
        try db.update(id: bugToClose.id) { bug in
            bug.storage["status"] = .string("closed")
            bug.storage["closedAt"] = .date(Date())
            bug.storage["resolution"] = .string("Fixed in v2.1")
        }
        print("\n✅ Closed bug: \(bugToClose.string("title"))")
    }
    
    // Cleanup
    try? FileManager.default.removeItem(at: fileURL)
    
    print("\n" + "=" * 50)
    print("🎉 All DX improvements demonstrated!")
    print("=" * 50)
}

// Helper for printing
private func * (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}

// Run the example
// try? improvedDXExamples()

