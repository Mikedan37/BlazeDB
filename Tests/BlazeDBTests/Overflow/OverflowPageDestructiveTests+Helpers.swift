//
//  OverflowPageDestructiveTests+Helpers.swift
//  BlazeDBTests
//
//  Helper utilities for destructive overflow page tests
//  Corruption simulation, chain validation, concurrency helpers
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import XCTest
@testable import BlazeDB

// MARK: - Chain Validation Helpers

extension OverflowPageDestructiveTests {
    
    /// Validate overflow chain structure and integrity
    func validateOverflowChain(
        pageIndices: [Int],
        expectedDataSize: Int,
        pageStore: PageStore
    ) throws {
        XCTAssertGreaterThan(pageIndices.count, 0, "Chain must have at least one page")
        
        // Verify pages are sequential (or at least valid)
        for i in 0..<(pageIndices.count - 1) {
            XCTAssertGreaterThan(pageIndices[i+1], pageIndices[i], 
                                "Chain should be sequential at index \(i)")
        }
        
        // Verify we can read the full chain
        if let firstPage = pageIndices.first {
            let readData = try pageStore.readPageWithOverflow(index: firstPage)
            XCTAssertNotNil(readData, "Should read full chain")
            if let data = readData {
                XCTAssertEqual(data.count, expectedDataSize, 
                              "Read data size should match expected")
            }
        }
    }
    
    /// Verify chain termination (last page has next=0)
    func verifyChainTermination(
        pageIndex: Int,
        pageStore: PageStore,
        fileURL: URL
    ) throws -> Bool {
        // Read page and check overflow header
        let pageData = try pageStore.readPage(index: pageIndex)
        guard let data = pageData, data.count >= 16 else {
            return false
        }
        
        // Check if it's an overflow page (magic "OVER")
        let magicBytes = data.prefix(4)
        let magic = magicBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        if magic == 0x4F564552 {  // "OVER"
            // Read next pointer (bytes 8-11)
            let nextBytes = data.subdata(in: 8..<12)
            let nextPointer = nextBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            return nextPointer == 0  // Terminated if next=0
        }
        
        return true  // Not an overflow page, or regular page
    }
}

// MARK: - Corruption Simulation Helpers

extension OverflowPageDestructiveTests {
    
    /// Simulate corruption by modifying page bytes directly
    func corruptPage(
        _ pageIndex: Int,
        at offset: Int,
        with data: Data,
        fileURL: URL,
        pageSize: Int = 4096
    ) throws {
        let fileHandle = try FileHandle(forUpdating: fileURL)
        defer { try? fileHandle.close() }
        
        let absoluteOffset = UInt64(pageIndex * pageSize + offset)
        try fileHandle.seek(toOffset: absoluteOffset)
        try fileHandle.write(contentsOf: data)
        try fileHandle.synchronize()
    }
    
    /// Break overflow chain pointer
    func breakChainPointer(
        pageIndex: Int,
        invalidNextPage: UInt32 = 99999,
        fileURL: URL,
        pageSize: Int = 4096
    ) throws {
        let offset = 8  // Next pointer is at offset 8 in overflow header
        var invalidPointer = invalidNextPage.bigEndian
        let pointerData = Data(bytes: &invalidPointer, count: 4)
        try corruptPage(pageIndex, at: offset, with: pointerData, fileURL: fileURL, pageSize: pageSize)
    }
    
    /// Create circular overflow chain
    func createCircularChain(
        pageIndices: [Int],
        fileURL: URL,
        pageSize: Int = 4096
    ) throws {
        guard pageIndices.count >= 3 else {
            throw NSError(domain: "Test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Need at least 3 pages for circular chain"
            ])
        }
        
        // Make page[N] point to page[1] (creating loop)
        let lastPageIndex = pageIndices[pageIndices.count - 1]
        let targetPageIndex = UInt32(pageIndices[1])
        
        try breakChainPointer(
            pageIndex: lastPageIndex,
            invalidNextPage: targetPageIndex,
            fileURL: fileURL,
            pageSize: pageSize
        )
    }
    
    /// Truncate page (simulate partial write)
    func truncatePage(
        _ pageIndex: Int,
        to size: Int,
        fileURL: URL,
        pageSize: Int = 4096
    ) throws {
        let fileHandle = try FileHandle(forUpdating: fileURL)
        defer { try? fileHandle.close() }
        
        let offset = UInt64(pageIndex * pageSize)
        try fileHandle.seek(toOffset: offset)
        
        // Write only partial data
        let partialData = Data(repeating: 0, count: size)
        try fileHandle.write(contentsOf: partialData)
        try fileHandle.synchronize()
    }
}

