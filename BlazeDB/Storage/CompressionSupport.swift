//
//  CompressionSupport.swift
//  BlazeDB
//
//  Data compression for large text fields
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

#if canImport(Compression)
import Compression

// MARK: - Compression Configuration

public struct CompressionConfig {
    public var enabled: Bool = true
    public var algorithm: CompressionAlgorithm = .lz4
    public var minimumSize: Int = 1024  // Only compress if > 1KB
    public var compressFields: Set<String>?  // nil = auto, specific fields = manual
    
    public init() {}
    
    public enum CompressionAlgorithm {
        case lz4      // Fast, good compression
        case zlib     // Better compression, slower
        case lzma     // Best compression, slowest
        
        var algorithm: compression_algorithm {
            switch self {
            case .lz4: return COMPRESSION_LZ4
            case .zlib: return COMPRESSION_ZLIB
            case .lzma: return COMPRESSION_LZMA
            }
        }
    }
}

// MARK: - Compressor

internal struct DataCompressor {
    
    /// Compress data
    static func compress(_ data: Data, algorithm: compression_algorithm) throws -> Data {
        let sourceBuffer = Array(data)
        let destBufferSize = data.count
        var destBuffer = [UInt8](repeating: 0, count: destBufferSize)
        
        let compressedSize = compression_encode_buffer(
            &destBuffer,
            destBufferSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            algorithm
        )
        
        guard compressedSize > 0 else {
            throw BlazeDBError.invalidData(reason: "Compression failed")
        }
        
        return Data(destBuffer.prefix(compressedSize))
    }
    
    /// Decompress data
    static func decompress(_ data: Data, algorithm: compression_algorithm, originalSize: Int) throws -> Data {
        let sourceBuffer = Array(data)
        var destBuffer = [UInt8](repeating: 0, count: originalSize)
        
        let decompressedSize = compression_decode_buffer(
            &destBuffer,
            originalSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            algorithm
        )
        
        guard decompressedSize == originalSize else {
            throw BlazeDBError.corruptedData(location: "compressed data", reason: "Decompression failed")
        }
        
        return Data(destBuffer)
    }
}

// MARK: - Compressed Field Wrapper

extension BlazeDocumentField {
    
    /// Compress string field if beneficial
    mutating func compressIfBeneficial(config: CompressionConfig) throws {
        guard config.enabled else { return }
        
        switch self {
        case .string(let text):
            let data = text.data(using: .utf8) ?? Data()
            
            guard data.count >= config.minimumSize else { return }
            
            let compressed = try DataCompressor.compress(data, algorithm: config.algorithm.algorithm)
            
            // Only use compression if it saves space
            if compressed.count < data.count {
                let ratio = Double(compressed.count) / Double(data.count)
                BlazeLogger.trace("Compressed text field: \(data.count) → \(compressed.count) bytes (\(String(format: "%.1f", ratio * 100))%)")
                
                // Store as Data with compression marker
                self = .data(compressed)
            }
            
        case .data(let originalData):
            guard originalData.count >= config.minimumSize else { return }
            
            let compressed = try DataCompressor.compress(originalData, algorithm: config.algorithm.algorithm)
            
            if compressed.count < originalData.count {
                self = .data(compressed)
            }
            
        default:
            break
        }
    }
}

// MARK: - BlazeDBClient Compression Extension

extension BlazeDBClient {
    
    nonisolated(unsafe) private static var compressionConfigs: [String: CompressionConfig] = [:]
    private static let compressionLock = NSLock()
    
    /// Enable compression for large fields
    ///
    /// - Parameter config: Compression configuration
    ///
    /// ## Example
    /// ```swift
    /// var config = CompressionConfig()
    /// config.algorithm = .lz4
    /// config.minimumSize = 1024  // Only compress > 1KB
    /// config.compressFields = ["description", "content"]
    ///
    /// db.enableCompression(config)
    /// ```
    public func enableCompression(_ config: CompressionConfig = CompressionConfig()) {
        let key = "\(name)-\(fileURL.path)"
        
        Self.compressionLock.lock()
        Self.compressionConfigs[key] = config
        Self.compressionLock.unlock()
        
        BlazeLogger.info("📦 Compression enabled for '\(name)' (algorithm: \(config.algorithm), min size: \(config.minimumSize) bytes)")
    }
    
    /// Disable compression
    public func disableCompression() {
        let key = "\(name)-\(fileURL.path)"
        
        Self.compressionLock.lock()
        Self.compressionConfigs.removeValue(forKey: key)
        Self.compressionLock.unlock()
        
        BlazeLogger.info("📦 Compression disabled for '\(name)'")
    }
    
    /// Get current compression config
    internal func getCompressionConfig() -> CompressionConfig? {
        let key = "\(name)-\(fileURL.path)"
        
        Self.compressionLock.lock()
        defer { Self.compressionLock.unlock() }
        
        return Self.compressionConfigs[key]
    }
}

#endif // canImport(Compression)

