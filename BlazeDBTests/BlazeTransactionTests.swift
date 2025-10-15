//  BlazeTransactionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.

import XCTest
@testable import BlazeDB

final class BlazeTransactionTests: XCTestCase {
    var dbURL: URL!
    var db: BlazeDBClient!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        dbURL = tempDir.appendingPathComponent("testdb.blz")
        try? FileManager.default.removeItem(at: dbURL)
        db = try BlazeDBClient(name: "testdb", fileURL: dbURL, password: "txnpassword")
    }

    func testTransactionCommitAndPersistence() throws {
        let id1 = UUID()
        // Insert data
        let record = BlazeDataRecord(["message": .string("First")])
        try db.insert(record, id: id1)
        let readBack: BlazeDataRecord? = try db.fetch(id: id1)
        XCTAssertEqual(readBack?.storage["message"]?.stringValue, "First")

        // Reinitialize db to test persistence
        db = try BlazeDBClient(name: "testdb", fileURL: dbURL, password: "txnpassword")
        let persisted: BlazeDataRecord? = try db.fetch(id: id1)
        XCTAssertEqual(persisted?.storage["message"]?.stringValue, "First")

        // Overwrite with new data
        let updatedRecord = BlazeDataRecord(["message": .string("Second")])
        try db.update(id: id1, with: updatedRecord)

        // Final check after overwrite
        db = try BlazeDBClient(name: "testdb", fileURL: dbURL, password: "txnpassword")
        let finalData: BlazeDataRecord? = try db.fetch(id: id1)
        XCTAssertEqual(finalData?.storage["message"]?.stringValue, "Second")
    }

    func testRollbackDiscardsChanges() throws {
        let id2 = UUID()
        let record = BlazeDataRecord(["message": .string("Temp")])
        try db.insert(record, id: id2)
        try db.delete(id: id2)

        let fetched: BlazeDataRecord? = try db.fetch(id: id2)
        XCTAssertNil(fetched, "Record should be nil after delete (rollback confirmed)")
    }

    func testConcurrentWritesStayConsistent() throws {
        let expectation1 = expectation(description: "Write Data1")
        let expectation2 = expectation(description: "Write Data2")

        let id3 = UUID()
        let id4 = UUID()
        let record1 = BlazeDataRecord(["message": .string("Data1")])
        let record2 = BlazeDataRecord(["message": .string("Data2")])

        DispatchQueue.global().async {
            do {
                try self.db.insert(record1, id: id3)
                expectation1.fulfill()
            } catch {
                XCTFail("Write Data1 failed: \(error)")
            }
        }

        DispatchQueue.global().async {
            do {
                try self.db.insert(record2, id: id4)
                expectation2.fulfill()
            } catch {
                XCTFail("Write Data2 failed: \(error)")
            }
        }

        wait(for: [expectation1, expectation2], timeout: 5.0)

        // Verify data
        let readData1: BlazeDataRecord? = try db.fetch(id: id3)
        let readData2: BlazeDataRecord? = try db.fetch(id: id4)
        XCTAssertEqual(readData1?.storage["message"]?.stringValue, "Data1")
        XCTAssertEqual(readData2?.storage["message"]?.stringValue, "Data2")
    }
}
