import Foundation
import XCTest
@testable import BlazeDBCore

/// Regression for #467: afterInsert is post-commit. Failures must not fail the insert API
/// or leave callers thinking a durable write rolled back.
final class AfterInsertPostCommitTests: XCTestCase {
    private let password = "AfterInsert-PostCommit-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("after-insert-postcommit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertSucceedsWhenAfterInsertTriggerThrows() throws {
        let url = tempDir.appendingPathComponent("insert-after-throw.blazedb")
        let db = try BlazeDBClient(name: "AfterInsertInsert", fileURL: url, password: password)
        defer { try? db.close() }

        db.createTrigger(name: "boom", event: .afterInsert) { _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "afterInsert boom"
            ])
        }

        let id = try db.insert(BlazeDataRecord(["name": .string("kept")]))
        XCTAssertEqual(try db.count(), 1)
        XCTAssertEqual(try db.fetch(id: id)?.storage["name"]?.stringValue, "kept")
    }

    func testInsertManySucceedsWhenLaterAfterInsertTriggerThrows() throws {
        let url = tempDir.appendingPathComponent("insert-many-after-throw.blazedb")
        let db = try BlazeDBClient(name: "AfterInsertInsertMany", fileURL: url, password: password)
        defer { try? db.close() }

        var seen = 0
        db.createTrigger(name: "boom-second", event: .afterInsert) { _, _ in
            seen += 1
            if seen == 2 {
                throw NSError(domain: "AfterInsertPostCommit", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "second afterInsert boom"
                ])
            }
        }

        let ids = try db.insertMany([
            BlazeDataRecord(["name": .string("a")]),
            BlazeDataRecord(["name": .string("b")]),
        ])
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(try db.count(), 2)
        XCTAssertEqual(seen, 2, "Both afterInsert handlers should still run")
    }

    func testBeforeInsertTriggerFailureStillRejectsWrite() throws {
        let url = tempDir.appendingPathComponent("before-insert-throw.blazedb")
        let db = try BlazeDBClient(name: "BeforeInsertReject", fileURL: url, password: password)
        defer { try? db.close() }

        db.createTrigger(name: "reject", event: .beforeInsert) { _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "beforeInsert reject"
            ])
        }

        XCTAssertThrowsError(try db.insert(BlazeDataRecord(["name": .string("blocked")])))
        XCTAssertEqual(try db.count(), 0)
    }

    /// `onInsert` is enhanced beforeInsert. This PR changed enhanced BEFORE from
    /// swallow-all to rethrow; lock that intentional behavior change.
    func testEnhancedOnInsertThrowRejectsWrite() throws {
        let url = tempDir.appendingPathComponent("enhanced-oninsert-throw.blazedb")
        let db = try BlazeDBClient(name: "EnhancedOnInsertReject", fileURL: url, password: password)
        defer { try? db.close() }

        db.onInsert { _, _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "enhanced onInsert reject"
            ])
        }

        XCTAssertThrowsError(try db.insert(BlazeDataRecord(["name": .string("blocked")])))
        XCTAssertEqual(try db.count(), 0)
    }

    func testUpdateSucceedsWhenAfterUpdateTriggerThrows() throws {
        let url = tempDir.appendingPathComponent("update-after-throw.blazedb")
        let db = try BlazeDBClient(name: "AfterUpdatePostCommit", fileURL: url, password: password)
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["name": .string("before")]))
        db.createTrigger(name: "boom", event: .afterUpdate) { _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 5)
        }

        try db.update(id: id, with: BlazeDataRecord(["name": .string("after")]))
        XCTAssertEqual(try db.fetch(id: id)?.storage["name"]?.stringValue, "after")
    }

    func testDeleteSucceedsWhenAfterDeleteTriggerThrows() throws {
        let url = tempDir.appendingPathComponent("delete-after-throw.blazedb")
        let db = try BlazeDBClient(name: "AfterDeletePostCommit", fileURL: url, password: password)
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["name": .string("kept")]))
        db.createTrigger(name: "boom", event: .afterDelete) { _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 6)
        }

        try db.delete(id: id)
        XCTAssertNil(try db.fetch(id: id))
        XCTAssertEqual(try db.count(), 0)
    }

    func testBeforeUpdateTriggerFailurePreservesRecord() throws {
        let url = tempDir.appendingPathComponent("before-update-throw.blazedb")
        let db = try BlazeDBClient(name: "BeforeUpdateReject", fileURL: url, password: password)
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["name": .string("original")]))
        db.createTrigger(name: "reject", event: .beforeUpdate) { _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 7)
        }

        XCTAssertThrowsError(try db.update(id: id, with: BlazeDataRecord(["name": .string("changed")])))
        XCTAssertEqual(try db.fetch(id: id)?.storage["name"]?.stringValue, "original")
        XCTAssertEqual(try db.count(), 1)
    }

    func testBeforeDeleteTriggerFailurePreservesRecord() throws {
        let url = tempDir.appendingPathComponent("before-delete-throw.blazedb")
        let db = try BlazeDBClient(name: "BeforeDeleteReject", fileURL: url, password: password)
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["name": .string("original")]))
        db.createTrigger(name: "reject", event: .beforeDelete) { _, _ in
            throw NSError(domain: "AfterInsertPostCommit", code: 8)
        }

        XCTAssertThrowsError(try db.delete(id: id))
        XCTAssertEqual(try db.fetch(id: id)?.storage["name"]?.stringValue, "original")
        XCTAssertEqual(try db.count(), 1)
    }
}
