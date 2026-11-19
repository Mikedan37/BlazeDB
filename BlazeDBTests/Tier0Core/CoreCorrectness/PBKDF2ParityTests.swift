//
//  PBKDF2ParityTests.swift
//  BlazeDB_Tier0 — the password KDF must keep deriving the exact bytes it always has,
//  or existing databases stop opening.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PBKDF2ParityTests: XCTestCase {
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// PBKDF2-HMAC-SHA256 known answers (RFC 7914 §11 and the common RFC 6070-style set),
    /// cross-checked with OpenSSL's PKCS5_PBKDF2_HMAC.
    func testProductionKDFMatchesKnownAnswers() throws {
        let vectors: [(String, String, Int, Int, String)] = [
            ("password", "salt", 1, 32, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
            ("password", "salt", 2, 32, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
            ("password", "salt", 4096, 32, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"),
            ("passwd", "salt", 1, 64, "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"),
            ("Password", "NaCl", 80_000, 64, "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"),
            ("passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 40, "348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9"),
        ]
        for (password, salt, iterations, length, expected) in vectors {
            let key = try KeyManager.deriveKeyPBKDF2(password: Data(password.utf8), salt: Data(salt.utf8),
                                                     iterations: iterations, keyLength: length)
            XCTAssertEqual(hex(key), expected, "\(password)/\(salt)/\(iterations)")
        }
    }

    /// The production KDF must equal the Swift loop every existing database was keyed with.
    func testProductionKDFMatchesPreviousImplementation() throws {
        var generator = SystemRandomNumberGenerator()
        for i in 0..<64 {
            let password = Data((0..<(1 + i % 40)).map { _ in UInt8.random(in: 0...255, using: &generator) })
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
            let iterations = 1 + (i * 37) % 300
            let length = [16, 32, 33, 64][i % 4]
            XCTAssertEqual(
                try KeyManager.deriveKeyPBKDF2(password: password, salt: salt, iterations: iterations, keyLength: length),
                try KeyManager.swiftPBKDF2(password: password, salt: salt, iterations: iterations, keyLength: length),
                "case \(i): iterations \(iterations), length \(length)"
            )
        }
        // One case at a database-like cost: UTF-8 password, 16-byte salt, 32-byte key.
        let password = Data("Pässwörd-Ünïcode-123!".utf8)
        let salt = Data((0..<16).map { UInt8(truncatingIfNeeded: $0 &* 29 &+ 7) })
        XCTAssertEqual(
            try KeyManager.deriveKeyPBKDF2(password: password, salt: salt, iterations: 10_000, keyLength: 32),
            try KeyManager.swiftPBKDF2(password: password, salt: salt, iterations: 10_000, keyLength: 32)
        )
    }

    func testInvalidParametersThrowInsteadOfTrapping() {
        XCTAssertThrowsError(try KeyManager.deriveKeyPBKDF2(password: Data("p".utf8), salt: Data("s".utf8), iterations: 0, keyLength: 32))
        XCTAssertThrowsError(try KeyManager.deriveKeyPBKDF2(password: Data("p".utf8), salt: Data("s".utf8), iterations: 1, keyLength: 0))
    }
}
