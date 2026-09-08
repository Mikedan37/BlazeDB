import Foundation
import XCTest
@testable import BlazeDBCore

/// A cached JOIN result produced against right-hand collection R1 must never be
/// returned for the same left query joined to R2 (issue #450).
final class JoinQueryCacheIsolationTests: XCTestCase {
    private let databaseName = "join_query_cache_isolation"
    private let password = "JoinQueryCacheIsolation-Test-2026!"
    private let sharedRightID = UUID()
    private var databaseURLs: [URL] = []

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        databaseURLs = [
            directory.appendingPathComponent("JoinQueryCacheIsolation-L-\(id).blazedb"),
            directory.appendingPathComponent("JoinQueryCacheIsolation-R1-\(id).blazedb"),
            directory.appendingPathComponent("JoinQueryCacheIsolation-R2-\(id).blazedb")
        ]
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        for url in databaseURLs {
            for artifact in databaseArtifacts(for: url) { try? FileManager.default.removeItem(at: artifact) }
        }
        super.tearDown()
    }

    /// Distinct-payload regression: the same left query joined to two different
    /// right-hand collections must not cross-hit.
    func testJoinCacheDoesNotCrossHitBetweenRightHandCollections() throws {
        let (left, rightOne, rightTwo) = try openDatabases()
        defer { close(left, rightOne, rightTwo) }
        try seedLeft(left)
        try seedRight(rightOne, owner: "right-one")
        try seedRight(rightTwo, owner: "right-two")

        XCTAssertEqual(try cachedRightOwners(left, joining: rightOne), ["right-one"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 1, "First cached JOIN must create one entry")
        XCTAssertEqual(try cachedRightOwners(left, joining: rightOne), ["right-one"],
                       "Repeating the identical JOIN must reuse its own entry")
        XCTAssertEqual(QueryCache.shared.stats().entries, 1, "Identical JOINs must reuse one cache entry")
        XCTAssertEqual(try cachedRightOwners(left, joining: rightTwo), ["right-two"],
                       "JOIN against R2 must not return the result cached for R1")
        XCTAssertEqual(QueryCache.shared.stats().entries, 2,
                       "Distinct right-hand collections need distinct JOIN cache entries")
        XCTAssertEqual(try cachedRightOwners(left, joining: rightTwo), ["right-two"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 2)
    }

    /// The cache key itself must carry the right-hand collection identity, so no
    /// two live right-hand collections can ever address the same entry.
    func testJoinCacheKeyEncodesRightHandCollectionIdentity() throws {
        let (left, rightOne, rightTwo) = try openDatabases()
        defer { close(left, rightOne, rightTwo) }
        try seedLeft(left)
        try seedRight(rightOne, owner: "right-one")
        try seedRight(rightTwo, owner: "right-two")

        let keyOne = joinQuery(left, joining: rightOne).generateCacheKey()
        let keyTwo = joinQuery(left, joining: rightTwo).generateCacheKey()

        XCTAssertNotEqual(keyOne, keyTwo, "Live right-hand collections must not share a JOIN cache key")
        XCTAssertTrue(keyOne.contains(rightOne.collection.instanceID.uuidString),
                      "JOIN cache key must encode the right-hand collection instanceID")
        XCTAssertTrue(keyTwo.contains(rightTwo.collection.instanceID.uuidString),
                      "JOIN cache key must encode the right-hand collection instanceID")
        XCTAssertTrue(keyOne.contains(left.collection.instanceID.uuidString),
                      "JOIN cache key must still encode the left collection instanceID")
    }

    /// Distinct join tuples must remain distinct even when their field names
    /// contain characters used by the cache-key encoding.
    func testJoinCacheKeyIsUnambiguousForDelimiterBearingJoinTuples() throws {
        let (left, right, donor) = try openDatabases()
        defer { close(left, right, donor) }

        let tuples: [(foreignKey: String, primaryKey: String, type: JoinType)] = [
            ("a", "b=c", .inner),
            ("a=b", "c", .inner),
            ("a|b", "c", .inner),
            ("a", "b|c", .inner),
            ("a:b", "c", .inner),
            ("a", "b:c", .inner),
            ("a", "b", .left)
        ]

        let keys = tuples.map { tuple in
            left.query()
                .where("kind", equals: .string("joinable"))
                .join(right.collection,
                      on: tuple.foreignKey,
                      equals: tuple.primaryKey,
                      type: tuple.type)
                .generateCacheKey()
        }

        XCTAssertEqual(Set(keys).count, tuples.count,
                       "Distinct join tuples must always produce distinct cache keys")
    }

    /// Planted-cache regression: a JOIN lookup must consume the entry planted under
    /// its own key and never the entry belonging to another right-hand collection.
    func testJoinCacheConsumesPlantedHitFromMatchingRightHandCollectionOnly() throws {
        let (left, rightOne, rightTwo) = try openDatabases()
        defer { close(left, rightOne, rightTwo) }
        try seedLeft(left)
        try seedRight(rightOne, owner: "storage-one")
        try seedRight(rightTwo, owner: "storage-two")

        let keyOne = joinQuery(left, joining: rightOne).generateCacheKey()
        let keyTwo = joinQuery(left, joining: rightTwo).generateCacheKey()
        // `cachedRightOwners` reads through `execute(withCache:)`, so plant in that
        // API's result-type namespace (#454) — an unprefixed plant is never looked up.
        QueryCache.shared.set(key: QueryCacheNamespace.queryResult + keyOne, value: plantedJoin(owner: "planted-one"), ttl: 60)
        QueryCache.shared.set(key: QueryCacheNamespace.queryResult + keyTwo, value: plantedJoin(owner: "planted-two"), ttl: 60)

        XCTAssertEqual(try cachedRightOwners(left, joining: rightOne), ["planted-one"],
                       "Lookup must consume the entry planted for R1, not storage-one")
        XCTAssertEqual(try cachedRightOwners(left, joining: rightTwo), ["planted-two"],
                       "Lookup must consume the entry planted for R2, not storage-two or planted-one")
        XCTAssertEqual(QueryCache.shared.stats().entries, 2)
    }

    /// Close/reopen of the right-hand database must not consume the previous
    /// right-hand instance's JOIN cache entry.
    func testJoinCacheIsNotReusedAfterRightHandDatabaseReopens() throws {
        let (left, right, donor) = try openDatabases()
        defer { close(left, right, donor) }
        try seedLeft(left)
        try seedRight(right, owner: "before-close")
        try seedRight(donor, owner: "after-reopen")
        try donor.close()

        let staleKey = joinQuery(left, joining: right).generateCacheKey()
        XCTAssertEqual(try cachedRightOwners(left, joining: right), ["before-close"])
        try right.close()
        // Replace the closed right-hand files with pre-seeded contents; no post-cache
        // database write can clear the entry cached above.
        try replaceDatabase(at: databaseURLs[1], with: databaseURLs[2])

        let reopened = try BlazeDBClient(name: databaseName, fileURL: databaseURLs[1], password: password)
        defer { close(reopened) }
        // Re-plant so the assertion holds even if closing the database drained the cache.
        // Must use the namespace `execute(withCache:)` reads (#454), otherwise the plant
        // is unreachable and the assertion below would pass vacuously.
        QueryCache.shared.set(key: QueryCacheNamespace.queryResult + staleKey, value: plantedJoin(owner: "before-close"), ttl: 60)

        XCTAssertEqual(try cachedRightOwners(left, joining: reopened), ["after-reopen"],
                       "A reopened right-hand database must not consume the closed instance's JOIN entry")
    }

    // MARK: - Fixtures

    private func openDatabases() throws -> (BlazeDBClient, BlazeDBClient, BlazeDBClient) {
        (
            try BlazeDBClient(name: databaseName, fileURL: databaseURLs[0], password: password),
            try BlazeDBClient(name: databaseName, fileURL: databaseURLs[1], password: password),
            try BlazeDBClient(name: databaseName, fileURL: databaseURLs[2], password: password)
        )
    }

    private func seedLeft(_ database: BlazeDBClient) throws {
        try database.insert(BlazeDataRecord([
            "kind": .string("joinable"), "refId": .uuid(sharedRightID)
        ]))
    }

    private func seedRight(_ database: BlazeDBClient, owner: String) throws {
        try database.insert(BlazeDataRecord([
            "id": .uuid(sharedRightID), "owner": .string(owner)
        ]))
    }

    private func joinQuery(_ left: BlazeDBClient, joining right: BlazeDBClient) -> QueryBuilder {
        left.query()
            .where("kind", equals: .string("joinable"))
            .join(right.collection, on: "refId", equals: "id", type: .inner)
    }

    private func cachedRightOwners(_ left: BlazeDBClient, joining right: BlazeDBClient) throws -> [String] {
        let result = try joinQuery(left, joining: right).execute(withCache: 60)
        let joined = result.joinedOrNil ?? []
        return joined.compactMap { $0.right?.storage["owner"]?.stringValue }.sorted()
    }

    private func plantedJoin(owner: String) -> QueryResult {
        .joined([JoinedRecord(
            left: BlazeDataRecord(["kind": .string("joinable"), "refId": .uuid(sharedRightID)]),
            right: BlazeDataRecord(["id": .uuid(sharedRightID), "owner": .string(owner)])
        )])
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
