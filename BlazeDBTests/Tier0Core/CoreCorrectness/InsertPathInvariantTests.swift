import Foundation
import XCTest
@testable import BlazeDBCore

/// Regression tests for #379: all public insert paths must honor the same constraints and triggers.
final class InsertPathInvariantTests: XCTestCase {
    private let password = "InsertPathInvariant-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("insert-path-invariant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertWithExplicitIDHonorsUniqueConstraintLikeInsert() throws {
        let url = tempDir.appendingPathComponent("explicit-id-unique.blazedb")
        let db = try BlazeDBClient(name: "ExplicitIDUnique", fileURL: url, password: password)
        defer { try? db.close() }

        try db.createUniqueIndex(on: "email")
        _ = try db.insert(BlazeDataRecord(["email": .string("dup@example.com")]))

        XCTAssertThrowsError(
            try db.insert(BlazeDataRecord(["email": .string("dup@example.com")]), id: UUID()),
            "insert(_:id:) should enforce the same unique constraint as insert()"
        )
    }

    func testInsertManyHonorsUniqueConstraintAgainstExistingRows() throws {
        let url = tempDir.appendingPathComponent("insert-many-unique-existing.blazedb")
        let db = try BlazeDBClient(name: "InsertManyUniqueExisting", fileURL: url, password: password)
        defer { try? db.close() }

        try db.createUniqueIndex(on: "email")
        _ = try db.insert(BlazeDataRecord(["email": .string("dup@example.com")]))

        XCTAssertThrowsError(
            try db.insertMany([BlazeDataRecord(["email": .string("dup@example.com")])]),
            "insertMany() should reject a unique constraint violation against existing rows"
        )
    }

    func testInsertManyHonorsUniqueConstraintWithinSameBatch() throws {
        let url = tempDir.appendingPathComponent("insert-many-unique-batch.blazedb")
        let db = try BlazeDBClient(name: "InsertManyUniqueBatch", fileURL: url, password: password)
        defer { try? db.close() }

        try db.createUniqueIndex(on: "email")

        XCTAssertThrowsError(
            try db.insertMany([
                BlazeDataRecord(["email": .string("dup@example.com")]),
                BlazeDataRecord(["email": .string("dup@example.com")]),
            ]),
            "insertMany() should reject duplicate unique values inside the same batch"
        )
        XCTAssertEqual(
            try db.count(),
            0,
            "A failed same-batch unique check must not leave any rows from that batch"
        )
    }

    func testInsertManyHonorsCheckConstraintsLikeInsert() throws {
        let url = tempDir.appendingPathComponent("insert-many-check.blazedb")
        let db = try BlazeDBClient(name: "InsertManyCheck", fileURL: url, password: password)
        defer { try? db.close() }

        db.addCheckConstraint(CheckConstraint(name: "adult", field: "age") { record in
            (record.storage["age"]?.intValue ?? 0) >= 18
        })

        XCTAssertThrowsError(
            try db.insert(BlazeDataRecord(["age": .int(15)])),
            "insert() should reject a check-constraint violation"
        )
        XCTAssertThrowsError(
            try db.insertMany([BlazeDataRecord(["age": .int(15)])]),
            "insertMany() should reject the same check-constraint violation"
        )
    }

    func testInsertManyRunsInsertTriggersLikeInsert() throws {
        let url = tempDir.appendingPathComponent("insert-many-trigger.blazedb")
        let db = try BlazeDBClient(name: "InsertManyTrigger", fileURL: url, password: password)
        defer { try? db.close() }

        db.onInsert { _, modified, _ in
            modified?.storage["triggered"] = .string("yes")
        }

        let ids = try db.insertMany([BlazeDataRecord(["name": .string("bulk")])])
        let fetched = try db.fetch(id: ids[0])
        XCTAssertEqual(
            fetched?.storage["triggered"]?.stringValue,
            "yes",
            "insertMany() should apply the same trigger side effects as insert()"
        )
    }
}
