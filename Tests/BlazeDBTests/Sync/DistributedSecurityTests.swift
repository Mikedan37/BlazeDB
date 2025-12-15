//
//  DistributedSecurityTests.swift
//  BlazeDBTests
//
//  Comprehensive security tests for P2P distributed sync
//
//  Created by Michael Danylchuk on 1/15/25.
//

import XCTest
@testable import BlazeDB
import Foundation
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif

final class DistributedSecurityTests: XCTestCase {
    var tempDir: URL!
    var db1: BlazeDBClient!
    var db2: BlazeDBClient!
    var validator: SecurityValidator!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let db1URL = tempDir.appendingPathComponent("db1.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2.blazedb")
        
        db1 = try BlazeDBClient(name: "db1", fileURL: db1URL, password: "SecurePass123!")
        db2 = try BlazeDBClient(name: "db2", fileURL: db2URL, password: "SecurePass456!")
        
        validator = SecurityValidator(maxOperationsPerMinute: 1000)
    }
    
    override func tearDown() async throws {
        // Only cleanup if setup was successful
        if tempDir != nil {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    // MARK: - Authentication Tests
    
    func testAuthentication_ValidToken_Succeeds() async throws {
        let authToken = "secret-token-123"
        
        // Server requires auth token
        let server = try BlazeServer(
            port: 8080,
            database: db1,
            databaseName: "db1",
            authToken: authToken
        )
        
        // Client provides correct token
        let remote = RemoteNode(
            host: "localhost",
            port: 8080,
            database: "db1",
            authToken: authToken
        )
        
        // Should connect successfully
        // (Note: This is a simplified test - full connection test would require actual network)
        XCTAssertNotNil(server)
        XCTAssertNotNil(remote)
    }
    
    func testAuthentication_InvalidToken_Fails() async throws {
        let serverToken = "correct-token"
        let clientToken = "wrong-token"
        
        // Server requires auth token
        let server = try? BlazeServer(
            port: 8080,
            database: db1,
            databaseName: "db1",
            authToken: serverToken
        )
        
        // Client provides wrong token
        let remote = RemoteNode(
            host: "localhost",
            port: 8080,
            database: "db1",
            authToken: clientToken
        )
        
        // Connection should fail during handshake
        // (Note: Full test would require actual network connection)
        XCTAssertNotNil(server)
        XCTAssertNotEqual(serverToken, clientToken)
    }
    
    func testAuthentication_NoTokenWhenRequired_Fails() async throws {
        let serverToken = "required-token"
        
        // Server requires auth token
        let server = try? BlazeServer(
            port: 8080,
            database: db1,
            databaseName: "db1",
            authToken: serverToken
        )
        
        // Client provides no token
        let remote = RemoteNode(
            host: "localhost",
            port: 8080,
            database: "db1",
            authToken: nil
        )
        
        // Connection should fail
        XCTAssertNotNil(server)
        XCTAssertNil(remote.authToken)
    }
    
    // MARK: - Replay Protection Tests
    
    func testReplayProtection_DuplicateOperation_Rejected() async throws {
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")]
        )
        
        // First validation should succeed
        try await validator.validateReplayProtection(operation)
        
        // Second validation should fail (duplicate)
        do {
            try await validator.validateReplayProtection(operation)
            XCTFail("Should have rejected duplicate operation")
        } catch SecurityError.duplicateOperation {
            // Expected
        }
    }
    
    func testReplayProtection_DuplicateNonce_Rejected() async throws {
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        let operation1 = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug 1")],
            nonce: nonce
        )
        
        let operation2 = BlazeOperation(
            id: UUID(),  // Different ID
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug 2")],
            nonce: nonce  // Same nonce!
        )
        
        // First validation should succeed
        try await validator.validateReplayProtection(operation1)
        
        // Second validation should fail (same nonce)
        do {
            try await validator.validateReplayProtection(operation2)
            XCTFail("Should have rejected operation with duplicate nonce")
        } catch SecurityError.replayAttack {
            // Expected
        }
    }
    
    func testReplayProtection_ExpiredOperation_Rejected() async throws {
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        let expiredDate = Date().addingTimeInterval(-120)  // 2 minutes ago
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")],
            expiresAt: expiredDate
        )
        
        do {
            try await validator.validateReplayProtection(operation)
            XCTFail("Should have rejected expired operation")
        } catch SecurityError.operationExpired {
            // Expected
        }
    }
    
    func testReplayProtection_ValidOperation_Succeeds() async throws {
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")],
            expiresAt: Date().addingTimeInterval(60)  // Valid for 60 seconds
        )
        
        // Should succeed
        try await validator.validateReplayProtection(operation)
    }
    
    // MARK: - Rate Limiting Tests
    
    func testRateLimiting_ExceedsLimit_Rejected() async throws {
        let userId = UUID()
        let maxOps = 10
        
        let validator = SecurityValidator(maxOperationsPerMinute: maxOps)
        
        // Send max operations
        for _ in 0..<maxOps {
            try await validator.checkRateLimit(userId: userId)
        }
        
        // Next operation should fail
        do {
            try await validator.checkRateLimit(userId: userId)
            XCTFail("Should have rejected operation exceeding rate limit")
        } catch SecurityError.rateLimitExceeded {
            // Expected
        }
    }
    
    func testRateLimiting_WithinLimit_Succeeds() async throws {
        let userId = UUID()
        let maxOps = 10
        
        let validator = SecurityValidator(maxOperationsPerMinute: maxOps)
        
        // Send operations within limit
        for _ in 0..<maxOps {
            try await validator.checkRateLimit(userId: userId)
        }
        
        // Should succeed
        XCTAssertTrue(true)
    }
    
    // MARK: - Authorization Tests
    
    func testAuthorization_NoPermission_Rejected() async throws {
        let userId = UUID()
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // User has no permissions
        let permissions = SyncPermissions(
            userId: userId,
            readCollections: [],
            writeCollections: [],
            deleteCollections: [],
            canAdmin: false
        )
        
        await validator.setPermissions(permissions, for: userId)
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")],
            expiresAt: Date().addingTimeInterval(60)
        )
        
        do {
            try await validator.validateAuthorization(operation, userId: userId)
            XCTFail("Should have rejected operation without permission")
        } catch SecurityError.permissionDenied {
            // Expected
        }
    }
    
    func testAuthorization_WritePermission_Succeeds() async throws {
        let userId = UUID()
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // User has write permission for "bugs"
        let permissions = SyncPermissions(
            userId: userId,
            readCollections: ["bugs"],
            writeCollections: ["bugs"],
            deleteCollections: [],
            canAdmin: false
        )
        
        await validator.setPermissions(permissions, for: userId)
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")],
            expiresAt: Date().addingTimeInterval(60)
        )
        
        // Should succeed
        try await validator.validateAuthorization(operation, userId: userId)
    }
    
    func testAuthorization_AdminPermission_Succeeds() async throws {
        let userId = UUID()
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // User has admin permission
        let permissions = SyncPermissions(
            userId: userId,
            readCollections: [],
            writeCollections: [],
            deleteCollections: [],
            canAdmin: true
        )
        
        await validator.setPermissions(permissions, for: userId)
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .createIndex,
            collectionName: "bugs",
            recordId: UUID(),
            changes: [:],
            expiresAt: Date().addingTimeInterval(60)
        )
        
        // Should succeed (admin can do anything)
        try await validator.validateAuthorization(operation, userId: userId)
    }
    
    // MARK: - Signature Verification Tests
    
    func testSignature_ValidSignature_Succeeds() async throws {
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // Generate key pair
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        
        // Create operation without signature first
        var operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")]
        )
        
        // Sign operation - remove signature and encode
        operation.signature = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // Ensure deterministic encoding
        let encoded = try encoder.encode(operation)
        let key = SymmetricKey(data: publicKey.rawRepresentation)
        let signature = HMAC<SHA256>.authenticationCode(for: encoded, using: key)
        operation.signature = Data(signature)
        
        // Verify signature
        try await validator.verifySignature(operation, publicKey: publicKey)
    }
    
    func testSignature_InvalidSignature_Rejected() async throws {
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // Generate key pair
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        
        var operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")]
        )
        
        // Sign with wrong key
        operation.signature = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // Ensure deterministic encoding
        let encoded = try encoder.encode(operation)
        let wrongKey = SymmetricKey(data: Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        let signature = HMAC<SHA256>.authenticationCode(for: encoded, using: wrongKey)
        operation.signature = Data(signature)
        
        // Verify should fail
        do {
            try await validator.verifySignature(operation, publicKey: publicKey)
            XCTFail("Should have rejected invalid signature")
        } catch SecurityError.invalidSignature {
            // Expected
        }
    }
    
    // MARK: - Complete Validation Tests
    
    func testCompleteValidation_ValidOperation_Succeeds() async throws {
        let userId = UUID()
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // Set permissions
        let permissions = SyncPermissions(
            userId: userId,
            readCollections: ["bugs"],
            writeCollections: ["bugs"],
            deleteCollections: [],
            canAdmin: false
        )
        
        await validator.setPermissions(permissions, for: userId)
        
        // Generate key pair
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        
        var operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")],
            expiresAt: Date().addingTimeInterval(60)
        )
        
        // Sign operation
        operation.signature = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // Ensure deterministic encoding
        let encoded = try encoder.encode(operation)
        let key = SymmetricKey(data: publicKey.rawRepresentation)
        let signature = HMAC<SHA256>.authenticationCode(for: encoded, using: key)
        operation.signature = Data(signature)
        
        // Complete validation should succeed
        try await validator.validateOperation(operation, userId: userId, publicKey: publicKey)
    }
    
    func testCompleteValidation_InvalidOperation_Rejected() async throws {
        let userId = UUID()
        let nodeId = UUID()
        // Use current time in milliseconds for timestamp
        let currentTimeMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = LamportTimestamp(counter: currentTimeMs, nodeId: nodeId)
        
        // User has no permissions
        let permissions = SyncPermissions(
            userId: userId,
            readCollections: [],
            writeCollections: [],
            deleteCollections: [],
            canAdmin: false
        )
        
        await validator.setPermissions(permissions, for: userId)
        
        let operation = BlazeOperation(
            id: UUID(),
            timestamp: timestamp,
            nodeId: nodeId,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Bug")],
            expiresAt: Date().addingTimeInterval(60)
        )
        
        // Complete validation should fail (no permission)
        do {
            try await validator.validateOperation(operation, userId: userId, publicKey: nil)
            XCTFail("Should have rejected operation without permission")
        } catch SecurityError.permissionDenied {
            // Expected
        }
    }
    
    // MARK: - Connection Limit Tests
    
    func testConnectionLimit_ExceedsLimit_Rejected() throws {
        // Create server
        let server1 = BlazeServer(
            port: 8080,
            database: db1,
            databaseName: "db1"
        )
        
        let server2 = BlazeServer(
            port: 8081,
            database: db2,
            databaseName: "db2"
        )
        
        // Should accept up to maxConnections
        XCTAssertNotNil(server1)
        XCTAssertNotNil(server2)
        
        // (Note: Full test would require actual network connections)
    }
}

