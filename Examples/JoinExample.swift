import Foundation
import BlazeDB

// MARK: - JOIN Example

/// This example demonstrates how to use JOINs to query related data across collections
func joinExample() throws {
    // Setup databases
    let bugsURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("bugs.blazedb")
    let usersURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("users.blazedb")
    
    let bugsDB = try BlazeDBClient(
        name: "bugs",
        fileURL: bugsURL,
        password: "password"
    )
    
    let usersDB = try BlazeDBClient(
        name: "users",
        fileURL: usersURL,
        password: "password"
    )
    
    // Insert users
    let userAlice = UUID()
    let userBob = UUID()
    
    _ = try usersDB.insert(BlazeDataRecord([
        "id": .uuid(userAlice),
        "name": .string("Alice"),
        "email": .string("alice@example.com"),
        "role": .string("developer")
    ]))
    
    _ = try usersDB.insert(BlazeDataRecord([
        "id": .uuid(userBob),
        "name": .string("Bob"),
        "email": .string("bob@example.com"),
        "role": .string("qa")
    ]))
    
    print("✅ Inserted 2 users")
    
    // Insert bugs
    _ = try bugsDB.insert(BlazeDataRecord([
        "title": .string("Login broken"),
        "status": .string("open"),
        "priority": .int(1),
        "author_id": .uuid(userAlice)
    ]))
    
    _ = try bugsDB.insert(BlazeDataRecord([
        "title": .string("Slow query"),
        "status": .string("in_progress"),
        "priority": .int(2),
        "author_id": .uuid(userBob)
    ]))
    
    _ = try bugsDB.insert(BlazeDataRecord([
        "title": .string("Memory leak"),
        "status": .string("open"),
        "priority": .int(1),
        "author_id": .uuid(userAlice)
    ]))
    
    print("✅ Inserted 3 bugs")
    
    // EXAMPLE 1: Inner Join (bugs with authors)
    print("\n--- Example 1: Inner Join ---")
    let bugsWithAuthors = try bugsDB.join(
        with: usersDB,
        on: "author_id",  // Foreign key in bugs
        equals: "id",      // Primary key in users
        type: .inner       // Only matching records
    )
    
    print("Bugs with authors (\(bugsWithAuthors.count)):")
    for joined in bugsWithAuthors {
        let bugTitle = joined.left["title"]?.stringValue ?? "Unknown"
        let authorName = joined.right?["name"]?.stringValue ?? "Unknown"
        let status = joined.left["status"]?.stringValue ?? "Unknown"
        print("  - '\(bugTitle)' by \(authorName) [\(status)]")
    }
    
    // EXAMPLE 2: Left Join (all bugs, with author if exists)
    print("\n--- Example 2: Left Join ---")
    
    // Add orphan bug (no author)
    _ = try bugsDB.insert(BlazeDataRecord([
        "title": .string("Orphan bug"),
        "status": .string("open"),
        "author_id": .uuid(UUID()) // Non-existent user
    ]))
    
    let allBugsWithAuthors = try bugsDB.join(
        with: usersDB,
        on: "author_id",
        equals: "id",
        type: .left
    )
    
    print("All bugs with authors (\(allBugsWithAuthors.count)):")
    for joined in allBugsWithAuthors {
        let bugTitle = joined.left["title"]?.stringValue ?? "Unknown"
        let authorName = joined.right?["name"]?.stringValue ?? "Unknown Author"
        print("  - '\(bugTitle)' by \(authorName)")
    }
    
    // EXAMPLE 3: Using merged() for simplified access
    print("\n--- Example 3: Merged Records ---")
    
    for joined in bugsWithAuthors {
        let merged = joined.merged()
        
        // Access fields from both collections easily
        let title = merged["title"]?.stringValue ?? ""
        let authorName = merged["name"]?.stringValue ?? ""
        let authorEmail = merged["email"]?.stringValue ?? ""
        let priority = merged["priority"]?.intValue ?? 0
        
        print("  - [\(priority)] \(title)")
        print("    Author: \(authorName) <\(authorEmail)>")
    }
    
    // EXAMPLE 4: Filtering joined results
    print("\n--- Example 4: Filtering Joined Results ---")
    
    let openBugs = bugsWithAuthors.filter { joined in
        joined.left["status"]?.stringValue == "open"
    }
    
    print("Open bugs: \(openBugs.count)")
    
    let aliceBugs = bugsWithAuthors.filter { joined in
        joined.right?["name"]?.stringValue == "Alice"
    }
    
    print("Alice's bugs: \(aliceBugs.count)")
    
    // EXAMPLE 5: Performance - Batch fetching
    print("\n--- Example 5: Performance Test ---")
    
    // Insert many bugs
    for i in 0..<1000 {
        let authorID = i % 2 == 0 ? userAlice : userBob
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug \(i)"),
            "author_id": .uuid(authorID)
        ]))
    }
    
    let start = Date()
    let manyResults = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
    let duration = Date().timeIntervalSince(start)
    
    print("Joined 1000+ bugs in \(String(format: "%.2f", duration * 1000))ms")
    print("Using batch fetch (not N+1 queries) ✅")
    
    // Clean up
    try? FileManager.default.removeItem(at: bugsURL)
    try? FileManager.default.removeItem(at: usersURL)
}

// Run the example
// try? joinExample()

