import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// A successful delete must not come back when crash recovery replays the WAL.
///
/// Insert publishes the record in the catalog and leaves its page image in the
/// legacy WAL until checkpoint. `delete()` zeros that page in the main file but,
/// before the tombstone, did not append a WAL record. The next open replayed the
/// earlier image onto a catalog that still listed the id, so the deleted record
/// was readable again. `close()`/`persist()` hid this by checkpointing and then
/// saving the catalog.
final class DeleteWALReplayTests: XCTestCase {
    private let password = "DeleteWALReplay-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-wal-replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCrashAfterDeleteDoesNotRestoreTheRecord() throws {
        let url = tempDir.appendingPathComponent("records.blazedb")
        let db = try BlazeDBClient(name: "DeleteWALReplay", fileURL: url, password: password)

        let keeper = try db.insert(BlazeDataRecord(["title": .string("keeper")]))
        try db.persist()
        let secret = try db.insert(BlazeDataRecord(["title": .string("secret")]))
        try db.delete(id: secret)

        let crashDir = tempDir.appendingPathComponent("crash-copy", isDirectory: true)
        try FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)
        let crashURL = crashDir.appendingPathComponent("records.blazedb")
        try copyDatabaseArtifacts(from: url, to: crashURL)
        try db.close()

        let reopened = try BlazeDBClient(name: "DeleteWALReplay", fileURL: crashURL, password: password)
        defer { try? reopened.close() }

        let deleted = try reopened.fetch(id: secret)
        XCTAssertNil(deleted?.storage["title"]?.stringValue)
        let kept = try reopened.fetch(id: keeper)
        XCTAssertEqual(kept?.storage["title"]?.stringValue, "keeper")
    }

    /// Copy the database and its sidecars without checkpointing. This is the
    /// on-disk state a crash leaves behind after `delete()` returns.
    private func copyDatabaseArtifacts(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        let sourceDir = source.deletingLastPathComponent()
        let destDir = dest.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let names = try fm.contentsOfDirectory(atPath: sourceDir.path)
        var copiedWAL = false
        for name in names where name == source.lastPathComponent || name.hasPrefix(base + ".") {
            try fm.copyItem(
                at: sourceDir.appendingPathComponent(name),
                to: destDir.appendingPathComponent(name)
            )
            if name.hasSuffix(".wal") {
                copiedWAL = true
            }
        }
        XCTAssertTrue(copiedWAL, "Crash snapshot is missing the WAL sidecar")
        XCTAssertTrue(fm.fileExists(atPath: dest.path))
    }
}
