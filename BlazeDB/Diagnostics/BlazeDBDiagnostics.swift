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
}
