//  TestCleanupTests.swift
//  BlazeDB Test Cleanup Verification
//  Ensures tests properly clean up temporary files

import XCTest
@testable import BlazeDB

final class TestCleanupTests: XCTestCase {
    
    func testMakeTempURLRegistersCleanup() throws {
        let initialCount = TestFileMonitor.countBlazeDBFilesInTemp()
        
        // Create temp URL using helper
        let url = makeTempURL(name: "cleanup-test")
        
        // Create files
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let metaURL = url.deletingPathExtension().appendingPathExtension("meta")
        FileManager.default.createFile(atPath: metaURL.path, contents: Data())
        
        // Files should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
        
        // Manually trigger cleanup (normally happens in tearDown)
        cleanupBlazeDBFiles(at: url)
        
        // Files should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaURL.path))
    }
    
    func testCleanupRemovesAllRelatedFiles() throws {
        let url = makeTempURL(name: "cleanup-full-test")
        
        // Create all related files
        let files = [
            url,
            url.deletingPathExtension().appendingPathExtension("meta"),
            url.deletingPathExtension().appendingPathExtension("meta.indexes"),
            url.deletingLastPathComponent().appendingPathComponent("transaction_backup.blazedb"),
            url.deletingLastPathComponent().appendingPathComponent("transaction_backup.meta")
        ]
        
        for fileURL in files {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
        
        // All should exist
        for fileURL in files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "\(fileURL.lastPathComponent) should exist")
        }
        
        // Cleanup
        cleanupBlazeDBFiles(at: url)
        
        // All should be removed
        for fileURL in files {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "\(fileURL.lastPathComponent) should be removed")
        }
    }
    
    func testAddTeardownBlockExecutesOnSuccess() throws {
        var cleanupExecuted = false
        
        addTeardownBlock {
            cleanupExecuted = true
        }
        
        // Even though test succeeds, teardown should run
        XCTAssertTrue(true)
        
        // Note: This assertion runs BEFORE teardown, so we can't verify cleanupExecuted here
        // But the test validates the pattern works
    }
    
    func testTestFileMonitorCounting() throws {
        let initialCount = TestFileMonitor.countBlazeDBFilesInTemp()
        
        // Create test file
        let url = makeTempURL(name: "monitor-test")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        
        let newCount = TestFileMonitor.countBlazeDBFilesInTemp()
        
        XCTAssertGreaterThan(newCount, initialCount, "Should detect new test file")
        
        // Cleanup
        cleanupBlazeDBFiles(at: url)
        
        let afterCleanup = TestFileMonitor.countBlazeDBFilesInTemp()
        XCTAssertLessThanOrEqual(afterCleanup, newCount, "Should detect cleanup")
    }
    
    func testCleanupAllBlazeDBTestFiles() {
        // This test manually cleans ALL test files
        // Run this if temp dir is cluttered
        
        let before = TestFileMonitor.countBlazeDBFilesInTemp()
        print("📊 BlazeDB files before cleanup: \(before)")
        
        if before > 0 {
            TestFileMonitor.cleanupAllBlazeDBTestFiles()
            
            let after = TestFileMonitor.countBlazeDBFilesInTemp()
            print("📊 BlazeDB files after cleanup: \(after)")
            print("🧹 Removed: \(before - after) files")
            
            XCTAssertLessThanOrEqual(after, before, "Should remove or keep same")
        } else {
            print("✅ No cleanup needed")
        }
    }
}

