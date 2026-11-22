import Foundation
import XCTest
@testable import BlazeDBCore

/// Cascade delete must remove child rows that declare the foreign key.
/// It must not delete the referenced parent, or an unrelated collection that
/// merely stores the same field name.
final class CascadeDeleteTargetTests: XCTestCase {
    private let password = "CascadeDeleteTarget-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cascade-delete-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCascadeDeleteRemovesChildrenAndKeepsReferencedRow() throws {
        let users = try open("users")
        let bugs = try open("bugs")
        let notes = try open("notes")
        defer {
            try? users.close()
            try? bugs.close()
            try? notes.close()
        }

        let userID = UUID()
        // The parent stores the same field name as the child foreign key.
        // The old lookup treated that as a match and deleted this row.
        _ = try users.insert(BlazeDataRecord([
            "id": .uuid(userID),
            "name": .string("Ada"),
            "userId": .uuid(userID)
        ]))

        let otherUserID = try users.insert(BlazeDataRecord(["name": .string("Grace")]))
        _ = try bugs.insert(BlazeDataRecord([
            "title": .string("owned"),
            "userId": .uuid(userID)
        ]))
        _ = try bugs.insert(BlazeDataRecord([
            "title": .string("also owned"),
            "userId": .uuid(userID)
        ]))
        let otherBug = try bugs.insert(BlazeDataRecord([
            "title": .string("someone else"),
            "userId": .uuid(otherUserID)
        ]))
        let noteID = try notes.insert(BlazeDataRecord([
            "body": .string("not a child of this foreign key"),
            "userId": .uuid(userID)
        ]))

        bugs.addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        ))

        var relationships = RelationshipManager()
        relationships.register(users, as: "users")
        relationships.register(bugs, as: "bugs")
        relationships.register(notes, as: "notes")

        try relationships.cascadeDelete(
            from: "users",
            id: userID,
            foreignKeys: bugs.getForeignKeys()
        )

        let remainingBugs = try bugs.fetchAll()
        XCTAssertEqual(remainingBugs.count, 1)
        XCTAssertEqual(remainingBugs.first?.storage["id"]?.uuidValue, otherBug)
        XCTAssertNotNil(try users.fetch(id: userID), "Referenced user must survive cascade")
        XCTAssertNotNil(try notes.fetch(id: noteID), "Unrelated collection must not be cascade-deleted")
    }

    func testDeleteOfReferencingRowSucceedsWhenForeignKeyIsCascade() throws {
        let bugs = try open("bugs-direct")
        defer { try? bugs.close() }

        bugs.addForeignKey(ForeignKey(
            name: "bug_user_fk",
            field: "userId",
            referencedCollection: "users",
            onDelete: .cascade
        ))
        let bugID = try bugs.insert(BlazeDataRecord([
            "title": .string("owned"),
            "userId": .uuid(UUID())
        ]))

        try bugs.delete(id: bugID)

        XCTAssertNil(try bugs.fetch(id: bugID))
        XCTAssertEqual(try bugs.fetchAll().count, 0)
    }

    private func open(_ name: String) throws -> BlazeDBClient {
        try BlazeDBClient(
            name: name,
            fileURL: tempDir.appendingPathComponent("\(name).blazedb"),
            password: password
        )
    }
}
