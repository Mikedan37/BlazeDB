//
//  UniqueConstraintDurabilityTests.swift
//  BlazeDBTests
//
//  Unique indexes are a catalog constraint. Closing and reopening the database
//  must keep rejecting duplicate values.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class UniqueConstraintDurabilityTests: XCTestCase {
    private let password = "UniqueConstraint-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unique-constraint-durability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testUniqueIndexRejectsDuplicateAfterReopen() throws {
        let url = tempDir.appendingPathComponent("email.blazedb")
        let created = try BlazeDBClient(name: "UniqueEmail", fileURL: url, password: password)
        try created.createUniqueIndex(on: "email")
        _ = try created.insert(BlazeDataRecord(["email": .string("a@example.com")]))
        let metaAfterInsert = try created.collection.fetchMeta()
        XCTAssertEqual(
            metaAfterInsert[BlazeDBClient.uniqueFieldsMetaKey]?.arrayValue?.compactMap(\.stringValue),
            ["email"],
            "insert republished the catalog without the unique constraint; keys=\(metaAfterInsert.keys.sorted())"
        )
        try created.close()

        let reopened = try BlazeDBClient(name: "UniqueEmail", fileURL: url, password: password)
        defer { try? reopened.close() }

        XCTAssertThrowsError(
            try reopened.insert(BlazeDataRecord(["email": .string("a@example.com")])),
            "A reopened database must still reject a duplicate unique value"
        ) { error in
            guard case BlazeDBError.transactionFailed = error else {
                return XCTFail("Expected unique constraint failure, got \(error)")
            }
        }
        _ = try reopened.insert(BlazeDataRecord(["email": .string("b@example.com")]))
        XCTAssertEqual(try reopened.count(), 2)
    }

    func testUniqueCompoundIndexRejectsDuplicateAfterReopen() throws {
        let url = tempDir.appendingPathComponent("team-email.blazedb")
        let created = try BlazeDBClient(name: "UniqueTeamEmail", fileURL: url, password: password)
        try created.createUniqueCompoundIndex(on: ["team", "email"])
        _ = try created.insert(BlazeDataRecord([
            "team": .string("red"),
            "email": .string("a@example.com")
        ]))
        try created.close()

        let reopened = try BlazeDBClient(name: "UniqueTeamEmail", fileURL: url, password: password)
        defer { try? reopened.close() }

        XCTAssertThrowsError(
            try reopened.insert(BlazeDataRecord([
                "team": .string("red"),
                "email": .string("a@example.com")
            ]))
        )
        _ = try reopened.insert(BlazeDataRecord([
            "team": .string("blue"),
            "email": .string("a@example.com")
        ]))
        XCTAssertEqual(try reopened.count(), 2)
    }
}