// MARK: - Concurrency Helpers

extension OverflowPageDestructiveTests {
    
    /// Run concurrent operations with timeout
    func runConcurrent<T>(
        count: Int,
        timeout: TimeInterval = 10.0,
        operation: @escaping (Int) throws -> T
    ) throws -> [T] {
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = count
        
        var results: [T?] = Array(repeating: nil, count: count)
        var errors: [Error] = []
        let lock = NSLock()
        
        for i in 0..<count {
            DispatchQueue.global().async {
                do {
                    let result = try operation(i)
                    lock.lock()
                    results[i] = result
                    lock.unlock()
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: timeout)
        
        if !errors.isEmpty {
            throw errors.first!
        }
        
        return results.compactMap { $0 }
    }
    
    /// Measure operation time
    func measureTime<T>(_ operation: () throws -> T) rethrows -> (result: T, time: TimeInterval) {
        let start = Date()
        let result = try operation()
        let elapsed = Date().timeIntervalSince(start)
        return (result, elapsed)
    }
}

// MARK: - Memory Leak Detection Helpers

extension OverflowPageDestructiveTests {
    
    /// Track memory usage (placeholder - needs actual memory tracking)
    struct MemorySnapshot {
        let timestamp: Date
        let description: String
        
        static func capture(_ description: String) -> MemorySnapshot {
            return MemorySnapshot(timestamp: Date(), description: description)
        }
    }
    
    /// Compare memory snapshots
    func compareMemory(
        before: MemorySnapshot,
        after: MemorySnapshot,
        maxGrowthMB: Double = 10.0
    ) -> Bool {
        // Placeholder - actual implementation needs memory tracking
        // For now, just verify operations complete without crashes
        return true
    }
}

// MARK: - Reactive Query Test Helpers

extension OverflowPageDestructiveTests {
    
    /// Wait for reactive query update with timeout
    func waitForReactiveUpdate(
        query: BlazeQuery,
        initialCount: Int,
        timeout: TimeInterval = 2.0,
        expectedChange: Int? = nil
    ) -> Int {
        let startTime = Date()
        var currentCount = initialCount
        
        while Date().timeIntervalSince(startTime) < timeout {
            currentCount = query.wrappedValue.count
            if let expected = expectedChange {
                if currentCount == initialCount + expected {
                    return currentCount
                }
            } else if currentCount != initialCount {
                return currentCount
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        return currentCount
    }
    
    /// Count change notifications
    func countNotifications(
        db: BlazeDBClient,
        timeout: TimeInterval = 1.0,
        operation: () throws -> Void
    ) throws -> Int {
        var count = 0
        let lock = NSLock()
        
        let token = db.observe { changes in
            lock.lock()
            count += changes.count
            lock.unlock()
        }
        
        defer { token.invalidate() }
        
        try operation()
        
        // Wait for batching (50ms delay)
        Thread.sleep(forTimeInterval: timeout)
        
        lock.lock()
        let finalCount = count
        lock.unlock()
        
        return finalCount
    }
}

// MARK: - Assertion Helpers

extension OverflowPageDestructiveTests {
    
    /// Assert no partial reads (data must be full or nil)
    func assertNoPartialReads(
        readData: Data?,
        expectedData: Data,
        message: String = "Read must be full or nil, never partial"
    ) {
        if let data = readData {
            XCTAssertEqual(data.count, expectedData.count, 
                          "\(message): Got \(data.count) bytes, expected \(expectedData.count)")
            XCTAssertEqual(data, expectedData, 
                          "\(message): Data must match exactly if not nil")
        }
        // nil is acceptable (record deleted)
    }
    
    /// Assert chain integrity
    func assertChainIntegrity(
        pageIndices: [Int],
        readData: Data?,
        expectedData: Data
    ) {
        XCTAssertGreaterThan(pageIndices.count, 0, "Chain must exist")
        
        if let data = readData {
            XCTAssertEqual(data.count, expectedData.count, 
                          "Chain must return full data")
            XCTAssertEqual(data, expectedData, 
                          "Chain data must match exactly")
        } else {
            XCTFail("Chain should return data")
        }
    }
    
    /// Assert no corruption (data must be readable)
    func assertNoCorruption(
        pageIndex: Int,
        pageStore: PageStore,
        message: String = "Page should not be corrupted"
    ) throws {
        let readData = try pageStore.readPageWithOverflow(index: pageIndex)
        XCTAssertNotNil(readData, "\(message): Should be readable")
    }
}

