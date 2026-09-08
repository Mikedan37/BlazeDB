//  QueryCacheNamespaceTests.swift
//  BlazeDBTests
//
//  Regression tests for #454: the cached query APIs store different result types
//  and must not share a cache key.

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// `execute(withCache:)` stores a `QueryResult`; the deprecated `executeWithCache(ttl:)`
/// stores `[BlazeDataRecord]`. Both derived their key from `generateCacheKey()`, so
/// alternating the two APIs on the same query shape made every lookup fail its type
/// cast, re-execute, and overwrite the other API's entry — correct results, but the
/// cache never held a usable entry for either caller.
///
/// Each cached path must therefore carry a result-type namespace in its key.
final class QueryCacheNamespaceTests: XCTestCase {

    private var tempURL: URL?
    private var db: BlazeDBClient?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueryCacheNamespace-\(testID).blazedb")
        db = try BlazeDBClient(
            name: "query_cache_namespace_\(testID)",
            fileURL: try requireFixture(tempURL),
            password: "QueryCacheNamespace123!"
        )
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        db = nil
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("wal"))
        }
        super.tearDown()
    }

    /// Plants a deliberately incompatible payload in each API's namespace, then
    /// alternates the two APIs. A shared key cannot satisfy both: whichever entry
    /// was written last wins, and the other API misses, re-executes and overwrites.
    ///
    /// The planted payloads carry a `sentinel` field that no stored record has, so a
    /// re-execution is distinguishable from a cache hit — entry counts alone would
    /// not tell the two apart.
    func testCachedQueryAPIs_KeepSeparateNamespacesPerResultType() throws {
        for i in 0..<3 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "idx": .int(i)]))
        }

        // Writes clear the cache, so plant only once the data is in place.
        QueryCache.shared.clearAll()

        let baseKey = try requireFixture(db).query()
            .where("status", equals: .string("open"))
            .generateCacheKey()

        let legacySentinel = [BlazeDataRecord(["sentinel": .string("legacy")])]
        QueryCache.shared.set(key: "legacy-records:" + baseKey, value: legacySentinel, ttl: 60)

        let modernSentinel = QueryResult.records([BlazeDataRecord(["sentinel": .string("modern")])])
        QueryCache.shared.set(key: "query-result:" + baseKey, value: modernSentinel, ttl: 60)

        for round in 1...3 {
            let legacy = try requireFixture(db).query()
                .where("status", equals: .string("open"))
                .executeWithCache(ttl: 60)
            XCTAssertEqual(
                legacy.first?["sentinel"],
                .string("legacy"),
                "round \(round): deprecated API did not read its own namespace"
            )

            let modern = try requireFixture(db).query()
                .where("status", equals: .string("open"))
                .execute(withCache: 60)
            XCTAssertEqual(
                try modern.records.first?["sentinel"],
                .string("modern"),
                "round \(round): modern API did not read its own namespace"
            )
        }
    }

    /// Each API must occupy its own cache slot. Sharing one key means the second call
    /// overwrites the first, leaving a single entry that only one caller can ever use.
    func testCachedQueryAPIs_OccupySeparateCacheEntries() throws {
        for i in 0..<3 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["status": .string("open"), "idx": .int(i)]))
        }

        QueryCache.shared.clearAll()

        _ = try requireFixture(db).query()
            .where("status", equals: .string("open"))
            .executeWithCache(ttl: 60)
        _ = try requireFixture(db).query()
            .where("status", equals: .string("open"))
            .execute(withCache: 60)

        XCTAssertEqual(
            QueryCache.shared.stats().entries,
            2,
            "the two cached APIs store different result types and must not share one entry"
        )
    }
}
