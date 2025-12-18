//
//  BlazeDBClient+Debug.swift
//  BlazeDB
//
//  Debug and monitoring APIs for BlazeBinary encoding
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Encoding Stats

public struct EncodingStats {
    public let blazeBinarySize: Int
    public let jsonSize: Int
    public let recordCount: Int
    public let savings: Double  // Percentage
    public let avgRecordSize: Int
    public let compressionRatio: Double
    
    public var description: String {
        return """
        Encoding Statistics:
          Records: \(recordCount)
          BlazeBinary: \(blazeBinarySize / 1024) KB
          JSON (for comparison): \(jsonSize / 1024) KB
          Savings: \(String(format: "%.1f", savings))%
          Avg record size: \(avgRecordSize) bytes
          Compression ratio: \(String(format: "%.2f", compressionRatio))x
        """
    }
}

// MARK: - Debug APIs

extension BlazeDBClient {
    
    // MARK: - JSON Export (For Debugging)
    
    /// Export a single record as human-readable JSON
    ///
    /// Useful for debugging BlazeBinary-encoded records.
    /// Does NOT affect the database (read-only).
    ///
    /// - Parameter id: Record ID to export
    /// - Returns: Pretty-printed JSON string
    /// - Throws: If record not found
    public func exportAsJSON(id: UUID) throws -> String {
        guard let record = try fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let json = try encoder.encode(record)
        return String(data: json, encoding: .utf8) ?? "{}"
    }
    
    /// Export all records as JSON array
    ///
    /// Useful for:
    /// - Debugging
    /// - Backup (human-readable)
    /// - Data export to other systems
    ///
    /// - Returns: Pretty-printed JSON array
    /// - Throws: If fetch fails
    public func exportAllAsJSON() throws -> String {
        let records = try fetchAll()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let json = try encoder.encode(records)
        return String(data: json, encoding: .utf8) ?? "[]"
    }
    
    /// Export specific fields as JSON
    ///
    /// - Parameters:
    ///   - id: Record ID
    ///   - fields: Fields to export
    /// - Returns: JSON object with specified fields
    public func exportFields(id: UUID, fields: [String]) throws -> String {
        guard let record = try fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        var filtered: [String: BlazeDocumentField] = [:]
        for field in fields {
            if let value = record.storage[field] {
                filtered[field] = value
            }
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let json = try encoder.encode(BlazeDataRecord(filtered))
        return String(data: json, encoding: .utf8) ?? "{}"
    }
    
    // MARK: - Encoding Statistics
    
    /// Get encoding statistics for the database
    ///
    /// Shows how much space BlazeBinary saves compared to JSON.
    ///
    /// - Returns: Encoding stats (sizes, savings, compression ratio)
    /// - Throws: If fetch fails
    public func getEncodingStats() throws -> EncodingStats {
        let records = try fetchAll()
        
        var blazeBinaryTotal = 0
        var jsonTotal = 0
        
        for record in records {
            // Calculate BlazeBinary size
            if let binaryData = try? BlazeBinaryEncoder.encode(record) {
                blazeBinaryTotal += binaryData.count
            }
            
            // Calculate JSON size (for comparison)
            if let jsonData = try? JSONEncoder().encode(record) {
                jsonTotal += jsonData.count
            }
        }
        
        let savings = jsonTotal > 0 ? 
            Double(jsonTotal - blazeBinaryTotal) / Double(jsonTotal) * 100 : 0
        
        let compressionRatio = jsonTotal > 0 ?
            Double(jsonTotal) / Double(blazeBinaryTotal) : 1.0
        
        let avgRecordSize = records.count > 0 ?
            blazeBinaryTotal / records.count : 0
        
        return EncodingStats(
            blazeBinarySize: blazeBinaryTotal,
            jsonSize: jsonTotal,
            recordCount: records.count,
            savings: savings,
            avgRecordSize: avgRecordSize,
            compressionRatio: compressionRatio
        )
    }
    
    /// Get storage format information
    ///
    /// - Returns: Format description (e.g., "BlazeBinary v1.0")
    public func getStorageFormat() -> String {
        return "BlazeBinary v1.0 (53% smaller, 48% faster, zero dependencies)"
    }
    
    /// Get encoding format version
    ///
    /// - Returns: Current encoding version
    public func getEncodingVersion() -> String {
        return "1.0"
    }
    
    // MARK: - Validation & Health
    
    /// Validate all records can be encoded/decoded properly
    ///
    /// Useful for catching encoding bugs or corrupted data.
    ///
    /// - Returns: Validation report with any issues found
    public func validateEncoding() throws -> ValidationReport {
        let records = try fetchAll()
        var issues: [IntegrityIssue] = []
        
        for record in records {
            // Test round-trip encoding
            do {
                let encoded = try BlazeBinaryEncoder.encode(record)
                let decoded = try BlazeBinaryDecoder.decode(encoded)
                
                // Verify field count matches
                if decoded.storage.count != record.storage.count {
                    let recordID = record.storage["id"]?.uuidValue ?? UUID()
                    issues.append(IntegrityIssue(
                        severity: .error,
                        message: "Record \(recordID): Field count mismatch after round-trip"
                    ))
                }
            } catch {
                let recordID = record.storage["id"]?.uuidValue ?? UUID()
                issues.append(IntegrityIssue(
                    severity: .error,
                    message: "Record \(recordID): Encoding failed - \(error)"
                ))
            }
        }
        
        return ValidationReport(ok: issues.isEmpty, issues: issues)
    }
    
    // MARK: - Encoding Error Monitoring
    
    /// Track encoding errors in telemetry
    internal func trackEncodingError(_ error: Error, operation: String) {
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(
            operation: "encoding_error",
            duration: 0,
            success: false,
            recordCount: 0,
            error: error
        )
        #endif
        BlazeLogger.error("🔴 Encoding error in \(operation): \(error)")
    }
}

