//
//  KeyUnlockProvider.swift
//  BlazeDB
//
//  Platform-neutral protocol for key unlocking (biometric/auth)
//  Allows BlazeDB to work on Linux without LocalAuthentication dependency
//
//  Created by Auto on 12/14/25.
//

import Foundation

/// Protocol for key unlocking operations (biometric authentication, etc.)
/// Platform-neutral abstraction that allows different implementations per platform
public protocol KeyUnlockProvider {
    /// Attempt to unlock a key with the given reason
    /// - Parameter reason: Human-readable reason for the unlock request
    /// - Throws: If unlock fails or is not available
    func unlockKey(reason: String) async throws
    
    /// Check if key unlocking is available on this platform
    /// - Returns: true if unlock capability is available, false otherwise
    func isAvailable() -> Bool
}

#if canImport(LocalAuthentication)
import LocalAuthentication

/// Apple platform implementation using LocalAuthentication
/// Provides biometric authentication (Face ID, Touch ID) on iOS/macOS
public final class AppleKeyUnlockProvider: KeyUnlockProvider {
    private let context: LAContext
    
    public init() {
        self.context = LAContext()
    }
    
    public func unlockKey(reason: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if success {
                    continuation.resume()
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: KeyUnlockError.unlockFailed("Unknown error"))
                }
            }
        }
    }
    
    public func isAvailable() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}

/// Default provider type for Apple platforms
public typealias DefaultKeyUnlockProvider = AppleKeyUnlockProvider

#else

/// Headless/server implementation for Linux and other non-Apple platforms
/// Performs no actual authentication - always succeeds (for server use cases)
/// In production, you may want to validate via environment variable or config
public final class HeadlessKeyUnlockProvider: KeyUnlockProvider {
    private let allowUnlock: Bool
    
    /// Initialize headless provider
    /// - Parameter allowUnlock: If true, unlock always succeeds. If false, unlock always fails.
    ///   Defaults to true for server/headless environments where no UI is available.
    public init(allowUnlock: Bool = true) {
        self.allowUnlock = allowUnlock
    }
    
    public func unlockKey(reason: String) async throws {
        guard allowUnlock else {
            throw KeyUnlockError.unlockFailed("Key unlock is disabled in headless mode")
        }
        // In headless/server mode, unlock always succeeds
        // No biometric authentication available
        return
    }
    
    public func isAvailable() -> Bool {
        // In headless mode, "availability" means the provider is configured to allow unlocks
        return allowUnlock
    }
}

/// Default provider type for non-Apple platforms
public typealias DefaultKeyUnlockProvider = HeadlessKeyUnlockProvider

#endif

/// Errors that can occur during key unlock operations
public enum KeyUnlockError: Error, LocalizedError {
    case unlockFailed(String)
    case notAvailable
    
    public var errorDescription: String? {
        switch self {
        case .unlockFailed(let reason):
            return "Key unlock failed: \(reason)"
        case .notAvailable:
            return "Key unlock is not available on this platform"
        }
    }
}

