//
//  ServerTransportProvider.swift
//  BlazeDB
//
//  Platform-neutral protocol for server transport (TCP listening)
//  Allows BlazeDB to work on Linux without Network.framework dependency
//
//  Created by Auto on 12/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Protocol for server transport operations (TCP listening, connection handling)
/// Platform-neutral abstraction that allows different implementations per platform
public protocol ServerTransportProvider {
    /// Start listening for connections on the specified port
    /// - Parameter port: Port number to listen on
    /// - Parameter onConnection: Callback when a new connection is established
    /// - Throws: If server cannot be started
    func startServer(port: UInt16, onConnection: @escaping @Sendable (ServerConnection) async -> Void) async throws
    
    /// Stop listening for connections
    func stopServer() async
    
    /// Check if server transport is available on this platform
    /// - Returns: true if server transport is available, false otherwise
    func isAvailable() -> Bool
}

/// Protocol for a server connection (abstracts platform-specific connection types)
public protocol ServerConnection {
    /// Start the connection
    func start() async
    
    /// Cancel/close the connection
    func cancel()
    
    /// Wait for connection to be ready
    /// - Returns: true if connection is ready, false otherwise
    func waitForReady() async -> Bool
    
    #if canImport(Network)
    /// Get the underlying NWConnection (Apple platforms only)
    /// - Returns: The NWConnection instance, or nil if not available
    func getNWConnection() -> NWConnection?
    #endif
}

#if canImport(Network)
import Network

/// Apple platform implementation using Network framework
/// Provides TCP server functionality on iOS/macOS
public final class AppleServerTransportProvider: ServerTransportProvider, @unchecked Sendable {
    private var listener: NWListener?
    private var isRunning = false
    
    public init() {}
    
    public func startServer(port: UInt16, onConnection: @escaping (ServerConnection) async -> Void) async throws {
        guard !isRunning else {
            throw ServerTransportError.alreadyRunning
        }
        
        // Create TCP listener
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw ServerTransportError.invalidPort(port)
        }
        
        let listener = try NWListener(using: parameters, on: port)
        
        // Handle new connections
        let connectionHandler = onConnection  // Capture before Task
        listener.newConnectionHandler = { @Sendable connection in
            Task { @Sendable in
                let serverConnection = AppleServerConnection(connection: connection)
                await connectionHandler(serverConnection)
            }
        }
        
        // Start listening
        listener.start(queue: .global())
        self.listener = listener
        self.isRunning = true
        
        BlazeLogger.info("AppleServerTransportProvider listening on port \(port.rawValue)")
    }
    
    public func stopServer() async {
        guard isRunning else { return }
        
        listener?.cancel()
        listener = nil
        isRunning = false
        
        BlazeLogger.info("AppleServerTransportProvider stopped")
    }
    
    public func isAvailable() -> Bool {
        // Network framework is available on Apple platforms
        return true
    }
}

/// Apple platform server connection wrapper
private final class AppleServerConnection: ServerConnection {
    private let connection: NWConnection
    
    init(connection: NWConnection) {
        self.connection = connection
    }
    
    func start() async {
        connection.start(queue: .global())
    }
    
    func cancel() {
        connection.cancel()
    }
    
    func waitForReady() async -> Bool {
        // Wait for connection to be ready
        return await withCheckedContinuation { continuation in
            let stateUpdateHandler: @Sendable (NWConnection.State) -> Void = { state in
                switch state {
                case .ready:
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    continuation.resume(returning: false)
                default:
                    // Continue waiting
                    break
                }
            }
            
            connection.stateUpdateHandler = stateUpdateHandler
            
            // Check current state immediately
            stateUpdateHandler(connection.state)
        }
    }
    
    #if canImport(Network)
    func getNWConnection() -> NWConnection? {
        return connection
    }
    #endif
}


/// Default provider type for Apple platforms
public typealias DefaultServerTransportProvider = AppleServerTransportProvider

#else

/// No-op implementation for Linux and other non-Apple platforms
/// Performs no actual server operations - all operations are no-ops
/// Suitable for server/headless environments where Network.framework is not available
public final class HeadlessServerTransportProvider: ServerTransportProvider {
    private var isRunning = false
    
    public init() {}
    
    public func startServer(port: UInt16, onConnection: @escaping (ServerConnection) async -> Void) async throws {
        guard !isRunning else {
            throw ServerTransportError.alreadyRunning
        }
        
        isRunning = true
        BlazeLogger.warn("HeadlessServerTransportProvider: Server transport not available on this platform. Server will not accept connections.")
    }
    
    public func stopServer() async {
        guard isRunning else { return }
        isRunning = false
        BlazeLogger.info("HeadlessServerTransportProvider: stopServer called (no-op on Linux)")
    }
    
    public func isAvailable() -> Bool {
        // Server transport is not available on Linux
        return false
    }
}

/// No-op server connection for headless platforms
private final class HeadlessServerConnection: ServerConnection {
    func start() async {
        // No-op
    }
    
    func cancel() {
        // No-op
    }
    
    func waitForReady() async -> Bool {
        // Never ready on headless platform
        return false
    }
    
    #if canImport(Network)
    func getNWConnection() -> NWConnection? {
        return nil
    }
    #endif
}

/// Default provider type for non-Apple platforms
public typealias DefaultServerTransportProvider = HeadlessServerTransportProvider

#endif

/// Errors that can occur during server transport operations
public enum ServerTransportError: Error, LocalizedError {
    case alreadyRunning
    case invalidPort(UInt16)
    case notAvailable
    
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .invalidPort(let port):
            return "Invalid port number: \(port)"
        case .notAvailable:
            return "Server transport is not available on this platform"
        }
    }
}

#endif // !BLAZEDB_LINUX_CORE

