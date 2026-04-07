//
//  ConstantTimeEqualsOverflowTests.swift
//  BlazeDB
//
//  Validates that signature verification does not crash when the stored
//  signature has a length that differs from the expected HMAC-SHA256
//  output (32 bytes) by >= 256 bytes.
//

import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import BlazeDBCore

final class ConstantTimeEqualsOverflowTests: XCTestCase {

    private func makeMinimalLayout() -> StorageLayout {
        StorageLayout(
            indexMap: [:],
            nextPageIndex: 0,
            secondaryIndexes: [:]
        )
    }

    /// A corrupted or malicious .meta file could contain a signature field
    /// of arbitrary length. HMAC-SHA256 always produces 32 bytes. When the
    /// stored signature length XOR'd with 32 exceeds 255, UInt8.init traps.
    ///
    /// Example: signature = 300 bytes → 32 ^ 300 = 284 → UInt8(284) → fatal error
    ///
    /// Expected failure on current code:
    ///   StorageLayout.constantTimeEquals is called from SecureLayout.verify(using:).
    ///   Line 931: `var diff = UInt8(lhs.count ^ rhs.count)` traps when the
    ///   XOR result exceeds 255. This is a runtime crash, not a thrown error,
    ///   so the catch block in verify(using:) does not help.
    func testVerifyDoesNotCrashWithOversizedSignature() {
        let key = SymmetricKey(size: .bits256)
        let layout = makeMinimalLayout()

        let oversizedSignature = Data(repeating: 0xFF, count: 300)

        let tampered = StorageLayout.SecureLayout(
            secureLayoutVersion: 2,
            layout: layout,
            encodingFormat: nil,
            signedPayload: Data("test".utf8),
            signature: oversizedSignature,
            signedAt: Date()
        )

        // This should return false (signature mismatch), not crash.
        // On current code, this traps in UInt8.init at constantTimeEquals line 931.
        let result = tampered.verify(using: key)

        XCTAssertFalse(result, "Oversized signature should fail verification, not crash")
    }

    /// Edge case: signature of 288 bytes. 32 ^ 288 = 256 → UInt8(256) traps.
    /// This is the exact boundary where the overflow begins.
    func testVerifyDoesNotCrashAtExactOverflowBoundary() {
        let key = SymmetricKey(size: .bits256)
        let layout = makeMinimalLayout()

        let boundarySignature = Data(repeating: 0xAA, count: 288)

        let tampered = StorageLayout.SecureLayout(
            secureLayoutVersion: 2,
            layout: layout,
            encodingFormat: nil,
            signedPayload: Data("test".utf8),
            signature: boundarySignature,
            signedAt: Date()
        )

        let result = tampered.verify(using: key)

        XCTAssertFalse(result, "Boundary signature should fail verification, not crash")
    }
}
