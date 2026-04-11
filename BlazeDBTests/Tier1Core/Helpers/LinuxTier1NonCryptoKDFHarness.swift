//  LinuxTier1NonCryptoKDFHarness.swift
//  BlazeDBTests
//
//  WARNING: TEST-ONLY CI RUNTIME HARNESS.
//  This is intentionally loud so it is not mistaken for product behavior.

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// Linux-only runtime relief harness for non-crypto Tier1 suites.
///
/// Why this exists:
/// - Tier1 query/CRUD suites validate behavior, not PBKDF2 cost tuning.
/// - Linux Tier1 wall time is dominated by repeated DB init KDF overhead.
///
/// Guardrail:
/// - Crypto/security suites must NOT inherit from this class.
open class LinuxTier1NonCryptoKDFHarness: XCTestCase {
    override open class func setUp() {
        super.setUp()
        #if os(Linux)
        KeyManager.setTestPBKDF2IterationsOverride(10_000)
        #endif
    }

    override open class func tearDown() {
        #if os(Linux)
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        #endif
        super.tearDown()
    }
}
