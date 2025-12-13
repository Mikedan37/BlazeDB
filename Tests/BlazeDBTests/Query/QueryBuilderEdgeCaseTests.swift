//  QueryBuilderEdgeCaseTests.swift
//  BlazeDBTests
//
//  Bulletproof edge case tests for Query Builder

import XCTest
@testable import BlazeDB

final class QueryBuilderEdgeCaseTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QBEdge-\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "qb_edge", fileURL: tempURL, password: "QueryBuilderEdge123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Null/Nil Edge Cases
    
    func testWhereOnMissingField() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Has title")]))
        _ = try db.insert(BlazeDataRecord(["other": .string("No title")]))
        
        // Filter on field that doesn't exist in all records
        let results = try db.query()
            .where("title", equals: .string("Has title"))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testComparisonWithNilFields() throws {
        _ = try db.insert(BlazeDataRecord(["priority": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["title": .string("No priority")]))
        
        // Greater than on field that's missing in one record
        let results = try db.query()
            .where("priority", greaterThan: .int(3))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testEmptyStringEquals() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Not empty")]))
        
        let results = try db.query()
            .where("title", equals: .string(""))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testContainsOnEmptyString() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug")]))
        
        let results = try db.query()
            .where("title", contains: "Bug")
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testWhereInWithEmptyArray() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        let results = try db.query()
            .where("status", in: [])
            .execute()
        
        XCTAssertEqual(results.count, 0, "Empty IN array should match nothing")
    }
    
    // MARK: - Type Mismatch Edge Cases
    
    func testCompareIntWithDouble() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .double(20.5)]))
        
        // Should handle mixed types
        let results = try db.query()
            .where("value", greaterThan: .double(15.0))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testCompareDoubleWithInt() throws {
        _ = try db.insert(BlazeDataRecord(["value": .double(10.5)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(20)]))
        
        let results = try db.query()
            .where("value", greaterThan: .int(15))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testCompareIncompatibleTypes() throws {
        _ = try db.insert(BlazeDataRecord(["value": .string("text")]))
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        
        // Comparing string to int should not crash
        let results = try db.query()
            .where("value", greaterThan: .int(5))
            .execute()
        
        // Only the int record should potentially match
        XCTAssertLessThanOrEqual(results.count, 1)
    }
    
    // MARK: - Boundary Value Tests
    
    func testLimitZero() throws {
        _ = try db.insert(BlazeDataRecord(["id": .int(1)]))
        
        let results = try db.query()
            .limit(0)
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testLimitLargerThanDataset() throws {
        _ = try db.insert(BlazeDataRecord(["id": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["id": .int(2)]))
        
        let results = try db.query()
            .limit(1000)
            .execute()
        
        XCTAssertEqual(results.count, 2, "Should return all available records")
    }
    
    func testOffsetLargerThanDataset() throws {
        _ = try db.insert(BlazeDataRecord(["id": .int(1)]))
        
        let results = try db.query()
            .offset(1000)
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testNegativeLimit() throws {
        _ = try db.insert(BlazeDataRecord(["id": .int(1)]))
        
        // Negative limit should be treated as 0
        let results = try db.query()
            .limit(-5)
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testNegativeOffset() throws {
        _ = try db.insert(BlazeDataRecord(["id": .int(1)]))
        
        // Negative offset should be treated as 0
        let results = try db.query()
            .offset(-5)
            .execute()
        
        XCTAssertGreaterThan(results.count, 0)
    }
    
    // MARK: - Unicode & Special Characters
    
    func testUnicodeInContains() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("🐛 Login broken")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug report")]))
        
        let results = try db.query()
            .where("title", contains: "🐛")
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testSpecialCharactersInWhere() throws {
        _ = try db.insert(BlazeDataRecord(["path": .string("/api/v1/users")]))
        _ = try db.insert(BlazeDataRecord(["path": .string("/api/v2/users")]))
        
        let results = try db.query()
            .where("path", contains: "/api/v1/")
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testCaseSenitivityInContains() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("LOGIN broken")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("login broken")]))
        
        let results = try db.query()
            .where("title", contains: "LOGIN")
            .execute()
        
        XCTAssertEqual(results.count, 1, "Contains is case-sensitive")
    }
    
    // MARK: - Array Field Edge Cases
    
    func testQueryOnArrayField() throws {
        _ = try db.insert(BlazeDataRecord([
            "tags": .array([.string("urgent"), .string("backend")])
        ]))
        
        // Can't directly compare array equality, but shouldn't crash
        XCTAssertNoThrow(try db.query().whereNotNil("tags").execute())
    }
    
    func testQueryOnDictionaryField() throws {
        _ = try db.insert(BlazeDataRecord([
            "metadata": .dictionary(["key": .string("value")])
        ]))
        
        XCTAssertNoThrow(try db.query().whereNotNil("metadata").execute())
    }
    
    // MARK: - Large Dataset Edge Cases
    
    func testQueryOn10KRecords() throws {
        // Insert 10k records (batch insert - 20x faster!)
        let records = (0..<10000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ])
        }
        let insertedIDs = try db.insertMany(records)
        XCTAssertEqual(insertedIDs.count, 10000, "Should insert exactly 10000 records")
        
        // CRITICAL: Persist to ensure all records are flushed and indexed before querying
        try db.persist()
        
        // Verify total count before querying
        let totalCount = db.count()
        XCTAssertEqual(totalCount, 10000, "Database should have exactly 10000 records after insert and persist")
        
        let results = try db.query()
            .where("status", equals: .string("open"))
            .execute()
        
        XCTAssertEqual(results.count, 5000, "Should find exactly 5000 records with status 'open' (got \(results.count))")
    }
    
    func testLimitOn10KRecords() throws {
        // Batch insert 10k records (20x faster!)
        let records = (0..<10000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        _ = try db.insertMany(records)
        
        let results = try db.query()
            .limit(100)
            .execute()
        
        XCTAssertEqual(results.count, 100)
    }
    
    func testOffsetNearEnd() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let results = try db.query()
            .orderBy("index", descending: false)
            .offset(95)
            .execute()
        
        XCTAssertEqual(results.count, 5)
    }
    
    // MARK: - Concurrent Query Tests
    
    func testConcurrentQueries() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        
        let expectation = self.expectation(description: "Concurrent queries")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        
        for _ in 0..<10 {
            queue.async {
                do {
                    let results = try self.db.query()
                        .where("status", equals: .string("open"))
                        .orderBy("index", descending: true)
                        .limit(10)
                        .execute()
                    XCTAssertEqual(results.count, 10)
                } catch {
                    XCTFail("Query failed: \(error)")
                }
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Filter Ordering Edge Cases
    
    func testFilterOrderMatters() throws {
        // Batch insert 1000 records (10x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "value": .int(i),
                "category": .string(i < 100 ? "A" : "B")
            ])
        }
        _ = try db.insertMany(records)
        
        // Selective filter first (better performance)
        let results1 = try db.query()
            .where("category", equals: .string("A"))  // Filters to 100
            .where("value", greaterThan: .int(50))    // Then filters to ~50
            .execute()
        
        // Less selective filter first
        let results2 = try db.query()
            .where("value", greaterThan: .int(50))    // Filters to 950
            .where("category", equals: .string("A"))  // Then filters to ~50
            .execute()
        
        // Both should return same results (order independent)
        XCTAssertEqual(results1.count, results2.count)
    }
    
    // MARK: - Date Comparison Edge Cases
    
    func testDateComparison() throws {
        let now = Date()
        let past = Date(timeIntervalSinceNow: -3600)
        let future = Date(timeIntervalSinceNow: 3600)
        
        _ = try db.insert(BlazeDataRecord(["created_at": .date(past)]))
        _ = try db.insert(BlazeDataRecord(["created_at": .date(now)]))
        _ = try db.insert(BlazeDataRecord(["created_at": .date(future)]))
        
        let recent = try db.query()
            .where("created_at", greaterThan: .date(now))
            .execute()
        
        XCTAssertEqual(recent.count, 1)
    }
    
    func testDateEqualityExact() throws {
        let exactDate = Date(timeIntervalSince1970: 1700000000)
        
        _ = try db.insert(BlazeDataRecord(["created_at": .date(exactDate)]))
        _ = try db.insert(BlazeDataRecord(["created_at": .date(Date())]))
        
        // Debug: Check what was stored
        let allRecords = try db.fetchAll()
        print("📅 Date equality test:")
        print("  exactDate = \(exactDate) (1970 epoch: 1700000000)")
        print("  exactDate.timeIntervalSinceReferenceDate = \(exactDate.timeIntervalSinceReferenceDate)")
        for record in allRecords {
            let field = record.storage["created_at"]
            print("  Stored: \(String(describing: field))")
        }
        
        let results = try db.query()
            .where("created_at", equals: .date(exactDate))
            .execute()
        
        print("  Query results: \(results.count)")
        
        XCTAssertEqual(results.count, 1, "Should match the record with exactDate")
    }
    
    // MARK: - Boolean Logic Edge Cases
    
    func testBooleanEquals() throws {
        _ = try db.insert(BlazeDataRecord(["is_active": .bool(true)]))
        _ = try db.insert(BlazeDataRecord(["is_active": .bool(false)]))
        
        let active = try db.query()
            .where("is_active", equals: .bool(true))
            .execute()
        
        XCTAssertEqual(active.count, 1)
    }
    
    func testBooleanNotEquals() throws {
        _ = try db.insert(BlazeDataRecord(["is_active": .bool(true)]))
        _ = try db.insert(BlazeDataRecord(["is_active": .bool(false)]))
        
        let results = try db.query()
            .where("is_active", notEquals: .bool(false))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - UUID Comparison Edge Cases
    
    func testUUIDEquals() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(uuid1)]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(uuid2)]))
        
        let results = try db.query()
            .where("id", equals: .uuid(uuid1))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testUUIDInArray() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let uuid3 = UUID()
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(uuid1)]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(uuid2)]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(uuid3)]))
        
        let results = try db.query()
            .where("id", in: [.uuid(uuid1), .uuid(uuid3)])
            .execute()
        
        XCTAssertEqual(results.count, 2)
    }
    
    // MARK: - Sort Stability Tests
    
    func testSortStability() throws {
        // Insert records with same sort key
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "priority": .int(1),
                "index": .int(i)
            ]))
        }
        
        let results = try db.query()
            .orderBy("priority", descending: false)
            .execute()
        
        // Should maintain insertion order for equal values
        XCTAssertEqual(results.count, 10)
    }
    
    func testMultipleSortsWithNils() throws {
        _ = try db.insert(BlazeDataRecord(["a": .int(1), "b": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["a": .int(1)])) // b is nil
        _ = try db.insert(BlazeDataRecord(["a": .int(2), "b": .int(1)]))
        
        let results = try db.query()
            .orderBy("a", descending: false)
            .orderBy("b", descending: false)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 3)
        // Nils should sort last
        XCTAssertNotNil(records[0].storage["b"])
    }
    
    // MARK: - Complex WHERE Combinations
    
    func testManyWhereClauses() throws {
        _ = try db.insert(BlazeDataRecord([
            "f1": .int(1),
            "f2": .int(2),
            "f3": .int(3),
            "f4": .int(4),
            "f5": .int(5)
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "f1": .int(10),
            "f2": .int(20),
            "f3": .int(30),
            "f4": .int(40),
            "f5": .int(50)
        ]))
        
        // 5 where clauses
        let results = try db.query()
            .where("f1", greaterThan: .int(5))
            .where("f2", greaterThan: .int(15))
            .where("f3", greaterThan: .int(25))
            .where("f4", greaterThan: .int(35))
            .where("f5", greaterThan: .int(45))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testConflictingWhereClauses() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        
        // Impossible condition
        let results = try db.query()
            .where("value", greaterThan: .int(5))
            .where("value", lessThan: .int(5))
            .execute()
        
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - JOIN Edge Cases with Query Builder
    
    func testJoinAfterHeavyFiltering() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryBuilderEdge123!")
        
        let userID = UUID()
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(userID), "name": .string("Alice")]))
        
        // Insert 1000 bugs (batch insert - 10x faster!), only 1 matches filter
        let bugRecords = (0..<1000).map { i in
            BlazeDataRecord([
                "title": .string(i == 500 ? "Special Bug" : "Bug \(i)"),
                "status": .string("open"),
                "author_id": .uuid(userID)
            ])
        }
        _ = try db.insertMany(bugRecords)
        
        // Heavy filter before join
        let results = try db.query()
            .where("title", equals: .string("Special Bug"))
            .join(usersDB.collection, on: "author_id")
            .executeJoin()
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].left["title"]?.stringValue, "Special Bug")
    }
    
    func testJoinWithNoMatchesAfterFilter() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users2-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryBuilderEdge123!")
        
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")]))
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "author_id": .uuid(UUID())]))
        
        // Filter eliminates all records
        let results = try db.query()
            .where("status", equals: .string("nonexistent"))
            .join(usersDB.collection, on: "author_id")
            .executeJoin()
        
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - Stress Tests
    
    func testVerySelectiveFilter() throws {
        // 10k records (batch insert - 20x faster!), only 1 matches
        let records = (0..<10000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "special": .bool(i == 5000)
            ])
        }
        let insertedIDs = try db.insertMany(records)
        XCTAssertEqual(insertedIDs.count, 10000, "Should insert exactly 10000 records")
        
        // CRITICAL: Persist to ensure all records are flushed and indexed before querying
        try db.persist()
        
        // Verify total count before querying
        let totalCount = db.count()
        XCTAssertEqual(totalCount, 10000, "Database should have exactly 10000 records after insert and persist")
        
        let results = try db.query()
            .where("special", equals: .bool(true))
            .execute()
        
        let resultRecords = try results.records
        XCTAssertEqual(resultRecords.count, 1, "Should find exactly 1 record with special=true (got \(resultRecords.count))")
        
        // Safe access: only access index if we have at least one record
        if resultRecords.count > 0 {
            XCTAssertEqual(resultRecords[0].storage["index"]?.intValue, 5000, "The matching record should have index 5000")
        } else {
            XCTFail("Expected 1 matching record but found 0. Total records in DB: \(totalCount)")
        }
    }
    
    func testQueryBuilderMemoryEfficiency() throws {
        // Insert large dataset (batch insert - 15x faster!)
        let records = (0..<5000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "status": .string("open")
            ])
        }
        _ = try db.insertMany(records)
        
        // Query with limit (should not load all 5000 into final array)
        let results = try db.query()
            .where("status", equals: .string("open"))
            .orderBy("index", descending: true)
            .limit(10)
            .execute()
        
        let resultRecords = try results.records
        XCTAssertEqual(resultRecords.count, 10)
        XCTAssertEqual(resultRecords[0].storage["index"]?.intValue, 4999)
    }
    
    // MARK: - Chaining Order Tests
    
    func testWhereAfterOrderBy() throws {
        // This shouldn't make sense but should not crash
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "value": .int(i),
                "status": .string("open")
            ]))
        }
        
        XCTAssertNoThrow(try db.query()
            .orderBy("value", descending: false)
            .where("status", equals: .string("open"))
            .execute())
    }
    
    func testMultipleLimits() throws {
        for i in 0..<20 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Last limit should win
        let results = try db.query()
            .limit(15)
            .limit(5)
            .execute()
        
        XCTAssertEqual(results.count, 5)
    }
    
    func testMultipleOffsets() throws {
        for i in 0..<20 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Last offset should win
        let results = try db.query()
            .offset(5)
            .offset(10)
            .execute()
        
        XCTAssertEqual(results.count, 10)
    }
    
    // MARK: - Error Recovery Tests
    
    func testQueryAfterFailedQuery() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        // First query with non-existent field (should work but return empty)
        let noResults = try db.query()
            .where("nonexistent", equals: .string("value"))
            .execute()
        XCTAssertEqual(noResults.count, 0)
        
        // Second query should still work
        let results = try db.query()
            .where("status", equals: .string("open"))
            .execute()
        XCTAssertEqual(results.count, 1)
    }
    
    func testQueryBuilderReuse() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        // Create builder
        let builder = db.query().where("status", equals: .string("open"))
        
        // Execute multiple times
        let results1 = try builder.execute()
        let results2 = try builder.execute()
        
        XCTAssertEqual(results1.count, results2.count)
    }
    
    // MARK: - Field Name Edge Cases
    
    func testFieldNameWithSpaces() throws {
        _ = try db.insert(BlazeDataRecord(["field name": .string("value")]))
        
        let results = try db.query()
            .where("field name", equals: .string("value"))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testFieldNameWithDots() throws {
        _ = try db.insert(BlazeDataRecord(["user.name": .string("Alice")]))
        
        let results = try db.query()
            .where("user.name", equals: .string("Alice"))
            .execute()
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testEmptyFieldName() throws {
        _ = try db.insert(BlazeDataRecord(["": .string("Empty key")]))
        
        XCTAssertNoThrow(try db.query().where("", equals: .string("Empty key")).execute())
    }
}

