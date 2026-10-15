import XCTest
@testable import BlazeDBCore

/// `restore(from:)` replaces the database files with a backup snapshot.
/// The live WAL is not part of that snapshot. Replaying it onto the restored
/// file puts post-backup page images back under the backup catalog's ids.
final class RestoreDropsLiveWALTests: XCTestCase {
    private var tempDir: URL!
    private let password = "RestoreDropsLiveWAL-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-drops-wal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testRestoreKeepsTheBackupRecordInsteadOfReplayingALaterUpdate() throws {
        let url = tempDir.appendingPathComponent("live.blazedb")
        let backupURL = tempDir.appendingPathComponent("snapshot.blazedb")
        let db = try BlazeDBClient(name: "restore-wal", fileURL: url, password: password)
        let id = try db.insert(BlazeDataRecord(["title": .string("original")]))
        _ = try db.backup(to: backupURL)

        try db.update(id: id, with: BlazeDataRecord(["title": .string("mutated")]))
        try db.restore(from: backupURL)
        XCTAssertEqual(try db.fetch(id: id)?.storage["title"]?.stringValue, "original")
        try db.close()

        let reopened = try BlazeDBClient(name: "restore-wal", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: id)?.storage["title"]?.stringValue, "original")
        XCTAssertEqual(try reopened.count(), 1)
    }

    func testRestoreDoesNotPutAReusedPageBackUnderTheBackupRecord() throws {
        let url = tempDir.appendingPathComponent("reuse.blazedb")
        let backupURL = tempDir.appendingPathComponent("reuse-snapshot.blazedb")
        let db = try BlazeDBClient(name: "restore-reuse", fileURL: url, password: password)
        let keep = try db.insert(BlazeDataRecord(["title": .string("keep")]))
        let drop = try db.insert(BlazeDataRecord(["title": .string("drop")]))
        _ = try db.backup(to: backupURL)

        try db.delete(id: drop)
        let created = try db.insert(BlazeDataRecord(["title": .string("newcomer")]))
        try db.restore(from: backupURL)

        XCTAssertEqual(try db.fetch(id: keep)?.storage["title"]?.stringValue, "keep")
        XCTAssertEqual(try db.fetch(id: drop)?.storage["title"]?.stringValue, "drop")
        XCTAssertNil(try db.fetch(id: created))
        try db.close()

        let reopened = try BlazeDBClient(name: "restore-reuse", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: drop)?.storage["title"]?.stringValue, "drop")
        XCTAssertNil(try reopened.fetch(id: created))
    }
}
