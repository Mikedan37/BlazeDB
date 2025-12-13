//
//  TransactionRecoveryTests.swift
//  BlazeDBTests
//
//  Created by Michael Danylchuk on 10/11/25.
//

import XCTest
import CryptoKit
@testable import BlazeDB

final class TransactionRecoveryTests: XCTestCase {

    // MARK: - Helpers

    struct Env {
        let dir: URL
        let dbURL: URL
        let key: SymmetricKey
    }

    private func makeEnv(testName: String = #function) throws -> Env {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("blazedb.recovery.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbURL = dir.appendingPathComponent("data.blz")
        let key = SymmetricKey(size: .bits256)
        return Env(dir: dir, dbURL: dbURL, key: key)
    }

    private func randomData(_ count: Int = 64) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// Returns data if a page exists and is readable; otherwise nil.
    private func tryRead(_ store: BlazeDB.PageStore, index: Int) -> Data? {
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

        let log = TransactionLog()
        // Use the static TransactionLog API (no explicit logURL in this build)
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        print("[TEST] WAL entries appended (BEGIN + WRITE) for txID: \(txID)")
        // Simulate crash: no appendCommit

        // "Restart" DB by making a fresh PageStore and invoking recovery.
        let restartedStore: BlazeDB.PageStore = try .init(fileURL: env.dbURL, key: env.key)
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

        let log = TransactionLog()
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        try log.appendCommit(txID: txID)

        // "Restart" and recover
        let restartedStore: BlazeDB.PageStore = try .init(fileURL: env.dbURL, key: env.key)
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

        let log = TransactionLog()
        try log.appendBegin(txID: txID)
        try log.appendWrite(pageID: page, data: payload)
        try log.appendCommit(txID: txID)

        // First recovery
        print("[TEST] Starting first recovery")
        var store: BlazeDB.PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        let firstRead = try? store.readPage(index: page)
        print("[TEST] After first recovery: page size = \(firstRead?.count ?? -1)")
        XCTAssertEqual(firstRead, payload)

        // Second recovery should be a no-op
        print("[TEST] Starting second recovery")
        store = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: store)
        let secondRead = try? store.readPage(index: page)
        print("[TEST] After second recovery: page size = \(secondRead?.count ?? -1)")
        XCTAssertEqual(secondRead, payload)
    }

    /// Mixed committed and uncommitted entries: only committed ones should apply.
    func testMixedCommittedAndUncommitted_onlyCommittedApply() throws {
        let env = try makeEnv()

        // TX A (committed)
        let txA = UUID()
        let pageA = 4
        let dataA = randomData(24)
        let log = TransactionLog()
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

        let restartedStore: BlazeDB.PageStore = try .init(fileURL: env.dbURL, key: env.key)
        try log.recover(into: restartedStore)

        XCTAssertEqual(try restartedStore.readPage(index: pageA), dataA, "Committed tx must apply")
        XCTAssertNil(tryRead(restartedStore, index: pageB), "Uncommitted tx must not apply")
    }
}
