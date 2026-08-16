import Foundation
import XCTest
@testable import BlazeDBCore

final class QueryCacheDatabaseIsolationTests: XCTestCase {
    private let databaseName = "query_cache_isolation"
    private let password = "QueryCacheIsolation-Test-2026!"
    private var databaseURLs: [URL] = []

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        databaseURLs = [
            directory.appendingPathComponent("QueryCacheDatabaseIsolation-A-\(id).blazedb"),
            directory.appendingPathComponent("QueryCacheDatabaseIsolation-B-\(id).blazedb")
        ]
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        for url in databaseURLs {
            for artifact in databaseArtifacts(for: url) { try? FileManager.default.removeItem(at: artifact) }
        }
        super.tearDown()
    }

    func testExecuteWithCacheIsScopedPerDatabaseInstance() throws {
        let (databaseA, databaseB) = try openDatabases()
        defer { close(databaseA, databaseB) }
        try seed(databaseA, owner: "database-a", value: 101)
        try seed(databaseB, owner: "database-b", value: 202)

        XCTAssertEqual(try cachedOwners(databaseA), ["database-a"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 1, "First cached call must create one entry")
        XCTAssertEqual(try cachedOwners(databaseA), ["database-a"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 1, "Identical calls must reuse one cache entry")
        XCTAssertEqual(try cachedOwners(databaseB), ["database-b"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 2, "Distinct live databases need distinct entries")
        XCTAssertEqual(try cachedOwners(databaseB), ["database-b"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 2, "Repeated calls in B must reuse its entry")
    }

    func testDeprecatedExecuteWithCacheIsScopedPerDatabaseInstance() throws {
        let (databaseA, databaseB) = try openDatabases()
        defer { close(databaseA, databaseB) }
        try seed(databaseA, owner: "database-a", value: 101)
        try seed(databaseB, owner: "database-b", value: 202)

        XCTAssertEqual(try cachedOwners(databaseA, deprecated: true), ["database-a"])
        XCTAssertEqual(try cachedOwners(databaseB, deprecated: true), ["database-b"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 2, "Deprecated caching must isolate same-named live databases")
    }

    func testGroupedAggregationCacheIsScopedPerDatabaseInstance() throws {
        let (databaseA, databaseB) = try openDatabases()
        defer { close(databaseA, databaseB) }
        try seed(databaseA, owner: "database-a", value: 101)
        try seed(databaseB, owner: "database-b", value: 202)

        XCTAssertEqual(try cachedTotal(databaseA), 101.0, accuracy: 0.001)
        XCTAssertEqual(try cachedTotal(databaseA), 101.0, accuracy: 0.001)
        XCTAssertEqual(try cachedTotal(databaseB), 202.0, accuracy: 0.001)
        XCTAssertEqual(try cachedTotal(databaseB), 202.0, accuracy: 0.001)
    }

    func testCloseAndReopenDoesNotReuseEarlierCacheEntry() throws {
        let (databaseA, donor) = try openDatabases()
        defer { close(databaseA, donor) }
        try seed(databaseA, owner: "before-close", value: 303)
        try seed(donor, owner: "after-reopen", value: 404)
        try seed(donor, owner: "after-reopen-extra", value: 505)
        try donor.close()

        XCTAssertEqual(try cachedOwners(databaseA), ["before-close"])
        try databaseA.close()
        // Replace closed files with pre-seeded contents; no post-cache database write can clear the old entry.
        try replaceDatabase(at: databaseURLs[0], with: databaseURLs[1])

        let reopened = try BlazeDBClient(name: databaseName, fileURL: databaseURLs[0], password: password)
        defer { close(reopened) }
        XCTAssertEqual(try cachedOwners(reopened), ["after-reopen", "after-reopen-extra"])
    }

    private func openDatabases() throws -> (BlazeDBClient, BlazeDBClient) {
        (
            try BlazeDBClient(name: databaseName, fileURL: databaseURLs[0], password: password),
            try BlazeDBClient(name: databaseName, fileURL: databaseURLs[1], password: password)
        )
    }

    private func seed(_ database: BlazeDBClient, owner: String, value: Int) throws {
        try database.insert(BlazeDataRecord([
            "kind": .string("shared"), "owner": .string(owner), "value": .int(value)
        ]))
    }

    private func cachedOwners(_ database: BlazeDBClient, deprecated: Bool = false) throws -> [String] {
        let records: [BlazeDataRecord]
        if deprecated {
            records = try database.query().where("kind", equals: .string("shared")).executeWithCache(ttl: 60)
        } else {
            records = try database.query().where("kind", equals: .string("shared")).execute(withCache: 60).records
        }
        return records.compactMap { $0.storage["owner"]?.stringValue }.sorted()
    }

    private func cachedTotal(_ database: BlazeDBClient) throws -> Double {
        let result = try database.query().groupBy("kind").sum("value", as: "total")
            .executeGroupedAggregationWithCache(ttl: 60)
        return result.groups["shared"]?.sum("total") ?? 0
    }

    private func close(_ databases: BlazeDBClient...) {
        for database in databases { try? database.close() }
    }

    private func databaseArtifacts(for url: URL) -> [URL] {
        let base = url.deletingPathExtension()
        return [url, base.appendingPathExtension("meta"), base.appendingPathExtension("salt"), base.appendingPathExtension("wal")]
    }

    private func replaceDatabase(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        let destinationArtifacts = databaseArtifacts(for: destination)
        for artifact in destinationArtifacts { try? fileManager.removeItem(at: artifact) }
        for (sourceArtifact, destinationArtifact) in zip(databaseArtifacts(for: source), destinationArtifacts)
            where fileManager.fileExists(atPath: sourceArtifact.path) {
            try fileManager.copyItem(at: sourceArtifact, to: destinationArtifact)
        }
    }
}
