//
//  TransactionRecoveryTests.swift
//  BlazeDBTests
//
//  Created by Michael Danylchuk on 10/11/25.
//

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class TransactionRecoveryTests: XCTestCase {

    // MARK: - Helpers

    struct Env {
        let dir: URL
        let dbURL: URL
        let logURL: URL
        let key: SymmetricKey
    }

    private func makeEnv(testName: String = #function) throws -> Env {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("blazedb.recovery.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbURL = dir.appendingPathComponent("data.blz")
        let logURL = dir.appendingPathComponent("txlog.blz")
        let key = SymmetricKey(size: .bits256)
        return Env(dir: dir, dbURL: dbURL, logURL: logURL, key: key)
    }

    private func randomData(_ count: Int = 64) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    /// Deterministic digest of selected page contents for replay-idempotence checks.
    private func stateDigest(_ store: PageStore, pages: [Int]) throws -> String {
        var buffer = Data()
        for page in pages.sorted() {
            let payload = try store.readPage(index: page)
            if let payload {
                buffer.append(Data("P\(page):".utf8))
                buffer.append(payload)
            } else {
                buffer.append(Data("P\(page):<nil>".utf8))
            }
            buffer.append(0x0a)
        }

        let digest = SHA256.hash(data: buffer)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns data if a page exists and is readable; otherwise nil.
    private func tryRead(_ store: PageStore, index: Int) -> Data? {
        do { return try store.readPage(index: index) } catch { return nil }
    }

    // MARK: - Tests

    /// If a transaction doesn't commit, recovery should not apply its writes.
    func testInterruptedCommitRecovery_rollsBackUncommitted() throws {
        let env = try makeEnv()
        print("[TEST] Environment created at: \(env.dir.path)")

        // Prepare intended write but DO NOT commit the transaction in WAL.
        let txID = UUID()
        let page = 0
        let payload = randomData(48)

        let log = TransactionLog(logFileURL: env.logURL)
        // Use the static TransactionLog API (no explicit logURL in this build)
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        print("[TEST] WAL entries appended (BEGIN + WRITE) for txID: \(txID)")
        // Simulate crash: no appendCommit

        // "Restart" DB by making a fresh PageStore and invoking recovery.
        let restartedStore: PageStore = try .init(fileURL: env.dbURL, key: env.key)
        print("[TEST] Restarted PageStore initialized at: \(env.dbURL.path)")
        try log.recover(into: restartedStore)

        // Because the tx never committed, nothing should be applied.
        let currentData = try? restartedStore.readPage(index: page)
        print("[TEST] Current data length after recovery: \(currentData?.count ?? -1)")
        if let d = currentData { print("[TEST] Data bytes: \(d as NSData)") }
        let result = tryRead(restartedStore, index: page)
        XCTAssertTrue(result == nil || result!.isEmpty, "Uncommitted WAL entries must not be applied to the store")
    }

    /// A committed transaction must replay successfully from WAL on restart.
    func testWALReplayAfterCommit_appliesCommittedWrites() throws {
        let env = try makeEnv()

        let txID = UUID()
        let page = 1
        let payload = randomData(64)

        let log = TransactionLog(logFileURL: env.logURL)
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        try log.appendCommit(txID: txID)

        // "Restart" and recover
        let restartedStore: PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: restartedStore)

        // The page should now exist with exact bytes.
        let readBack = try restartedStore.readPage(index: page)
        XCTAssertEqual(readBack, payload, "Committed WAL write must be applied on recovery")
    }

    /// Running recovery multiple times must be idempotent.
    func testDoubleRecoveryIsIdempotent() throws {
        let env = try makeEnv()

        let txID = UUID()
        let page = 2
        let payload = randomData(32)

        let log = TransactionLog(logFileURL: env.logURL)
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        try log.appendCommit(txID: txID)

        // First recovery
        print("[TEST] Starting first recovery")
        var store: PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        let firstRead = try? store.readPage(index: page)
        print("[TEST] After first recovery: page size = \(firstRead?.count ?? -1)")
        XCTAssertEqual(firstRead, payload)
        store.close()

        // Second recovery should be a no-op
        print("[TEST] Starting second recovery")
        store = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        let secondRead = try? store.readPage(index: page)
        print("[TEST] After second recovery: page size = \(secondRead?.count ?? -1)")
        XCTAssertEqual(secondRead, payload)
    }

    /// Tier 0 invariant: replaying the same committed WAL stream twice yields identical final state.
    func testRecoveryReplayTwice_YieldsIdenticalStateDigest() throws {
        let env = try makeEnv()
        let log = TransactionLog(logFileURL: env.logURL)

        let txID = UUID()
        let writes: [(Int, Data)] = [
            (10, randomData(32)),
            (11, randomData(32)),
            (12, randomData(32))
        ]

        try log.appendBegin(txID: txID)
        for (page, data) in writes {
            try log.appendWrite(pageID: page, data: data)
        }
        try log.appendCommit(txID: txID)

        // Snapshot WAL bytes before first replay so we can replay the exact same stream twice.
        let walBytes = try Data(contentsOf: env.logURL)
        XCTAssertFalse(walBytes.isEmpty)

        var store = try PageStore(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        let digestAfterFirstReplay = try stateDigest(store, pages: writes.map(\.0))
        store.close()

        try walBytes.write(to: env.logURL, options: .atomic)
        store = try PageStore(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        let digestAfterSecondReplay = try stateDigest(store, pages: writes.map(\.0))
        store.close()

        XCTAssertEqual(
            digestAfterFirstReplay,
            digestAfterSecondReplay,
            "Replaying identical committed WAL stream twice must converge to identical state."
        )
    }

    /// Regression guard for incident INC-2026-03-03-02:
    /// reopen after explicit close must not produce transient lock/save errors.
    func testRecoveryReopenAfterClose_AvoidsLockContention() throws {
        let env = try makeEnv()
        let txID = UUID()
        let page = 3
        let payload = randomData(48)

        let log = TransactionLog(logFileURL: env.logURL)
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        try log.appendCommit(txID: txID)

        var store: PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        XCTAssertEqual(try store.readPage(index: page), payload)
        store.close()

        store = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        XCTAssertEqual(try store.readPage(index: page), payload)
        store.close()
    }

    /// Mixed committed and uncommitted entries: only committed ones should apply.
    func testMixedCommittedAndUncommitted_onlyCommittedApply() throws {
        let env = try makeEnv()

        // TX A (committed)
        let txA = UUID()
        let pageA = 4
        let dataA = randomData(24)
        let log = TransactionLog(logFileURL: env.logURL)
        try log.appendBegin(txID: txA)
        try log.appendWrite(pageID: pageA, data: dataA)
        try log.appendCommit(txID: txA)

        // TX B (uncommitted)
        let txB = UUID()
        let pageB = 5
        let dataB = randomData(24)
        try log.appendBegin(txID: txB)
        try log.appendWrite(pageID: pageB, data: dataB)
        // no commit

        let restartedStore: PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: restartedStore)

        XCTAssertEqual(try restartedStore.readPage(index: pageA), dataA, "Committed tx must apply")
        XCTAssertNil(tryRead(restartedStore, index: pageB), "Uncommitted tx must not apply")
    }

    /// Regression guard: if an uncommitted tx overwrites an existing committed page,
    /// recovery must preserve the previously committed page content.
    func testUncommittedOverwriteDoesNotDeletePreviouslyCommittedPage() throws {
        let env = try makeEnv()
        let page = 6
        let committedData = randomData(32)
        let uncommittedOverwrite = randomData(32)

        let log = TransactionLog(logFileURL: env.logURL)

        let txCommitted = UUID()
        try log.appendBegin(txID: txCommitted)
        try log.appendWrite(pageID: page, data: committedData)
        try log.appendCommit(txID: txCommitted)

        let txUncommitted = UUID()
        try log.appendBegin(txID: txUncommitted)
        try log.appendWrite(pageID: page, data: uncommittedOverwrite)
        // no commit: simulate crash before commit

        let restartedStore: PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: restartedStore)

        XCTAssertEqual(
            try restartedStore.readPage(index: page),
            committedData,
            "Recovery must keep the last committed version and ignore uncommitted overwrite"
        )
    }

    /// Recovery must not swallow `Data(contentsOf:)` failures (e.g. path is a directory), which would hint
    /// at an empty WAL and truncate without surfacing the real I/O problem.
    func testRecover_propagatesFailureWhenLogIsNotAReadableFile() throws {
        let env = try makeEnv()
        let store = try PageStore(fileURL: env.dbURL, key: env.key)
        let log = TransactionLog(logFileURL: env.logURL)
        XCTAssertThrowsError(try log.recover(into: store, from: env.dir)) { err in
            let ns = err as NSError
            XCTAssertFalse(ns.domain.isEmpty)
        }
    }
}
