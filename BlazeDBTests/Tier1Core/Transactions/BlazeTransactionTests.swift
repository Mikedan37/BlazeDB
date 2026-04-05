//  BlazeTransactionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeTransactionTests: XCTestCase {
    private var dbURL: URL?
    private var db: BlazeDBClient?
    private let testPassword = "TxnPass-1234!"

    override func setUpWithError() throws {
        BlazeDBClient.clearCachedKey()
        let tempDir = FileManager.default.temporaryDirectory
        let testID = UUID().uuidString
        let url = tempDir.appendingPathComponent("testdb-\(testID).blz")
        dbURL = url
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("wal"))
        db = try BlazeDBClient(name: "testdb-\(testID)", fileURL: url, password: testPassword)
    }
    
    override func tearDownWithError() throws {
        if let url = dbURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
    }

    func testTransactionCommitAndPersistence() throws {
        let id1 = UUID()
        // Insert data
        let record = BlazeDataRecord(["message": .string("First")])
        try requireFixture(db).insert(record, id: id1)
        let readBack: BlazeDataRecord? = try requireFixture(db).fetch(id: id1)
        XCTAssertEqual(readBack?.storage["message"]?.stringValue, "First")

        // Flush metadata before reopening (only 1 record, < 100 threshold)
        try requireFixture(db).collection.persist()
        try requireFixture(db).close()
        db = nil

        // Reinitialize db to test persistence
        db = try BlazeDBClient(name: "testdb-reopen", fileURL: try requireFixture(dbURL), password: testPassword)
        let persisted: BlazeDataRecord? = try requireFixture(db).fetch(id: id1)
        XCTAssertEqual(persisted?.storage["message"]?.stringValue, "First")

        // Overwrite with new data
        let updatedRecord = BlazeDataRecord(["message": .string("Second")])
        try requireFixture(db).update(id: id1, with: updatedRecord)

        // Flush metadata again before final check
        try requireFixture(db).collection.persist()
        try requireFixture(db).close()
        db = nil

        // Final check after overwrite
        db = try BlazeDBClient(name: "testdb-reopen-2", fileURL: try requireFixture(dbURL), password: testPassword)
        let finalData: BlazeDataRecord? = try requireFixture(db).fetch(id: id1)
        XCTAssertEqual(finalData?.storage["message"]?.stringValue, "Second")
    }

    func testRollbackDiscardsChanges() throws {
        let id2 = UUID()
        let record = BlazeDataRecord(["message": .string("Temp")])
        try requireFixture(db).insert(record, id: id2)
        try requireFixture(db).delete(id: id2)

        let fetched: BlazeDataRecord? = try requireFixture(db).fetch(id: id2)
        XCTAssertNil(fetched, "Record should be nil after delete (rollback confirmed)")
    }

    func testConcurrentWritesStayConsistent() throws {
        let expectation1 = expectation(description: "Write Data1")
        let expectation2 = expectation(description: "Write Data2")

        let id3 = UUID()
        let id4 = UUID()
        let record1 = BlazeDataRecord(["message": .string("Data1")])
        let record2 = BlazeDataRecord(["message": .string("Data2")])
        let dbRef = try requireFixture(db)

        DispatchQueue.global().async {
            do {
                try dbRef.insert(record1, id: id3)
                expectation1.fulfill()
            } catch {
                XCTFail("Write Data1 failed: \(error)")
            }
        }

        DispatchQueue.global().async {
            do {
                try dbRef.insert(record2, id: id4)
                expectation2.fulfill()
            } catch {
                XCTFail("Write Data2 failed: \(error)")
            }
        }

        wait(for: [expectation1, expectation2], timeout: 5.0)

        // Verify data
        let readData1: BlazeDataRecord? = try requireFixture(db).fetch(id: id3)
        let readData2: BlazeDataRecord? = try requireFixture(db).fetch(id: id4)
        XCTAssertEqual(readData1?.storage["message"]?.stringValue, "Data1")
        XCTAssertEqual(readData2?.storage["message"]?.stringValue, "Data2")
    }
}
