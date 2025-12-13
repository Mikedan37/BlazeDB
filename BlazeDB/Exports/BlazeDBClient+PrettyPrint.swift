//
//  BlazeDBClient+PrettyPrint.swift
//  BlazeDB
//
//  Pretty-print database to human-readable text file for debugging
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Pretty Print Configuration

public struct PrettyPrintOptions {
    public var includeMetadata: Bool
    public var includeStats: Bool
    public var indentSize: Int
    public var sortByField: String?
    public var maxRecords: Int?
    public var includeTypes: Bool
    
    public init(
        includeMetadata: Bool = true,
        includeStats: Bool = true,
        indentSize: Int = 2,
        sortByField: String? = nil,
        maxRecords: Int? = nil,
        includeTypes: Bool = true
    ) {
        self.includeMetadata = includeMetadata
        self.includeStats = includeStats
        self.indentSize = indentSize
        self.sortByField = sortByField
        self.maxRecords = maxRecords
        self.includeTypes = includeTypes
    }
    
    public static var `default`: PrettyPrintOptions {
        return PrettyPrintOptions()
    }
    
    public static var compact: PrettyPrintOptions {
        return PrettyPrintOptions(
            includeMetadata: false,
            includeStats: false,
            indentSize: 0
        )
    }
}

// MARK: - Pretty Print Extension

extension BlazeDBClient {
    
    /// Export entire database to pretty-printed human-readable text file
    ///
    /// Perfect for:
    /// - Debugging BlazeBinary-encoded databases
    /// - Visual inspection of data
    /// - Sharing database content with team
    /// - Creating readable backups
    ///
    /// Example output:
    /// ```
    /// ╔════════════════════════════════════════════════════════════════╗
    /// ║                     BLAZEDB DEBUG EXPORT                       ║
    /// ╚════════════════════════════════════════════════════════════════╝
    ///
    /// Database: AshPile
    /// Records: 10,000
    /// Storage Format: BlazeBinary v1.0 (53% smaller than JSON)
    /// File Size: 4.0 MB
    ///
    /// ────────────────────────────────────────────────────────────────
    /// Record #1
    /// ────────────────────────────────────────────────────────────────
    ///   id: 550e8400-e29b-41d4-a716-446655440000 (UUID)
    ///   title: "App crashes on startup" (String)
    ///   priority: 5 (Int)
    ///   status: "open" (String)
    ///   createdAt: 2025-11-12T10:30:00Z (Date)
    /// ```
    ///
    /// - Parameters:
    ///   - fileURL: Where to save the text file
    ///   - options: Formatting options
    /// - Throws: If export fails
    public func prettyPrintToFile(_ fileURL: URL, options: PrettyPrintOptions = .default) throws {
        BlazeLogger.info("📝 Exporting database to pretty-printed text file...")
        
        var output = ""
        let indent = String(repeating: " ", count: options.indentSize)
        
        // HEADER
        output += "╔════════════════════════════════════════════════════════════════╗\n"
        output += "║                     BLAZEDB DEBUG EXPORT                       ║\n"
        output += "╚════════════════════════════════════════════════════════════════╝\n\n"
        
        // METADATA
        if options.includeMetadata {
            output += "Database: \(name)\n"
            output += "Project: \(project)\n"
            output += "File: \(fileURL.path)\n"
            output += "Storage Format: \(getStorageFormat())\n"
            output += "Export Date: \(Date().description)\n"
            output += "\n"
        }
        
        // STATS
        if options.includeStats {
            let stats = try getEncodingStats()
            // Note: getStorageStats is async, skip for sync prettyPrint
            // Use prettyPrintAsync for full stats
            
            output += "════════════════════════════════════════════════════════════════\n"
            output += "DATABASE STATISTICS\n"
            output += "════════════════════════════════════════════════════════════════\n"
            output += "Records: \(stats.recordCount)\n"
            output += "BlazeBinary Size: \(stats.blazeBinarySize / 1024) KB\n"
            output += "JSON Size (comparison): \(stats.jsonSize / 1024) KB\n"
            output += "Savings: \(String(format: "%.1f", stats.savings))%\n"
            output += "Compression Ratio: \(String(format: "%.2f", stats.compressionRatio))x\n"
            output += "Avg Record Size: \(stats.avgRecordSize) bytes\n"
            output += "\n"
        }
        
        // RECORDS
        var records = try fetchAll()
        
        // Sort if requested
        if let sortField = options.sortByField {
            records.sort { r1, r2 in
                guard let v1 = r1.storage[sortField],
                      let v2 = r2.storage[sortField] else {
                    return false
                }
                return String(describing: v1) < String(describing: v2)
            }
        }
        
        // Limit if requested
        if let maxRecords = options.maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        
        output += "════════════════════════════════════════════════════════════════\n"
        output += "RECORDS (\(records.count) total)\n"
        output += "════════════════════════════════════════════════════════════════\n\n"
        
        // Print each record
        for (index, record) in records.enumerated() {
            output += "────────────────────────────────────────────────────────────────\n"
            output += "Record #\(index + 1)\n"
            output += "────────────────────────────────────────────────────────────────\n"
            
            // Sort fields for consistent output
            let sortedFields = record.storage.sorted { $0.key < $1.key }
            
            for (key, value) in sortedFields {
                let typeInfo = options.includeTypes ? " (\(value.typeName))" : ""
                output += "\(indent)\(key): \(value.prettyString)\(typeInfo)\n"
            }
            
            output += "\n"
        }
        
        // FOOTER
        output += "════════════════════════════════════════════════════════════════\n"
        output += "END OF EXPORT\n"
        output += "════════════════════════════════════════════════════════════════\n"
        
        // Write to file
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
        
        BlazeLogger.info("✅ Database exported to: \(fileURL.path)")
        print("✅ Exported \(records.count) records to: \(fileURL.lastPathComponent)")
    }
    
