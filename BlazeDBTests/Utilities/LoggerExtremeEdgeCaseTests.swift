//
//  LoggerExtremeEdgeCaseTests.swift
//  BlazeDBTests
//
//  Extreme edge case tests for BlazeLogger.
//  Tests very long messages, extreme concurrency, and handler failures.
//
//  Created: Phase 3 Robustness Testing
//

import XCTest
@testable import BlazeDB

final class LoggerExtremeEdgeCaseTests: XCTestCase {
    
    override func tearDown() {
        BlazeLogger.reset()
    }
    
    // MARK: - Extreme Message Tests
    
    /// Test logging extremely long message (1MB+)
    func testVeryLongMessage() {
        print("📝 Testing very long log message (1MB)...")
        
        BlazeLogger.level = .debug
        
        var receivedMessages: [String] = []
        BlazeLogger.handler = { message, level in
            receivedMessages.append(message)
        }
        
        // Create 1MB message
        let longMessage = String(repeating: "A", count: 1_000_000)
        let startTime = Date()
        
        BlazeLogger.debug(longMessage)
        
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(receivedMessages.count, 1, "Should receive exactly one log message")
        
        // Message includes "[BlazeDB:DEBUG] " prefix (16 chars) + original message
        let expectedLength = 1_000_000 + 16  // "[BlazeDB:DEBUG] " = 16 chars
        XCTAssertEqual(receivedMessages[0].count, expectedLength, "Message should include prefix + 1MB content")
        XCTAssertTrue(receivedMessages[0].contains(longMessage), "Message should contain original 1MB string")
        
        // Should be fast even with large message
        XCTAssertLessThan(duration, 0.1, "Logging 1MB message should be < 100ms")
        
        print("  Logged 1MB message in \(String(format: "%.3f", duration))s")
        print("✅ Very long message handling works")
    }
    
    /// Test logging from 100+ concurrent threads
    func testExtremeConcurrentLogging() {
        print("📝 Testing extreme concurrent logging (100 threads)...")
        
        BlazeLogger.level = .info
        
        var messageCount = 0
        let countLock = NSLock()
        
        BlazeLogger.handler = { _, _ in
            countLock.lock()
            messageCount += 1
            countLock.unlock()
        }
        
        let expectation = self.expectation(description: "100 concurrent logs")
        expectation.expectedFulfillmentCount = 100
        
        let queue = DispatchQueue(label: "test.logger", attributes: .concurrent)
        
        for i in 0..<100 {
            queue.async {
                BlazeLogger.info("Message from thread \(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertEqual(messageCount, 100, "Should receive all 100 messages")
        
        print("✅ Extreme concurrent logging works correctly")
    }
    
    /// Test logger when custom handler crashes
    // REMOVED: testHandlerCrashDoesNotBreakLogger
    // Reason: fatalError() cannot be caught by XCTest - it terminates the process immediately.
    // This test was crashing the test suite. If a custom handler calls fatalError(), 
    // the app SHOULD crash - that's what fatalError() is designed for.
    

    /// Test logging with special control characters
    func testLoggingWithControlCharacters() {
        print("📝 Testing logging with control characters...")
        
        BlazeLogger.level = .debug
        
        var receivedMessages: [String] = []
        BlazeLogger.handler = { message, _ in
            receivedMessages.append(message)
        }
        
        // Log messages with control characters
        BlazeLogger.debug("Message\nwith\nnewlines")
        BlazeLogger.debug("Message\twith\ttabs")
        BlazeLogger.debug("Message\rwith\rcarriage\rreturns")
        BlazeLogger.debug("Message\0with\0nulls")
        
        XCTAssertEqual(receivedMessages.count, 4, "Should handle all control characters")
        
        // Verify messages preserved
        XCTAssertTrue(receivedMessages[0].contains("\n"))
        XCTAssertTrue(receivedMessages[1].contains("\t"))
        
        print("✅ Control characters in log messages work correctly")
    }
}

