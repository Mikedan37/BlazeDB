//
//  SyncExample_RemoteServer.swift
//  BlazeDB Examples
//
//  Example: Setting up a BlazeDB sync server
//  This server accepts connections from remote clients
//
//  Usage: Run this to start a sync server on port 8080
//

import Foundation
import BlazeDB

@main
struct SyncExample_RemoteServer {
    static func main() async throws {
        print("🔥 BlazeDB Sync Server Example")
        print("=" .repeating(60))
        
        // Create database
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_server_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let dbURL = tempDir.appendingPathComponent("server_db.blazedb")
        let serverDB = try BlazeDBClient(name: "ServerDB", fileURL: dbURL, password: "serverpass123")
        
        print("\n📦 Database created: \(dbURL.path)")
        
        // Create server
        let port: UInt16 = 8080
        let authToken = "secret-token-123" // In production, use secure token generation
        
        print("\n🚀 Starting BlazeDB sync server...")
        print("   Port: \(port)")
        print("   Auth: Enabled")
        print("   Encryption: E2E (AES-256-GCM)")
        
        let server = try BlazeServer(
            database: "ServerDB",
            port: port,
            localDB: serverDB,
            authToken: authToken
        )
        
        try await server.start()
        print("✅ Server listening on port \(port)")
        print("\n📡 Waiting for client connections...")
        print("   Clients can connect using:")
        print("   - Host: localhost (or your IP)")
        print("   - Port: \(port)")
        print("   - Auth Token: \(authToken)")
        
        // Insert some test data
        print("\n📝 Inserting test data...")
        let testRecordId = try serverDB.insert(BlazeDataRecord([
            "message": .string("Hello from server!"),
            "serverTime": .date(Date()),
            "status": .string("running")
        ]))
        print("✅ Test record inserted: \(testRecordId)")
        
        // Keep server running
        print("\n⏳ Server running... (Press Ctrl+C to stop)")
        print("   Connect a client to see sync in action!")
        
        // In a real app, you'd keep this running
        // For this example, we'll wait a bit then stop
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
        
        print("\n🛑 Stopping server...")
        await server.stop()
        print("✅ Server stopped")
    }
}

extension String {
    func repeating(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}

