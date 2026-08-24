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
}
