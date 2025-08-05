//  BlazeTransactionTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.

//import XCTest
//@testable import BlazeDB
//import CryptoKit
//
//final class BlazeTransactionTests: XCTestCase {
//    var dbURL: URL!
//    var key: SymmetricKey!
//
//    override func setUpWithError() throws {
//        let tempDir = FileManager.default.temporaryDirectory
//        dbURL = tempDir.appendingPathComponent("testdb.blz")
//        try? FileManager.default.removeItem(at: dbURL) // clean slate
//        key = SymmetricKey(size: .bits256)
//    }
//
//    func testMultipleTransactionsAndPersistence() throws {
//        let db = try BlazeDatabase(url: dbURL, key: key)
//
//        // 🚀 Transaction 1 - Write "First"
//        let txn1 = db.beginTransaction()
//        let firstData = Data("First".utf8)
//        try txn1.write(pageID: 1, data: firstData)
//        let readBack1 = try txn1.read(pageID: 1)
//        XCTAssertEqual(readBack1, firstData)
//        try txn1.commit()
//
//        // 🔁 Transaction 2 - Read back from disk
//        let txn2 = db.beginTransaction()
//        let persisted = try txn2.read(pageID: 1)
//        XCTAssertEqual(persisted, firstData)
//        try txn2.commit()
//
//        // 🧹 Transaction 3 - Overwrite with "Second"
//        let txn3 = db.beginTransaction()
//        let secondData = Data("Second".utf8)
//        try txn3.write(pageID: 1, data: secondData)
//        try txn3.commit()
//
//        // 🧪 Final check - make sure overwrite worked
//        let txn4 = db.beginTransaction()
//        let finalData = try txn4.read(pageID: 1)
//        XCTAssertEqual(finalData, secondData)
//        try txn4.commit()
//    }
//
//    func testRollbackDiscardsChanges() throws {
//        let db = try BlazeDB.BlazeDatabase(url: dbURL, key: key)
//
//        let txn1 = db.beginTransaction()
//        let data = Data("Temp".utf8)
//        try txn1.write(pageID: 2, data: data)
//        txn1.rollback()
//
//        let txn2 = db.beginTransaction()
//        XCTAssertThrowsError(try txn2.read(pageID: 2)) // should not exist
//    }
//}
