//
//  BlazeDBError+Suggestions.swift
//  BlazeDB
//
//  Enhanced error messages with suggestions and remediation
//  Makes errors teach the user instead of just failing
//

import Foundation

extension BlazeDBError {
    
    /// Enhanced error message with suggestions
    ///
    /// Attempts to provide actionable guidance for common errors.
    public var suggestedMessage: String {
        switch self {
        case .invalidQuery(let reason, let suggestion):
            var msg = "Invalid query: \(reason)"
            if let suggestion = suggestion {
                msg += "\n💡 Suggestion: \(suggestion)"
            }
            return msg
            
        case .indexNotFound(let field, let available):
            var msg = "No index found for field '\(field)'."
            if !available.isEmpty {
                msg += "\n📋 Available indexes: \(available.joined(separator: ", "))"
            }
            msg += "\n💡 Suggestion: Create an index with: db.createIndex(on: \"\(field)\")"
            return msg
            
        case .invalidField(let name, let expected, let actual):
            var msg = "Field '\(name)' has invalid type: expected \(expected) but got \(actual)."
            msg += "\n💡 Suggestion: Check your data model matches the expected schema. Verify field types."
            return msg
            
        case .migrationFailed(let reason, let underlying):
            var msg = "Database migration failed: \(reason)"
            if let underlying = underlying {
                msg += "\n🔍 Underlying error: \(underlying.localizedDescription)"
            }
            msg += "\n💡 Suggestion: Restore from backup if available. Run 'blazedb doctor' to check database health."
            return msg
            
        case .recordNotFound(let id, let collection, let suggestion):
            var msg = "Record not found"
            if let id = id { msg += " with ID: \(id)" }
            if let collection = collection { msg += " in collection '\(collection)'" }
            msg += "."
            if let suggestion = suggestion {
                msg += "\n💡 Suggestion: \(suggestion)"
            } else {
                msg += "\n💡 Suggestion: Verify the ID is correct. The record may have been deleted."
            }
            return msg
            
        case .recordExists(let id, let suggestion):
            var msg = "Record already exists"
            if let id = id { msg += " with ID: \(id)" }
            msg += "."
            if let suggestion = suggestion {
                msg += "\n💡 Suggestion: \(suggestion)"
            } else {
                msg += "\n💡 Suggestion: Use update() to modify existing record or upsert() to insert-or-update."
            }
            return msg
            
        case .permissionDenied(let operation, let path):
            var msg = "Permission denied for operation: \(operation)"
            if let path = path {
                msg += " at path: \(path)"
            }
            msg += "."
            #if os(Linux)
            msg += "\n💡 Suggestion: Check file permissions. Ensure directory is writable (chmod 755)."
            #else
            msg += "\n💡 Suggestion: Check file permissions and app sandbox entitlements."
            #endif
            return msg
            
        case .databaseLocked(let operation, let timeout, let path):
            var msg = "Database is locked for operation: \(operation)"
            if let path = path {
                msg += " at path: \(path.path)"
            }
            if let timeout = timeout {
                msg += " (timeout: \(timeout)s)"
            }
            msg += "."
            msg += "\n💡 Suggestion: Close other instances of the database and try again."
            return msg
            
        case .diskFull(let available):
            var msg = "Disk is full or nearly full."
            if let available = available {
                msg += " Only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available."
            }
            msg += "\n💡 Suggestion: Free up disk space and retry the operation."
            return msg
            
        case .corruptedData(let location, let reason):
            var msg = "Data corruption detected at \(location): \(reason)."
            msg += "\n💡 Suggestion: Restore from backup if available. Run 'blazedb doctor' to check database health."
            return msg
            
        case .passwordTooWeak(let requirements):
            var msg = "Password is too weak. Requirements: \(requirements)."
            msg += "\n💡 Suggestion: Use a stronger password (8+ chars, letters, numbers, special characters)."
            return msg
            
        case .invalidInput(let reason):
            var msg = "Invalid input: \(reason)."
            if reason.contains("directory") || reason.contains("path") {
                msg += "\n💡 Suggestion: Ensure the directory exists and is writable. Use BlazeDB.openDefault() for automatic directory creation."
            } else {
                msg += "\n💡 Suggestion: Check your input parameters."
            }
            return msg
            
        case .transactionFailed(let reason, let underlying):
            var msg = "Transaction failed: \(reason)."
            if let underlying = underlying {
                msg += "\n🔍 Underlying error: \(underlying.localizedDescription)"
            }
            msg += "\n💡 Suggestion: All changes have been rolled back. Check the underlying error and retry."
            return msg
            
        default:
            return localizedDescription
        }
    }
    
    /// Suggest similar field names when a field is not found
    ///
    /// Uses simple prefix matching and Levenshtein-like distance.
    /// - Parameters:
    ///   - targetField: The field name that was not found
    ///   - availableFields: List of available field names
    /// - Returns: Array of suggested field names (up to 3)
    public static func suggestFieldNames(
        targetField: String,
        availableFields: [String]
    ) -> [String] {
        guard !availableFields.isEmpty else { return [] }
        
        let targetLower = targetField.lowercased()
        var suggestions: [(String, Int)] = []
        
        for field in availableFields {
            let fieldLower = field.lowercased()
            
            // Exact match (case-insensitive)
            if fieldLower == targetLower {
                return [field]  // Perfect match, return immediately
            }
            
            // Prefix match
            if fieldLower.hasPrefix(targetLower) || targetLower.hasPrefix(fieldLower) {
                suggestions.append((field, 0))
                continue
            }
            
            // Simple similarity (Levenshtein-lite)
            let distance = simpleEditDistance(targetLower, fieldLower)
            if distance <= 2 {  // Max 2 character differences
                suggestions.append((field, distance))
            }
        }
        
        // Sort by distance, then alphabetically
        suggestions.sort { first, second in
            if first.1 != second.1 {
                return first.1 < second.1
            }
            return first.0 < second.0
        }
        
        return Array(suggestions.prefix(3).map { $0.0 })
    }
    
    /// Simple edit distance calculation (Levenshtein-lite)
    private static func simpleEditDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        
        // Quick check: if lengths differ by more than 2, skip
        if abs(s1Array.count - s2Array.count) > 2 {
            return Int.max
        }
        
        // Simple character-by-character comparison
        var distance = 0
        let minLength = min(s1Array.count, s2Array.count)
        
        for i in 0..<minLength {
            if s1Array[i] != s2Array[i] {
                distance += 1
            }
        }
        
        // Add difference in length
        distance += abs(s1Array.count - s2Array.count)
        
        return distance
    }
}
