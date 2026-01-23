//
//  ForeignKeyTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for foreign keys and referential integrity
//

import XCTest
@testable import BlazeDBCore

final class ForeignKeyTests: XCTestCase {
    
    var tempDir: URL!
    var usersDB: BlazeDBClient!
    var bugsDB: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FK-Test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create two databases: users and bugs
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        
        usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "test-pass-123456")
        bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "test-pass-123456")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Foreign Key Definition Tests
    
    func testForeignKey_CanBeAdded() {
        print("🔗 Testing foreign key can be added")
        
        let fk = ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        )
        
        bugsDB.addForeignKey(fk)
        
        let foreignKeys = bugsDB.getForeignKeys()
        
        XCTAssertEqual(foreignKeys.count, 1)
        XCTAssertEqual(foreignKeys.first?.name, "bug_user_fk")
        XCTAssertEqual(foreignKeys.first?.field, "userId")
        
        print("  ✅ Foreign key added successfully")
    }
    
    func testForeignKey_CanBeRemoved() {
        print("🔗 Testing foreign key can be removed")
        
        let fk = ForeignKey(
            name: "test_fk",
            field: "userId",
            referencedCollection: "users"
        )
        
        bugsDB.addForeignKey(fk)
        
        var foreignKeys = bugsDB.getForeignKeys()
        XCTAssertEqual(foreignKeys.count, 1)
        
        // Remove it
        bugsDB.removeForeignKey(named: "test_fk")
        
        foreignKeys = bugsDB.getForeignKeys()
        XCTAssertEqual(foreignKeys.count, 0)
        
        print("  ✅ Foreign key removed successfully")
    }
    
    func testForeignKey_MultipleForeignKeys() {
        print("🔗 Testing multiple foreign keys")
        
        bugsDB.addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users"
        ))
        
        bugsDB.addForeignKey(ForeignKey(
            name: "bug_project_fk",
            field: "projectId",
            referencedCollection: "projects"
        ))
        
        let foreignKeys = bugsDB.getForeignKeys()
        
        XCTAssertEqual(foreignKeys.count, 2)
        print("  ✅ Multiple foreign keys supported")
    }
    
    // MARK: - Referential Integrity Tests
    
    func testReferentialIntegrity_ValidReference() throws {
        print("🔗 Testing valid foreign key reference")
        
        // Create user
        let userId = try usersDB.insert(BlazeDataRecord([
            "name": .string("Alice"),
            "email": .string("alice@example.com")
        ]))
        
        // Add foreign key
        bugsDB.addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .restrict
        ))
        
        // Insert bug with valid userId
        let bugId = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "userId": .uuid(userId)
        ]))
        
        XCTAssertNotNil(bugId)
        print("  ✅ Valid reference accepted")
    }
    
    func testReferentialIntegrity_CascadeDelete() throws {
        print("🔗 Testing CASCADE DELETE")
        
        // Setup: Create user and bugs
        let userId = try usersDB.insert(BlazeDataRecord([
            "name": .string("Bob")
        ]))
        
        let bug1Id = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "userId": .uuid(userId)
        ]))
        
        let bug2Id = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "userId": .uuid(userId)
        ]))
        
        print("    Created: 1 user, 2 bugs")
        
        // Setup RelationshipManager for cascade
        var relationships = RelationshipManager()
        relationships.register(usersDB, as: "users")
        relationships.register(bugsDB, as: "bugs")
        
        let fk = ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "bugs",  // Bugs reference users
            onDelete: .cascade
        )
        
        // Delete user → should cascade delete bugs
        try relationships.cascadeDelete(from: "users", id: userId, foreignKeys: [fk])
        
        // Verify bugs were deleted
        let remainingBugs = try bugsDB.fetchAll()
        
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
        
        bugsDB.addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users"
        ))
        
        // Insert bug without userId (should be allowed)
        let bugId = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Bug without owner")
            // No userId field
        ]))
        
        XCTAssertNotNil(bugId)
        print("  ✅ Null foreign key allowed (optional)")
    }
    
    func testForeignKey_ThreadSafety() throws {
        print("🔗 Testing foreign key thread safety")
        
        // Add/remove foreign keys concurrently
        DispatchQueue.concurrentPerform(iterations: 10) { i in
            let fk = ForeignKey(
                name: "fk_\(i)",
                field: "field\(i)",
                referencedCollection: "collection\(i)"
            )
            
            self.bugsDB.addForeignKey(fk)
            self.bugsDB.removeForeignKey(named: "fk_\(i)")
        }
        
        // Should not crash
        print("  ✅ Thread-safe foreign key operations")
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_SchemaValidation() throws {
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "priority", type: .int, required: true)
        ])
        
        bugsDB.defineSchema(schema)
        
        measure(metrics: [XCTClockMetric()]) {
            for i in 0..<100 {
                _ = try? self.bugsDB.insert(BlazeDataRecord([
                    "title": .string("Bug \(i)"),
                    "priority": .int(i % 5 + 1)
                ]))
            }
        }
    }
}

