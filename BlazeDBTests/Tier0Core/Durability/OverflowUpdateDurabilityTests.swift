//
//  OverflowUpdateDurabilityTests.swift
//  BlazeDB
//
//  An update that spills onto overflow pages fsyncs those pages before metadata
//  records the new nextPageIndex. Reopening with that stale catalog must not
//  hand the overflow pages to the next insert.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class OverflowUpdateDurabilityTests: XCTestCase {
    private let password = "OverflowUpdateDurability-2026!"

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("overflow-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sidecar(_ fileURL: URL, _ ext: String) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension(ext)
    }

    private func copyDatabase(from source: URL, to destination: URL, metaOverride: Data? = nil) throws {
        let fm = FileManager.default
        try fm.copyItem(at: source, to: destination)
        try fm.copyItem(at: sidecar(source, "salt"), to: sidecar(destination, "salt"))
        if let metaOverride {
            try metaOverride.write(to: sidecar(destination, "meta"), options: .atomic)
        } else {
            try fm.copyItem(at: sidecar(source, "meta"), to: sidecar(destination, "meta"))
        }
    }

    /// Crash after `update` returns and before `close`: the copied files are the on-disk image.
    func testCrashAfterOverflowUpdateKeepsRecordReadableAfterNextInsert() throws {
        BlazeDBClient.clearCachedKey()
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("live.blazedb")
        let marker = String(repeating: "Z", count: 8_000)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let db = try BlazeDBClient(name: "live", fileURL: url, password: password)
        let id = try db.insert(BlazeDataRecord([
            "body": .string("small"),
            "createdAt": .date(createdAt)
        ]))
        try db.update(id: id, with: BlazeDataRecord([
            "body": .string(marker),
            "createdAt": .date(createdAt)
        ]))

        let crashDir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: crashDir) }
        let crashURL = crashDir.appendingPathComponent("crash.blazedb")
        try copyDatabase(from: url, to: crashURL)
        try db.close()

        BlazeDBClient.clearCachedKey()
        let reopened = try BlazeDBClient(name: "crash", fileURL: crashURL, password: password)
        defer { try? reopened.close() }

        XCTAssertEqual(try reopened.fetch(id: id)?.storage["body"], .string(marker))
        _ = try reopened.insert(BlazeDataRecord([
            "body": .string("next"),
            "createdAt": .date(createdAt)
        ]))
        try reopened.close()

        BlazeDBClient.clearCachedKey()
        let afterInsert = try BlazeDBClient(name: "after-insert", fileURL: crashURL, password: password)
        defer { try? afterInsert.close() }
        XCTAssertEqual(
            try afterInsert.fetch(id: id)?.storage["body"],
            .string(marker),
            "Insert after a crash must not overwrite the updated record's overflow pages"
        )
    }

    /// Crash in the window after the overflow pages are fsynced and before metadata is replaced.
    func testStaleNextPageIndexAfterOverflowWriteDoesNotReuseThosePages() throws {
        BlazeDBClient.clearCachedKey()
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("live.blazedb")
        let marker = String(repeating: "Q", count: 8_000)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let db = try BlazeDBClient(name: "live", fileURL: url, password: password)
        let id = try db.insert(BlazeDataRecord([
            "body": .string("small"),
            "createdAt": .date(createdAt)
        ]))
        let staleMetaURL = dir.appendingPathComponent("meta-before-update")
        try FileManager.default.copyItem(at: db.collection.metaURL, to: staleMetaURL)
        let staleMeta = try Data(contentsOf: staleMetaURL)
        let nextPageBeforeUpdate = db.collection.nextPageIndex
        try db.update(id: id, with: BlazeDataRecord([
            "body": .string(marker),
            "createdAt": .date(createdAt)
        ]))
        try db.close()

        let crashDir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: crashDir) }
        let crashURL = crashDir.appendingPathComponent("crash.blazedb")
        try copyDatabase(from: url, to: crashURL, metaOverride: staleMeta)

        let pageCount = try pageCount(of: crashURL)
        XCTAssertGreaterThan(
            pageCount,
            nextPageBeforeUpdate,
            "The overflow update must have written pages past the pre-update catalog"
        )

        BlazeDBClient.clearCachedKey()
        let reopened = try BlazeDBClient(name: "crash", fileURL: crashURL, password: password)
        defer { try? reopened.close() }

        XCTAssertGreaterThanOrEqual(reopened.collection.nextPageIndex, pageCount)
        XCTAssertEqual(try reopened.fetch(id: id)?.storage["body"], .string(marker))
        _ = try reopened.insert(BlazeDataRecord([
            "body": .string("next"),
            "createdAt": .date(createdAt)
        ]))
        try reopened.close()

        // Reopen so the record cache cannot hide a page that the insert overwrote.
        BlazeDBClient.clearCachedKey()
        let afterInsert = try BlazeDBClient(name: "after-insert", fileURL: crashURL, password: password)
        defer { try? afterInsert.close() }
        XCTAssertEqual(
            try afterInsert.fetch(id: id)?.storage["body"],
            .string(marker),
            "A stale nextPageIndex must not reuse pages already occupied by the updated record"
        )
    }

    private func pageCount(of fileURL: URL) throws -> Int {
        let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        return (size?.intValue ?? 0) / 4096
    }
}
