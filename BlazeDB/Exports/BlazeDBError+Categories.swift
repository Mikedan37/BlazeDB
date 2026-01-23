//
//  BlazeDBError+Categories.swift
//  BlazeDB
//
//  Error categorization and user-friendly presentation
//  No core logic changes - presentation layer only
//

import Foundation

extension BlazeDBError {
    
    /// Error category for user guidance
    public enum Category {
        case corruption
        case schemaMismatch
        case missingIndex
        case encryptionKey
        case ioFailure
        case invalidInput
        case transaction
        case migration
        case other
    }
    
    /// Categorize error for user guidance
    public var category: Category {
        switch self {
        case .corruptedData:
            return .corruption
        case .invalidField, .invalidData:
            return .schemaMismatch
        case .indexNotFound:
            return .missingIndex
        case .passwordTooWeak, .permissionDenied:
            return .encryptionKey
        case .diskFull, .databaseLocked:
            return .ioFailure
        case .invalidInput:
            return .invalidInput
        case .transactionFailed:
            return .transaction
        case .migrationFailed:
            return .migration
        default:
            return .other
        }
    }
    
    /// User-friendly category name
    public var categoryName: String {
        switch category {
        case .corruption: return "Data Corruption"
        case .schemaMismatch: return "Schema Mismatch"
        case .missingIndex: return "Missing Index"
        case .encryptionKey: return "Encryption/Key Issue"
        case .ioFailure: return "I/O Failure"
        case .invalidInput: return "Invalid Input"
        case .transaction: return "Transaction Error"
        case .migration: return "Migration Error"
        case .other: return "Other Error"
        }
    }
    
    /// Actionable guidance for the user
    public var guidance: String {
        switch self {
        case .corruptedData:
            return "Restore from backup if available. Run 'blazedb doctor' to check database health."
        case .invalidField:
            return "Check your data model matches the expected schema. Verify field types."
        case .indexNotFound:
            return "Create the missing index for better performance, or use a different query."
        case .passwordTooWeak:
            return "Use a stronger password (8+ chars, letters, numbers, special characters)."
        case .permissionDenied:
            return "Check file permissions and app sandbox entitlements. On Linux, ensure directory is writable (chmod 755)."
        case .databaseLocked:
            return "Close other instances of the database and try again."
        case .diskFull:
            return "Free up disk space and retry the operation."
        case .invalidInput(let reason):
            // Check if it's a path-related error
            if reason.contains("directory") || reason.contains("path") {
                return "Ensure the directory exists and is writable. Use BlazeDB.openDefault() for automatic directory creation."
            }
            return "Check your input parameters."
        case .migrationFailed:
            return "Restore from backup. Migration cannot proceed safely."
        case .transactionFailed:
            return "All changes have been rolled back. Check the underlying error and retry."
        default:
            return "See error message for details."
        }
    }
    
    /// Formatted error for CLI/tooling output
    public var formattedDescription: String {
        var output = "❌ \(categoryName): \(errorDescription ?? "Unknown error")\n"
        output += "   💡 \(guidance)"
        return output
    }
}
