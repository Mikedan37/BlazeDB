import Foundation
import XCTest
@testable import BlazeDBCore

/// `incrementalBackup` used to read only `updated_at` / `created_at`.
/// Inserts and updates stamp `createdAt` / `updatedAt`, so a normal database
/// produced an empty backup file.
final class IncrementalBackupTimestampTests: XCTestCase {
    private let password = "IncrementalBackup-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("incremental-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testIncrementalBackupIncludesEngineTimestampsAndUpdates() async throws {
        let url = tempDir.appendingPathComponent("db.blazedb")
        let db = try BlazeDBClient(name: "IncrementalBackup", fileURL: url, password: password)
        defer { try? db.close() }

        let untouchedId = try await db.insert(BlazeDataRecord([
            "name": .string("untouched"),
            "createdAt": .date(Date().addingTimeInterval(-86400 * 3))
        ]))
        _ = try await db.insert(BlazeDataRecord([
            "name": .string("fresh")
        ]))
        _ = try await db.insert(BlazeDataRecord([
            "name": .string("backfill"),
            "created_at": .date(Date().addingTimeInterval(-86400 * 3))
        ]))

        let fetched = try await db.fetch(id: untouchedId)
        var edited = try XCTUnwrap(fetched)
        edited.storage["name"] = .string("edited")
        try db.update(id: untouchedId, with: edited)

        let backupURL = tempDir.appendingPathComponent("incremental.json")
        let stats = try await db.incrementalBackup(
            to: backupURL,
            since: Date().addingTimeInterval(-3600)
        )

        let backedUp = try JSONDecoder().decode([BlazeDataRecord].self, from: Data(contentsOf: backupURL))
        let names = Set(backedUp.compactMap { $0.storage["name"]?.stringValue })

        XCTAssertEqual(stats.recordCount, 2)
        XCTAssertEqual(names, ["fresh", "edited"])
    }
}
