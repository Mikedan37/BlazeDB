//  QueryExplainTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for query EXPLAIN and optimization

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryExplainTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    // Linux CI is currently the bottleneck lane for Tier1 wall time.
    // Keep macOS stress sizes unchanged; use threshold-focused fixture sizes on Linux.
    private var largeTableScanRecordCount: Int {
        #if os(Linux)
        return 1001
        #else
        return 15000
        #endif
    }
    
    private var largeSortRecordCount: Int {
        #if os(Linux)
        return 10001
        #else
        return 20000
        #endif
    }
    
    private var groupedAggregationRecordCount: Int {
        #if os(Linux)
        return 1200
        #else
        return 5000
        #endif
    }
    
    private var groupedAggregationFilterThreshold: Int {
        #if os(Linux)
        return 600
        #else
        return 2500
        #endif
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        BlazeDBClient.clearCachedKey()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Explain-\(UUID().uuidString).blazedb")
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
        try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
        db = try BlazeDBClient(name: "explain_test", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
    }
    
    override func tearDownWithError() throws {
        try db?.close()
        db = nil
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
        try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
        BlazeDBClient.clearCachedKey()
        try super.tearDownWithError()
    }
    
    // MARK: - Basic EXPLAIN
    
    func testExplainSimpleQuery() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let plan = try requireFixture(db).query()
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
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query()
            .limit(10)
            .explain()
        
        XCTAssertLessThanOrEqual(plan.estimatedRecords, 10)
    }
    
    func testExplainWithSort() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let plan = try requireFixture(db).query()
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
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query()
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
            try? FileManager.default.removeItem(at: try requireFixture(usersURL))
            try? FileManager.default.removeItem(at: try requireFixture(usersURL).deletingPathExtension().appendingPathExtension("meta"))
        }
        let usersDB = try BlazeDBClient(name: "users", fileURL: try requireFixture(usersURL), password: "SecureTestDB-456!")
        
        _ = try requireFixture(usersDB).insert(BlazeDataRecord(["id": .uuid(UUID())]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["author_id": .uuid(UUID())]))
        
        let plan = try requireFixture(db).query()
            .join(try requireFixture(usersDB).collection, on: "author_id")
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
        let records = (0..<largeTableScanRecordCount).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query().explain()
        
        // Should warn about large dataset
        XCTAssertTrue(plan.warnings.contains { $0.contains("Large dataset") })
    }
    
    func testExplainWarnsManyFilters() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        
        let plan = try requireFixture(db).query()
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
        let records = (0..<largeSortRecordCount).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query()
            .orderBy("value", descending: true)
            .explain()
        
        // Should warn about sorting many records
        XCTAssertTrue(plan.warnings.contains { $0.contains("Sorting") })
    }
    
    // MARK: - Estimation Accuracy
    
    func testEstimateReasonablyAccurate() throws {
        // Batch insert 1000 records (10x faster!)
        let records = (0..<1000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query()
            .where("value", greaterThan: .int(500))
            .limit(10)
            .explain()
        
        // Estimated records should be around 10 (limit)
        XCTAssertLessThanOrEqual(plan.estimatedRecords, 100)
    }
    
    // MARK: - Query Plan Output
    
    func testExplainPrintsReadable() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let plan = try requireFixture(db).query()
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
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Should not throw
        XCTAssertNoThrow(try requireFixture(db).query().where("value", equals: .int(5)).explainQuery())
    }
    
    // MARK: - Optimization Hints
    
    func testUseIndexHint() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open")]))
        
        let query = try requireFixture(db).query()
            .useIndex("status")
            .where("status", equals: .string("open"))
        
        // Should not throw
        XCTAssertNoThrow(try query.execute())
    }
    
    func testForceTableScanHint() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(1)]))
        
        let query = try requireFixture(db).query()
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
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query()
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
        let records = (0..<groupedAggregationRecordCount).map { i in
            BlazeDataRecord([
                "team": .string("team_\(i % 10)"),
                "value": .int(i)
            ])
        }
        _ = try requireFixture(db).insertMany(records)
        
        let plan = try requireFixture(db).query()
            .where("value", greaterThan: .int(groupedAggregationFilterThreshold))
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

    func testExplainListsCandidateIndexesForIndexedFilter() throws {
        for i in 0..<20 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        try requireFixture(db).collection.createIndex(on: "status")

        let plan = try requireFixture(db).query()
            .where("status", equals: .string("open"))
            .explain()

        XCTAssertFalse(
            plan.candidateIndexes.isEmpty,
            "Explain should surface candidate indexes for indexed filter fields"
        )
    }

    func testDeprecatedPlannerExplain_NotesIndexSelectionIsAdvisory() throws {
        for i in 0..<20 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        try requireFixture(db).collection.createIndex(on: "status")

        let explanation = try requireFixture(db).explain {
            try requireFixture(db).query().where("status", equals: .string("open"))
        }

        XCTAssertTrue(
            explanation.notes.contains(where: { $0.localizedCaseInsensitiveContains("advisory") }),
            "Deprecated planner explain should not imply guaranteed index execution"
        )
    }
}

