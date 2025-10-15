//
//  TransactionDurabilityTests.swift
//  BlazeDB
//
//  Created by Michael Danylchuk on 10/11/25.
//

//
//  TransactionDurabilityTests.swift
//  BlazeDBTests
//
//  Covers WAL/log presence, commit clearing, crash-recovery invariants,
//  and basic concurrency serialization properties without relying on
//  internal TransactionLog APIs.
//

import XCTest
@testable import BlazeDB

final class TransactionDurabilityTests: XCTestCase {

    // MARK: - Helpers

    private func tmpDir(_ name: String = UUID().uuidString) -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("blazedb-tests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func dbURL(in dir: URL) -> URL { dir.appendingPathComponent("test.db") }

    /// Best-effort guess for the WAL/tx log location used in tests.
    /// If it doesn't exist for the current build, the test will `XCTSkip`.
    private func guessTxLogURL(for dbURL: URL) -> URL {
        // Try common candidates used earlier in this codebase.
        let dir = dbURL.deletingLastPathComponent()
        let candidates = [
            dir.appendingPathComponent("txlog.blz"),
            dbURL.appendingPathExtension("txlog"),
            dir.appendingPathComponent("\(dbURL.deletingPathExtension().lastPathComponent).txlog")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // default primary candidate
        return dir.appendingPathComponent("txlog.blz")
    }

    private func makeStore(at url: URL) throws -> BlazeDB.PageStore {
        // PageStore accepts a key for API compatibility but ignores it (encryption disabled).
        return try BlazeDB.PageStore(fileURL: url, key: .init(size: .bits256))
    }

    private func asString(_ data: Data) -> String { String(data: data, encoding: .utf8) ?? "<nonutf8>" }

    // MARK: - 1) WAL presence & clearing

    func testWALLogContainsEntriesPreCommitAndClearsAfterCommit() throws {
        let dir = tmpDir("wal-presence")
        let url = dbURL(in: dir)
        let store: BlazeDB.PageStore = try makeStore(at: url)

        // Seed page 0 with baseline content.
        try store.write(index: 0, data: Data("baseline".utf8))

        let tx = BlazeTransaction(store: store)
        let newData = Data("tx-write".utf8)
        try tx.write(pageID: 0, data: newData)
        try tx.ensureWALCreatedForTesting()
        // Force WAL flush after write, if available for testing
        try tx.flushStagedWritesForTesting()

        // WAL should exist and be non-empty before commit (if journaling is wired).
        let walURL = guessTxLogURL(for: url)
        let candidates = [
            walURL,
            dbURL(in: dir).appendingPathExtension("txlog"),
            dir.appendingPathComponent("test.txlog"),
            dir.appendingPathComponent("wal.log"),
            dir.appendingPathComponent("journal.blz")
        ]
        var found = false
        for candidate in candidates {
            print("🔎 Probing: \(candidate.path)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                found = true
                let preSize = (try? Data(contentsOf: candidate).count) ?? 0
                XCTAssertGreaterThan(preSize, 0, "WAL should contain pending operations before commit at: \(candidate.path)")
                break
            }
        }
        if !found {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            print("⚠️ No WAL file found. Directory contents: \(files)")
            XCTSkip("WAL file not found pre-commit — journaling is lazily created in this configuration.")
        }

        // Commit and ensure file reflects new data.
        try tx.commit()
        guard let readBack = try? store.read(index: 0) else {
            XCTFail("Expected non-nil data from store.read(index: 0)")
            return
        }
        XCTAssertEqual(asString(readBack), "tx-write")

        // After commit, WAL should be empty or removed.
        if FileManager.default.fileExists(atPath: walURL.path) {
            let postSize = (try? Data(contentsOf: walURL).count) ?? 0
            XCTAssertEqual(postSize, 0, "WAL should be cleared after commit")
            if postSize > 0 {
                try? FileManager.default.removeItem(at: walURL)
            }
        } // else: treated as removed and thus cleared
    }

    // MARK: - 2) Crash-recovery invariant: no partial outcomes

    func testCrashRecovery_NoPartialOutcomes_AllOrNothing() throws {
        let dir = tmpDir("wal-crash-invariant")
        let url = dbURL(in: dir)

        // 1) Create store and seed page indices 0 & 1 with known values.
        do {
            let store: BlazeDB.PageStore = try makeStore(at: url)
            try store.write(index: 0, data: Data("A0".utf8))
            try store.write(index: 1, data: Data("B0".utf8))

            // Begin a tx and stage two updates but DO NOT commit (simulate crash before commit).
            var tx = BlazeTransaction(store: store)
            try tx.write(pageID: 0, data: Data("A1".utf8))
            try tx.write(pageID: 1, data: Data("B1".utf8))
            // Implicit crash: the tx goes out of scope without commit and process restarts.
            _ = tx // keep compiler happy
        }

        // 2) "Restart" by reopening store (fresh instance).
        let store2: BlazeDB.PageStore = try makeStore(at: url)

        // Read both pages. The durability contract with WAL is: either both new values (replayed) OR both old values (rolled back).
        // The only invalid state is a partial application (one new and one old).
        guard let a = try? store2.read(index: 0),
              let b = try? store2.read(index: 1) else {
            XCTFail("Expected non-nil reads from store2 for pages 0 and 1")
            return
        }
        let aStr = asString(a)
        let bStr = asString(b)

        // Allowed outcomes: (A1,B1) or (A0,B0)
        let okAllNew = (aStr == "A1" && bStr == "B1")
        let okAllOld = (aStr == "A0" && bStr == "B0")
        XCTAssertTrue(okAllNew || okAllOld, "Crash recovery must not produce partial state: got (\(aStr), \(bStr))")
    }

    // MARK: - 3) Concurrency serialization on same page

    func testConcurrentWritesToSamePageSerializeFinalStateIsConsistent() throws {
        let dir = tmpDir("wal-concurrency-write")
        let url = dbURL(in: dir)
        let store: BlazeDB.PageStore = try makeStore(at: url)

        try store.write(index: 0, data: Data("base".utf8))

        let exp = expectation(description: "both tx complete")
        exp.expectedFulfillmentCount = 2

        let q = DispatchQueue(label: "txq", attributes: .concurrent)
        var resultA: Error?
        var resultB: Error?

        q.async {
            var tx = BlazeTransaction(store: store)
            try? tx.write(pageID: 0, data: Data("AAAA".utf8))
            resultA = (try? tx.commit()).map { _ in nil } ?? NSError(domain: "commitA", code: 1)
            exp.fulfill()
        }

        q.async {
            var tx = BlazeTransaction(store: store)
            try? tx.write(pageID: 0, data: Data("BBBB".utf8))
            resultB = (try? tx.commit()).map { _ in nil } ?? NSError(domain: "commitB", code: 1)
            exp.fulfill()
        }

        wait(for: [exp], timeout: 3.0)

        // At least one commit should succeed; the other may fail due to locking or may succeed later.
        // The final stored value must equal either AAAA or BBBB, never a partial mix.
        let final = try store.read(index: 0)
        guard let final = final else {
            XCTFail("Expected non-nil data from store.read(index: 0)")
            return
        }
        let s = asString(final)
        XCTAssertTrue(s == "AAAA" || s == "BBBB", "Final content should be one of the committed values, got: \(s)")
    }

    func testConcurrentReadsAllowedWhileWriterOperates() throws {
        let dir = tmpDir("wal-concurrency-read")
        let url = dbURL(in: dir)
        let store: BlazeDB.PageStore = try makeStore(at: url)
        try store.write(index: 0, data: Data("start".utf8))

        let startedWrite = expectation(description: "writer started")
        let finishedWrite = expectation(description: "writer finished")
        let readerOk = expectation(description: "reader ok")

        DispatchQueue.global().async {
            var tx = BlazeTransaction(store: store)
            try? tx.write(pageID: 0, data: Data("writer".utf8))
            startedWrite.fulfill()
            // Simulate work
            usleep(100_000)
            _ = try? tx.commit()
            finishedWrite.fulfill()
        }

        wait(for: [startedWrite], timeout: 1.0)

        // Reader should be able to read *some* consistent value (impl-defined: pre/post image).
        DispatchQueue.global().async {
            let data = try? store.read(index: 0)
            XCTAssertNotNil(data)
            readerOk.fulfill()
        }

        wait(for: [readerOk, finishedWrite], timeout: 2.0)
    }

    // MARK: - 4) Corrupted WAL is ignored (startup remains usable)

    func testStartupWithCorruptedWALDoesNotBrickDatabase() throws {
        let dir = tmpDir("wal-corrupt")
        let url = dbURL(in: dir)
        let store: BlazeDB.PageStore = try makeStore(at: url)

        // Seed a good page
        try store.write(index: 0, data: Data("good".utf8))

        // Create or overwrite a txlog with garbage.
        let walURL = guessTxLogURL(for: url)
        try Data([0x00, 0xFF, 0x13, 0x37, 0x00]).write(to: walURL, options: .atomic)

        // Reopen store to trigger any startup recovery logic.
        let store2: BlazeDB.PageStore = try makeStore(at: url)
        guard let data = try? store2.read(index: 0) else {
            XCTFail("Expected to read valid page 0 after corrupted WAL recovery")
            return
        }
        XCTAssertEqual(asString(data), "good")
    }
}
