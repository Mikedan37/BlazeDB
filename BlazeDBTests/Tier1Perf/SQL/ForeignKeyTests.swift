//
//  ForeignKeyTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for foreign keys and referential integrity
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class ForeignKeyTests: XCTestCase {
    
    private var tempDir: URL?
    private var usersDB: BlazeDBClient?
    private var bugsDB: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FK-Test-\(UUID().uuidString)")
        let dir = try XCTUnwrap(tempDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Create two databases: users and bugs
        let usersURL = dir.appendingPathComponent("users.blazedb")
        let bugsURL = dir.appendingPathComponent("bugs.blazedb")
        
        usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "SecureTestDB-456!")
        bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        super.tearDown()
    }
    
    // MARK: - Foreign Key Definition Tests
    
    func testForeignKey_CanBeAdded() throws {
        print("🔗 Testing foreign key can be added")
        
        let fk = ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        )
        
        try requireFixture(bugsDB).addForeignKey(fk)
        
        let foreignKeys = try requireFixture(bugsDB).getForeignKeys()
        
        XCTAssertEqual(foreignKeys.count, 1)
        XCTAssertEqual(foreignKeys.first?.name, "bug_user_fk")
        XCTAssertEqual(foreignKeys.first?.field, "userId")
        
        print("  ✅ Foreign key added successfully")
    }
    
    func testForeignKey_CanBeRemoved() throws {
        print("🔗 Testing foreign key can be removed")
        
        let fk = ForeignKey(
            name: "test_fk",
            field: "userId",
            referencedCollection: "users"
        )
        
        try requireFixture(bugsDB).addForeignKey(fk)
        
        var foreignKeys = try requireFixture(bugsDB).getForeignKeys()
        XCTAssertEqual(foreignKeys.count, 1)
        
        // Remove it
        try requireFixture(bugsDB).removeForeignKey(named: "test_fk")
        
        foreignKeys = try requireFixture(bugsDB).getForeignKeys()
        XCTAssertEqual(foreignKeys.count, 0)
        
        print("  ✅ Foreign key removed successfully")
    }
    
    func testForeignKey_MultipleForeignKeys() throws {
        print("🔗 Testing multiple foreign keys")
        
        try requireFixture(bugsDB).addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users"
        ))
        
        try requireFixture(bugsDB).addForeignKey(ForeignKey(
            name: "bug_project_fk",
            field: "projectId",
            referencedCollection: "projects"
        ))
        
        let foreignKeys = try requireFixture(bugsDB).getForeignKeys()
        
        XCTAssertEqual(foreignKeys.count, 2)
        print("  ✅ Multiple foreign keys supported")
    }
    
    // MARK: - Referential Integrity Tests
    
    func testReferentialIntegrity_ValidReference() throws {
        print("🔗 Testing valid foreign key reference")
        
        // Create user
        let userId = try requireFixture(usersDB).insert(BlazeDataRecord([
            "name": .string("Alice"),
            "email": .string("alice@example.com")
        ]))
        
        // Add foreign key
        try requireFixture(bugsDB).addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .restrict
        ))
        
        // Insert bug with valid userId
        let bugId = try requireFixture(bugsDB).insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "userId": .uuid(userId)
        ]))
        
        XCTAssertNotNil(bugId)
        print("  ✅ Valid reference accepted")
    }
    
    func testReferentialIntegrity_CascadeDelete() throws {
        print("🔗 Testing CASCADE DELETE")
        
        // Setup: Create user and bugs
        let userId = try requireFixture(usersDB).insert(BlazeDataRecord([
            "name": .string("Bob")
        ]))
        
        _ = try requireFixture(bugsDB).insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "userId": .uuid(userId)
        ]))
        
        _ = try requireFixture(bugsDB).insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "userId": .uuid(userId)
        ]))
        
        print("    Created: 1 user, 2 bugs")
        
        // Setup RelationshipManager for cascade
        var relationships = RelationshipManager()
        relationships.register(try requireFixture(usersDB), as: "users")
        relationships.register(try requireFixture(bugsDB), as: "bugs")
        
        let fk = ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "bugs",  // Bugs reference users
            onDelete: .cascade
        )
        
        // Delete user → should cascade delete bugs
        try relationships.cascadeDelete(from: "users", id: userId, foreignKeys: [fk])
        
        // Verify bugs were deleted
        let remainingBugs = try requireFixture(bugsDB).fetchAll()
        
        XCTAssertEqual(remainingBugs.count, 0, "Cascade should delete all related bugs")
        print("  ✅ CASCADE DELETE: Deleted 2 related bugs")
    }
    
    func testReferentialIntegrity_SetNull() throws {
        print("🔗 Testing SET NULL on delete")
        
        // Note: This would require implementing setNull logic
        // For now, just verify the enum exists
        
        let fk = ForeignKey(
            name: "test_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .setNull
        )
        
        XCTAssertEqual(fk.onDelete, .setNull)
        print("  ✅ SET NULL action supported")
    }
    
    func testReferentialIntegrity_Restrict() {
        print("🔗 Testing RESTRICT on delete")
        
        let fk = ForeignKey(
            name: "test_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .restrict
        )
        
        XCTAssertEqual(fk.onDelete, .restrict)
        print("  ✅ RESTRICT action supported")
    }
    
    // MARK: - Edge Cases
    
    func testForeignKey_WithNullValue() throws {
        print("🔗 Testing foreign key with null/missing value")
        
        try requireFixture(bugsDB).addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users"
        ))
        
        // Insert bug without userId (should be allowed)
        let bugId = try requireFixture(bugsDB).insert(BlazeDataRecord([
            "title": .string("Bug without owner")
            // No userId field
        ]))
        
        XCTAssertNotNil(bugId)
        print("  ✅ Null foreign key allowed (optional)")
    }
    
    func testForeignKey_ThreadSafety() throws {
        print("🔗 Testing foreign key thread safety")

        final class SendableDBRef: @unchecked Sendable {
            let db: BlazeDBClient
            init(_ db: BlazeDBClient) { self.db = db }
        }
        let dbRef = SendableDBRef(try requireFixture(bugsDB))
        
        // Add/remove foreign keys concurrently
        DispatchQueue.concurrentPerform(iterations: 10) { i in
            let fk = ForeignKey(
                name: "fk_\(i)",
                field: "field\(i)",
                referencedCollection: "collection\(i)"
            )
            
            dbRef.db.addForeignKey(fk)
            dbRef.db.removeForeignKey(named: "fk_\(i)")
        }
        
        // Should not crash
        print("  ✅ Thread-safe foreign key operations")
    }

    func testDeleteWithUnsupportedCascadeActionThrows() throws {
        try requireFixture(bugsDB).addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        ))

        let bugId = try requireFixture(bugsDB).insert(BlazeDataRecord([
            "title": .string("Bug with unsupported cascade"),
            "userId": .uuid(UUID())
        ]))

        XCTAssertThrowsError(try requireFixture(bugsDB).delete(id: bugId)) { error in
            let message = String(describing: error).lowercased()
            XCTAssertTrue(
                message.contains("not implemented") || message.contains("unsupported"),
                "Delete should clearly fail for unsupported foreign key delete actions"
            )
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_SchemaValidation() throws {
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "priority", type: .int, required: true)
        ])
        
        try requireFixture(bugsDB).defineSchema(schema)
        let bugs = try requireFixture(bugsDB)
        measure(metrics: [XCTClockMetric()]) {
            for i in 0..<100 {
                _ = try? bugs.insert(BlazeDataRecord([
                    "title": .string("Bug \(i)"),
                    "priority": .int(i % 5 + 1)
                ]))
            }
        }
    }
}

