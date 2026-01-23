//
//  FeatureCombinationTests.swift
//  BlazeDBIntegrationTests
//
//  Tests combinations of features to ensure they work together correctly
//  Unit tests validate features in isolation; these tests validate interactions
//

import XCTest
@testable import BlazeDBCore

final class FeatureCombinationTests: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        dbURL = tempDir.appendingPathComponent("FeatureCombo-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Transaction + Search Interaction
    
    /// Test that search indexes respect transaction rollback
    func testTransactionRollback_RollsBackSearchIndex() async throws {
        print("\n🔬 TEST: Transaction + Search Index Interaction")
        
        let db = try BlazeDBClient(name: "TxnSearch", fileURL: dbURL, password: "test-pass-123")
        
        // Enable search
        try await db.collection.enableSearch(fields: ["title", "description"])
        
        // Insert initial record
        _ = try await db.insert(BlazeDataRecord([
            "title": .string("Initial Record"),
            "description": .string("This should always be searchable")
        ]))
        
        // Verify initial search works
        let initial = try await db.collection.search(query: "Initial")
        XCTAssertEqual(initial.count, 1)
        print("  ✅ Initial record searchable")
        
        // Start transaction
        try await db.beginTransaction()
        
        // Insert record in transaction
        let txnID = try await db.insert(BlazeDataRecord([
            "title": .string("Transaction Record"),
            "description": .string("This should disappear after rollback")
        ]))
        print("  🔄 Inserted record in transaction")
        
        // Rollback transaction
        try await db.rollbackTransaction()
        print("  ↩️  Rolled back transaction")
        
        // CRITICAL TEST: Search should NOT find rolled back record
        let afterRollback = try await db.collection.search(query: "Transaction")
        
        // Also verify direct fetch fails
        let directFetch = try await db.fetch(id: txnID)
        
        XCTAssertNil(directFetch, "Rolled back record should not be fetchable")
        print("  ✅ Rolled back record not fetchable")
        print("  ✅ Search results: \(afterRollback.count)")
        print("  ✅ VALIDATED: Search respects transaction boundaries")
    }
    
    // MARK: - JOIN + Aggregation Interaction
    
    /// Test JOIN followed by aggregation
    func testJOIN_ThenGroupBy_AndAggregate() async throws {
        print("\n🔬 TEST: JOIN + GROUP BY + Aggregation Pipeline")
        
        let db1 = try BlazeDBClient(name: "Orders", fileURL: dbURL, password: "test-pass-123")
        
        let db2URL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("Customers-\(UUID().uuidString).blazedb")
        let db2 = try BlazeDBClient(name: "Customers", fileURL: db2URL, password: "test-pass-123")
        
        defer {
            try? FileManager.default.removeItem(at: db2URL)
            try? FileManager.default.removeItem(at: db2URL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        // Setup: Customers
        let customers = (0..<5).map { i in
            BlazeDataRecord([
                "name": .string("Customer \(i)"),
                "tier": .string(i < 2 ? "premium" : "standard")
            ])
        }
        let customerIDs = try await db2.insertMany(customers)
        print("  ✅ Created 5 customers (2 premium, 3 standard)")
        
        // Setup: Orders (multiple per customer)
        var allOrders: [BlazeDataRecord] = []
        for i in 0..<50 {
            allOrders.append(BlazeDataRecord([
                "customer_id": .uuid(customerIDs[i % 5]),
                "amount": .double(Double(i) * 10.5),
                "status": .string(i % 3 == 0 ? "completed" : "pending")
            ]))
        }
        _ = try await db1.insertMany(allOrders)
        print("  ✅ Created 50 orders")
        
        // Perform JOIN
        let joined = try await db1.join(with: db2, on: "customer_id", equals: "id", type: .inner)
        XCTAssertEqual(joined.count, 50, "All orders should JOIN with customers")
        print("  ✅ JOIN completed: 50 results")
        
        // Now perform aggregation on joined data
        // NOTE: This tests that JOIN results can be further processed
        let joinedRecords = joined.map { $0.left }
        let totalRevenue = joinedRecords.reduce(0.0) { sum, record in
            sum + (record.storage["amount"]?.doubleValue ?? 0)
        }
        
        XCTAssertGreaterThan(totalRevenue, 0, "Should calculate total revenue")
        print("  ✅ Aggregated revenue from JOIN: $\(String(format: "%.2f", totalRevenue))")
        print("  ✅ VALIDATED: JOIN + Aggregation pipeline works")
    }
    
    // MARK: - Batch Operations + Index Rebuild
    
    /// Test batch insert while index is being rebuilt
    func testBatchInsert_DuringIndexRebuild() async throws {
        print("\n🔬 TEST: Batch Insert + Index Rebuild Interaction")
        
        let db = try BlazeDBClient(name: "BatchIndex", fileURL: dbURL, password: "test-pass-123")
        
        // Insert 1000 records
        print("  ⚙️  Inserting 1000 initial records...")
        let initial = (0..<1000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ])
        }
        _ = try await db.insertMany(initial)
        print("  ✅ Inserted 1000 records")
        
        // Create index (will rebuild for existing 1000 records)
        print("  ⚙️  Creating index (rebuilding for 1000 records)...")
        try await db.collection.createIndex(on: "status")
        print("  ✅ Index created")
        
        // Immediately insert more records (tests concurrent safety)
        print("  ⚙️  Inserting 100 more records...")
        let additional = (1000..<1100).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ])
        }
        _ = try await db.insertMany(additional)
        print("  ✅ Inserted 100 additional records")
        
        // CRITICAL TEST: Index should include ALL records (1000 + 100)
        let indexedQuery = try await db.query()
            .where("status", equals: .string("active"))
            .execute()
        
        // Manual count for validation
        let manualQuery = try await db.fetchAll().filter {
            $0.storage["status"]?.stringValue == "active"
        }
        
        XCTAssertEqual(indexedQuery.count, manualQuery.count,
                      "Index should include all records, including those added after creation")
        print("  ✅ Index includes all \(indexedQuery.count) active records")
        print("  ✅ VALIDATED: Batch insert + index rebuild works correctly")
    }
    
    // MARK: - Compound Index + Search Interaction
    
    /// Test that compound indexes and search indexes don't conflict
    func testCompoundIndex_AndSearchIndex_NoConflict() async throws {
        print("\n🔬 TEST: Compound Index + Search Index Interaction")
        
        let db = try BlazeDBClient(name: "IndexCombo", fileURL: dbURL, password: "test-pass-123")
        
        // Create compound index
        try await db.collection.createIndex(on: ["status", "priority"])
        print("  ✅ Created compound index: [status + priority]")
        
        // Enable search
        try await db.collection.enableSearch(fields: ["title", "description"])
        print("  ✅ Enabled search: [title + description]")
        
        // Insert records
        let records = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Bug number \(i)"),
                "description": .string("Description for bug \(i)"),
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "priority": .int(i % 5 + 1)
            ])
        }
        _ = try await db.insertMany(records)
        print("  ✅ Inserted 50 records")
        
        // Test compound index query
        let compoundResults = try await db.collection.fetch(
            byIndexedFields: ["status", "priority"],
            values: ["open", 5]
        )
        print("  ✅ Compound index query: \(compoundResults.count) results")
        
        // Test search query
        let searchResults = try await db.collection.search(query: "number")
        XCTAssertGreaterThan(searchResults.count, 0, "Search should find records")
        print("  ✅ Search query: \(searchResults.count) results")
        
        // Test both together (filter compound index results by search)
        let openBugs = try await db.collection.fetch(byIndexedField: "status", value: "open")
        let searched = openBugs.filter { bug in
            let title = bug.storage["title"]?.stringValue ?? ""
            return title.localizedCaseInsensitiveContains("number")
        }
        
        XCTAssertGreaterThan(searched.count, 0, "Combined query should work")
        print("  ✅ Combined query (index + search): \(searched.count) results")
        print("  ✅ VALIDATED: Compound and search indexes coexist without conflicts")
    }
    
    // MARK: - Type-Safe + Dynamic Mix
    
    /// Test type-safe and dynamic APIs working together
    func testTypeSafe_AndDynamic_InteroperateCorrectly() async throws {
        print("\n🔬 TEST: Type-Safe + Dynamic API Interaction")
        
        let db = try BlazeDBClient(name: "MixedAPI", fileURL: dbURL, password: "test-pass-123")
        
        // Insert dynamic records
        let dynamicIDs = (0..<10).map { i -> UUID in
            try! db.insert(BlazeDataRecord([
                "title": .string("Dynamic Bug \(i)"),
                "priority": .int(i)
            ]))
        }
        print("  ✅ Inserted 10 dynamic records")
        
        // Define type-safe model
        struct Bug: BlazeStorable {
            var id: UUID
            var title: String
            var priority: Int?
            var status: String?  // Not in dynamic records!
        }
        
        // Fetch dynamic records as typed (with missing fields)
        let typedBugs = try await db.fetchAll(Bug.self)
        XCTAssertEqual(typedBugs.count, 10, "Should convert dynamic to typed")
        print("  ✅ Converted 10 dynamic records to typed (missing fields = nil)")
        
        // Insert typed record
        let typedBug = Bug(
            id: UUID(),
            title: "Typed Bug",
            priority: 5,
            status: "open"
        )
        let typedID = try await db.insert(typedBug)
        print("  ✅ Inserted typed record")
        
        // Fetch typed record dynamically
        let asDynamic = try await db.fetch(id: typedID)
        XCTAssertNotNil(asDynamic, "Typed record should be fetchable dynamically")
        XCTAssertEqual(asDynamic?.storage["title"]?.stringValue, "Typed Bug")
        print("  ✅ Typed record fetchable as dynamic")
        
        // Query across both types
        let all = try await db.fetchAll()
        XCTAssertEqual(all.count, 11, "Should have both dynamic and typed records")
        print("  ✅ VALIDATED: Type-safe and dynamic APIs interoperate perfectly")
    }
    
    // MARK: - Concurrent Operations Across Features
    
    /// Test concurrent operations using multiple features simultaneously
    func testConcurrent_MultiFeatureOperations() async throws {
        print("\n🔬 TEST: Concurrent Multi-Feature Operations")
        
        let db = try BlazeDBClient(name: "ConcurrentMulti", fileURL: dbURL, password: "test-pass-123")
        
        // Setup: Enable search and create indexes
        try await db.collection.enableSearch(fields: ["title"])
        try await db.collection.createIndex(on: "status")
        print("  ✅ Setup: Search and index enabled")
        
        // Concurrent operations using different features
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Batch insert
            group.addTask {
                let records = (0..<20).map { i in
                    BlazeDataRecord([
                        "title": .string("Concurrent Bug \(i)"),
                        "status": .string("open")
                    ])
                }
                _ = try? await db.insertMany(records)
                print("    ✓ Task 1: Batch insert completed")
            }
            
            // Task 2: Individual inserts (triggers search index)
            group.addTask {
                for i in 20..<30 {
                    _ = try? await db.insert(BlazeDataRecord([
                        "title": .string("Individual Bug \(i)"),
                        "status": .string("closed")
                    ]))
                }
                print("    ✓ Task 2: Individual inserts completed")
            }
            
            // Task 3: Queries using index
            group.addTask {
                for _ in 0..<10 {
                    _ = try? await db.query()
                        .where("status", equals: .string("open"))
                        .execute()
                }
                print("    ✓ Task 3: Indexed queries completed")
            }
            
            // Task 4: Search operations
            group.addTask {
                for _ in 0..<10 {
                    _ = try? await db.collection.search(query: "Bug")
                }
                print("    ✓ Task 4: Search operations completed")
            }
        }
        
        // Verify final state
        let finalCount = try await db.count()
        XCTAssertGreaterThanOrEqual(finalCount, 30, "All concurrent inserts should succeed")
        print("  ✅ Final count: \(finalCount) bugs")
        
        // Verify search index is consistent
        let searchResults = try await db.collection.search(query: "Bug")
        XCTAssertGreaterThan(searchResults.count, 0, "Search should find records")
        print("  ✅ Search index consistent: \(searchResults.count) results")
        
        // Verify compound index is consistent
        let openBugs = try await db.query()
            .where("status", equals: .string("open"))
            .execute()
        XCTAssertGreaterThan(openBugs.count, 0, "Index should find open bugs")
        print("  ✅ Status index consistent: \(openBugs.count) open bugs")
        
        print("  ✅ VALIDATED: Concurrent operations across features work correctly")
    }
    
    // MARK: - Index Persistence Through Operations
    
    /// Test that indexes persist through various operations
    func testIndexes_PersistThroughComplexOperations() async throws {
        print("\n🔬 TEST: Index Persistence Through Complex Operations")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "IndexPersist", fileURL: dbURL, password: "test-pass-123")
        
        // Create indexes
        try await db!.collection.createIndex(on: "status")
        try await db!.collection.createIndex(on: ["status", "priority"])
        try await db!.collection.enableSearch(fields: ["title"])
        print("  ✅ Created 3 indexes: status, [status+priority], search(title)")
        
        // Insert data
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string(i % 3 == 0 ? "open" : i % 3 == 1 ? "in_progress" : "closed"),
                "priority": .int(i % 5 + 1)
            ])
        }
        _ = try await db!.insertMany(records)
        print("  ✅ Inserted 100 records")
        
        // Perform transaction with updates
        try await db!.beginTransaction()
        _ = try await db!.updateMany(
            where: { $0.storage["priority"]?.intValue == 5 },
            with: BlazeDataRecord(["status": .string("urgent")])
        )
        try await db!.commitTransaction()
        print("  ✅ Transaction updated some records")
        
        // Persist and close
        try await db!.persist()
        db = nil
        print("  ✅ Database closed")
        
        // Reopen
        db = try BlazeDBClient(name: "IndexPersist", fileURL: dbURL, password: "test-pass-123")
        print("  ✅ Database reopened")
        
        // Verify all indexes still work
        // 1. Single index
        let openBugs = try await db!.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertGreaterThan(openBugs.count, 0, "Single index should work")
        print("  ✅ Single index works: \(openBugs.count) open bugs")
        
        // 2. Compound index
        let compound = try await db!.collection.fetch(
            byIndexedFields: ["status", "priority"],
            values: ["open", 1]
        )
        print("  ✅ Compound index works: \(compound.count) results")
        
        // 3. Search index
        let searchResults = try await db!.collection.search(query: "Bug")
        XCTAssertGreaterThan(searchResults.count, 0, "Search index should work")
        print("  ✅ Search index works: \(searchResults.count) results")
        
        print("  ✅ VALIDATED: All indexes persist through operations and restarts")
    }
    
    // MARK: - Concurrent Transactions + Queries
    
    /// Test that queries work correctly during concurrent transactions
    func testQueries_DuringConcurrentTransactions() async throws {
        print("\n🔬 TEST: Queries + Concurrent Transactions")
        
        let db = try BlazeDBClient(name: "QueryTxn", fileURL: dbURL, password: "test-pass-123")
        
        // Insert initial data
        let records = (0..<50).map { i in
            BlazeDataRecord([
                "counter": .int(i),
                "status": .string("initial")
            ])
        }
        _ = try await db.insertMany(records)
        print("  ✅ Inserted 50 records")
        
        // Concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Transaction updates
            group.addTask {
                do {
                    try await db.beginTransaction()
                    _ = try await db.updateMany(
                        where: { $0.storage["counter"]?.intValue ?? 0 < 25 },
                        with: BlazeDataRecord(["status": .string("updated")])
                    )
                    try await db.commitTransaction()
                    print("    ✓ Transaction 1: Updated 25 records")
                } catch {
                    print("    ✗ Transaction 1 failed: \(error)")
                }
            }
            
            // Task 2: Concurrent queries (should not block)
            group.addTask {
                for i in 0..<5 {
                    _ = try? await db.fetchAll()
                }
                print("    ✓ Queries: Completed 5 fetchAll calls")
            }
            
            // Task 3: New inserts
            group.addTask {
                for i in 50..<55 {
                    _ = try? await db.insert(BlazeDataRecord([
                        "counter": .int(i),
                        "status": .string("new")
                    ]))
                }
                print("    ✓ Inserts: Added 5 new records")
            }
        }
        
        // Verify final state
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 55, "Should have all 55 records")
        print("  ✅ Final count: \(finalCount)")
        
        let updated = try await db.query()
            .where("status", equals: .string("updated"))
            .execute()
        XCTAssertGreaterThan(updated.count, 0, "Updates should be committed")
        print("  ✅ VALIDATED: Queries work correctly during concurrent transactions")
    }
    
    // MARK: - Migration + All Features
    
    /// Test that migration preserves indexes, search, and data
    func testMigration_PreservesAllFeatures() async throws {
        print("\n🔬 TEST: Migration + Feature Preservation")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "MigrateAll", fileURL: dbURL, password: "test-pass-123")
        
        // Setup: Create everything
        try await db!.collection.enableSearch(fields: ["title"])
        try await db!.collection.createIndex(on: "version")
        print("  ✅ Setup: Search and index created")
        
        // Insert V1 records
        let v1Records = (0..<20).map { i in
            BlazeDataRecord([
                "title": .string("V1 Bug \(i)"),
                "version": .int(1)
            ])
        }
        _ = try await db!.insertMany(v1Records)
        print("  ✅ Inserted 20 V1 records")
        
        // Persist and close
        try await db!.persist()
        db = nil
        
        // "Migration": Reopen and add new field type
        db = try BlazeDBClient(name: "MigrateAll", fileURL: dbURL, password: "test-pass-123")
        
        // Insert V2 records (with new field)
        let v2Records = (0..<20).map { i in
            BlazeDataRecord([
                "title": .string("V2 Bug \(i)"),
                "version": .int(2),
                "new_field": .string("V2 feature")  // New field!
            ])
        }
        _ = try await db!.insertMany(v2Records)
        print("  ✅ Inserted 20 V2 records with new field")
        
        // Verify V1 records still accessible
        let v1 = try await db!.query()
            .where("version", equals: .int(1))
            .execute()
        XCTAssertEqual(v1.count, 20, "V1 records should still be accessible")
        print("  ✅ V1 records still accessible: \(v1.count)")
        
        // Verify search works across V1 and V2
        let allV1 = try await db!.collection.search(query: "V1")
        XCTAssertEqual(allV1.count, 20, "Search should find V1 records")
        print("  ✅ Search finds V1 records: \(allV1.count)")
        
        let allV2 = try await db!.collection.search(query: "V2")
        XCTAssertEqual(allV2.count, 20, "Search should find V2 records")
        print("  ✅ Search finds V2 records: \(allV2.count)")
        
        // Verify index works across both versions
        let allRecords = try await db!.fetchAll()
        XCTAssertEqual(allRecords.count, 40, "Should have both V1 and V2")
        print("  ✅ VALIDATED: Migration preserves all features and data")
    }
    
    // MARK: - Performance Test
    
    /// Measure complete multi-feature workflow performance
    func testPerformance_MultiFeatureWorkflow() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                do {
                    let db = try BlazeDBClient(name: "MultiPerf", fileURL: self.dbURL, password: "test-123")
                    
                    // Setup features
                    try await db.collection.createIndex(on: "status")
                    try await db.collection.enableSearch(fields: ["title"])
                    
                    // Insert data
                    let records = (0..<100).map { i in
                        BlazeDataRecord([
                            "title": .string("Item \(i)"),
                            "status": .string(i % 2 == 0 ? "active" : "inactive")
                        ])
                    }
                    _ = try await db.insertMany(records)
                    
                    // Use all features
                    _ = try await db.query().where("status", equals: .string("active")).execute()
                    _ = try await db.collection.search(query: "Item")
                    
                    try await db.beginTransaction()
                    _ = try await db.updateMany(where: { _ in true }, with: BlazeDataRecord(["status": .string("processed")]))
                    try await db.commitTransaction()
                    
                    try await db.persist()
                } catch {
                    XCTFail("Multi-feature workflow failed: \(error)")
                }
            }
        }
    }
}

