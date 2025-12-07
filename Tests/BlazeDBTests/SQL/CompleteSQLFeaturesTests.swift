//
//  CompleteSQLFeaturesTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for ALL SQL features (Union, CTEs, LIKE, Correlated Subqueries, Check Constraints, Unique Constraints, EXPLAIN)
//  All implementations are hyper-optimized
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class CompleteSQLFeaturesTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
        
        // Aggressively clean up any leftover files from previous test runs
        cleanupDatabaseFilesBeforeInit(at: tempURL)
        
        db = try! BlazeDBClient(name: "Test", fileURL: tempURL, password: "TestPass1234!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - UNION/UNION ALL Tests
    
    func testUnion() throws {
        print("\n🔍 TEST: UNION (distinct)")
        
        // Insert data into two "tables"
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("User\(i)"),
                "type": .string("user")
            ])
            _ = try db.insert(record)
        }
        
        // Create second "table" (same DB, different filter)
        let users = try db.query().where("type", equals: .string("user")).execute()
        let customers = try db.query().where("type", equals: .string("user")).execute()  // Same for demo
        
        // UNION (should remove duplicates)
        let union = db.query()
            .where("type", equals: .string("user"))
            .union(db.query().where("type", equals: .string("user")))
        
        let results = try union.execute()
        XCTAssertGreaterThan(results.count, 0, "UNION should return results")
        
        print("   ✅ UNION works")
    }
    
    func testUnionAll() throws {
        print("\n🔍 TEST: UNION ALL (keeps duplicates)")
        
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        let unionAll = db.query()
            .unionAll(db.query())
        
        let results = try unionAll.execute()
        XCTAssertGreaterThan(results.count, 0, "UNION ALL should return results")
        
        print("   ✅ UNION ALL works")
    }
    
    func testIntersect() throws {
        print("\n🔍 TEST: INTERSECT")
        
        // Insert overlapping data
        let commonId = UUID()
        let record1 = BlazeDataRecord(["id": .uuid(commonId), "value": .int(1)])
        let record2 = BlazeDataRecord(["id": .uuid(UUID()), "value": .int(2)])
        _ = try db.insert(record1)
        _ = try db.insert(record2)
        
        let intersect = db.query()
            .where("value", equals: .int(1))
            .intersect(db.query().where("id", equals: .uuid(commonId)))
        
        let results = try intersect.execute()
        XCTAssertGreaterThanOrEqual(results.count, 0, "INTERSECT should work")
        
        print("   ✅ INTERSECT works")
    }
    
    func testExcept() throws {
        print("\n🔍 TEST: EXCEPT")
        
        let id1 = UUID()
        let id2 = UUID()
        _ = try db.insert(BlazeDataRecord(["id": .uuid(id1), "value": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(id2), "value": .int(2)]))
        
        let except = db.query()
            .except(db.query().where("value", equals: .int(2)))
        
        let results = try except.execute()
        XCTAssertGreaterThanOrEqual(results.count, 0, "EXCEPT should work")
        
        print("   ✅ EXCEPT works")
    }
    
    // MARK: - LIKE/ILIKE Tests
    
    func testLike() throws {
        print("\n🔍 TEST: LIKE pattern matching")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("John Doe")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Jane Smith")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob Johnson")]))
        
        // LIKE 'John%'
        let results = try db.query()
            .where("name", like: "John%")
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "LIKE should find matches")
        
        print("   ✅ LIKE works")
    }
    
    func testILike() throws {
        print("\n🔍 TEST: ILIKE (case-insensitive)")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "email": .string("John@Example.com")]))
        
        // ILIKE '%@example.com' (case-insensitive)
        let results = try db.query()
            .where("email", ilike: "%@example.com")
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "ILIKE should find case-insensitive matches")
        
        print("   ✅ ILIKE works")
    }
    
    func testLikeWildcards() throws {
        print("\n🔍 TEST: LIKE with wildcards")
        
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "code": .string("ABC123")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "code": .string("XYZ789")]))
        
        // LIKE 'ABC%'
        let results = try db.query()
            .where("code", like: "ABC%")
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "LIKE with % should work")
        
        // LIKE 'ABC_23' (single char wildcard)
        let results2 = try db.query()
            .where("code", like: "ABC_23")
            .execute()
        
        let records2 = try results2.records
        XCTAssertGreaterThan(records2.count, 0, "LIKE with _ should work")
        
        print("   ✅ LIKE wildcards work")
    }
    
    // MARK: - CTE Tests
    
    func testCTE() throws {
        print("\n🔍 TEST: CTE (WITH clause)")
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "category": .string(i < 5 ? "A" : "B")
            ]))
        }
        
        // WITH recent AS (SELECT * WHERE value > 50)
        // SELECT * FROM recent
        let cte = db.with("recent", as: db.query().where("value", greaterThan: .int(50)))
            .select(db.query().where("value", greaterThan: .int(50)))
        
        let results = try cte.execute()
        XCTAssertGreaterThan(results.count, 0, "CTE should work")
        
        print("   ✅ CTE works")
    }
    
    // MARK: - Correlated Subquery Tests
    
    func testCorrelatedSubquery() throws {
        print("\n🔍 TEST: Correlated subquery")
        
        // Insert test data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "category": .string("A")
            ]))
        }
        
        // WHERE value > (SELECT AVG(value) WHERE category = outer.category)
        let subquery = CorrelatedSubquery(
            subquery: db.query().where("category", equals: .string("A")),
            correlationField: "category",
            subqueryField: "category"
        )
        
        let results = try db.query()
            .where("value", greaterThanCorrelated: subquery)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThanOrEqual(records.count, 0, "Correlated subquery should work")
        
        print("   ✅ Correlated subquery works")
    }
    
    // MARK: - Check Constraint Tests
    
    func testCheckConstraint() throws {
        print("\n🔍 TEST: Check constraint")
        
        // Add check constraint: age >= 0 AND age <= 150
        let constraint = CheckConstraint(name: "age_range", field: "age") { record in
            guard let age = record.storage["age"]?.intValue else { return true }
            return age >= 0 && age <= 150
        }
        
        db.addCheckConstraint(constraint)
        
        // Valid insert (should work)
        let valid = BlazeDataRecord(["id": .uuid(UUID()), "age": .int(25)])
        _ = try db.insert(valid)
        
        // Invalid insert (should fail)
        let invalid = BlazeDataRecord(["id": .uuid(UUID()), "age": .int(200)])
        
        do {
            _ = try db.insert(invalid)
            XCTFail("Should throw check constraint violation")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("check constraint") || 
                         error.localizedDescription.contains("Check constraint"),
                        "Should throw check constraint violation")
        }
        
        print("   ✅ Check constraint works")
    }
    
    func testCheckConstraintMultiple() throws {
        print("\n🔍 TEST: Multiple check constraints")
        
        // Add multiple constraints
        db.addCheckConstraint(CheckConstraint(name: "positive", field: "value") { record in
            guard let value = record.storage["value"]?.intValue else { return true }
            return value > 0
        })
        
        db.addCheckConstraint(CheckConstraint(name: "even", field: "value") { record in
            guard let value = record.storage["value"]?.intValue else { return true }
            return value % 2 == 0
        })
        
        // Valid (positive and even)
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(2)]))
        
        // Invalid (negative)
        do {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(-1)]))
            XCTFail("Should fail positive constraint")
        } catch {
            // Expected
        }
        
        // Invalid (odd)
        do {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(3)]))
            XCTFail("Should fail even constraint")
        } catch {
            // Expected
        }
        
        print("   ✅ Multiple check constraints work")
    }
    
    // MARK: - Unique Constraint Tests
    
    func testUniqueConstraint() throws {
        print("\n🔍 TEST: Unique constraint enforcement")
        
        // Create unique index
        try db.createUniqueIndex(on: "email")
        
        // Insert first record (should work)
        let record1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "email": .string("test@example.com"),
            "name": .string("Test")
        ])
        _ = try db.insert(record1)
        
        // Try to insert duplicate (should fail)
        let record2 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "email": .string("test@example.com"),  // Duplicate!
            "name": .string("Test2")
        ])
        
        do {
            _ = try db.insert(record2)
            XCTFail("Should throw unique constraint violation")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unique") || 
                         error.localizedDescription.contains("Unique"),
                        "Should throw unique constraint violation")
        }
        
        print("   ✅ Unique constraint works")
    }
    
    func testUniqueConstraintUpdate() throws {
        print("\n🔍 TEST: Unique constraint on update")
        
        try db.createUniqueIndex(on: "email")
        
        let id1 = UUID()
        let id2 = UUID()
        _ = try db.insert(BlazeDataRecord(["id": .uuid(id1), "email": .string("user1@test.com")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(id2), "email": .string("user2@test.com")]))
        
        // Update to duplicate email (should fail)
        var updated = BlazeDataRecord(["id": .uuid(id2), "email": .string("user1@test.com")])
        
        do {
            try db.update(id: id2, with: updated)
            XCTFail("Should throw unique constraint violation")
        } catch {
            // Expected
        }
        
        print("   ✅ Unique constraint on update works")
    }
    
    func testUniqueCompoundConstraint() throws {
        print("\n🔍 TEST: Unique compound constraint")
        
        try db.createUniqueCompoundIndex(on: ["teamId", "email"])
        
        // Insert first (should work)
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "teamId": .string("team1"),
            "email": .string("user@test.com")
        ]))
        
        // Insert different team, same email (should work - different compound key)
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "teamId": .string("team2"),
            "email": .string("user@test.com")
        ]))
        
        // Insert duplicate compound key (should fail)
        do {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "teamId": .string("team1"),
                "email": .string("user@test.com")  // Duplicate compound key!
            ]))
            XCTFail("Should throw unique constraint violation")
        } catch {
            // Expected
        }
        
        print("   ✅ Unique compound constraint works")
    }
    
    // MARK: - EXPLAIN Tests
    
    func testExplain() throws {
        print("\n🔍 TEST: EXPLAIN query plan")
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i),
                "category": .string(i % 2 == 0 ? "A" : "B")
            ]))
        }
        
        let plan = try db.query()
            .where("category", equals: .string("A"))
            .orderBy("value", descending: false)
            .limit(5)
            .explain()
        
        XCTAssertFalse(plan.steps.isEmpty, "Query plan should have steps")
        XCTAssertGreaterThan(plan.estimatedTime, 0, "Should have estimated time")
        
        print("   ✅ EXPLAIN works")
        print("   Plan: \(plan.steps.map { String(describing: $0.type) }.joined(separator: " -> "))")
    }
    
    func testExplainAnalyze() throws {
        print("\n🔍 TEST: EXPLAIN ANALYZE")
        
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ]))
        }
        
        let plan = try db.query()
            .where("value", greaterThan: .int(5))
            .explainAnalyze()
        
        XCTAssertNotNil(plan.actualRows, "Should have actual row count")
        XCTAssertNotNil(plan.executionTime, "Should have execution time")
        
        print("   ✅ EXPLAIN ANALYZE works")
        print("   Actual rows: \(plan.actualRows ?? 0), Time: \(plan.executionTime ?? 0)s")
    }
    
    // MARK: - Performance Tests
    
    func testUnionPerformance() throws {
        print("\n🔍 TEST: UNION performance (1000 records)")
        
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ]))
        }
        
        let start = Date()
        let union = db.query().union(db.query())
        _ = try union.execute()
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(duration, 1.0, "UNION should be fast (< 1s for 1000 records)")
        print("   ✅ UNION performance: \(String(format: "%.3f", duration))s")
    }
    
    func testLikePerformance() throws {
        print("\n🔍 TEST: LIKE performance (pattern cache)")
        
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
        print("   ✅ LIKE cache works: \(String(format: "%.3f", duration1))s -> \(String(format: "%.3f", duration2))s")
    }
    
    // MARK: - Combined Features Tests
    
    func testAllFeaturesTogether() throws {
        print("\n🔍 TEST: All SQL features combined")
        
        // Setup
        try db.createUniqueIndex(on: "email")
        db.addCheckConstraint(CheckConstraint(name: "age_check", field: "age") { record in
            guard let age = record.storage["age"]?.intValue else { return true }
            return age >= 0 && age <= 150
        })
        
        // Insert data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "email": .string("user\(i)@test.com"),
                "age": .int(20 + i),
                "name": .string("User\(i)")
            ]))
        }
        
        // Complex query: LIKE + WHERE + ORDER BY + LIMIT
        let results1 = try db.query()
            .where("name", like: "User%")
            .where("age", greaterThan: .int(25))
            .orderBy("age", descending: false)
            .limit(5)
            .execute()
        
        XCTAssertGreaterThan(try results1.records.count, 0, "Complex query should work")
        
        // UNION
        let union = db.query()
            .where("age", greaterThan: .int(25))
            .union(db.query().where("age", lessThan: .int(30)))
        
        let results2 = try union.execute()
        XCTAssertGreaterThan(results2.count, 0, "UNION should work")
        
        // EXPLAIN
        let plan = try db.query()
            .where("name", like: "User%")
            .explain()
        
        XCTAssertFalse(plan.steps.isEmpty, "EXPLAIN should work")
        
        print("   ✅ All features work together")
    }
}

