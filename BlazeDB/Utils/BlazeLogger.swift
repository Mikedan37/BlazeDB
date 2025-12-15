//  BlazeLogger.swift
//  BlazeDB
//  Created by Michael Danylchuk on 11/6/25.

import Foundation

/// Log level for BlazeDB operations
public enum BlazeLogLevel: Int, Comparable {
    case silent = 0
    case error = 1
    case warn = 2
    case info = 3
    case debug = 4
    case trace = 5
    
    public static func < (lhs: BlazeLogLevel, rhs: BlazeLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Centralized logging for BlazeDB
/// Thread-safe via nonisolated(unsafe) for performance (logging must be callable from anywhere)
public final class BlazeLogger {
    /// Global log level - set this to control verbosity
    /// Default is .warn (quiet unless problems) - set to .debug or .trace for development
    public nonisolated(unsafe) static var level: BlazeLogLevel = {
        #if DEBUG
        // Auto-detect test environment and silence
        if NSClassFromString("XCTestCase") != nil {
            return .silent
        }
        #endif
        return .warn
    }()
    
    /// Custom log handler - override for custom logging systems
    public nonisolated(unsafe) static var handler: ((String, BlazeLogLevel) -> Void)?
    
    /// Include file:line location in logs (default: only for warn/error)
    /// Set to true to always include location for debugging
    public nonisolated(unsafe) static var includeLocation: Bool = false
    
    /// Capture stack traces for error/warn logs (default: OFF for performance)
    /// ⚠️ WARNING: Stack capture adds ~1-2ms overhead per log call!
    /// Enable only for debugging critical issues in development.
    public nonisolated(unsafe) static var captureStackTraces: Bool = false
    
    /// Maximum stack frames to include in logs (default: 5)
    public nonisolated(unsafe) static var maxStackFrames: Int = 5
    
    // MARK: - Convenience Methods
    
    /// Enable verbose logging for development/debugging
    public static func enableDebugMode() {
        level = .debug
        includeLocation = true
    }
    
    /// Enable maximum verbosity (trace all operations + stack traces)
    public static func enableTraceMode() {
        level = .trace
        includeLocation = true
        captureStackTraces = true
    }
    
    /// Disable all logging (production mode)
    public static func enableSilentMode() {
        level = .silent
    }
    
    /// Reset to defaults (warnings + errors only)
    public static func reset() {
        level = .warn
        includeLocation = false
        handler = nil
    }
    
    // MARK: - Logging Methods
    
    /// Log at trace level (most verbose)
    /// Uses @autoclosure to avoid string interpolation overhead when logging is disabled
    public static func trace(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        guard level >= .trace else { return }  // Early return before evaluating message
        log(message(), level: .trace, includeStack: false, file: file, line: line)
    }
    
    /// Log at debug level
    /// Uses @autoclosure to avoid string interpolation overhead when logging is disabled
    public static func debug(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        guard level >= .debug else { return }  // Early return before evaluating message
        log(message(), level: .debug, includeStack: false, file: file, line: line)
    }
    
    /// Log at info level
    /// Uses @autoclosure to avoid string interpolation overhead when logging is disabled
    public static func info(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        guard level >= .info else { return }  // Early return before evaluating message
        log(message(), level: .info, includeStack: false, file: file, line: line)
    }
    
    /// Log at warn level
    /// Uses @autoclosure to avoid string interpolation overhead when logging is disabled
    /// - Parameters:
    ///   - message: Log message (lazy-evaluated)
    ///   - includeStack: Force stack trace capture (even if captureStackTraces is false)
    ///   - file: Source file (auto-filled)
    ///   - line: Source line (auto-filled)
    public static func warn(_ message: @autoclosure () -> String, 
                           includeStack: Bool = false,
                           file: String = #file, 
                           line: Int = #line) {
        guard level >= .warn else { return }  // Early return before evaluating message
        log(message(), level: .warn, includeStack: includeStack, file: file, line: line)
    }
    
    /// Log at error level
    /// Uses @autoclosure to avoid string interpolation overhead when logging is disabled
    /// - Parameters:
    ///   - message: Log message (lazy-evaluated)
    ///   - error: Optional Error to include
    ///   - includeStack: Force stack trace capture (even if captureStackTraces is false)
    ///   - file: Source file (auto-filled)
    ///   - line: Source line (auto-filled)
    public static func error(_ message: @autoclosure () -> String,
                            error: Error? = nil,
                            includeStack: Bool = false,
                            file: String = #file, 
                            line: Int = #line) {
        guard self.level >= .error else { return }  // Early return before evaluating message
        var msg = message()
        if let error = error {
            msg += " | Error: \(error.localizedDescription)"
        }
        log(msg, level: .error, includeStack: includeStack, file: file, line: line)
    }
    
    // MARK: - Internal
    
    private static func log(_ message: String, 
                           level: BlazeLogLevel, 
                           includeStack: Bool = false,
                           file: String, 
                           line: Int) {
        guard self.level >= level else { return }
        
        let prefix: String
        switch level {
        case .trace:
            prefix = "TRACE"
        case .debug:
            prefix = "DEBUG"
        case .info:
            prefix = "INFO"
        case .warn:
            prefix = "WARN"
        case .error:
            prefix = "ERROR"
        case .silent:
            return
        }
        
        // Include location for errors/warnings, or if explicitly enabled
        let shouldIncludeLocation = includeLocation || level <= .warn
        let location = shouldIncludeLocation ? " (\((file as NSString).lastPathComponent):\(line))" : ""
        
        var logMessage = "[BlazeDB:\(prefix)] \(message)\(location)"
        
        // ✅ Smart stack trace capture (only when needed!)
        if includeStack || captureStackTraces {
            let stackTrace = captureStackTrace()
            if !stackTrace.isEmpty {
                logMessage += "\n\(stackTrace)"
            }
        }
        
        // Use custom handler if set, otherwise print
        if let handler = handler {
            handler(logMessage, level)
        } else {
            print(logMessage)
        }
    }
    
    /// Capture and format stack trace (expensive - only call when needed!)
    private static func captureStackTrace() -> String {
        let symbols = Thread.callStackSymbols
        
        // Skip internal frames:
        // 0: captureStackTrace()
        // 1: log()
        // 2: error()/warn()
        // 3: Actual caller ← Start here!
        let relevantFrames = symbols
            .dropFirst(3)
            .prefix(maxStackFrames)
            .enumerated()
            .map { index, frame in
                // Clean up frame for readability
                let cleaned = frame
                    .replacingOccurrences(of: #"\s+BlazeDB\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                return "   #\(index): \(cleaned)"
            }
            .joined(separator: "\n")
        
        return relevantFrames.isEmpty ? "" : "   Stack trace:\n\(relevantFrames)"
    }
}

