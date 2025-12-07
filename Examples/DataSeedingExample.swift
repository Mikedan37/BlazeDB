import Foundation
import BlazeDB

// MARK: - Data Seeding & Fixtures Example

/// This example demonstrates BlazeDB's data seeding capabilities
/// Perfect for testing, demos, and development!

struct Bug: BlazeStorable {
    var id: UUID
    var title: String
    var priority: Int
    var status: String
    var assignee: String
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        priority: Int,
        status: String = "open",
        assignee: String = "unassigned",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.status = status
        self.assignee = assignee
        self.createdAt = createdAt
    }
}

func seedingExample() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("seeding-example.blazedb")
    
    guard let db = BlazeDBClient(name: "SeedDemo", at: fileURL, password: "password-123") else {
        print("❌ Failed to initialize database")
        return
    }
    
    print("\n🌱 Data Seeding Demo")
    print("=" * 60)
    
    // ============================================
    // 1. BASIC SEEDING
    // ============================================
    
    print("\n📝 Basic seeding...")
    
    // Generate 10 bugs
    let bugs = try db.seed(Bug.self, count: 10) { i in
        Bug(
            title: "Bug #\(i)",
            priority: i % 5 + 1,
            status: ["open", "closed"][i % 2],
            assignee: ["Alice", "Bob", "Charlie"][i % 3]
        )
    }
    
    print("✅ Created \(bugs.count) bugs with seeding")
    
    // ============================================
    // 2. REALISTIC RANDOM DATA
    // ============================================
    
    print("\n🎲 Seeding with realistic random data...")
    
    let randomBugs = try db.seed(Bug.self, count: 20) { i in
        Bug(
            title: RandomData.bugTitle(),           // Random title
            priority: RandomData.priority(),        // Random 1-10
            status: RandomData.status(),            // Random status
            assignee: RandomData.name(),            // Random name
            createdAt: RandomData.pastDate(days: 30)  // Random past date
        )
    }
    
    print("✅ Created \(randomBugs.count) bugs with random data")
    
    // Show variety
    let statuses = Set(randomBugs.map { $0.status })
    let assignees = Set(randomBugs.map { $0.assignee })
    print("  Unique statuses: \(statuses.count)")
    print("  Unique assignees: \(assignees.count)")
    
    // ============================================
    // 3. FACTORIES (Reusable Patterns)
    // ============================================
    
    print("\n🏭 Using factories...")
    
    // Register a factory
    db.factory(Bug.self) { i in
        Bug(
            title: "Factory Bug #\(i)",
            priority: 5,
            status: "open",
            assignee: "QA Team"
        )
    }
    
    // Create 5 bugs using the factory
    let factoryBugs = try db.create(Bug.self, count: 5)
    print("✅ Created \(factoryBugs.count) bugs from factory")
    
    // Create just one
    let singleBug = try db.create(Bug.self)
    print("✅ Created single bug: \(singleBug.title)")
    
    // ============================================
    // 4. BULK INSERT WITH DSL
    // ============================================
    
    print("\n📦 Bulk insert with DSL...")
    
    let ids = try db.bulkInsert {
        BlazeDataRecord { "title" => "Quick 1"; "priority" => 1 }
        BlazeDataRecord { "title" => "Quick 2"; "priority" => 2 }
        BlazeDataRecord { "title" => "Quick 3"; "priority" => 3 }
    }
    
    print("✅ Created \(ids.count) records with bulk DSL")
    
    // ============================================
    // 5. FIXTURES FROM JSON
    // ============================================
    
    print("\n📄 Loading fixtures from JSON...")
    
    // Create JSON file
    let jsonURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("fixtures.json")
    
    let json = """
    [
        {
            "id": "\(UUID().uuidString)",
            "title": "Fixture Bug 1",
            "priority": 3,
            "status": "open",
            "assignee": "Alice",
            "createdAt": "\(ISO8601DateFormatter().string(from: Date()))"
        },
        {
            "id": "\(UUID().uuidString)",
            "title": "Fixture Bug 2",
            "priority": 7,
            "status": "closed",
            "assignee": "Bob",
            "createdAt": "\(ISO8601DateFormatter().string(from: Date()))"
        }
    ]
    """
    
    try json.data(using: .utf8)?.write(to: jsonURL)
    
    let fixtureBugs = try db.loadFixtures(Bug.self, from: jsonURL)
    print("✅ Loaded \(fixtureBugs.count) bugs from JSON")
    
    for bug in fixtureBugs {
        print("  • \(bug.title) - P\(bug.priority)")
    }
    
    // ============================================
    // 6. SNAPSHOTS (Save & Restore State)
    // ============================================
    
    print("\n💾 Snapshots (save & restore)...")
    
    let allBefore = try db.fetchAll(Bug.self)
    print("\nTotal bugs before snapshot: \(allBefore.count)")
    
    // Create snapshot
    let snapshot = try db.snapshot()
    print("✅ Created snapshot (\(snapshot.records.count) records)")
    
    // Modify database
    _ = try db.seed(Bug.self, count: 10) { i in
        Bug(title: "New Bug \(i)", priority: i)
    }
    
    let allAfterChanges = try db.fetchAll(Bug.self)
    print("Total bugs after changes: \(allAfterChanges.count)")
    
    // Restore snapshot
    try db.restore(snapshot)
    
    let allAfterRestore = try db.fetchAll(Bug.self)
    print("✅ Restored snapshot")
    print("Total bugs after restore: \(allAfterRestore.count)")
    
    // ============================================
    // 7. TESTING WORKFLOWS
    // ============================================
    
    print("\n🧪 Testing workflow example:")
    print("-" * 60)
    
    print("\n```swift")
    print("// 1. Create snapshot before test")
    print("let snapshot = try db.snapshot()")
    print("")
    print("// 2. Seed test data")
    print("try db.seed(Bug.self, count: 100) { i in")
    print("    Bug(title: \"Test \(i)\", priority: i % 10)")
    print("}")
    print("")
    print("// 3. Run your tests")
    print("let results = try db.query(Bug.self)")
    print("    .where(\\.priority, greaterThan: 5)")
    print("    .all()")
    print("XCTAssertEqual(results.count, expectedCount)")
    print("")
    print("// 4. Restore snapshot (clean state)")
    print("try db.restore(snapshot)")
    print("```")
    
    // ============================================
    // 8. RANDOM DATA HELPERS
    // ============================================
    
    print("\n🎲 Random data generators:")
    
    let randomIds = try db.seedRandom(count: 15, fields: [
        "title": { .string(RandomData.bugTitle()) },
        "priority": { .int(RandomData.priority()) },
        "status": { .string(RandomData.status()) },
        "assignee": { .string(RandomData.name()) },
        "tags": { .array(RandomData.tags().map { .string($0) }) },
        "createdAt": { .date(RandomData.pastDate(days: 30)) }
    ])
    
    print("✅ Created \(randomIds.count) bugs with random realistic data")
    
    let randomBugs = try db.fetchAll()
    print("\nRandom sample:")
    for bug in randomBugs.prefix(3) {
        print("  • [\(bug.string("assignee"))] \(bug.string("title"))")
    }
    
    // ============================================
    // 9. PERFORMANCE COMPARISON
    // ============================================
    
    print("\n⚡ Performance comparison:")
    print("-" * 60)
    
    // Clear database
    _ = try db.deleteMany { _ in true }
    
    // Measure seeding
    let seedStart = Date()
    _ = try db.seed(Bug.self, count: 100) { i in
        Bug(title: "Seed \(i)", priority: i % 10)
    }
    let seedTime = Date().timeIntervalSince(seedStart)
    
    _ = try db.deleteMany { _ in true }
    
    // Measure manual creation
    let manualStart = Date()
    for i in 0..<100 {
        let bug = Bug(title: "Manual \(i)", priority: i % 10)
        _ = try db.insert(bug)
    }
    let manualTime = Date().timeIntervalSince(manualStart)
    
    print("\nSeeding 100 records:")
    print("  Seed method: \(Int(seedTime * 1000))ms")
    print("  Manual loop: \(Int(manualTime * 1000))ms")
    print("  Speedup: \(String(format: "%.1fx", manualTime / seedTime))")
    
    // Cleanup
    try? FileManager.default.removeItem(at: fileURL)
    try? FileManager.default.removeItem(at: jsonURL)
    
    print("\n" + "=" * 60)
    print("🎉 Data seeding demo complete!")
    print("=" * 60)
    
    print("\n💡 Use cases:")
    print("  • Testing (quick test data)")
    print("  • Demos (realistic sample data)")
    print("  • Development (fast database population)")
    print("  • Snapshots (save/restore state)")
}

// Helper
private func * (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}

// Run the example
// try? seedingExample()

