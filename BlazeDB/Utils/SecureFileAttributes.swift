//
//  SecureFileAttributes.swift
//  BlazeDB
//
//  Owner-only creation helpers for sensitive on-disk material (#357 / #324).
//

import Foundation

/// Owner-only creation helpers for sensitive on-disk material (#357 / #324).
public enum SecureFileAttributes {
    public static let ownerOnlyFilePermissions: Int = 0o600
    public static let ownerOnlyDirectoryPermissions: Int = 0o700

    /// Restrict an existing path to owner-only on POSIX. No-op when attributes are unavailable.
    public static func restrictToOwnerOnly(at url: URL, directory: Bool = false) {
        #if os(Windows)
        return
        #else
        let mode = directory ? ownerOnlyDirectoryPermissions : ownerOnlyFilePermissions
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: mode],
                ofItemAtPath: url.path
            )
        } catch {
            BlazeLogger.warn("Could not set owner-only permissions on \(url.lastPathComponent): \(error.localizedDescription)")
        }
        #endif
    }

    /// Create an empty file with owner-only mode when supported.
    @discardableResult
    public static func createOwnerOnlyFile(at url: URL) -> Bool {
        #if os(Windows)
        return FileManager.default.createFile(atPath: url.path, contents: nil)
        #else
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: ownerOnlyFilePermissions]
        )
        if created {
            restrictToOwnerOnly(at: url)
        }
        return created
        #endif
    }

    /// Atomically write data then force owner-only permissions (covers umask after `.atomic`).
    public static func writeOwnerOnly(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        restrictToOwnerOnly(at: url)
    }

    /// Create a directory with 0700 when missing.
    public static func ensureOwnerOnlyDirectory(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            #if os(Windows)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            #else
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: ownerOnlyDirectoryPermissions]
            )
            #endif
        }
        restrictToOwnerOnly(at: url, directory: true)
    }
}
