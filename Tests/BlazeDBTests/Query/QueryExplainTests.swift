//  QueryExplainTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for query EXPLAIN and optimization

import XCTest
@testable import BlazeDB

final class QueryExplainTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Explain-\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "explain_test", fileURL: tempURL, password: "QueryExplainTest123!")
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
    
    // MARK: - Basic EXPLAIN
    
    func testExplainSimpleQuery() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let plan = try db.query()
            .where("index", greaterThan: .int(50))
            .explain()
        
        XCTAssertGreaterThan(plan.steps.count, 0)
        XCTAssertGreaterThan(plan.estimatedRecords, 0)
        XCTAssertGreaterThan(plan.estimatedTime, 0)
    }
    
    func testExplainWithLimit() throws {
        // Batch insert 1000 records (10x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query()
            .limit(10)
            .explain()
        
        XCTAssertLessThanOrEqual(plan.estimatedRecords, 10)
    }
    
    func testExplainWithSort() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let plan = try db.query()
            .orderBy("value", descending: true)
            .explain()
        
        // Should have sort step
        let hasSortStep = plan.steps.contains { step in
            if case .sort = step.type { return true }
            return false
        }
        XCTAssertTrue(hasSortStep)
    }
    
    func testExplainWithAggregation() throws {
        // Batch insert 1000 records (10x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord(["status": .string(i % 2 == 0 ? "open" : "closed")])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query()
            .groupBy("status")
            .count()
            .explain()
        
        // Should have aggregate or groupBy step
        let hasAggStep = plan.steps.contains { step in
            if case .aggregate = step.type { return true }
            if case .groupBy = step.type { return true }
            return false
        }
        XCTAssertTrue(hasAggStep)
    }
    
    func testExplainWithJoin() throws {
        let usersURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Users-\(UUID().uuidString).blazedb")
        defer { 
            try? FileManager.default.removeItem(at: usersURL)
            try? FileManager.default.removeItem(at: usersURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "QueryExplainTest123!")
        
        _ = try usersDB.insert(BlazeDataRecord(["id": .uuid(UUID())]))
        _ = try db.insert(BlazeDataRecord(["author_id": .uuid(UUID())]))
        
        let plan = try db.query()
            .join(usersDB.collection, on: "author_id")
            .explain()
        
        // Should have join step
        let hasJoinStep = plan.steps.contains { step in
            if case .join = step.type { return true }
            return false
        }
        XCTAssertTrue(hasJoinStep)
    }
    
    // MARK: - Warnings
    
    func testExplainWarnsLargeTableScan() throws {
        // Batch insert 15k records (20x faster!)
        let records = (0..<5000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query().explain()
        
        // Should warn about large dataset
        XCTAssertGreaterThan(plan.warnings.count, 0)
    }
    
    func testExplainWarnsManyFilters() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        let plan = try db.query()
            .where("f1", equals: .int(1))
            .where("f2", equals: .int(1))
            .where("f3", equals: .int(1))
            .where("f4", equals: .int(1))
            .where("f5", equals: .int(1))
            .where("f6", equals: .int(1))  // 6 filters
            .explain()
        
        // Should warn about many filters
        XCTAssertGreaterThan(plan.warnings.count, 0)
    }
    
    func testExplainWarnsLargeSort() throws {
        // Batch insert 20k records (20x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query()
            .orderBy("value", descending: true)
            .explain()
        
        // Should warn about sorting many records
        XCTAssertGreaterThan(plan.warnings.count, 0)
    }
    
    // MARK: - Estimation Accuracy
    
    func testEstimateReasonablyAccurate() throws {
        // Batch insert 1000 records (10x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query()
            .where("value", greaterThan: .int(500))
            .limit(10)
            .explain()
        
        // Estimated records should be around 10 (limit)
        XCTAssertLessThanOrEqual(plan.estimatedRecords, 100)
    }
    
    // MARK: - Query Plan Output
    
    func testExplainPrintsReadable() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let plan = try db.query()
            .where("value", greaterThan: .int(50))
            .orderBy("value", descending: true)
            .limit(10)
            .explain()
        
        let output = plan.description
        
        XCTAssertTrue(output.contains("Query Execution Plan"))
        XCTAssertTrue(output.contains("Estimated records"))
        XCTAssertTrue(output.contains("steps"))
    }
    
    func testExplainQueryConvenience() throws {
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Should not throw
        XCTAssertNoThrow(try db.query().where("value", equals: .int(5)).explainQuery())
    }
    
    // MARK: - Optimization Hints
    
    func testUseIndexHint() throws {
        _ = try db.insert(BlazeDataRecord(["status": .string("open")]))
        
        let query = db.query()
            .useIndex("status")
            .where("status", equals: .string("open"))
        
        // Should not throw
        XCTAssertNoThrow(try query.execute())
    }
    
    func testForceTableScanHint() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        let query = db.query()
            .forceTableScan()
            .where("value", equals: .int(1))
        
        // Should not throw
        XCTAssertNoThrow(try query.execute())
    }
    
    // MARK: - Complex Query Plans
    
    func testExplainComplexQuery() throws {
        // Batch insert 1000 records (10x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "priority": .int(i % 5 + 1),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query()
            .where("status", equals: .string("open"))
            .where("priority", greaterThan: .int(3))
            .orderBy("value", descending: true)
            .limit(20)
            .explain()
        
        // Should have multiple steps
        XCTAssertGreaterThanOrEqual(plan.steps.count, 3)
        
        // Should estimate around 20 final records (limit)
        XCTAssertLessThanOrEqual(plan.estimatedRecords, 20)
    }
    
    func testExplainGroupedAggregation() throws {
        // Batch insert 5000 records (15x faster!)
        let records = (0..<5000).map { i in
            BlazeDataRecord([
                "team": .string("team_\(i % 10)"),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        let plan = try db.query()
            .where("value", greaterThan: .int(2500))
            .groupBy("team")
            .count()
            .sum("value")
            .explain()
        
        // Should estimate around 10 groups
        XCTAssertLessThanOrEqual(plan.estimatedRecords, 20)
        
        // Should have groupBy step
        let hasGroupBy = plan.steps.contains { step in
            if case .groupBy = step.type { return true }
            return false
        }
        XCTAssertTrue(hasGroupBy)
    }
}

