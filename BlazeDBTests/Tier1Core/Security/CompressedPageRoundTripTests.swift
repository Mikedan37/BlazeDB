//
//  CompressedPageRoundTripTests.swift
//  BlazeDB
//
//  Cross-platform behavior checks for page version 0x03 (compressed pages).
//

import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

final class CompressedPageRoundTripTests: XCTestCase {
    private var tempURL: URL!
    private var store: PageStore!
    private var key: SymmetricKey!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompressRoundTrip-\(UUID().uuidString).blazedb")
        try? FileManager.default.removeItem(at: url)
        tempURL = url
        key = SymmetricKey(size: .bits256)
        store = try PageStore(fileURL: url, key: key)
    }

    override func tearDown() {
        store = nil
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    #if canImport(Compression)
    func testCompressedPageRoundTrip() throws {
        store.enableCompression()

        // Payload must exceed 1024 bytes to trigger compression.
        let payload = Data(repeating: 0xAB, count: 2048)
        try store.writePageCompressed(index: 0, plaintext: payload)

        let readBack = try store.readPageCompressed(index: 0)
        XCTAssertNotNil(readBack, "Compressed page should be readable")
        XCTAssertEqual(readBack, payload, "Round-trip data should match original")
    }
    #else
    func testCompressedPageFailsWithClearPlatformMessageWhenCompressionUnavailable() throws {
        // Write a synthetic page with valid header + version 0x03 marker.
        var page = Data("BZDB".utf8)
        page.append(0x03)
        var length = UInt32(256).bigEndian
        page.append(Data(bytes: &length, count: 4))
        page.append(Data(repeating: 0xCD, count: 256))
        if page.count < 4096 {
            page.append(Data(repeating: 0, count: 4096 - page.count))
        }
        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: page)
        try handle.synchronize()
        try handle.close()

        XCTAssertThrowsError(try store.readPage(index: 0)) { error in
            let message = (error as NSError).localizedDescription.lowercased()
            XCTAssertTrue(message.contains("compression"))
            XCTAssertTrue(message.contains("not available on this platform"))
            XCTAssertTrue(message.contains("0x03"))
        }
    }
    #endif
}
