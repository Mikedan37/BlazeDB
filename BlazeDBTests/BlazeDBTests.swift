//  BlazeDBTests.swift
//  BlazeDBTests
//  Created by Michael Danylchuk on 6/15/25.
import XCTest

@testable import BlazeDB

final class BlazeDBClientTests: XCTestCase {
    var tempURL: URL!
    var store: PageStore!
    var client: BlazeDBClient!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blz")
        _ = try KeyManager.getKey(from: .password("test-password"))
        store = try PageStore(fileURL: tempURL)
        client = try BlazeDBClient(fileURL: tempURL, password: "test-password")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }

    func testInsertAndFetchDynamicRecord() throws {
        let idString = UUID().uuidString
        let id = try client.insert(BlazeDataRecord([
            "id": BlazeDocumentField.string(idString),
            "type": BlazeDocumentField.string("note"),
            "content": BlazeDocumentField.string("Hello, Blaze!"),
            "author": BlazeDocumentField.string("Michael")
        ]))
        let record = try client.fetch(id: id)
        XCTAssertEqual(record?.storage["content"]?.value as? String, "Hello, Blaze!")
    }

    func testSoftDeleteAndPurge() throws {
        let id = UUID().uuidString
        let record = BlazeDataRecord([
            "id": .string(id),
            "type": .string("note"),
            "content": .string("To be deleted")
        ])
        let insertedID = try client.insert(record)
        print("Inserted ID:", insertedID)
        assert(insertedID.uuidString == id) // 💥 Now it’s valid Swift // 🧨 if this fails, we already found the issue
        
        try client.softDelete(id: insertedID)
        try client.purge()
        
        let result = try client.fetch(id: insertedID)
        XCTAssertNil(result, "Expected fetch to return nil after purge")
    }

    func testRawDump() throws {
        let idString = UUID().uuidString
        let id = try client.insert(BlazeDataRecord([
            "id": BlazeDocumentField.string(idString),
            "type": BlazeDocumentField.string("blob"),
            "data": BlazeDocumentField.string("xyz")
        ]))
        let dump = try client.rawDump()
        XCTAssertFalse(dump.isEmpty)
        XCTAssertTrue(dump.values.contains { !$0.isEmpty })
    }
    
    func testSecondaryIndexPersistsAfterRestart() throws {
        let dbURL = tempDBURL()
        let store = try PageStore(fileURL: dbURL)
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")

        var collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test")
        try collection.createIndex(on: ["status"])
        
        let record = BlazeDataRecord(["title": .string("Issue"), "status": .string("open")])
        try collection.insert(record)

        // simulate restart
        let collectionReloaded = try DynamicCollection(store: store, metaURL: metaURL, project: "Test")
        let results = collectionReloaded.query("status", equals: "open")
        XCTAssertEqual(results.count, 1)
    }
    
    func testCompoundIndexPersists() throws {
        let dbURL = tempDBURL()
        let store = try PageStore(fileURL: dbURL)
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")

        var collection = try DynamicCollection(store: store, metaURL: metaURL, project: "Test")
        try collection.createIndex(on: ["status", "priority"])
        
        let record = BlazeDataRecord([
            "title": .string("Fix me"),
            "status": .string("open"),
            "priority": .string("high")
        ])
        try collection.insert(record)

        let reloaded = try DynamicCollection(store: store, metaURL: metaURL, project: "Test")
        let results = reloaded.query(["status", "priority"], equals: ["open", "high"])
        XCTAssertEqual(results.count, 1)
    }
    
    private func tempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(UUID().uuidString + ".blaze")
    }
}
