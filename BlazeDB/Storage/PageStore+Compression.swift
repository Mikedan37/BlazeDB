//
//  PageStore+Compression.swift
//  BlazeDB
//
//  Page-level compression for 50-70% storage savings
//  Compresses pages > 1KB using LZ4 (fast) or ZLIB (balanced)
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(Compression)
import Compression

extension PageStore {
    
    // MARK: - Compression Configuration
    
    // Swift 6: Protected by NSLock, safe for concurrent access
    nonisolated(unsafe) private static var compressionEnabled: [ObjectIdentifier: Bool] = [:]
    private static let compressionLock = NSLock()
    
    /// Enable compression for pages > 1KB
    public func enableCompression() {
        let id = ObjectIdentifier(self)
        Self.compressionLock.lock()
        defer { Self.compressionLock.unlock() }
        Self.compressionEnabled[id] = true
    }
    
    /// Disable compression
    public func disableCompression() {
        let id = ObjectIdentifier(self)
        Self.compressionLock.lock()
        defer { Self.compressionLock.unlock() }
        Self.compressionEnabled[id] = false
    }
    
    private var isCompressionEnabled: Bool {
        let id = ObjectIdentifier(self)
        Self.compressionLock.lock()
        defer { Self.compressionLock.unlock() }
        return Self.compressionEnabled[id] ?? false
    }
    
    // MARK: - Compressed Write
    
