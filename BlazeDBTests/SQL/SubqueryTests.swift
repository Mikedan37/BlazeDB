//  SubqueryTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for subquery functionality

import XCTest
@testable import BlazeDBCore

final class SubqueryTests: XCTestCase {
    
    var tempURL: URL!
    var usersURL: URL!
    var db: BlazeDBClient!
    var usersDB: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bugs-\(UUID().uuidString).blazedb")
        usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "bugs", fileURL: tempURL, password: "test-pass-123")
        usersDB = try! BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        db = nil
        usersDB = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: usersURL)
        try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Basic Subquery
    
    func testSubqueryInWhereClause() throws {
        // Create users
        let alice = UUID()
        let bob = UUID()
        let charlie = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(alice), "name": .string("Alice"), "role": .string("senior")]))
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(bob), "name": .string("Bob"), "role": .string("junior")]))
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(charlie), "name": .string("Charlie"), "role": .string("senior")]))
        
        // Create bugs
        for i in 0..<20 {
            let author = [alice, bob, charlie][i % 3]
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(author)
            ]))
        }
        
        // Subquery: Get IDs of senior developers
        let seniorDevs = usersDB.query()
            .where("role", equals: .string("senior"))
            .asSubquery(extracting: "id")
        
        // Main query: Get bugs by senior devs
        let results = try db.query()
            .where("author_id", inSubquery: seniorDevs)
            .execute()
        
        // Should be ~13 bugs (alice + charlie's bugs)
        XCTAssertGreaterThan(results.count, 10)
        XCTAssertLessThan(results.count, 15)
    }
    
    func testSubqueryWithFiltering() throws {
        // Setup data
        let alice = UUID()
        let bob = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(alice), "active": .bool(true)]))
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(bob), "active": .bool(false)]))
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(i % 2 == 0 ? alice : bob),
                "priority": .int(i % 5 + 1)
            ]))
        }
        
        // Subquery: Active users
        let activeUsers = usersDB.query()
            .where("active", equals: .bool(true))
            .asSubquery(extracting: "id")
        
        // Main query: High-priority bugs by active users
        let results = try db.query()
            .where("priority", greaterThan: .int(3))
            .where("author_id", inSubquery: activeUsers)
            .execute()
        
        // Should only get Alice's high-priority bugs
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0)
        for result in records {
            XCTAssertEqual(result.storage["author_id"]?.uuidValue, alice)
        }
    }
    
    func testSubqueryReturnsEmpty() throws {
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(UUID()), "role": .string("admin")]))
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["title": .string("Bug \(i)"), "author_id": .uuid(UUID())]))
        }
        
        // Subquery returns no results
        let seniorDevs = usersDB.query()
            .where("role", equals: .string("nonexistent"))
            .asSubquery(extracting: "id")
        
        let results = try db.query()
            .where("author_id", inSubquery: seniorDevs)
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSubqueryNotIn() throws {
        let alice = UUID()
        let bob = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(alice), "role": .string("senior")]))
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(bob), "role": .string("junior")]))
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(i % 2 == 0 ? alice : bob)
            ]))
        }
        
        // Get bugs NOT by senior devs
        let seniorDevs = usersDB.query()
            .where("role", equals: .string("senior"))
            .asSubquery(extracting: "id")
        
        let results = try db.query()
            .where("author_id", notInSubquery: seniorDevs)
            .execute()
        
        // Should be Bob's bugs only
        let records = try results.records
        XCTAssertEqual(records.count, 5)
        for result in records {
            XCTAssertEqual(result.storage["author_id"]?.uuidValue, bob)
        }
    }
    
    // MARK: - Complex Subqueries
    
    func testNestedFiltersInSubquery() throws {
        let alice = UUID()
        let bob = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(alice),
            "name": .string("Alice"),
            "role": .string("senior"),
            "active": .bool(true)
        ]))
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(bob),
            "name": .string("Bob"),
            "role": .string("senior"),
            "active": .bool(false)
        ]))
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "author_id": .uuid(i % 2 == 0 ? alice : bob)
            ]))
        }
        
        // Subquery with multiple filters
        let activeSeniors = usersDB.query()
            .where("role", equals: .string("senior"))
            .where("active", equals: .bool(true))
            .asSubquery(extracting: "id")
        
        let results = try db.query()
            .where("author_id", inSubquery: activeSeniors)
            .execute()
        
        XCTAssertEqual(results.count, 5)  // Only Alice's bugs
    }
    
    func testSubqueryWithNonIDField() throws {
        _ = try usersDB.insert(BlazeDataRecord(["name": .string("Alice"), "email": .string("alice@example.com")]))
        _ = try usersDB.insert(BlazeDataRecord(["name": .string("Bob"), "email": .string("bob@example.com")]))
        
        _ = try db.insert(BlazeDataRecord(["assignee_email": .string("alice@example.com")]))
        _ = try db.insert(BlazeDataRecord(["assignee_email": .string("charlie@example.com")]))
        
        // Subquery extracts emails
        let userEmails = usersDB.query()
            .asSubquery(extracting: "email")
        
        let results = try db.query()
            .where("assignee_email", inSubquery: userEmails)
            .execute()
        
        XCTAssertEqual(results.count, 1)  // Only Alice's email matches
    }
    
    // MARK: - Performance
    
    func testSubqueryPerformance() throws {
        // Insert 100 users (20 senior, 80 junior) - capture their IDs
        var seniorIDs: [UUID] = []
        var allUserIDs: [UUID] = []
        
        for i in 0..<100 {
            let role = i < 20 ? "senior" : "junior"
            let userID = try usersDB.insert(BlazeDataRecord([
                "role": .string(role)
            ]))
            allUserIDs.append(userID)
            if role == "senior" {
                seniorIDs.append(userID)
            }
        }
        
        // Insert 1000 bugs (batch insert for speed)
        let bugRecords = (0..<1000).map { i in
            BlazeDataRecord([
                "author_id": .uuid(allUserIDs[i % allUserIDs.count])
            ])
        }
        _ = try db.insertMany(bugRecords)
        
        // Now test the subquery performance
        print("📊 Subquery test data:")
        print("  Total users: \(allUserIDs.count)")
        print("  Senior users: \(seniorIDs.count)")
        print("  First 3 senior IDs: \(seniorIDs.prefix(3))")
        
        let start = Date()
        let seniorDevs = usersDB.query()
            .where("role", equals: .string("senior"))
            .asSubquery(extracting: "id")  // Extract record ID, not custom "user_id"
        
        // Debug: Check what the subquery returns
        let seniorUsers = try usersDB.query()
            .where("role", equals: .string("senior"))
            .execute()
            .records
        print("  Subquery found \(seniorUsers.count) senior users")
        let extractedIDs = seniorUsers.compactMap { $0.storage["id"]?.uuidValue }
        print("  Extracted \(extractedIDs.count) IDs from subquery")
        print("  First 3 extracted: \(extractedIDs.prefix(3))")
        
        let results = try db.query()
            .where("author_id", inSubquery: seniorDevs)
            .execute()
        let duration = Date().timeIntervalSince(start)
        
        print("  Final results: \(results.count) bugs")
        
        XCTAssertGreaterThan(results.count, 0, "Should find bugs by senior devs")
        XCTAssertLessThan(duration, 0.5, "Subquery should be fast")
    }
    
    // MARK: - Edge Cases
    
    func testSubqueryWithEmptyResult() throws {
        _ = try usersDB.insert(BlazeDataRecord(["role": .string("admin")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug")]))
        
        let seniorDevs = usersDB.query()
            .where("role", equals: .string("senior"))
            .asSubquery(extracting: "id")
        
        let results = try db.query()
            .where("author_id", inSubquery: seniorDevs)
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSubqueryWithMissingField() throws {
        _ = try usersDB.insert(BlazeDataRecord(["name": .string("Alice")]))  // No "id"
        _ = try db.insert(BlazeDataRecord(["author_id": .uuid(UUID())]))
        
        let subquery = usersDB.query()
            .asSubquery(extracting: "nonexistent")
        
        let results = try db.query()
            .where("author_id", inSubquery: subquery)
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - Real-World Scenarios
    
    func testBugsByActiveTeamMembers() throws {
        // Teams
        let team1 = UUID()
        let team2 = UUID()
        
        // Users
        let users = [
            (UUID(), team1, true),
            (UUID(), team1, false),
            (UUID(), team2, true),
            (UUID(), team2, false)
        ]
        
        for (id, teamID, active) in users {
            _ = try usersDB.insert(BlazeDataRecord([
                "id": .uuid(id),
                "team_id": .uuid(teamID),
                "active": .bool(active)
            ]))
        }
        
        // Bugs
        for i in 0..<40 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(users[i % 4].0)
            ]))
        }
        
        // Get bugs by active team1 members
        let activeTeam1Users = usersDB.query()
            .where("team_id", equals: .uuid(team1))
            .where("active", equals: .bool(true))
            .asSubquery(extracting: "id")
        
        let results = try db.query()
            .where("author_id", inSubquery: activeTeam1Users)
            .execute()
        
        XCTAssertEqual(results.count, 10)  // 1/4 of users match
    }
}

