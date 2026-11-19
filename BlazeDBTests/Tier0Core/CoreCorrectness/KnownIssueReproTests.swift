// Known-issue reproductions. Each test behind a `guard ... BLAZEDB_RUN_KNOWN_ISSUES` line asserts
// the intended behavior, fails on origin/main, and is skipped unless BLAZEDB_RUN_KNOWN_ISSUES=1,
// so the suite stays green until the fix lands. The PR that fixes an issue deletes that guard line,
// and the test then gates every run.

import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

/// Reproductions of known correctness bugs on origin/main (gate: see the file header).
final class KnownIssueReproTests: XCTestCase {
    private let password = "KnownIssueRepro-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("known-issue-repro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        BlazeDBClient.clearCachedKey()
        try? FileManager.default.removeItem(at: tempDir)
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        super.tearDown()
    }

    private func open(_ url: URL) throws -> BlazeDBClient {
        try BlazeDBClient(name: "KnownIssue", fileURL: url, password: password)
    }

    private func metaURL(_ url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("meta")
    }

    // MARK: - Fetch returns a record stored under another ID

    // Contract: "Fetch a record by ID" (DynamicCollection.swift:1240); the read path itself
    // calls this state "indexMap corruption" (DynamicCollection.swift:1342);
    // Docs/Guarantees/SAFETY_MODEL.md:150-153 "Refuses ... Provides clear error message".

    func testFetchByID_CatalogAliasesAnotherRecord_NeverReturnsForeignRecord() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: fetch(id: A) returns and caches record B when the catalog maps A to B's page") }
        try assertAliasedFetchIsRejected(enableMVCC: false)
    }

    func testFetchByIDUnderMVCC_CatalogAliasesAnotherRecord_NeverReturnsForeignRecord() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: MVCC fetch(id: A) returns record B when the catalog maps A to B's page") }
        try assertAliasedFetchIsRejected(enableMVCC: true)
    }

    /// Point A's catalog entry at B's page under a valid signature, then fetch A.
    /// Refusing to open, throwing or returning nil are all acceptable; returning B is not.
    private func assertAliasedFetchIsRejected(enableMVCC: Bool) throws {
        let url = tempDir.appendingPathComponent("alias.blazedb")
        let seed = try open(url)
        let a = try seed.insert(BlazeDataRecord(["value": .int(1)]))
        let b = try seed.insert(BlazeDataRecord(["value": .int(2)]))
        try seed.persist()
        let key = seed.collection.encryptionKey
        try seed.close()

        let meta = metaURL(url)
        var layout = try StorageLayout.loadSecure(from: meta, signingKey: key)
        layout.indexMap[a] = try XCTUnwrap(layout.indexMap[b])
        try layout.saveSecure(to: meta, signingKey: key)
        let aliased = try Data(contentsOf: meta)

        let db: BlazeDBClient
        do {
            db = try open(url)
        } catch {
            // A fix may detect the alias at open and refuse; it must not rewrite .meta doing so.
            XCTAssertEqual(try? Data(contentsOf: meta), aliased, "a refused open must leave .meta untouched")
            return
        }
        defer { try? db.close() }
        if enableMVCC { db.setMVCCEnabled(true) }

        for attempt in 1...2 {
            if let got = try? db.fetch(id: a) {
                XCTAssertEqual(
                    got.storage["id"]?.uuidValue, a,
                    "fetch(id: A) attempt \(attempt) returned the record stored as B (mvcc=\(enableMVCC))"
                )
                // Also catches B's data relabeled with A's id.
                XCTAssertNotEqual(
                    got.storage["value"]?.intValue, 2,
                    "fetch(id: A) attempt \(attempt) returned B's data (mvcc=\(enableMVCC))"
                )
            }
        }
        XCTAssertEqual(try db.fetch(id: b)?.storage["id"]?.uuidValue, b, "control: fetch(id: B) must still return B")
    }

    // MARK: - Unreadable .meta is deleted and rebuilt from a page scan

    // The intended policy is an OPEN DECISION. Docs/Guarantees/SAFETY_MODEL.md:84-88 and :150-153 say
    // refuse ("Refuses to open corrupted database"; rebuild is a user recovery step at :159);
    // Docs/Architecture/ARCHITECTURE_DETAILED.md:132 says rebuild automatically. The assertion accepts
    // either policy, provided the unreadable .meta is preserved (left untouched on refusal, or a
    // byte-identical copy kept on rebuild) and nothing deleted comes back (the rebuilt catalog serves
    // exactly the 9 live records with the updated value).
    // Not covered: an AutoMigration failure inside the same do block (DynamicCollection.swift:331-339)
    // has no deterministic test hook.

    func testOpen_MetaIsNotJSON_RefusesOrKeepsOriginal() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: non-JSON .meta (code 3) is deleted and silently rebuilt from a page scan") }
        try assertCorruptMetaNotSilentlyDiscarded { _, _, meta in
            try Data([0x00, 0xFF, 0x13, 0x37] + Array("garbage".utf8)).write(to: meta, options: .atomic)
        }
    }

    func testOpen_MetaIsTruncatedJSON_RefusesOrKeepsOriginal() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: truncated .meta (code 2) is deleted and silently rebuilt from a page scan") }
        try assertCorruptMetaNotSilentlyDiscarded { original, _, meta in
            try original.prefix(original.count / 2).write(to: meta, options: .atomic)
        }
    }

    func testOpen_MetaIsUnsignedPlainLayout_RefusesOrKeepsOriginal() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: unsigned plain-layout .meta (code 2) is deleted and silently rebuilt from a page scan") }
        try assertCorruptMetaNotSilentlyDiscarded { _, key, meta in
            let layout = try StorageLayout.loadSecure(from: meta, signingKey: key)
            try layout.save(to: meta)
        }
    }

    func testOpen_MetaV2MissingSignedPayload_RefusesOrKeepsOriginal() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: v2 .meta without signedPayload (code 4) is deleted and silently rebuilt from a page scan") }
        try assertCorruptMetaNotSilentlyDiscarded { original, _, meta in
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            XCTAssertNotNil(object.removeValue(forKey: "signedPayload"))
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: meta, options: .atomic)
        }
    }

    func testOpen_MetaV2SignedPayloadUndecodable_RefusesOrKeepsOriginal() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: validly signed v2 .meta with an undecodable payload (code 6) is deleted and silently rebuilt") }
        try assertCorruptMetaNotSilentlyDiscarded { original, key, meta in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let secure = try decoder.decode(StorageLayout.SecureLayout.self, from: original)
            let payload = Data("not-json".utf8)
            let unsigned = StorageLayout.SecureLayout(
                secureLayoutVersion: 2, layout: secure.layout, signedPayload: payload, signature: Data(), signedAt: Date()
            )
            let signed = StorageLayout.SecureLayout(
                secureLayoutVersion: 2, layout: secure.layout, signedPayload: payload,
                signature: try unsigned.expectedSignature(using: key), signedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(signed).write(to: meta, options: .atomic)
        }
    }

    /// 10 records, r1 updated, r2 deleted, persisted and closed; then `corrupt` rewrites .meta.
    private func assertCorruptMetaNotSilentlyDiscarded(
        _ corrupt: (_ original: Data, _ key: SymmetricKey, _ meta: URL) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = tempDir.appendingPathComponent("corrupt.blazedb")
        let meta = metaURL(url)
        let seed = try open(url)
        var ids: [UUID] = []
        for i in 0..<10 {
            ids.append(try seed.insert(BlazeDataRecord(["value": .int(i)])))
        }
        try seed.update(id: ids[1], with: BlazeDataRecord(["value": .int(100)]))
        try seed.delete(id: ids[2])
        try seed.persist()
        let key = seed.collection.encryptionKey
        try seed.close()
        BlazeDBClient.clearCachedKey()

        try corrupt(try Data(contentsOf: meta), key, meta)
        let corrupted = try Data(contentsOf: meta)

        let db: BlazeDBClient
        do {
            db = try open(url)
        } catch {
            XCTAssertEqual(try? Data(contentsOf: meta), corrupted, "a refused open must leave .meta untouched", file: file, line: line)
            return
        }
        defer { try? db.close() }

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(
            files.contains { (try? Data(contentsOf: $0)) == corrupted },
            "open discarded the unreadable .meta (no copy kept) and rebuilt the catalog from a page scan",
            file: file, line: line
        )
        XCTAssertEqual(try db.fetchAll().count, 9, "rebuilt catalog must list exactly the 9 live records", file: file, line: line)
        XCTAssertEqual(try db.fetch(id: ids[1])?.storage["value"]?.intValue, 100, "rebuilt catalog must serve the updated value", file: file, line: line)
        XCTAssertNil(try db.fetch(id: ids[2]), "rebuilt catalog must not resurrect a deleted record", file: file, line: line)
    }

    // MARK: - updateMany(ids:set:) drops unpatched fields

    // Contract: BlazeDBClient+Batch.swift:257-271 documents `fields` as "Fields to update" with a
    // single-field example; the sibling updateMany(where:set:) merges (BlazeDBClient.swift:1067-1110).

    func testUpdateManyByIDs_PartialPatch_PreservesUnpatchedFields() async throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_RUN_KNOWN_ISSUES"] == "1" else { throw XCTSkip("Known issue: updateMany(ids:set:) replaces the whole record and drops every field not in the patch") }
        let db = try open(tempDir.appendingPathComponent("patch.blazedb"))
        defer { try? db.close() }
        let id = try await db.insert(BlazeDataRecord([
            "title": .string("keep"), "value": .int(7), "status": .string("open")
        ]))

        let updated = try await db.updateMany(ids: [id], set: ["status": .string("closed")])

        XCTAssertEqual(updated, 1)
        let fetched = try await db.fetch(id: id)
        let record = try XCTUnwrap(fetched)
        XCTAssertEqual(record.storage["status"]?.stringValue, "closed")
        XCTAssertEqual(record.storage["title"]?.stringValue, "keep", "updateMany(ids:set:) dropped an unpatched field")
        XCTAssertEqual(record.storage["value"]?.intValue, 7, "updateMany(ids:set:) dropped an unpatched field")
    }
}
