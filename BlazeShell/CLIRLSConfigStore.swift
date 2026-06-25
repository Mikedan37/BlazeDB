//
//  CLIRLSConfigStore.swift
//  BlazeCLICore
//

import Foundation
import BlazeDBCore

public struct CLIRLSPolicySpec: Codable, Equatable, Sendable {
    public let preset: String
    public let ownerField: String?
    public let teamField: String?

    public init(preset: String, ownerField: String?, teamField: String?) {
        self.preset = preset
        self.ownerField = ownerField
        self.teamField = teamField
    }
}

public struct CLIRLSConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var policies: [CLIRLSPolicySpec]

    public init(enabled: Bool, policies: [CLIRLSPolicySpec]) {
        self.enabled = enabled
        self.policies = policies
    }

    public static let empty = CLIRLSConfig(enabled: false, policies: [])
}

public enum CLIRLSConfigStore {
    public static func configURL(forDBPath dbPath: String) -> URL {
        let dbURL = URL(fileURLWithPath: dbPath)
        let fileName = "." + dbURL.lastPathComponent + ".rls.json"
        return dbURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    public static func load(forDBPath dbPath: String) throws -> CLIRLSConfig {
        let url = configURL(forDBPath: dbPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CLIRLSConfig.self, from: data)
    }

    public static func save(_ config: CLIRLSConfig, forDBPath dbPath: String) throws {
        let url = configURL(forDBPath: dbPath)
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }

    public static func apply(_ config: CLIRLSConfig, to client: BlazeDBClient) {
        client.clearRLSPolicies()
        for policy in config.policies {
            switch policy.preset {
            case "admin-owner":
                client.configureRLSAdminAndOwnerPolicies(userIDField: policy.ownerField ?? "ownerId")
            case "admin-team":
                client.configureRLSAdminAndTeamPolicies(teamIDField: policy.teamField ?? "teamId")
            case "viewer-readonly":
                client.configureRLSViewerReadOnlyPolicies()
            default:
                continue
            }
        }

        if config.enabled {
            client.enableRLS()
        } else {
            client.disableRLS()
        }
    }

    @discardableResult
    public static func loadAndApply(forDBPath dbPath: String, to client: BlazeDBClient) throws -> CLIRLSConfig {
        let config = try load(forDBPath: dbPath)
        apply(config, to: client)
        return config
    }
}
