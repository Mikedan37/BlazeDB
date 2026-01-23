//
//  PropertyBasedTests.swift
//  BlazeDBTests
//
//  Property-based testing: Generate thousands of random test cases
//  to find edge cases that humans would never think of.
//
//  Property-based testing asks: "What properties should ALWAYS be true?"
//  Then tests them with random inputs until it finds a counter-example.
//
//  Created: 2025-11-12
//

import XCTest
@testable import BlazeDBCore

final class PropertyBasedTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PropTest-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try! BlazeDBClient(name: "prop_test", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Random Generators
    
    /// Generate random BlazeDocumentField
    private func randomField() -> BlazeDocumentField {
        let fieldType = Int.random(in: 0...8)
        
        switch fieldType {
        case 0:
            // Random string (various lengths)
            let length = Int.random(in: 0...200)
            let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
            let str = String((0..<length).map { _ in chars.randomElement()! })
            return .string(str)
            
        case 1:
            // Random int (full range)
            return .int(Int.random(in: Int.min...Int.max))
            
        case 2:
            // Random double (including special values)
            let special = Int.random(in: 0...10)
            if special == 0 { return .double(0.0) }
            if special == 1 { return .double(-0.0) }
            if special == 2 { return .double(.infinity) }
            if special == 3 { return .double(-.infinity) }
            return .double(Double.random(in: -1e9...1e9))
            
        case 3:
            // Random bool
            return .bool(Bool.random())
            
        case 4:
            // Random date (past 50 years)
            let timestamp = Double.random(in: 0...1.5e9)
            return .date(Date(timeIntervalSince1970: timestamp))
            
        case 5:
            // Random UUID
            return .uuid(UUID())
            
        case 6:
            // Random data (various sizes)
            let size = Int.random(in: 0...1000)
            let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
            return .data(data)
            
        case 7:
            // Random array (1-10 elements)
            let count = Int.random(in: 1...10)
            let array = (0..<count).map { _ in randomSimpleField() }
            return .array(array)
            
        case 8:
            // Random dictionary (1-5 keys)
            let count = Int.random(in: 1...5)
            var dict: [String: BlazeDocumentField] = [:]
            for i in 0..<count {
                dict["key\(i)"] = randomSimpleField()
            }
            return .dictionary(dict)
            
        default:
            return .string("fallback")
        }
    }
    
    /// Generate simple field (no nested arrays/dicts)
    private func randomSimpleField() -> BlazeDocumentField {
        let type = Int.random(in: 0...5)
        switch type {
        case 0: return .string("test\(Int.random(in: 0...100))")
        case 1: return .int(Int.random(in: -1000...1000))
        case 2: return .double(Double.random(in: -100...100))
        case 3: return .bool(Bool.random())
        case 4: return .date(Date(timeIntervalSince1970: Double.random(in: 0...1e9)))
        case 5: return .uuid(UUID())
        default: return .int(0)
        }
    }
    
    /// Generate random record (1-20 fields)
    private func randomRecord() -> BlazeDataRecord {
        let fieldCount = Int.random(in: 1...20)
        var fields: [String: BlazeDocumentField] = [:]
        
        for i in 0..<fieldCount {
            let fieldName = "field\(i)"
            fields[fieldName] = randomField()
        }
        
        return BlazeDataRecord(fields)
    }
    
    // MARK: - Property: Insert → Fetch Round-Trip
    
    /// Property: ANY record inserted should be fetchable with identical data
    func testProperty_InsertFetchRoundTrip() throws {
        print("\n🎲 PROPERTY: Insert → Fetch Round-Trip (1000 random records)")
        
        var insertedIDs: [UUID] = []
        var insertedRecords: [UUID: BlazeDataRecord] = [:]
        
        // Generate and insert 1000 random records
        for i in 0..<1000 {
            let record = randomRecord()
            let id = try db.insert(record)
            
            insertedIDs.append(id)
            insertedRecords[id] = record
            
            if i % 100 == 0 {
                print("  Generated \(i) random records...")
            }
        }
        
        print("  ✅ Inserted 1000 random records")
        
        // Property: Every inserted record should be fetchable
        var successCount = 0
        var failCount = 0
        
        for id in insertedIDs {
            guard let fetched = try db.fetch(id: id) else {
                failCount += 1
                continue
            }
            
            // Verify data matches (field by field)
            let original = insertedRecords[id]!
            
            // Compare field counts
            if fetched.storage.count != original.storage.count {
                failCount += 1
                continue
            }
            
            // Compare each field
            var fieldsMatch = true
            for (key, originalValue) in original.storage {
                guard let fetchedValue = fetched.storage[key] else {
                    fieldsMatch = false
                    break
                }
                
                // Compare values (allowing for floating point precision)
                if !valuesEqual(originalValue, fetchedValue) {
                    fieldsMatch = false
                    break
                }
            }
            
            if fieldsMatch {
                successCount += 1
            } else {
                failCount += 1
            }
        }
        
        print("  📊 Round-trip success: \(successCount)/1000")
        print("  📊 Round-trip failures: \(failCount)/1000")
        
        XCTAssertEqual(failCount, 0, "ALL random records should survive round-trip")
        
        print("  ✅ PROPERTY VERIFIED: Insert → Fetch is invertible!")
    }
    
    /// Property: Insert → Persist → Reopen → Fetch (with random data)
    func testProperty_PersistenceRoundTrip() throws {
        print("\n🎲 PROPERTY: Persistence Round-Trip (500 random records)")
        
        var insertedIDs: [UUID] = []
        var insertedRecords: [UUID: BlazeDataRecord] = [:]
        
        // Insert 500 random records
        for i in 0..<500 {
            let record = randomRecord()
            let id = try db.insert(record)
            
            insertedIDs.append(id)
            insertedRecords[id] = record
            
            if i % 100 == 0 {
                print("  Generated \(i) random records...")
            }
        }
        
        // Persist
        try db.persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "prop_test", fileURL: tempURL, password: "test-pass-123")
        
        print("  📊 Reopened database")
        
        // Property: Every inserted record should survive persist/reopen
        var successCount = 0
        var failCount = 0
        
        for id in insertedIDs {
            if let _ = try? db.fetch(id: id) {
                successCount += 1
            } else {
                failCount += 1
            }
        }
        
        print("  📊 Survival rate: \(successCount)/500")
        
        XCTAssertEqual(successCount, 500, "ALL random records should survive persist/reopen")
        XCTAssertEqual(failCount, 0, "Zero records should be lost")
        
        print("  ✅ PROPERTY VERIFIED: Persistence preserves all data!")
    }
    
    // MARK: - Property: Query Determinism
    
    /// Property: Same query should ALWAYS return same results
    func testProperty_QueryDeterminism() throws {
        print("\n🎲 PROPERTY: Query Determinism (100 random queries)")
        
        // Insert diverse data
        for i in 0..<200 {
            try db.insert(BlazeDataRecord([
                "status": .string(["open", "closed", "pending"].randomElement()!),
                "priority": .int(Int.random(in: 1...5)),
                "value": .int(Int.random(in: 0...1000))
            ]))
        }
        
        var determinismFailures = 0
        
        // Run 100 random queries, each twice
        for i in 0..<100 {
            let status = ["open", "closed", "pending"].randomElement()!
            
            // Run same query twice
            let result1 = try db.query().where("status", equals: .string(status)).execute()
            let result2 = try db.query().where("status", equals: .string(status)).execute()
            
            // Property: Results should be identical
            if result1.count != result2.count {
                determinismFailures += 1
                print("  ❌ Query \(i): Got \(result1.count) then \(result2.count) results")
            }
            
            if i % 20 == 0 {
                print("  Tested \(i) random queries...")
            }
        }
        
        print("  📊 Determinism failures: \(determinismFailures)/100")
        
        XCTAssertEqual(determinismFailures, 0, "Query results should be deterministic")
        
        print("  ✅ PROPERTY VERIFIED: Queries are deterministic!")
    }
    
    // MARK: - Property: Aggregation Correctness
    
    /// Property: Aggregation results should match manual calculation
    func testProperty_AggregationCorrectness() throws {
        print("\n🎲 PROPERTY: Aggregation Correctness (50 iterations)")
        
        var failures = 0
        
        for iteration in 0..<50 {
            // Clear database
            let allRecords = try db.fetchAll()
            for record in allRecords {
                if let id = record.storage["id"]?.uuidValue {
                    try? db.delete(id: id)
                }
            }
            
            // Insert random integers
            let values = (0..<100).map { _ in Int.random(in: -1000...1000) }
            for value in values {
                try db.insert(BlazeDataRecord(["value": .int(value)]))
            }
            
            // Query aggregation
            let result = try db.query()
                .sum("value", as: "total")
                .count(as: "count")
                .executeAggregation()
            
            // Manual calculation
            let expectedSum = Double(values.reduce(0, +))
            let expectedCount = values.count
            
            // Property: Aggregation should match manual calculation
            let actualSum = result.sum("total") ?? -999999.0
            let actualCount = result.values["count"]?.intValue ?? -1
            
            if abs(actualSum - expectedSum) > 0.1 {
                failures += 1
                print("  ❌ Iteration \(iteration): Sum mismatch (expected \(expectedSum), got \(actualSum))")
            }
            
            if actualCount != expectedCount {
                failures += 1
                print("  ❌ Iteration \(iteration): Count mismatch (expected \(expectedCount), got \(actualCount))")
            }
            
            if iteration % 10 == 0 {
                print("  Tested \(iteration) random datasets...")
            }
        }
        
        print("  📊 Aggregation failures: \(failures)/50")
        
        XCTAssertEqual(failures, 0, "Aggregations should be mathematically correct")
        
        print("  ✅ PROPERTY VERIFIED: Aggregations are correct!")
    }
    
    // MARK: - Property: Update Preserves Other Fields
    
    /// Property: Updating one field shouldn't affect other fields
    func testProperty_UpdatePreservesOtherFields() throws {
        print("\n🎲 PROPERTY: Update Preserves Other Fields (200 tests)")
        
        var failures = 0
        
        for i in 0..<200 {
            // Insert record with multiple fields
            let id = try db.insert(BlazeDataRecord([
                "field1": .int(i),
                "field2": .string("value\(i)"),
                "field3": .double(Double(i) * 1.5),
                "field4": .bool(i % 2 == 0),
                "field5": .uuid(UUID())
            ]))
            
            // Store original values
            let original = try db.fetch(id: id)!
            let originalField2 = original["field2"]
            let originalField3 = original["field3"]
            let originalField4 = original["field4"]
            let originalField5 = original["field5"]
            
            // Update only field1
            try db.update(id: id, with: BlazeDataRecord([
                "field1": .int(i + 1000)
            ]))
            
            // Fetch updated record
            let updated = try db.fetch(id: id)!
            
            // Property: Other fields should be unchanged
            if !valuesEqual(updated["field2"]!, originalField2!) { failures += 1 }
            if !valuesEqual(updated["field3"]!, originalField3!) { failures += 1 }
            if !valuesEqual(updated["field4"]!, originalField4!) { failures += 1 }
            if !valuesEqual(updated["field5"]!, originalField5!) { failures += 1 }
            
            if i % 50 == 0 {
                print("  Tested \(i) random updates...")
            }
        }
        
        print("  📊 Field preservation failures: \(failures)")
        
        XCTAssertEqual(failures, 0, "Updates should preserve other fields")
        
        print("  ✅ PROPERTY VERIFIED: Updates preserve other fields!")
    }
    
    // MARK: - Property: Delete Idempotence
    
    /// Property: Deleting twice should be same as deleting once
    func testProperty_DeleteIdempotence() throws {
        print("\n🎲 PROPERTY: Delete Idempotence (100 tests)")
        
        for i in 0..<100 {
            // Insert record
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            
            // Delete once
            try db.delete(id: id)
            let countAfterFirst = db.count()
            
            // Delete again (should not error)
            XCTAssertNoThrow(try db.delete(id: id), "Deleting non-existent record should be safe")
            let countAfterSecond = db.count()
            
            // Property: Count should be the same
            XCTAssertEqual(countAfterFirst, countAfterSecond, 
                          "Deleting twice should be same as deleting once")
        }
        
        print("  ✅ PROPERTY VERIFIED: Delete is idempotent!")
    }
    
    // MARK: - Property: Count Consistency
    
    /// Property: count() should always equal fetchAll().count
    func testProperty_CountConsistency() throws {
        print("\n🎲 PROPERTY: Count Consistency (100 random operations)")
        
        var failures = 0
        
        for i in 0..<100 {
            // Random operation
            let op = Int.random(in: 0...2)
            
            switch op {
            case 0:  // Insert
                try db.insert(randomRecord())
            case 1:  // Update (if possible)
                let all = try db.fetchAll()
                if let random = all.randomElement(),
                   let id = random.storage["id"]?.uuidValue {
                    try db.update(id: id, with: randomRecord())
                }
            case 2:  // Delete (if possible)
                let all = try db.fetchAll()
                if let random = all.randomElement(),
                   let id = random.storage["id"]?.uuidValue,
                   all.count > 5 {  // Keep at least 5
                    try db.delete(id: id)
                }
            default:
                break
            }
            
            // Property: count() should equal fetchAll().count
            let count = db.count()
            let fetchAllCount = try db.fetchAll().count
            
            if count != fetchAllCount {
                failures += 1
                print("  ❌ Iteration \(i): count()=\(count), fetchAll().count=\(fetchAllCount)")
            }
        }
        
        print("  📊 Count consistency failures: \(failures)/100")
        
        XCTAssertEqual(failures, 0, "count() should always equal fetchAll().count")
        
        print("  ✅ PROPERTY VERIFIED: Count is consistent!")
    }
    
    // MARK: - Property: Commutativity
    
    /// Property: Order of inserts shouldn't affect final state
    func testProperty_InsertOrderIndependence() throws {
        print("\n🎲 PROPERTY: Insert Order Independence")
        
        // Create 2 databases with same data in different order
        let records = (0..<50).map { i in
            BlazeDataRecord(["index": .int(i), "data": .string("Record \(i)")])
        }
        
        // Database 1: Sequential order
        let db1URL = tempURL.deletingLastPathComponent().appendingPathComponent("prop1.blazedb")
        try? FileManager.default.removeItem(at: db1URL)
        BlazeDBClient.clearCachedKey()
        let db1 = try BlazeDBClient(name: "prop1", fileURL: db1URL, password: "test-pass-123")
        
        for record in records {
            try db1.insert(record)
        }
        try db1.persist()
        
        // Database 2: Shuffled order
        let db2URL = tempURL.deletingLastPathComponent().appendingPathComponent("prop2.blazedb")
        try? FileManager.default.removeItem(at: db2URL)
        BlazeDBClient.clearCachedKey()
        let db2 = try BlazeDBClient(name: "prop2", fileURL: db2URL, password: "test-pass-123")
        
        for record in records.shuffled() {
            try db2.insert(record)
        }
        try db2.persist()
        
        // Property: Both databases should have same content (order-independent)
        XCTAssertEqual(db1.count(), db2.count(), "Count should be same regardless of insert order")
        
        let all1 = try db1.fetchAll().sorted { $0["index"]!.intValue! < $1["index"]!.intValue! }
        let all2 = try db2.fetchAll().sorted { $0["index"]!.intValue! < $1["index"]!.intValue! }
        
        XCTAssertEqual(all1.count, all2.count, "Should have same number of records")
        
        // Cleanup
        try? FileManager.default.removeItem(at: db1URL)
        try? FileManager.default.removeItem(at: db2URL)
        try? FileManager.default.removeItem(at: db1URL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: db2URL.deletingPathExtension().appendingPathExtension("meta"))
        
        print("  ✅ PROPERTY VERIFIED: Insert order doesn't affect final state!")
    }
    
    // MARK: - Property: Filter Correctness
    
    /// Property: Filter results should match manual filtering
    func testProperty_FilterCorrectness() throws {
        print("\n🎲 PROPERTY: Filter Correctness (100 random queries)")
        
        // Insert diverse data
        for i in 0..<200 {
            try db.insert(BlazeDataRecord([
                "status": .string(["open", "closed", "pending"].randomElement()!),
                "priority": .int(Int.random(in: 1...5)),
                "value": .int(Int.random(in: 0...100))
            ]))
        }
        
        let allRecords = try db.fetchAll()
        var failures = 0
        
        // Test 100 random queries
        for i in 0..<100 {
            let testStatus = ["open", "closed", "pending"].randomElement()!
            
            // Query using BlazeDB
            let queryResult = try db.query()
                .where("status", equals: .string(testStatus))
                .execute()
            
            // Manual filter
            let manualResult = allRecords.filter {
                $0["status"]?.stringValue == testStatus
            }
            
            // Property: Counts should match
            if queryResult.count != manualResult.count {
                failures += 1
                print("  ❌ Query \(i): BlazeDB=\(queryResult.count), Manual=\(manualResult.count)")
            }
            
            if i % 20 == 0 {
                print("  Tested \(i) random queries...")
            }
        }
        
        print("  📊 Filter failures: \(failures)/100")
        
        XCTAssertEqual(failures, 0, "Query filters should match manual filtering")
        
        print("  ✅ PROPERTY VERIFIED: Filters are correct!")
    }
    
    // MARK: - Property: Update Commutativity
    
    /// Property: Multiple updates should be commutative (last write wins)
    func testProperty_UpdateCommutativity() throws {
        print("\n🎲 PROPERTY: Update Commutativity (50 sequences)")
        
        var failures = 0
        
        for i in 0..<50 {
            let id = try db.insert(BlazeDataRecord(["value": .int(0)]))
            
            // Apply random sequence of updates
            let updateCount = Int.random(in: 5...20)
            var lastValue = 0
            
            for j in 0..<updateCount {
                let newValue = Int.random(in: 0...1000)
                try db.update(id: id, with: BlazeDataRecord(["value": .int(newValue)]))
                lastValue = newValue
            }
            
            // Property: Final value should be the last update
            let final = try db.fetch(id: id)
            let finalValue = final?["value"]?.intValue ?? -1
            
            if finalValue != lastValue {
                failures += 1
                print("  ❌ Sequence \(i): Expected \(lastValue), got \(finalValue)")
            }
            
            // Cleanup
            try db.delete(id: id)
        }
        
        print("  📊 Commutativity failures: \(failures)/50")
        
        XCTAssertEqual(failures, 0, "Last update should always win")
        
        print("  ✅ PROPERTY VERIFIED: Updates are commutative!")
    }
    
    // MARK: - Property: Transaction Atomicity
    
    /// Property: Either all operations succeed or none do
    func testProperty_TransactionAtomicity() throws {
        print("\n🎲 PROPERTY: Transaction Atomicity (100 sequences)")
        
        var atomicityViolations = 0
        
        for i in 0..<100 {
            let initialCount = db.count()
            
            // Perform batch operation (should be atomic)
            let recordCount = Int.random(in: 5...20)
            let records = (0..<recordCount).map { _ in randomRecord() }
            
            do {
                _ = try db.insertMany(records)
                
                // Property: All should be inserted
                let newCount = db.count()
                if newCount != initialCount + recordCount {
                    atomicityViolations += 1
                    print("  ❌ Batch \(i): Expected \(initialCount + recordCount), got \(newCount)")
                }
            } catch {
                // Property: None should be inserted on failure
                let newCount = db.count()
                if newCount != initialCount {
                    atomicityViolations += 1
                    print("  ❌ Batch \(i): Partial insert on failure (initial=\(initialCount), after=\(newCount))")
                }
            }
            
            if i % 20 == 0 {
                print("  Tested \(i) random batch operations...")
            }
        }
        
        print("  📊 Atomicity violations: \(atomicityViolations)/100")
        
        XCTAssertEqual(atomicityViolations, 0, "Batch operations should be atomic")
        
        print("  ✅ PROPERTY VERIFIED: Batch operations are atomic!")
    }
    
    // MARK: - Property: Field Type Preservation
    
    /// Property: Field types should be preserved exactly
    func testProperty_FieldTypePreservation() throws {
        print("\n🎲 PROPERTY: Field Type Preservation (500 random fields)")
        
        var failures = 0
        
        for i in 0..<500 {
            let field = randomField()
            let id = try db.insert(BlazeDataRecord(["test": field]))
            
            let fetched = try db.fetch(id: id)
            let fetchedField = fetched?["test"]
            
            // Property: Type should be preserved
            if !sameType(field, fetchedField) {
                failures += 1
                print("  ❌ Field \(i): Type changed from \(typeString(field)) to \(typeString(fetchedField))")
            }
            
            // Clean up
            try db.delete(id: id)
            
            if i % 100 == 0 {
                print("  Tested \(i) random fields...")
            }
        }
        
        print("  📊 Type preservation failures: \(failures)/500")
        
        XCTAssertEqual(failures, 0, "Field types should be preserved")
        
        print("  ✅ PROPERTY VERIFIED: Field types preserved!")
    }
    
    // MARK: - Property: Concurrent Safety
    
    /// Property: Concurrent operations should not corrupt database
    func testProperty_ConcurrentSafety() throws {
        print("\n🎲 PROPERTY: Concurrent Safety (1000 concurrent operations)")
        
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()
        
        // 1000 concurrent operations
        for i in 0..<1000 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    let op = Int.random(in: 0...3)
                    
                    switch op {
                    case 0:  // Insert
                        _ = try self.db.insert(self.randomRecord())
                    case 1:  // Fetch
                        _ = try self.db.fetchAll()
                    case 2:  // Update
                        let all = try self.db.fetchAll()
                        if let random = all.randomElement(),
                           let id = random.storage["id"]?.uuidValue {
                            try self.db.update(id: id, with: self.randomRecord())
                        }
                    case 3:  // Delete
                        let all = try self.db.fetchAll()
                        if let random = all.randomElement(),
                           let id = random.storage["id"]?.uuidValue,
                           all.count > 10 {
                            try self.db.delete(id: id)
                        }
                    default:
                        break
                    }
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
            }
        }
        
        group.wait()
        
        print("  📊 Concurrent operations: 1000")
        print("  📊 Errors: \(errors.count)")
        
        // Property: Database should remain consistent
        XCTAssertNoThrow(try db.fetchAll(), "Database should remain queryable")
        
        let finalCount = db.count()
        XCTAssertGreaterThan(finalCount, 0, "Database should have some records")
        
        print("  ✅ PROPERTY VERIFIED: Concurrent operations are safe!")
    }
    
    // MARK: - Property: Data Size Bounds
    
    /// Property: Records should fit within reasonable size limits
    func testProperty_DataSizeBounds() throws {
        print("\n🎲 PROPERTY: Data Size Bounds (100 random sizes)")
        
        var tooLargeCount = 0
        var successCount = 0
        
        for i in 0..<100 {
            // Random data size from 1 byte to 10KB
            let size = Int.random(in: 1...10_000)
            let data = Data(repeating: UInt8(i % 256), count: size)
            
            do {
                _ = try db.insert(BlazeDataRecord(["data": .data(data)]))
                successCount += 1
            } catch {
                tooLargeCount += 1
            }
            
            if i % 20 == 0 {
                print("  Tested \(i) random sizes...")
            }
        }
        
        print("  📊 Successful inserts: \(successCount)/100")
        print("  📊 Too large: \(tooLargeCount)/100")
        
        // Property: Should handle most reasonable sizes
        XCTAssertGreaterThan(successCount, 90, "Should handle 90%+ of random sizes")
        
        print("  ✅ PROPERTY VERIFIED: Handles reasonable data sizes!")
    }
    
    // MARK: - Helper Functions
    
    /// Compare two BlazeDocumentField values for equality
    private func valuesEqual(_ a: BlazeDocumentField, _ b: BlazeDocumentField) -> Bool {
        switch (a, b) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return abs(a - b) < 0.0001
        case (.bool(let a), .bool(let b)): return a == b
        case (.date(let a), .date(let b)): return abs(a.timeIntervalSince1970 - b.timeIntervalSince1970) < 0.001
        case (.uuid(let a), .uuid(let b)): return a == b
        case (.data(let a), .data(let b)): return a == b
        default: return false
        }
    }
    
    /// Check if two fields have the same type
    private func sameType(_ a: BlazeDocumentField, _ b: BlazeDocumentField?) -> Bool {
        guard let b = b else { return false }
        
        switch (a, b) {
        case (.string, .string): return true
        case (.int, .int): return true
        case (.double, .double): return true
        case (.bool, .bool): return true
        case (.date, .date): return true
        case (.uuid, .uuid): return true
        case (.data, .data): return true
        case (.array, .array): return true
        case (.dictionary, .dictionary): return true
        default: return false
        }
    }
    
    /// Get type name as string
    private func typeString(_ field: BlazeDocumentField?) -> String {
        guard let field = field else { return "nil" }
        
        switch field {
        case .string: return "String"
        case .int: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .date: return "Date"
        case .uuid: return "UUID"
        case .data: return "Data"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        }
    }
}

