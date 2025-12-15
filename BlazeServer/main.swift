//
//  main.swift
//  BlazeServer
//
//  Minimal executable entry point for running BlazeDB in server mode.
//

import Foundation
import BlazeDB

@main
struct BlazeServerMain {
    static func main() async {
        // Read configuration from environment with sensible defaults so this
        // works both locally and inside Docker.
        let env = ProcessInfo.processInfo.environment
        
        let databaseName = env["BLAZEDB_DB_NAME"] ?? "ServerMainDB"
        let password = env["BLAZEDB_PASSWORD"] ?? "change-me"
        let project = env["BLAZEDB_PROJECT"] ?? "BlazeServer"
        
        let port: UInt16 = {
            if let portStr = env["BLAZEDB_PORT"], let parsed = UInt16(portStr) {
                return parsed
            }
            return 9090
        }()
        
        let authToken = env["BLAZEDB_AUTH_TOKEN"]
        let sharedSecret = env["BLAZEDB_SHARED_SECRET"]
        
        let config = BlazeDBServerConfig(
            databaseName: databaseName,
            password: password,
            project: project,
            port: port,
            authToken: authToken,
            sharedSecret: sharedSecret
        )
        
        do {
            _ = try await BlazeDBServer.start(config)
            BlazeLogger.info("✅ BlazeServer started successfully")
            BlazeLogger.info("📡 Listening on port \(port)")
            BlazeLogger.info("💾 Database: \(databaseName)")
            BlazeLogger.info("🔐 Authentication: \(authToken != nil ? "enabled" : "disabled")")
            BlazeLogger.info("🚀 Server ready to accept connections")
            // Keep the process alive indefinitely.
            RunLoop.main.run()
        } catch {
            BlazeLogger.error("❌ Failed to start BlazeServer", error: error)
            exit(1)
        }
    }
}