    /// Write page with optional compression (50-70% savings for large pages)
    public func writePageCompressed(index: Int, plaintext: Data) throws {
        guard isCompressionEnabled && plaintext.count > 1024 else {
            // Compression disabled or page too small - write normally
            return try writePage(index: index, plaintext: plaintext)
        }
        
        // Compress using LZ4 (fast, good compression)
        let compressed = try compressData(plaintext, algorithm: COMPRESSION_LZ4)
        
        // Only use compression if it saves space
        guard compressed.count < plaintext.count else {
            // Compression didn't help - write uncompressed
            return try writePage(index: index, plaintext: plaintext)
        }
        
        // Write compressed data with compression marker (version 0x03)
        try queue.sync(flags: .barrier) {
            // Encrypt compressed data
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(compressed, using: key, nonce: nonce)
            
            var buffer = Data()
            guard let magicBytes = "BZDB".data(using: .utf8) else {
                throw NSError(domain: "PageStore", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to encode page header magic"
                ])
            }
            buffer.append(magicBytes)
            buffer.append(0x03)  // Version 0x03 = compressed + encrypted
            
            // Store original length (for decompression target size)
            var originalLength = UInt32(plaintext.count).bigEndian
            buffer.append(Data(bytes: &originalLength, count: 4))
            
            // Store compressed length (for ciphertext bounds) - FIXED in v0x03.1
            var compressedLength = UInt32(sealedBox.ciphertext.count).bigEndian
            buffer.append(Data(bytes: &compressedLength, count: 4))
            
            // Encryption components
            buffer.append(contentsOf: nonce)
            buffer.append(contentsOf: sealedBox.tag)
            buffer.append(contentsOf: sealedBox.ciphertext)
            
            // Pad to page size
            if buffer.count < pageSize {
                buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
            }
            
            let offset = off_t(index * pageSize)
            try atomicWrite(offset: offset, data: buffer)
            try fileHandle.compatSynchronize()
        }
    }
    
    // MARK: - Compressed Read
    
    /// Read page with automatic decompression
    public func readPageCompressed(index: Int) throws -> Data? {
        // Read stored page metadata to detect v0x03 format.
        let storedPage = try queue.sync {
            try atomicRead(offset: off_t(index * pageSize), count: pageSize)
        }
        
        guard storedPage.count >= 9 else { return try readPage(index: index) }
        let version = storedPage[4]
        
        if version == 0x03 {
            return try _decodeCompressedPageV03(storedPage: storedPage, index: index)
        }
        
        // Non-compressed pages still flow through the canonical reader.
        return try readPage(index: index)
    }

    /// Decode v0x03 compressed+encrypted page payload.
    /// Supports both current layout (with compressedLength) and the legacy layout.
    internal func _decodeCompressedPageV03(storedPage: Data, index: Int) throws -> Data {
        guard storedPage.count >= 37 else {
            throw NSError(domain: "PageStore", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Page \(index) too short for compressed format"
            ])
        }

        let originalLength = Int(storedPage.subdata(in: 5..<9).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })

        // First attempt current format (v0x03.1): [magic][v][origLen][compressedLen][nonce][tag][ciphertext]
        if storedPage.count >= 41 {
            let compressedLength = Int(storedPage.subdata(in: 9..<13).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
            if compressedLength > 0, 41 + compressedLength <= storedPage.count {
                if let decoded = try? _decryptAndDecompressCompressedV03Payload(
                    storedPage: storedPage,
                    originalLength: originalLength,
                    nonceOffset: 13,
                    tagOffset: 25,
                    ciphertextOffset: 41,
                    ciphertextLength: compressedLength
                ) {
                    return decoded
                }
            }
        }

        // Fallback for legacy layout: [magic][v][origLen][nonce][tag][ciphertext(+padding...)]
        let legacyCiphertextLength = max(0, storedPage.count - 37)
        if let decoded = try? _decryptAndDecompressCompressedV03Payload(
            storedPage: storedPage,
            originalLength: originalLength,
            nonceOffset: 9,
            tagOffset: 21,
            ciphertextOffset: 37,
            ciphertextLength: legacyCiphertextLength
        ) {
            return decoded
        }

        throw NSError(domain: "PageStore", code: 8, userInfo: [
            NSLocalizedDescriptionKey: "Corrupted compression payload for page \(index)"
        ])
    }

    private func _decryptAndDecompressCompressedV03Payload(
        storedPage: Data,
        originalLength: Int,
        nonceOffset: Int,
        tagOffset: Int,
        ciphertextOffset: Int,
        ciphertextLength: Int
    ) throws -> Data {
        guard ciphertextLength > 0 else {
            throw NSError(domain: "PageStore", code: 9, userInfo: [
                NSLocalizedDescriptionKey: "Invalid compressed ciphertext length"
            ])
        }
        guard storedPage.count >= ciphertextOffset + ciphertextLength else {
            throw NSError(domain: "PageStore", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Compressed ciphertext range out of bounds"
            ])
        }

        let nonceData = storedPage.subdata(in: nonceOffset..<(nonceOffset + 12))
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw NSError(domain: "PageStore", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Invalid compressed page nonce"
            ])
        }
        let tagData = storedPage.subdata(in: tagOffset..<(tagOffset + 16))
        let ciphertext = storedPage.subdata(in: ciphertextOffset..<(ciphertextOffset + ciphertextLength))
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)
        let compressed = try AES.GCM.open(sealedBox, using: key)
        return try decompressData(compressed, originalSize: originalLength, algorithm: COMPRESSION_LZ4)
    }
    
    // MARK: - Compression Helpers
    
    /// Compress data using specified algorithm
    /// Standardized API: compress(_ input: Data) throws -> Data
    private func compressData(_ data: Data, algorithm: compression_algorithm) throws -> Data {
        // Convert Data to [UInt8] for compression API
        let sourceBuffer = Array(data)
        let destBufferSize = data.count
        var destBuffer = [UInt8](repeating: 0, count: destBufferSize)
        
        // Compression API signature: (dest, destSize, src, srcSize, scratch, algorithm)
        let compressedSize = compression_encode_buffer(
            &destBuffer,
            destBufferSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            algorithm
        )
        
        guard compressedSize > 0 else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Compression failed"
            ])
        }
        
        // Convert back to Data
        return Data(destBuffer.prefix(compressedSize))
    }
    
    /// Decompress data using specified algorithm
    /// Standardized API: decompress(_ input: Data) throws -> Data
    private func decompressData(_ data: Data, originalSize: Int, algorithm: compression_algorithm) throws -> Data {
        // Convert Data to [UInt8] for decompression API
        let sourceBuffer = Array(data)
        var destBuffer = [UInt8](repeating: 0, count: originalSize)
        
        // Decompression API signature: (dest, destSize, src, srcSize, scratch, algorithm)
        let decompressedSize = compression_decode_buffer(
            &destBuffer,
            originalSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            algorithm
        )
        
        guard decompressedSize == originalSize else {
            throw BlazeDBError.corruptedData(
                location: "compressed page",
                reason: "Decompression failed: expected \(originalSize) bytes, got \(decompressedSize)"
            )
        }
        
        // Convert back to Data
        return Data(destBuffer)
    }
}

#endif // canImport(Compression)

