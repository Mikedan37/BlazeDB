//
//  SecurityValidator.swift
//  BlazeDB Distributed
//
//  Security validation for operations: replay protection, signatures, etc.
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Validates operations for security (replay protection, signatures, etc.)
public actor SecurityValidator {
    // Replay protection: Track seen operations and nonces
    private var seenOperations: Set<UUID> = []
    private var seenNonces: Set<Data> = []
    
    // Rate limiting: Track operation counts per user
    private var operationCounts: [UUID: (count: Int, resetTime: Date)] = [:]
    private let maxOperationsPerMinute: Int
    private let operationWindow: TimeInterval = 60  // 1 minute
    
    // Authorization: User permissions
    private var userPermissions: [UUID: SyncPermissions] = [:]
    
    public init(maxOperationsPerMinute: Int = 1000) {
        self.maxOperationsPerMinute = maxOperationsPerMinute
    }
    
    // MARK: - Replay Protection
    
    /// Validate operation for replay attacks
    public func validateReplayProtection(_ operation: BlazeOperation) throws {
        // 1. Check if operation ID already seen
        guard !seenOperations.contains(operation.id) else {
            throw SecurityError.duplicateOperation(operation.id)
        }
        
        // 2. Check if nonce already seen
        guard !seenNonces.contains(operation.nonce) else {
            throw SecurityError.replayAttack(operation.id)
        }
        
        // 3. Check if operation expired
        guard operation.expiresAt > Date() else {
            throw SecurityError.operationExpired(operation.id)
        }
        
        // 4. Check timestamp (must be recent, within 60 seconds)
        let timestampDate = Date(timeIntervalSince1970: Double(operation.timestamp.counter) / 1000.0)
        let age = Date().timeIntervalSince(timestampDate)
        guard age < 60 else {
            throw SecurityError.operationTooOld(operation.id)
        }
        
        // Record as seen
        seenOperations.insert(operation.id)
        seenNonces.insert(operation.nonce)
        
        // Cleanup old entries (keep last 10,000)
        if seenOperations.count > 10_000 {
            let toRemove = seenOperations.prefix(seenOperations.count - 10_000)
            seenOperations.subtract(toRemove)
        }
        if seenNonces.count > 10_000 {
            let toRemove = seenNonces.prefix(seenNonces.count - 10_000)
            seenNonces.subtract(toRemove)
        }
    }
    
    // MARK: - Rate Limiting
    
    /// Check if user has exceeded rate limit
    public func checkRateLimit(userId: UUID) throws {
        let now = Date()
        
        // Get or create user count
        var userCount = operationCounts[userId] ?? (count: 0, resetTime: now.addingTimeInterval(operationWindow))
        
        // Reset if window expired
        if now > userCount.resetTime {
            userCount = (count: 0, resetTime: now.addingTimeInterval(operationWindow))
        }
        
        // Check limit
        guard userCount.count < maxOperationsPerMinute else {
            throw SecurityError.rateLimitExceeded(userId)
        }
        
        // Increment
        userCount.count += 1
        operationCounts[userId] = userCount
    }
    
    // MARK: - Authorization
    
    /// Set permissions for a user
    public func setPermissions(_ permissions: SyncPermissions, for userId: UUID) {
        userPermissions[userId] = permissions
    }
    
    /// Check if user has permission for operation
    public func validateAuthorization(_ operation: BlazeOperation, userId: UUID) throws {
        guard let permissions = userPermissions[userId] else {
            // Default: no permissions (deny all)
            throw SecurityError.permissionDenied(userId, operation.collectionName)
        }
        
        // Check collection-level permission
        switch operation.type {
        case .insert, .update:
            guard permissions.canWrite(collection: operation.collectionName) else {
                throw SecurityError.permissionDenied(userId, operation.collectionName)
            }
        case .delete:
            guard permissions.canDelete(collection: operation.collectionName) else {
                throw SecurityError.permissionDenied(userId, operation.collectionName)
            }
        case .createIndex, .dropIndex:
            guard permissions.canAdmin else {
                throw SecurityError.permissionDenied(userId, operation.collectionName)
            }
        }
    }
    
    // MARK: - Signature Verification
    
    /// Verify operation signature
    public func verifySignature(_ operation: BlazeOperation, publicKey: P256.KeyAgreement.PublicKey) throws {
        guard let signature = operation.signature else {
            // Signature is optional (for now)
            return
        }
        
        // Encode operation (without signature)
        var opWithoutSig = operation
        opWithoutSig.signature = nil
        let encoded = try JSONEncoder().encode(opWithoutSig)
        
        // Verify HMAC
        let key = SymmetricKey(data: publicKey.rawRepresentation)
        let isValid = HMAC<SHA256>.isValidAuthenticationCode(
            signature,
            authenticating: encoded,
            using: key
        )
        
        guard isValid else {
            throw SecurityError.invalidSignature(operation.id)
        }
    }
    
    // MARK: - Complete Validation
    
    /// Validate operation completely (replay, rate limit, authorization, signature)
    public func validateOperation(
        _ operation: BlazeOperation,
        userId: UUID,
        publicKey: P256.KeyAgreement.PublicKey? = nil
    ) throws {
        // 1. Replay protection
        try validateReplayProtection(operation)
        
        // 2. Rate limiting
        try checkRateLimit(userId: userId)
        
        // 3. Authorization
        try validateAuthorization(operation, userId: userId)
        
        // 4. Signature (if provided)
        if let publicKey = publicKey {
            try verifySignature(operation, publicKey: publicKey)
        }
    }
    
    // MARK: - Performance Optimizations
    
    /// Fast path: Skip signature verification (saves ~0.01ms)
    public func validateOperationWithoutSignature(
        _ operation: BlazeOperation,
        userId: UUID
    ) throws {
        // Skip signature verification (saves ~0.01ms)
        try validateReplayProtection(operation)
        try checkRateLimit(userId: userId)
        try validateAuthorization(operation, userId: userId)
        // Signature verification skipped!
    }
    
    /// Batch validate multiple operations (faster than individual checks)
    public func validateOperationsBatch(
        _ operations: [BlazeOperation],
        userId: UUID,
        publicKey: P256.KeyAgreement.PublicKey? = nil
    ) throws {
        // Pre-filter: Remove already-seen operations (fast path)
        let unseenOps = operations.filter { op in
            !seenOperations.contains(op.id) && !seenNonces.contains(op.nonce)
        }
        
        guard !unseenOps.isEmpty else {
            return  // All operations already seen (idempotent)
        }
        
        // Batch check rate limit (single check for all operations)
        let opCount = unseenOps.count
        let currentCount = operationCounts[userId]?.count ?? 0
        
        guard currentCount + opCount <= maxOperationsPerMinute else {
            throw SecurityError.rateLimitExceeded(userId)
        }
        
        // Batch update rate limit counter
        let now = Date()
        var userCount = operationCounts[userId] ?? (count: 0, resetTime: now.addingTimeInterval(operationWindow))
        if now > userCount.resetTime {
            userCount = (count: 0, resetTime: now.addingTimeInterval(operationWindow))
        }
        userCount.count += opCount
        operationCounts[userId] = userCount
        
        // Batch check permissions
        if let permissions = userPermissions[userId] {
            // Pre-check: All operations must be in allowed collections
            let allowedCollections = permissions.writeCollections.union(permissions.readCollections)
            let invalidOps = unseenOps.filter { !allowedCollections.contains($0.collectionName) }
            
            guard invalidOps.isEmpty else {
                // Safe unwrap: We know invalidOps is not empty from guard above
                guard let firstInvalid = invalidOps.first else {
                    BlazeLogger.error("SecurityValidator: invalidOps is not empty but first element is nil")
                    throw SecurityError.permissionDenied(userId, "unknown")
                }
                throw SecurityError.permissionDenied(userId, firstInvalid.collectionName)
            }
        } else {
            // No permissions = deny all
            // Safe unwrap: We know unseenOps is not empty from guard at line 228
            guard let firstUnseen = unseenOps.first else {
                BlazeLogger.error("SecurityValidator: unseenOps is not empty but first element is nil")
                throw SecurityError.permissionDenied(userId, "unknown")
            }
            throw SecurityError.permissionDenied(userId, firstUnseen.collectionName)
        }
        
        // Batch add to seen sets (single allocation)
        let operationIds = Set(unseenOps.map(\.id))
        let nonces = Set(unseenOps.map(\.nonce))
        
        seenOperations.formUnion(operationIds)
        seenNonces.formUnion(nonces)
        
        // Batch verify signatures (if provided and public key available)
        if let publicKey = publicKey {
            for op in unseenOps where op.signature != nil {
                try verifySignature(op, publicKey: publicKey)
            }
        }
        
        // Cleanup old entries (periodic, not per-operation)
        if seenOperations.count > 10_000 {
            let toRemove = seenOperations.prefix(seenOperations.count - 10_000)
            seenOperations.subtract(toRemove)
        }
        if seenNonces.count > 10_000 {
            let toRemove = seenNonces.prefix(seenNonces.count - 10_000)
            seenNonces.subtract(toRemove)
        }
    }
    
    /// Fast path: Skip validation for trusted nodes (optional optimization)
    public func validateOperationFast(
        _ operation: BlazeOperation,
        userId: UUID,
        isTrusted: Bool = false
    ) throws {
        // Fast path: Skip all checks for trusted nodes
        if isTrusted {
            // Only check for duplicates (minimal overhead)
            guard !seenOperations.contains(operation.id) else {
                throw SecurityError.duplicateOperation(operation.id)
            }
            seenOperations.insert(operation.id)
            return
        }
        
        // Normal validation path
        try validateOperation(operation, userId: userId, publicKey: nil)
    }
}

