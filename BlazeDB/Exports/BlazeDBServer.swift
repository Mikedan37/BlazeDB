//
//  BlazeDBServer.swift
//  BlazeDB
//
//  High-level server helper for running BlazeDB in "server mode"
//  over the BlazeBinary protocol on a TCP port.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Configuration for running BlazeDB in server mode.
///
/// This is designed so a backend SwiftPM executable can do:
///
/// ```swift
/// import BlazeDB
///
/// @main
/// struct Main {
///     static func main() async throws {
///         let config = BlazeDBServerConfig(
///             databaseName: "ServerMainDB",
///             password: "change-me",
///             port: 9090
///         )
///         _ = try await BlazeDBServer.start(config)
///         RunLoop.main.run()
///     }
/// }
/// ```
public struct BlazeDBServerConfig {
    /// Logical database name (used with the convenience API and for discovery).
    public let databaseName: String
    /// Encryption password for the database.
    public let password: String
    /// Optional project namespace for the database.
    public let project: String
    /// TCP port to listen on for BlazeBinary sync traffic.
    public let port: UInt16
    /// Optional auth token all clients must present.
    public let authToken: String?
    /// Optional shared secret used to derive per‑database auth tokens.
    public let sharedSecret: String?
    
    public init(
        databaseName: String,
        password: String,
        project: String = "BlazeServer",
        port: UInt16 = 9090,
        authToken: String? = nil,
        sharedSecret: String? = nil
    ) {
        self.databaseName = databaseName
        self.password = password
        self.project = project
        self.port = port
        self.authToken = authToken
        self.sharedSecret = sharedSecret
    }
}

/// High-level entry point for running BlazeDB in server mode.
///
/// This wraps `BlazeServer` and the convenience database APIs so that a
/// backend can spin up a BlazeBinary TCP server with just a few lines of code.
public enum BlazeDBServer {
    
    /// Start a BlazeDB server using the given configuration.
    ///
    /// - Parameter config: Server configuration (database name, password, port, auth).
    /// - Returns: The underlying `BlazeServer` actor so callers can stop it or query state.
    @discardableResult
    public static func start(_ config: BlazeDBServerConfig) async throws -> BlazeServer {
        // Create or open the database using the convenience API (Application Support/BlazeDB).
        let client = try BlazeDBClient(
            name: config.databaseName,
            password: config.password,
            project: config.project
        )
        
        // Register in the global registry so other components can discover it by name.
        BlazeDBClient.registerDatabase(name: config.databaseName, client: client)
        
        // Create the low-level server that listens on a TCP port and speaks BlazeBinary.
        let server = BlazeServer(
            port: config.port,
            database: client,
            databaseName: config.databaseName,
            authToken: config.authToken,
            sharedSecret: config.sharedSecret
        )
        
        try await server.start()
        return server
    }
}
#endif // !BLAZEDB_LINUX_CORE

