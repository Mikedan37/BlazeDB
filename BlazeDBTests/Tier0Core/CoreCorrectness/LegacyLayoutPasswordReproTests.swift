// Known-issue reproductions. Each test behind a `guard ... BLAZEDB_RUN_KNOWN_ISSUES` line asserts
// the intended behavior, fails on origin/main, and is skipped unless BLAZEDB_RUN_KNOWN_ISSUES=1,
// so the suite stays green until the fix lands. The PR that fixes an issue deletes that guard line,
// and the test then gates every run. Tests without the guard are controls and always run.

import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

/// A database whose .meta uses the legacy v1 secure layout (no secureLayoutVersion, no signedPayload).
///
/// Contract: Docs/Guarantees/SAFETY_MODEL.md:163-167, wrong password => "Database refuses to open".
/// The error type is not pinned: the documented `authenticationFailed` does not exist.
final class LegacyLayoutPasswordReproTests: XCTestCase {
    private let password = "LegacyLayoutOwner-2026!"
    private let recordCount = 5
    private var tempDir: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-layout-password-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("legacy.blazedb")
    }

    override func tearDown() {
        BlazeDBClient.clearCachedKey()
        try? FileManager.default.removeItem(at: tempDir)
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        super.tearDown()
    }

    func testOpenV1Layout_WrongPassword_RefusesAndLeavesMetaUntouched() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: a wrong password opens a database whose .meta is a legacy v1 secure layout") }
        let ids = try makeV1Database()
        let meta = dbURL.deletingPathExtension().appendingPathExtension("meta")
        let metaBefore = try Data(contentsOf: meta)

        XCTAssertThrowsError(
            try BlazeDBClient(name: "Legacy", fileURL: dbURL, password: "WrongPassword-456!"),
            "a wrong password must not open a v1-layout database"
        )
        XCTAssertEqual(try Data(contentsOf: meta), metaBefore, "a wrong-password open must not rewrite .meta")

        BlazeDBClient.clearCachedKey()
        let owner: BlazeDBClient
        do {
            owner = try BlazeDBClient(name: "Legacy", fileURL: dbURL, password: password)
        } catch {
            return XCTFail("owner locked out after a wrong-password attempt: \(error)")
        }
        defer { try? owner.close() }
        for (i, id) in ids.enumerated() {
            XCTAssertEqual(try owner.fetch(id: id)?.storage["value"]?.intValue, i)
        }
    }

    /// Compatibility guard for any fix: the right password still opens a v1-layout database.
    func testOpenV1Layout_CorrectPassword_ReadsAllRecords() throws {
        let ids = try makeV1Database()
        let db = try BlazeDBClient(name: "Legacy", fileURL: dbURL, password: password)
        defer { try? db.close() }
        for (i, id) in ids.enumerated() {
            XCTAssertEqual(try db.fetch(id: id)?.storage["value"]?.intValue, i)
        }
    }

    /// Creates a database, then rewrites its .meta in the v1 shape (pattern from
    /// Tier1Core/Persistence/SecureLayoutSignatureTests.swift:60-100) and drops the warm session.
    private func makeV1Database() throws -> [UUID] {
        let db = try BlazeDBClient(name: "Legacy", fileURL: dbURL, password: password)
        var ids: [UUID] = []
        for i in 0..<recordCount {
            ids.append(try db.insert(BlazeDataRecord(["value": .int(i)])))
        }
        try db.persist()
        let key = db.collection.encryptionKey
        try db.close()

        let meta = dbURL.deletingPathExtension().appendingPathExtension("meta")
        let layout = try StorageLayout.loadSecure(from: meta, signingKey: key)
        let unsigned = StorageLayout.SecureLayout(
            secureLayoutVersion: 1, layout: layout, signedPayload: nil, signature: Data(), signedAt: Date()
        )
        let v1 = StorageLayout.SecureLayout(
            secureLayoutVersion: 1, layout: layout, signedPayload: nil,
            signature: try unsigned.expectedSignature(using: key), signedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(v1)) as? [String: Any])
        object.removeValue(forKey: "secureLayoutVersion")
        object.removeValue(forKey: "signedPayload")
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: meta, options: .atomic)
        // Fixture check: with no password, loadSecure has no KDF retry or legacy key-bytes fallback, so
        // this is the strict HMAC check. A fix that removes the lenient path must still open this file.
        XCTAssertNoThrow(
            try StorageLayout.loadSecure(from: meta, signingKey: key),
            "fixture: the v1 .meta must verify strictly with the correct key"
        )

        // Without this the warm session throws passwordMismatch and hides the bug (BlazeDBClient.swift:228-232).
        BlazeDBClient.clearCachedKey()
        return ids
    }
}