// MARK: - Sync Permissions

public struct SyncPermissions {
    public let userId: UUID
    public let readCollections: Set<String>
    public let writeCollections: Set<String>
    public let deleteCollections: Set<String>
    public let canAdmin: Bool
    
    public init(
        userId: UUID,
        readCollections: Set<String> = [],
        writeCollections: Set<String> = [],
        deleteCollections: Set<String> = [],
        canAdmin: Bool = false
    ) {
        self.userId = userId
        self.readCollections = readCollections
        self.writeCollections = writeCollections
        self.deleteCollections = deleteCollections
        self.canAdmin = canAdmin
    }
    
    public func canRead(collection: String) -> Bool {
        return readCollections.contains(collection) || canAdmin
    }
    
    public func canWrite(collection: String) -> Bool {
        return writeCollections.contains(collection) || canAdmin
    }
    
    public func canDelete(collection: String) -> Bool {
        return deleteCollections.contains(collection) || canAdmin
    }
}

// MARK: - Security Errors

public enum SecurityError: Error, LocalizedError {
    case duplicateOperation(UUID)
    case replayAttack(UUID)
    case operationExpired(UUID)
    case operationTooOld(UUID)
    case rateLimitExceeded(UUID)
    case permissionDenied(UUID, String)
    case invalidSignature(UUID)
    case invalidAuthToken
    
    public var errorDescription: String? {
        switch self {
        case .duplicateOperation(let id):
            return "Operation \(id) has already been processed (duplicate)"
        case .replayAttack(let id):
            return "Replay attack detected for operation \(id)"
        case .operationExpired(let id):
            return "Operation \(id) has expired"
        case .operationTooOld(let id):
            return "Operation \(id) is too old (timestamp validation failed)"
        case .rateLimitExceeded(let userId):
            return "Rate limit exceeded for user \(userId)"
        case .permissionDenied(let userId, let collection):
            return "User \(userId) does not have permission for collection \(collection)"
        case .invalidSignature(let id):
            return "Invalid signature for operation \(id)"
        case .invalidAuthToken:
            return "Invalid authentication token"
        }
    }
}
#endif // !BLAZEDB_LINUX_CORE