    /// Quick pretty-print to console (for debugging)
    ///
    /// - Parameter limit: Max records to print (default: 10)
    public func prettyPrint(limit: Int = 10) throws {
        let records = try fetchAll().prefix(limit)
        
        print("\n╔════════════════════════════════════════════════════════════════╗")
        print("║                     \(name) - Quick View                      ")
        print("╚════════════════════════════════════════════════════════════════╝\n")
        
        for (index, record) in records.enumerated() {
            print("Record #\(index + 1):")
            for (key, value) in record.storage.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value.prettyString)")
            }
            print("")
        }
        
        let total = try fetchAll().count
        if total > limit {
            print("... and \(total - limit) more records\n")
        }
    }
    
    /// Export to Markdown table format
    ///
    /// - Parameters:
    ///   - fileURL: Where to save markdown file
    ///   - fields: Fields to include in table
    /// - Throws: If export fails
    public func exportAsMarkdownTable(_ fileURL: URL, fields: [String]) throws {
        let records = try fetchAll()
        
        var markdown = "# \(name) Database Export\n\n"
        markdown += "**Records:** \(records.count)  \n"
        markdown += "**Exported:** \(Date().description)  \n\n"
        
        // Table header
        markdown += "| "
        markdown += fields.joined(separator: " | ")
        markdown += " |\n"
        
        // Separator
        markdown += "| "
        markdown += fields.map { _ in "---" }.joined(separator: " | ")
        markdown += " |\n"
        
        // Rows
        for record in records {
            markdown += "| "
            let values = fields.map { field in
                record.storage[field]?.prettyString ?? "—"
            }
            markdown += values.joined(separator: " | ")
            markdown += " |\n"
        }
        
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        
        BlazeLogger.info("✅ Markdown table exported to: \(fileURL.path)")
    }
    
    /// Export to CSV format
    ///
    /// - Parameters:
    ///   - fileURL: Where to save CSV file
    ///   - fields: Fields to include
    /// - Throws: If export fails
    public func exportAsCSV(_ fileURL: URL, fields: [String]) throws {
        let records = try fetchAll()
        
        var csv = ""
        
        // Header
        csv += fields.joined(separator: ",")
        csv += "\n"
        
        // Rows
        for record in records {
            let values = fields.map { field in
                let value = record.storage[field]?.prettyString ?? ""
                // Escape commas and quotes
                if value.contains(",") || value.contains("\"") {
                    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return value
            }
            csv += values.joined(separator: ",")
            csv += "\n"
        }
        
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        
        BlazeLogger.info("✅ CSV exported to: \(fileURL.path)")
    }
}

// MARK: - Field Value Extensions

extension BlazeDocumentField {
    
    /// Type name for debugging
    var typeName: String {
        switch self {
        case .string: return "String"
        case .int: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .uuid: return "UUID"
        case .date: return "Date"
        case .data: return "Data"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        case .vector: return "Vector"
        case .null: return "Null"
        }
    }
    
    /// Pretty string representation
    var prettyString: String {
        switch self {
        case .string(let s):
            return "\"\(s)\""
        case .int(let i):
            return "\(i)"
        case .double(let d):
            return String(format: "%.6f", d)
        case .bool(let b):
            return b ? "true" : "false"
        case .uuid(let u):
            return u.uuidString
        case .date(let d):
            return ISO8601DateFormatter().string(from: d)
        case .data(let d):
            return "<\(d.count) bytes: \(d.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))...>"
        case .array(let arr):
            if arr.isEmpty {
                return "[]"
            }
            return "[\(arr.count) items]"
        case .dictionary(let dict):
            if dict.isEmpty {
                return "{}"
            }
            return "{\(dict.count) keys}"
        case .vector(let vec):
            return "<Vector: \(vec.count) dimensions>"
        case .null:
            return "null"
        }
    }
    
    /// Detailed pretty string (for nested structures)
    func prettyString(indent: Int = 0) -> String {
        let indentStr = String(repeating: "  ", count: indent)
        
        switch self {
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            var result = "[\n"
            for (index, item) in arr.enumerated() {
                result += "\(indentStr)  [\(index)]: \(item.prettyString(indent: indent + 1))\n"
            }
            result += "\(indentStr)]"
            return result
            
        case .dictionary(let dict):
            if dict.isEmpty { return "{}" }
            var result = "{\n"
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                result += "\(indentStr)  \(key): \(value.prettyString(indent: indent + 1))\n"
            }
            result += "\(indentStr)}"
            return result
            
        default:
            return prettyString
        }
    }
}

