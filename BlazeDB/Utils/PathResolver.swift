//
//  PathResolver.swift
//  BlazeDB
//
//  Platform-safe path resolution and directory management
//  Ensures Linux and macOS compatibility
//

import Foundation

/// Platform-safe path resolver
///
/// Provides consistent, safe default paths across platforms.
/// Handles directory creation and permission errors explicitly.
public struct PathResolver {
    
    /// Get default database directory for current platform
    ///
    /// - Returns: URL to default directory
    /// - Throws: Error if directory cannot be determined or created
    ///
    /// Platform-specific defaults:
    /// - macOS: ~/Library/Application Support/BlazeDB
    /// - Linux: ~/.local/share/blazedb
    public static func defaultDatabaseDirectory() throws -> URL {
        #if os(macOS) || os(iOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support/BlazeDB")
        #elseif os(Linux)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent(".local/share/blazedb")
        #else
        // Fallback to temp directory
        let appSupport = FileManager.default.temporaryDirectory.appendingPathComponent("BlazeDB")
        #endif
        
        // Create directory if it doesn't exist
        try createDirectoryIfNeeded(at: appSupport)
        
        return appSupport
    }
    
    /// Create directory if it doesn't exist
    ///
    /// - Parameter url: Directory URL
    /// - Throws: Error if creation fails or permissions are insufficient
    private static func createDirectoryIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        
        // Check if directory exists
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if exists {
            // Verify it's actually a directory
            if !isDirectory.boolValue {
                throw BlazeDBError.invalidInput(
                    reason: "Path exists but is not a directory: \(url.path)"
                )
            }
            // Verify we can write to it
            if !fileManager.isWritableFile(atPath: url.path) {
                throw BlazeDBError.permissionDenied(
                    operation: "write",
                    path: url.path
                )
            }
            return
        }
        
        // Create directory (including intermediate directories)
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o755  // rwxr-xr-x
                ]
            )
        } catch {
            throw BlazeDBError.permissionDenied(
                operation: "create directory",
                path: url.path
            )
        }
        
        // Verify creation succeeded
        guard fileManager.fileExists(atPath: url.path) else {
            throw BlazeDBError.invalidInput(
                reason: "Failed to create directory: \(url.path)"
            )
        }
    }
    
    /// Resolve database path (handles relative and absolute paths)
    ///
    /// - Parameters:
    ///   - path: Path string (relative or absolute)
    ///   - baseDirectory: Base directory for relative paths (defaults to current directory)
    /// - Returns: Resolved URL
    /// - Throws: Error if path is invalid
    public static func resolveDatabasePath(
        _ path: String,
        baseDirectory: URL? = nil
    ) throws -> URL {
        let base = baseDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        if path.hasPrefix("/") || path.hasPrefix("~") {
            // Absolute path
            let expanded = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        } else {
            // Relative path
            return base.appendingPathComponent(path)
        }
    }
    
    /// Validate database path
    ///
    /// - Parameter url: Database URL
    /// - Throws: Error if path is invalid
    public static func validateDatabasePath(_ url: URL) throws {
        let path = url.path
        
        // Check for path traversal
        if path.contains("..") {
            throw BlazeDBError.invalidInput(
                reason: "Path contains '..' (path traversal): \(path)"
            )
        }
        
        // Check parent directory exists and is writable
        let parent = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: parent.path) {
            throw BlazeDBError.invalidInput(
                reason: "Parent directory does not exist: \(parent.path)"
            )
        }
        
        if !fileManager.isWritableFile(atPath: parent.path) {
            throw BlazeDBError.permissionDenied(
                operation: "create database",
                path: parent.path
            )
        }
    }
}
