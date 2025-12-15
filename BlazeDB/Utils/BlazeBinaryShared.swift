//
//  BlazeBinaryShared.swift
//  BlazeDB
//
//  Shared definitions for BlazeBinary encoder and decoder
//

import Foundation

// MARK: - Common Field Dictionary (Compression Optimization)

/// IMPORTANT: This is an OPTIMIZATION, NOT a limitation!
/// - Common fields (0x01-0x7F): 1 byte encoding (compressed)
/// - Custom fields (0xFF prefix): Full name encoding (uncompressed)
/// - Total fields supported: UNLIMITED! ✅
///
/// Top 127 most common field names get compressed to 1 byte.
/// Any other field name is stored normally (no limit!)
///
/// Example:
/// - "id" → 0x01 (1 byte, compressed)
/// - "myCustomField123" → 0xFF + length + name (uncompressed)
let COMMON_FIELDS: [UInt8: String] = [
    0x01: "id",
    0x02: "createdAt",
    0x03: "updatedAt",
    0x04: "userId",
    0x05: "teamId",
    0x06: "title",
    0x07: "description",
    0x08: "status",
    0x09: "priority",
    0x0A: "assignedTo",
    0x0B: "tags",
    0x0C: "completedAt",
    0x0D: "dueDate",
    0x0E: "startDate",
    0x0F: "category",
    0x10: "name",
    0x11: "email",
    0x12: "password",
    0x13: "username",
    0x14: "firstName",
    0x15: "lastName",
    0x16: "age",
    0x17: "phone",
    0x18: "address",
    0x19: "city",
    0x1A: "state",
    0x1B: "zip",
    0x1C: "country",
    0x1D: "organizationId",
    0x1E: "projectId",
    0x1F: "taskId",
    0x20: "bugId",
    0x21: "issueId",
    0x22: "commentId",
    0x23: "attachmentId",
    0x24: "versionId",
    0x25: "parentId",
    0x26: "childIds",
    0x27: "metadata",
    0x28: "config",
    0x29: "settings",
    0x2A: "preferences",
    0x2B: "type",
    0x2C: "kind",
    0x2D: "label",
    0x2E: "value",
    0x2F: "count",
    0x30: "total",
    0x31: "sum",
    0x32: "average",
    0x33: "min",
    0x34: "max",
    0x35: "isActive",
    0x36: "isDeleted",
    0x37: "isPublic",
    0x38: "isPrivate",
    0x39: "isArchived",
    0x3A: "isFavorite",
    // Can extend up to 0x7F (127 total)
    // Any field NOT in this list: stored with full name (unlimited!)
]

let COMMON_FIELDS_REVERSE: [String: UInt8] = Dictionary(
    uniqueKeysWithValues: COMMON_FIELDS.map { ($1, $0) }
)

// MARK: - Type Tags

enum TypeTag: UInt8 {
    case string = 0x01
    case int = 0x02
    case double = 0x03
    case bool = 0x04
    case uuid = 0x05
    case date = 0x06
    case data = 0x07
    case array = 0x08
    case dictionary = 0x09
    case vector = 0x0A
    case null = 0x0B
    
    // Optimizations:
    case emptyString = 0x11
    case smallInt = 0x12  // 0-255, stored in 1 byte
    case emptyArray = 0x18
    case emptyDict = 0x19
    // 0x20-0x2F: Inline strings (type + length in 1 byte!)
}

// MARK: - BlazeBinary Header

struct BlazeBinaryHeader {
    let magic: (UInt8, UInt8, UInt8, UInt8, UInt8)  // "BLAZE"
    let version: UInt8                               // 0x01
    let fieldCount: UInt16                           // Big-endian
    
    func isMagicValid() -> Bool {
        return magic.0 == 0x42 && magic.1 == 0x4C && magic.2 == 0x41 && 
               magic.3 == 0x5A && magic.4 == 0x45
    }
}

// MARK: - Errors

enum BlazeBinaryError: Error, LocalizedError {
    case invalidFormat(String)
    case unsupportedVersion(UInt8)
    case corruptedData(String)
    case encodingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg):
            return "Invalid BlazeBinary format: \(msg)"
        case .unsupportedVersion(let version):
            return "Unsupported BlazeBinary version: 0x\(String(version, radix: 16))"
        case .corruptedData(let msg):
            return "Corrupted BlazeBinary data: \(msg)"
        case .encodingFailed(let msg):
            return "BlazeBinary encoding failed: \(msg)"
        }
    }
}

