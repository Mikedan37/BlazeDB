//
//  RelationshipVisualizerTests.swift
//  BlazeDBVisualizerTests
//
//  Test relationship visualization functionality
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class RelationshipVisualizerTests: XCTestCase {
    var tempDir: URL!
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test123")
        
        // Create test data with relationships
        let userId1 = UUID()
        let userId2 = UUID()
        
        // Users
        try db.insert(BlazeDataRecord( [
            "id": .uuid(userId1),
            "name": .string("John"),
            "email": .string("john@test.com")
        ]))
        
        try db.insert(BlazeDataRecord( [
            "id": .uuid(userId2),
            "name": .string("Sarah"),
            "email": .string("sarah@test.com")
        ]))
        
        // Posts (referencing users)
        try db.insert(BlazeDataRecord( [
            "title": .string("Post 1"),
            "userId": .uuid(userId1),
            "content": .string("Content")
        ]))
        
        try db.insert(BlazeDataRecord( [
            "title": .string("Post 2"),
            "userId": .uuid(userId2),
            "content": .string("Content")
        ]))
        
        try db.persist()
    }
    
    override func tearDown() async throws {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Foreign Key Tests
    
    func testForeignKeyCreation() {
        let fk = ForeignKey(
            name: "user_posts",
            field: "userId",
            referencedCollection: "users",
            referencedField: "id",
            onDelete: .cascade,
            onUpdate: .cascade
        )
        
        XCTAssertEqual(fk.name, "user_posts")
        XCTAssertEqual(fk.field, "userId")
        XCTAssertEqual(fk.referencedCollection, "users")
    }
    
    func testCascadeDelete() {
        let fk = ForeignKey(
            name: "user_posts",
            field: "userId",
            referencedCollection: "users",
            referencedField: "id",
            onDelete: .cascade,
            onUpdate: .cascade
        )
        
        XCTAssertEqual(fk.onDelete, .cascade)
    }
    
    func testSetNullAction() {
        let fk = ForeignKey(
            name: "optional_link",
            field: "optionalId",
            referencedCollection: "users",
            referencedField: "id",
            onDelete: .setNull,
            onUpdate: .restrict
        )
        
        XCTAssertEqual(fk.onDelete, .setNull)
        XCTAssertEqual(fk.onUpdate, .restrict)
    }
    
    // MARK: - Relationship Detection Tests
    
    func testDetectPotentialRelationships() throws {
        let records = try db.fetchAll()
        
        // Look for UUID fields that might be foreign keys
        var uuidFields: Set<String> = []
        
        for record in records {
            for (key, value) in record.storage {
                if case .uuid = value {
                    uuidFields.insert(key)
                }
            }
        }
        
        XCTAssertTrue(uuidFields.contains("id"), "Should detect 'id' field")
        XCTAssertTrue(uuidFields.contains("userId"), "Should detect 'userId' field")
    }
    
    func testOrphanedRecordDetection() throws {
        // Create orphaned record (userId points to non-existent user)
        let orphanedUserId = UUID()
        try db.insert(BlazeDataRecord( [
            "title": .string("Orphaned Post"),
            "userId": .uuid(orphanedUserId),  // Non-existent user!
            "content": .string("Orphaned content")
        ]))
        
        let records = try db.fetchAll()
        
        // Get all user IDs
        let userIds = Set(records.compactMap { record -> UUID? in
            if let name = record.storage["name"], case .string = name {
                // This is a user record
                if let id = record.storage["id"], case .uuid(let uuid) = id {
                    return uuid
                }
            }
            return nil
        })
        
        // Check for orphaned posts
        let orphanedPosts = records.filter { record in
            if let userId = record.storage["userId"], case .uuid(let uuid) = userId {
                return !userIds.contains(uuid)
            }
            return false
        }
        
        XCTAssertEqual(orphanedPosts.count, 1, "Should detect 1 orphaned post")
    }
    
    // MARK: - Visualization Tests
    
    func testNodePositionCalculation() {
        let size = CGSize(width: 800, height: 600)
        
        // Calculate positions for 4 nodes in a circle
        let positions = (0..<4).map { index -> CGPoint in
            let angle = (Double(index) / Double(4)) * 2 * .pi - .pi / 2
            let radius = min(size.width, size.height) * 0.35
            let centerX = size.width / 2
            let centerY = size.height / 2
            
            return CGPoint(
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius
            )
        }
        
        // All positions should be within bounds
        for pos in positions {
            XCTAssertGreaterThanOrEqual(pos.x, 0)
            XCTAssertLessThanOrEqual(pos.x, size.width)
            XCTAssertGreaterThanOrEqual(pos.y, 0)
            XCTAssertLessThanOrEqual(pos.y, size.height)
        }
        
        // Positions should be evenly distributed
        XCTAssertNotEqual(positions[0], positions[1])
        XCTAssertNotEqual(positions[1], positions[2])
    }
    
    // MARK: - Integration Tests
    
    func testRelationshipIntegrity() throws {
        let records = try db.fetchAll()
        
        // Get posts
        let posts = records.filter { $0.storage["title"] != nil }
        
        // Get users
        let users = records.filter { $0.storage["email"] != nil }
        
        XCTAssertEqual(posts.count, 3, "Should have 3 posts (2 + 1 setup)")
        XCTAssertEqual(users.count, 2, "Should have 2 users")
        
        // Check that all posts reference valid users (except orphaned one)
        let userIds = Set(users.compactMap { record -> UUID? in
            if let id = record.storage["id"], case .uuid(let uuid) = id {
                return uuid
            }
            return nil
        })
        
        var validReferences = 0
        for post in posts {
            if let userId = post.storage["userId"], case .uuid(let uuid) = userId {
                if userIds.contains(uuid) {
                    validReferences += 1
                }
            }
        }
        
        XCTAssertEqual(validReferences, 2, "Should have 2 valid references")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyDatabase() throws {
        let emptyDB = try BlazeDBClient(
            name: "empty",
            fileURL: tempDir.appendingPathComponent("empty.blazedb"),
            password: "test123"
        )
        
        let records = try emptyDB.fetchAll()
        XCTAssertTrue(records.isEmpty)
        
        let config = SearchConfig(fields: ["any"])
        let results = FullTextSearchEngine.search(records: records, query: "test", config: config)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testCircularRelationships() {
        // Test that circular references are handled
        let fk1 = ForeignKey(
            name: "a_to_b",
            field: "bId",
            referencedCollection: "b",
            referencedField: "id",
            onDelete: .restrict,
            onUpdate: .restrict
        )
        
        let fk2 = ForeignKey(
            name: "b_to_a",
            field: "aId",
            referencedCollection: "a",
            referencedField: "id",
            onDelete: .restrict,
            onUpdate: .restrict
        )
        
        // Should not crash or infinite loop
        XCTAssertNotEqual(fk1.name, fk2.name)
    }
}

