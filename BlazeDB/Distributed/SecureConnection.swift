//
//  SecureConnection.swift
//  BlazeDB Distributed
//
//  Secure connection with Diffie-Hellman handshake and E2E encryption
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(Network)
import Network

/// Secure connection with DH handshake and AES-256-GCM encryption
public class SecureConnection {
    private let connection: NWConnection
    private var groupKey: SymmetricKey?
    private let nodeId: UUID
    private let database: String
    private let authToken: String?  // SECURITY: Authentication token
    private var isHandshaked = false
    
    public init(
        connection: NWConnection,
        nodeId: UUID,
        database: String,
        authToken: String? = nil  // SECURITY: Authentication token
    ) {
        self.connection = connection
        self.nodeId = nodeId
        self.database = database
        self.authToken = authToken
    }
    
    // MARK: - Factory
    
    public static func create(
        to remote: RemoteNode,
        database: String,
        nodeId: UUID
    ) async throws -> SecureConnection {
        // SECURITY: Pass auth token from RemoteNode
        // Create TCP connection
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        
        let tlsOptions = remote.useTLS ? NWProtocolTLS.Options() : nil
        
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let connection = NWConnection(
            host: NWEndpoint.Host(remote.host),
            port: NWEndpoint.Port(rawValue: remote.port)!,
            using: parameters
        )
        
        let secureConnection = SecureConnection(
            connection: connection,
            nodeId: nodeId,
            database: database,
            authToken: remote.authToken  // SECURITY: Pass auth token
        )
        
        // Start connection
        connection.start(queue: .global())
        
        // Wait for connection
        try await secureConnection.waitForConnection()
        
        // Perform handshake
        try await secureConnection.performHandshake(remote: remote)
        
        return secureConnection
    }
    
    // MARK: - Handshake
    
    private func waitForConnection() async throws {
        let state = await connection.state
        
        switch state {
        case .ready:
            return
        case .waiting(let error):
            throw ConnectionError.waiting(error)
        case .failed(let error):
            throw ConnectionError.failed(error)
        default:
            // Wait for state change
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            try await waitForConnection()
        }
    }
    
    private func performHandshake(remote: RemoteNode) async throws {
        // STEP 1: Generate ephemeral key pair
        let clientPrivateKey = P256.KeyAgreement.PrivateKey()
        let clientPublicKey = clientPrivateKey.publicKey
        
        // STEP 2: Send Hello
        let hello = HandshakeMessage(
            protocol: "blazedb/1.0",
            nodeId: nodeId,
            database: database,
            publicKey: clientPublicKey.rawRepresentation,
            capabilities: [.e2eEncryption, .compression, .selectiveSync, .rls],
            timestamp: Date(),
            authToken: authToken  // SECURITY: Include auth token
        )
        
        let helloData = try encodeHandshake(hello)
        try await sendFrame(type: .handshake, payload: helloData)
        
        // STEP 3: Receive Welcome
        let welcomeFrame = try await receiveFrame()
        guard welcomeFrame.type == .handshakeAck else {
            throw HandshakeError.invalidResponse
        }
        
        let welcome = try decodeHandshake(welcomeFrame.payload)
        let serverPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: welcome.publicKey)
        
        // STEP 4: Derive shared secret (DH!)
        let sharedSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        
        // STEP 5: Derive symmetric key (HKDF!)
        guard let salt = "blazedb-sync-v1".data(using: .utf8),
              let info = [database, welcome.database].sorted().joined(separator: ":").data(using: .utf8) else {
            throw HandshakeError.invalidResponse
        }
        
