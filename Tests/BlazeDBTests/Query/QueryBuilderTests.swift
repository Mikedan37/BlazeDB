//  QueryBuilderTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for Query Builder

import XCTest
@testable import BlazeDB

final class QueryBuilderTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QB-\(testID).blazedb")
        
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "query_test_\(testID)", fileURL: tempURL, password: "QueryBuilderTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? db?.persist()
        db = nil
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - WHERE Clause Tests
    
    func testWhereEquals() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "title": .string("Bug 1")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed"), "title": .string("Bug 2")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "title": .string("Bug 3")]))
        
        let results = try db.query()
            .where("status", equals: .string("open"))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 2)
        for result in records {
            XCTAssertEqual(result.storage["status"]?.stringValue, "open")
        }
    }
    
    func testWhereNotEquals() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        let results = try db.query()
            .where("status", notEquals: .string("closed"))
            .execute()
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testWhereGreaterThan() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10)]))
        
        let results = try db.query()
            .where("priority", greaterThan: .int(4))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 2)
        for result in records {
            XCTAssertGreaterThan(result.storage["priority"]?.intValue ?? 0, 4)
        }
    }
    
    func testWhereLessThan() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10)]))
        
        let results = try db.query()
            .where("priority", lessThan: .int(6))
            .execute()
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testWhereGreaterThanOrEqual() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10)]))
        
        let results = try db.query()
            .where("priority", greaterThanOrEqual: .int(5))
            .execute()
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testWhereLessThanOrEqual() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10)]))
        
        let results = try db.query()
            .where("priority", lessThanOrEqual: .int(5))
            .execute()
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testWhereContains() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Login broken")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Slow query")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login timeout")]))
        
        let results = try db.query()
            .where("title", contains: "Login")
            .execute()
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testWhereIn() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("in_progress")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        let results = try db.query()
            .where("status", in: [.string("open"), .string("in_progress")])
            .execute()
        
        XCTAssertEqual(results.count, 3)
    }
    
    func testWhereNil() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Has title")]))
        _ = try db.insert(BlazeDataRecord(["other": .string("No title")]))
        
        let results = try db.query()
            .whereNil("title")
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testWhereNotNil() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Has title")]))
        _ = try db.insert(BlazeDataRecord(["other": .string("No title")]))
        
        let results = try db.query()
            .whereNotNil("title")
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testWhereCustomClosure() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(1), "status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(5), "status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10), "status": .string("closed")]))
        
        let results = try db.query()
            .where { record in
                let priority = record["priority"]?.intValue ?? 0
                let status = record["status"]?.stringValue ?? ""
                return priority > 3 && status == "open"
            }
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1, "Should return 1 record")
        guard !records.isEmpty else {
            XCTFail("Query returned no records")
            return
        }
        XCTAssertEqual(records[0].storage["priority"]?.intValue, 5)
    }
    
    // MARK: - Multiple WHERE Clauses
    
    func testMultipleWhereClausesAND() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["status": .string("closed"), "priority": .int(5)]))
        
        let results = try db.query()
            .where("status", equals: .string("open"))
            .where("priority", greaterThan: .int(3))
            .execute()
        
        // Both conditions must be true (AND logic)
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].storage["priority"]?.intValue, 5)
    }
    
    func testChainedFilters() throws {
        for i in 1...20 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "priority": .int(i),
                "severity": .string(i % 3 == 0 ? "high" : "low")
            ]))
        }
        
        let results = try db.query()
            .where("status", equals: .string("open"))
            .where("priority", greaterThan: .int(10))
            .where("severity", equals: .string("high"))
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0)
        for result in records {
            XCTAssertEqual(result["status"]?.stringValue, "open")
            XCTAssertGreaterThan(result["priority"]?.intValue ?? 0, 10)
            XCTAssertEqual(result["severity"]?.stringValue, "high")
        }
    }
    
    // MARK: - ORDER BY Tests
    
    func testOrderByAscending() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10)]))
        
        let results = try db.query()
            .orderBy("priority", descending: false)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["priority"]?.intValue, 1)
        XCTAssertEqual(records[1].storage["priority"]?.intValue, 5)
        XCTAssertEqual(records[2].storage["priority"]?.intValue, 10)
    }
    
    func testOrderByDescending() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(10)]))
        
        let results = try db.query()
            .orderBy("priority", descending: true)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["priority"]?.intValue, 10)
        XCTAssertEqual(records[1].storage["priority"]?.intValue, 5)
        XCTAssertEqual(records[2].storage["priority"]?.intValue, 1)
    }
    
    func testOrderByString() throws {
        _ = try db.insert(BlazeDataRecord(["name": .string("Charlie")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("Alice")]))
        _ = try db.insert(BlazeDataRecord(["name": .string("Bob")]))
        
        let results = try db.query()
            .orderBy("name", descending: false)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "Alice")
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Bob")
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "Charlie")
    }
    
    func testOrderByDate() throws {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)
        
        _ = try db.insert(BlazeDataRecord(["created_at": .date(date2)]))
        _ = try db.insert(BlazeDataRecord(["created_at": .date(date1)]))
        _ = try db.insert(BlazeDataRecord(["created_at": .date(date3)]))
        
        let results = try db.query()
            .orderBy("created_at", descending: true)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records[0].storage["created_at"]?.dateValue, date3)
        XCTAssertEqual(records[1].storage["created_at"]?.dateValue, date2)
        XCTAssertEqual(records[2].storage["created_at"]?.dateValue, date1)
    }
    
    func testMultipleOrderBy() throws {
        // Same priority, different names
        _ = try db.insert(BlazeDataRecord(["priority": .int(1), "name": .string("Charlie")]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(1), "name": .string("Alice")]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(2), "name": .string("Bob")]))
        
        let results = try db.query()
            .orderBy("priority", descending: false)
            .orderBy("name", descending: false)
            .execute()
        
        // Should sort by priority first, then name
        let records = try results.records
        XCTAssertEqual(records[0].storage["name"]?.stringValue, "Alice") // priority 1, name A
        XCTAssertEqual(records[1].storage["name"]?.stringValue, "Charlie") // priority 1, name C
        XCTAssertEqual(records[2].storage["name"]?.stringValue, "Bob") // priority 2
    }
    
    // MARK: - LIMIT & OFFSET Tests
    
    func testLimit() throws {
        for i in 1...10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let results = try db.query()
            .limit(5)
            .execute()
        
        XCTAssertEqual(results.count, 5)
    }
    
    func testOffset() throws {
        for i in 1...10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let results = try db.query()
            .orderBy("index", descending: false)
            .offset(5)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 5)
        XCTAssertEqual(records[0].storage["index"]?.intValue, 6)
    }
    
    func testLimitAndOffset() throws {
        for i in 1...20 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Page 2: Skip 10, take 10
        let results = try db.query()
            .orderBy("index", descending: false)
            .offset(10)
            .limit(10)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 10)
        XCTAssertEqual(records[0].storage["index"]?.intValue, 11)
        XCTAssertEqual(records[9].storage["index"]?.intValue, 20)
    }
    
    // MARK: - Combined Tests
    
    func testWhereOrderLimit() throws {
        for i in 1...20 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "priority": .int(i)
            ]))
        }
        
        let results = try db.query()
            .where("status", equals: .string("open"))
            .orderBy("priority", descending: true)
            .limit(3)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].storage["priority"]?.intValue, 20)
        XCTAssertEqual(records[1].storage["priority"]?.intValue, 18)
        XCTAssertEqual(records[2].storage["priority"]?.intValue, 16)
    }
    
    func testComplexQuery() throws {
        let now = Date()
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "status": .string("open"),
            "priority": .int(1),
            "created_at": .date(Date(timeIntervalSince1970: 1000))
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "status": .string("open"),
            "priority": .int(5),
            "created_at": .date(Date(timeIntervalSince1970: 2000))
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 3"),
            "status": .string("closed"),
            "priority": .int(10),
            "created_at": .date(Date(timeIntervalSince1970: 3000))
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 4"),
            "status": .string("open"),
            "priority": .int(10),
            "created_at": .date(Date(timeIntervalSince1970: 4000))
        ]))
        
        let results = try db.query()
            .where("status", equals: .string("open"))
            .where("priority", greaterThan: .int(3))
            .where("title", contains: "Bug")
            .orderBy("created_at", descending: true)
            .limit(5)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 2) // Bug 2 and Bug 4
        XCTAssertEqual(records[0].storage["title"]?.stringValue, "Bug 4") // Most recent
        XCTAssertEqual(records[1].storage["title"]?.stringValue, "Bug 2")
    }
    
    // MARK: - JOIN Integration Tests
    
    func testQueryBuilderWithJoin() throws {
        // Setup second database
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users0-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryBuilderTest123!")
        
        let userAlice = UUID()
        let userBob = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice"),
            "role": .string("senior")
        ]))
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userBob),
            "name": .string("Bob"),
            "role": .string("junior")
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "status": .string("open"),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "status": .string("closed"),
            "author_id": .uuid(userBob)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug 3"),
            "status": .string("open"),
            "author_id": .uuid(userAlice)
        ]))
        
        // Query: Open bugs by senior developers
        let results = try db.query()
            .where("status", equals: .string("open"))
            .join(usersDB.collection, on: "author_id", equals: "id")
            .executeJoin()
        
        // Filter by author role (done after join for now)
        let seniorBugs = results.filter {
            $0.right?["role"]?.stringValue == "senior"
        }
        
        XCTAssertEqual(seniorBugs.count, 2) // Both Bug 1 and Bug 3
        for result in seniorBugs {
            XCTAssertEqual(result.left["status"]?.stringValue, "open")
            XCTAssertEqual(result.right?["name"]?.stringValue, "Alice")
        }
    }
    
    func testQueryBuilderJoinWithOrder() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users2-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryBuilderTest123!")
        
        let userAlice = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug C"),
            "priority": .int(1),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug A"),
            "priority": .int(3),
            "author_id": .uuid(userAlice)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug B"),
            "priority": .int(2),
            "author_id": .uuid(userAlice)
        ]))
        
        let results = try db.query()
            .join(usersDB.collection, on: "author_id")
            .orderBy("priority", descending: true)
            .executeJoin()
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].left["title"]?.stringValue, "Bug A") // priority 3
        XCTAssertEqual(results[1].left["title"]?.stringValue, "Bug B") // priority 2
        XCTAssertEqual(results[2].left["title"]?.stringValue, "Bug C") // priority 1
    }
    
    func testQueryBuilderJoinWithLimit() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users3-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryBuilderTest123!")
        
        let userAlice = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord([
            "id": .uuid(userAlice),
            "name": .string("Alice")
        ]))
        
        for i in 1...10 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "author_id": .uuid(userAlice)
            ]))
        }
        
        let results = try db.query()
            .join(usersDB.collection, on: "author_id")
            .limit(5)
            .executeJoin()
        
        XCTAssertEqual(results.count, 5)
    }
    
    // MARK: - Performance Tests
    
    func testQueryBuilderFilterBeforeJoinOptimization() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users4-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryBuilderTest123!")
        
        let userAlice = UUID()
        let userBob = UUID()
        
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(userAlice), "name": .string("Alice")]))
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(userBob), "name": .string("Bob")]))
        
        // Insert 1000 bugs (only 100 are "open")
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i < 100 ? "open" : "closed"),
                "author_id": .uuid(i % 2 == 0 ? userAlice : userBob)
            ]))
        }
        
        // Filter before join (only loads 100 bugs + users, not 1000)
        let start = Date()
        let results = try db.query()
            .where("status", equals: .string("open"))
            .join(usersDB.collection, on: "author_id")
            .executeJoin()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(results.count, 100)
        
        // Should be fast (filtering reduces data before join)
        print("Query builder + JOIN filtered 1000 → 100 records in \(String(format: "%.2f", duration * 1000))ms")
    }
    
    func testQueryBuilderPerformance() throws {
        // Insert 1000 records
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i % 3 == 0 ? "open" : "closed"),
                "priority": .int(i % 10),
                "title": .string("Bug \(i)")
            ]))
        }
        
        measure {
            let results = try! db.query()
                .where("status", equals: .string("open"))
                .where("priority", greaterThan: .int(5))
                .orderBy("priority", descending: true)
                .limit(20)
                .execute()
            
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyQuery() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug")]))
        
        let results = try db.query()
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testQueryWithNoMatches() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        let results = try db.query()
            .where("status", equals: .string("nonexistent"))
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testQueryOnEmptyDatabase() throws {
        let results = try db.query()
            .where("status", equals: .string("open"))
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testOrderByWithNilValues() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(5), "title": .string("Has priority")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("No priority")]))
        _ = try db.insert(BlazeDataRecord(["priority": .int(1), "title": .string("Has priority 2")]))
        
        let results = try db.query()
            .orderBy("priority", descending: false)
            .execute()
        
        let records = try results.records
        // Records with values should come first, nil last
        XCTAssertNotNil(records[0].storage["priority"])
        XCTAssertNotNil(records[1].storage["priority"])
        XCTAssertNil(records[2].storage["priority"])
    }
    
    // MARK: - Real-World Scenarios
    
    func testBugTrackerQuery() throws {
        let now = Date()
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Critical bug"),
            "status": .string("open"),
            "priority": .int(1),
            "severity": .string("high"),
            "created_at": .date(now)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Minor bug"),
            "status": .string("open"),
            "priority": .int(5),
            "severity": .string("low"),
            "created_at": .date(Date(timeIntervalSinceNow: -3600))
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Old bug"),
            "status": .string("closed"),
            "priority": .int(3),
            "severity": .string("medium"),
            "created_at": .date(Date(timeIntervalSinceNow: -86400))
        ]))
        
        // Query: Open bugs with high severity, by recency
        let results = try db.query()
            .where("status", equals: .string("open"))
            .where("severity", equals: .string("high"))
            .orderBy("created_at", descending: true)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].storage["title"]?.stringValue, "Critical bug")
    }
    
    func testTopNQuery() throws {
        // Insert 100 bugs with various priorities
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "priority": .int(i % 10),
                "created_at": .date(Date(timeIntervalSince1970: Double(i * 1000)))
            ]))
        }
        
        // Get top 10 highest priority bugs
        let results = try db.query()
            .orderBy("priority", descending: true)
            .limit(10)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 10)
        
        // All should have high priority
        for result in records {
            let priority = result.storage["priority"]?.intValue ?? 0
            XCTAssertGreaterThanOrEqual(priority, 9)
        }
    }
    
    func testPaginationWithQueryBuilder() throws {
        for i in 1...50 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string("open")
            ]))
        }
        
        // Page 1
        let page1 = try db.query()
            .where("status", equals: .string("open"))
            .orderBy("index", descending: false)
            .limit(10)
            .offset(0)
            .execute()
        
        let page1Records = try page1.records
        XCTAssertEqual(page1Records.count, 10)
        XCTAssertEqual(page1Records[0].storage["index"]?.intValue, 1)
        
        // Page 2
        let page2 = try db.query()
            .where("status", equals: .string("open"))
            .orderBy("index", descending: false)
            .limit(10)
            .offset(10)
            .execute()
        
        let page2Records = try page2.records
        XCTAssertEqual(page2Records.count, 10)
        XCTAssertEqual(page2Records[0].storage["index"]?.intValue, 11)
    }
    
    // MARK: - Type Comparison Tests
    
    func testCompareIntegers() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(20)]))
        
        let gt = try db.query().where("value", greaterThan: .int(15)).execute()
        XCTAssertEqual(gt.count, 1)
        
        let lt = try db.query().where("value", lessThan: .int(15)).execute()
        XCTAssertEqual(lt.count, 1)
    }
    
    func testCompareDoubles() throws {
        _ = try db.insert(BlazeDataRecord(["value": .double(10.5)]))
        _ = try db.insert(BlazeDataRecord(["value": .double(20.5)]))
        
        let gt = try db.query().where("value", greaterThan: .double(15.0)).execute()
        XCTAssertEqual(gt.count, 1)
    }
    
    func testCompareMixedNumericTypes() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .double(20.5)]))
        
        // Should handle int vs double comparison
        let results = try db.query().where("value", greaterThan: .double(15.0)).execute()
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Chainability Tests
    
    func testChainableAPI() throws {
        for i in 1...20 {
            _ = try db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "priority": .int(i),
                "title": .string("Bug \(i)")
            ]))
        }
        
        // This should all chain smoothly
        let results = try db
            .query()
            .where("status", equals: .string("open"))
            .where("priority", greaterThan: .int(10))
            .orderBy("priority", descending: true)
            .limit(3)
            .execute()
        
        XCTAssertEqual(results.count, 3)
    }
    
    // MARK: - Dynamic Schema Tests
    
    func testQueryBuilderWithDifferentDocumentTypes() throws {
        _ = try db.insert(BlazeDataRecord([
            "type": .string("bug"),
            "title": .string("Bug 1"),
            "severity": .string("high")
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "type": .string("feature"),
            "title": .string("Feature 1"),
            "estimated_hours": .int(40)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "type": .string("bug"),
            "title": .string("Bug 2"),
            "severity": .string("low")
        ]))
        
        // Filter by document type
        let bugs = try db.query()
            .where("type", equals: .string("bug"))
            .execute()
        
        XCTAssertEqual(bugs.count, 2)
        
        // Filter bugs by severity
        let highSeverity = try db.query()
            .where("type", equals: .string("bug"))
            .where("severity", equals: .string("high"))
            .execute()
        
        XCTAssertEqual(highSeverity.count, 1)
    }
    
    // MARK: - Performance Metrics
    
    /// Measure simple query performance
    func testPerformance_SimpleQuery() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ])
        }
        _ = try db.insertMany(records)
        
        measure {
            do {
                _ = try db.query()
                    .where("status", equals: .string("active"))
                    .execute()
            } catch {
                XCTFail("Query failed: \(error)")
            }
        }
    }
    
    /// Measure complex query with sorting and limiting
    func testPerformance_ComplexQuery() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "priority": .int(i % 10),
                "status": .string("open")
            ])
        }
        _ = try db.insertMany(records)
        
        measure {
            do {
                _ = try db.query()
                    .where("status", equals: .string("open"))
                    .where("priority", greaterThan: .int(5))
                    .orderBy("priority", descending: true)
                    .limit(20)
                    .execute()
            } catch {
                XCTFail("Complex query failed: \(error)")
            }
        }
    }
}

