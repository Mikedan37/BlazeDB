//
//  DumpFormat.swift
//  BlazeDB
//
//  Deterministic dump format for database export/import
//  Self-describing, verifiable, complete
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Dump format version
public enum DumpFormatVersion: Int, Codable {
    case v1 = 1
}

/// Dump header metadata
public struct DumpHeader: Codable {
    /// Format version
    public let formatVersion: DumpFormatVersion
    
    /// Database schema version at export time
    public let schemaVersion: SchemaVersion
    
    /// Database identifier (UUID)
    public let databaseId: UUID
    
    /// Export timestamp
    public let exportedAt: Date
    
    /// Database name
    public let databaseName: String
    
    /// Export tool version (optional)
    public let toolVersion: String?
    
    public init(
        formatVersion: DumpFormatVersion = .v1,
        schemaVersion: SchemaVersion,
        databaseId: UUID,
        exportedAt: Date = Date(),
        databaseName: String,
        toolVersion: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.databaseId = databaseId
        self.exportedAt = exportedAt
        self.databaseName = databaseName
        self.toolVersion = toolVersion
    }
}

/// Dump manifest (footer)
/// Contains hashes for verification
public struct DumpManifest: Codable {
    /// SHA256 hash of header JSON
    public let headerHash: String
    
    /// SHA256 hash of payload data
    public let payloadHash: String
    
    /// Record count
    public let recordCount: Int
    
    /// Total size of payload (bytes)
    public let payloadSize: Int
    
    /// Combined hash (hash of headerHash + payloadHash)
    public let combinedHash: String
    
    public init(
        headerHash: String,
        payloadHash: String,
        recordCount: Int,
        payloadSize: Int
    ) {
        self.headerHash = headerHash
        self.payloadHash = payloadHash
        self.recordCount = recordCount
        self.payloadSize = payloadSize
        
        // Combined hash for tamper detection
        let combined = (headerHash + payloadHash).data(using: .utf8)!
        self.combinedHash = combined.sha256()
    }
}

/// Complete dump structure
public struct DatabaseDump: Codable {
    /// Header metadata
    public let header: DumpHeader
    
    /// Payload: records in canonical order
    public let records: [BlazeDataRecord]
    
    /// Footer manifest
    public let manifest: DumpManifest
    
    /// Encode to deterministic JSON
    /// - Returns: JSON data (deterministic encoding)
    public static func encode(header: DumpHeader, records: [BlazeDataRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // CRITICAL: Use sortedKeys to ensure deterministic dictionary ordering
        // Without this, dictionary keys can be in any order, causing hash mismatches
        encoder.outputFormatting = [.sortedKeys]
        
        // Sort records by ID for deterministic ordering
        let sortedRecords = records.sorted { r1, r2 in
            let id1 = r1.storage["id"]?.uuidValue ?? UUID()
            let id2 = r2.storage["id"]?.uuidValue ?? UUID()
            return id1.uuidString < id2.uuidString
        }
        
        // Encode header and records separately for hashing
        let headerData = try encoder.encode(header)
        let recordsData = try encoder.encode(sortedRecords)
        
        // Compute hashes
        let headerHash = headerData.sha256()
        let payloadHash = recordsData.sha256()
        
        // Create manifest
        let manifest = DumpManifest(
            headerHash: headerHash,
            payloadHash: payloadHash,
            recordCount: sortedRecords.count,
            payloadSize: recordsData.count
        )
        
        // Encode complete dump (use sorted records for consistency)
        let dump = DatabaseDump(header: header, records: sortedRecords, manifest: manifest)
        return try encoder.encode(dump)
    }
    
    /// Decode from JSON and verify integrity
    /// - Parameter data: JSON data
    /// - Returns: Verified dump
    /// - Throws: Error if verification fails
    public static func decodeAndVerify(_ data: Data) throws -> DatabaseDump {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let dump = try decoder.decode(DatabaseDump.self, from: data)
        
        // Verify integrity
        try dump.verify()
        
        return dump
    }
    
    /// Verify dump integrity
    /// - Throws: Error if tampering detected
    public func verify() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // CRITICAL: Must match encoding settings used during export
        encoder.outputFormatting = [.sortedKeys]
        
        // Sort records the same way as during export
        let sortedRecords = records.sorted { r1, r2 in
            let id1 = r1.storage["id"]?.uuidValue ?? UUID()
            let id2 = r2.storage["id"]?.uuidValue ?? UUID()
            return id1.uuidString < id2.uuidString
        }
        
        // Re-encode header and records
        let headerData = try encoder.encode(header)
        let recordsData = try encoder.encode(sortedRecords)
        
        // Compute expected hashes
        let expectedHeaderHash = headerData.sha256()
        let expectedPayloadHash = recordsData.sha256()
        
        // Verify header hash
        guard manifest.headerHash == expectedHeaderHash else {
            throw BlazeDBError.corruptedData(
                location: "dump header",
                reason: "Header hash mismatch - dump may be tampered"
            )
        }
        
        // Verify payload hash
        guard manifest.payloadHash == expectedPayloadHash else {
            throw BlazeDBError.corruptedData(
                location: "dump payload",
                reason: "Payload hash mismatch - dump may be tampered"
            )
        }
        
        // Verify combined hash
        let expectedCombined = (expectedHeaderHash + expectedPayloadHash).data(using: .utf8)!
        let expectedCombinedHash = expectedCombined.sha256()
        
        guard manifest.combinedHash == expectedCombinedHash else {
            throw BlazeDBError.corruptedData(
                location: "dump manifest",
                reason: "Combined hash mismatch - dump may be tampered"
            )
        }
        
        // Verify record count matches
        guard manifest.recordCount == sortedRecords.count else {
            throw BlazeDBError.corruptedData(
                location: "dump manifest",
                reason: "Record count mismatch"
            )
        }
    }
}

// MARK: - SHA256 Helper

extension Data {
    func sha256() -> String {
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
        #else
        // Fallback: use base64 for non-CryptoKit platforms
        // Note: This is not cryptographically secure, but acceptable for non-security-critical verification
        return self.base64EncodedString()
        #endif
    }
}
