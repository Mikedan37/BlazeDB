//
//  RecordCacheLifecycleTests.swift
//  BlazeDBTests — #307: evict per-database record caches at teardown
//

import XCTest
import Foundation
@testable import BlazeDBCore

final class RecordCacheLifecycleTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordCacheLifecycle-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        unsetenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE")
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// #307: a fresh database recreated at the same path must not inherit a
    /// decoded record cached by the previous session.
    func testCloseAndRecreateSamePathDoesNotReturnStaleCachedPayload() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache.blazedb")
        let password = "RecordCacheLifecycle-Pass_123!"
        let recordID = UUID()

        let firstSession = try BlazeDBClient(
            name: "record-cache-first",
            fileURL: databaseURL,
            password: password
        )
        try firstSession.insert(
            BlazeDataRecord(["payload": .string("first-session")]),
            id: recordID
        )
        let firstPayload = try firstSession.fetch(id: recordID)?.storage["payload"]?.stringValue
        XCTAssertEqual(firstPayload, "first-session")
        try firstSession.close()

        let databaseBaseURL = databaseURL.deletingPathExtension()
        for extensionName in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(
                at: databaseBaseURL.appendingPathExtension(extensionName)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))

        let secondSession = try BlazeDBClient(
            name: "record-cache-second",
            fileURL: databaseURL,
            password: password
        )
        try secondSession.insert(
            BlazeDataRecord(["payload": .string("second-session")]),
            id: recordID
        )
        let secondPayload = try secondSession.fetch(id: recordID)?.storage["payload"]?.stringValue
        XCTAssertEqual(secondPayload, "second-session")
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        try secondSession.close()
    }

    // MARK: - #307 registry-ownership coverage

    private static let databasePassword = "RecordCacheLifecycle-Pass_123!"

    private func makeClient(_ name: String, at url: URL) throws -> BlazeDBClient {
        try BlazeDBClient(name: name, fileURL: url, password: Self.databasePassword)
    }

    /// `forDatabase` mints a fresh empty cache for an unowned path, so a released path
    /// can never surface a decode made by a previous session.
    private func assertNoRegisteredDecode(_ id: UUID, at path: String, _ message: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(RecordCache.forDatabase(path).get(id: id), message, file: file, line: line)
    }

    /// Seeds `count` fillers plus one fetched record (populating the cache), then persists
    /// so `unsavedChanges` is zero before VACUUM.
    private func seedAndPopulateCache(_ client: BlazeDBClient, cachedID: UUID, count: Int) throws -> Int {
        for value in 0..<count {
            _ = try client.insert(BlazeDataRecord(["value": .int(value)]))
        }
        try client.insert(BlazeDataRecord(["payload": .string("pre-vacuum")]), id: cachedID)
        XCTAssertNotNil(try client.fetch(id: cachedID), "seeding must populate the record cache")
        try client.persist()
        return count + 1
    }

    /// #307: teardown through `deinit` must release the registry entry exactly like an
    /// explicit close, so a database recreated at the same path serves only its own data.
    func testDeinitWithoutExplicitCloseDoesNotLeaveDecodedRecordsRegistered() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache-deinit.blazedb")
        let recordID = UUID()
        var firstSession: BlazeDBClient? = try makeClient("record-cache-deinit-first", at: databaseURL)
        let registryPath = try XCTUnwrap(firstSession?.collection.fileURL.path)
        try firstSession?.insert(BlazeDataRecord(["payload": .string("first-session")]), id: recordID)
        XCTAssertEqual(try firstSession?.fetch(id: recordID)?.storage["payload"]?.stringValue, "first-session")
        firstSession = nil  // deterministic drop: this teardown runs through deinit only
        assertNoRegisteredDecode(recordID, at: registryPath, "deinit must release the registry entry")

        let databaseBaseURL = databaseURL.deletingPathExtension()
        for extensionName in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(at: databaseBaseURL.appendingPathExtension(extensionName))
        }
        let secondSession = try makeClient("record-cache-deinit-second", at: databaseURL)
        try secondSession.insert(BlazeDataRecord(["payload": .string("second-session")]), id: recordID)
        XCTAssertEqual(try secondSession.fetch(id: recordID)?.storage["payload"]?.stringValue, "second-session")
        try secondSession.close()
    }

    /// #307: a successful VACUUM installs a replacement collection, which must own the
    /// path's registry entry; the pre-vacuum cache is emptied on its way out.
    func testVacuumSuccessInstallsFreshOwnedCache() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache-vacuum-success.blazedb")
        let seededID = UUID()
        let client = try makeClient("record-cache-vacuum-success", at: databaseURL)
        let seededCount = try seedAndPopulateCache(client, cachedID: seededID, count: 20)
        let registryPath = client.collection.fileURL.path
        let preVacuumCache = client.collection.recordCache
        XCTAssertNotNil(preVacuumCache.get(id: seededID), "fixture must cache a decoded record")

        try client.vacuum()
        XCTAssertTrue(RecordCache.forDatabase(registryPath) === client.collection.recordCache,
                      "the live post-vacuum collection must own the registry entry for its path")
        XCTAssertFalse(client.collection.recordCache === preVacuumCache,
                       "the pre-vacuum cache must not stay registered for the replacement")
        XCTAssertNil(preVacuumCache.get(id: seededID),
                     "a released cache must be emptied, not merely unregistered")
        XCTAssertEqual(try client.fetchAll().count, seededCount)
        try client.close()
    }

    /// #307: a VACUUM that fails before its replacement is constructed rolls back to a
    /// fresh same-path collection, which must own the registry entry.
    func testVacuumRenameFailureRollbackKeepsLiveCacheRegistered() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache-vacuum-rename.blazedb")
        let client = try makeClient("record-cache-vacuum-rename", at: databaseURL)
        let seededCount = try seedAndPopulateCache(client, cachedID: UUID(), count: 20)
        let registryPath = client.collection.fileURL.path
        let preVacuumCache = client.collection.recordCache
        setenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE", "1", 1)
        XCTAssertThrowsError(try client.vacuum(), "the simulated rename failure must surface")
        unsetenv("BLAZEDB_SIMULATE_VACUUM_RENAME_FAILURE")
        XCTAssertTrue(RecordCache.forDatabase(registryPath) === client.collection.recordCache,
                      "the rollback replacement must own the registry entry for its path")
        XCTAssertFalse(client.collection.recordCache === preVacuumCache,
                       "the pre-vacuum cache must not stay registered for the rollback replacement")
        XCTAssertEqual(try client.fetchAll().count, seededCount)
        try client.close()
    }

    /// #307: a VACUUM that fails *after* its success replacement was constructed discards that
    /// replacement while a rollback replacement is live on the same path; releasing the obsolete
    /// one must not evict the live one's cache — both can hold the very same cache object.
    func testVacuumRollbackAfterSuccessReplacementKeepsLiveCacheRegistered() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache-vacuum-post.blazedb")
        let client = try makeClient("record-cache-vacuum-post", at: databaseURL)
        let seededCount = try seedAndPopulateCache(client, cachedID: UUID(), count: 20)
        let registryPath = client.collection.fileURL.path
        // A NON-EMPTY directory at the marker path fails the write only after the replacement exists.
        let markerURL = client.collection.fileURL
            .deletingPathExtension().appendingPathExtension("vacuum_success")
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
        try Data([0x01]).write(to: markerURL.appendingPathComponent("occupied"))
        XCTAssertThrowsError(try client.vacuum(), "a post-replacement VACUUM failure must surface")
        XCTAssertTrue(RecordCache.forDatabase(registryPath) === client.collection.recordCache,
                      "an obsolete vacuum replacement must not evict the live rollback replacement's cache")
        XCTAssertEqual(try client.fetchAll().count, seededCount)
        XCTAssertFalse(client.isClosed)
        try client.close()
    }

    /// #307: a close whose flush fails must still surface that failure AND still release
    /// the registry entry — release is not conditional on flush success.
    func testCloseFlushFailureStillReleasesRegisteredCache() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache-close-flush.blazedb")
        let recordID = UUID()
        let client = try makeClient("record-cache-close-flush", at: databaseURL)
        try client.insert(BlazeDataRecord(["payload": .string("first-session")]), id: recordID)
        XCTAssertNotNil(try client.fetch(id: recordID), "fixture must cache a decoded record")
        _ = try client.insert(BlazeDataRecord(["payload": .string("unflushed")]))
        let registryPath = client.collection.fileURL.path
        setenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE", "1", 1)
        XCTAssertThrowsError(try client.collection.close(), "close must still surface the flush failure")
        assertNoRegisteredDecode(recordID, at: registryPath, "a failed flush must still release the entry")
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
    }

    /// #307: the client keeps suppressing a flush failure and keeps marking itself closed,
    /// but it must not do both while stranding a registry entry for the same path.
    func testCloseFlushFailureLeavesClientClosedWithCleanRegistry() throws {
        let databaseURL = tempDir.appendingPathComponent("record-cache-client-flush.blazedb")
        let recordID = UUID()
        let client = try makeClient("record-cache-client-flush", at: databaseURL)
        try client.insert(BlazeDataRecord(["payload": .string("first-session")]), id: recordID)
        XCTAssertNotNil(try client.fetch(id: recordID), "fixture must cache a decoded record")
        _ = try client.insert(BlazeDataRecord(["payload": .string("unflushed")]))
        let registryPath = client.collection.fileURL.path
        setenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE", "1", 1)
        XCTAssertNoThrow(try client.close(), "client close must keep suppressing flush failures")
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
        XCTAssertTrue(client.isClosed, "client close must still mark the database closed")
        assertNoRegisteredDecode(recordID, at: registryPath, "a closed client must not strand an entry")
    }

    /// #307: for any path P, an acquisition of P must never observe a decode written by an
    /// earlier acquisition of P — whether or not that predecessor ever released. Transferring
    /// ownership is not enough on its own: the successor is handed the very same cache object.
    func testAcquireNeverInheritsAPreviousAcquisitionsDecodes() {
        let registryPath = tempDir.appendingPathComponent("registry-property.blazedb").path
        let recordID = UUID()
        let predecessor = RecordCache.acquire(forDatabase: registryPath)
        predecessor.cache.set(id: recordID, record: BlazeDataRecord(["payload": .string("previous-session")]))
        // The predecessor deliberately never releases: a still-open handle, or an initializer
        // that threw after acquiring, leaves its entry in place and the property must still hold.
        let successor = RecordCache.acquire(forDatabase: registryPath)
        XCTAssertNil(successor.cache.get(id: recordID),
                     "a new acquisition must never inherit a previous owner's decodes")
        RecordCache.release(forDatabase: registryPath, token: predecessor.token)
        RecordCache.release(forDatabase: registryPath, token: successor.token)
    }

    /// #307: lazy-field fetches must use the owning database's cache, not the
    /// process-global UUID-only cache shared by unrelated databases.
    func testLazyFieldFetchDoesNotReuseSharedCacheAcrossDatabaseInstances() throws {
        RecordCache.shared.clear()
        defer { RecordCache.shared.clear() }

        let recordID = UUID()
        let firstDatabase = try makeClient(
            "lazy-field-first",
            at: tempDir.appendingPathComponent("lazy-field-first.blazedb")
        )
        defer { try? firstDatabase.close() }
        try firstDatabase.insert(
            BlazeDataRecord(["payload": .string("database-a")]),
            id: recordID
        )

        let firstRecord = try XCTUnwrap(
            try firstDatabase.collection.fetchLazyFieldRecord(id: recordID),
            "the first database must return its lazy-field record"
        )
        XCTAssertEqual(firstRecord["payload"]?.stringValue, "database-a")
        XCTAssertNil(
            RecordCache.shared.get(id: recordID),
            "lazy-field fetch must not populate the process-global cache"
        )

        let secondDatabase = try makeClient(
            "lazy-field-second",
            at: tempDir.appendingPathComponent("lazy-field-second.blazedb")
        )
        defer { try? secondDatabase.close() }
        try secondDatabase.insert(
            BlazeDataRecord(["payload": .string("database-b")]),
            id: recordID
        )
        RecordCache.shared.set(
            id: recordID,
            record: BlazeDataRecord(["payload": .string("stale-global")])
        )

        let secondRecord = try XCTUnwrap(
            try secondDatabase.collection.fetchLazyFieldRecord(id: recordID),
            "the second database must return its own lazy-field record"
        )
        XCTAssertEqual(secondRecord["payload"]?.stringValue, "database-b")
        RecordCache.shared.remove(id: recordID)
    }
}
