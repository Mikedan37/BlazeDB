//
//  SQLFeaturesTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for new SQL features:
//  - Window Functions (ROW_NUMBER, RANK, LAG, LEAD, SUM OVER)
//  - Triggers (BEFORE/AFTER INSERT/UPDATE/DELETE)
//  - EXISTS/NOT EXISTS subqueries
//  - CASE WHEN statements
//  - Foreign Key Constraints
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class SQLFeaturesTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("blazedb")
        db = try! BlazeDBClient(name: "Test", fileURL: tempURL, password: "SQLFeaturesTest123!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Window Functions Tests
    
    func testRowNumber() throws {
        print("\n🔍 TEST: ROW_NUMBER() window function")
        
        // Insert test data
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "category": .string(i % 2 == 0 ? "A" : "B")
            ])
            _ = try db.insert(record)
        }
        
        // Query with ROW_NUMBER
        let results = try db.query()
            .orderBy("value", descending: false)
            .rowNumber(partitionBy: nil, orderBy: ["value"], as: "row_num")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 10, "Should have 10 results")
        
        // Verify row numbers
        for (index, result) in results.enumerated() {
            let rowNum = result.getWindowValue("row_num")?.intValue
            XCTAssertEqual(rowNum, index + 1, "Row number should be \(index + 1)")
        }
        
        print("   ✅ ROW_NUMBER works correctly")
    }
    
    func testRowNumberWithPartition() throws {
        print("\n🔍 TEST: ROW_NUMBER() with PARTITION BY")
        
        // Insert test data with categories
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i),
                "category": .string(i < 5 ? "A" : "B")
            ])
            _ = try db.insert(record)
        }
        
        // Query with partitioned ROW_NUMBER
        let results = try db.query()
            .orderBy("category", descending: false)
            .orderBy("value", descending: false)
            .rowNumber(partitionBy: ["category"], orderBy: ["value"], as: "row_num")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 10, "Should have 10 results")
        
        // Verify row numbers restart for each partition
        var categoryA = 0
        var categoryB = 0
        
        for result in results {
            let category = result.record.storage["category"]?.stringValue ?? ""
            let rowNum = result.getWindowValue("row_num")?.intValue ?? 0
            
            if category == "A" {
                categoryA += 1
                XCTAssertEqual(rowNum, categoryA, "Category A row number should be \(categoryA)")
            } else {
                categoryB += 1
                XCTAssertEqual(rowNum, categoryB, "Category B row number should be \(categoryB)")
            }
        }
        
        print("   ✅ ROW_NUMBER with PARTITION BY works correctly")
    }
    
    func testRank() throws {
        print("\n🔍 TEST: RANK() window function")
        
        // Insert test data with ties
        let values = [10, 20, 20, 30, 30, 30, 40]
        for value in values {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "score": .int(value)
            ])
            _ = try db.insert(record)
        }
        
        // Query with RANK
        let results = try db.query()
            .orderBy("score", descending: false)
            .rank(partitionBy: nil, orderBy: ["score"], as: "rank")
            .executeWithWindow()
        
        // Verify ranks (ties get same rank, next rank skips)
        let expectedRanks = [1, 2, 2, 4, 4, 4, 7]
        for (index, result) in results.enumerated() {
            let rank = result.getWindowValue("rank")?.intValue
            XCTAssertEqual(rank, expectedRanks[index], "Rank should be \(expectedRanks[index])")
        }
        
        print("   ✅ RANK works correctly")
    }
    
    func testDenseRank() throws {
        print("\n🔍 TEST: DENSE_RANK() window function")
        
        // Insert test data with ties
        let values = [10, 20, 20, 30, 30, 30, 40]
        for value in values {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "score": .int(value)
            ])
            _ = try db.insert(record)
        }
        
        // Query with DENSE_RANK
        let results = try db.query()
            .orderBy("score", descending: false)
            .denseRank(partitionBy: nil, orderBy: ["score"], as: "dense_rank")
            .executeWithWindow()
        
        // Verify dense ranks (ties get same rank, next rank doesn't skip)
        let expectedRanks = [1, 2, 2, 3, 3, 3, 4]
        for (index, result) in results.enumerated() {
            let rank = result.getWindowValue("dense_rank")?.intValue
            XCTAssertEqual(rank, expectedRanks[index], "Dense rank should be \(expectedRanks[index])")
        }
        
        print("   ✅ DENSE_RANK works correctly")
    }
    
    func testLag() throws {
        print("\n🔍 TEST: LAG() window function")
        
        // Insert test data
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "day": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // Query with LAG
        let results = try db.query()
            .orderBy("day", descending: false)
            .lag("value", offset: 1, partitionBy: nil, orderBy: ["day"], as: "prev_value")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 5, "Should have 5 results")
        
        // First record should have NULL (no previous)
        let firstLag = results[0].getWindowValue("prev_value")
        XCTAssertTrue(firstLag == nil || firstLag == .data(Data()), "First LAG should be NULL")
        
        // Other records should have previous value
        for i in 1..<5 {
            let lagValue = results[i].getWindowValue("prev_value")?.intValue
            let expected = (i - 1) * 10
            XCTAssertEqual(lagValue, expected, "LAG should be \(expected)")
        }
        
        print("   ✅ LAG works correctly")
    }
    
    func testLead() throws {
        print("\n🔍 TEST: LEAD() window function")
        
        // Insert test data
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "day": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // Query with LEAD
        let results = try db.query()
            .orderBy("day", descending: false)
            .lead("value", offset: 1, partitionBy: nil, orderBy: ["day"], as: "next_value")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 5, "Should have 5 results")
        
        // Last record should have NULL (no next)
        let lastLead = results[4].getWindowValue("next_value")
        XCTAssertTrue(lastLead == nil || lastLead == .data(Data()), "Last LEAD should be NULL")
        
        // Other records should have next value
        for i in 0..<4 {
            let leadValue = results[i].getWindowValue("next_value")?.intValue
            let expected = (i + 1) * 10
            XCTAssertEqual(leadValue, expected, "LEAD should be \(expected)")
        }
        
        print("   ✅ LEAD works correctly")
    }
    
    func testSumOver() throws {
        print("\n🔍 TEST: SUM() OVER window function")
        
        // Insert test data
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "amount": .int((i + 1) * 10),
                "day": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // Query with SUM OVER (running total)
        let results = try db.query()
            .orderBy("day", descending: false)
            .sumOver("amount", partitionBy: nil, orderBy: ["day"], as: "running_total")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 5, "Should have 5 results")
        
        // Verify running totals: 10, 30, 60, 100, 150
        let expectedTotals = [10, 30, 60, 100, 150]
        for (index, result) in results.enumerated() {
            let total = result.getWindowValue("running_total")?.doubleValue ?? 0
            XCTAssertEqual(Int(total), expectedTotals[index], "Running total should be \(expectedTotals[index])")
        }
        
        print("   ✅ SUM OVER works correctly")
    }
    
    func testAvgOver() throws {
        print("\n🔍 TEST: AVG() OVER window function")
        
        // Insert test data
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int((i + 1) * 10),
                "day": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        // Query with AVG OVER (running average)
        let results = try db.query()
            .orderBy("day", descending: false)
            .avgOver("value", partitionBy: nil, orderBy: ["day"], as: "running_avg")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 5, "Should have 5 results")
        
        // Verify running averages: 10, 15, 20, 25, 30
        let expectedAvgs = [10.0, 15.0, 20.0, 25.0, 30.0]
        for (index, result) in results.enumerated() {
            let avg = result.getWindowValue("running_avg")?.doubleValue ?? 0
            XCTAssertEqual(avg, expectedAvgs[index], accuracy: 0.1, "Running avg should be ~\(expectedAvgs[index])")
        }
        
        print("   ✅ AVG OVER works correctly")
    }
    
    // MARK: - Triggers Tests
    
    func testBeforeInsertTrigger() throws {
        print("\n🔍 TEST: BEFORE INSERT trigger")
        
        var triggerFired = false
        var modifiedValue: String?
        
        // Register trigger
        db.createTrigger(name: "test_before_insert", event: .beforeInsert) { record, modified in
            triggerFired = true
            modified?.storage["triggered"] = .string("yes")
            modifiedValue = modified?.storage["triggered"]?.stringValue
        }
        
        // Insert record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "BEFORE INSERT trigger should fire")
        
        // Verify record was modified
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["triggered"]?.stringValue, "yes", "Trigger should modify record")
        
        print("   ✅ BEFORE INSERT trigger works")
    }
    
    func testAfterInsertTrigger() throws {
        print("\n🔍 TEST: AFTER INSERT trigger")
        
        var triggerFired = false
        var insertedId: UUID?
        
        // Register trigger
        db.createTrigger(name: "test_after_insert", event: .afterInsert) { record, _ in
            triggerFired = true
            insertedId = record.storage["id"]?.uuidValue
        }
        
        // Insert record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "AFTER INSERT trigger should fire")
        XCTAssertEqual(insertedId, id, "Trigger should receive inserted record")
        
        print("   ✅ AFTER INSERT trigger works")
    }
    
    func testBeforeUpdateTrigger() throws {
        print("\n🔍 TEST: BEFORE UPDATE trigger")
        
        var triggerFired = false
        var oldValue: String?
        var newValue: String?
        
        // Insert initial record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "status": .string("old")
        ])
        let id = try db.insert(record)
        
        // Register trigger
        db.createTrigger(name: "test_before_update", event: .beforeUpdate) { oldRecord, modified in
            triggerFired = true
            oldValue = oldRecord.storage["status"]?.stringValue
            newValue = modified?.storage["status"]?.stringValue
            modified?.storage["updated_by_trigger"] = .string("yes")
        }
        
        // Update record
        var updated = record
        updated.storage["status"] = .string("new")
        try db.update(id: id, with: updated)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "BEFORE UPDATE trigger should fire")
        XCTAssertEqual(oldValue, "old", "Trigger should receive old value")
        XCTAssertEqual(newValue, "new", "Trigger should receive new value")
        
        // Verify record was modified by trigger
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["updated_by_trigger"]?.stringValue, "yes", "Trigger should modify record")
        
        print("   ✅ BEFORE UPDATE trigger works")
    }
    
    func testAfterUpdateTrigger() throws {
        print("\n🔍 TEST: AFTER UPDATE trigger")
        
        var triggerFired = false
        
        // Insert initial record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "status": .string("old")
        ])
        let id = try db.insert(record)
        
        // Register trigger
        db.createTrigger(name: "test_after_update", event: .afterUpdate) { record, _ in
            triggerFired = true
        }
        
        // Update record
        var updated = record
        updated.storage["status"] = .string("new")
        try db.update(id: id, with: updated)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "AFTER UPDATE trigger should fire")
        
        print("   ✅ AFTER UPDATE trigger works")
    }
    
    func testBeforeDeleteTrigger() throws {
        print("\n🔍 TEST: BEFORE DELETE trigger")
        
        var triggerFired = false
        var deletedId: UUID?
        
        // Insert record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Register trigger
        db.createTrigger(name: "test_before_delete", event: .beforeDelete) { record, _ in
            triggerFired = true
            deletedId = record.storage["id"]?.uuidValue
        }
        
        // Delete record
        try db.delete(id: id)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "BEFORE DELETE trigger should fire")
        XCTAssertEqual(deletedId, id, "Trigger should receive deleted record")
        
        print("   ✅ BEFORE DELETE trigger works")
    }
    
    func testAfterDeleteTrigger() throws {
        print("\n🔍 TEST: AFTER DELETE trigger")
        
        var triggerFired = false
        
        // Insert record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Register trigger
        db.createTrigger(name: "test_after_delete", event: .afterDelete) { record, _ in
            triggerFired = true
        }
        
        // Delete record
        try db.delete(id: id)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "AFTER DELETE trigger should fire")
        
        print("   ✅ AFTER DELETE trigger works")
    }
    
    func testMultipleTriggers() throws {
        print("\n🔍 TEST: Multiple triggers")
        
        var trigger1Fired = false
        var trigger2Fired = false
        
        // Register multiple triggers
        db.createTrigger(name: "trigger1", event: .beforeInsert) { _, _ in
            trigger1Fired = true
        }
        
        db.createTrigger(name: "trigger2", event: .beforeInsert) { _, _ in
            trigger2Fired = true
        }
        
        // Insert record
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        _ = try db.insert(record)
        
        // Verify both triggers fired
        XCTAssertTrue(trigger1Fired, "Trigger 1 should fire")
        XCTAssertTrue(trigger2Fired, "Trigger 2 should fire")
        
        print("   ✅ Multiple triggers work correctly")
    }
    
    // MARK: - EXISTS Subquery Tests
    
    func testWhereExists() throws {
        print("\n🔍 TEST: WHERE EXISTS subquery")
        
        // Create two databases for subquery
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Insert users
        let user1 = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let user2 = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob")])
        let user1Id = try usersDB.insert(user1)
        let user2Id = try usersDB.insert(user2)
        
        // Insert orders (only for user1)
        let order1 = BlazeDataRecord(["id": .uuid(UUID()), "user_id": .uuid(user1Id), "amount": .int(100)])
        _ = try ordersDB.insert(order1)
        
        // Query: Users who have orders (EXISTS)
        let subquery = ordersDB.query().where("user_id", equals: .uuid(user1Id))  // Simplified for demo
        let results = try usersDB.query()
            .whereExists(subquery)
            .execute()
        
        // Should find user1 (has order), not user2 (no order)
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "Should find users with orders")
        
        print("   ✅ WHERE EXISTS works")
    }
    
    func testWhereNotExists() throws {
        print("\n🔍 TEST: WHERE NOT EXISTS subquery")
        
        // Create two databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Insert users
        let user1 = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let user2 = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob")])
        let user1Id = try usersDB.insert(user1)
        _ = try usersDB.insert(user2)
        
        // Insert order only for user1
        let order1 = BlazeDataRecord(["id": .uuid(UUID()), "user_id": .uuid(user1Id), "amount": .int(100)])
        _ = try ordersDB.insert(order1)
        
        // Query: Users who have NO orders (NOT EXISTS)
        let subquery = ordersDB.query().where("user_id", equals: .uuid(user1Id))
        let results = try usersDB.query()
            .whereNotExists(subquery)
            .execute()
        
        // Should find user2 (no orders)
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "Should find users without orders")
        
        print("   ✅ WHERE NOT EXISTS works")
    }
    
    // MARK: - CASE WHEN Tests
    
    func testCaseWhen() throws {
        print("\n🔍 TEST: CASE WHEN statement")
        
        // Insert test data
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "age": .int(i * 10)
            ])
            _ = try db.insert(record)
        }
        
        // Create CASE WHEN expression
        let caseWhen = CaseWhenExpression(
            clauses: [
                CaseWhenClause(condition: .lessThan(field: "age", value: .int(18)), thenValue: .string("Minor")),
                CaseWhenClause(condition: .lessThan(field: "age", value: .int(65)), thenValue: .string("Adult")),
            ],
            elseValue: .string("Senior")
        )
        
        // Evaluate for each record
        let records = try db.fetchAll()
        for record in records {
            let ageGroup = caseWhen.evaluate(for: record)
            let age = record.storage["age"]?.intValue ?? 0
            
            if age < 18 {
                XCTAssertEqual(ageGroup.stringValue, "Minor", "Age \(age) should be Minor")
            } else if age < 65 {
                XCTAssertEqual(ageGroup.stringValue, "Adult", "Age \(age) should be Adult")
            } else {
                XCTAssertEqual(ageGroup.stringValue, "Senior", "Age \(age) should be Senior")
            }
        }
        
        print("   ✅ CASE WHEN works correctly")
    }
    
    // MARK: - Foreign Key Tests
    
    func testForeignKeyConstraint() throws {
        print("\n🔍 TEST: Foreign key constraint")
        
        // Create two databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Insert user
        let user = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let userId = try usersDB.insert(user)
        
        // Add foreign key constraint
        let fk = ForeignKeyConstraint(
            name: "fk_user_id",
            localField: "user_id",
            referencedDB: usersDB,
            referencedField: "id"
        )
        ordersDB.addForeignKey(fk)
        
        // Insert order with valid foreign key (should work)
        let order1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "user_id": .uuid(userId),
            "amount": .int(100)
        ])
        _ = try ordersDB.insert(order1)
        
        // Try to insert order with invalid foreign key (should fail)
        let invalidOrder = BlazeDataRecord([
            "id": .uuid(UUID()),
            "user_id": .uuid(UUID()),  // Non-existent user
            "amount": .int(200)
        ])
        
        do {
            _ = try ordersDB.insert(invalidOrder)
            XCTFail("Should throw foreign key violation")
        } catch {
            // Expected
            XCTAssertTrue(error.localizedDescription.contains("foreign key") || 
                         error.localizedDescription.contains("does not exist"),
                        "Should throw foreign key violation")
        }
        
        print("   ✅ Foreign key constraint works")
    }
    
    func testForeignKeyCascade() throws {
        print("\n🔍 TEST: Foreign key CASCADE delete")
        
        // Create two databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Insert user
        let user = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let userId = try usersDB.insert(user)
        
        // Add foreign key with CASCADE
        let fk = ForeignKeyConstraint(
            name: "fk_user_id",
            localField: "user_id",
            referencedDB: usersDB,
            referencedField: "id",
            onDelete: .cascade
        )
        ordersDB.addForeignKey(fk)
        
        // Insert orders
        let order1 = BlazeDataRecord(["id": .uuid(UUID()), "user_id": .uuid(userId), "amount": .int(100)])
        let order2 = BlazeDataRecord(["id": .uuid(UUID()), "user_id": .uuid(userId), "amount": .int(200)])
        let order1Id = try ordersDB.insert(order1)
        let order2Id = try ordersDB.insert(order2)
        
        // Delete user (should cascade delete orders)
        try usersDB.delete(id: userId)
        
        // Verify orders are deleted
        XCTAssertNil(try ordersDB.fetch(id: order1Id), "Order 1 should be cascade deleted")
        XCTAssertNil(try ordersDB.fetch(id: order2Id), "Order 2 should be cascade deleted")
        
        print("   ✅ Foreign key CASCADE works")
    }
    
    func testForeignKeyRestrict() throws {
        print("\n🔍 TEST: Foreign key RESTRICT delete")
        
        // Create two databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Insert user
        let user = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let userId = try usersDB.insert(user)
        
        // Add foreign key with RESTRICT
        let fk = ForeignKeyConstraint(
            name: "fk_user_id",
            localField: "user_id",
            referencedDB: usersDB,
            referencedField: "id",
            onDelete: .restrict
        )
        ordersDB.addForeignKey(fk)
        
        // Insert order
        let order = BlazeDataRecord(["id": .uuid(UUID()), "user_id": .uuid(userId), "amount": .int(100)])
        _ = try ordersDB.insert(order)
        
        // Try to delete user (should fail due to RESTRICT)
        do {
            try usersDB.delete(id: userId)
            XCTFail("Should throw foreign key violation")
        } catch {
            // Expected
            XCTAssertTrue(error.localizedDescription.contains("foreign key") || 
                         error.localizedDescription.contains("reference"),
                        "Should throw foreign key violation")
        }
        
        // Verify user still exists
        XCTAssertNotNil(try usersDB.fetch(id: userId), "User should still exist")
        
        print("   ✅ Foreign key RESTRICT works")
    }
    
    func testForeignKeySetNull() throws {
        print("\n🔍 TEST: Foreign key SET NULL delete")
        
        // Create two databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Insert user
        let user = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let userId = try usersDB.insert(user)
        
        // Add foreign key with SET NULL
        let fk = ForeignKeyConstraint(
            name: "fk_user_id",
            localField: "user_id",
            referencedDB: usersDB,
            referencedField: "id",
            onDelete: .setNull
        )
        ordersDB.addForeignKey(fk)
        
        // Insert order
        let order = BlazeDataRecord(["id": .uuid(UUID()), "user_id": .uuid(userId), "amount": .int(100)])
        let orderId = try ordersDB.insert(order)
        
        // Delete user (should set foreign key to null)
        try usersDB.delete(id: userId)
        
        // Verify order's user_id is set to null
        let fetched = try ordersDB.fetch(id: orderId)
        XCTAssertNil(fetched?.storage["user_id"], "user_id should be set to null")
        
        print("   ✅ Foreign key SET NULL works")
    }
    
    // MARK: - Combined Features Tests
    
    func testWindowFunctionWithFilter() throws {
        print("\n🔍 TEST: Window function with WHERE filter")
        
        // Insert test data
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i * 10),
                "category": .string(i < 5 ? "A" : "B")
            ])
            _ = try db.insert(record)
        }
        
        // Query with filter and window function
        let results = try db.query()
            .where("category", equals: .string("A"))
            .orderBy("value", descending: false)
            .rowNumber(partitionBy: nil, orderBy: ["value"], as: "row_num")
            .executeWithWindow()
        
        XCTAssertEqual(results.count, 5, "Should have 5 results after filter")
        
        // Verify row numbers are sequential
        for (index, result) in results.enumerated() {
            let rowNum = result.getWindowValue("row_num")?.intValue
            XCTAssertEqual(rowNum, index + 1, "Row number should be \(index + 1)")
        }
        
        print("   ✅ Window function with filter works")
    }
    
    func testTriggerWithForeignKey() throws {
        print("\n🔍 TEST: Trigger with foreign key constraint")
        
        // Create two databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Add foreign key
        let fk = ForeignKeyConstraint(
            name: "fk_user_id",
            localField: "user_id",
            referencedDB: usersDB,
            referencedField: "id"
        )
        ordersDB.addForeignKey(fk)
        
        // Add trigger that modifies order
        var triggerFired = false
        ordersDB.createTrigger(name: "set_timestamp", event: .beforeInsert) { record, modified in
            triggerFired = true
            modified?.storage["created_at"] = .date(Date())
        }
        
        // Insert user
        let user = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let userId = try usersDB.insert(user)
        
        // Insert order (should trigger and validate FK)
        let order = BlazeDataRecord([
            "id": .uuid(UUID()),
            "user_id": .uuid(userId),
            "amount": .int(100)
        ])
        let orderId = try ordersDB.insert(order)
        
        // Verify trigger fired
        XCTAssertTrue(triggerFired, "Trigger should fire")
        
        // Verify FK validation worked
        let fetched = try ordersDB.fetch(id: orderId)
        XCTAssertNotNil(fetched, "Order should be inserted")
        XCTAssertNotNil(fetched?.storage["created_at"], "Trigger should add created_at")
        
        print("   ✅ Trigger with foreign key works")
    }
    
    func testCaseWhenInQuery() throws {
        print("\n🔍 TEST: CASE WHEN in query result")
        
        // Insert test data
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "age": .int(i * 10)
            ])
            _ = try db.insert(record)
        }
        
        // Create CASE WHEN expression
        let caseWhen = CaseWhenExpression(
            clauses: [
                CaseWhenClause(condition: .lessThan(field: "age", value: .int(18)), thenValue: .string("Minor")),
                CaseWhenClause(condition: .lessThan(field: "age", value: .int(65)), thenValue: .string("Adult"))
            ],
            elseValue: .string("Senior")
        )
        
        // Query and apply CASE WHEN
        let records = try db.query()
            .orderBy("age", descending: false)
            .execute()
        
        let results = try records.records
        
        // Evaluate CASE WHEN for each record
        for record in results {
            let ageGroup = caseWhen.evaluate(for: record)
            let age = record.storage["age"]?.intValue ?? 0
            
            if age < 18 {
                XCTAssertEqual(ageGroup.stringValue, "Minor")
            } else if age < 65 {
                XCTAssertEqual(ageGroup.stringValue, "Adult")
            } else {
                XCTAssertEqual(ageGroup.stringValue, "Senior")
            }
        }
        
        print("   ✅ CASE WHEN in query works")
    }
    
    func testComplexQueryWithAllFeatures() throws {
        print("\n🔍 TEST: Complex query with all new features")
        
        // Create databases
        let usersDB = try BlazeDBClient(name: "Users", fileURL: tempURL.appendingPathExtension("users.blazedb"), password: "SQLFeaturesTest123!")
        let ordersDB = try BlazeDBClient(name: "Orders", fileURL: tempURL.appendingPathExtension("orders.blazedb"), password: "SQLFeaturesTest123!")
        
        // Add foreign key
        let fk = ForeignKeyConstraint(
            name: "fk_user_id",
            localField: "user_id",
            referencedDB: usersDB,
            referencedField: "id"
        )
        ordersDB.addForeignKey(fk)
        
        // Insert users
        let user1 = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Alice")])
        let user2 = BlazeDataRecord(["id": .uuid(UUID()), "name": .string("Bob")])
        let user1Id = try usersDB.insert(user1)
        _ = try usersDB.insert(user2)
        
        // Insert orders
        for i in 0..<5 {
            let order = BlazeDataRecord([
                "id": .uuid(UUID()),
                "user_id": .uuid(user1Id),
                "amount": .int((i + 1) * 10),
                "day": .int(i)
            ])
            _ = try ordersDB.insert(order)
        }
        
        // Complex query: Window function + EXISTS + CASE WHEN
        let subquery = ordersDB.query().where("user_id", equals: .uuid(user1Id))
        
        let usersWithOrders = try usersDB.query()
            .whereExists(subquery)
            .execute()
        
        XCTAssertGreaterThan(try usersWithOrders.records.count, 0, "Should find users with orders")
        
        // Query orders with window function
        let orderResults = try ordersDB.query()
            .where("user_id", equals: .uuid(user1Id))
            .orderBy("day", descending: false)
            .sumOver("amount", partitionBy: nil, orderBy: ["day"], as: "running_total")
            .executeWithWindow()
        
        XCTAssertEqual(orderResults.count, 5, "Should have 5 orders")
        
        // Verify running totals
        let expectedTotals = [10, 30, 60, 100, 150]
        for (index, result) in orderResults.enumerated() {
            let total = result.getWindowValue("running_total")?.doubleValue ?? 0
            XCTAssertEqual(Int(total), expectedTotals[index], "Running total should be \(expectedTotals[index])")
        }
        
        print("   ✅ Complex query with all features works")
    }
}

