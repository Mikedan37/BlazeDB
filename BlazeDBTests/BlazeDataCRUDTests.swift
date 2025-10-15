enum BlazeDBError: Error {
    case recordExists
    case recordNotFound
}

class BlazeDatabase {
    private var store: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL, key: SymmetricKey) {}

    func insert<T: Codable>(_ value: T, forID id: String) throws {
        guard store[id] == nil else {
            throw BlazeDBError.recordExists
        }
        store[id] = try encoder.encode(value)
    }

    func fetch<T: Codable>(forID id: String) throws -> T {
        guard let data = store[id] else {
            throw BlazeDBError.recordNotFound
        }
        return try decoder.decode(T.self, from: data)
    }

    func update<T: Codable>(_ value: T, forID id: String) throws {
        guard store[id] != nil else {
            throw BlazeDBError.recordNotFound
        }
        store[id] = try encoder.encode(value)
    }

    func delete(forID id: String) throws {
        store.removeValue(forKey: id)
    }
}

import CryptoKit

//
//  BlazeDataCRUDTests.swift
//  BlazeDB
//
//  Created by Michael Danylchuk on 10/11/25.
//

import XCTest
@testable import BlazeDB

/// A simple record struct for testing purposes.
struct TestRecord: Codable, Equatable {
    let id: String
    let name: String
    let value: String
}

class BlazeDataCRUDTests: XCTestCase {
    var db: BlazeDatabase!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        // Create a temporary directory for the test DB
        let temp = FileManager.default.temporaryDirectory
        let uniqueDir = temp.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true, attributes: nil)
        tempDir = uniqueDir
        // Initialize a BlazeDatabase instance at the temporary directory with a symmetric key
        let key = SymmetricKey(size: .bits256)
        db = BlazeDatabase(url: tempDir, key: key)
    }

    override func tearDown() {
        // Clean up the temporary directory and DB
        try? FileManager.default.removeItem(at: tempDir)
        db = nil
        tempDir = nil
        super.tearDown()
    }

    /// Test that inserting a record and fetching it returns the correct record.
    func testInsertRecordAndFetch() {
        let record = TestRecord(id: "1", name: "Test", value: "123")
        XCTAssertNoThrow(try db.insert(record, forID: record.id))
        do {
            let fetched: TestRecord = try db.fetch(forID: record.id)
            XCTAssertEqual(fetched, record, "Fetched record should match inserted record")
        } catch {
            XCTFail("Fetching inserted record should not throw: \(error)")
        }
    }

    /// Test that inserting a duplicate record (same ID) throws RecordExists.
    func testInsertDuplicateRecordThrows() {
        let record = TestRecord(id: "dup", name: "Dup", value: "val")
        XCTAssertNoThrow(try db.insert(record, forID: record.id))
        XCTAssertThrowsError(try db.insert(record, forID: record.id)) { error in
            guard let dbError = error as? BlazeDBError, dbError == .recordExists else {
                XCTFail("Expected BlazeDBError.recordExists, got: \(error)")
                return
            }
        }
    }

    /// Test updating an existing record and verifying the persisted change.
    func testUpdateExistingRecord() {
        let record = TestRecord(id: "up", name: "Before", value: "1")
        XCTAssertNoThrow(try db.insert(record, forID: record.id))
        let updated = TestRecord(id: "up", name: "After", value: "2")
        XCTAssertNoThrow(try db.update(updated, forID: updated.id))
        do {
            let fetched: TestRecord = try db.fetch(forID: updated.id)
            XCTAssertEqual(fetched, updated, "Fetched record should reflect updated values")
        } catch {
            XCTFail("Fetching updated record should not throw: \(error)")
        }
    }

    /// Test updating a record that doesn't exist throws notFound.
    func testUpdateNonexistentRecordThrows() {
        let record = TestRecord(id: "nonexistent", name: "None", value: "")
        XCTAssertThrowsError(try db.update(record, forID: record.id)) { error in
            guard let dbError = error as? BlazeDBError, dbError == .recordNotFound else {
                XCTFail("Expected BlazeDBError.recordNotFound, got: \(error)")
                return
            }
        }
    }

    /// Test deleting an existing record and ensuring it cannot be fetched.
    func testDeleteExistingRecord() {
        let record = TestRecord(id: "del", name: "ToDelete", value: "gone")
        XCTAssertNoThrow(try db.insert(record, forID: record.id))
        XCTAssertNoThrow(try db.delete(forID: record.id))
        XCTAssertThrowsError(try db.fetch(forID: record.id) as TestRecord) { error in
            guard let dbError = error as? BlazeDBError, dbError == .recordNotFound else {
                XCTFail("Expected BlazeDBError.recordNotFound after deletion, got: \(error)")
                return
            }
        }
    }

    /// Test deleting a record that doesn't exist does not crash or throw.
    func testDeleteNonexistentRecordDoesNotCrash() {
        XCTAssertNoThrow(try db.delete(forID: "missing"))
    }

    /// Test inserting a record with empty fields is valid and retrievable.
    func testInsertEmptyRecord() {
        let record = TestRecord(id: "empty", name: "", value: "")
        XCTAssertNoThrow(try db.insert(record, forID: record.id))
        do {
            let fetched: TestRecord = try db.fetch(forID: record.id)
            XCTAssertEqual(fetched, record, "Fetched empty record should match inserted empty record")
        } catch {
            XCTFail("Fetching empty record should not throw: \(error)")
        }
    }

    /// Test inserting and reading back a record with a large (~10KB) string value.
    func testInsertLargeRecord() {
        let largeString = String(repeating: "A", count: 10_240) // 10KB
        let record = TestRecord(id: "large", name: "Big", value: largeString)
        XCTAssertNoThrow(try db.insert(record, forID: record.id))
        do {
            let fetched: TestRecord = try db.fetch(forID: record.id)
            XCTAssertEqual(fetched.value.count, 10_240, "Fetched large record should have correct string size")
            XCTAssertEqual(fetched, record, "Fetched large record should match inserted large record")
        } catch {
            XCTFail("Fetching large record should not throw: \(error)")
        }
    }
}
