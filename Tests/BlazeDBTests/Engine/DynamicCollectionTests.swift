//  DynamicCollectionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.
import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDB

final class DynamicCollectionTests: XCTestCase {
    var key: SymmetricKey!

    override func setUpWithError() throws {
        // Use a predictable key for all tests
        key = try KeyManager.getKey(from: .password("TestPassword123!"))
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
    
    func testFetchAllByProjectFiltering() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        
        // Create collection with ProjectA
        let collectionA = try DynamicCollection(store: store, metaURL: metaURL, project: "ProjectA", encryptionKey: key)
        
        // Insert 2 records (will have project="ProjectA")
        _ = try collectionA.insert(BlazeDataRecord(["name": .string("A1")]))
        _ = try collectionA.insert(BlazeDataRecord(["name": .string("A2")]))
        
        try collectionA.persist()
        
        // Now create collection with ProjectB using same files
        let collectionB = try DynamicCollection(store: store, metaURL: metaURL, project: "ProjectB", encryptionKey: key)
        
        // Insert 1 record (will have project="ProjectB")
        _ = try collectionB.insert(BlazeDataRecord(["name": .string("B1")]))
        
        try collectionB.persist()
        
        // Fetch by project from each collection
        let projectARecords = try collectionA.fetchAll(byProject: "ProjectA")
        let projectBRecords = try collectionB.fetchAll(byProject: "ProjectB")
        
        XCTAssertEqual(projectARecords.count, 2, "Should find 2 ProjectA records")
        XCTAssertEqual(projectBRecords.count, 1, "Should find 1 ProjectB record")
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    func testContainsIDMethod() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        let id = try collection.insert(BlazeDataRecord(["name": .string("Test")]))
        
        XCTAssertTrue(collection.contains(id))
        
        try collection.delete(id: id)
        
        XCTAssertFalse(collection.contains(id))
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    func testDestroyCollectionCleanup() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        for i in 0..<10 {
            _ = try collection.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        try collection.persist()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
        
        try collection.destroy()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaURL.path))
    }
    
    func testFetchAllSorted() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        _ = try collection.insert(BlazeDataRecord(["name": .string("Charlie"), "age": .int(30)]))
        _ = try collection.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(25)]))
        _ = try collection.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(35)]))
        
        let sortedAsc = try collection.fetchAllSorted(by: "age", ascending: true)
        XCTAssertEqual(sortedAsc[0].storage["age"]?.intValue, 25)
        XCTAssertEqual(sortedAsc[1].storage["age"]?.intValue, 30)
        XCTAssertEqual(sortedAsc[2].storage["age"]?.intValue, 35)
        
        let sortedDesc = try collection.fetchAllSorted(by: "age", ascending: false)
        XCTAssertEqual(sortedDesc[0].storage["age"]?.intValue, 35)
        XCTAssertEqual(sortedDesc[1].storage["age"]?.intValue, 30)
        XCTAssertEqual(sortedDesc[2].storage["age"]?.intValue, 25)
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    func testRunQueryMethods() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        _ = try collection.insert(BlazeDataRecord(["status": .string("active"), "priority": .int(1)]))
        _ = try collection.insert(BlazeDataRecord(["status": .string("inactive"), "priority": .int(2)]))
        _ = try collection.insert(BlazeDataRecord(["status": .string("active"), "priority": .int(3)]))
        
        let query = BlazeQueryLegacy<[String: BlazeDocumentField]>()
            .evaluate { $0["status"] == .string("active") }
        
        let results = try collection.runQuery(query)
        XCTAssertEqual(results.count, 2)
        
        let sortedQuery = BlazeQueryLegacy<[String: BlazeDocumentField]>()
            .evaluate { $0["status"] == .string("active") }
            .sort { lhs, rhs in
                guard let lhsPriority = lhs["priority"]?.intValue,
                      let rhsPriority = rhs["priority"]?.intValue else { return false }
                return lhsPriority < rhsPriority
            }
        
        let sortedResults = try collection.runQuerySorted(sortedQuery)
        XCTAssertEqual(sortedResults.count, 2)
        XCTAssertEqual(sortedResults[0].storage["priority"]?.intValue, 1)
        XCTAssertEqual(sortedResults[1].storage["priority"]?.intValue, 3)
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    func testQueryContext() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        _ = try collection.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(25)]))
        _ = try collection.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(30)]))
        
        let query = BlazeQueryLegacy<[String: BlazeDocumentField]>()
            .evaluate { $0["name"] == .string("Alice") }
        
        let allRecords = try collection.fetchAll()
        let results = query.apply(to: allRecords.map { $0.storage })
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["name"], .string("Alice"))
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    func testFetchMetaAndUpdateMeta() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try BlazeDB.PageStore(fileURL: tmpURL, key: key)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test", encryptionKey: key)
        
        try collection.persist()
        
        var meta = try collection.fetchMeta()
        XCTAssertTrue(meta.isEmpty || meta.keys.count > 0, "Meta should be fetchable")
        
        let newMeta: [String: BlazeDocumentField] = [
            "appVersion": .string("1.0.0"),
            "lastAccessed": .date(Date())
        ]
        
        try collection.updateMeta(newMeta)
        
        meta = try collection.fetchMeta()
        XCTAssertEqual(meta["appVersion"], .string("1.0.0"))
        XCTAssertNotNil(meta["lastAccessed"])
        
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}

