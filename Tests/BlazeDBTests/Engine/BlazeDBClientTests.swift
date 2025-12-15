//  BlazeDBTests.swift
//  BlazeDBTests
//  Created by Michael Danylchuk on 6/15/25.
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

final class BlazeDBClientTests: XCTestCase {
    var tempURL: URL!
    var store: BlazeDB.PageStore!
    var client: BlazeDBClient!
    var key: SymmetricKey!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blz")
        key = try KeyManager.getKey(from: .password("BlazeDBClientTest123!"))
        store = try BlazeDB.PageStore(fileURL: tempURL, key: key)
        client = try BlazeDBClient(name: "test-name", fileURL: tempURL, password: "BlazeDBClientTest123!")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }

    func testInsertAndFetchDynamicRecord() throws {
        let idString = UUID().uuidString
        let id = try client.insert(BlazeDataRecord([
            "id": .string(idString),
            "type": .string("note"),
            "content": .string("Hello, Blaze!"),
            "author": .string("Michael")
        ]))
        let record = try client.fetch(id: id)
        XCTAssertEqual(record?.storage["content"], .some(.string("Hello, Blaze!")))
    }
    
    // MARK: - Performance Tests
    
    /// Measure insert performance for single records
    func testPerformance_SingleInsert() throws {
        measure {
            do {
                _ = try client.insert(BlazeDataRecord([
                    "type": .string("note"),
                    "content": .string("Performance test"),
                    "timestamp": .date(Date())
                ]))
            } catch {
                XCTFail("Insert failed: \(error)")
            }
        }
    }
    
    /// Measure fetch performance by ID
    func testPerformance_FetchByID() throws {
        // Setup: Insert test record
        let id = try client.insert(BlazeDataRecord([
            "content": .string("Test data")
        ]))
        
        measure {
            do {
                _ = try client.fetch(id: id)
            } catch {
                XCTFail("Fetch failed: \(error)")
            }
        }
    }
    
    /// Measure update performance
    func testPerformance_Update() throws {
        // Setup: Insert test record
        let id = try client.insert(BlazeDataRecord([
            "content": .string("Original")
        ]))
        
        measure {
            do {
                try client.update(id: id, with: BlazeDataRecord([
                    "content": .string("Updated")
                ]))
            } catch {
                XCTFail("Update failed: \(error)")
            }
        }
    }
    
    /// Measure delete performance
    func testPerformance_Delete() throws {
        measure {
            do {
                // Insert and delete in one measure block
                let id = try client.insert(BlazeDataRecord([
                    "content": .string("To delete")
                ]))
                try client.delete(id: id)
            } catch {
                XCTFail("Delete failed: \(error)")
            }
        }
    }
    
    /// Measure batch insert performance (100 records)
    func testPerformance_BatchInsert100() throws {
        measure {
            do {
                let records = (0..<100).map { i in
                    BlazeDataRecord([
                        "index": .int(i),
                        "data": .string("Record \(i)")
                    ])
                }
                _ = try client.insertMany(records)
            } catch {
                XCTFail("Batch insert failed: \(error)")
            }
        }
    }
    
    /// Measure fetchAll performance with 100 records
    func testPerformance_FetchAll100() throws {
        // Setup: Insert 100 records
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
        }
        _ = try client.insertMany(records)
        
        measure {
            do {
                _ = try client.fetchAll()
            } catch {
                XCTFail("FetchAll failed: \(error)")
            }
        }
    }

    func testSoftDeleteAndPurge() throws {
        let id = UUID()
        let record = BlazeDataRecord([
            "id": .uuid(id),   // ✅ pass as UUID not string
            "type": .string("note"),
            "content": .string("To be deleted")
        ])
        let insertedID = try client.insert(record)
        XCTAssertEqual(insertedID, id)

        try client.softDelete(id: insertedID)
        try client.purge()

        let result = try client.fetch(id: insertedID)
        XCTAssertNil(result, "Expected fetch to return nil after purge")
    }

    func testRawDump() throws {
        let idString = UUID().uuidString
        _ = try client.insert(BlazeDataRecord([
            "id": .string(idString),
            "type": .string("blob"),
            "data": .string("xyz")
        ]))
        let dump = try client.rawDump()
        XCTAssertFalse(dump.isEmpty)
        XCTAssertTrue(dump.values.contains { !$0.isEmpty })
    }

    func testSecondaryIndexPersistsAfterRestart() throws {
        let dbURL = tempDBURL()
        let store = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")

        var collection = try DynamicCollection(
            store: store,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )

        try collection.createIndex(on: ["status"])

        let record = BlazeDataRecord([
            "title": .string("Issue"),
            "status": .string("open")
        ])
        _ = try collection.insert(record)
        
        // Flush metadata before restart (only 1 record, < 100 threshold)
        try collection.persist()

        // simulate restart
        let reopenedStore = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let collectionReloaded = try DynamicCollection(
            store: reopenedStore,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )

        // Use indexed fetch instead of a fake query sugar
        let results = try collectionReloaded.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.storage["status"], .some(.string("open")))
    }

    func testCompoundIndexPersists() throws {
        let dbURL = tempDBURL()
        let store = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")

        var collection = try DynamicCollection(
            store: store,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )
        try collection.createIndex(on: ["status", "priority"])
        try collection.createIndex(on: ["status"])

        let record = BlazeDataRecord([
            "title": .string("Fix me"),
            "status": .string("open"),
            "priority": .string("high")
        ])
        _ = try collection.insert(record)
        
        // Flush metadata before restart (only 1 record, < 100 threshold)
        try collection.persist()

        let reopenedStore = try BlazeDB.PageStore(fileURL: dbURL, key: key)
        let reloaded = try DynamicCollection(
            store: reopenedStore,
            metaURL: metaURL,
            project: "Test",
            encryptionKey: key
        )

        // Fetch by single field "status" and filter manually by "priority"
        let statusOpen = try reloaded.fetch(byIndexedField: "status", value: "open")
        let results = statusOpen.filter { $0.storage["priority"] == .some(.string("high")) }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.storage["status"], .some(.string("open")))
        XCTAssertEqual(results.first?.storage["priority"], .some(.string("high")))
    }

    func testCheckIntegrityReturnValues() throws {
        let dbURL = tempDBURL()
        let db = try BlazeDBClient(name: "IntegrityTest", fileURL: dbURL, password: "BlazeDBClientTest123!")
        
        _ = try db.insert(BlazeDataRecord(["valid": .string("data")]))
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let report = db.checkDatabaseIntegrity()
        
        XCTAssertTrue(report.ok, "Integrity check should pass for valid database")
        XCTAssertTrue(report.issues.isEmpty, "Should have no issues for valid database")
        
        try? FileManager.default.removeItem(at: dbURL)
    }
    
    private func tempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(UUID().uuidString + ".blaze")
    }
}

