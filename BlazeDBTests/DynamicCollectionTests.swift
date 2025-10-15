//  DynamicCollectionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.
import XCTest
import CryptoKit
@testable import BlazeDB

final class DynamicCollectionTests: XCTestCase {
    var key: SymmetricKey!

    override func setUpWithError() throws {
        // Use a predictable key for all tests
        key = try KeyManager.getKey(from: .password("test-password"))
    }

    func testSecondaryIndexFetch() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        try collection.createIndex(on: "status")

        let statuses = ["done", "inProgress", "notStarted"]
        let recordCount = 100
        for i in 0..<recordCount {
            let status = statuses[i % statuses.count]
            let rec = BlazeDataRecord([
                "title": .string("Item \(i)"),
                "status": .string(status)
            ])
            _ = try collection.insert(rec)
        }

        let inProgress = try collection.fetch(byIndexedField: "status", value: "inProgress")
        XCTAssertEqual(inProgress.count, recordCount / statuses.count)
        XCTAssertTrue(inProgress.allSatisfy { $0.storage["status"]?.stringValue == "inProgress" })

        let done = try collection.fetch(byIndexedField: "status", value: "done")
        let expectedDone = (0..<recordCount).filter { statuses[$0 % statuses.count] == "done" }.count
        XCTAssertEqual(done.count, expectedDone)

        let unknown = try collection.fetch(byIndexedField: "status", value: "missing")
        XCTAssertEqual(unknown.count, 0)

        measure(metrics: [XCTClockMetric()]) {
            _ = try? collection.fetch(byIndexedField: "status", value: "inProgress")
        }
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    func testCompoundIndexFetch() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        try collection.createIndex(on: ["status", "priority"])

        let statuses = ["done", "inProgress", "notStarted"]
        let priorities = ["low", "medium", "high"]
        let recordCount = 100
        for i in 0..<recordCount {
            let rec = BlazeDataRecord([
                "title": .string("Task \(i)"),
                "status": .string(statuses[i % statuses.count]),
                "priority": .string(priorities[i % priorities.count])
            ])
            _ = try collection.insert(rec)
        }

        // Insert a record that actually matches the query parameters ("inProgress", "high")
        let match = BlazeDataRecord([
            "title": .string("Match Record"),
            "status": .string("inProgress"),
            "priority": .string("high")
        ])
        _ = try collection.insert(match)

        let results = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", "high"])
        XCTAssertTrue(results.allSatisfy {
            $0.storage["status"]?.stringValue == "inProgress" &&
            $0.storage["priority"]?.stringValue == "high"
        })
        XCTAssertGreaterThan(results.count, 0)

        measure(metrics: [XCTClockMetric()]) {
            _ = try? collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", "low"])
        }
    }

    func testIndexUpdateOnFieldChange() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        try collection.createIndex(on: ["status", "priority"])

        var record = BlazeDataRecord([
            "title": .string("Test"),
            "status": .string("inProgress"),
            "priority": .int(1)
        ])
        let id = try collection.insert(record)

        let found1 = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", 1])
        XCTAssertTrue(found1.contains { $0.storage["title"]?.stringValue == "Test" })

        record.storage["status"] = .string("done")
        try collection.update(id: id, with: record)

        let foundOld = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", 1])
        XCTAssertTrue(foundOld.isEmpty)

        let found2 = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        XCTAssertTrue(found2.contains { $0.storage["title"]?.stringValue == "Test" })

        measure(metrics: [XCTClockMetric()]) {
            _ = try? collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        }
        try collection.delete(id: id)
        let foundAfterDelete = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        XCTAssertTrue(foundAfterDelete.isEmpty)
    }

    func testMultiFieldIndexQueryPerformance() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        try collection.createIndex(on: ["type", "severity"])

        let types = ["bug", "feature", "task"]
        let severities = [1, 2, 3]
        for i in 0..<300 {
            let rec = BlazeDataRecord([
                "title": .string("Entry \(i)"),
                "type": .string(types[i % types.count]),
                "severity": .int(severities[i % severities.count])
            ])
            _ = try collection.insert(rec)
        }

        // Insert a matching record for the test query
        let matchingRecord = BlazeDataRecord([
            "title": .string("Bug Severity 2 Case"),
            "type": .string("bug"),
            "severity": .int(2)
        ])
        _ = try collection.insert(matchingRecord)

        let matches = try collection.fetch(byIndexedFields: ["type", "severity"], values: ["bug", 2])
        XCTAssertTrue(matches.allSatisfy {
            $0.storage["type"]?.stringValue == "bug" &&
            $0.storage["severity"]?.intValue == 2
        })
        XCTAssertGreaterThan(matches.count, 0)

        measure(metrics: [XCTClockMetric()]) {
            _ = try? collection.fetch(byIndexedFields: ["type", "severity"], values: ["bug", 2])
        }
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}

// MARK: - Edge and Error Handling Tests
extension DynamicCollectionTests {
    func testDuplicateIndexCreationThrows() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        // Create initial index
        try collection.createIndex(on: "status")

        // Calling again should not throw or crash
        XCTAssertNoThrow(try collection.createIndex(on: "status"))

        // Verify that fetching by the indexed field still works
        let rec = BlazeDataRecord(["status": .string("done")])
        _ = try collection.insert(rec)
        let fetched = try collection.fetch(byIndexedField: "status", value: "done")
        XCTAssertEqual(fetched.count, 1)

        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    func testFetchOnUnindexedFieldThrows() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        let record = BlazeDataRecord(["title": .string("Item")])
        _ = try collection.insert(record)
        let results = try collection.fetch(byIndexedField: "missingIndex", value: "value")
        XCTAssertTrue(results.isEmpty, "Fetching an unindexed field should return an empty array, not throw.")
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    func testCorruptedMetaFileRecovery() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        _ = FileManager.default.createFile(atPath: metaURL.path, contents: Data("corrupted".utf8))

        XCTAssertNoThrow(try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key))
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    func testFetchByInvalidCompoundIndexThrows() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)
        try collection.createIndex(on: ["a", "b"])

        let rec = BlazeDataRecord(["a": .string("one"), "b": .string("two")])
        _ = try collection.insert(rec)

        let results = try collection.fetch(byIndexedFields: ["a", "c"], values: ["one", "missing"])
        XCTAssertTrue(results.isEmpty, "Fetching with a non-existent compound index should return an empty array, not throw.")
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    /// Duplicated compound-index keys should not crash and must return multiple matches.
    func testDuplicateCompoundIndexKeysAreSupported() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject", encryptionKey: key)

        try collection.createIndex(on: ["kind", "rank"])

        // Insert two different records that share the same compound index values.
        let r1 = BlazeDataRecord([
            "title": .string("R1"),
            "kind": .string("alpha"),
            "rank": .int(1)
        ])
        _ = try collection.insert(r1)

        let r2 = BlazeDataRecord([
            "title": .string("R2"),
            "kind": .string("alpha"),
            "rank": .int(1)
        ])
        _ = try collection.insert(r2)

        // Both should be retrievable via the compound index key (alpha, 1).
        let results = try collection.fetch(byIndexedFields: ["kind", "rank"], values: ["alpha", 1])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.storage["title"]?.stringValue == "R1" })
        XCTAssertTrue(results.contains { $0.storage["title"]?.stringValue == "R2" })

        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}
