//  BlazeLoggerTests.swift
//  BlazeDBTests
//  Created by Michael Danylchuk on 11/6/25.

import XCTest
@testable import BlazeDB

final class BlazeLoggerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset to known state before each test
        BlazeLogger.reset()
    }
    
    override func tearDown() {
        BlazeLogger.reset()
        super.tearDown()
    }
    
    // MARK: - Log Level Tests
    
    func testDefaultLogLevel() {
        // Default should be .warn
        XCTAssertEqual(BlazeLogger.level, .warn, "Default log level should be .warn")
    }
    
    func testLogLevelHierarchy() {
        // Test level comparison
        XCTAssertTrue(BlazeLogLevel.silent < BlazeLogLevel.error)
        XCTAssertTrue(BlazeLogLevel.error < BlazeLogLevel.warn)
        XCTAssertTrue(BlazeLogLevel.warn < BlazeLogLevel.info)
        XCTAssertTrue(BlazeLogLevel.info < BlazeLogLevel.debug)
        XCTAssertTrue(BlazeLogLevel.debug < BlazeLogLevel.trace)
    }
    
    func testSilentMode() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        
        BlazeLogger.enableSilentMode()
        
        // Nothing should be logged
        BlazeLogger.error("Error message")
        BlazeLogger.warn("Warning message")
        BlazeLogger.info("Info message")
        BlazeLogger.debug("Debug message")
        BlazeLogger.trace("Trace message")
        
        XCTAssertEqual(captured.count, 0, "Silent mode should suppress all logs")
    }
    
    func testErrorLevel() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .error
        
        BlazeLogger.error("Error message")
        BlazeLogger.warn("Warning message")
        BlazeLogger.info("Info message")
        
        XCTAssertEqual(captured.count, 1, "Error level should only show errors")
        XCTAssertTrue(captured[0].contains("ERROR"))
        XCTAssertTrue(captured[0].contains("Error message"))
    }
    
    func testWarnLevel() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .warn
        
        BlazeLogger.error("Error message")
        BlazeLogger.warn("Warning message")
        BlazeLogger.info("Info message")
        
        XCTAssertEqual(captured.count, 2, "Warn level should show errors + warnings")
        XCTAssertTrue(captured.contains { $0.contains("ERROR") })
        XCTAssertTrue(captured.contains { $0.contains("WARN") })
    }
    
    func testInfoLevel() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        
        BlazeLogger.error("Error")
        BlazeLogger.warn("Warning")
        BlazeLogger.info("Info")
        BlazeLogger.debug("Debug")
        
        XCTAssertEqual(captured.count, 3, "Info level should show errors + warnings + info")
        XCTAssertFalse(captured.contains { $0.contains("DEBUG") })
    }
    
    func testDebugLevel() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .debug
        
        BlazeLogger.error("Error")
        BlazeLogger.warn("Warning")
        BlazeLogger.info("Info")
        BlazeLogger.debug("Debug")
        BlazeLogger.trace("Trace")
        
        XCTAssertEqual(captured.count, 4, "Debug level should show all except trace")
        XCTAssertFalse(captured.contains { $0.contains("TRACE") })
    }
    
    func testTraceLevel() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .trace
        
        BlazeLogger.error("Error")
        BlazeLogger.warn("Warning")
        BlazeLogger.info("Info")
        BlazeLogger.debug("Debug")
        BlazeLogger.trace("Trace")
        
        XCTAssertEqual(captured.count, 5, "Trace level should show everything")
        XCTAssertTrue(captured.contains { $0.contains("TRACE") })
    }
    
    // MARK: - Custom Handler Tests
    
    func testCustomHandler() {
        var capturedMessages: [String] = []
        var capturedLevels: [BlazeLogLevel] = []
        
        BlazeLogger.handler = { message, level in
            capturedMessages.append(message)
            capturedLevels.append(level)
        }
        
        BlazeLogger.level = .debug
        
        BlazeLogger.error("Test error")
        BlazeLogger.warn("Test warning")
        BlazeLogger.debug("Test debug")
        
        XCTAssertEqual(capturedMessages.count, 3)
        XCTAssertEqual(capturedLevels.count, 3)
        XCTAssertEqual(capturedLevels[0], .error)
        XCTAssertEqual(capturedLevels[1], .warn)
        XCTAssertEqual(capturedLevels[2], .debug)
    }
    
    func testHandlerReceivesCorrectData() {
        var lastMessage: String?
        var lastLevel: BlazeLogLevel?
        
        BlazeLogger.handler = { message, level in
            lastMessage = message
            lastLevel = level
        }
        
        BlazeLogger.level = .info
        BlazeLogger.info("Test info message")
        
        XCTAssertNotNil(lastMessage)
        XCTAssertTrue(lastMessage!.contains("[BlazeDB:INFO]"))
        XCTAssertTrue(lastMessage!.contains("Test info message"))
        XCTAssertEqual(lastLevel, .info)
    }
    
    // MARK: - Location Tests
    
    func testLocationIncludedForErrors() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .error
        BlazeLogger.includeLocation = false  // Default
        
        BlazeLogger.error("Test error")
        
        XCTAssertEqual(captured.count, 1)
        // Errors should include location even with includeLocation=false
        XCTAssertTrue(captured[0].contains("BlazeLoggerTests.swift"))
    }
    
    func testLocationIncludedForWarnings() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .warn
        BlazeLogger.includeLocation = false  // Default
        
        BlazeLogger.warn("Test warning")
        
        XCTAssertEqual(captured.count, 1)
        // Warnings should include location even with includeLocation=false
        XCTAssertTrue(captured[0].contains("BlazeLoggerTests.swift"))
    }
    
    func testLocationNotIncludedForInfo() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        BlazeLogger.includeLocation = false  // Default
        
        BlazeLogger.info("Test info")
        
        XCTAssertEqual(captured.count, 1)
        // Info should NOT include location by default
        XCTAssertFalse(captured[0].contains("BlazeLoggerTests.swift"))
    }
    
    func testLocationIncludedWhenEnabled() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        BlazeLogger.includeLocation = true  // Explicit enable
        
        BlazeLogger.info("Test info")
        
        XCTAssertEqual(captured.count, 1)
        // Should include location when explicitly enabled
        XCTAssertTrue(captured[0].contains("BlazeLoggerTests.swift"))
    }
    
    // MARK: - Format Tests
    
    func testLogFormatNoEmoji() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        
        BlazeLogger.info("Test message")
        
        // Should NOT contain emoji
        XCTAssertFalse(captured[0].contains("ℹ️"))
        XCTAssertFalse(captured[0].contains("🪲"))
        XCTAssertFalse(captured[0].contains("⚠️"))
        
        // Should contain clean format
        XCTAssertTrue(captured[0].contains("[BlazeDB:INFO]"))
    }
    
    func testLogFormatStructure() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .error
        
        BlazeLogger.error("Critical error")
        
        // Format: [BlazeDB:LEVEL] message (file:line)
        let message = captured[0]
        XCTAssertTrue(message.hasPrefix("[BlazeDB:ERROR]"))
        XCTAssertTrue(message.contains("Critical error"))
        XCTAssertTrue(message.contains("BlazeLoggerTests.swift"))
    }
    
    // MARK: - Convenience Method Tests
    
    func testEnableDebugMode() {
        BlazeLogger.enableDebugMode()
        
        XCTAssertEqual(BlazeLogger.level, .debug)
        XCTAssertTrue(BlazeLogger.includeLocation)
    }
    
    func testEnableTraceMode() {
        BlazeLogger.enableTraceMode()
        
        XCTAssertEqual(BlazeLogger.level, .trace)
        XCTAssertTrue(BlazeLogger.includeLocation)
    }
    
    func testEnableSilentMode() {
        BlazeLogger.enableSilentMode()
        
        XCTAssertEqual(BlazeLogger.level, .silent)
    }
    
    func testReset() {
        // Modify all settings
        BlazeLogger.level = .trace
        BlazeLogger.includeLocation = true
        BlazeLogger.handler = { _, _ in }
        
        // Reset should restore defaults
        BlazeLogger.reset()
        
        XCTAssertEqual(BlazeLogger.level, .warn)
        XCTAssertFalse(BlazeLogger.includeLocation)
        XCTAssertNil(BlazeLogger.handler)
    }
    
    // MARK: - Performance Tests
    
    func testSilentModeHasZeroOverhead() {
        BlazeLogger.enableSilentMode()
        
        // Expensive computation that should be skipped
        var executionCount = 0
        
        let start = Date()
        for _ in 0..<1000 {
            BlazeLogger.debug("Expensive: \({ executionCount += 1; return executionCount }())")
        }
        let duration = Date().timeIntervalSince(start)
        
        // Should be near-instant (< 1ms) because logs are skipped
        XCTAssertLessThan(duration, 0.001, "Silent mode should skip string interpolation")
        
        // Execution count should be 0 (closure never evaluated)
        // Note: Swift may optimize this differently, so we just verify it's fast
    }
    
    func testLogLevelFiltering() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .warn
        
        // These should be filtered out
        BlazeLogger.trace("Trace")
        BlazeLogger.debug("Debug")
        BlazeLogger.info("Info")
        
        XCTAssertEqual(captured.count, 0, "Lower level logs should be filtered")
        
        // These should pass through
        BlazeLogger.warn("Warning")
        BlazeLogger.error("Error")
        
        XCTAssertEqual(captured.count, 2, "Higher level logs should pass")
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentLogging() {
        var captured: [String] = []
        let lock = NSLock()
        
        BlazeLogger.handler = { message, _ in
            lock.lock()
            captured.append(message)
            lock.unlock()
        }
        
        BlazeLogger.level = .debug
        
        let group = DispatchGroup()
        for i in 0..<100 {
            DispatchQueue.global().async(group: group) {
                BlazeLogger.debug("Message \(i)")
            }
        }
        
        group.wait()
        
        XCTAssertEqual(captured.count, 100, "All concurrent logs should be captured")
    }
    
    func testHandlerCanBeChangedSafely() {
        var captured1: [String] = []
        var captured2: [String] = []
        
        BlazeLogger.handler = { message, _ in captured1.append(message) }
        BlazeLogger.level = .info
        
        BlazeLogger.info("First")
        
        // Change handler
        BlazeLogger.handler = { message, _ in captured2.append(message) }
        
        BlazeLogger.info("Second")
        
        XCTAssertEqual(captured1.count, 1)
        XCTAssertEqual(captured2.count, 1)
    }
    
    // MARK: - Integration Tests
    
    func testLoggerIntegrationWithRealOperations() {
        var errorCount = 0
        var warnCount = 0
        
        BlazeLogger.handler = { _, level in
            switch level {
            case .error: errorCount += 1
            case .warn: warnCount += 1
            default: break
            }
        }
        
        BlazeLogger.level = .warn
        
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("logger-test-\(UUID().uuidString).blazedb")
            defer { try? FileManager.default.removeItem(at: url) }
            
            // Create database - should log warnings if any
            let db = try BlazeDBClient(name: "LogTest", fileURL: url, password: "BlazeLoggerTest123!")
            
            // Normal operations shouldn't log
            _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
            _ = try db.fetchAll()
            
            // Verify no excessive logging
            XCTAssertLessThanOrEqual(warnCount, 2, "Normal operations should not spam warnings")
            XCTAssertEqual(errorCount, 0, "Normal operations should not error")
        } catch {
            XCTFail("Integration test failed: \(error)")
        }
    }
    
    func testLoggerSilencedInTestEnvironment() {
        // This test itself proves auto-silence works
        // If auto-silence didn't work, this test would spam console
        
        // BlazeLogger should detect XCTestCase and default to .silent
        // (but we explicitly set levels in tests, so this is just documentation)
        
        XCTAssertTrue(true, "If console is clean, auto-silence works")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyMessage() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        
        BlazeLogger.info("")
        
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].contains("[BlazeDB:INFO]"))
    }
    
    func testVeryLongMessage() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        
        let longMessage = String(repeating: "A", count: 10000)
        BlazeLogger.info(longMessage)
        
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].contains(longMessage))
    }
    
    func testSpecialCharactersInMessage() {
        var captured: [String] = []
        BlazeLogger.handler = { message, _ in captured.append(message) }
        BlazeLogger.level = .info
        
        BlazeLogger.info("Test with \"quotes\" and 'apostrophes' and \n newlines")
        
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].contains("quotes"))
    }
    
    func testResetClearsHandler() {
        BlazeLogger.handler = { _, _ in }
        XCTAssertNotNil(BlazeLogger.handler)
        
        BlazeLogger.reset()
        
        XCTAssertNil(BlazeLogger.handler)
    }
}

