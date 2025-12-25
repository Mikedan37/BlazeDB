//
//  TCPRelay+Compression.swift
//  BlazeDB Distributed
//
//  Network compression for distributed sync (safe Swift implementation)
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if canImport(Compression)
import Compression

extension TCPRelay {
    /// Compress data for network transmission
    ///
    /// Uses LZ4 compression (fast, good compression ratio).
    /// If compression fails or doesn't save space, returns data uncompressed.
    /// Compression is transparent and optional - failures are non-fatal.
    ///
    /// - Parameter data: Data to compress
    /// - Returns: Compressed data with magic bytes, or original data if compression failed/didn't help
    nonisolated func compress(_ data: Data) -> Data {
        // Only compress if data is large enough to benefit (>1KB)
        guard data.count > 1024 else {
            return data  // Too small, not worth compressing
        }
        
        do {
            // Use safe Swift patterns (no unsafe pointers)
            let sourceBuffer = Array(data)
            let destBufferSize = data.count
            var destBuffer = [UInt8](repeating: 0, count: destBufferSize)
            
            let compressedSize = compression_encode_buffer(
                &destBuffer,
                destBufferSize,
                sourceBuffer,
                sourceBuffer.count,
                nil,
                COMPRESSION_LZ4  // Fast compression algorithm
            )
            
            // Only use compression if it saves space
            guard compressedSize > 0 && compressedSize < data.count else {
                return data  // Compression didn't help or failed
            }
            
            // Prepend magic bytes to indicate compression
            var compressed = Data()
            guard let magic = "BZL4".data(using: .utf8) else {
                return data  // Failed to encode magic bytes
            }
            compressed.append(magic)
            compressed.append(Data(destBuffer.prefix(compressedSize)))
            
            return compressed
        } catch {
            // Compression failed - return uncompressed (non-fatal)
            BlazeLogger.debug("Network compression failed, sending uncompressed: \(error)")
            return data
        }
    }
    
    /// Decompress data if needed
    ///
    /// Checks for compression magic bytes and decompresses if present.
    /// If decompression fails, throws an error (corruption).
    ///
    /// - Parameter data: Data that may be compressed
    /// - Returns: Decompressed data, or original data if not compressed
    /// - Throws: RelayError if decompression fails
    nonisolated func decompressIfNeeded(_ data: Data) throws -> Data {
        // Check for compression magic bytes
        guard data.count >= 4 else {
            return data  // Not compressed
        }
        
        let magicRange = data.startIndex..<(data.startIndex + 4)
        guard let magic = String(data: data[magicRange], encoding: .utf8) else {
            return data  // Invalid magic bytes, assume not compressed
        }
        
        // Determine algorithm from magic bytes
        let algorithm: compression_algorithm
        switch magic {
        case "BZL4":  // LZ4 (fastest)
            algorithm = COMPRESSION_LZ4
        case "BZLB":  // ZLIB (balanced)
            algorithm = COMPRESSION_ZLIB
        case "BZMA":  // LZMA (best compression)
            algorithm = COMPRESSION_LZMA
        case "BZCZ":  // Legacy (LZ4)
            algorithm = COMPRESSION_LZ4
        default:
            // Not compressed
            return data
        }
        
        // Extract compressed data (after magic bytes)
        let compressed = data.suffix(from: data.startIndex + 4)
        
        // Estimate decompressed size (conservative estimate)
        let multiplier: Int
        switch algorithm {
        case COMPRESSION_LZ4: multiplier = 3  // LZ4: 2-3x
        case COMPRESSION_ZLIB: multiplier = 4  // ZLIB: 3-4x
        case COMPRESSION_LZMA: multiplier = 10  // LZMA: 5-10x
        default: multiplier = 3
        }
        
        let estimatedSize = compressed.count * multiplier
        
        // Use safe Swift patterns (no unsafe pointers)
        let sourceBuffer = Array(compressed)
        var destBuffer = [UInt8](repeating: 0, count: estimatedSize)
        
        let decompressedSize = compression_decode_buffer(
            &destBuffer,
            estimatedSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            algorithm
        )
        
        guard decompressedSize > 0 else {
            throw RelayError.decompressionFailed
        }
        
        return Data(destBuffer.prefix(decompressedSize))
    }
}

#endif // canImport(Compression)
#endif // !BLAZEDB_LINUX_CORE

