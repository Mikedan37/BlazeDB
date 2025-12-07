//  PageStoreTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import XCTest
@testable import BlazeDB
import CryptoKit

final class PageStoreTests: XCTestCase {

    var tempURL: URL!
    var key: SymmetricKey!
    var store: BlazeDB.PageStore!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent("test.blz")
        key = SymmetricKey(size: .bits256)
        store = try BlazeDB.PageStore(fileURL: tempURL, key: key)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testWriteAndReadPage() throws {
        let original = "This is a 🔥 test record.".data(using: .utf8)!
        try store.writePage(index: 0, plaintext: original)

        let readBack = try store.readPage(index: 0)
        XCTAssertEqual(readBack, original, "Decrypted data should match original")
    }

    func testInvalidRead() throws {
        let result = try store.readPage(index: 99)
        XCTAssertNil(result, "Reading a non-existent page should return nil")
    }

    func testPageTooLargeThrows() throws {
        let tooBig = Data(repeating: 0x01, count: 4096)
        XCTAssertThrowsError(try store.writePage(index: 1, plaintext: tooBig))
    }
}
