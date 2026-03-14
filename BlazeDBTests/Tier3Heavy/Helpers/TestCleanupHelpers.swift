//
//  TestCleanupHelpers.swift
//  BlazeDBTests
//
//  Helper utilities for proper test cleanup and resource management
//

import XCTest
import Foundation
@testable import BlazeDBCore

extension XCTestCase {
    /// Properly clean up a BlazeDB instance and all associated files
    func cleanupBlazeDB(_ db: inout BlazeDBClient?, at fileURL: URL) {
        // Step 1: Persist any pending changes
        try? db?.persist()
        
        // Step 2: Release the database instance
        db = nil
        
        // Step 3: Small delay to ensure file handles are released
        Thread.sleep(forTimeInterval: 0.05)
        
        // Step 4: Remove all associated files
        let extensions = ["", "meta", "indexes", "wal", "backup", "transaction_backup"]
        for ext in extensions {
            let url = ext.isEmpty ? fileURL : fileURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        
        // Step 4b: Remove transaction log and transaction backup files from parent directory
        let parentDir = fileURL.deletingLastPathComponent()
        let txnLogURL = parentDir.appendingPathComponent("txn_log.json")
        let txnBackupURL = parentDir.appendingPathComponent("txn_in_progress.blazedb")
        let txnMetaBackupURL = parentDir.appendingPathComponent("txn_in_progress.meta")
        
        try? FileManager.default.removeItem(at: txnLogURL)
        try? FileManager.default.removeItem(at: txnBackupURL)
        try? FileManager.default.removeItem(at: txnMetaBackupURL)
        
        // Step 5: Additional delay for filesystem consistency
        Thread.sleep(forTimeInterval: 0.02)
    }
    
    /// Clean up multiple database instances (for join/multi-db tests)
    func cleanupMultipleBlazeDBs(_ databases: inout [(db: BlazeDBClient?, url: URL)]) {
        for i in 0..<databases.count {
            cleanupBlazeDB(&databases[i].db, at: databases[i].url)
        }
    }
}

