//  NonCryptoKDFHarness.swift
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

/// Cross-platform runtime relief harness for non-crypto Tier1 suites.
///
/// Why this exists:
/// - Tier1 query/CRUD suites validate behavior, not PBKDF2 cost tuning.
/// - Reduced iterations bound repeated DB init KDF overhead during each suite.
///
/// Guardrail:
/// - Crypto, key-management, encryption and KDF suites must NOT inherit this class.
/// - The override is process-global: even non-adopting security suites see 10,000
///   while it is active. Run security suites outside an active harness lifecycle.
open class NonCryptoKDFHarness: XCTestCase {
    nonisolated(unsafe) private static var previousIterationsOverride: Int?

    override open class func setUp() {
        super.setUp()
        previousIterationsOverride = KeyManager.currentTestPBKDF2IterationsOverride()
        KeyManager.setTestPBKDF2IterationsOverride(10_000)
    }

    override open class func tearDown() {
        KeyManager.setTestPBKDF2IterationsOverride(previousIterationsOverride)
        super.tearDown()
    }
}

@available(*, deprecated, renamed: "NonCryptoKDFHarness")
public typealias LinuxTier1NonCryptoKDFHarness = NonCryptoKDFHarness
