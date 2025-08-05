//  DynamicCollectionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.
import XCTest
@testable import BlazeDB

final class DynamicCollectionTests: XCTestCase {
    func testSecondaryIndexFetch() throws {
        // Setup: Create in-memory store (or temp file if you must)
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try PageStore(fileURL: tmpURL)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject")

        // 1. Create secondary index on "status"
        try collection.createIndex(on: "status")

        // 2. Insert 100 records, alternating "done", "inProgress", "notStarted"
        let statuses = ["done", "inProgress", "notStarted"]
        let recordCount = 100
        var insertedIDs: [UUID] = []
        for i in 0..<recordCount {
            let status = statuses[i % statuses.count]
            let rec = BlazeDataRecord([
                "title": .string("Item \(i)"),
                "status": .string(status)
            ])
            let id = try collection.insert(rec)
            insertedIDs.append(id)
        }

        // 3. Fetch all "inProgress"
        let inProgress = try collection.fetch(byIndexedField: "status", value: "inProgress")
        XCTAssertEqual(inProgress.count, recordCount / statuses.count)
        XCTAssertTrue(inProgress.allSatisfy { $0.storage["status"]?.stringValue == "inProgress" })

        // 4. Fetch all "done"
        let done = try collection.fetch(byIndexedField: "status", value: "done")
        let expectedDone = (0..<recordCount).filter { statuses[$0 % statuses.count] == "done" }.count
        XCTAssertEqual(done.count, expectedDone)
        XCTAssertTrue(done.allSatisfy { $0.storage["status"]?.stringValue == "done" })

        // 5. Fetch for a status with no records
        let unknown = try collection.fetch(byIndexedField: "status", value: "missing")
        XCTAssertEqual(unknown.count, 0)

        // Clean up
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
    
    func testCompoundIndexFetch() throws {
        // 1. Setup temp store & collection
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try PageStore(fileURL: tmpURL)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject")

        // 2. Create compound index on "status" + "priority"
        try collection.createIndex(on: ["status", "priority"])

        // 3. Insert 100 records with various combinations of status/priority
        let statuses = ["done", "inProgress", "notStarted"]
        let priorities = ["low", "medium", "high"]
        let recordCount = 100
        for i in 0..<recordCount {
            let status = statuses[i % statuses.count]
            let priority = priorities[i % priorities.count]
            let rec = BlazeDataRecord([
                "title": .string("Task \(i)"),
                "status": .string(status),
                "priority": .string(priority)
            ])
            _ = try collection.insert(rec)
        }

        // 4. Fetch all "inProgress" + "high" records
        let results = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", "high"])
        XCTAssertTrue(results.allSatisfy { rec in
            rec.storage["status"]?.stringValue == "inProgress" &&
            rec.storage["priority"]?.stringValue == "high"
        })
        // There should be about 11-12 such records (every 3*3=9 cycles)
        XCTAssertGreaterThan(results.count, 0)
        print("Fetched \(results.count) inProgress+high tasks")

        // 5. Benchmark speed (optional, just for log)
        measure {
            _ = try? collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", "low"])
        }
    }
    
    func testIndexUpdateOnFieldChange() throws {
        // Setup collection
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try PageStore(fileURL: tmpURL)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject")

        // Create compound index on ["status", "priority"]
        try collection.createIndex(on: ["status", "priority"])

        // Insert record
        var record = BlazeDataRecord([
            "title": .string("Test"),
            "status": .string("inProgress"),
            "priority": .int(1)
        ])
        let id = try collection.insert(record)

        // Confirm index lookup
        let found1 = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", 1])
        XCTAssertTrue(found1.contains { $0.storage["title"]?.stringValue == "Test" })

        // Update the record's status (should update index)
        record.storage["status"] = .string("done")
        try collection.update(id: id, with: record)

        // Should not find by old key
        let foundOld = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["inProgress", 1])
        XCTAssertTrue(foundOld.isEmpty)

        // Should find by new key
        let found2 = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        XCTAssertTrue(found2.contains { $0.storage["title"]?.stringValue == "Test" })

        // Delete record, should be gone from all indexes
        try collection.delete(id: id)
        let foundAfterDelete = try collection.fetch(byIndexedFields: ["status", "priority"], values: ["done", 1])
        XCTAssertTrue(foundAfterDelete.isEmpty)
    }
}

    func testMultiFieldIndexQueryPerformance() throws {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".db")
        let metaURL = tmpURL.deletingPathExtension().appendingPathExtension("meta")
        let store = try PageStore(fileURL: tmpURL)
        let collection = try DynamicCollection(store: store, metaURL: metaURL, project: "TestProject")

        try collection.createIndex(on: ["type", "severity"])

        let types = ["bug", "feature", "task"]
        let severities = [1, 2, 3]
        for i in 0..<300 {
            let type = types[i % types.count]
            let severity = severities[i % severities.count]
            let rec = BlazeDataRecord([
                "title": .string("Entry \(i)"),
                "type": .string(type),
                "severity": .int(severity)
            ])
            _ = try collection.insert(rec)
        }

        let matches = try collection.fetch(byIndexedFields: ["type", "severity"], values: ["bug", 2])
        XCTAssertTrue(matches.allSatisfy {
            $0.storage["type"]?.stringValue == "bug" &&
            $0.storage["severity"]?.intValue == 2
        })
        XCTAssertGreaterThan(matches.count, 0)

        measure {
            _ = try? collection.fetch(byIndexedFields: ["type", "severity"], values: ["bug", 2])
        }

        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
