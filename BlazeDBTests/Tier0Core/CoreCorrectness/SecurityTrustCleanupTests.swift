//
//  SecurityTrustCleanupTests.swift
//  BlazeDBTests
//
//  Tier 0 regressions for the security-trust cleanup pass
//  (#365, #334–#337, #358-adjacent, KDF constants, #357).
//

import XCTest
@testable import BlazeDBCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

final class SecurityTrustCleanupTests: XCTestCase {
    private var tempDir: URL!
    private let password = "SecurityTrust-Cleanup-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecurityTrust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - KDF constants (#273)

    func testProductionPBKDF2IterationConstantIs600k() {
        XCTAssertEqual(KeyManager.productionPBKDF2Iterations, 600_000)
        XCTAssertEqual(KeyManager.xctestPBKDF2Iterations, 100_000)
    }

    func testPBKDF2DerivationIsDeterministicForFixedInputs() throws {
        let salt = Data(repeating: 0x42, count: 16)
        let a = try KeyManager.deriveKeyPBKDF2(
            password: Data("fixed-pass".utf8),
            salt: salt,
            iterations: 1_000,
            keyLength: 32
        )
        let b = try KeyManager.deriveKeyPBKDF2(
            password: Data("fixed-pass".utf8),
            salt: salt,
            iterations: 1_000,
            keyLength: 32
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }

    // MARK: - #365 unauthenticated txn_log

    func testManagerMountRemovesUnauthenticatedTxnLogWithoutReplay() throws {
        let dbURL = tempDir.appendingPathComponent("mount-txnlog.blazedb")
        let password = self.password

        // Create a legitimate encrypted DB with one page of known plaintext.
        let store1 = try PageStore(fileURL: dbURL, key: try KeyManager.getKey(from: password, salt: try loadSalt(for: dbURL)))
        let original = Data(repeating: 0xAB, count: 64)
        try store1.writePage(index: 7, plaintext: original)
        store1.close()

        // Plant an unauthenticated NDJSON journal that would overwrite page 7.
        let injected = Data(repeating: 0xEE, count: 64)
        let journal = tempDir.appendingPathComponent("txn_log.json")
        let txID = UUID().uuidString
        let begin = try JSONEncoder().encode(TransactionLog.Operation.begin(txID: txID))
        let write = try JSONEncoder().encode(TransactionLog.Operation.write(pageID: 7, data: injected))
        let commit = try JSONEncoder().encode(TransactionLog.Operation.commit(txID: txID))
        var ndjson = Data()
        ndjson.append(begin); ndjson.append(0x0A)
        ndjson.append(write); ndjson.append(0x0A)
        ndjson.append(commit); ndjson.append(0x0A)
        try ndjson.write(to: journal)

        let manager = BlazeDBManager()
        _ = try manager.mountDatabase(named: "victim", fileURL: dbURL, password: password)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path), "sidecar must be removed, not replayed")

