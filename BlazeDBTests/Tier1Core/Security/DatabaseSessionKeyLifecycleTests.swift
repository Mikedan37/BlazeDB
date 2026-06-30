//
//  DatabaseSessionKeyLifecycleTests.swift
//  BlazeDB_Tier1
//
//  Process-session key lifecycle — see DATABASE_SESSION_KEY_LIFECYCLE.md
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DatabaseSessionKeyLifecycleTests: XCTestCase {
    private let password = "SessionLifecycle-123!"
    private let altPassword = "AltSessionLife-456!"

    override func setUpWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(2_000)
        KeyManager.resetPBKDF2DerivationCountForTesting()
        BlazeDBClient.clearSessionKeys()
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        BlazeDBClient.clearSessionKeys()
    }

    private func makeDBURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("session-\(label)-\(UUID().uuidString).blazedb")
    }

    private func seedDatabase(at url: URL) throws -> UUID {
        let db = try BlazeDBClient(name: "seed", fileURL: url, password: password)
        defer { try? db.close() }
        let id = try db.insert(BlazeDataRecord(["marker": .string("seeded")]))
        try db.persist()
        return id
    }

    func testColdOpenRunsPBKDF2() throws {
        let dbURL = makeDBURL("cold")
        defer { cleanupBlazeDBFiles(at: dbURL) }

        _ = try seedDatabase(at: dbURL)
        KeyManager.resetPBKDF2DerivationCountForTesting()
        BlazeDBClient.clearSessionKeys()

        _ = try BlazeDBClient(name: "cold", fileURL: dbURL, password: password)
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 1)
    }

    func testReopenInSameProcessSkipsPBKDF2() throws {
        let dbURL = makeDBURL("warm")
        defer { cleanupBlazeDBFiles(at: dbURL) }

        let id = try seedDatabase(at: dbURL)
        KeyManager.resetPBKDF2DerivationCountForTesting()

        var db = try BlazeDBClient(name: "warm", fileURL: dbURL, password: password)
        try db.close()
        db = try BlazeDBClient(name: "warm", fileURL: dbURL, password: password)
        let record = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(record["marker"], .string("seeded"))
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 0)
        try db.close()
    }

    func testSessionInvalidationForcesPBKDF2Again() throws {
        let dbURL = makeDBURL("invalidate")
        defer { cleanupBlazeDBFiles(at: dbURL) }

        _ = try seedDatabase(at: dbURL)
        BlazeDBClient.clearSessionKeys()

        var db = try BlazeDBClient(name: "invalidate", fileURL: dbURL, password: password)
        try db.close()

        KeyManager.resetPBKDF2DerivationCountForTesting()
        BlazeDBClient.clearSessionKeys(for: dbURL.path)

        db = try BlazeDBClient(name: "invalidate", fileURL: dbURL, password: password)
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 1)
        try db.close()
    }

    func testWrongPasswordOnWarmReopenFails() throws {
        let dbURL = makeDBURL("wrong-warm")
        defer { cleanupBlazeDBFiles(at: dbURL) }

        _ = try seedDatabase(at: dbURL)

        var db = try BlazeDBClient(name: "wrong-warm", fileURL: dbURL, password: password)
        try db.close()

        XCTAssertThrowsError(
            try BlazeDBClient(name: "wrong-warm", fileURL: dbURL, password: altPassword)
        ) { error in
            guard case BlazeDBError.passwordMismatch = error else {
                XCTFail("Expected passwordMismatch, got \(error)")
                return
            }
        }

        db = try BlazeDBClient(name: "wrong-warm", fileURL: dbURL, password: password)
        try db.close()
    }

    func testTwoDatabasesDoNotEvictEachOthersSession() throws {
        let dbURL1 = makeDBURL("multi-a")
        let dbURL2 = makeDBURL("multi-b")
        defer {
            cleanupBlazeDBFiles(at: dbURL1)
            cleanupBlazeDBFiles(at: dbURL2)
        }

        _ = try seedDatabase(at: dbURL1)
        _ = try seedDatabase(at: dbURL2)

        var db1 = try BlazeDBClient(name: "a", fileURL: dbURL1, password: password)
        var db2 = try BlazeDBClient(name: "b", fileURL: dbURL2, password: password)
        try db1.close()
        try db2.close()

        BlazeDBClient.clearSessionKeys(for: dbURL1.path)

        KeyManager.resetPBKDF2DerivationCountForTesting()
        db1 = try BlazeDBClient(name: "a", fileURL: dbURL1, password: password)
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 1)

        KeyManager.resetPBKDF2DerivationCountForTesting()
        db2 = try BlazeDBClient(name: "b", fileURL: dbURL2, password: password)
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 0)

        try db1.close()
        try db2.close()
    }

    func testCloseReleasesHandleButPreservesSessionKey() throws {
        let dbURL = makeDBURL("close-preserve")
        defer { cleanupBlazeDBFiles(at: dbURL) }

        let id = try seedDatabase(at: dbURL)

        var db = try BlazeDBClient(name: "close-preserve", fileURL: dbURL, password: password)
        try db.close()
        XCTAssertTrue(db.isClosed)

        KeyManager.resetPBKDF2DerivationCountForTesting()
        db = try BlazeDBClient(name: "close-preserve", fileURL: dbURL, password: password)
        let record = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(record["marker"], .string("seeded"))
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 0)
        try db.close()
    }

    func testClearSessionKeysEvictsAllSessions() throws {
        let dbURL = makeDBURL("clear-all")
        defer { cleanupBlazeDBFiles(at: dbURL) }

        _ = try seedDatabase(at: dbURL)
        var db = try BlazeDBClient(name: "clear-all", fileURL: dbURL, password: password)
        try db.close()

        BlazeDBClient.clearSessionKeys()
        KeyManager.resetPBKDF2DerivationCountForTesting()

        db = try BlazeDBClient(name: "clear-all", fileURL: dbURL, password: password)
        XCTAssertEqual(KeyManager.pbkdf2DerivationCountForTesting, 1)
        try db.close()
    }
}
