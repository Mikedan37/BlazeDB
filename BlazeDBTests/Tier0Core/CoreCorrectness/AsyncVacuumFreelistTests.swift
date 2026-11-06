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
            for ext in ["meta", "wal", "salt", "backup", "vacuum_backup.blazedb", "vacuum_backup.meta", "vacuum.blazedb", "vacuum.meta", "vacuum_in_progress", "vacuum_success"] {
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
    }

    func testAsyncVacuumWithNoDeletesReportsNoReclaimedPages() async throws {
        let db = try BlazeDBClient(name: "async-vacuum-stats", fileURL: databaseURL, password: password)
        defer { try? db.close() }
        _ = try await db.insert(BlazeDataRecord(["marker": .string("a")]))
        _ = try await db.insert(BlazeDataRecord(["marker": .string("b")]))
        try await db.persist()

        let stats = try await db.vacuum()
        XCTAssertEqual(stats.pagesBefore, 2)
        XCTAssertEqual(stats.pagesAfter, 2)
        XCTAssertEqual(stats.pagesReclaimed, 0)
        XCTAssertEqual(stats.sizeReclaimed, 0)
    }

    func testAsyncVacuumPreservesOverflowRecordAcrossReopen() async throws {
        let db = try BlazeDBClient(name: "async-vacuum-overflow", fileURL: databaseURL, password: password)
        let payload = String(repeating: "o", count: 6_000)
        let small = try await db.insert(BlazeDataRecord(["marker": .string("small")]))
        let large = try await db.insert(BlazeDataRecord([
            "marker": .string("large"),
            "payload": .string(payload)
        ]))
        let dropped = try await db.insert(BlazeDataRecord(["marker": .string("drop")]))
        try await db.delete(id: dropped)
        try await db.persist()

        _ = try await db.vacuum()

        let live = try await db.fetch(id: large)
        XCTAssertEqual(live?.storage["payload"]?.stringValue, payload)
        try db.close()

        let reopened = try BlazeDBClient(name: "async-vacuum-overflow", fileURL: databaseURL, password: password)
        defer { try? reopened.close() }
        let again = try await reopened.fetch(id: large)
        XCTAssertEqual(again?.storage["payload"]?.stringValue, payload, "Overflow record did not survive vacuum reopen")
        let smallMarker = try await marker(of: small, in: reopened)
        XCTAssertEqual(smallMarker, "small")
    }

    func testAsyncVacuumRenameFailureLeavesRecordsReadable() async throws {
        let db = try BlazeDBClient(name: "async-vacuum-rename", fileURL: databaseURL, password: password)
        defer { try? db.close() }
        let id = try await db.insert(BlazeDataRecord(["marker": .string("keep")]))
        try await db.persist()

        setenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE", "1", 1)
        defer { unsetenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE") }

        do {
            _ = try await db.vacuum()
            XCTFail("Vacuum should surface the simulated rename failure and keep the original file")
        } catch {
            let kept = try await marker(of: id, in: db)
            XCTAssertEqual(kept, "keep")
        }
    }

    private func marker(of id: UUID, in db: BlazeDBClient) async throws -> String? {
        guard let record = try await db.fetch(id: id) else { return nil }
        if case let .string(value)? = record.storage["marker"] {
            return value
        }
        return nil
    }
}