        manager.unmountDatabase(named: "victim")
        let salt = try Data(contentsOf: dbURL.deletingPathExtension().appendingPathExtension("salt"))
        let store2 = try PageStore(fileURL: dbURL, key: try KeyManager.getKey(from: password, salt: salt))
        let readBack = try store2.readPage(index: 7)
        XCTAssertEqual(readBack, original, "injected plaintext must not be sealed into the encrypted DB")
        store2.close()
    }

    func testRecoverAllTransactionsFailsClosedWhenTxnLogPresent() throws {
        let dbURL = tempDir.appendingPathComponent("recover-all.blazedb")
        let manager = BlazeDBManager()
        _ = try manager.mountDatabase(named: "db", fileURL: dbURL, password: password)

        let journal = tempDir.appendingPathComponent("txn_log.json")
        try Data("{\"op\":\"begin\"}\n".utf8).write(to: journal)

        XCTAssertThrowsError(try manager.recoverAllTransactions()) { error in
            let ns = error as NSError
            XCTAssertEqual(ns.domain, "BlazeDBManager")
            XCTAssertEqual(ns.code, 3650)
        }
        manager.unmountAllDatabases()
    }

    // MARK: - RLS #334–#337

    func testPublicGraphHonorsClientRLSContext() throws {
        let url = tempDir.appendingPathComponent("graph-rls.blazedb")
        let db = try BlazeDBClient(name: "graph-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let teamA = UUID()
        let teamB = UUID()
        let userA = UUID()

        db.enableRLS()
        db.setRLSContext(userID: userA, teamIDs: [teamA], roles: ["engineer"])
        db.rls.addPolicy(SecurityPolicy(
            name: "team_select",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let team = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(team)
        })

        // Inserts need insert policy or disable briefly — use admin role for seed then switch.
        db.setRLSContext(userID: userA, teamIDs: [teamA, teamB], roles: ["admin"])
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamA), "n": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamA), "n": .int(2)]))
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamB), "n": .int(3)]))

        db.setRLSContext(userID: userA, teamIDs: [teamA], roles: ["engineer"])
        let points = try db.graph().x("team_id").y(.count).toPoints()
        XCTAssertEqual(points.count, 1, "public graph() must apply client RLS context (#334)")
        XCTAssertEqual(points.first?.y as? Int, 2)
    }

    func testUpdateRejectsPostMutationRLSViolation() throws {
        let url = tempDir.appendingPathComponent("with-check.blazedb")
        let db = try BlazeDBClient(name: "with-check", fileURL: url, password: password)
        defer { try? db.close() }

        let owner = UUID()
        let other = UUID()
        db.enableRLS()
        db.setRLSContext(userID: owner, roles: ["admin"])
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_update",
            operation: .update,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID
        })
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_insert",
            operation: .insert,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID || context.hasRole("admin")
        })
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_select",
            operation: .select,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID || context.hasRole("admin")
        })

        let id = try db.insert(BlazeDataRecord(["userId": .uuid(owner), "note": .string("mine")]))
        db.setRLSContext(userID: owner, roles: ["member"])

        var stolen = try XCTUnwrap(try db.fetch(id: id))
        stolen.storage["userId"] = .uuid(other)
        XCTAssertThrowsError(try db.update(id: id, with: stolen), "WITH CHECK must reject ownership transfer (#335)")
        let still = try XCTUnwrap(try db.fetch(id: id))
        XCTAssertEqual(still.storage["userId"]?.uuidValue, owner)
    }

    func testGetRecordCountRespectsRLS() throws {
        let url = tempDir.appendingPathComponent("count-rls.blazedb")
        let db = try BlazeDBClient(name: "count-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let user = UUID()
        let other = UUID()
        db.enableRLS()
        db.setRLSContext(userID: user, roles: ["admin"])
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        _ = try db.insert(BlazeDataRecord(["userId": .uuid(user)]))
        _ = try db.insert(BlazeDataRecord(["userId": .uuid(other)]))

        db.setRLSContext(userID: user, roles: ["member"])
        XCTAssertEqual(db.getRecordCount(), 1, "getRecordCount must not leak total rows under RLS (#336)")
        XCTAssertEqual(try db.stats().recordCount, 1)
    }

    func testFilteredObservationDoesNotForwardDeletes() throws {
        let url = tempDir.appendingPathComponent("observe-rls.blazedb")
        let db = try BlazeDBClient(name: "observe-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["tag": .string("keep")]))
        let exp = expectation(description: "no delete forwarded")
        exp.isInverted = true
        let token = db.observe(where: { ($0.storage["tag"]?.stringValue ?? "") == "keep" }) { changes in
            for change in changes {
                if case .delete = change.type {
                    exp.fulfill()
                }
            }
        }
        defer { token.invalidate() }

        try db.delete(id: id)
        wait(for: [exp], timeout: 0.3)
    }

    // MARK: - #357 permissions

    func testNewDatabaseArtifactsAreOwnerOnlyOnPOSIX() throws {
        #if os(Windows)
        throw XCTSkip("POSIX permissions not applicable on Windows")
        #else
        let url = tempDir.appendingPathComponent("perms.blazedb")
        let db = try BlazeDBClient(name: "perms", fileURL: url, password: password)
        defer { try? db.close() }

        let salt = url.deletingPathExtension().appendingPathExtension("salt")
        let dbMode = try posixMode(at: url)
        let saltMode = try posixMode(at: salt)
        XCTAssertEqual(dbMode & 0o077, 0, "DB file must not be group/world accessible")
        XCTAssertEqual(saltMode & 0o077, 0, ".salt must not be group/world accessible")
        #endif
    }

    // MARK: - helpers

    private func loadSalt(for fileURL: URL) throws -> Data {
        let saltURL = fileURL.deletingPathExtension().appendingPathExtension("salt")
        if FileManager.default.fileExists(atPath: saltURL.path) {
            return try Data(contentsOf: saltURL)
        }
        let salt = try SecureRandom.bytesStrict(count: 16)
        try SecureFileAttributes.writeOwnerOnly(salt, to: saltURL)
        return salt
    }

    private func posixMode(at url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let mode = attrs[.posixPermissions] as? NSNumber else {
            throw NSError(domain: "SecurityTrustCleanupTests", code: 1)
        }
        return mode.intValue
    }
}
