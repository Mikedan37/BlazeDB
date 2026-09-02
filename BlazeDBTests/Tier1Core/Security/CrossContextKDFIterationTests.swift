//
//  CrossContextKDFIterationTests.swift
//  BlazeDB_Tier1
//
//  A database created in one KDF context must open in the other.
//  `KeyManager.pbkdf2Iterations` is 600k in production and 100k under XCTest,
//  so the same password+salt derives different keys per context. A meta signed
//  by a production launch must still verify when an XCTest-hosted process
//  opens it (and vice versa), and the client must adopt the key that verified
//  so page decryption stays consistent.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class CrossContextKDFIterationTests: XCTestCase {
    private let password = "CrossContext-2026!"

    override func setUpWithError() throws {
        BlazeDBClient.clearSessionKeys()
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        BlazeDBClient.clearSessionKeys()
    }

    private func makeDBURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cross-context-\(label)-\(UUID().uuidString)")
            .appendingPathExtension("blazedb")
    }

    /// Production launch writes the DB (600k), a test-hosted process reopens it (100k).
    /// This is the direction that fatally crashed Seeker: the reopen context's
    /// fallback list never tried the production iteration count.
    func testDatabaseCreatedUnderProductionIterationsOpensUnderXCTestIterations() throws {
        let url = makeDBURL("prod-to-test")

        KeyManager.setTestPBKDF2IterationsOverride(KeyManager.productionPBKDF2Iterations)
        let seededID: UUID
        do {
            let db = try BlazeDBClient(name: "cross", fileURL: url, password: password)
            seededID = try db.insert(BlazeDataRecord(["marker": .string("prod-context")]))
            try db.persist()
            try db.close()
        }

        // Simulate the other process context: different iteration count, no
        // in-process session or cached key to fall back on.
        BlazeDBClient.clearSessionKeys()
        KeyManager.setTestPBKDF2IterationsOverride(KeyManager.xctestPBKDF2Iterations)

        let reopened = try BlazeDBClient(name: "cross", fileURL: url, password: password)
        defer { try? reopened.close() }
        let record = try reopened.fetch(id: seededID)
        XCTAssertEqual(record?["marker"], .string("prod-context"))
    }
}
