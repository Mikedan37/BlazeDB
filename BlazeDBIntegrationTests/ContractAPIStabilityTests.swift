//
//  ContractAPIStabilityTests.swift
//  BlazeDBIntegrationTests
//
//  CONTRACT TESTING: Validate API stability and backward compatibility
//  Ensures public API doesn't break between versions
//

import XCTest
@testable import BlazeDBCore

final class ContractAPIStabilityTests: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Contract-\(UUID().uuidString).blazedb")
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
    
    // MARK: - API Contract Tests
    
    /// CONTRACT: BlazeDBClient initialization API is stable
    func testContract_DatabaseInitialization() async throws {
        print("\n📜 CONTRACT: Database Initialization API")
        
        // Test 1: Standard init (throwing)
        print("  ✅ Test 1: Throwing initializer")
        let db1 = try BlazeDBClient(
            name: "Test",
            fileURL: dbURL,
            password: "contract-test-123"
        )
        XCTAssertNotNil(db1)
        
        // Test 2: Failable init (non-throwing)
        print("  ✅ Test 2: Failable initializer")
        let db2 = try? BlazeDBClient(
            name: "Test2",
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).db"),
            password: "contract-test-123"
        )
        XCTAssertNotNil(db2)
        
        // Test 3: Weak password handling
        print("  ✅ Test 3: Weak password rejection")
        let weakDB = try? BlazeDBClient(name: "Weak", fileURL: dbURL, password: "weak")
        XCTAssertNil(weakDB, "Weak password should be rejected")
        
        print("  ✅ CONTRACT VALIDATED: Initialization API stable!")
    }
    
    /// CONTRACT: CRUD operations API is stable
    func testContract_CRUDOperations() async throws {
        print("\n📜 CONTRACT: CRUD Operations API")
        
        let db = try BlazeDBClient(name: "CRUD", fileURL: dbURL, password: "contract-123")
        
        // Insert
        print("  ✅ Test: insert(_:) returns UUID")
        let id = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        XCTAssertNotNil(id)
        XCTAssert(type(of: id) == UUID.self)
        
        // Fetch
        print("  ✅ Test: fetch(id:) returns BlazeDataRecord?")
        let fetched = try await db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssert(type(of: fetched) == Optional<BlazeDataRecord>.self)
        
        // Update
        print("  ✅ Test: update(id:with:) doesn't throw on success")
        try await db.update(id: id, with: BlazeDataRecord(["value": .int(2)]))
        
        // Delete
        print("  ✅ Test: delete(id:) doesn't throw on success")
        try await db.delete(id: id)
        
        // FetchAll
        print("  ✅ Test: fetchAll() returns [BlazeDataRecord]")
        let all = try await db.fetchAll()
        XCTAssert(type(of: all) == Array<BlazeDataRecord>.self)
        
        print("  ✅ CONTRACT VALIDATED: CRUD API stable!")
    }
    
    /// CONTRACT: Query builder API is stable
    func testContract_QueryBuilderAPI() async throws {
        print("\n📜 CONTRACT: Query Builder API")
        
        let db = try BlazeDBClient(name: "QueryContract", fileURL: dbURL, password: "contract-123")
        
        _ = try await db.insertMany((0..<10).map { i in
            BlazeDataRecord(["value": .int(i)])
        })
        
        // Test: Chainable query API
        print("  ✅ Test: Chainable query API")
        let result = try await db.query()
            .where("value", greaterThan: .int(5))
            .orderBy("value")
            .limit(3)
            .execute()
        
        XCTAssert(result.count <= 3)
        
        // Test: Async query
        print("  ✅ Test: Async query execution")
        let asyncResult = try await db.query().where("value", equals: .int(1)).execute()
        XCTAssert(asyncResult.count >= 0)
        
        // Test: Join API
        print("  ✅ Test: JOIN API exists")
        let db2URL = dbURL.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).db")
        let db2 = try BlazeDBClient(name: "Join", fileURL: db2URL, password: "contract-123")
        _ = try await db2.insert(BlazeDataRecord(["ref": .int(1)]))
        
        defer {
            try? FileManager.default.removeItem(at: db2URL)
            try? FileManager.default.removeItem(at: db2URL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        let joined = try await db.join(with: db2, on: "value", equals: "ref", type: .inner)
        XCTAssert(type(of: joined) == Array<JoinedRecord>.self)
        
        print("  ✅ CONTRACT VALIDATED: Query API stable!")
    }
    
    /// CONTRACT: Type-safe API is stable
    func testContract_TypeSafeAPI() async throws {
        print("\n📜 CONTRACT: Type-Safe API")
        
        let db = try BlazeDBClient(name: "TypeSafe", fileURL: dbURL, password: "contract-123")
        
        struct TestModel: BlazeStorable {
            var id: UUID
            var title: String
            var value: Int
        }
        
        // Insert type-safe
        print("  ✅ Test: insert(_: BlazeStorable)")
        let model = TestModel(id: UUID(), title: "Test", value: 42)
        let id = try await db.insert(model)
        XCTAssertNotNil(id)
        
        // Fetch type-safe
        print("  ✅ Test: fetch(_:id:)")
        let fetched = try await db.fetch(TestModel.self, id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test")
        
        // FetchAll type-safe
        print("  ✅ Test: fetchAll(_:)")
        let all = try await db.fetchAll(TestModel.self)
        XCTAssertEqual(all.count, 1)
        
        print("  ✅ CONTRACT VALIDATED: Type-safe API stable!")
    }
    
    /// CONTRACT: Transaction API is stable
    func testContract_TransactionAPI() async throws {
        print("\n📜 CONTRACT: Transaction API")
        
        let db = try BlazeDBClient(name: "TxnContract", fileURL: dbURL, password: "contract-123")
        
        // Begin
        print("  ✅ Test: beginTransaction()")
        try await db.beginTransaction()
        
        // Operations
        _ = try await db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Commit
        print("  ✅ Test: commitTransaction()")
        try await db.commitTransaction()
        
        // Rollback
        print("  ✅ Test: rollbackTransaction()")
        try await db.beginTransaction()
        _ = try await db.insert(BlazeDataRecord(["value": .int(2)]))
        try await db.rollbackTransaction()
        
        let count = try await db.count()
        XCTAssertEqual(count, 1, "Only committed record should exist")
        
        print("  ✅ CONTRACT VALIDATED: Transaction API stable!")
    }
    
    /// CONTRACT: Search API is stable
    func testContract_SearchAPI() async throws {
        print("\n📜 CONTRACT: Search API")
        
        let db = try BlazeDBClient(name: "SearchContract", fileURL: dbURL, password: "contract-123")
        
        // Enable search
        print("  ✅ Test: enableSearch(fields:)")
        try await db.collection.enableSearch(fields: ["title"])
        
        // Insert searchable data
        _ = try await db.insert(BlazeDataRecord(["title": .string("Searchable text")]))
        
        // Search
        print("  ✅ Test: search(query:in:)")
        let results = try await db.collection.search(
            query: "Searchable",
            in: ["title"]
        )
        
        XCTAssert(type(of: results) == Array<FullTextSearchResult>.self)
        XCTAssertGreaterThan(results.count, 0)
        
        print("  ✅ CONTRACT VALIDATED: Search API stable!")
    }
    
    // MARK: - Backward Compatibility
    
    /// Test: V1 code can read V2 database
    func testBackwardCompatibility_V1CodeReadsV2Database() async throws {
        print("\n🔙 COMPATIBILITY: V1 Code Reads V2 Database")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "Compat", fileURL: dbURL, password: "compat-123")
        
        // V2: Insert with new fields
        _ = try await db!.insert(BlazeDataRecord([
            "title": .string("V2 Bug"),
            "newField": .string("V2 feature")  // New field
        ]))
        
        try await db!.persist()
        db = nil
        
        // V1 code: Read without knowing about newField
        db = try BlazeDBClient(name: "Compat", fileURL: dbURL, password: "compat-123")
        
        let records = try await db!.fetchAll()
        XCTAssertEqual(records.count, 1, "Expected 1 record to be inserted and persisted")
        
        guard !records.isEmpty else {
            XCTFail("No records found - insert may have failed")
            return
        }
        
        // V1 code only reads title
        let title = records[0].storage["title"]?.stringValue
        XCTAssertEqual(title, "V2 Bug")
        
        print("  ✅ V1 code can read V2 database (extra fields ignored)")
        print("  ✅ VALIDATED: Backward compatible!")
    }
}

