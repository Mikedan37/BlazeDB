//  TestHelpers.swift
//  BlazeDB Test Utilities
//  Shared helpers for test isolation and cleanup

import Foundation
import XCTest
@testable import BlazeDB

/// Helper to ensure proper cleanup of test files even if tests crash
extension XCTestCase {
    
    /// Create a unique temp URL and register it for automatic cleanup
    func makeTempURL(name: String = "test", ext: String = "blazedb") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).\(ext)")
        
        // Register cleanup block (runs even if test crashes)
        addTeardownBlock { [url] in
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta.indexes"))
        }
        
        return url
    }
    
    /// Clean up all BlazeDB-related files for a given URL
    func cleanupBlazeDBFiles(at url: URL) {
        let urls = [
            url,
            url.deletingPathExtension().appendingPathExtension("meta"),
            url.deletingPathExtension().appendingPathExtension("meta.indexes"),
            url.deletingLastPathComponent().appendingPathComponent("transaction_backup.blazedb"),
            url.deletingLastPathComponent().appendingPathComponent("transaction_backup.meta"),
        ]
        
        for fileURL in urls {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// Utility to count test files in temp directory
class TestFileMonitor {
    static func countBlazeDBFilesInTemp() -> Int {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        
        let blazeFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".blazedb") ||
                   name.hasSuffix(".blaze") ||
                   name.hasSuffix(".blz") ||
                   name.hasSuffix(".meta") ||
                   name.hasSuffix(".meta.indexes") ||
                   name.hasPrefix("BlazeDB-") ||
                   name.hasPrefix("BlazeCorruption-") ||
                   name.hasPrefix("BlazeStress-") ||
                   name.hasPrefix("BlazeFS-") ||
                   name.contains("blazedb.recovery") ||
                   name.hasPrefix("backup_v0_")
        }
        
        return blazeFiles.count
    }
    
    static func cleanupAllBlazeDBTestFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        
        let blazeFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".blazedb") ||
                   name.hasSuffix(".blaze") ||
                   name.hasSuffix(".blz") ||
                   name.hasSuffix(".meta") ||
                   name.hasSuffix(".meta.indexes") ||
                   name.hasSuffix(".db") ||
                   name.hasPrefix("BlazeDB-") ||
                   name.hasPrefix("BlazeCorruption-") ||
                   name.hasPrefix("BlazeStress-") ||
                   name.hasPrefix("BlazeFS-") ||
                   name.hasPrefix("PageStoreBoundary-") ||
                   name.contains("blazedb.recovery") ||
                   name.hasPrefix("backup_v0_") ||
                   name.hasPrefix("cleanup-") ||
                   name.hasPrefix("testListDB") ||
                   name.hasPrefix("testdb") ||
                   name.hasPrefix("switch")
        }
        
        print("🧹 Cleaning \(blazeFiles.count) BlazeDB test files...")
        
        for file in blazeFiles {
            try? FileManager.default.removeItem(at: file)
        }
        
        print("✅ Cleanup complete")
    }
}

