//
//  ExportService.swift
//  BlazeDBVisualizer
//
//  Export database records to CSV, JSON, or other formats
//  ✅ CSV export with headers
//  ✅ JSON export (pretty or compact)
//  ✅ Filtered export
//  ✅ Progress tracking
//
//  Created by Michael Danylchuk on 11/14/25.
//

import Foundation
import BlazeDB

final class ExportService {
    
    static let shared = ExportService()
    
    private init() {}
    
    // MARK: - CSV Export
    
    /// Export database records to CSV format
    func exportToCSV(records: [BlazeDataRecord], to url: URL) throws {
        guard !records.isEmpty else {
            throw ExportServiceError.noRecords
        }
        
        // Collect all unique field names
        var allFields = Set<String>()
        for record in records {
            allFields.formUnion(record.storage.keys)
        }
        let sortedFields = allFields.sorted()
        
        // Generate CSV
        var csv = ""
        
        // Header row
        csv += sortedFields.map { escapeCSV($0) }.joined(separator: ",")
        csv += "\n"
        
        // Data rows
        for record in records {
            let row = sortedFields.map { field in
                if let value = record.storage[field] {
                    return escapeCSV(fieldToString(value))
                } else {
                    return ""
                }
            }.joined(separator: ",")
            
            csv += row + "\n"
        }
        
        // Write to file
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - JSON Export
    
    /// Export database records to JSON format
    func exportToJSON(records: [BlazeDataRecord], to url: URL, prettyPrint: Bool = true) throws {
        guard !records.isEmpty else {
            throw ExportServiceError.noRecords
        }
        
        // Convert to JSON-friendly format
        let jsonArray = records.map { record in
            var dict: [String: Any] = [:]
            
            for (key, value) in record.storage {
                dict[key] = value.toJSON()
            }
            
            return dict
        }
        
        // Encode to JSON
        let options: JSONSerialization.WritingOptions = prettyPrint
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys]
        
        let data = try JSONSerialization.data(withJSONObject: jsonArray, options: options)
        
        // Write to file
        try data.write(to: url, options: [.atomic])
    }
    
    // MARK: - Export All Database
    
    /// Export entire database (opens database, fetches all, exports)
    func exportDatabase(
        dbPath: String,
        password: String,
        format: ExportFormat,
        to url: URL,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
        // Open database
        let dbURL = URL(fileURLWithPath: dbPath)
        let name = dbURL.deletingPathExtension().lastPathComponent
        let db = try BlazeDBClient(name: name, fileURL: dbURL, password: password)
        
        // Get all records
        let records = try db.fetchAll()
        
        guard !records.isEmpty else {
            throw ExportServiceError.noRecords
        }
        
        // Export based on format
        switch format {
        case .csv:
            try exportToCSV(records: records, to: url)
        case .json(let pretty):
            try exportToJSON(records: records, to: url, prettyPrint: pretty)
        }
        
        // Report completion
        progressHandler?(records.count, records.count)
    }
    
    // MARK: - Helper Functions
    
    private func fieldToString(_ field: BlazeDocumentField) -> String {
        switch field {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .uuid(let u): return u.uuidString
        case .date(let d): return d.ISO8601Format()
        case .data(let d): return d.base64EncodedString()
        case .array(let a): return "[\(a.count) items]"
        case .dictionary(let d): return "{\(d.count) fields}"
        }
    }
    
    private func escapeCSV(_ string: String) -> String {
        // If string contains comma, quote, or newline, wrap in quotes
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            // Escape quotes by doubling them
            let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return string
    }
}

// MARK: - Export Format

enum ExportFormat {
    case csv
    case json(prettyPrint: Bool)
    
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

// MARK: - Export Service Errors

enum ExportServiceError: LocalizedError {
    case noRecords
    case writeFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .noRecords:
            return "No records to export"
        case .writeFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        }
    }
}

