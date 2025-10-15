//
//  StorageStatsTests.swift
//  BlazeDB
//
//  Created by Michael Danylchuk on 10/11/25.
//


//
//  StorageStatsTests.swift
//  BlazeDBTests
//
//  Created by Michael Danylchuk on 10/11/25.
//


import XCTest
import CryptoKit
@testable import BlazeDB

private typealias DBPageStore = BlazeDB.PageStore

final class StorageStatsTests: XCTestCase {
    // MARK: - Helpers
    private func makeTempURL(_ name: String = UUID().uuidString) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeDB-StorageStats", isDirectory: true)
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(name + ".db")
    }

    private func openStore(named: String = UUID().uuidString) throws -> (DBPageStore, URL) {
        let url = try makeTempURL(named)
        let key = SymmetricKey(size: .bits256) // encryption disabled internally, API-compatible
        let store = try DBPageStore(fileURL: url, key: key)
        return (store, url)
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }

    private func detectPageSize(via url: URL, store: DBPageStore) throws -> Int {
        // Write one small page to infer page size from the on-disk file length.
        let initial = try fileSize(url)
        XCTAssertEqual(initial, 0)
        _ = try store.write("p".data(using: .utf8)!)
        let sizeAfter = try fileSize(url)
        XCTAssertGreaterThan(sizeAfter, 0)
        return sizeAfter // exactly one page
    }

    private func overwriteHeader(url: URL, pageIndex: Int, pageSize: Int, with header: Data) throws {
        precondition(header.count == 5, "header must be 5 bytes: 'BZDB' + version")
        let fh = try FileHandle(forUpdating: url)
        try fh.seek(toOffset: UInt64(pageIndex * pageSize))
        try fh.write(contentsOf: header)
        try fh.synchronize()
        try fh.close()
    }

    private func appendBytes(url: URL, bytes count: Int) throws {
        let fh = try FileHandle(forUpdating: url)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data(repeating: 0xA7, count: count))
        try fh.synchronize()
        try fh.close()
    }

    // MARK: - Tests

    func testEmptyFileStats() throws {
        let (store, url) = try openStore(named: #function)
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 0)
        XCTAssertEqual(stats.orphanedPages, 0)
        XCTAssertEqual(stats.estimatedSize, 0)
        // sanity: file actually exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testValidHeadersCountNoOrphans() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        // write another valid page (append)
        _ = try store.write("q".data(using: .utf8)!)
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 2)
        XCTAssertEqual(stats.orphanedPages, 0)
        XCTAssertEqual(stats.estimatedSize, 2 * pageSize)
    }

    func testPartialTrailingPageIsIgnored() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        // Append some stray bytes (< one page) to simulate a torn/incomplete page at the end.
        try appendBytes(url: url, bytes: 123)
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 1)
        XCTAssertEqual(stats.orphanedPages, 0)
        XCTAssertEqual(stats.estimatedSize, pageSize + 123) // size includes the tail, but not another page
    }

    func testInvalidHeaderCountsAsOrphan() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        _ = try store.write("ok".data(using: .utf8)!) // now 2 pages
        // Corrupt header of page 1
        let badHeader = Data([0x58, 0x58, 0x58, 0x58, 0x01]) // "XXXX" + 0x01
        try overwriteHeader(url: url, pageIndex: 1, pageSize: pageSize, with: badHeader)
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 2)
        XCTAssertEqual(stats.orphanedPages, 1)
        XCTAssertEqual(stats.estimatedSize, 2 * pageSize)
    }

    func testZeroedPageHeaderIsOrphan() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        _ = try store.write("valid".data(using: .utf8)!) // page 1
        try store.deletePage(index: 0) // zero the first page's header & content
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 2)
        XCTAssertEqual(stats.orphanedPages, 1)
        XCTAssertEqual(stats.estimatedSize, 2 * pageSize)
    }

    func testVersionMismatchHeaderIsOrphan() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        _ = try store.write("valid".data(using: .utf8)!) // page 1
        // "BZDB" + wrong version 0x02
        let wrongVersion = ("BZDB".data(using: .utf8) ?? Data()) + Data([0x02])
        try overwriteHeader(url: url, pageIndex: 1, pageSize: pageSize, with: wrongVersion)
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 2)
        XCTAssertEqual(stats.orphanedPages, 1)
        XCTAssertEqual(stats.estimatedSize, 2 * pageSize)
    }

    func testManyPagesRandomCorruption() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        // Create 16 pages total
        for _ in 0..<15 { _ = try store.write("x".data(using: .utf8)!) }
        var toCorrupt: Set<Int> = []
        while toCorrupt.count < 3 { toCorrupt.insert(Int.random(in: 0..<16)) }
        let badHeader = Data([0x42, 0x5A, 0x44, 0x42, 0xFF]) // BZDB + bad version
        for idx in toCorrupt { try overwriteHeader(url: url, pageIndex: idx, pageSize: pageSize, with: badHeader) }
        let stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 16)
        XCTAssertEqual(stats.orphanedPages, toCorrupt.count)
        XCTAssertEqual(stats.estimatedSize, 16 * pageSize)
    }

    func testDeleteThenRewriteClearsOrphan() throws {
        let (store, url) = try openStore(named: #function)
        let pageSize = try detectPageSize(via: url, store: store)
        _ = try store.write("1".data(using: .utf8)!) // page 1
        _ = try store.write("2".data(using: .utf8)!) // page 2
        try store.deletePage(index: 1) // orphan page 1
        var stats = try store.getStorageStats()
        XCTAssertEqual(stats.orphanedPages, 1)
        // Rewrite valid header/content at index 1
        try store.writePage(index: 1, plaintext: "replaced".data(using: .utf8)!)
        stats = try store.getStorageStats()
        XCTAssertEqual(stats.totalPages, 3)
        XCTAssertEqual(stats.orphanedPages, 0)
        XCTAssertEqual(stats.estimatedSize, 3 * pageSize)
    }

    func testConcurrentStatsUnderWrites() throws {
        let (store, _) = try openStore(named: #function)
        let writers = 10
        let writesPer = 10
        let grp = DispatchGroup()
        for _ in 0..<writers {
            grp.enter()
            DispatchQueue.global().async {
                defer { grp.leave() }
                for i in 0..<writesPer {
                    _ = try? store.write("w\(i)".data(using: .utf8)!)
                }
            }
        }
        // Concurrently poll stats
        var errors = 0
        let polls = 100
        for _ in 0..<polls {
            DispatchQueue.global().async {
                do { _ = try store.getStorageStats() } catch { errors += 1 }
            }
        }
        grp.wait()
        // Ensure no errors were thrown by stats under concurrent writes
        XCTAssertEqual(errors, 0)
        // And we wrote at least writers*writesPer pages (plus any created to probe size if called)
        let stats = try store.getStorageStats()
        XCTAssertGreaterThanOrEqual(stats.totalPages, writers * writesPer)
    }
}
