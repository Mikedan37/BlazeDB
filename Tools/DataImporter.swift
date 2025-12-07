//
//  DataImporter.swift
//  BlazeDB Migration Tools
//
//  Bulk import from CSV and JSON files
//

import Foundation

// MARK: - BlazeDBClient Extensions for Import

extension BlazeDBClient {
    
    /// Import records from a JSON file
    ///
    /// Expected JSON format:
    /// ```json
    /// [
    ///   {"id": "uuid", "title": "Bug 1", "priority": 5},
    ///   {"id": "uuid", "title": "Bug 2", "priority": 3}
    /// ]
    /// ```
    ///
    /// - Parameters:
    ///   - url: URL to JSON file
    ///   - collection: Optional collection name to tag records
    /// - Returns: Number of records imported
    /// - Throws: Error if import fails
    ///
    /// Example:
    /// ```swift
    /// let url = Bundle.main.url(forResource: "users", withExtension: "json")!
    /// let count = try db.importJSON(from: url)
    /// print("✅ Imported \(count) records")
    /// ```
    @discardableResult
    public func importJSON(from url: URL, collection: String? = nil) throws -> Int {
        let data = try Data(contentsOf: url)
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MigrationError.invalidData("JSON must be an array of objects")
        }
        
        var records: [BlazeDataRecord] = []
        
        for jsonObject in jsonArray {
            var storage: [String: BlazeDocumentField] = [:]
            
            if let collection = collection {
                storage["_collection"] = .string(collection)
            }
            
            for (key, value) in jsonObject {
                storage[key] = convertJSONValue(value)
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        // Batch insert for performance
        if !records.isEmpty {
            _ = try insertMany(records)
            print("✅ Imported \(records.count) records from JSON")
        }
        
        return records.count
    }
    
    /// Import records from a CSV file
    ///
    /// Expected CSV format:
    /// ```csv
    /// title,priority,status
    /// "Bug 1",5,"open"
    /// "Bug 2",3,"closed"
    /// ```
    ///
    /// - Parameters:
    ///   - url: URL to CSV file
    ///   - hasHeader: Whether first row contains column names (default: true)
    ///   - delimiter: Field delimiter (default: ",")
    ///   - collection: Optional collection name to tag records
    /// - Returns: Number of records imported
    /// - Throws: Error if import fails
    ///
    /// Example:
    /// ```swift
    /// let url = Bundle.main.url(forResource: "bugs", withExtension: "csv")!
    /// let count = try db.importCSV(from: url, hasHeader: true)
    /// print("✅ Imported \(count) records")
    /// ```
    @discardableResult
    public func importCSV(from url: URL, hasHeader: Bool = true, delimiter: String = ",", collection: String? = nil) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            throw MigrationError.invalidData("CSV file is empty")
        }
        
        // Parse header
        let headers: [String]
        let startRow: Int
        
        if hasHeader {
            headers = parseCSVLine(lines[0], delimiter: delimiter)
            startRow = 1
        } else {
            // Generate column names: col0, col1, col2, ...
            let firstRow = parseCSVLine(lines[0], delimiter: delimiter)
            headers = (0..<firstRow.count).map { "col\($0)" }
            startRow = 0
        }
        
        // Parse rows
        var records: [BlazeDataRecord] = []
        
        for i in startRow..<lines.count {
            let values = parseCSVLine(lines[i], delimiter: delimiter)
            
            guard values.count == headers.count else {
                print("⚠️ Skipping row \(i): column count mismatch")
                continue
            }
            
            var storage: [String: BlazeDocumentField] = [:]
            
            if let collection = collection {
                storage["_collection"] = .string(collection)
            }
            
            for (index, header) in headers.enumerated() {
                let value = values[index]
                storage[header] = inferType(from: value)
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        // Batch insert for performance
        if !records.isEmpty {
            _ = try insertMany(records)
            print("✅ Imported \(records.count) records from CSV")
        }
        
        return records.count
    }
    
    // MARK: - Private Helpers
    
    private func convertJSONValue(_ value: Any) -> BlazeDocumentField {
        switch value {
        case let string as String:
            // Try to parse as UUID
            if let uuid = UUID(uuidString: string) {
                return .uuid(uuid)
            }
            // Try to parse as Date (ISO8601)
            if let date = ISO8601DateFormatter().date(from: string) {
                return .date(date)
            }
            return .string(string)
            
        case let int as Int:
            return .int(int)
            
        case let double as Double:
            return .double(double)
            
        case let bool as Bool:
            return .bool(bool)
            
        case let array as [Any]:
            return .array(array.map { convertJSONValue($0) })
            
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { convertJSONValue($0) })
            
        default:
            return .string(String(describing: value))
        }
    }
    
    private func parseCSVLine(_ line: String, delimiter: String) -> [String] {
        var values: [String] = []
        var currentValue = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if String(char) == delimiter && !insideQuotes {
                values.append(currentValue.trimmingCharacters(in: .whitespaces))
                currentValue = ""
            } else {
                currentValue.append(char)
            }
        }
        
        values.append(currentValue.trimmingCharacters(in: .whitespaces))
        return values
    }
    
    private func inferType(from string: String) -> BlazeDocumentField {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try Int
        if let intValue = Int(trimmed) {
            return .int(intValue)
        }
        
        // Try Double
        if let doubleValue = Double(trimmed) {
            return .double(doubleValue)
        }
        
        // Try Bool
        if trimmed.lowercased() == "true" {
            return .bool(true)
        }
        if trimmed.lowercased() == "false" {
            return .bool(false)
        }
        
        // Try UUID
        if let uuid = UUID(uuidString: trimmed) {
            return .uuid(uuid)
        }
        
        // Try Date (ISO8601)
        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return .date(date)
        }
        
        // Default to String
        return .string(trimmed)
    }
}

