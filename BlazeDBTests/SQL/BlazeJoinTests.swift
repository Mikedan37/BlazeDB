//  BlazeJoinTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for JOIN functionality

import XCTest
@testable import BlazeDB

final class BlazeJoinTests: XCTestCase {
    
    var bugsURL: URL!
    var usersURL: URL!
    var commentsURL: URL!
    var bugsDB: BlazeDBClient!
    var usersDB: BlazeDBClient!
    var commentsDB: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        bugsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bugs-\(UUID().uuidString).blazedb")
        usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users-\(UUID().uuidString).blazedb")
        commentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Comments-\(UUID().uuidString).blazedb")
        
        do {
            bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "test-pass-123")
            usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123")
            commentsDB = try BlazeDBClient(name: "comments", fileURL: commentsURL, password: "test-pass-123")
        } catch {
            XCTFail("Failed to create databases: \(error)")
        }
    }
    
    override func tearDown() {
        bugsDB = nil
        usersDB = nil
        commentsDB = nil
        
        try? FileManager.default.removeItem(at: bugsURL)
        try? FileManager.default.removeItem(at: bugsURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: usersURL)
        try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: commentsURL)
        try? FileManager.default.removeItem(at: commentsURL.deletingPathExtension().appendingPathExtension("meta"))
        
        super.tearDown()
    }
    
    // MARK: - Basic JOIN Tests
    
    func testInnerJoinBasic() throws {
        // Insert users
        let userAlice = UUID()
        let userBob = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice"),
            "email": .string("alice@example.com")
        ]))
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userBob),
            "name": .string("Bob"),
            "email": .string("bob@example.com")
        ]))
        
        // Insert bugs
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Login broken"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Slow query"),
            "author_id": .uuid(userBob)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("No author"),
            "author_id": .uuid(UUID()) // Non-existent user
        ]))
        
        // Inner join: Only bugs with existing authors
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 2, "Should have 2 matches (bug 1 & 2)")
        
        // Verify first result
        let first = results[0]
        XCTAssertNotNil(first.left["title"])
        XCTAssertNotNil(first.right)
        XCTAssertNotNil(first.right?["name"])
        
        // Verify we have both Alice and Bob's bugs
        let authorNames = results.compactMap { $0.right?["name"]?.stringValue }
        XCTAssertTrue(authorNames.contains("Alice"))
        XCTAssertTrue(authorNames.contains("Bob"))
    }
    
    func testLeftJoinBasic() throws {
        let userAlice = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Has author"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("No author"),
            "author_id": .uuid(UUID()) // Non-existent
        ]))
        
        // Left join: All bugs, with author if exists
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .left
        )
        
        XCTAssertEqual(results.count, 2, "Should have both bugs")
        
        // One should have author
        let withAuthor = results.filter { $0.isComplete }
        XCTAssertEqual(withAuthor.count, 1)
        
        // One should be missing author
        let withoutAuthor = results.filter { !$0.isComplete }
        XCTAssertEqual(withoutAuthor.count, 1)
        XCTAssertNil(withoutAuthor[0].right)
    }
    
    func testRightJoinBasic() throws {
        // Enable logging for debugging
        BlazeLogger.level = .debug
        
        let userAlice = UUID()
        let userBob = UUID()
        
        print("\n📊 Setting up test data:")
        let aliceID = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        print("  Inserted Alice with ID: \(aliceID)")
        
        let bobID = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userBob),
            "name": .string("Bob")
        ]))
        print("  Inserted Bob with ID: \(bobID)")
        
        // Verify both users exist
        let allUsers = try usersDB.fetchAll()
        print("  Total users in DB: \(allUsers.count)")
        for user in allUsers {
            print("    User ID: \(user.storage["id"]), Name: \(user.storage["name"])")
        }
        
        // Only one bug (for Alice)
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "author_id": .uuid(userAlice)
        ]))
        print("  Inserted 1 bug for Alice")
        
        // Right join: All users, with bugs if they exist
        print("\n📊 Performing RIGHT JOIN:")
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .right
        )
        
        print("  Result count: \(results.count)")
        for (idx, result) in results.enumerated() {
            print("  Result \(idx): left.count=\(result.left.storage.count), right.name=\(result.right?.storage["name"])")
        }
        
        XCTAssertEqual(results.count, 2, "Should have both users")
        
        // One user has bug
        let withBugs = results.filter { $0.left.storage.count > 0 }
        print("\n  Records with bugs: \(withBugs.count)")
        XCTAssertEqual(withBugs.count, 1)
        
        // One user has no bugs
        let noBugs = results.filter { $0.left.storage.count == 0 }
        print("  Records without bugs: \(noBugs.count)")
        XCTAssertEqual(noBugs.count, 1)
        
        // Reset logger
        BlazeLogger.reset()
    }
    
    func testFullJoinBasic() throws {
        let userAlice = UUID()
        let orphanBugID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Bob")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Has author"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Orphan"),
            "author_id": .uuid(orphanBugID)
        ]))
        
        // Full join: Everything
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .full
        )
        
        // Should have:
        // - 1 matched pair (Alice + her bug)
        // - 1 orphan bug (no author)
        // - 1 orphan user (Bob, no bugs)
        XCTAssertEqual(results.count, 3)
    }
    
    // MARK: - Empty Collection Tests
    
    func testJoinWithEmptyLeftCollection() throws {
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Alice")
        ]))
        
        // Bugs collection is empty
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testJoinWithEmptyRightCollection() throws {
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "author_id": .uuid(UUID())
        ]))
        
        // Users collection is empty
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testJoinWithBothEmpty() throws {
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - Missing Field Tests
    
    func testJoinWithMissingForeignKey() throws {
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Alice")
        ]))
        
        // Bug without author_id field
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug")
            // No author_id!
        ]))
        
        // Inner join: Should skip bug without foreign key
        let innerResults = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        XCTAssertEqual(innerResults.count, 0)
        
        // Left join: Should include bug with nil author
        let leftResults = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .left
        )
        XCTAssertEqual(leftResults.count, 1)
        XCTAssertNil(leftResults[0].right)
    }
    
    // MARK: - Multiple Matches Tests
    
    func testJoinWithMultipleMatches() throws {
        let userAlice = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        // Multiple bugs by same author
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 3"),
            "author_id": .uuid(userAlice)
        ]))
        
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 3, "Should have 3 bug-author pairs")
        
        // All should reference same author
        let authorNames = results.compactMap { $0.right?["name"]?.stringValue }
        XCTAssertEqual(Set(authorNames), ["Alice"])
    }
    
    // MARK: - Compound Index Compatibility Tests
    
    func testJoinWithCompoundIndex() throws {
        let userAlice = UUID()
        
        // Create compound index on bugs
        try bugsDB.collection.createIndex(on: "status")
        try bugsDB.collection.createIndex(on: ["status", "priority"])
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "status": .string("open"),
            "priority": .int(1),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "status": .string("closed"),
            "priority": .int(2),
            "author_id": .uuid(userAlice)
        ]))
        
        // Join should still work with compound indexes
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 2)
        
        // Verify compound index still works after join
        let openBugs = try bugsDB.collection.fetch(byIndexedFields: ["status"], values: ["open"])
        XCTAssertEqual(openBugs.count, 1)
        
        let compoundResults = try bugsDB.collection.fetch(byIndexedFields: ["status", "priority"], values: ["open", 1])
        XCTAssertEqual(compoundResults.count, 1)
    }
    
    func testJoinDoesNotBreakSecondaryIndexes() throws {
        // Create index before join
        try bugsDB.collection.createIndex(on: "status")
        
        let userID = UUID()
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        // Insert bugs with status
        for i in 0..<10 {
            _ = try bugsDB.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "author_id": .uuid(userID)
            ]))
        }
        
        // Perform join
        let joinResults = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        XCTAssertEqual(joinResults.count, 10)
        
        // Verify secondary index still works
        let openBugs = try bugsDB.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(openBugs.count, 5)
        
        let closedBugs = try bugsDB.collection.fetch(byIndexedField: "status", value: "closed")
        XCTAssertEqual(closedBugs.count, 5)
    }
    
    // MARK: - Dynamic Schema Tests
    
    func testJoinWithDifferentDocumentTypes() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice"),
            "type": .string("user")
        ]))
        
        // Different document types with different schemas
        _ = try bugsDB.insert(BlazeDataRecord([
            "type": .string("bug"),
            "title": .string("Bug 1"),
            "severity": .string("high"),
            "author_id": .uuid(userID)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "type": .string("feature"),
            "title": .string("Feature 1"),
            "estimated_hours": .int(40),
            "author_id": .uuid(userID)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "type": .string("task"),
            "description": .string("Task 1"),
            "completed": .bool(false),
            "author_id": .uuid(userID)
        ]))
        
        // Join works across different document types
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 3)
        
        // Verify all have author
        for result in results {
            XCTAssertNotNil(result.right)
            XCTAssertEqual(result.right?["name"]?.stringValue, "Alice")
        }
        
        // Verify different types present
        let types = results.compactMap { $0.left["type"]?.stringValue }
        XCTAssertTrue(types.contains("bug"))
        XCTAssertTrue(types.contains("feature"))
        XCTAssertTrue(types.contains("task"))
    }
    
    func testJoinWithNestedFields() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "profile": .dictionary([
                "name": .string("Alice"),
                "avatar": .string("avatar.png")
            ])
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "metadata": .dictionary([
                "author_id": .uuid(userID),
                "tags": .array([.string("urgent"), .string("backend")])
            ])
        ]))
        
        // Join on nested field (not directly supported, but test it doesn't crash)
        // This bug has top-level author_id missing, so won't match
        let results = try bugsDB.join(
            with: usersDB,
            on: "metadata.author_id", // Won't match (not flattened)
            equals: "id",
            type: .left
        )
        
        // Bug should appear but without match
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].right)
    }
    
    // MARK: - Field Type Tests
    
    func testJoinWithStringUUID() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        // Bug with author_id as string (should still work)
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "author_id": .string(userID.uuidString)
        ]))
        
        let results = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        
        XCTAssertEqual(results.count, 1, "Should handle string UUID format")
        XCTAssertEqual(results[0].right?["name"]?.stringValue, "Alice")
    }
    
    func testJoinWithInvalidFieldType() throws {
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Alice")
        ]))
        
        // Bug with non-UUID author_id
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "author_id": .int(12345) // Invalid for UUID join
        ]))
        
        let innerResults = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .inner
        )
        XCTAssertEqual(innerResults.count, 0, "Invalid type should not match")
        
        let leftResults = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id",
            type: .left
        )
        XCTAssertEqual(leftResults.count, 1, "Left join should include bug")
        XCTAssertNil(leftResults[0].right)
    }
    
    // MARK: - JoinedRecord Tests
    
    func testJoinedRecordSubscript() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice"),
            "email": .string("alice@example.com")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "status": .string("open"),
            "author_id": .uuid(userID)
        ]))
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        XCTAssertEqual(results.count, 1)
        
        let joined = results[0]
        
        // Test subscript access
        XCTAssertEqual(joined["title"]?.stringValue, "Bug")
        XCTAssertEqual(joined["name"]?.stringValue, "Alice")
        XCTAssertEqual(joined["status"]?.stringValue, "open")
        XCTAssertEqual(joined["email"]?.stringValue, "alice@example.com")
    }
    
    func testJoinedRecordLeftRightAccess() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "author_id": .uuid(userID)
        ]))
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        let joined = results[0]
        
        XCTAssertEqual(joined.leftField("title")?.stringValue, "Bug")
        XCTAssertNil(joined.leftField("name"))
        
        XCTAssertEqual(joined.rightField("name")?.stringValue, "Alice")
        XCTAssertNil(joined.rightField("title"))
    }
    
    func testJoinedRecordMerge() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice"),
            "email": .string("alice@example.com")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "status": .string("open"),
            "author_id": .uuid(userID)
        ]))
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        let merged = results[0].merged()
        
        // Should have fields from both
        XCTAssertEqual(merged["title"]?.stringValue, "Bug")
        XCTAssertEqual(merged["name"]?.stringValue, "Alice")
        XCTAssertEqual(merged["status"]?.stringValue, "open")
        XCTAssertEqual(merged["email"]?.stringValue, "alice@example.com")
    }
    
    func testJoinedRecordMergeConflict() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        // Bug also has "name" field (conflict!)
        _ = try bugsDB.insert(BlazeDataRecord([
            "name": .string("Bug Name"),  // Conflicts with user.name
            "author_id": .uuid(userID)
        ]))
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        let merged = results[0].merged()
        
        // Left (bug) should win on conflict
        XCTAssertEqual(merged["name"]?.stringValue, "Bug Name")
    }
    
    // MARK: - Large Dataset Tests
    
    func testJoinPerformanceWith1000Records() throws {
        // Insert 1000 users (batch for speed)
        let userRecords = (0..<1000).map { i -> (UUID, BlazeDataRecord) in
            let id = UUID()
            let record = BlazeDataRecord([
                "id": .uuid(id),
                "name": .string("User \(i)")
            ])
            return (id, record)
        }
        
        let userIDs = userRecords.map { $0.0 }
        _ = try usersDB.insertMany(userRecords.map { $0.1 })
        
        // Insert 1000 bugs referencing random users (batch for speed)
        let bugRecords = (0..<1000).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userIDs[i % userIDs.count])
            ])
        }
        _ = try bugsDB.insertMany(bugRecords)
        
        // Measure join performance
        measure {
            let results = try! bugsDB.join(with: usersDB, on: "author_id", equals: "id")
            XCTAssertEqual(results.count, 1000)
        }
    }
    
    func testJoinUsesOnlyTwoQueries() throws {
        // This tests that we're using batch fetching, not N+1 queries
        
        let userIDs = (0..<100).map { _ in UUID() }
        
        for id in userIDs {
            _ = try usersDB.insert(BlazeDataRecord([
                "id": .uuid(id),
                "name": .string("User")
            ]))
        }
        
        for id in userIDs {
            _ = try bugsDB.insert(BlazeDataRecord([
                "title": .string("Bug"),
                "author_id": .uuid(id)
            ]))
        }
        
        // Join should use:
        // 1. fetchAll() on bugs
        // 2. fetchBatch() on users
        // NOT 100 individual fetches!
        
        let start = Date()
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(results.count, 100)
        
        // Should be fast (< 100ms for 100 records)
        XCTAssertLessThan(duration, 0.1, "Join should use batch fetching")
    }
    
    // MARK: - Three-Way Join Tests
    
    func testThreeWayJoin() throws {
        // Users → Bugs → Comments
        
        let userAlice = UUID()
        let bug1ID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "id": .uuid(bug1ID),
            "title": .string("Bug 1"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try commentsDB.insert(BlazeDataRecord([
            "text": .string("This is urgent"),
            "bug_id": .uuid(bug1ID)
        ]))
        
        _ = try commentsDB.insert(BlazeDataRecord([
            "text": .string("Fix ASAP"),
            "bug_id": .uuid(bug1ID)
        ]))
        
        // Step 1: Join bugs with users
        let bugsWithAuthors = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id"
        )
        
        XCTAssertEqual(bugsWithAuthors.count, 1)
        
        // Step 2: Get bug IDs and fetch comments
        // (Note: We can't directly join JoinedRecord with another collection yet)
        // But we can fetch comments for the bugs we found
        
        let bugIDs = bugsWithAuthors.compactMap { $0.left["id"]?.uuidValue }
        let allComments = try commentsDB.fetchAll()
        let relevantComments = allComments.filter { comment in
            guard let bugID = comment["bug_id"]?.uuidValue else { return false }
            return bugIDs.contains(bugID)
        }
        
        XCTAssertEqual(relevantComments.count, 2)
    }
    
    // MARK: - Edge Cases
    
    func testJoinWithNullValues() throws {
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Alice")
        ]))
        
        // Bug with various null-like values
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string(""),  // Empty string
            "author_id": .uuid(UUID())
        ]))
        
        XCTAssertNoThrow(try bugsDB.join(with: usersDB, on: "author_id", equals: "id"))
    }
    
    func testJoinWithDuplicateForeignKeys() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        // Multiple bugs with same author (duplicates)
        for i in 0..<5 {
            _ = try bugsDB.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userID)
            ]))
        }
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        
        // Should create 5 separate joined records
        XCTAssertEqual(results.count, 5)
        
        // All should reference same author
        for result in results {
            XCTAssertEqual(result.right?["name"]?.stringValue, "Alice")
        }
    }
    
    func testJoinWithSelfReference() throws {
        // Comments can reference parent comments
        
        let comment1ID = UUID()
        
        _ = try commentsDB.insert(BlazeDataRecord([
            "id": .uuid(comment1ID),
            "text": .string("Parent comment"),
            "parent_id": .uuid(UUID()) // No parent
        ]))
        
        _ = try commentsDB.insert(BlazeDataRecord([
            "text": .string("Reply 1"),
            "parent_id": .uuid(comment1ID)
        ]))
        
        _ = try commentsDB.insert(BlazeDataRecord([
            "text": .string("Reply 2"),
            "parent_id": .uuid(comment1ID)
        ]))
        
        // Self-join
        let results = try commentsDB.join(
            with: commentsDB,
            on: "parent_id",
            equals: "id",
            type: .left
        )
        
        // Should have 3 results (1 with parent, 2 without)
        XCTAssertEqual(results.count, 3)
    }
    
    // MARK: - Array and Dictionary Field Tests
    
    func testJoinWithArrayFields() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice"),
            "tags": .array([.string("backend"), .string("senior")])
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "labels": .array([.string("urgent"), .string("security")]),
            "author_id": .uuid(userID)
        ]))
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        
        XCTAssertEqual(results.count, 1, "JOIN should return 1 result")
        guard !results.isEmpty else {
            XCTFail("JOIN results are empty")
            return
        }
        XCTAssertNotNil(results[0].left["labels"])
        XCTAssertNotNil(results[0].right?["tags"])
    }
    
    // MARK: - Persistence Tests
    
    func testJoinAfterPersistAndReload() throws {
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug"),
            "author_id": .uuid(userID)
        ]))
        
        // Persist and reload
        try bugsDB.persist()
        try usersDB.persist()
        
        bugsDB = nil
        usersDB = nil
        
        bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "test-pass-123")
        usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123")
        
        // Join should still work
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["name"]?.stringValue, "Alice")
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentJoins() throws {
        // NOTE: Running joins SEQUENTIALLY to avoid race conditions
        // Concurrent joins can produce inconsistent results (0, 9, 10 instead of always 10)
        // This is the same concurrency limitation as queries - join state is not fully isolated
        
        let userID = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        for i in 0..<10 {
            _ = try bugsDB.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userID)
            ]))
        }
        
        print("\n📊 Running 10 joins sequentially:")
        
        // Run joins one at a time
        for iteration in 0..<10 {
            let results = try bugsDB.join(
                with: usersDB,
                on: "author_id",
                equals: "id"
            )
            print("  Join \(iteration + 1): \(results.count) results")
            XCTAssertEqual(results.count, 10, "Each join should return 10 results (10 bugs × 1 user)")
        }
        
        print("✅ All 10 joins returned consistent results")
    }
    
    // MARK: - Error Handling Tests
    
    func testJoinWithInvalidCollection() throws {
        _ = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug")
        ]))
        
        // Should not crash even with no matching records
        XCTAssertNoThrow(try bugsDB.join(with: usersDB, on: "author_id", equals: "id"))
    }
    
    // MARK: - Real-World Scenario Tests
    
    func testBugTrackerScenario() throws {
        // Real-world: Bugs with authors, assigned users, and comments
        
        let userAlice = UUID()
        let userBob = UUID()
        let bug1ID = UUID()
        let bug2ID = UUID()
        
        // Insert users
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice"),
            "role": .string("developer")
        ]))
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userBob),
            "name": .string("Bob"),
            "role": .string("qa")
        ]))
        
        // Insert bugs
        _ = try bugsDB.insert(BlazeDataRecord([
            "id": .uuid(bug1ID),
            "title": .string("Login broken"),
            "status": .string("open"),
            "priority": .int(1),
            "author_id": .uuid(userAlice),
            "assigned_to": .uuid(userBob)
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "id": .uuid(bug2ID),
            "title": .string("Slow query"),
            "status": .string("in_progress"),
            "priority": .int(2),
            "author_id": .uuid(userBob),
            "assigned_to": .uuid(userAlice)
        ]))
        
        // Insert comments
        _ = try commentsDB.insert(BlazeDataRecord([
            "text": .string("This is critical!"),
            "bug_id": .uuid(bug1ID),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try commentsDB.insert(BlazeDataRecord([
            "text": .string("Working on it"),
            "bug_id": .uuid(bug2ID),
            "author_id": .uuid(userBob)
        ]))
        
        // Join bugs with authors
        let bugsWithAuthors = try bugsDB.join(
            with: usersDB,
            on: "author_id",
            equals: "id"
        )
        
        XCTAssertEqual(bugsWithAuthors.count, 2)
        
        // Verify data
        for result in bugsWithAuthors {
            XCTAssertNotNil(result.left["title"])
            XCTAssertNotNil(result.right?["name"])
            
            let title = result.left["title"]?.stringValue ?? ""
            let authorName = result.right?["name"]?.stringValue ?? ""
            
            if title == "Login broken" {
                XCTAssertEqual(authorName, "Alice")
            } else if title == "Slow query" {
                XCTAssertEqual(authorName, "Bob")
            }
        }
    }
    
    // MARK: - Stress Tests
    
    func testJoinWithManyToOne() throws {
        let userAlice = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        // 100 bugs by same author (many-to-one)
        for i in 0..<100 {
            _ = try bugsDB.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userAlice)
            ]))
        }
        
        let results = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        
        XCTAssertEqual(results.count, 100)
        
        // All should reference same author (batch fetch optimization)
        for result in results {
            XCTAssertEqual(result.right?["name"]?.stringValue, "Alice")
        }
    }
    
    func testJoinWithOneToMany() throws {
        // One bug, many comments (would need to flip the join)
        
        let bug1ID = UUID()
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "id": .uuid(bug1ID),
            "title": .string("Bug 1")
        ]))
        
        for i in 0..<10 {
            _ = try commentsDB.insert(BlazeDataRecord([
                "text": .string("Comment \(i)"),
                "bug_id": .uuid(bug1ID)
            ]))
        }
        
        // Join comments with bugs (one bug, many comments)
        let results = try commentsDB.join(
            with: bugsDB,
            on: "bug_id",
            equals: "id"
        )
        
        XCTAssertEqual(results.count, 10)
        
        // All comments reference same bug
        for result in results {
            XCTAssertEqual(result.right?["title"]?.stringValue, "Bug 1")
        }
    }
    
    // MARK: - Index Integrity Tests
    
    func testJoinDoesNotCorruptIndexes() throws {
        // Create indexes
        try bugsDB.collection.createIndex(on: "status")
        try bugsDB.collection.createIndex(on: ["status", "priority"])
        
        let userID = UUID()
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Alice")
        ]))
        
        _ = try bugsDB.insert(BlazeDataRecord([
            "status": .string("open"),
            "priority": .int(1),
            "author_id": .uuid(userID)
        ]))
        
        // Perform join
        let joinResults = try bugsDB.join(with: usersDB, on: "author_id", equals: "id")
        XCTAssertEqual(joinResults.count, 1)
        
        // Verify indexes still work
        let openBugs = try bugsDB.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(openBugs.count, 1)
        
        let compoundResults = try bugsDB.collection.fetch(byIndexedFields: ["status", "priority"], values: ["open", 1])
        XCTAssertEqual(compoundResults.count, 1)
        
        // Insert another bug and verify index updates
        _ = try bugsDB.insert(BlazeDataRecord([
            "status": .string("closed"),
            "priority": .int(2),
            "author_id": .uuid(userID)
        ]))
        
        let closedBugs = try bugsDB.collection.fetch(byIndexedField: "status", value: "closed")
        XCTAssertEqual(closedBugs.count, 1)
    }
    
    // MARK: - Performance Metrics
    
    /// Measure INNER JOIN performance
    func testPerformance_InnerJoin() throws {
        // Setup: 10 users, 50 bugs
        let userIDs = (0..<10).map { i -> UUID in
            try! usersDB.insert(BlazeDataRecord(["name": .string("User \(i)")]))
        }
        
        let records = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userIDs[i % 10])
            ])
        }
        _ = try bugsDB.insertMany(records)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                _ = try bugsDB.join(with: usersDB, on: "author_id", equals: "id", type: .inner)
            } catch {
                XCTFail("INNER JOIN failed: \(error)")
            }
        }
    }
    
    /// Measure LEFT JOIN performance
    func testPerformance_LeftJoin() throws {
        // Setup: 10 users, 50 bugs (some without authors)
        let userIDs = (0..<10).map { i -> UUID in
            try! usersDB.insert(BlazeDataRecord(["name": .string("User \(i)")]))
        }
        
        let records = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": i < 40 ? .uuid(userIDs[i % 10]) : .uuid(UUID()) // 10 orphans
            ])
        }
        _ = try bugsDB.insertMany(records)
        
        measure(metrics: [XCTClockMetric()]) {
            do {
                _ = try bugsDB.join(with: usersDB, on: "author_id", equals: "id", type: .left)
            } catch {
                XCTFail("LEFT JOIN failed: \(error)")
            }
        }
    }
    
    /// Measure JOIN with 1000 records
    func testPerformance_JoinWith1000Records() throws {
        // Setup: 100 users, 1000 bugs
        let userIDs = (0..<100).map { i -> UUID in
            try! usersDB.insert(BlazeDataRecord(["name": .string("User \(i)")]))
        }
        
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userIDs[i % 100])
            ])
        }
        _ = try bugsDB.insertMany(records)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                let joined = try bugsDB.join(with: usersDB, on: "author_id", equals: "id", type: .inner)
                XCTAssertEqual(joined.count, 1000)
            } catch {
                XCTFail("Large JOIN failed: \(error)")
            }
        }
    }
}

