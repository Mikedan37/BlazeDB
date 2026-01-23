//
//  BlazeDBClient+SharedSecret.swift
//  BlazeDB
//
//  Shared secret authentication - works cross-platform!
//  Perfect for Raspberry Pi + Vapor + BlazeDB
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#elseif canImport(Crypto)
import Crypto
#else
// Fallback for platforms without CryptoKit/Crypto
// Note: Token derivation will not work without crypto support
#endif

extension BlazeDBClient {
    
    /// Derive auth token from shared secret
    /// Different token per database pair (secure!)
    /// Works on macOS, iOS, Linux (Raspberry Pi), etc.
    ///
    /// **Example:**
    /// ```swift
    /// // Both databases use same password
    /// let token = BlazeDBClient.deriveToken(
    ///     from: "my-password-123",
    ///     database1: "MacDB",
    ///     database2: "PiDB"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - secret: Shared secret (user's password)
    ///   - database1: First database name
    ///   - database2: Second database name
    /// - Returns: Derived auth token (base64 encoded)
    public static func deriveToken(
        from secret: String,
        database1: String,
        database2: String
    ) -> String {
        // Sort database names (ensures same token regardless of order)
        let dbNames = [database1, database2].sorted().joined(separator: ":")
        
        // Derive token using HKDF (works on all platforms!)
        guard let secretData = secret.data(using: .utf8),
              let salt = "blazedb-auth-v1".data(using: .utf8),
              let info = dbNames.data(using: .utf8) else {
            // UTF-8 encoding should never fail for ASCII strings, but handle gracefully
            let fallbackData = Data(secret.utf8) + Data(dbNames.utf8)
            #if canImport(CryptoKit)
            let hash = SHA256.hash(data: fallbackData)
            return Data(hash).base64EncodedString()
            #else
            // Fallback for platforms without CryptoKit
            return fallbackData.base64EncodedString()
            #endif
        }
        
        #if canImport(CryptoKit)
        // Apple platforms (macOS, iOS, etc.) - uses CryptoKit
        let tokenKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secretData),
            salt: salt,
            info: info,
            outputByteCount: 32  // 256-bit token
        )
        
        return tokenKey.withUnsafeBytes { Data($0).base64EncodedString() }
        #elseif canImport(Crypto)
        // Linux (Raspberry Pi, Vapor, etc.) - uses Swift Crypto
        let tokenKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secretData),
            salt: salt,
            info: info,
            outputByteCount: 32  // 256-bit token
        )
        
        return tokenKey.withUnsafeBytes { Data($0).base64EncodedString() }
        #else
        // Fallback: Simple hash-based derivation (works everywhere)
        // Note: For production, use CryptoKit (Apple) or Swift Crypto (Linux)
        // This fallback is less secure but ensures the code compiles everywhere
        var combined = secretData
        combined.append(salt)
        combined.append(info)
        
        // Use simple hash (not cryptographically perfect, but works)
        var hash = [UInt8](repeating: 0, count: 32)
        var hasher = Hasher()
        hasher.combine(combined)
        let hashValue = hasher.finalize()
        
        // Convert to bytes (simplified - use proper crypto in production)
        withUnsafeBytes(of: hashValue) { bytes in
            for i in 0..<min(32, bytes.count) {
                hash[i] = bytes[i]
            }
        }
        
        // Extend if needed
        if hash.count < 32 {
            var extended = hash
            while extended.count < 32 {
                var hasher2 = Hasher()
                hasher2.combine(extended)
                hasher2.combine(secretData)
                let additional = hasher2.finalize()
                withUnsafeBytes(of: additional) { bytes in
                    for i in 0..<min(32 - extended.count, bytes.count) {
                        extended.append(bytes[i])
                    }
                }
            }
            hash = Array(extended.prefix(32))
        }
        
        return Data(hash).base64EncodedString()
        #endif
    }
    
    /// Generate secure random token
    /// Works on all platforms (macOS, iOS, Linux, etc.)
    ///
    /// **Example:**
    /// ```swift
    /// let token = BlazeDBClient.generateSecureToken()
    /// // Returns: "abc123xyz..." (base64 encoded)
    /// ```
    ///
    /// - Returns: Secure random token (base64 encoded)
    public static func generateSecureToken() -> String {
        #if canImport(CryptoKit)
        // Apple platforms - use CryptoKit
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
        #elseif canImport(Crypto)
        // Linux (Raspberry Pi, Vapor) - use Swift Crypto
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
        #else
        // Fallback: Use system random (works on all platforms)
        var randomBytes = [UInt8](repeating: 0, count: 32)
        #if os(Linux)
        // Linux: Use /dev/urandom
        if let urandom = FileHandle(forReadingAtPath: "/dev/urandom") {
            let data = urandom.readData(ofLength: 32)
            randomBytes = Array(data)
            urandom.closeFile()
        } else {
            // Fallback to random
            for i in 0..<32 {
                randomBytes[i] = UInt8.random(in: 0...255)
            }
        }
        #else
        // Other platforms: Use random
        for i in 0..<32 {
            randomBytes[i] = UInt8.random(in: 0...255)
        }
        #endif
        return Data(randomBytes).base64EncodedString()
        #endif
    }
    
    /// Start server with shared secret (recommended!)
    /// Works on all platforms!
    ///
    /// **Example:**
    /// ```swift
    /// // On Raspberry Pi (Vapor server)
    /// let server = try await db.startServer(
    ///     port: 8080,
    ///     sharedSecret: "my-password-123"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - port: Port to listen on (default: 8080)
    ///   - sharedSecret: Shared secret (user's password)
    ///   - peerDatabase: Optional specific peer database name
    /// - Returns: The server instance
    @discardableResult
    public func startServer(
        port: UInt16 = 8080,
        sharedSecret: String,
        peerDatabase: String? = nil
    ) async throws -> BlazeServer {
        // For shared secret, server will derive tokens during handshake
        // based on the client's database name
        // This allows server to accept connections from any client with same secret
        
        // Create server with shared secret (not a pre-derived token)
        // Note: databaseName is required by BlazeServer.init
        // Use a default name if not available
        let server = try BlazeServer(
            port: port,
            database: self,
            databaseName: "BlazeDB",  // Default database name
            authToken: nil,  // No pre-derived token
            sharedSecret: sharedSecret  // Store secret for handshake verification
        )
        
        try await server.start()
        
        // Advertise for discovery
        let discovery = BlazeDiscovery()
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let deviceName = Host.current().name ?? "Unknown"
        #else
        let deviceName = ProcessInfo.processInfo.hostName
        #endif
        discovery.advertise(
            database: self.name,
            deviceName: deviceName,
            port: port
        )
        
        BlazeLogger.info("✅ Server started with shared secret! Database '\(self.name)' is discoverable on port \(port)")
        BlazeLogger.info("   Device: \(deviceName)")
        BlazeLogger.debug("   Shared secret: \(sharedSecret.prefix(4))...")
        
        return server
    }
    
    /// Sync with shared secret (recommended!)
    /// Works on all platforms (macOS, iOS, Linux, Vapor)!
    ///
    /// **Example:**
    /// ```swift
    /// // On iPhone (client)
    /// try await db.sync(
    ///     to: "192.168.1.100",  // Raspberry Pi IP
    ///     port: 8080,
    ///     database: "PiDB",
    ///     sharedSecret: "my-password-123"  // Same password!
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - host: Server hostname or IP address
    ///   - port: Server port (default: 8080)
    ///   - database: Database name on server
    ///   - sharedSecret: Shared secret (user's password)
    /// - Returns: The sync engine instance
    @discardableResult
    public func sync(
        to host: String,
        port: UInt16 = 8080,
        database: String,
        sharedSecret: String
    ) async throws -> BlazeSyncEngine {
        // Derive token from secret
        let token = Self.deriveToken(
            from: sharedSecret,
            database1: self.name,
            database2: database
        )
        
        // Sync with derived token
        let remoteNode = RemoteNode(
            host: host,
            port: port,
            database: database,
            useTLS: true,
            authToken: token
        )
        
        return try await enableSync(
            remote: remoteNode,
            policy: SyncPolicy(),
            role: .client
        )
    }
    
    /// Auto-connect with shared secret
    /// Automatically discovers and connects to server with shared secret
    ///
    /// **Example:**
    /// ```swift
    /// // On iPhone - auto-connect to Raspberry Pi
    /// try await db.autoConnect(
    ///     sharedSecret: "my-password-123"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - sharedSecret: Shared secret (user's password)
    ///   - timeout: Maximum time to wait for discovery (default: 30 seconds)
    ///   - filter: Optional filter to match specific databases
    /// - Returns: The sync engine instance
    @discardableResult
    public func autoConnect(
        sharedSecret: String,
        timeout: TimeInterval = 30.0,
        filter: ((DiscoveredDatabase) -> Bool)? = nil
    ) async throws -> BlazeSyncEngine {
        let discovery = BlazeDiscovery()
        discovery.startBrowsing()
        
        // Wait for discovery with timeout
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            let databases = discovery.discoveredDatabases
            
            // Apply filter if provided
            let matching = filter != nil ? databases.filter(filter!) : databases
            
            if let first = matching.first {
                discovery.stopBrowsing()
                BlazeLogger.info("✅ Auto-connecting to: \(first.name) on \(first.deviceName)")
                
                // Derive token for this database pair
                let token = Self.deriveToken(
                    from: sharedSecret,
                    database1: self.name,
                    database2: first.database
                )
                
                // Connect with derived token
                return try await sync(
                    to: first.host,
                    port: first.port,
                    database: first.database,
                    sharedSecret: sharedSecret
                )
            }
            
            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }
        
        discovery.stopBrowsing()
        throw BlazeDBError.connectionFailed("No databases discovered within \(timeout) seconds")
    }
}
#endif // !BLAZEDB_LINUX_CORE

