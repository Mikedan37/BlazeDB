import Foundation
import BlazeDB

// MARK: - Query Builder Example

/// This example demonstrates the powerful query builder with JOINs
func queryBuilderExample() throws {
    // Setup
    let bugsURL = FileManager.default.temporaryDirectory.appendingPathComponent("qb_bugs.blazedb")
    let usersURL = FileManager.default.temporaryDirectory.appendingPathComponent("qb_users.blazedb")
    
    let bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "demo")
    let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "demo")
    
    // Insert users
    let userAlice = UUID()
    let userBob = UUID()
    let userCharlie = UUID()
    
    _ = try usersDB.insert(BlazeDataRecord([
        "id": .uuid(userAlice),
        "name": .string("Alice"),
        "role": .string("senior"),
        "email": .string("alice@example.com")
    ]))
    
    _ = try usersDB.insert(BlazeDataRecord([
        "id": .uuid(userBob),
        "name": .string("Bob"),
        "role": .string("junior"),
        "email": .string("bob@example.com")
    ]))
    
    _ = try usersDB.insert(BlazeDataRecord([
        "id": .uuid(userCharlie),
        "name": .string("Charlie"),
        "role": .string("senior"),
        "email": .string("charlie@example.com")
    ]))
    
    // Insert bugs
    let now = Date()
    for i in 0..<20 {
        let author = [userAlice, userBob, userCharlie][i % 3]
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug \(i)"),
            "status": .string(i % 3 == 0 ? "open" : "closed"),
            "priority": .int(i % 5 + 1),
            "severity": .string(i % 2 == 0 ? "high" : "low"),
            "author_id": .uuid(author),
            "created_at": .date(Date(timeInterval: Double(i * 3600), since: now))
        ]))
    }
    
    print("🔍 QUERY BUILDER EXAMPLES")
    print("=" * 60)
    
    // EXAMPLE 1: Simple WHERE
    print("\n📝 Example 1: Simple WHERE clause")
    print("Code: db.query().where(\"status\", equals: \"open\").execute()")
    
    let openBugs = try bugsDB.query()
        .where("status", equals: .string("open"))
        .execute()
    
    print("Result: \(openBugs.count) open bugs")
    
    // EXAMPLE 2: Multiple WHERE (AND logic)
    print("\n📝 Example 2: Multiple WHERE clauses (AND)")
    print("Code: .where(\"status\", equals: \"open\")")
    print("      .where(\"priority\", lessThan: 3)")
    
    let filtered = try bugsDB.query()
        .where("status", equals: .string("open"))
        .where("priority", lessThan: .int(3))
        .execute()
    
    print("Result: \(filtered.count) open bugs with priority < 3")
    
    // EXAMPLE 3: ORDER BY
    print("\n📝 Example 3: ORDER BY")
    print("Code: .where(\"status\", equals: \"open\")")
    print("      .orderBy(\"priority\", descending: false)")
    
    let sorted = try bugsDB.query()
        .where("status", equals: .string("open"))
        .orderBy("priority", descending: false)
        .execute()
    
    print("Result: \(sorted.count) bugs sorted by priority (ascending)")
    if !sorted.isEmpty {
        print("  First: priority = \(sorted[0]["priority"]?.intValue ?? 0)")
        print("  Last: priority = \(sorted[sorted.count - 1]["priority"]?.intValue ?? 0)")
    }
    
    // EXAMPLE 4: LIMIT
    print("\n📝 Example 4: TOP N with LIMIT")
    print("Code: .orderBy(\"priority\", descending: true).limit(5)")
    
    let topBugs = try bugsDB.query()
        .orderBy("priority", descending: true)
        .limit(5)
        .execute()
    
    print("Result: Top \(topBugs.count) bugs by priority")
    for (i, bug) in topBugs.enumerated() {
        print("  \(i+1). \(bug["title"]?.stringValue ?? "") (priority: \(bug["priority"]?.intValue ?? 0))")
    }
    
    // EXAMPLE 5: Query Builder + JOIN
    print("\n📝 Example 5: Query Builder + JOIN (THE POWERFUL ONE!) 🔥")
    print("Code: db.query()")
    print("        .where(\"status\", equals: \"open\")")
    print("        .where(\"priority\", lessThan: 3)")
    print("        .join(usersDB, on: \"author_id\")")
    print("        .orderBy(\"created_at\", descending: true)")
    print("        .limit(5)")
    print("        .executeJoin()")
    
    let complexQuery = try bugsDB.query()
        .where("status", equals: .string("open"))
        .where("priority", lessThan: .int(3))
        .join(usersDB.collection, on: "author_id")
        .orderBy("created_at", descending: true)
        .limit(5)
        .executeJoin()
    
    print("\nResult: \(complexQuery.count) bugs with author details")
    for (i, joined) in complexQuery.enumerated() {
        let title = joined.left["title"]?.stringValue ?? ""
        let author = joined.right?["name"]?.stringValue ?? ""
        let priority = joined.left["priority"]?.intValue ?? 0
        print("  \(i+1). '\(title)' by \(author) (priority: \(priority))")
    }
    
    // EXAMPLE 6: Contains (Text Search)
    print("\n📝 Example 6: Text search with contains")
    print("Code: .where(\"title\", contains: \"Bug\")")
    
    let searchResults = try bugsDB.query()
        .where("title", contains: "Bug")
        .where("status", equals: .string("open"))
        .limit(3)
        .execute()
    
    print("Result: \(searchResults.count) bugs matching search")
    
    // EXAMPLE 7: IN clause
    print("\n📝 Example 7: IN clause")
    print("Code: .where(\"priority\", in: [1, 2, 5])")
    
    let inResults = try bugsDB.query()
        .where("priority", in: [.int(1), .int(2), .int(5)])
        .execute()
    
    print("Result: \(inResults.count) bugs with priority 1, 2, or 5")
    
    // EXAMPLE 8: Custom closure (maximum flexibility)
    print("\n📝 Example 8: Custom WHERE closure")
    print("Code: .where { bug in")
    print("        bug[\"priority\"]?.intValue ?? 0 > 3 &&")
    print("        bug[\"status\"]?.stringValue == \"open\"")
    print("      }")
    
    let customResults = try bugsDB.query()
        .where { bug in
            let priority = bug["priority"]?.intValue ?? 0
            let status = bug["status"]?.stringValue ?? ""
            return priority > 3 && status == "open"
        }
        .execute()
    
    print("Result: \(customResults.count) bugs matching custom logic")
    
    // EXAMPLE 9: Real-World AshPile Query
    print("\n📝 Example 9: Real-world AshPile query 🚀")
    print("Query: \"Show top 10 open high-severity bugs by senior devs, sorted by recency\"")
    
    let ashpileQuery = try bugsDB.query()
        .where("status", equals: .string("open"))
        .where("severity", equals: .string("high"))
        .join(usersDB.collection, on: "author_id")
        .orderBy("created_at", descending: true)
        .limit(10)
        .executeJoin()
    
    // Filter by senior role (could optimize this later)
    let seniorBugs = ashpileQuery.filter {
        $0.right?["role"]?.stringValue == "senior"
    }
    
    print("\nResult: \(seniorBugs.count) bugs matching all criteria")
    for (i, joined) in seniorBugs.enumerated() {
        let title = joined.left["title"]?.stringValue ?? ""
        let author = joined.right?["name"]?.stringValue ?? ""
        print("  \(i+1). '\(title)' by \(author) (senior dev)")
    }
    
    // EXAMPLE 10: Pagination
    print("\n📝 Example 10: Pagination (page 2 of open bugs)")
    print("Code: .where(\"status\", equals: \"open\")")
    print("      .orderBy(\"created_at\", descending: true)")
    print("      .offset(10).limit(10)")
    
    let page2 = try bugsDB.query()
        .where("status", equals: .string("open"))
        .orderBy("created_at", descending: true)
        .offset(10)
        .limit(10)
        .execute()
    
    print("Result: Page 2 with \(page2.count) bugs")
    
    // Clean up
    try? FileManager.default.removeItem(at: bugsURL)
    try? FileManager.default.removeItem(at: usersURL)
    
    print("\n✅ QUERY BUILDER DEMO COMPLETE!")
    print("This is the swifty, chainable API you wanted! 🔥")
}

// Run: try? queryBuilderExample()

