//
//  CICDDetection.swift
//  BlazeDB
//
//  Utility to detect if tests are running in CI/CD environment
//

import Foundation

/// Utility to detect if code is running in CI/CD environment (GitHub Actions, etc.)
public enum CICDDetection {
    /// Returns true if running in CI/CD environment
    public static var isRunningInCI: Bool {
        let env = ProcessInfo.processInfo.environment
        
        // GitHub Actions sets CI=true and GITHUB_ACTIONS=true
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            return true
        }
        
        // Other CI systems
        if env["CI"] == "true" {
            return true
        }
        
        // Explicit override for local testing (if needed)
        if env["BLAZEDB_FORCE_CI_MODE"] == "1" {
            return true
        }
        
        return false
    }
    
    /// Returns true if stress tests should run
    public static var shouldRunStressTests: Bool {
        return isRunningInCI
    }
}

