import Foundation
import XCTest
@testable import BlazeDBCore

/// Rollback must restore records that do not fit in a single page.
/// `writePage` rejects those payloads, so an in-transaction shrink of an
/// overflow record used to survive `rollbackTransaction()`.
final class OverflowRollbackTests: XCTestCase {
    private let password = "OverflowRollback-Test-2026!"
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverflowRollback-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        if let databaseURL {
            let sidecarBase = databaseURL.deletingPathExtension()
            for ext in ["meta", "wal", "salt"] {
                try? FileManager.default.removeItem(at: sidecarBase.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: databaseURL)
        }
        super.tearDown()
    }

    func testRollbackRestoresOverflowRecordAfterShrink() throws {
        let db = try BlazeDBClient(name: "overflow-rollback", fileURL: databaseURL, password: password)
        defer { try? db.close() }

        let original = String(repeating: "A", count: 8_000)
        let id = try db.insert(BlazeDataRecord([
            "body": .string(original),
            "status": .string("draft")
        ]))
        XCTAssertEqual(try db.fetch(id: id)?.storage["body"]?.stringValue, original)

        try db.beginTransaction()
        try db.update(id: id, with: BlazeDataRecord([
            "id": .uuid(id),
            "body": .string("short"),
            "status": .string("published")
        ]))
        XCTAssertEqual(try db.fetch(id: id)?.storage["status"]?.stringValue, "published")

        try db.rollbackTransaction()

        let restored = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(restored.storage["status"]?.stringValue, "draft")
        XCTAssertEqual(restored.storage["body"]?.stringValue, original)

        try db.close()
        let reopened = try BlazeDBClient(name: "overflow-rollback", fileURL: databaseURL, password: password)
        defer { try? reopened.close() }
        let durable = try XCTUnwrap(reopened.fetch(id: id))
        XCTAssertEqual(durable.storage["status"]?.stringValue, "draft")
        XCTAssertEqual(durable.storage["body"]?.stringValue, original)
    }
}
