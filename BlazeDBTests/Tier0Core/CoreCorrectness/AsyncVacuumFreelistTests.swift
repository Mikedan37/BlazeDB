import Foundation
import XCTest
@testable import BlazeDBCore

/// Async vacuum rewrites live pages at low indexes. The saved layout must not
/// keep the pre-compaction freelist, or the next insert reuses a live page.
final class AsyncVacuumFreelistTests: XCTestCase {
    private let password = "AsyncVacuumFreelist-Test-2026!"
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsyncVacuumFreelist-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        if let databaseURL {
            let sidecarBase = databaseURL.deletingPathExtension()
            for ext in ["meta", "wal", "salt", "backup"] {
                try? FileManager.default.removeItem(at: sidecarBase.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: databaseURL)
        }
        super.tearDown()
    }

    func testAsyncVacuumDoesNotOverwriteSurvivorsOnNextInsert() async throws {
        let db = try BlazeDBClient(name: "async-vacuum-freelist", fileURL: databaseURL, password: password)
        defer { try? db.close() }

        let keepA = try await db.insert(BlazeDataRecord(["marker": .string("keep-a")]))
        let dropped = try await db.insert(BlazeDataRecord(["marker": .string("drop")]))
        let keepB = try await db.insert(BlazeDataRecord(["marker": .string("keep-b")]))
        try await db.delete(id: dropped)
        try await db.persist()

        _ = try await db.vacuum()
        _ = try await db.insert(BlazeDataRecord(["marker": .string("after-vacuum")]))

        let markerA = try await marker(of: keepA, in: db)
        let markerB = try await marker(of: keepB, in: db)
        XCTAssertEqual(markerA, "keep-a", "Survivor keep-a was overwritten after vacuum")
        XCTAssertEqual(markerB, "keep-b", "Survivor keep-b was overwritten after vacuum")

        try db.close()
        let reopened = try BlazeDBClient(name: "async-vacuum-freelist-reopen", fileURL: databaseURL, password: password)
        defer { try? reopened.close() }
        let reopenedA = try await marker(of: keepA, in: reopened)
        let reopenedB = try await marker(of: keepB, in: reopened)
        XCTAssertEqual(reopenedA, "keep-a")
        XCTAssertEqual(reopenedB, "keep-b")
    }

    /// Inserts stay in the legacy WAL until checkpoint. Async vacuum used to open a
    /// second store on `name.blazedb.vacuum-…`, which is the live `name.blazedb.wal`,
    /// and replay cleared that log. A crash before the compacted file replaced the
    /// database then lost the committed rows. The gap (delete the middle record)
    /// also used to publish the compacted catalog before the data file moved, so
    /// the last survivor was read from the deleted page.
    func testCommittedRecordsSurviveCrashDuringAsyncVacuum() async throws {
        let db = try BlazeDBClient(name: "async-vacuum-crash", fileURL: databaseURL, password: password)
        let keepA = try await db.insert(BlazeDataRecord(["marker": .string("keep-a")]))
        let dropped = try await db.insert(BlazeDataRecord(["marker": .string("drop")]))
        let keepB = try await db.insert(BlazeDataRecord(["marker": .string("keep-b")]))
        try await db.delete(id: dropped)

        setenv("BLAZEDB_CRASH_ASYNC_VACUUM_BEFORE_SWAP", "1", 1)
        defer { unsetenv("BLAZEDB_CRASH_ASYNC_VACUUM_BEFORE_SWAP") }
        do {
            _ = try await db.vacuum()
            XCTFail("Vacuum should stop before replacing the live files")
        } catch {
            // The fault closes the store without applying a later WAL rewrite.
        }
        unsetenv("BLAZEDB_CRASH_ASYNC_VACUUM_BEFORE_SWAP")
        try? db.close()

        let reopened = try BlazeDBClient(name: "async-vacuum-crash-reopen", fileURL: databaseURL, password: password)
        defer { try? reopened.close() }
        let reopenedA = try await marker(of: keepA, in: reopened)
        let reopenedB = try await marker(of: keepB, in: reopened)
        XCTAssertEqual(reopenedA, "keep-a")
        XCTAssertEqual(reopenedB, "keep-b")
        let droppedRecord = try await reopened.fetch(id: dropped)
        XCTAssertNil(droppedRecord)
    }

    private func marker(of id: UUID, in db: BlazeDBClient) async throws -> String? {
        guard let record = try await db.fetch(id: id) else { return nil }
        if case let .string(value)? = record.storage["marker"] {
            return value
        }
        return nil
    }
}
