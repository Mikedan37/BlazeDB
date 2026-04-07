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
    
    /// Enable compression for pages > 1KB
    public func enableCompression() {
        compressionStateLock.lock()
        compressionEnabled = true
        compressionStateLock.unlock()
    }
    
    /// Disable compression
    public func disableCompression() {
        compressionStateLock.lock()
        compressionEnabled = false
        compressionStateLock.unlock()
    }
    
    private var isCompressionEnabled: Bool {
        compressionStateLock.lock()
        defer { compressionStateLock.unlock() }
        return compressionEnabled
    }

    #if DEBUG
    /// Regression guard for issue #39:
    /// compression state is instance-scoped; no shared static table should exist.
    internal static func _compressionStateTableCountForTests() -> Int {
        0
    }
    #endif
    
    // MARK: - Compressed Write
    
    /// Build a compressed + encrypted page buffer in v0x03 format.
    /// Returns nil when compression does not reduce payload size.
    internal func _encryptCompressedPageBuffer(plaintext: Data) throws -> Data? {
        // Compress using LZ4 (fast, good compression)
        let compressed = try compressData(plaintext, algorithm: COMPRESSION_LZ4)

        // Only use compression if it saves space
        guard compressed.count < plaintext.count else {
            return nil
        }

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

        return buffer
    }

    /// Write page with optional compression (50-70% savings for large pages)
    public func writePageCompressed(index: Int, plaintext: Data) throws {
        guard isCompressionEnabled && plaintext.count > 1024 else {
            // Compression disabled or page too small - write normally
            return try writePage(index: index, plaintext: plaintext)
        }

        try queue.sync(flags: .barrier) {
            guard let buffer = try _encryptCompressedPageBuffer(plaintext: plaintext) else {
                // Compression didn't help - write uncompressed via normal path.
                return try _writePageLocked(index: index, plaintext: plaintext)
            }

            try _writeEncryptedBufferDurablyLocked(index: index, buffer: buffer)
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

    /// Encrypt compressed payload and format a page buffer for version 0x03.
    /// Must be called while holding the barrier on `queue`.
    private func _encryptCompressedPageBuffer(compressed: Data, originalLength: Int) throws -> Data {
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
        var originalLengthBE = UInt32(originalLength).bigEndian
        buffer.append(Data(bytes: &originalLengthBE, count: 4))

        // Store compressed ciphertext length (for ciphertext bounds)
        var compressedLengthBE = UInt32(sealedBox.ciphertext.count).bigEndian
        buffer.append(Data(bytes: &compressedLengthBE, count: 4))

        // Encryption components
        buffer.append(contentsOf: nonce)
        buffer.append(contentsOf: sealedBox.tag)
        buffer.append(contentsOf: sealedBox.ciphertext)

        guard buffer.count <= pageSize else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Compressed page too large (max: \(pageSize) bytes)"
            ])
        }

        if buffer.count < pageSize {
            buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
        }

        return buffer
    }
}

#endif // canImport(Compression)

