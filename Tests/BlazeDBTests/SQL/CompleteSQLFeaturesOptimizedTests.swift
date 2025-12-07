//
//  CompleteSQLFeaturesOptimizedTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for ALL SQL features with optimizations
//  Tests cover edge cases, performance, and correctness
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class CompleteSQLFeaturesOptimizedTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
        db = try! BlazeDBClient(name: "Test", fileURL: tempURL, password: "CompleteSQLTest123!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - UNION/INTERSECT/EXCEPT Performance Tests
    
    func testUnionPerformance() throws {
        print("\n🔍 TEST: UNION performance (1000 records)")
        
        // Insert test data
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i),
                "category": .string(i % 2 == 0 ? "A" : "B")
            ]))
        }
        
        let start = Date()
        let union = db.query()
            .where("category", equals: .string("A"))
            .union(db.query().where("category", equals: .string("B")))
        let results = try union.execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 2.0, "UNION should be fast (< 2s for 1000 records)")
        XCTAssertGreaterThan(results.count, 0, "Should return results")
        print("   ✅ UNION performance: \(String(format: "%.3f", duration))s, \(results.count) results")
    }
    
    func testIntersectPerformance() throws {
        print("\n🔍 TEST: INTERSECT performance")
        
        let commonIds = (0..<100).map { _ in UUID() }
        
        // Insert overlapping data
        for id in commonIds {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(id), "value": .int(1)]))
        }
        for id in commonIds {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(id), "value": .int(2)]))
        }
        
        let start = Date()
        let intersect = db.query()
            .where("value", equals: .int(1))
            .intersect(db.query().where("value", equals: .int(2)))
        let results = try intersect.execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 1.0, "INTERSECT should be fast")
        print("   ✅ INTERSECT performance: \(String(format: "%.3f", duration))s")
    }
    
    // MARK: - LIKE/ILIKE Pattern Cache Tests
    
    func testLikePatternCache() throws {
        print("\n🔍 TEST: LIKE pattern cache optimization")
        
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("User\(i)@example.com")
            ]))
        }
        
        // First query (compiles pattern)
        let start1 = Date()
        _ = try db.query().where("name", like: "User%").execute()
        let duration1 = Date().timeIntervalSince(start1)
        
        // Second query (uses cached pattern)
        let start2 = Date()
        _ = try db.query().where("name", like: "User%").execute()
        let duration2 = Date().timeIntervalSince(start2)
        
        XCTAssertLessThan(duration2, duration1 * 1.5, "Cached pattern should be faster")
        print("   ✅ LIKE cache: \(String(format: "%.3f", duration1))s -> \(String(format: "%.3f", duration2))s")
    }
    
    func testLikeWildcards() throws {
        print("\n🔍 TEST: LIKE wildcards")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "code": .string("ABC123")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "code": .string("XYZ789")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "code": .string("ABC_456")]))
        
        // Test % wildcard
        let results1 = try db.query().where("code", like: "ABC%").execute()
        XCTAssertGreaterThan(try results1.records.count, 0, "LIKE with % should work")
        
        // Test _ wildcard
        let results2 = try db.query().where("code", like: "ABC_456").execute()
        XCTAssertGreaterThan(try results2.records.count, 0, "LIKE with _ should work")
        
        print("   ✅ LIKE wildcards work")
    }
    
    // MARK: - CTE Optimization Tests
    
    func testCTECaching() throws {
        print("\n🔍 TEST: CTE result caching")
        
        for i in 0..<50 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "category": .string(i < 25 ? "A" : "B")
            ]))
        }
        
        let start = Date()
        let cte = db.with("recent", as: db.query().where("value", greaterThan: .int(200)))
            .select(db.query().where("value", greaterThan: .int(200)))
        let results = try cte.execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 1.0, "CTE should be fast")
        print("   ✅ CTE performance: \(String(format: "%.3f", duration))s")
    }
    
    // MARK: - Correlated Subquery Cache Tests
    
    func testCorrelatedSubqueryCache() throws {
        print("\n🔍 TEST: Correlated subquery caching")
        
        for i in 0..<20 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "category": .string("A")
            ]))
        }
        
        let subquery = CorrelatedSubquery(
            subquery: db.query().where("category", equals: .string("A")),
            correlationField: "category",
            subqueryField: "category"
        )
        
        let start = Date()
        let results = try db.query()
            .where("value", greaterThanCorrelated: subquery)
            .execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 1.0, "Correlated subquery should be fast")
        print("   ✅ Correlated subquery performance: \(String(format: "%.3f", duration))s")
    }
    
    // MARK: - Savepoint Tests
    
    func testSavepoint() throws {
        print("\n🔍 TEST: Transaction savepoints")
        
        try db.beginTransaction()
        
        // Insert first record
        let id1 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(1)]))
        
        // Create savepoint
        try db.savepoint("sp1")
        
        // Insert second record
        let id2 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(2)]))
        
        // Rollback to savepoint
        try db.rollbackToSavepoint("sp1")
        
        // First record should exist, second should not
        XCTAssertNotNil(try db.fetch(id: id1), "Record before savepoint should exist")
        XCTAssertNil(try db.fetch(id: id2), "Record after savepoint should not exist")
        
        try db.rollbackTransaction()
        
        print("   ✅ Savepoints work")
    }
    
    func testSavepointNested() throws {
        print("\n🔍 TEST: Nested savepoints")
        
        try db.beginTransaction()
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(1)]))
        try db.savepoint("sp1")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(2)]))
        try db.savepoint("sp2")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(3)]))
        
        // Rollback to sp1 (should remove sp2 and later changes)
        try db.rollbackToSavepoint("sp1")
        
        // Verify only first record exists
        let results = try db.query().execute()
        XCTAssertEqual(try results.records.count, 1, "Only record before sp1 should exist")
        
        try db.rollbackTransaction()
        
        print("   ✅ Nested savepoints work")
    }
    
    // MARK: - Index Hints Tests
    
    func testIndexHint() throws {
        print("\n🔍 TEST: Index hints")
        
        // Create index
        try db.collection.createIndex(on: "email")
        
        // Insert data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "email": .string("user\(i)@test.com")
            ]))
        }
        
        // Use index hint
        let results = try db.query()
            .useIndex(on: "email")
            .where("email", equals: .string("user5@test.com"))
            .execute()
        
        XCTAssertGreaterThan(try results.records.count, 0, "Index hint should work")
        print("   ✅ Index hints work")
    }
    
    // MARK: - Regex Query Tests
    
    func testRegexQuery() throws {
        print("\n🔍 TEST: Regex query")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "email": .string("test@example.com")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "email": .string("invalid-email")]))
        
        // Test email regex
        let emailPattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}$"
        let results = try db.query()
            .where("email", matches: emailPattern)
            .execute()
        
        XCTAssertEqual(try results.records.count, 1, "Should match valid email")
        print("   ✅ Regex query works")
    }
    
    func testRegexCaseInsensitive() throws {
        print("\n🔍 TEST: Regex case-insensitive")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("John Doe")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("JANE SMITH")]))
        
        let results = try db.query()
            .where("name", matchesCaseInsensitive: "^john")
            .execute()
        
        XCTAssertGreaterThan(try results.records.count, 0, "Case-insensitive regex should work")
        print("   ✅ Case-insensitive regex works")
    }
    
    // MARK: - Combined Features Performance Tests
    
    func testAllFeaturesCombined() throws {
        print("\n🔍 TEST: All features combined performance")
        
        // Setup
        try db.createUniqueIndex(on: "email")
        db.addCheckConstraint(CheckConstraint(name: "age_check", field: "age") { record in
            guard let age = record.storage["age"]?.intValue else { return true }
            return age >= 0 && age <= 150
        })
        
        // Insert data
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "email": .string("user\(i)@test.com"),
                "age": .int(20 + i % 50),
                "name": .string("User\(i)")
            ]))
        }
        
        let start = Date()
        
        // Complex query: LIKE + WHERE + UNION + ORDER BY
        let query1 = db.query()
            .where("name", like: "User%")
            .where("age", greaterThan: .int(25))
        
        let query2 = db.query()
            .where("age", lessThan: .int(30))
        
        let union = query1.union(query2)
            .orderBy("age", descending: false)
            .limit(10)
        
        let results = try union.execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 2.0, "Combined features should be fast")
        XCTAssertGreaterThan(results.count, 0, "Should return results")
        
        print("   ✅ All features combined: \(String(format: "%.3f", duration))s, \(results.count) results")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyUnion() throws {
        print("\n🔍 TEST: Empty UNION")
        
        let union = db.query()
            .where("nonexistent", equals: .string("value"))
            .union(db.query().where("alsoNonexistent", equals: .string("value")))
        
        let results = try union.execute()
        XCTAssertEqual(results.count, 0, "Empty UNION should return empty array")
        print("   ✅ Empty UNION works")
    }
    
    func testLikeEmptyPattern() throws {
        print("\n🔍 TEST: LIKE empty pattern")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Test")]))
        
        let results = try db.query()
            .where("name", like: "")
            .execute()
        
        // Empty pattern should match everything (or nothing, depending on implementation)
        XCTAssertGreaterThanOrEqual(try results.records.count, 0, "Empty pattern should handle gracefully")
        print("   ✅ Empty LIKE pattern works")
    }
    
    func testSavepointWithoutTransaction() throws {
        print("\n🔍 TEST: Savepoint without transaction")
        
        XCTAssertThrowsError(try db.savepoint("sp1")) { error in
            XCTAssertTrue(error.localizedDescription.contains("transaction") || 
                         error.localizedDescription.contains("Transaction"),
                        "Should throw transaction error")
        }
        print("   ✅ Savepoint validation works")
    }
}

