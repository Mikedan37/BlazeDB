//
//  SchemaForeignKeyIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests for schema validation + foreign keys in real scenarios
//

import XCTest
@testable import BlazeDBCore

final class SchemaForeignKeyIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Schema-FK-Integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Real-World Scenario 1: Bug Tracker with Schema
    
    func testIntegration_BugTrackerWithSchema() throws {
        print("\n🐛 INTEGRATION: Bug Tracker with Schema Validation")
        
        let dbURL = tempDir.appendingPathComponent("ashpile.blazedb")
        let db = try BlazeDBClient(name: "AshPile", fileURL: dbURL, password: "test-pass-123456")
        
        // Define bug schema
        let bugSchema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "description", type: .string, required: false),
            FieldSchema(name: "status", type: .string, required: true, validator: { field in
                guard case .string(let value) = field else { return false }
                return ["open", "in-progress", "closed", "wontfix"].contains(value)
            }),
            FieldSchema(name: "priority", type: .int, required: true, validator: { field in
                guard case .int(let value) = field else { return false }
                return value >= 1 && value <= 5
            }),
            FieldSchema(name: "assigneeId", type: .uuid, required: false)
        ], strict: false)
        
        db.defineSchema(bugSchema)
        print("  📋 Schema defined")
        
        // Valid bug
        let bug1 = try db.insert(BlazeDataRecord([
            "title": .string("Memory leak in login"),
            "status": .string("open"),
            "priority": .int(5)
        ]))
        print("  ✅ Valid bug inserted: \(bug1)")
        
        // Invalid status (should fail)
        do {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Another bug"),
                "status": .string("pending"),  // Invalid! Not in enum
                "priority": .int(3)
            ]))
            XCTFail("Should reject invalid status")
        } catch {
            print("  ✅ Invalid status rejected: \(error)")
        }
        
        // Invalid priority (should fail)
        do {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Another bug"),
                "status": .string("open"),
                "priority": .int(10)  // Invalid! Must be 1-5
            ]))
            XCTFail("Should reject invalid priority")
        } catch {
            print("  ✅ Invalid priority rejected")
        }
        
        // Missing required field (should fail)
        do {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Incomplete bug")
                // Missing status and priority!
            ]))
            XCTFail("Should reject missing required fields")
        } catch {
            print("  ✅ Missing required fields rejected")
        }
        
        // Valid bug with all fields
        let bug2 = try db.insert(BlazeDataRecord([
            "title": .string("UI crash on startup"),
            "description": .string("App crashes when opening"),
            "status": .string("in-progress"),
            "priority": .int(5),
            "assigneeId": .uuid(UUID())
        ]))
        
        XCTAssertNotNil(bug2)
        
        let totalBugs = db.count()
        XCTAssertEqual(totalBugs, 2, "Should have 2 valid bugs")
        
        print("  ✅ Bug tracker with schema: \(totalBugs) valid bugs")
    }
    
    // MARK: - Real-World Scenario 2: Multi-Collection with Foreign Keys
    
    func testIntegration_MultiCollectionWithForeignKeys() throws {
        print("\n🗄️  INTEGRATION: Multi-Collection with Foreign Keys")
        
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let commentsURL = tempDir.appendingPathComponent("comments.blazedb")
        
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123456")
        let bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "test-pass-123456")
        let commentsDB = try BlazeDBClient(name: "comments", fileURL: commentsURL, password: "test-pass-123456")
        
        // Define foreign keys
        bugsDB.addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        ))
        
        commentsDB.addForeignKey(ForeignKey(
            name: "comment_bug_fk",
            field: "bugId",
            referencedCollection: "bugs",
            onDelete: .cascade
        ))
        
        commentsDB.addForeignKey(ForeignKey(
            name: "comment_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        ))
        
        print("  🔗 Foreign keys defined")
        
        // Create data
        let user1 = try usersDB.insert(BlazeDataRecord(["name": .string("Alice")]))
        let bug1 = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "userId": .uuid(user1)
        ]))
        let comment1 = try commentsDB.insert(BlazeDataRecord([
            "text": .string("Comment 1"),
            "bugId": .uuid(bug1),
            "userId": .uuid(user1)
        ]))
        
        print("  ✅ Created: 1 user, 1 bug, 1 comment")
        
        // Setup relationship manager
        var relationships = RelationshipManager()
        relationships.register(usersDB, as: "users")
        relationships.register(bugsDB, as: "bugs")
        relationships.register(commentsDB, as: "comments")
        
        // Delete user → should cascade to bugs and comments
        let userFK = bugsDB.getForeignKeys().first!
        try relationships.cascadeDelete(from: "users", id: user1, foreignKeys: [userFK])
        
        let remainingBugs = try bugsDB.fetchAll()
        XCTAssertEqual(remainingBugs.count, 0, "Cascade should delete bugs")
        
        print("  ✅ CASCADE DELETE worked across collections")
    }
    
    // MARK: - Real-World Scenario 3: Schema + Telemetry
    
    func testIntegration_SchemaWithTelemetry() async throws {
        print("\n📊 INTEGRATION: Schema Validation + Telemetry")
        
        let dbURL = tempDir.appendingPathComponent("schema-telemetry.blazedb")
        let db = try BlazeDBClient(name: "SchemaTest", fileURL: dbURL, password: "test-pass-123456")
        
        // Enable telemetry
        db.telemetry.enable(samplingRate: 1.0)
        
        // Define schema
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "value", type: .int, required: true)
        ])
        db.defineSchema(schema)
        
        print("  📋 Schema + telemetry enabled")
        
        // Try invalid inserts (should fail and be tracked)
        for _ in 0..<3 {
            try? await db.insert(BlazeDataRecord([
                "value": .string("invalid")  // Wrong type!
            ]))
        }
        
        // Valid inserts (should succeed)
        for i in 0..<5 {
            _ = try await db.insert(BlazeDataRecord([
                "value": .int(i)
            ]))
        }
        
        // Wait for telemetry
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check telemetry
        let summary = try await db.telemetry.getSummary()
        
        print("  📊 Telemetry:")
        print("    Operations: \(summary.totalOperations)")
        print("    Errors: \(summary.errorCount)")
        print("    Success rate: \(String(format: "%.1f", summary.successRate))%")
        
        // Should track both successes and failures
        XCTAssertEqual(summary.totalOperations, 8, "Should track 8 operations (3 failed + 5 success)")
        XCTAssertEqual(summary.errorCount, 3, "Should track 3 schema validation errors")
        XCTAssertEqual(summary.successRate, 62.5, accuracy: 1.0)
        
        print("  ✅ Schema errors tracked in telemetry")
    }
    
    // MARK: - Real-World Scenario 4: Migration with Schema
    
    func testIntegration_MigrationWithSchema() throws {
        print("\n🔄 INTEGRATION: Migration with Schema Evolution")
        
        let dbURL = tempDir.appendingPathComponent("migration.blazedb")
        var db: BlazeDBClient? = try BlazeDBClient(name: "Migration", fileURL: dbURL, password: "test-pass-123456")
        
        // V1 Schema
        let schemaV1 = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true)
        ])
        db!.defineSchema(schemaV1)
        
        _ = try db!.insert(BlazeDataRecord(["title": .string("Bug 1")]))
        
        print("  📋 V1 Schema: 1 field")
        
        // Close and reopen
        db = nil
        db = try BlazeDBClient(name: "Migration", fileURL: dbURL, password: "test-pass-123456")
        
        // V2 Schema (add required field)
        let schemaV2 = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "priority", type: .int, required: true, defaultValue: .int(3))
        ])
        db!.defineSchema(schemaV2)
        
        // New inserts must have priority
        let bug2 = try db!.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "priority": .int(5)
        ]))
        
        XCTAssertNotNil(bug2)
        print("  📋 V2 Schema: Migrated successfully")
    }
    
    // MARK: - Real-World Scenario 5: Complex Validation
    
    func testIntegration_ComplexValidation() throws {
        print("\n🔍 INTEGRATION: Complex Field Validation")
        
        let dbURL = tempDir.appendingPathComponent("complex.blazedb")
        let db = try BlazeDBClient(name: "Complex", fileURL: dbURL, password: "test-pass-123456")
        
        // Complex schema with multiple validators
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "email", type: .string, required: true, validator: { field in
                guard case .string(let value) = field else { return false }
                return value.contains("@") && value.contains(".")
            }),
            FieldSchema(name: "age", type: .int, required: true, validator: { field in
                guard case .int(let value) = field else { return false }
                return value >= 18 && value <= 120
            }),
            FieldSchema(name: "username", type: .string, required: true, validator: { field in
                guard case .string(let value) = field else { return false }
                return value.count >= 3 && value.count <= 20 && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            })
        ], strict: true)
        
        db.defineSchema(schema)
        print("  📋 Complex schema defined")
        
        // Try invalid email
        do {
            _ = try db.insert(BlazeDataRecord([
                "email": .string("invalid-email"),
                "age": .int(25),
                "username": .string("alice")
            ]))
            XCTFail("Should reject invalid email")
        } catch {
            print("  ✅ Invalid email rejected")
        }
        
        // Try invalid age
        do {
            _ = try db.insert(BlazeDataRecord([
                "email": .string("alice@example.com"),
                "age": .int(15),  // Too young!
                "username": .string("alice")
            ]))
            XCTFail("Should reject invalid age")
        } catch {
            print("  ✅ Invalid age rejected")
        }
        
        // Try invalid username
        do {
            _ = try db.insert(BlazeDataRecord([
                "email": .string("alice@example.com"),
                "age": .int(25),
                "username": .string("al")  // Too short!
            ]))
            XCTFail("Should reject invalid username")
        } catch {
            print("  ✅ Invalid username rejected")
        }
        
        // Valid record
        let id = try db.insert(BlazeDataRecord([
            "email": .string("alice@example.com"),
            "age": .int(25),
            "username": .string("alice_99")
        ]))
        
        XCTAssertNotNil(id)
        print("  ✅ Valid record accepted")
    }
    
    // MARK: - Real-World Scenario 6: E-commerce with Relationships
    
    func testIntegration_EcommerceWithRelationships() throws {
        print("\n🛒 INTEGRATION: E-commerce with Foreign Keys")
        
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        let ordersURL = tempDir.appendingPathComponent("orders.blazedb")
        let itemsURL = tempDir.appendingPathComponent("items.blazedb")
        
        let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123456")
        let ordersDB = try BlazeDBClient(name: "orders", fileURL: ordersURL, password: "test-pass-123456")
        let itemsDB = try BlazeDBClient(name: "items", fileURL: itemsURL, password: "test-pass-123456")
        
        // Define schemas
        let userSchema = DatabaseSchema(fields: [
            FieldSchema(name: "name", type: .string, required: true),
            FieldSchema(name: "email", type: .string, required: true)
        ])
        usersDB.defineSchema(userSchema)
        
        let orderSchema = DatabaseSchema(fields: [
            FieldSchema(name: "userId", type: .uuid, required: true),
            FieldSchema(name: "total", type: .double, required: true)
        ])
        ordersDB.defineSchema(orderSchema)
        
        let itemSchema = DatabaseSchema(fields: [
            FieldSchema(name: "orderId", type: .uuid, required: true),
            FieldSchema(name: "product", type: .string, required: true),
            FieldSchema(name: "price", type: .double, required: true)
        ])
        itemsDB.defineSchema(itemSchema)
        
        // Define foreign keys
        ordersDB.addForeignKey(ForeignKey(
            name: "order_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        ))
        
        itemsDB.addForeignKey(ForeignKey(
            name: "item_order_fk",
            field: "orderId",
            referencedCollection: "orders",
            onDelete: .cascade
        ))
        
        print("  📋 Schemas + foreign keys defined")
        
        // Create user
        let userId = try usersDB.insert(BlazeDataRecord([
            "name": .string("Alice"),
            "email": .string("alice@example.com")
        ]))
        print("  ✅ User created: \(userId)")
        
        // Create order
        let orderId = try ordersDB.insert(BlazeDataRecord([
            "userId": .uuid(userId),
            "total": .double(99.99)
        ]))
        print("  ✅ Order created: \(orderId)")
        
        // Create order items
        let item1 = try itemsDB.insert(BlazeDataRecord([
            "orderId": .uuid(orderId),
            "product": .string("Widget"),
            "price": .double(49.99)
        ]))
        
        let item2 = try itemsDB.insert(BlazeDataRecord([
            "orderId": .uuid(orderId),
            "product": .string("Gadget"),
            "price": .double(49.99)
        ]))
        
        print("  ✅ Items created: 2 items")
        
        // Verify structure
        XCTAssertEqual(usersDB.count(), 1)
        XCTAssertEqual(ordersDB.count(), 1)
        XCTAssertEqual(itemsDB.count(), 2)
        
        print("  ✅ E-commerce structure: 1 user, 1 order, 2 items")
        
        // Setup relationships
        var relationships = RelationshipManager()
        relationships.register(usersDB, as: "users")
        relationships.register(ordersDB, as: "orders")
        relationships.register(itemsDB, as: "items")
        
        // Delete order → should cascade delete items
        let orderFK = itemsDB.getForeignKeys().first!
        try relationships.cascadeDelete(from: "orders", id: orderId, foreignKeys: [orderFK])
        
        XCTAssertEqual(itemsDB.count(), 0, "Items should be cascade deleted")
        print("  ✅ CASCADE DELETE: Order deleted → items deleted")
    }
    
    // MARK: - Real-World Scenario 7: Schema Validation Performance
    
    func testPerformance_SchemaValidation() throws {
        let dbURL = tempDir.appendingPathComponent("perf-schema.blazedb")
        let db = try BlazeDBClient(name: "PerfTest", fileURL: dbURL, password: "test-pass-123456")
        
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "value", type: .int, required: true, validator: { field in
                guard case .int(let value) = field else { return false }
                return value >= 0 && value <= 100
            })
        ])
        
        db.defineSchema(schema)
        
        measure(metrics: [XCTClockMetric()]) {
            // Insert 100 records with schema validation
            for i in 0..<100 {
                _ = try? db.insert(BlazeDataRecord([
                    "title": .string("Record \(i)"),
                    "value": .int(i % 100)
                ]))
            }
        }
        
        print("  ✅ Schema validation performance measured")
    }
}

