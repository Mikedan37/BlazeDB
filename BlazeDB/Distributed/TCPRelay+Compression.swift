//
//  TCPRelay+Compression.swift
//  BlazeDB Distributed
//
//  Compression stubs (unsafe code removed)
//

import Foundation

extension TCPRelay {
    /// Compress data (stub - returns data as-is)
    /// NOTE: Compression intentionally disabled. Previous implementation used unsafe pointers
    /// which were removed for Swift 6 safety. Compression can be re-implemented using safe
    /// Swift patterns, but is currently disabled to prioritize safety and correctness.
    nonisolated func compress(_ data: Data) -> Data {
        return data
    }
    
    /// Decompress data if needed (stub - returns data as-is)
    /// NOTE: Decompression intentionally disabled. See compress() for details.
    nonisolated func decompressIfNeeded(_ data: Data) throws -> Data {
        // Check for compression magic bytes
        guard data.count >= 4 else {
            return data  // Not compressed
        }
        
        let magicRange = data.startIndex..<(data.startIndex + 4)
        let magic = String(data: data[magicRange], encoding: .utf8) ?? ""
        
        // If magic bytes indicate compression, return as-is (decompression stubbed)
        switch magic {
        case "BZL4", "BZLB", "BZMA", "BZCZ":
            // Compressed data - return as-is (decompression stubbed)
            return data
        default:
            // Not compressed
            return data
        }
    }
}

