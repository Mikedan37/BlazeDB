// Known-issue reproductions. Each test behind a `guard ... BLAZEDB_RUN_KNOWN_ISSUES` line asserts
// the intended behavior, fails on origin/main, and is skipped unless BLAZEDB_RUN_KNOWN_ISSUES=1,
// so the suite stays green until the fix lands. The PR that fixes an issue deletes that guard line,
// and the test then gates every run. Tests without the guard are controls and always run.

import Foundation
import XCTest
@testable import BlazeDBCore

/// Inserts acknowledged before a crash (no persist/close) must be readable after reopen.
///
/// Contract: the default path saves the catalog on every insert "to preserve crash-prefix durability"
/// (DynamicCollection.swift:1176-1181); Docs/Architecture/ARCHITECTURE_DETAILED.md:1022,1034
/// ("Committed data is fsync'd before acknowledgment"). Docs/Guarantees/SAFETY_MODEL.md:31 still says
/// in-flight writes may be lost before persist(); the MVCC fix must update that line.
final class MVCCCrashDurabilityReproTests: XCTestCase {
    private let password = "MVCCCrashRepro-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mvcc-crash-repro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        BlazeDBClient.clearCachedKey()
        try? FileManager.default.removeItem(at: tempDir)
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        super.tearDown()
    }

    func testMVCCInsert_CrashBeforePersist_AcknowledgedInsertsSurviveReopen() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: MVCC saves the catalog every 100 changes, so acknowledged inserts vanish after a crash") }
        try assertAcknowledgedInsertsSurviveCrash(mvcc: true)
    }

    /// Control: the default (MVCC-off) path keeps the same inserts.
    func testLegacyInsert_CrashBeforePersist_AcknowledgedInsertsSurviveReopen() throws {
        try assertAcknowledgedInsertsSurviveCrash(mvcc: false)
    }

    private func assertAcknowledgedInsertsSurviveCrash(mvcc: Bool) throws {
        #if DEBUG
        let url = tempDir.appendingPathComponent("crash.blazedb")
        let db = try BlazeDBClient(name: "Crash", fileURL: url, password: password)
        if mvcc { db.setMVCCEnabled(true) }
        _ = try db.insert(BlazeDataRecord(["value": .int(0)]))
        try db.persist()

        var acknowledged: [UUID: Int] = [:]
        for value in 1...5 {
            acknowledged[try db.insert(BlazeDataRecord(["value": .int(value)]))] = value
        }
        db.collection.store.simulateCrashForTests()

        // Keep the crashed client alive: its deinit calls close(), which would flush and hide the loss.
        try withExtendedLifetime(db) {
            let reopened = try BlazeDBClient(name: "Crash", fileURL: url, password: password)
            defer { try? reopened.close() }
            if mvcc { reopened.setMVCCEnabled(true) }
            for (id, value) in acknowledged.sorted(by: { $0.value < $1.value }) {
                XCTAssertEqual(
                    try reopened.fetch(id: id)?.storage["value"]?.intValue, value,
                    "acknowledged insert \(value) lost after crash (mvcc=\(mvcc))"
                )
            }
            XCTAssertEqual(try reopened.fetchAll().count, 6, "record count after crash (mvcc=\(mvcc))")
        }
        #else
        throw XCTSkip("simulateCrashForTests is DEBUG-only")
        #endif
    }
}