        // Convert SharedSecret to SymmetricKey for HKDF
        let sharedSecretData = sharedSecret.withUnsafeBytes { Data($0) }
        groupKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecretData),
            salt: salt,
            info: info,
            outputByteCount: 32  // AES-256
        )
        
        // STEP 6: Verify challenge
        guard let challenge = welcome.challenge else {
            throw HandshakeError.invalidResponse
        }
        let keyData = groupKey!.withUnsafeBytes { Data($0) }
        let response = HMAC<SHA256>.authenticationCode(
            for: challenge,
            using: SymmetricKey(data: keyData)
        )
        
        try await sendFrame(type: .verify, payload: Data(response))
        
        // STEP 7: Receive confirmation
        let confirmFrame = try await receiveFrame()
        guard confirmFrame.type == .handshakeComplete else {
            throw HandshakeError.invalidResponse
        }
        
        isHandshaked = true
        
        BlazeLogger.info("SecureConnection handshake complete (AES-256-GCM, ECDH P-256, PFS enabled)")
    }
    
    /// Perform server-side handshake
    public func performServerHandshake(
        expectedAuthToken: String?,
        sharedSecret: String? = nil,
        serverDatabase: String? = nil
    ) async throws {
        // STEP 1: Receive Hello from client
        let helloFrame = try await receiveFrame()
        guard helloFrame.type == .handshake else {
            throw HandshakeError.invalidResponse
        }
        
        let hello = try decodeHandshake(helloFrame.payload)
        
        // SECURITY: Verify authentication token
        if let secret = sharedSecret, let serverDB = serverDatabase {
            // Shared secret mode: derive token from secret + database names
            // Use the same token derivation logic as BlazeDBClient
            let dbNames = [serverDB, hello.database].sorted().joined(separator: ":")
            guard let secretData = secret.data(using: .utf8),
                  let salt = "blazedb-auth-v1".data(using: .utf8),
                  let info = dbNames.data(using: .utf8) else {
                throw HandshakeError.invalidResponse
            }
            
            let expectedTokenKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: secretData),
                salt: salt,
                info: info,
                outputByteCount: 32
            )
            let expectedToken = expectedTokenKey.withUnsafeBytes { Data($0).base64EncodedString() }
            
            guard let clientToken = hello.authToken, clientToken == expectedToken else {
                throw HandshakeError.invalidAuthToken
            }
        } else if let expectedToken = expectedAuthToken {
            // Direct token mode: verify token matches
            guard hello.authToken == expectedToken else {
                throw HandshakeError.invalidAuthToken
            }
        } else if hello.authToken != nil {
            // Server requires no auth, but client sent token (reject)
            throw HandshakeError.invalidAuthToken
        }
        
        let clientPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: hello.publicKey)
        
        // STEP 2: Generate server key pair
        let serverPrivateKey = P256.KeyAgreement.PrivateKey()
        let serverPublicKey = serverPrivateKey.publicKey
        
        // STEP 3: Generate challenge
        let challenge = try AES.GCM.Nonce().withUnsafeBytes { Data($0) }
        
        // STEP 4: Send Welcome
        let welcome = HandshakeMessage(
            protocol: "blazedb/1.0",
            nodeId: nodeId,
            database: database,
            publicKey: serverPublicKey.rawRepresentation,
            capabilities: [.e2eEncryption, .compression, .selectiveSync, .rls],
            timestamp: Date(),
            challenge: challenge
        )
        
        let welcomeData = try encodeHandshake(welcome)
        try await sendFrame(type: .handshakeAck, payload: welcomeData)
        
        // STEP 5: Receive Verify
        let verifyFrame = try await receiveFrame()
        guard verifyFrame.type == .verify else {
            throw HandshakeError.invalidResponse
        }
        
        // STEP 6: Derive shared secret
        let sharedSecret = try serverPrivateKey.sharedSecretFromKeyAgreement(with: clientPublicKey)
        
        // STEP 7: Derive symmetric key
        guard let salt = "blazedb-sync-v1".data(using: .utf8),
              let info = [database, hello.database].sorted().joined(separator: ":").data(using: .utf8) else {
            throw HandshakeError.invalidResponse
        }
        
        // Convert SharedSecret to SymmetricKey for HKDF
        let sharedSecretData = sharedSecret.withUnsafeBytes { Data($0) }
        groupKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecretData),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        
        // STEP 8: Verify challenge response
        let keyData = groupKey!.withUnsafeBytes { Data($0) }
        let expectedResponse = HMAC<SHA256>.authenticationCode(
            for: challenge,
            using: SymmetricKey(data: keyData)
        )
        
        guard verifyFrame.payload == Data(expectedResponse) else {
            throw HandshakeError.invalidResponse
        }
        
        // STEP 9: Send confirmation
        try await sendFrame(type: .handshakeComplete, payload: Data())
        
        isHandshaked = true
        
        BlazeLogger.info("SecureConnection server handshake complete (AES-256-GCM, ECDH P-256, PFS enabled)")
    }
    
    // MARK: - Send/Receive
    
    public func send(_ data: Data) async throws {
        guard isHandshaked, let key = groupKey else {
            throw ConnectionError.notHandshaked
        }
        
        // Encrypt with AES-256-GCM
        let sealed = try AES.GCM.seal(data, using: key)
        let encrypted = sealed.combined!
        
        // Send encrypted frame
        try await sendFrame(type: .encryptedData, payload: encrypted)
    }
    
    public func receive() async throws -> Data {
        guard isHandshaked, let key = groupKey else {
            throw ConnectionError.notHandshaked
        }
        
        // Receive encrypted frame
        let frame = try await receiveFrame()
        
        // Decrypt
        let sealed = try AES.GCM.SealedBox(combined: frame.payload)
        let decrypted = try AES.GCM.open(sealed, using: key)
        
        return decrypted
    }
    
    // MARK: - Frame Protocol
    
    enum FrameType: UInt8 {
        case handshake = 0x01
        case handshakeAck = 0x02
        case verify = 0x03
        case handshakeComplete = 0x04
        case encryptedData = 0x05
        case operation = 0x06
    }
    
    struct Frame {
        let type: FrameType
        let payload: Data
    }
    
    private func sendFrame(type: FrameType, payload: Data) async throws {
        var frame = Data()
        frame.append(type.rawValue)
        var length = UInt32(payload.count).bigEndian
        frame.append(Data(bytes: &length, count: 4))
        frame.append(payload)
        
        try await connection.send(content: frame, completion: .contentProcessed { _ in })
    }
    
    private func receiveFrame() async throws -> Frame {
        // Read type (1 byte)
        let typeData = try await readExactly(1)
        guard let type = FrameType(rawValue: typeData[0]) else {
            throw FrameError.invalidType
        }
        
        // Read length (4 bytes)
        let lengthData = try await readExactly(4)
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        // Read payload
        let payload = try await readExactly(Int(length))
        
        return Frame(type: type, payload: payload)
    }
    
    private var receiveBuffer = Data()
    
    private func readExactly(_ count: Int) async throws -> Data {
        while receiveBuffer.count < count {
            let content = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                connection.receiveMessage { content, context, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: content)
                    }
                }
            }
            receiveBuffer.append(content ?? Data())
        }
        
        let result = receiveBuffer.prefix(count)
        receiveBuffer.removeFirst(count)
        return result
    }
    
    // MARK: - Handshake Messages
    
    struct HandshakeMessage {
        let `protocol`: String
        let nodeId: UUID
        let database: String
        let publicKey: Data
        let capabilities: Capabilities
        let timestamp: Date
        let challenge: Data?
        let authToken: String?  // SECURITY: Authentication token
        
        struct Capabilities: OptionSet {
            let rawValue: UInt8
            static let e2eEncryption = Capabilities(rawValue: 1 << 0)
            static let compression = Capabilities(rawValue: 1 << 1)
            static let selectiveSync = Capabilities(rawValue: 1 << 2)
            static let rls = Capabilities(rawValue: 1 << 3)
        }
        
        init(
            protocol: String,
            nodeId: UUID,
            database: String,
            publicKey: Data,
            capabilities: Capabilities,
            timestamp: Date,
            challenge: Data? = nil,
            authToken: String? = nil  // SECURITY: Authentication token
        ) {
            self.`protocol` = `protocol`
            self.nodeId = nodeId
            self.database = database
            self.publicKey = publicKey
            self.capabilities = capabilities
            self.timestamp = timestamp
            self.challenge = challenge
            self.authToken = authToken
        }
    }
    
    func encodeHandshake(_ msg: HandshakeMessage) throws -> Data {
        var data = Data()
        
        // Protocol
        let protocolBytes = msg.`protocol`.utf8
        data.append(UInt8(protocolBytes.count))
        data.append(contentsOf: protocolBytes)
        
        // Node ID
        withUnsafeBytes(of: msg.nodeId.uuid) {
            data.append(contentsOf: $0)
        }
        
        // Database
        let dbBytes = msg.database.utf8
        data.append(UInt8(dbBytes.count))
        data.append(contentsOf: dbBytes)
        
        // Public Key
        data.append(msg.publicKey)
        
        // Capabilities
        data.append(msg.capabilities.rawValue)
        
        // Timestamp
        var millis = UInt64(msg.timestamp.timeIntervalSince1970 * 1000).bigEndian
        data.append(Data(bytes: &millis, count: 8))
        
        // Challenge (if present)
        if let challenge = msg.challenge {
            data.append(challenge)
        }
        
        // Auth Token (if present)
        if let authToken = msg.authToken {
            let tokenBytes = authToken.utf8
            data.append(UInt8(tokenBytes.count))
            data.append(contentsOf: tokenBytes)
        } else {
            data.append(UInt8(0))  // 0 length = no token
        }
        
        return data
    }
    
    func decodeHandshake(_ data: Data) throws -> HandshakeMessage {
        var offset = 0
        
        // Protocol
        let protocolLen = Int(data[offset])
        offset += 1
        let `protocol` = String(data: data[offset..<offset+protocolLen], encoding: .utf8)!
        offset += protocolLen
        
        // Node ID
        let nodeId = UUID(uuid: data[offset..<offset+16].withUnsafeBytes { $0.load(as: uuid_t.self) })
        offset += 16
        
        // Database
        let dbLen = Int(data[offset])
        offset += 1
        let database = String(data: data[offset..<offset+dbLen], encoding: .utf8)!
        offset += dbLen
        
        // Public Key
        let publicKey = data[offset..<offset+65]
        offset += 65
        
        // Capabilities
        let capabilities = HandshakeMessage.Capabilities(rawValue: data[offset])
        offset += 1
        
        // Timestamp
        let millis = data[offset..<offset+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let timestamp = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        offset += 8
        
        // Challenge (if present)
        let challenge: Data?
        if data.count > offset {
            challenge = data[offset..<offset+16]
            offset += 16
        } else {
            challenge = nil
        }
        
        // Auth Token (if present)
        let authTokenLen = offset < data.count ? Int(data[offset]) : 0
        offset += 1
        let authToken: String?
        if authTokenLen > 0 && offset + authTokenLen <= data.count {
            authToken = String(data: data[offset..<offset+authTokenLen], encoding: .utf8)
            offset += authTokenLen
        } else {
            authToken = nil
        }
        
        return HandshakeMessage(
            protocol: `protocol`,
            nodeId: nodeId,
            database: database,
            publicKey: publicKey,
            capabilities: capabilities,
            timestamp: timestamp,
            challenge: challenge,
            authToken: authToken
        )
    }
}

// MARK: - Errors

enum ConnectionError: Error {
    case waiting(Error)
    case failed(Error)
    case notHandshaked
}

enum HandshakeError: Error {
    case invalidResponse
    case invalidAuthToken
}

enum FrameError: Error {
    case invalidType
}

#endif // canImport(Network)
#endif // !BLAZEDB_LINUX_CORE

