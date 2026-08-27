//
//  KDFTruthfulnessTests.swift
//  BlazeDBTests
//
//  Regression tests for production PBKDF2 constants and deterministic derivation (#273).
//

import XCTest
@testable import BlazeDBCore

final class KDFTruthfulnessTests: XCTestCase {
    func testProductionPBKDF2IterationConstantIs600k() {
        XCTAssertEqual(KeyManager.productionPBKDF2Iterations, 600_000)
        XCTAssertEqual(KeyManager.xctestPBKDF2Iterations, 100_000)
    }

    func testPBKDF2DerivationIsDeterministicForFixedInputs() throws {
        let salt = Data(repeating: 0x42, count: 16)
        let a = try KeyManager.deriveKeyPBKDF2(
            password: Data("fixed-pass".utf8),
            salt: salt,
            iterations: 1_000,
            keyLength: 32
        )
        let b = try KeyManager.deriveKeyPBKDF2(
            password: Data("fixed-pass".utf8),
            salt: salt,
            iterations: 1_000,
            keyLength: 32
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }
}
