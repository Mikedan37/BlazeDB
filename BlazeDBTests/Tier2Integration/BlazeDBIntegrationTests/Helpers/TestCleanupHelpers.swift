//
//  TestCleanupHelpers.swift
//  BlazeDB_Tier2
//
//  File-level cleanup for integration tests (no open BlazeDBClient required).
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

extension XCTestCase {
    /// Remove on-disk artifacts for a BlazeDB file URL (best-effort).
    func removeBlazeDBTestFiles(at fileURL: URL) {
        let base = fileURL.deletingPathExtension()
        let sidecars = [
            fileURL,
            base.appendingPathExtension("meta"),
            base.appendingPathExtension("meta.indexes"),
            base.appendingPathExtension("indexes"),
            base.appendingPathExtension("wal"),
            base.appendingPathExtension("backup"),
            base.appendingPathExtension("transaction_backup"),
        ]
        for url in sidecars {
            try? FileManager.default.removeItem(at: url)
        }

        let parentDir = fileURL.deletingLastPathComponent()
        for name in ["txn_log.json", "txn_in_progress.blazedb", "txn_in_progress.meta"] {
            try? FileManager.default.removeItem(at: parentDir.appendingPathComponent(name))
        }
    }

    /// Properly clean up a BlazeDB instance and all associated files.
    func cleanupBlazeDB(_ db: inout BlazeDBClient?, at fileURL: URL) {
        try? db?.persist()
        db = nil
        Thread.sleep(forTimeInterval: 0.05)
        removeBlazeDBTestFiles(at: fileURL)
        Thread.sleep(forTimeInterval: 0.02)
    }
}
