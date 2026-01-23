//
//  BlazeDBClient+Compatibility.swift
//  BlazeDB
//
//  On-disk compatibility contract: format versioning and validation
//  Ensures database format compatibility and provides actionable errors
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension BlazeDBClient {
    
    /// Database format version
    ///
    /// Format versions are incremented when on-disk layout changes in incompatible ways.
    /// BlazeDB will refuse to open databases with incompatible format versions.
    public struct FormatVersion: Sendable {
        /// Major version (incompatible changes)
        public let major: Int
        
        /// Minor version (compatible changes)
        public let minor: Int
        
        /// Patch version (bug fixes)
        public let patch: Int
        
        public init(major: Int, minor: Int, patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }
        
        /// Current format version supported by this BlazeDB build
        public static let current = FormatVersion(major: 1, minor: 0, patch: 0)
        
        /// String representation (e.g., "1.0.0")
        public var description: String {
            return "\(major).\(minor).\(patch)"
        }
        
        /// Check if this version is compatible with another version
        ///
        /// Compatibility rules:
        /// - Same major version: compatible
        /// - Different major version: incompatible
        /// - Minor/patch differences: compatible (minor/patch are for information only)
        public func isCompatible(with other: FormatVersion) -> Bool {
            return self.major == other.major
        }
    }
    
    /// Validate database format version at open time
    ///
    /// - Throws: `BlazeDBError.invalidData` if format version is incompatible
    internal func validateFormatVersion() throws {
        // If meta file doesn't exist, this is a new database - store current version
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            // New database - store current format version
            try storeFormatVersion()
            return
        }
        
        // Read format version from StorageLayout
        let layout: StorageLayout
        do {
            layout = try StorageLayout.load(from: metaURL)
        } catch {
            // If layout can't be loaded, assume legacy version and continue
            // (DynamicCollection will handle layout recovery)
            BlazeLogger.debug("Could not load layout for format validation - assuming compatible")
            return
        }
        
        // Extract format version from layout metadata
        // Format version is stored in metaData as "formatVersion" field
        let formatVersionString: String
        if case let .string(version)? = layout.metaData["formatVersion"] {
            formatVersionString = version
        } else {
            // No format version in metadata - assume version 1.0.0 (legacy)
            BlazeLogger.debug("No format version in metadata - assuming 1.0.0")
            formatVersionString = "1.0.0"
        }
        
        // Parse format version
        let parts = formatVersionString.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else {
            throw BlazeDBError.invalidData(
                reason: "Invalid format version format: '\(formatVersionString)'. Expected 'major.minor.patch'."
            )
        }
        
        let dbVersion = FormatVersion(
            major: parts[0],
            minor: parts.count > 1 ? parts[1] : 0,
            patch: parts.count > 2 ? parts[2] : 0
        )
        
        // Check compatibility
        guard dbVersion.isCompatible(with: .current) else {
            throw BlazeDBError.invalidData(
                reason: """
                Database format version (\(dbVersion.description)) is incompatible with current version (\(FormatVersion.current.description)).
                
                This database was created with a different major version of BlazeDB and cannot be opened.
                
                To resolve:
                1. Export data from the old version: Use the old BlazeDB version to export your data
                2. Upgrade BlazeDB: Install the version that supports format \(dbVersion.description)
                3. Import data: Use the new BlazeDB version to import your exported data
                
                Note: Format version changes are rare and only occur for major incompatible changes.
                """
            )
        }
        
        BlazeLogger.debug("Format version validated: \(dbVersion.description) (compatible with \(FormatVersion.current.description))")
    }
    
    /// Store format version in database metadata
    ///
    /// Called automatically when creating a new database
    internal func storeFormatVersion() throws {
        var layout: StorageLayout
        do {
            layout = try StorageLayout.load(from: metaURL)
        } catch {
            // Layout doesn't exist - create empty one
            layout = StorageLayout.empty()
        }
        
        // Store current format version in metadata
        layout.metaData["formatVersion"] = .string(FormatVersion.current.description)
        
        // Save updated layout
        try layout.save(to: metaURL)
        BlazeLogger.debug("Stored format version: \(FormatVersion.current.description)")
    }
}
