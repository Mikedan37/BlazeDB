//  AggregationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for aggregation functionality

import XCTest
@testable import BlazeDBCore

final class AggregationTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        // Aggressive test isolation
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Agg-\(testID).blazedb")
        
        // Clean up any leftover files (retry 3x)
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("indexes"))
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent().appendingPathComponent("transaction_backup.blazedb"))
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent().appendingPathComponent("transaction_backup.meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent().appendingPathComponent("txn_log.json"))
            
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        db = try! BlazeDBClient(name: "agg_test_\(testID)", fileURL: tempURL, password: "test-pass-123")
        
        // IMPORTANT: Disable MVCC until version persistence is implemented
        db.collection.mvccEnabled = false
    }
    
    override func tearDown() {
        if let tempURL = tempURL {
            cleanupBlazeDB(&db, at: tempURL)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic Aggregations
    
    func testCount() throws {
        // Insert test data
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        
        // Count all
        let result = try db.query()
            .count()
            .executeAggregation()
        
        XCTAssertEqual(result.count, 100)
    }
    
    func testCountWithFilter() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }
        
        let result = try db.query()
            .where("status", equals: .string("open"))
            .count()
            .executeAggregation()
        
        XCTAssertEqual(result.count, 50)
    }
    
    func testSum() throws {
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "value": .int(i),
                "status": .string("open")
            ]))
        }
        
        let result = try db.query()
            .sum("value", as: "total")
            .executeAggregation()
        
        XCTAssertEqual(result.sum("total"), 45.0)  // 0+1+2+...+9 = 45
    }
    
    func testSumWithDouble() throws {
        _ = try db.insert(BlazeDataRecord(["price": .double(10.5)]))
        _ = try db.insert(BlazeDataRecord(["price": .double(20.25)]))
        _ = try db.insert(BlazeDataRecord(["price": .double(5.75)]))
        
        let result = try db.query()
            .sum("price", as: "total")
            .executeAggregation()
        
        XCTAssertEqual(result.sum("total") ?? 0, 36.5, accuracy: 0.01)
    }
    
    func testAvg() throws {
        for i in 1...10 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let result = try db.query()
            .avg("value", as: "average")
            .executeAggregation()
        
        XCTAssertEqual(result.avg("average"), 5.5)  // (1+10)/2 = 5.5
    }
    
    func testMin() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(20)]))
        
        let result = try db.query()
            .min("value", as: "minimum")
            .executeAggregation()
        
        XCTAssertEqual(result.min("minimum")?.intValue, 5)
    }
    
    func testMax() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(5)]))
        _ = try db.insert(BlazeDataRecord(["value": .int(20)]))
        
        let result = try db.query()
            .max("value", as: "maximum")
            .executeAggregation()
        
        XCTAssertEqual(result.max("maximum")?.intValue, 20)
    }
    
    func testMultipleAggregations() throws {
        for i in 1...10 {
            _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let result = try db.query()
            .aggregate([
                .count(as: "total"),
                .sum("value", as: "sum"),
                .avg("value", as: "avg"),
                .min("value", as: "min"),
                .max("value", as: "max")
            ])
            .executeAggregation()
        
        // Access count by alias "total" since that's what we named it
        XCTAssertEqual(result["total"]?.intValue ?? 0, 10)
        XCTAssertEqual(result.sum("sum") ?? 0, 55.0)
        XCTAssertEqual(result.avg("avg") ?? 0, 5.5)
        XCTAssertEqual(result.min("min")?.intValue, 1)
        XCTAssertEqual(result.max("max")?.intValue, 10)
    }
    
    // MARK: - GROUP BY Tests
    
    func testGroupByCount() throws {
        // Optimized: Use insertMany for batch inserts
        let records = (0..<100).map { i -> BlazeDataRecord in
            let status: String
            if i % 3 == 0 {
                status = "open"
            } else if i % 3 == 1 {
                status = "closed"
            } else {
                status = "in_progress"
            }
            return BlazeDataRecord([
                "index": .int(i),
                "status": .string(status)
            ])
        }
        _ = try db.insertMany(records)
        
        let result = try db.query()
            .groupBy("status")
            .count(as: "total")
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 3)
        XCTAssert(result.groups.keys.contains("open"))
        XCTAssert(result.groups.keys.contains("closed"))
        XCTAssert(result.groups.keys.contains("in_progress"))
    }
    
    func testGroupByMultipleFields() throws {
        // Optimized: Use insertMany for batch inserts
        let records = (0..<20).map { i -> BlazeDataRecord in
            let status = i % 2 == 0 ? "open" : "closed"
            return BlazeDataRecord([
                "priority": .int(i % 3 + 1),  // 1, 2, 3
                "status": .string(status)
            ])
        }
        _ = try db.insertMany(records)
        
        let result = try db.query()
            .groupBy(["priority", "status"])
            .count()
            .executeGroupedAggregation()
        
        // Should have 6 groups: (1,open), (1,closed), (2,open), (2,closed), (3,open), (3,closed)
        XCTAssertEqual(result.groups.count, 6)
    }
    
    func testGroupByWithSum() throws {
        _ = try db.insert(BlazeDataRecord(["team": .string("A"), "hours": .double(10.5)]))
        _ = try db.insert(BlazeDataRecord(["team": .string("A"), "hours": .double(20.0)]))
        _ = try db.insert(BlazeDataRecord(["team": .string("B"), "hours": .double(15.0)]))
        _ = try db.insert(BlazeDataRecord(["team": .string("B"), "hours": .double(25.5)]))
        
        let result = try db.query()
            .groupBy("team")
            .sum("hours", as: "total_hours")
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups["A"]?.sum("total_hours") ?? 0, 30.5, accuracy: 0.01)
        XCTAssertEqual(result.groups["B"]?.sum("total_hours") ?? 0, 40.5, accuracy: 0.01)
    }
    
    func testGroupByWithAvg() throws {
        // Optimized: Use insertMany for batch inserts
        let records = (0..<10).map { i -> BlazeDataRecord in
            let category = i < 5 ? "A" : "B"
            return BlazeDataRecord([
                "category": .string(category),
                "score": .int(i + 1)
            ])
        }
        _ = try db.insertMany(records)
        
        let result = try db.query()
            .groupBy("category")
            .avg("score", as: "avg_score")
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups["A"]?.avg("avg_score") ?? 0, 3.0, accuracy: 0.01)  // (1+2+3+4+5)/5
        XCTAssertEqual(result.groups["B"]?.avg("avg_score") ?? 0, 8.0, accuracy: 0.01)  // (6+7+8+9+10)/5
    }
    
    func testGroupByMultipleAggregations() throws {
        // Optimized: Use insertMany for batch inserts
        let records = (0..<20).map { i -> BlazeDataRecord in
            let status = i % 2 == 0 ? "open" : "closed"
            return BlazeDataRecord([
                "status": .string(status),
                "priority": .int(i % 5 + 1),
                "hours": .double(Double(i))
            ])
        }
        _ = try db.insertMany(records)
        
        let result = try db.query()
            .groupBy("status")
            .aggregate([
                .count(as: "total"),
                .sum("hours", as: "total_hours"),
                .avg("priority", as: "avg_priority"),
                .min("hours", as: "min_hours"),
                .max("hours", as: "max_hours")
            ])
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 2)
        // Access count by alias "total" since that's what we named it
        XCTAssertEqual(result.groups["open"]?["total"]?.intValue ?? 0, 10)
        XCTAssertEqual(result.groups["closed"]?["total"]?.intValue ?? 0, 10)
    }
    
    // MARK: - HAVING Clause Tests
    
    func testHavingClause() throws {
        for i in 0..<50 {
            _ = try db.insert(BlazeDataRecord([
                "team": .string(i < 20 ? "A" : (i < 40 ? "B" : "C")),
                "value": .int(1)
            ]))
        }
        
        // Groups: A=20, B=20, C=10
        // Filter to groups with count > 15
        let result = try db.query()
            .groupBy("team")
            .count()
            .having { $0.count ?? 0 > 15 }
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 2)  // Only A and B
        XCTAssertNil(result.groups["C"])  // C filtered out by HAVING
    }
    
    func testHavingWithAverage() throws {
        for i in 0..<30 {
            _ = try db.insert(BlazeDataRecord([
                "team": .string(i < 10 ? "A" : (i < 20 ? "B" : "C")),
                "priority": .int(i < 10 ? 5 : (i < 20 ? 3 : 1))
            ]))
        }
        
        // Filter to teams with avg priority > 2
        let result = try db.query()
            .groupBy("team")
            .avg("priority", as: "avg_priority")
            .having { $0.avg("avg_priority") ?? 0 > 2.0 }
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 2)  // A (5) and B (3), not C (1)
        XCTAssertNotNil(result.groups["A"])
        XCTAssertNotNil(result.groups["B"])
        XCTAssertNil(result.groups["C"])
    }
    
    // MARK: - Edge Cases
    
    func testAggregationOnEmptyDataset() throws {
        let result = try db.query()
            .count()
            .executeAggregation()
        
        XCTAssertEqual(result.count, 0)
    }
    
    func testAggregationOnMissingField() throws {
        _ = try db.insert(BlazeDataRecord(["other": .string("value")]))
        
        let result = try db.query()
            .sum("nonexistent", as: "sum")
            .executeAggregation()
        
        XCTAssertEqual(result.sum("sum"), 0.0)
    }
    
    func testGroupByOnMissingField() throws {
        _ = try db.insert(BlazeDataRecord(["field1": .string("value")]))
        _ = try db.insert(BlazeDataRecord(["field2": .string("value")]))
        
        let result = try db.query()
            .groupBy("status")
            .count()
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 1)  // All grouped as "null"
    }
    
    func testAggregationWithNilValues() throws {
        print("🔍 Starting testAggregationWithNilValues")
        
        print("  Insert 1...")
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        print("  ✅ Insert 1 complete")
        
        print("  Insert 2...")
        _ = try db.insert(BlazeDataRecord(["other": .string("no value field")]))
        print("  ✅ Insert 2 complete")
        
        print("  Insert 3...")
        _ = try db.insert(BlazeDataRecord(["value": .int(20)]))
        print("  ✅ Insert 3 complete")
        
        print("  Verifying records were inserted...")
        let allRecords = try db.fetchAll()
        print("    📊 Found \(allRecords.count) records in database")
        for (i, record) in allRecords.enumerated() {
            print("    Record \(i+1): \(record.storage)")
        }
        
        print("  Building query...")
        let query = db.query().sum("value", as: "sum")
        print("  ✅ Query built")
        
        print("  Executing aggregation...")
        let result = try query.executeAggregation()
        print("  ✅ Aggregation complete")
        print("    Result: \(result.values)")
        print("    Sum value: \(result.sum("sum") ?? -999.0)")
        
        print("  Checking result...")
        XCTAssertEqual(result.sum("sum"), 30.0)  // Skips nil values
        print("  ✅ Test complete")
    }
    
    func testMixedIntAndDouble() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["value": .double(20.5)]))
        
        let result = try db.query()
            .sum("value", as: "sum")
            .executeAggregation()
        
        XCTAssertEqual(result.sum("sum") ?? 0, 30.5, accuracy: 0.01)
    }
    
    func testDateMinMax() throws {
        let now = Date()
        let past = Date(timeIntervalSinceNow: -3600)
        let future = Date(timeIntervalSinceNow: 3600)
        
        let id1 = try db.insert(BlazeDataRecord(["created_at": .date(now)]))
        let id2 = try db.insert(BlazeDataRecord(["created_at": .date(past)]))
        let id3 = try db.insert(BlazeDataRecord(["created_at": .date(future)]))
        
        // Verify records were inserted
        let allRecords = try db.fetchAll()
        print("📊 Inserted \(allRecords.count) records")
        XCTAssertEqual(allRecords.count, 3, "Expected 3 records to be inserted")
        
        if allRecords.count >= 3 {
            print("Record 1 has created_at: \(allRecords[0].storage["created_at"] != nil)")
            print("Record 2 has created_at: \(allRecords[1].storage["created_at"] != nil)")
            print("Record 3 has created_at: \(allRecords[2].storage["created_at"] != nil)")
        }
        
        let result = try db.query()
            .aggregate([
                .min("created_at", as: "earliest"),
                .max("created_at", as: "latest")
            ])
            .executeAggregation()
        
        // Debug: Check what keys are available
        print("\n📊 Aggregation Result:")
        print("Available keys: \(Array(result.values.keys))")
        print("All values: \(result.values)")
        
        // Try ALL possible keys
        print("\nChecking different key patterns:")
        print("  result['earliest']: \(String(describing: result["earliest"]))")
        print("  result['latest']: \(String(describing: result["latest"]))")
        print("  result['min_created_at']: \(String(describing: result["min_created_at"]))")
        print("  result['max_created_at']: \(String(describing: result["max_created_at"]))")
        
        // CRITICAL: Inspect BEFORE the guard so we can see what's wrong
        if let earliestField = result["earliest"] {
            print("\n🔍 Detailed inspection of 'earliest' field:")
            print("  Field exists: YES")
            print("  Field type: \(earliestField)")
            print("  Field.dateValue: \(String(describing: earliestField.dateValue))")
            print("  Field.intValue: \(String(describing: earliestField.intValue))")
            print("  Field.stringValue: \(String(describing: earliestField.stringValue))")
            
            // Try to see what case it is
            switch earliestField {
            case .date(let d): print("  Case: .date(\(d)) ✅ CORRECT!")
            case .int(let i): print("  Case: .int(\(i)) ❌ WRONG TYPE! Should be .date")
            case .double(let d): print("  Case: .double(\(d)) ❌ WRONG TYPE! Should be .date")
            case .string(let s): print("  Case: .string(\(s)) ❌ WRONG TYPE! Should be .date")
            case .bool(let b): print("  Case: .bool(\(b)) ❌ WRONG TYPE! Should be .date")
            case .uuid(let u): print("  Case: .uuid(\(u)) ❌ WRONG TYPE! Should be .date")
            case .data(let d): print("  Case: .data(\(d.count) bytes) ❌ WRONG TYPE! Should be .date")
            case .array: print("  Case: .array ❌ WRONG TYPE! Should be .date")
            case .dictionary: print("  Case: .dictionary ❌ WRONG TYPE! Should be .date")
            }
        } else {
            print("\n🔍 'earliest' field is NIL!")
        }
        
        // Now check if it's stored with default naming or custom alias
        let earliestKey = result["earliest"] != nil ? "earliest" : "min_created_at"
        let latestKey = result["latest"] != nil ? "latest" : "max_created_at"
        
        print("\n🔑 Using keys: '\(earliestKey)' and '\(latestKey)'")
        
        // Access the fields
        guard let earliestField = result[earliestKey] else {
            XCTFail("Expected '\(earliestKey)' field to be present. Available keys: \(Array(result.values.keys))")
            return
        }
        
        guard let latestField = result[latestKey] else {
            XCTFail("Expected '\(latestKey)' field to be present. Available keys: \(Array(result.values.keys))")
            return
        }
        
        // Extract dates
        guard let earliest = earliestField.dateValue else {
            XCTFail("'\(earliestKey)' field exists but dateValue is nil! Field type: \(earliestField)")
            return
        }
        
        guard let latest = latestField.dateValue else {
            XCTFail("'\(latestKey)' field exists but dateValue is nil! Field type: \(latestField)")
            return
        }
        
        XCTAssertEqual(earliest, past, "Earliest date should be 1 hour in the past")
        XCTAssertEqual(latest, future, "Latest date should be 1 hour in the future")
    }
    
    // MARK: - Complex Queries
    
    func testGroupByWithFiltering() throws {
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "priority": .int(i % 5 + 1),
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "hours": .double(Double(i))
            ]))
        }
        
        // Filter to "open" bugs, then group by priority
        let result = try db.query()
            .where("status", equals: .string("open"))
            .groupBy("priority")
            .aggregate([
                .count(as: "count"),
                .sum("hours", as: "total_hours")
            ])
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 5)  // 5 priority levels
    }
    
    func testComplexAggregation() throws {
        // Real-world scenario: Bug tracker stats
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "type": .string("bug"),
                "status": .string(i % 3 == 0 ? "open" : (i % 3 == 1 ? "closed" : "in_progress")),
                "priority": .int(i % 5 + 1),
                "estimated_hours": .double(Double(i % 10 + 1)),
                "team_id": .string(i % 4 == 0 ? "team1" : (i % 4 == 1 ? "team2" : (i % 4 == 2 ? "team3" : "team4")))
            ]))
        }
        
        let result = try db.query()
            .where("type", equals: .string("bug"))
            .where("status", equals: .string("open"))
            .groupBy("team_id")
            .aggregate([
                .count(as: "bug_count"),
                .sum("estimated_hours", as: "total_hours"),
                .avg("priority", as: "avg_priority")
            ])
            .having { ($0.values["bug_count"]?.intValue ?? 0) > 50 }
            .executeGroupedAggregation()
        
        XCTAssertGreaterThan(result.groups.count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testAggregationPerformanceOn10k() throws {
        // Insert 10k records using batch insert (much faster)
        let records = (0..<10000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 3 == 0 ? "open" : (i % 3 == 1 ? "closed" : "in_progress")),
                "priority": .int(i % 5 + 1)
            ])
        }
        _ = try db.insertMany(records)
        print("  Inserted 10k records via batch insert")
        
        let start = Date()
        let result = try db.query()
            .groupBy("status")
            .aggregate([
                .count(as: "count"),
                .avg("priority", as: "avg_priority")
            ])
            .executeGroupedAggregation()
        let duration = Date().timeIntervalSince(start)
        
        print("  Aggregation completed in \(String(format: "%.2f", duration))s")
        
        XCTAssertEqual(result.groups.count, 3)
        XCTAssertLessThan(duration, 3.0, "Aggregation on 10k records should be < 3s")
    }
    
    func testMemoryEfficientAggregation() throws {
        // Insert large dataset using batch insert
        let records = (0..<5000).map { i in
            BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        print("  Inserted 5k records via batch insert")
        
        // Aggregation should not load all records into final result
        let result = try db.query()
            .groupBy("status")
            .count()
            .executeGroupedAggregation()
        
        // Result is tiny (2 groups) even though 5000 records
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.totalCount, 5000)
    }
    
    // MARK: - Error Handling
    
    func testAggregationWithoutAggregationsFails() throws {
        XCTAssertThrowsError(try db.query().executeAggregation()) { error in
            XCTAssert(error is BlazeDBError)
        }
    }
    
    func testGroupByWithoutGroupByFails() throws {
        XCTAssertThrowsError(try db.query().count().executeGroupedAggregation()) { error in
            XCTAssert(error is BlazeDBError)
        }
    }
    
    func testGroupByWithoutAggregationsFails() throws {
        XCTAssertThrowsError(try db.query().groupBy("status").executeGroupedAggregation()) { error in
            XCTAssert(error is BlazeDBError)
        }
    }
    
    // MARK: - Real-World Scenarios
    
    func testBugTrackerDashboard() throws {
        // Simulate real bug tracker data
        for i in 0..<500 {
            _ = try db.insert(BlazeDataRecord([
                "type": .string("bug"),
                "status": .string(i % 4 == 0 ? "open" : (i % 4 == 1 ? "closed" : (i % 4 == 2 ? "in_progress" : "verified"))),
                "priority": .int(i % 5 + 1),
                "severity": .string(i % 3 == 0 ? "high" : (i % 3 == 1 ? "medium" : "low")),
                "estimated_hours": .double(Double(i % 20 + 1))
            ]))
        }
        
        // Dashboard query: Count and average priority by status
        let statusStats = try db.query()
            .where("type", equals: .string("bug"))
            .groupBy("status")
            .aggregate([
                .count(as: "count"),
                .avg("priority", as: "avg_priority")
            ])
            .executeGroupedAggregation()
        
        XCTAssertEqual(statusStats.groups.count, 4)
        
        // Severity breakdown
        let severityStats = try db.query()
            .where("type", equals: .string("bug"))
            .where("status", equals: .string("open"))
            .groupBy("severity")
            .count()
            .executeGroupedAggregation()
        
        XCTAssertGreaterThan(severityStats.groups.count, 0)
    }
    
    func testTimeSeries() throws {
        let calendar = Calendar.current
        for i in 0..<30 {
            let date = calendar.date(byAdding: .day, value: -i, to: Date())!
            _ = try db.insert(BlazeDataRecord([
                "created_at": .date(date),
                "value": .int(i)
            ]))
        }
        
        // Note: Full time series would need date bucketing (future feature)
        // For now, test basic date aggregation
        let result = try db.query()
            .aggregate([
                .count(as: "count"),  // Use standard name for convenience property
                .min("created_at", as: "earliest"),
                .max("created_at", as: "latest")
            ])
            .executeAggregation()
        
        XCTAssertEqual(result.count ?? 0, 30)
        XCTAssertNotNil(result["earliest"]?.dateValue, "Min date should be present")
        XCTAssertNotNil(result["latest"]?.dateValue, "Max date should be present")
    }
    
    // MARK: - Stress Tests
    
    func testLargeGroupCount() throws {
        // Many small groups
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "group": .string("group_\(i % 100)"),  // 100 groups
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        let result = try db.query()
            .groupBy("group")
            .count()
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 100)
    }
    
    func testFewLargeGroups() throws {
        // Few large groups - use batch insert for speed
        let records = (0..<10000).map { i in
            BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        print("  Inserted 10k records via batch insert")
        
        let result = try db.query()
            .groupBy("status")
            .aggregate([
                .count(as: "count"),
                .sum("value", as: "sum")
            ])
            .executeGroupedAggregation()
        
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.totalCount, 10000)
    }
    
    // MARK: - Performance Metrics
    
    /// Measure COUNT aggregation performance
    func testPerformance_CountAggregation() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord(["status": .string(i % 3 == 0 ? "open" : "closed")])
        }
        _ = try db.insertMany(records)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                _ = try db.query()
                    .count(as: "total")
                    .execute()
            } catch {
                XCTFail("COUNT aggregation failed: \(error)")
            }
        }
    }
    
    /// Measure SUM aggregation performance
    func testPerformance_SumAggregation() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord(["value": .double(Double(i))])
        }
        _ = try db.insertMany(records)
        
        measure(metrics: [XCTClockMetric()]) {
            do {
                _ = try db.query()
                    .sum("value", as: "total")
                    .execute()
            } catch {
                XCTFail("SUM aggregation failed: \(error)")
            }
        }
    }
    
    /// Measure GROUP BY performance
    func testPerformance_GroupBy() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "category": .string("cat_\(i % 10)"),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                _ = try db.query()
                    .groupBy("category")
                    .count(as: "total")
                    .execute()
            } catch {
                XCTFail("GROUP BY failed: \(error)")
            }
        }
    }
    
    /// Measure complex multi-aggregation with GROUP BY
    func testPerformance_ComplexGroupedAggregation() throws {
        // Setup: Insert 200 records
        let records = (0..<200).map { i in
            BlazeDataRecord([
                "priority": .int(i % 5 + 1),
                "hours": .double(Double(i)),
                "cost": .double(Double(i) * 50)
            ])
        }
        _ = try db.insertMany(records)
        
        measure(metrics: [XCTClockMetric()]) {
            do {
                _ = try db.query()
                    .groupBy("priority")
                    .aggregate([
                        .count(as: "count"),
                        .sum("hours", as: "total_hours"),
                        .avg("cost", as: "avg_cost"),
                        .min("cost", as: "min_cost"),
                        .max("cost", as: "max_cost")
                    ])
                    .execute()
            } catch {
                XCTFail("Complex aggregation failed: \(error)")
            }
        }
    }
}

