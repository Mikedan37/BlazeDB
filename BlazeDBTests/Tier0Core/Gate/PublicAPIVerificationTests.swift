// PublicAPIVerificationTests.swift
// BlazeDB - Open Source Release API Verification
//
// Exercises every public API category to verify nothing is broken.
// Each test is self-contained with its own database instance.

import XCTest
@testable import BlazeDBCore

final class PublicAPIVerificationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-api-verify-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeDB(_ name: String = "test") throws -> BlazeDBClient {
        let url = tempDir.appendingPathComponent("\(name).blazedb")
        return try BlazeDBClient(name: name, fileURL: url, password: "TestPassword-123!")
    }

    // MARK: - 1. Initialization

    func testInitWithURL() throws {
        let db = try makeDB("init-url")
        XCTAssertEqual(db.name, "init-url")
        XCTAssertFalse(db.isClosed)
        try db.close()
    }

    func testFailableInit() throws {
        let url = tempDir.appendingPathComponent("failable.blazedb")
        let db = BlazeDBClient(name: "failable", at: url, password: "TestPassword-123!")
        XCTAssertNotNil(db)
        try db?.close()
    }

    func testWeakPasswordRejected() {
        let url = tempDir.appendingPathComponent("weak.blazedb")
        XCTAssertThrowsError(try BlazeDBClient(name: "weak", fileURL: url, password: "abc"))
    }

    // MARK: - 2. Core CRUD

    func testInsertAndFetch() throws {
        let db = try makeDB("crud")
        let record = BlazeDataRecord(["name": .string("Alice"), "age": .int(30)])
        let id = try db.insert(record)

        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?["name"], .string("Alice"))
        XCTAssertEqual(fetched?["age"], .int(30))
        try db.close()
    }

    func testInsertWithExplicitID() throws {
        let db = try makeDB("crud-id")
        let id = UUID()
        try db.insert(BlazeDataRecord(["x": .int(1)]), id: id)
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        try db.close()
    }

    func testInsertMany() throws {
        let db = try makeDB("crud-many")
        let records = (0..<10).map { BlazeDataRecord(["i": .int($0)]) }
        let ids = try db.insertMany(records)
        XCTAssertEqual(ids.count, 10)
        try db.close()
    }

    func testFetchAll() throws {
        let db = try makeDB("crud-all")
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["i": .int(i)]))
        }
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 5)
        try db.close()
    }

    func testFetchPage() throws {
        let db = try makeDB("crud-page")
        for i in 0..<20 {
            _ = try db.insert(BlazeDataRecord(["i": .int(i)]))
        }
        let page = try db.fetchPage(offset: 5, limit: 5)
        XCTAssertEqual(page.count, 5)
        try db.close()
    }

    func testFetchBatch() throws {
        let db = try makeDB("crud-batch")
        let id1 = try db.insert(BlazeDataRecord(["x": .int(1)]))
        let id2 = try db.insert(BlazeDataRecord(["x": .int(2)]))
        let batch = try db.fetchBatch(ids: [id1, id2])
        XCTAssertEqual(batch.count, 2)
        try db.close()
    }

    func testCount() throws {
        let db = try makeDB("crud-count")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["x": .int(2)]))
        XCTAssertEqual(try db.count(), 2)
        try db.close()
    }

    func testUpdate() throws {
        let db = try makeDB("crud-update")
        let id = try db.insert(BlazeDataRecord(["name": .string("Alice")]))
        try db.update(id: id, with: BlazeDataRecord(["name": .string("Bob")]))
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?["name"], .string("Bob"))
        try db.close()
    }

    func testUpdateFields() throws {
        let db = try makeDB("crud-fields")
        let id = try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        try db.updateFields(id: id, fields: ["age": .int(31)])
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?["age"], .int(31))
        XCTAssertEqual(fetched?["name"], .string("Alice"))
        try db.close()
    }

    func testUpsert() throws {
        let db = try makeDB("crud-upsert")
        let id = UUID()
        let wasInsert1 = try db.upsert(id: id, data: BlazeDataRecord(["v": .int(1)]))
        XCTAssertTrue(wasInsert1)
        let wasInsert2 = try db.upsert(id: id, data: BlazeDataRecord(["v": .int(2)]))
        XCTAssertFalse(wasInsert2)
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?["v"], .int(2))
        try db.close()
    }

    func testDelete() throws {
        let db = try makeDB("crud-delete")
        let id = try db.insert(BlazeDataRecord(["x": .int(1)]))
        try db.delete(id: id)
        XCTAssertNil(try db.fetch(id: id))
        try db.close()
    }

    func testSoftDelete() throws {
        let db = try makeDB("crud-soft")
        let id = try db.insert(BlazeDataRecord(["x": .int(1)]))
        XCTAssertNotNil(try db.fetch(id: id))

        try db.softDelete(id: id)

        // Soft-deleted records should not appear in fetch or fetchAll
        XCTAssertNil(try db.fetch(id: id))
        let all = try db.fetchAll()
        XCTAssertTrue(all.isEmpty)
        try db.close()
    }

    func testDistinct() throws {
        let db = try makeDB("crud-distinct")
        _ = try db.insert(BlazeDataRecord(["color": .string("red")]))
        _ = try db.insert(BlazeDataRecord(["color": .string("blue")]))
        _ = try db.insert(BlazeDataRecord(["color": .string("red")]))
        let colors = try db.distinct(field: "color")
        XCTAssertEqual(colors.count, 2)
        try db.close()
    }

    // MARK: - 3. Data Types

    func testAllFieldTypes() throws {
        let db = try makeDB("types")
        let now = Date()
        let testUUID = UUID()
        let record = BlazeDataRecord([
            "str": .string("hello"),
            "num": .int(42),
            "dbl": .double(3.14),
            "flag": .bool(true),
            "when": .date(now),
            "uid": .uuid(testUUID),
            "blob": .data(Data([0x01, 0x02, 0x03])),
            "arr": .array([.int(1), .int(2)]),
            "dict": .dictionary(["key": .string("val")]),
            "nil": .null
        ])
        let id = try db.insert(record)
        let fetched = try db.fetch(id: id)!

        XCTAssertEqual(fetched["str"], .string("hello"))
        XCTAssertEqual(fetched["num"], .int(42))
        XCTAssertEqual(fetched["dbl"], .double(3.14))
        XCTAssertEqual(fetched["flag"], .bool(true))
        XCTAssertEqual(fetched["uid"], .uuid(testUUID))
        XCTAssertEqual(fetched["blob"], .data(Data([0x01, 0x02, 0x03])))
        XCTAssertEqual(fetched["arr"], .array([.int(1), .int(2)]))
        XCTAssertEqual(fetched["dict"], .dictionary(["key": .string("val")]))
        XCTAssertEqual(fetched["nil"], .null)
        if case .date(let d) = fetched["when"] {
            XCTAssertEqual(d.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Expected .date")
        }
        try db.close()
    }

    // MARK: - 4. Query Builder

    func testQueryWhereEquals() throws {
        let db = try makeDB("query-eq")
        _ = try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        _ = try db.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25)]))

        let results = try db.query()
            .where("name", equals: .string("Alice"))
            .execute()
            .records
        XCTAssertEqual(results.count, 1)
        try db.close()
    }

    func testQueryWhereGreaterThan() throws {
        let db = try makeDB("query-gt")
        _ = try db.insert(BlazeDataRecord(["score": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["score": .int(50)]))
        _ = try db.insert(BlazeDataRecord(["score": .int(90)]))

        let results = try db.query()
            .where("score", greaterThan: .int(40))
            .execute()
            .records
        XCTAssertEqual(results.count, 2)
        try db.close()
    }

    func testQueryOrderByLimitOffset() throws {
        let db = try makeDB("query-order")
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["i": .int(i)]))
        }

        let results = try db.query()
            .orderBy("i", descending: false)
            .limit(3)
            .offset(2)
            .execute()
            .records
        XCTAssertEqual(results.count, 3)
        try db.close()
    }

    func testQueryContains() throws {
        let db = try makeDB("query-contains")
        _ = try db.insert(BlazeDataRecord(["text": .string("hello world")]))
        _ = try db.insert(BlazeDataRecord(["text": .string("goodbye")]))

        let results = try db.query()
            .where("text", contains: "hello")
            .execute()
            .records
        XCTAssertEqual(results.count, 1)
        try db.close()
    }

    func testQueryExplain() throws {
        let db = try makeDB("query-explain")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))

        let plan = try db.query()
            .where("x", equals: .int(1))
            .explain()
        XCTAssertGreaterThanOrEqual(plan.estimatedRecords, 0)
        XCTAssertFalse(plan.description.isEmpty)
        try db.close()
    }

    // MARK: - 5. Transactions

    func testTransactionCommit() throws {
        let db = try makeDB("tx-commit")
        try db.beginTransaction()
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        try db.commitTransaction()
        XCTAssertEqual(try db.count(), 1)
        try db.close()
    }

    func testTransactionRollback() throws {
        let db = try makeDB("tx-rollback")
        _ = try db.insert(BlazeDataRecord(["x": .int(0)]))
        let countBefore = try db.count()

        try db.beginTransaction()
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        try db.rollbackTransaction()

        XCTAssertEqual(try db.count(), countBefore)
        try db.close()
    }

    // MARK: - 6. Persistence & Lifecycle

    func testPersistAndReopen() throws {
        let url = tempDir.appendingPathComponent("persist.blazedb")
        let password = "TestPassword-123!"

        let db1 = try BlazeDBClient(name: "persist", fileURL: url, password: password)
        let id = try db1.insert(BlazeDataRecord(["key": .string("value")]))
        try db1.persist()
        try db1.close()

        let db2 = try BlazeDBClient(name: "persist", fileURL: url, password: password)
        let fetched = try db2.fetch(id: id)
        XCTAssertEqual(fetched?["key"], .string("value"))
        try db2.close()
    }

    func testFlushAlias() throws {
        let db = try makeDB("flush")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        try db.persist()
        try db.close()
    }

    func testCloseIdempotent() throws {
        let db = try makeDB("close-idem")
        try db.close()
        XCTAssertTrue(db.isClosed)
        try db.close()
    }

    func testOperationAfterCloseThrows() throws {
        let db = try makeDB("close-op")
        try db.close()
        XCTAssertThrowsError(try db.insert(BlazeDataRecord(["x": .int(1)])))
    }

    // MARK: - 7. Health & Stats

    func testHealth() throws {
        let db = try makeDB("health")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        let report = try db.health()
        XCTAssertNotNil(report.status)
        XCTAssertFalse(report.summary.isEmpty)
        try db.close()
    }

    func testStats() throws {
        let db = try makeDB("stats")
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["i": .int(i)]))
        }
        let stats = try db.stats()
        XCTAssertEqual(stats.recordCount, 5)
        XCTAssertGreaterThan(stats.databaseSize, 0)

        let pretty = stats.prettyPrint()
        XCTAssertTrue(pretty.contains("Records: 5"))
        try db.close()
    }

    func testHealthAnalyzer() throws {
        let stats = DatabaseStats(
            pageCount: 10,
            walSize: nil,
            lastCheckpoint: nil,
            cacheHitRate: 0.95,
            indexCount: 2,
            recordCount: 100,
            databaseSize: 40960
        )
        let report = HealthAnalyzer.analyze(stats)
        XCTAssertEqual(report.status, .ok)
    }

    // MARK: - 8. Backup & Export

    func testBackup() throws {
        let db = try makeDB("backup-src")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        try db.persist()

        let backupURL = tempDir.appendingPathComponent("backup.blazedb")
        let backupStats = try db.backup(to: backupURL)
        XCTAssertGreaterThan(backupStats.fileSize, 0)

        let restored = try BlazeDBClient(name: "restored", fileURL: backupURL, password: "TestPassword-123!")
        XCTAssertEqual(try restored.count(), 1)
        try restored.close()
        try db.close()
    }

    func testExportDump() throws {
        let db = try makeDB("export")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        try db.persist()

        let dumpURL = tempDir.appendingPathComponent("dump.blazedb")
        try db.export(to: dumpURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dumpURL.path))
        try db.close()
    }

    func testExportAsJSON() throws {
        let db = try makeDB("json-export")
        let id = try db.insert(BlazeDataRecord(["name": .string("test")]))
        let json = try db.exportAsJSON(id: id)
        XCTAssertTrue(json.contains("test"))

        let allJSON = try db.exportAllAsJSON()
        XCTAssertTrue(allJSON.contains("test"))
        try db.close()
    }

    // MARK: - 9. Security Audit

    func testSecurityAudit() throws {
        let db = try makeDB("audit")
        let report = db.performSecurityAudit()
        XCTAssertGreaterThanOrEqual(report.overallScore, 0)
        try db.close()
    }

    // MARK: - 10. MVCC & GC

    func testMVCCToggle() throws {
        let db = try makeDB("mvcc")
        db.setMVCCEnabled(true)
        XCTAssertTrue(db.isMVCCEnabled())
        db.setMVCCEnabled(false)
        XCTAssertFalse(db.isMVCCEnabled())
        try db.close()
    }

    func testGCConfiguration() throws {
        let db = try makeDB("gc")
        var config = MVCCGCConfiguration()
        config.transactionThreshold = 50
        config.versionThreshold = 5.0
        config.timeInterval = 30.0
        db.configureGC(config)
        try db.close()
    }

    // MARK: - 11. Schema & Migration

    func testSchemaVersion() throws {
        let db = try makeDB("schema")
        let version = try db.getSchemaVersion()
        _ = version
        try db.close()
    }

    // MARK: - 12. Error Types

    func testErrorDescriptions() {
        let errors: [BlazeDBError] = [
            .recordNotFound(id: UUID()),
            .recordExists(id: UUID()),
            .transactionFailed("test"),
            .invalidQuery(reason: "bad"),
            .passwordTooWeak(requirements: "8+ chars"),
            .invalidData(reason: "corrupt"),
            .invalidInput(reason: "bad input"),
            .diskFull(availableSpace: 0),
            .databaseLocked(operation: "write"),
            .corruptedData(location: "page", reason: "bad crc"),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "Error \(error) has empty description")
            XCTAssertFalse(error.description.isEmpty, "Error \(error) has empty description")
        }
    }

    // MARK: - 13. BlazeDataRecord API

    func testBlazeDataRecordSubscript() {
        var record = BlazeDataRecord(["a": .int(1)])
        XCTAssertEqual(record["a"], .int(1))
        record["b"] = .string("hello")
        XCTAssertEqual(record["b"], .string("hello"))
    }

    // MARK: - 14. DatabaseStats Codable

    func testDatabaseStatsCodable() throws {
        let stats = DatabaseStats(
            pageCount: 100,
            walSize: 4096,
            lastCheckpoint: Date(),
            cacheHitRate: 0.95,
            indexCount: 3,
            recordCount: 500,
            databaseSize: 1_048_576
        )
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(DatabaseStats.self, from: data)
        XCTAssertEqual(decoded.recordCount, 500)
        XCTAssertEqual(decoded.pageCount, 100)
    }

    // MARK: - 15. Static Methods

    func testClearCachedKey() {
        BlazeDBClient.clearCachedKey()
        BlazeDBClient.clearCachedKey(for: "/nonexistent")
    }

    // MARK: - 16. Async APIs

    func testAsyncInsertAndFetch() async throws {
        let db = try makeDB("async")
        let record = BlazeDataRecord(["name": .string("async-test")])
        let id = try await db.insert(record)
        let fetched = try await db.fetch(id: id)
        XCTAssertEqual(fetched?["name"], .string("async-test"))
        try db.close()
    }

    func testAsyncPersist() async throws {
        let db = try makeDB("async-persist")
        _ = try await db.insert(BlazeDataRecord(["x": .int(1)]))
        try await db.persist()
        try db.close()
    }

    // MARK: - 17. Import (via file copy round-trip)

    func testImportFromBackup() throws {
        let url = tempDir.appendingPathComponent("import-src.blazedb")
        let password = "TestPassword-123!"

        let src = try BlazeDBClient(name: "src", fileURL: url, password: password)
        _ = try src.insert(BlazeDataRecord(["data": .string("imported")]))
        try src.persist()

        // Use the backup API to create a portable copy
        let destURL = tempDir.appendingPathComponent("import-dest.blazedb")
        let backupStats = try src.backup(to: destURL)
        try src.close()

        XCTAssertGreaterThan(backupStats.fileSize, 0)
        let dest = try BlazeDBClient(name: "dest", fileURL: destURL, password: password)
        XCTAssertEqual(try dest.count(), 1)
        try dest.close()
    }

    // MARK: - 18. Monitoring/Observability

    func testExportMonitoringJSON() throws {
        let db = try makeDB("monitoring")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        let jsonData = try db.exportMonitoringJSON()
        XCTAssertGreaterThan(jsonData.count, 0)
        let parsed = try JSONSerialization.jsonObject(with: jsonData)
        XCTAssertNotNil(parsed)
        try db.close()
    }

    // MARK: - 19. Query with closure predicate

    func testQueryWithClosurePredicate() throws {
        let db = try makeDB("query-closure")
        _ = try db.insert(BlazeDataRecord(["score": .int(10)]))
        _ = try db.insert(BlazeDataRecord(["score": .int(90)]))

        let results = try db.query()
            .where { record in
                if case .int(let v) = record["score"] { return v > 50 }
                return false
            }
            .execute()
            .records
        XCTAssertEqual(results.count, 1)
        try db.close()
    }
}
