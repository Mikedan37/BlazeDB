//
//  BlazeDBDiagnostics.swift
//  BlazeDBCore
//
//  Read-only environment facts for benchmarks and support tooling.
//

import Foundation

public enum BlazeDBDiagnostics {
    public static var pbkdf2IterationCount: Int {
        KeyManager.pbkdf2Iterations
    }

    public static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    public static var openProfilingEnabled: Bool {
        OpenProfileCollector.isEnabled
    }

    /// Monotonic uptime in seconds (cross-platform; safe on Linux/Android CI).
    public static func monotonicSeconds() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
