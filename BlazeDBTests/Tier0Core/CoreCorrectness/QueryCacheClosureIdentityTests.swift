import Foundation
import XCTest
@testable import BlazeDBCore

/// `where { }` records only `closure_N`. Two different predicates at the same
/// position used to share an `execute(withCache:)` entry and return each other's rows.
/// The RLS select gate stays cacheable because its identity is the partition, not the body.
final class QueryCacheClosureIdentityTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueryCacheClosure-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        let base = databaseURL.deletingPathExtension()
        for url in [databaseURL!, base.appendingPathExtension("meta"),
                    base.appendingPathExtension("salt"), base.appendingPathExtension("wal")] {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    func testDistinctClosuresDoNotShareCachedRows() throws {
        let database = try openDatabase()
        defer { try? database.close() }

        let alpha = try database.query()
            .where { $0.storage["name"]?.stringValue == "alpha" }
            .execute(withCache: 60)
        let beta = try database.query()
            .where { $0.storage["name"]?.stringValue == "beta" }
            .execute(withCache: 60)

        XCTAssertEqual(names(try alpha.records), ["alpha"])
        XCTAssertEqual(names(try beta.records), ["beta"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 0, "Unstable closures must not be stored")

        let legacyBeta = try database.query()
            .where { $0.storage["name"]?.stringValue == "beta" }
            .executeWithCache(ttl: 60)
        XCTAssertEqual(names(legacyBeta), ["beta"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 0)
    }

    func testClosureAfterDescribedFilterDoesNotReuseTheOtherPredicate() throws {
        let database = try openDatabase()
        defer { try? database.close() }

        let alpha = try database.query()
            .where("kind", equals: .string("a"))
            .where { $0.storage["name"]?.stringValue == "alpha" }
            .execute(withCache: 60)
        let alpine = try database.query()
            .where("kind", equals: .string("a"))
            .where { $0.storage["name"]?.stringValue == "alpine" }
            .execute(withCache: 60)

        XCTAssertEqual(names(try alpha.records), ["alpha"])
        XCTAssertEqual(names(try alpine.records), ["alpine"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 0)
    }

    func testNotLikePatternsDoNotShareCachedRows() throws {
        let database = try openDatabase()
        defer { try? database.close() }

        let notA = try database.query().where("name", notLike: "a%").execute(withCache: 60)
        let notB = try database.query().where("name", notLike: "b%").execute(withCache: 60)

        XCTAssertEqual(names(try notA.records), ["beta"])
        XCTAssertEqual(names(try notB.records), ["alpha", "alpine"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 0)
    }

    func testGroupedClosuresDoNotShareCachedGroups() throws {
        let database = try openDatabase()
        defer { try? database.close() }

        let onlyA = try database.query()
            .where { $0.storage["kind"]?.stringValue == "a" }
            .groupBy("kind")
            .count()
            .execute(withCache: 60)
            .grouped
        let onlyB = try database.query()
            .where { $0.storage["kind"]?.stringValue == "b" }
            .groupBy("kind")
            .count()
            .executeGroupedAggregationWithCache(ttl: 60)

        XCTAssertEqual(onlyA.groups["a"]?.count, 2)
        XCTAssertNil(onlyA.groups["b"])
        XCTAssertEqual(onlyB.groups["b"]?.count, 1)
        XCTAssertNil(onlyB.groups["a"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 0)
    }

    func testDescribedEqualityStillConsumesPlantedCacheHit() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        let query = database.query().where("name", equals: .string("alpha"))
        XCTAssertEqual(names(try query.execute(withCache: 60).records), ["alpha"])
        let key = QueryCacheNamespace.queryResult + query.generateCacheKey()
        QueryCache.shared.set(
            key: key,
            value: QueryResult.records([BlazeDataRecord(["name": .string("planted")])]),
            ttl: 60
        )
        let replay = try database.query().where("name", equals: .string("alpha")).execute(withCache: 60)
        XCTAssertEqual(names(try replay.records), ["planted"])
    }

    func testRLSSelectGateStillConsumesPlantedCacheHit() throws {
        let teamA = UUID()
        let database = try openDatabase(teamID: teamA)
        defer { try? database.close() }
        let teamB = UUID()
        _ = try database.insert(BlazeDataRecord(["name": .string("secret"), "teamId": .uuid(teamB), "kind": .string("b")]))

        database.enableRLS()
        database.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        database.setRLSContext(userID: UUID(), teamIDs: [teamA], roles: ["member"])
        QueryCache.shared.clearAll()

        let query = database.query()
        XCTAssertEqual(query.filterDescriptors.first?.cacheIdentityStable, true)
        let visible = try query.execute(withCache: 60)
        XCTAssertEqual(names(try visible.records), ["alpha", "alpine", "beta"])

        let key = QueryCacheNamespace.queryResult + query.generateCacheKey()
        let stored: QueryResult? = QueryCache.shared.get(key: key)
        XCTAssertEqual(names(try stored?.records ?? []), ["alpha", "alpine", "beta"],
                       "The RLS select gate must still be stored under its partition key")
        QueryCache.shared.set(
            key: key,
            value: QueryResult.records([BlazeDataRecord(["name": .string("planted")])]),
            ttl: 60
        )
        let replay = try database.query().execute(withCache: 60)
        XCTAssertEqual(names(try replay.records), ["planted"])
    }

    func testRLSContextDoesNotMakeUserClosuresShareACacheEntry() throws {
        let database = try openDatabase()
        defer { try? database.close() }
        database.enableRLS()
        database.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        database.setRLSContext(userID: UUID(), teamIDs: [UUID()], roles: ["admin"])
        QueryCache.shared.clearAll()

        let alpha = try database.query()
            .where { $0.storage["name"]?.stringValue == "alpha" }
            .execute(withCache: 60)
        let beta = try database.query()
            .where { $0.storage["name"]?.stringValue == "beta" }
            .execute(withCache: 60)

        XCTAssertEqual(names(try alpha.records), ["alpha"])
        XCTAssertEqual(names(try beta.records), ["beta"])
        XCTAssertEqual(QueryCache.shared.stats().entries, 0)
    }

    private func openDatabase(teamID: UUID = UUID()) throws -> BlazeDBClient {
        let database = try BlazeDBClient(
            name: "closure_cache",
            fileURL: databaseURL,
            password: "QueryCacheClosure-Test-2026!"
        )
        for (name, kind) in [("alpha", "a"), ("alpine", "a"), ("beta", "b")] {
            _ = try database.insert(BlazeDataRecord([
                "name": .string(name),
                "kind": .string(kind),
                "teamId": .uuid(teamID)
            ]))
        }
        return database
    }

    private func names(_ records: [BlazeDataRecord]) -> [String] {
        records.compactMap { $0.storage["name"]?.stringValue }.sorted()
    }
}
