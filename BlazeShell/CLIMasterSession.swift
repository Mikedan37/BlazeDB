//
//  CLIMasterSession.swift
//  BlazeCLICore
//

import Foundation

public enum CLIMasterSession {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var secretsByPathHash: [String: String] = [:]

    public static func setSessionSecret(pathHash: String, secret: String) {
        lock.lock()
        defer { lock.unlock() }
        secretsByPathHash[pathHash] = secret
    }

    public static func sessionSecret(pathHash: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return secretsByPathHash[pathHash]
    }

    public static func removeSessionSecret(pathHash: String) {
        lock.lock()
        defer { lock.unlock() }
        secretsByPathHash.removeValue(forKey: pathHash)
    }

    public static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        secretsByPathHash.removeAll()
    }
}
