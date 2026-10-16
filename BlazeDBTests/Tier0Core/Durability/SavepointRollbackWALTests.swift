import XCTest
@testable import BlazeDBCore

/// `rollbackToSavepoint` replaces the data file with the snapshot taken at
/// `savepoint`. Opening that file replays the live WAL, which still holds page
/// images written after the snapshot. Those images land on pages the snapshot
/// catalog still names.
final class SavepointRollbackWALTests: XCTestCase {
    private var tempDir: URL!
    private let password = "SavepointRollbackWAL-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("savepoint-wal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testRollbackToSavepointKeepsTheSnapshotValue() throws {
        let url = tempDir.appendingPathComponent("update.blazedb")
        let db = try BlazeDBClient(name: "savepoint-update", fileURL: url, password: password)
        let id = try db.insert(BlazeDataRecord(["title": .string("original")]))
        try db.beginTransaction()
        try db.savepoint("sp1")
        try db.update(id: id, with: BlazeDataRecord(["title": .string("mutated")]))

        try db.rollbackToSavepoint("sp1")

        XCTAssertEqual(try db.fetch(id: id)?.storage["title"]?.stringValue, "original")
        try db.commitTransaction()
        try db.close()

        let reopened = try BlazeDBClient(name: "savepoint-update", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: id)?.storage["title"]?.stringValue, "original")
        XCTAssertEqual(try reopened.count(), 1)
    }

    func testRollbackToSavepointDoesNotPutAReusedPageUnderTheSnapshotRecord() throws {
        let url = tempDir.appendingPathComponent("reuse.blazedb")
        let db = try BlazeDBClient(name: "savepoint-reuse", fileURL: url, password: password)
        let keep = try db.insert(BlazeDataRecord(["title": .string("keep")]))
        let drop = try db.insert(BlazeDataRecord(["title": .string("drop")]))
        try db.beginTransaction()
        try db.savepoint("sp1")

        try db.delete(id: drop)
        let created = try db.insert(BlazeDataRecord(["title": .string("newcomer")]))
        try db.rollbackToSavepoint("sp1")

        XCTAssertEqual(try db.fetch(id: keep)?.storage["title"]?.stringValue, "keep")
        XCTAssertEqual(try db.fetch(id: drop)?.storage["title"]?.stringValue, "drop")
        XCTAssertNil(try db.fetch(id: created))
        try db.commitTransaction()
        try db.close()

        let reopened = try BlazeDBClient(name: "savepoint-reuse", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: drop)?.storage["title"]?.stringValue, "drop")
        XCTAssertNil(try reopened.fetch(id: created))
    }

    func testRollbackToSavepointKeepsARecordInsertedBeforeIt() throws {
        let url = tempDir.appendingPathComponent("before.blazedb")
        let db = try BlazeDBClient(name: "savepoint-before", fileURL: url, password: password)
        try db.beginTransaction()
        let kept = try db.insert(BlazeDataRecord(["title": .string("kept")]))
        try db.savepoint("sp1")
        let dropped = try db.insert(BlazeDataRecord(["title": .string("dropped")]))

        try db.rollbackToSavepoint("sp1")

        XCTAssertEqual(try db.fetch(id: kept)?.storage["title"]?.stringValue, "kept")
        XCTAssertNil(try db.fetch(id: dropped))
        XCTAssertEqual(try db.count(), 1)
        try db.rollbackTransaction()
        XCTAssertEqual(try db.count(), 0)
        try db.close()
    }

    func testCommitKeepsAnUpdateMadeAfterASavepoint() throws {
        let url = tempDir.appendingPathComponent("commit.blazedb")
        let db = try BlazeDBClient(name: "savepoint-commit", fileURL: url, password: password)
        let id = try db.insert(BlazeDataRecord(["title": .string("original")]))
        try db.beginTransaction()
        try db.savepoint("sp1")
        try db.update(id: id, with: BlazeDataRecord(["title": .string("mutated")]))
        try db.commitTransaction()
        XCTAssertEqual(try db.fetch(id: id)?.storage["title"]?.stringValue, "mutated")
        try db.close()

        let reopened = try BlazeDBClient(name: "savepoint-commit", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: id)?.storage["title"]?.stringValue, "mutated")
    }
}
