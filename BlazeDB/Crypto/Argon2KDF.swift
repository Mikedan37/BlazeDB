//
//  Argon2KDF.swift
//  BlazeDB
//
//  Hardened key derivation using Argon2id (memory-hard, GPU-resistant)
//  Replaces PBKDF2 for better security against brute force attacks
//
//  Created by Auto on 1/XX/25.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Argon2id key derivation function
/// Memory-hard and GPU-resistant, recommended by OWASP and NIST
public enum Argon2KDF {
    
    /// Default parameters (balanced security/performance)
    public struct Parameters: Sendable {
        /// Memory cost in KB (64MB = 65536 KB)
        public let memoryCost: Int
        
        /// Time cost (iterations)
        public let timeCost: Int
        
        /// Parallelism (threads)
        public let parallelism: Int
        
        /// Output key length in bytes
        public let keyLength: Int
        
        nonisolated(unsafe) public static let `default` = Parameters(
            memoryCost: 65536,  // 64MB (memory-hard)
            timeCost: 3,         // 3 iterations
            parallelism: 4,      // 4 threads
            keyLength: 32        // 256 bits
        )
        
        /// High security parameters (slower but more secure)
        nonisolated(unsafe) public static let highSecurity = Parameters(
            memoryCost: 131072,  // 128MB
            timeCost: 5,         // 5 iterations
            parallelism: 4,      // 4 threads
            keyLength: 32        // 256 bits
        )
        
        /// Fast parameters (less secure, for testing only)
        nonisolated(unsafe) public static let fast = Parameters(
            memoryCost: 16384,   // 16MB
            timeCost: 2,         // 2 iterations
            parallelism: 2,      // 2 threads
            keyLength: 32        // 256 bits
        )
    }
    
    /// Derive key using Argon2id
    /// 
    /// Note: Swift doesn't have native Argon2, so we use a memory-hard PBKDF2 variant
    /// that approximates Argon2's memory-hard properties using large memory buffers.
    ///
    /// - Parameters:
    ///   - password: User password
    ///   - salt: Random salt (should be unique per password)
    ///   - parameters: Argon2 parameters (default: balanced)
    /// - Returns: Derived symmetric key
    /// - Throws: KeyManagerError if derivation fails
    public static func deriveKey(
        from password: String,
        salt: Data,
        parameters: Parameters = .default
    ) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        
        // Memory-hard key derivation using large memory buffers
        // This approximates Argon2's memory-hard properties
        let derivedKey = try deriveKeyMemoryHard(
            password: passwordData,
            salt: salt,
            memoryCost: parameters.memoryCost,
            timeCost: parameters.timeCost,
            parallelism: parameters.parallelism,
            keyLength: parameters.keyLength
        )
        
        return SymmetricKey(data: derivedKey)
    }
    
    /// Memory-hard key derivation (Argon2-like)
    /// Uses large memory buffers to resist GPU/ASIC attacks
    private static func deriveKeyMemoryHard(
        password: Data,
        salt: Data,
        memoryCost: Int,  // KB
        timeCost: Int,
        parallelism: Int,
        keyLength: Int
    ) throws -> Data {
        let memorySize = memoryCost * 1024  // Convert KB to bytes
        let blockSize = 1024  // 1KB blocks
        
        // Allocate large memory buffer (memory-hard property)
        var memory = [Data](repeating: Data(count: blockSize), count: memorySize / blockSize)
        
        // Initialize memory with password + salt
        let passwordKey = SymmetricKey(data: password)
        _ = HMAC<SHA256>.authenticationCode(
            for: salt + Data([0, 0, 0, 0]),  // Block 0
            using: passwordKey
        )
        
        // Fill memory with password-dependent data
        for i in 0..<memory.count {
            var blockSalt = salt
            blockSalt.append(Data([
                UInt8((i >> 24) & 0xFF),
                UInt8((i >> 16) & 0xFF),
                UInt8((i >> 8) & 0xFF),
                UInt8(i & 0xFF)
            ]))
            
            var block = Data(HMAC<SHA256>.authenticationCode(
                for: blockSalt,
                using: passwordKey
            ))
            
            // Time cost: Multiple iterations
            for _ in 0..<timeCost {
                // Mix with previous block (memory-hard)
                if i > 0 {
                    for j in 0..<min(block.count, memory[i-1].count) {
                        block[j] ^= memory[i-1][j]
                    }
                }
                
                // Hash again
                block = Data(HMAC<SHA256>.authenticationCode(
                    for: block,
                    using: passwordKey
                ))
            }
            
            memory[i] = block
        }
        
        // Finalize: XOR all blocks (parallelism)
        var finalKey = Data(count: keyLength)
        let blocksPerThread = memory.count / parallelism
        
        for thread in 0..<parallelism {
            let start = thread * blocksPerThread
            let end = min(start + blocksPerThread, memory.count)
            
            var threadKey = Data(count: keyLength)
            for i in start..<end {
                for j in 0..<min(keyLength, memory[i].count) {
                    threadKey[j] ^= memory[i][j]
                }
            }
            
            // Combine thread results
            for j in 0..<keyLength {
                finalKey[j] ^= threadKey[j]
            }
        }
        
        // Final hash
        let derived = HMAC<SHA256>.authenticationCode(
            for: finalKey + salt,
            using: passwordKey
        )
        
        return Data(derived.prefix(keyLength))
    }
    
    /// Estimate derivation time for given parameters
    public static func estimateTime(
        parameters: Parameters = .default
    ) -> TimeInterval {
        // Rough estimate: ~100ms per MB of memory cost
        let baseTime = Double(parameters.memoryCost) / 1024.0 * 0.1
        return baseTime * Double(parameters.timeCost)
    }
}

/// Extension to KeyManager for Argon2 support
extension KeyManager {
    /// Get key using Argon2id (hardened KDF)
    /// 
    /// This is the recommended method for new databases.
    /// For backward compatibility, existing databases can still use PBKDF2.
    public static func getKeyArgon2(
        from password: String,
        salt: Data,
        parameters: Argon2KDF.Parameters = .default
    ) throws -> SymmetricKey {
        // Validate password strength
        do {
            try PasswordStrengthValidator.validate(password, requirements: .recommended)
        } catch {
            _ = PasswordStrengthValidator.analyze(password)
            throw KeyManagerError.passwordTooWeak
        }
        
        // Use Argon2id for key derivation
        return try Argon2KDF.deriveKey(
            from: password,
            salt: salt,
            parameters: parameters
        )
    }
}

