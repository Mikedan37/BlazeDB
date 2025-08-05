//  KeyManagerTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import XCTest
@testable import BlazeDB

import CryptoKit

final class KeyManagerTests: XCTestCase {
    
    let testText = "🔥 Blaze it. Don't lose it.".data(using: .utf8)!
    var tempFile: URL!
    var store: PageStore!

    override func setUpWithError() throws {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blz")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFile)
    }


    func testPasswordKeyEncryptDecrypt() throws {
        let key = try KeyManager.getKey(from: .password("my-secure-password-🔥"))
        let store = try PageStore(fileURL: tempFile)

        try store.writePage(index: 1, plaintext: testText)
        let readBack = try store.readPage(index: 1)

        XCTAssertEqual(readBack, testText, "Password-derived key should decrypt properly")
    }

    func testWeakPasswordFails() throws {
        XCTAssertThrowsError(try KeyManager.getKey(from: .password("123"))) { error in
            guard case KeyManagerError.passwordTooWeak = error else {
                XCTFail("Expected passwordTooWeak error, got \(error)")
                return
            }
        }
    }
}
