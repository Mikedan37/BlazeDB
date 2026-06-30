//
//  OpenProfileBenchmarks.swift
//  BlazeDB_Tier3_Heavy
//
//  Diagnostic only — prints open breakdown when BLAZEDB_PROFILE_OPEN=1.
//  Not a regression gate (PBKDF2 cost varies by host and XCTest uses 100k iters).
//

import XCTest
@testable import BlazeDBCore

final class OpenProfileBenchmarks: XCTestCase {
    func testPrintColdOpenBreakdown() throws {
        setenv("BLAZEDB_PROFILE_OPEN", "1", 1)
        defer { unsetenv("BLAZEDB_PROFILE_OPEN") }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenProfile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("open.blazedb")
        let password = "OpenProfilePass-123!"

        let seed = try BlazeDBClient(name: "seed", fileURL: dbURL, password: password)
        _ = try seed.insertMany((0..<500).map { BlazeDataRecord(["i": .int($0)]) })
        try seed.persist()
        try seed.close()

        KeyManager.clearKeyCache()
        BlazeDBClient.clearCachedKey(for: dbURL.path)
        OpenProfileCollector.reset()

        let start = BlazeDBDiagnostics.monotonicSeconds()
        let db = try BlazeDBClient(name: "open", fileURL: dbURL, password: password)
        let wallMs = (BlazeDBDiagnostics.monotonicSeconds() - start) * 1000.0
        try db.close()

        print("OPEN_PROFILE_WALL_MS=\(String(format: "%.3f", wallMs))")
        print("OPEN_PROFILE_PBKDF2_ITERS=\(BlazeDBDiagnostics.pbkdf2IterationCount)")
        print("OPEN_PROFILE_UNDER_XCTEST=\(BlazeDBDiagnostics.isRunningUnderXCTest)")
        for span in OpenProfileCollector.snapshot() {
            print("OPEN_PROFILE_SPAN|\(span.name)|\(String(format: "%.3f", span.milliseconds))")
        }

        XCTAssertGreaterThan(wallMs, 0)
        XCTAssertFalse(OpenProfileCollector.snapshot().isEmpty)
    }
}
