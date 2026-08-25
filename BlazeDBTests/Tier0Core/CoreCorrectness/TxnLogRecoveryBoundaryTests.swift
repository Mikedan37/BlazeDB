//
//  TxnLogRecoveryBoundaryTests.swift
//  BlazeDBTests
//
//  Regression tests for #365: unauthenticated NDJSON txn_log must not replay into
//  keyed PageStores on BlazeDBManager mount. Binary WAL recovery remains the
//  authenticated crash-recovery path for BlazeDBClient / PageStore.
//

import XCTest
@testable import BlazeDBCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

final class TxnLogRecoveryBoundaryTests: XCTestCase {
    private var tempDir: URL!
    private let password = "TxnLogBoundary-Test-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TxnLogBoundary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    /// Plant a committed NDJSON write beside the DB file (legacy sidecar location).
    private func writeLegacyTxnLogSidecar(
        beside dbURL: URL,
        pageID: Int,
        plaintext: Data,
        useNamespaced: Bool = false
    ) throws -> URL {
        let txID = UUID().uuidString
        let begin = try JSONEncoder().encode(TransactionLog.Operation.begin(txID: txID))
        let write = try JSONEncoder().encode(TransactionLog.Operation.write(pageID: pageID, data: plaintext))
        let commit = try JSONEncoder().encode(TransactionLog.Operation.commit(txID: txID))
        var ndjson = Data()
        ndjson.append(begin); ndjson.append(0x0A)
        ndjson.append(write); ndjson.append(0x0A)
        ndjson.append(commit); ndjson.append(0x0A)

        let logURL: URL
        if useNamespaced {
            let base = dbURL.deletingPathExtension().lastPathComponent
            let digest = SHA256.hash(data: Data(dbURL.path.utf8))
            let digestHex = Data(digest).map { String(format: "%02x", $0) }.joined()
            logURL = dbURL.deletingLastPathComponent()
                .appendingPathComponent("txn_log-\(base)-\(digestHex).json")
        } else {
            logURL = dbURL.deletingLastPathComponent().appendingPathComponent("txn_log.json")
        }
        try ndjson.write(to: logURL)
        return logURL
    }

    func testManagerMountRemovesUnauthenticatedTxnLogWithoutReplay() throws {
        let dbURL = tempDir.appendingPathComponent("mount-txnlog.blazedb")

        let store1 = try PageStore(fileURL: dbURL, key: try key(for: dbURL))
        let original = Data(repeating: 0xAB, count: 64)
        try store1.writePage(index: 7, plaintext: original)
        store1.close()

        let injected = Data(repeating: 0xEE, count: 64)
        let journal = try writeLegacyTxnLogSidecar(beside: dbURL, pageID: 7, plaintext: injected)

        let manager = BlazeDBManager()
        _ = try manager.mountDatabase(named: "victim", fileURL: dbURL, password: password)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path), "sidecar must be removed, not replayed")
        manager.unmountDatabase(named: "victim")

        let store2 = try PageStore(fileURL: dbURL, key: try key(for: dbURL))
        let readBack = try store2.readPage(index: 7)
        XCTAssertEqual(readBack, original, "injected plaintext must not be sealed into the encrypted DB")
        store2.close()
    }

    func testManagerMountRemovesNamespacedTxnLogSidecarWithoutReplay() throws {
        let dbURL = tempDir.appendingPathComponent("namespaced-txnlog.blazedb")

        let store1 = try PageStore(fileURL: dbURL, key: try key(for: dbURL))
        try store1.writePage(index: 3, plaintext: Data(repeating: 0x11, count: 32))
        store1.close()

        let journal = try writeLegacyTxnLogSidecar(
            beside: dbURL,
            pageID: 3,
            plaintext: Data(repeating: 0x22, count: 32),
            useNamespaced: true
        )

        let manager = BlazeDBManager()
        _ = try manager.mountDatabase(named: "db", fileURL: dbURL, password: password)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        manager.unmountDatabase(named: "db")
    }

    func testManagerMountWithoutTxnLogSidecarPreservesExistingPages() throws {
        let dbURL = tempDir.appendingPathComponent("clean-mount.blazedb")

        let store1 = try PageStore(fileURL: dbURL, key: try key(for: dbURL))
        let payload = Data(repeating: 0xCD, count: 48)
        try store1.writePage(index: 2, plaintext: payload)
        store1.close()

        let manager = BlazeDBManager()
        _ = try manager.mountDatabase(named: "db", fileURL: dbURL, password: password)
        manager.unmountDatabase(named: "db")

        let store2 = try PageStore(fileURL: dbURL, key: try key(for: dbURL))
        XCTAssertEqual(try store2.readPage(index: 2), payload)
        store2.close()
    }

    func testBlazeDBClientOpenStillWorksWithoutTxnLogSidecar() throws {
        let dbURL = tempDir.appendingPathComponent("client-open.blazedb")
        let db = try BlazeDBClient(name: "client-open", fileURL: dbURL, password: password)
        let id = try db.insert(BlazeDataRecord(["note": .string("durable")]))
        try db.persist()
        try db.close()

        let db2 = try BlazeDBClient(name: "client-open", fileURL: dbURL, password: password)
        defer { try? db2.close() }
        let record = try db2.fetch(id: id)
        XCTAssertEqual(record?.storage["note"]?.stringValue, "durable")
    }

    func testRecoverAllTransactionsFailsClosedWhenTxnLogPresent() throws {
        let dbURL = tempDir.appendingPathComponent("recover-all.blazedb")
        let manager = BlazeDBManager()
        _ = try manager.mountDatabase(named: "db", fileURL: dbURL, password: password)

        _ = try writeLegacyTxnLogSidecar(
            beside: dbURL,
            pageID: 1,
            plaintext: Data(repeating: 0x99, count: 16)
        )

        XCTAssertThrowsError(try manager.recoverAllTransactions()) { error in
            let ns = error as NSError
            XCTAssertEqual(ns.domain, "BlazeDBManager")
            XCTAssertEqual(ns.code, 3650)
        }
        manager.unmountAllDatabases()
    }

    private func key(for dbURL: URL) throws -> SymmetricKey {
        let saltURL = dbURL.deletingPathExtension().appendingPathExtension("salt")
        let salt: Data
        if FileManager.default.fileExists(atPath: saltURL.path) {
            salt = try Data(contentsOf: saltURL)
        } else {
            salt = try SecureRandom.bytesStrict(count: 16)
            try salt.write(to: saltURL, options: .atomic)
        }
        return try KeyManager.getKey(from: password, salt: salt)
    }
}