// MARK: - Advanced Export Formats

extension BlazeDBClient {
    
    /// Export database with detailed formatting (nested structures expanded)
    ///
    /// - Parameters:
    ///   - fileURL: Output file
    ///   - expandNested: Expand arrays and dictionaries
    /// - Throws: If export fails
    public func prettyPrintDetailed(_ fileURL: URL, expandNested: Bool = true) throws {
        var output = ""
        
        // Header
        output += "╔════════════════════════════════════════════════════════════════╗\n"
        output += "║              BLAZEDB DETAILED DEBUG EXPORT                     ║\n"
        output += "╚════════════════════════════════════════════════════════════════╝\n\n"
        
        // Database info
        output += "Database: \(name)\n"
        output += "Format: \(getStorageFormat())\n"
        output += "Exported: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        
        // Stats
        let stats = try getEncodingStats()
        output += "Records: \(stats.recordCount)\n"
        output += "Storage: \(stats.blazeBinarySize / 1024) KB (BlazeBinary)\n"
        output += "Savings: \(String(format: "%.1f", stats.savings))% vs JSON\n\n"
        
        let records = try fetchAll()
        
        output += "════════════════════════════════════════════════════════════════\n"
        output += "RECORDS\n"
        output += "════════════════════════════════════════════════════════════════\n\n"
        
        for (index, record) in records.enumerated() {
            output += "┌─ Record #\(index + 1) ────────────────────────────────────────┐\n"
            
            for (key, value) in record.storage.sorted(by: { $0.key < $1.key }) {
                if expandNested {
                    output += "│ \(key): \(value.prettyString(indent: 1))\n"
                } else {
                    output += "│ \(key): \(value.prettyString) (\(value.typeName))\n"
                }
            }
            
            output += "└────────────────────────────────────────────────────────────────┘\n\n"
        }
        
        output += "════════════════════════════════════════════════════════════════\n"
        output += "END OF EXPORT - \(records.count) records total\n"
        output += "════════════════════════════════════════════════════════════════\n"
        
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
        
        print("✅ Detailed export saved to: \(fileURL.lastPathComponent)")
        print("   Records: \(records.count)")
        print("   Size: \(output.utf8.count / 1024) KB")
    }
    
    /// Export database schema (all unique field names and types)
    ///
    /// Useful for understanding database structure.
    ///
    /// - Parameter fileURL: Output file
    /// - Throws: If export fails
    public func exportSchema(_ fileURL: URL) throws {
        let records = try fetchAll()
        
        // Collect all field names and types
        var schema: [String: Set<String>] = [:]
        
        for record in records {
            for (key, value) in record.storage {
                if schema[key] == nil {
                    schema[key] = Set()
                }
                schema[key]?.insert(value.typeName)
            }
        }
        
        var output = ""
        output += "╔════════════════════════════════════════════════════════════════╗\n"
        output += "║                     DATABASE SCHEMA                            ║\n"
        output += "╚════════════════════════════════════════════════════════════════╝\n\n"
        
        output += "Database: \(name)\n"
        output += "Total Records: \(records.count)\n"
        output += "Unique Fields: \(schema.count)\n\n"
        
        output += "════════════════════════════════════════════════════════════════\n"
        output += "FIELDS\n"
        output += "════════════════════════════════════════════════════════════════\n\n"
        
        for (field, types) in schema.sorted(by: { $0.key < $1.key }) {
            let typeList = types.sorted().joined(separator: ", ")
            
            // Count occurrences
            let count = records.filter { $0.storage[field] != nil }.count
            let percentage = Double(count) / Double(records.count) * 100
            
            output += "• \(field)\n"
            output += "    Types: \(typeList)\n"
            output += "    Present in: \(count)/\(records.count) records (\(String(format: "%.1f", percentage))%)\n\n"
        }
        
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
        
        print("✅ Schema exported to: \(fileURL.lastPathComponent)")
        print("   Fields: \(schema.count)")
    }
    
    /// Quick debug dump to console (shows structure)
    ///
    /// - Parameter limit: Max records to show
    public func debugDump(limit: Int = 5) throws {
        print("\n╔════════════════════════════════════════════════════════════════╗")
        print("║                    \(name) - Quick Dump                       ")
        print("╚════════════════════════════════════════════════════════════════╝\n")
        
        let stats = try getEncodingStats()
        print("Records: \(stats.recordCount)")
        print("Storage: \(stats.blazeBinarySize / 1024) KB")
        print("Savings: \(String(format: "%.1f", stats.savings))% vs JSON")
        print("Format: BlazeBinary v1.0\n")
        
        let records = try fetchAll().prefix(limit)
        
        for (index, record) in records.enumerated() {
            print("Record #\(index + 1):")
            for (key, value) in record.storage.sorted(by: { $0.key < $1.key }) {
                print("  • \(key): \(value.prettyString)")
            }
            print("")
        }
        
        let total = try fetchAll().count
        if total > limit {
            print("... and \(total - limit) more records\n")
        }
    }
}

