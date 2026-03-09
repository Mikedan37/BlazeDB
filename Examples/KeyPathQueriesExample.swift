import Foundation
import BlazeDB

// MARK: - Type-Safe KeyPath Queries Example

/// This example demonstrates type-safe queries using KeyPaths
/// Get autocomplete and compile-time checking!

struct Bug: BlazeStorable {
    var id: UUID
    var title: String
    var priority: Int
    var status: String
    var createdAt: Date
    var assignee: String
    
    init(
        id: UUID = UUID(),
        title: String,
        priority: Int,
        status: String = "open",
        createdAt: Date = Date(),
        assignee: String = "unassigned"
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.status = status
        self.createdAt = createdAt
        self.assignee = assignee
    }
}

func keyPathExample() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("keypath-example.blazedb")
    
    guard let db = try? BlazeDBClient.open(at: fileURL, password: "password-123") else {
        print("❌ Failed to initialize database")
        return
    }
    
    print("\n🎯 KeyPath Query Demo")
    print("=" * 60)
    
    // ============================================
    // 1. SETUP - Create Test Data
    // ============================================
    
    print("\n📝 Creating test data...")
    
    let bugs = [
        Bug(title: "Login broken", priority: 5, status: "open", assignee: "Alice"),
        Bug(title: "UI glitch", priority: 2, status: "open", assignee: "Bob"),
        Bug(title: "Crash on iPad", priority: 10, status: "open", assignee: "Alice"),
        Bug(title: "Typo in docs", priority: 1, status: "closed", assignee: "Charlie"),
        Bug(title: "Performance issue", priority: 7, status: "in_progress", assignee: "Bob")
    ]
    
    _ = try db.insertMany(bugs)
    print("✅ Created \(bugs.count) bugs")
    
    // ============================================
    // 2. STRING-BASED vs KEYPATH QUERIES
    // ============================================
    
    print("\n📊 Comparison: String-based vs KeyPath queries")
    print("-" * 60)
    
    // OLD: String-based (works but no autocomplete)
    print("\n❌ String-based (typo-prone):")
    print("```swift")
    print(".where(\"status\", equals: \"open\")  // No autocomplete!")
    print("```")
    
    let stringBased = try db.query(Bug.self)
        .where("status", equals: "open")
        .where("priority", greaterThan: 3)
        .all()
    
    print("Found: \(stringBased.count) bugs")
    
    // NEW: KeyPath-based (autocomplete + type-safe!)
    print("\n✅ KeyPath-based (autocomplete + compile-time checking):")
    print("```swift")
    print(".where(\\.status, equals: \"open\")  // Autocomplete! Type-safe!")
    print("```")
    
    let keyPathBased = try db.query(Bug.self)
        .where(\.status, equals: "open")      // Autocomplete works here!
        .where(\.priority, greaterThan: 3)    // Xcode suggests 'priority'
        .all()
    
    print("Found: \(keyPathBased.count) bugs")
    
    // ============================================
    // 3. AUTOCOMPLETE DEMO
    // ============================================
    
    print("\n⌨️ Autocomplete demo:")
    print("-" * 60)
    print("When you type: db.query(Bug.self).where(\\.")
    print("Xcode suggests: ✅ status ✅ priority ✅ title ✅ assignee")
    print("NO MORE TYPOS! 🎉")
    
    // ============================================
    // 4. POWERFUL QUERIES WITH KEYPATHS
    // ============================================
    
    print("\n🔎 Advanced KeyPath queries:")
    
    // Multiple KeyPath filters
    let alicesBugs = try db.query(Bug.self)
        .where(\.assignee, equals: "Alice")
        .where(\.status, equals: "open")
        .orderBy(\.priority, descending: true)
        .all()
    
    print("\nAlice's open bugs (sorted by priority):")
    for bug in alicesBugs {
        print("  • P\(bug.priority): \(bug.title)")
    }
    
    // Date comparisons
    let recent = try db.query(Bug.self)
        .where(\.createdAt, greaterThan: Date().addingTimeInterval(-3600))
        .all()
    
    print("\nRecent bugs (last hour): \(recent.count)")
    
    // Complex chaining
    let complex = try db.query(Bug.self)
        .where(\.status, equals: "open")
        .where(\.priority, greaterThan: 3)
        .where(\.assignee, equals: "Alice")
        .orderBy(\.priority, descending: true)
        .limit(5)
        .all()
    
    print("\nComplex query results: \(complex.count)")
    
    // ============================================
    // 5. HELPER METHODS
    // ============================================
    
    print("\n🛠 Helper methods:")
    
    // Get first
    let firstHigh = try db.query(Bug.self)
        .where(\.priority, greaterThan: 8)
        .first()
    
    print("\nFirst high priority bug: \(firstHigh?.title ?? "none")")
    
    // Check existence
    let hasCritical = try db.query(Bug.self)
        .where(\.priority, equals: 10)
        .exists()
    
    print("Has critical bugs: \(hasCritical)")
    
    // Quick count
    let openCount = try db.query(Bug.self)
        .where(\.status, equals: "open")
        .count()
    
    print("Open bugs: \(openCount)")
    
    // ============================================
    // 6. CUSTOM PREDICATES (When You Need More)
    // ============================================
    
    print("\n🎨 Custom predicates:")
    
    let customFiltered = try db.query(Bug.self)
        .filter { bug in
            // Full access to typed object!
            bug.priority > 3 &&
            bug.status == "open" &&
            bug.tags.contains("critical")
        }
        .all()
    
    print("\nCustom filter results: \(customFiltered.count)")
    
    // ============================================
    // 7. ASYNC QUERIES
    // ============================================
    
    print("\n⚡ Async queries:")
    
    Task {
        let asyncBugs = try await db.query(Bug.self)
            .where(\.status, equals: "open")
            .where(\.priority, greaterThan: 5)
            .all()
        
        print("Async query found: \(asyncBugs.count) bugs")
        
        let asyncFirst = try await db.query(Bug.self)
            .where(\.assignee, equals: "Bob")
            .first()
        
        print("Bob's first bug: \(asyncFirst?.title ?? "none")")
    }
    
    // ============================================
    // 8. THE BIG WIN: NO TYPOS!
    // ============================================
    
    print("\n🏆 The KeyPath advantage:")
    print("-" * 60)
    
    print("\n❌ String-based (runtime errors):")
    print("```swift")
    print(".where(\"statuss\", equals: \"open\")  // Typo! Fails at runtime")
    print("```")
    
    print("\n✅ KeyPath-based (compile errors):")
    print("```swift")
    print(".where(\\.statuss, equals: \"open\")  // Compile error! Caught immediately")
    print("```")
    
    print("\n💡 Benefits:")
    print("  ✅ Autocomplete in Xcode")
    print("  ✅ Compile-time type checking")
    print("  ✅ Safe refactoring (rename field → updates all queries)")
    print("  ✅ No runtime 'field not found' errors")
    print("  ✅ Same or better performance")
    
    // Cleanup
    try? FileManager.default.removeItem(at: fileURL)
    
    print("\n" + "=" * 60)
    print("🎉 KeyPath queries demo complete!")
    print("=" * 60)
}

// Helper
private func * (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}

// Run the example
// try? keyPathExample()

