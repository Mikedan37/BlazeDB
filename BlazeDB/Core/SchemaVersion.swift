//
//  SchemaVersion.swift
//  BlazeDB
//
//  Explicit schema versioning for database evolution
//  No storage changes - metadata only
//

import Foundation

/// Schema version identifier
/// 
/// Versions are comparable and ordered.
/// Major version changes indicate breaking changes.
/// Minor version changes indicate additive changes.
///
/// ## Example
/// ```swift
/// let v1_0 = SchemaVersion(major: 1, minor: 0)
/// let v1_1 = SchemaVersion(major: 1, minor: 1)
/// let v2_0 = SchemaVersion(major: 2, minor: 0)
///
/// v1_0 < v1_1  // true
/// v1_1 < v2_0  // true
/// ```
public struct SchemaVersion: Codable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        return lhs.minor < rhs.minor
    }
    
    public static func == (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        return lhs.major == rhs.major && lhs.minor == rhs.minor
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        return "\(major).\(minor)"
    }
    
    /// Returns the next minor version
    public func nextMinor() -> SchemaVersion {
        return SchemaVersion(major: major, minor: minor + 1)
    }
    
    /// Returns the next major version
    public func nextMajor() -> SchemaVersion {
        return SchemaVersion(major: major + 1, minor: 0)
    }
}

/// Schema definition protocol
/// 
/// Applications declare their schema version explicitly.
/// This version is checked on database open.
public protocol BlazeSchema {
    /// Current schema version
    static var version: SchemaVersion { get }
}
