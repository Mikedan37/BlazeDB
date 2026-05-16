//
//  CLIPaths.swift
//  BlazeCLICore
//

import Foundation
import BlazeDBCore

public enum CLIPaths {
    /// Registry JSON next to other BlazeDB app data (PathResolver default directory).
    public static func registryURL() throws -> URL {
        let base = try PathResolver.defaultDatabaseDirectory()
        return base.appendingPathComponent("cli-registry.json", isDirectory: false)
    }

    /// Master keyring envelope.
    /// Uses a dedicated hidden directory under the user's home.
    public static func masterKeyringURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["BLAZEDB_MASTER_KEYRING_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".blazedb", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("keyring.json.enc", isDirectory: false)
    }
}
