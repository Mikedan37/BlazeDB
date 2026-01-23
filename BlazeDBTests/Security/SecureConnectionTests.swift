//
//  SecureConnectionTests.swift
//  BlazeDBTests
//
//  Tests for SecureConnection handshake and encryption
//

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDBCore

final class SecureConnectionTests: XCTestCase {
    
    func testHandshakeMessageEncoding() throws {
        let nodeId = UUID()
        let publicKey = P256.KeyAgreement.PrivateKey().publicKey
        
        let message = SecureConnection.HandshakeMessage(
            protocol: "blazedb/1.0",
            nodeId: nodeId,
            database: "bugs",
            publicKey: publicKey.rawRepresentation,
            capabilities: SecureConnection.HandshakeMessage.Capabilities(rawValue: 0b00000011), // e2e + compression
            timestamp: Date()
        )
        
        // Create connection for encoding/decoding
        let connection = SecureConnection(
            connection: NWConnection(host: "localhost", port: 8080, using: .tcp),
            nodeId: nodeId,
            database: "bugs"
        )
        
        let encoded = try connection.encodeHandshake(message)
        XCTAssertFalse(encoded.isEmpty)
        
        // Decode
        let decoded = try connection.decodeHandshake(encoded)
        
        XCTAssertEqual(decoded.protocol, "blazedb/1.0")
        XCTAssertEqual(decoded.nodeId, nodeId)
        XCTAssertEqual(decoded.database, "bugs")
        XCTAssertEqual(decoded.publicKey, publicKey.rawRepresentation)
    }
    
    func testKeyDerivation() throws {
        // Generate two key pairs
        let clientPrivateKey = P256.KeyAgreement.PrivateKey()
        let clientPublicKey = clientPrivateKey.publicKey
        
        let serverPrivateKey = P256.KeyAgreement.PrivateKey()
        let serverPublicKey = serverPrivateKey.publicKey
        
        // Derive shared secret on both sides
        let clientSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        let serverSecret = try serverPrivateKey.sharedSecretFromKeyAgreement(with: clientPublicKey)
        
        // Shared secrets should match
        XCTAssertEqual(clientSecret.withUnsafeBytes { Data($0) }, serverSecret.withUnsafeBytes { Data($0) })
        
        // Derive symmetric keys
        let salt = "blazedb-sync-v1".data(using: .utf8)!
        let info = ["bugs", "bugs"].sorted().joined(separator: ":").data(using: .utf8)!
        
        let clientKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: clientSecret,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        
        let serverKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: serverSecret,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        
        // Keys should match
        XCTAssertEqual(clientKey.rawRepresentation, serverKey.rawRepresentation)
    }
    
    func testEncryptionDecryption() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Hello, BlazeDB!".data(using: .utf8)!
        
        // Encrypt
        let sealed = try AES.GCM.seal(plaintext, using: key)
        let encrypted = sealed.combined!
        
        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertTrue(encrypted.count > plaintext.count)  // Should have nonce + tag
        
        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        
        XCTAssertEqual(decrypted, plaintext)
    }
    
    func testChallengeResponse() throws {
        let key = SymmetricKey(size: .bits256)
        let challenge = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        // Compute response
        let response = HMAC<SHA256>.authenticationCode(
            for: challenge,
            using: key
        )
        
        // Verify
        let expected = HMAC<SHA256>.authenticationCode(
            for: challenge,
            using: key
        )
        
        XCTAssertEqual(response, expected)
    }
}


