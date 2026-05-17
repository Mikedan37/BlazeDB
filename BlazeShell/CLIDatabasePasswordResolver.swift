//
//  CLIDatabasePasswordResolver.swift
//  BlazeCLICore
//

import Foundation

public enum CLIDatabasePasswordResolver {
    public static func resolve(
        path: String,
        masterMode: Bool,
        explicitPassword: String?,
        envPassword: String?,
        fallbackPrompt: Bool,
        readMasterPassphrase: () throws -> String,
        readStandardPassword: () throws -> String,
        readDatabasePassword: () throws -> String,
        resolveStoredSecret: (_ passphrase: String, _ dbPath: String) throws -> String?
    ) throws -> String {
        if masterMode {
            let passphrase = try readMasterPassphrase()
            if let stored = try resolveStoredSecret(passphrase, path) {
                return stored
            }
            if fallbackPrompt {
                return try readDatabasePassword()
            }
            throw NSError(
                domain: "blazedb.master",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No stored secret for this database"]
            )
        }

        if let explicitPassword, !explicitPassword.isEmpty {
            return explicitPassword
        }
        if let envPassword, !envPassword.isEmpty {
            return envPassword
        }
        if fallbackPrompt {
            return try readStandardPassword()
        }
        throw NSError(
            domain: "blazedb.password",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Password required"]
        )
    }
}
