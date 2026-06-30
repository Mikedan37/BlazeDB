//
//  DatabaseSessionStore.swift
//  BlazeDBCore
//
//  Process-scoped verified encryption sessions. See DATABASE_SESSION_KEY_LIFECYCLE.md.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

struct DatabaseSessionEntry {
    let derivedKey: SymmetricKey
    let verifier: Data
    let kdfCacheKey: String
    let salt: Data
}

enum DatabaseSessionStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: DatabaseSessionEntry] = [:]

    static func session(for path: String) -> DatabaseSessionEntry? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[path]
    }

    static func installSession(
        path: String,
        derivedKey: SymmetricKey,
        password: String,
        salt: Data,
        kdfCacheKey: String
    ) {
        let verifier = makeVerifier(derivedKey: derivedKey, password: password, salt: salt)
        lock.lock()
        defer { lock.unlock() }
        sessions[path] = DatabaseSessionEntry(
            derivedKey: derivedKey,
            verifier: verifier,
            kdfCacheKey: kdfCacheKey,
            salt: salt
        )
    }

    /// Removes the session for `path`. Returns the associated KeyManager cache key, if any.
    @discardableResult
    static func removeSession(for path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return sessions.removeValue(forKey: path)?.kdfCacheKey
    }

    static func removeAllSessions() {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeAll(keepingCapacity: false)
    }

    static func verifyPassword(_ password: String, session: DatabaseSessionEntry) -> Bool {
        let candidate = makeVerifier(derivedKey: session.derivedKey, password: password, salt: session.salt)
        return constantTimeEqual(candidate, session.verifier)
    }

    static func makeVerifier(derivedKey: SymmetricKey, password: String, salt: Data) -> Data {
        var message = Data(password.utf8)
        message.append(salt)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: derivedKey))
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhs.count {
            diff |= lhs[i] ^ rhs[i]
        }
        return diff == 0
    }
}
