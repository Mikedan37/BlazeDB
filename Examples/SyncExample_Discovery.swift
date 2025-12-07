//
//  SyncExample_Discovery.swift
//  BlazeDB Examples
//
//  Example: Automatic discovery of BlazeDB servers using mDNS/Bonjour
//  This enables Mac and iOS devices to find each other automatically
//
//  Usage: Run this to discover and connect to BlazeDB servers on your network
//

import Foundation
import BlazeDB

@main
struct SyncExample_Discovery {
    static func main() async throws {
        print("🔥 BlazeDB Discovery Example")
        print("=" .repeating(60))
        
        // Create discovery instance
        let discovery = BlazeDiscovery()
        
        // Start browsing for databases
        print("\n🔍 Starting discovery (mDNS/Bonjour)...")
        discovery.startBrowsing()
        print("✅ Browsing started")
        
        // Wait for discovery
        print("\n⏳ Waiting for databases to be discovered...")
        print("   (Make sure a server is advertising on the network)")
        
        // Check for discovered databases every second
        for i in 1...10 {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            let discovered = discovery.discoveredDatabases
            if !discovered.isEmpty {
                print("\n✅ Found \(discovered.count) database(s):")
                for db in discovered {
                    print("   - \(db.name)")
                    print("     Device: \(db.deviceName)")
                    print("     Host: \(db.host):\(db.port)")
                    print("     Database: \(db.database)")
                }
                break
            } else {
                print("   Checking... (\(i)/10)")
            }
        }
        
        // If we found databases, show how to connect
        let discovered = discovery.discoveredDatabases
        if discovered.isEmpty {
            print("\n⚠️  No databases found.")
            print("   Make sure a BlazeDB server is running and advertising.")
            print("   See SyncExample_RemoteServer for server setup.")
        } else {
            print("\n📝 Example: Connecting to discovered database...")
            let db = discovered.first!
            
            // Create client database
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("blazedb_discovery_client_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let clientDB = try BlazeDBClient(
                name: "DiscoveryClient",
                fileURL: tempDir.appendingPathComponent("client.blazedb"),
                password: "test123"
            )
            
            // Register in topology
            let topology = BlazeTopology()
            let clientId = try await topology.register(db: clientDB, name: "DiscoveryClient", role: .client)
            
            // Create remote node from discovered database
            let remote = RemoteNode(
                host: db.host,
                port: db.port,
                database: db.database,
                useTLS: true, // Recommended for production
                authToken: "secret-token-123" // Must match server
            )
            
            print("   Connecting to \(db.name) at \(db.host):\(db.port)...")
            
            // Connect
            try await topology.connectRemote(
                nodeId: clientId,
                remote: remote,
                policy: SyncPolicy()
            )
            
            print("✅ Connected to \(db.name)!")
            print("   Data will now sync automatically.")
        }
        
        // Stop browsing
        discovery.stopBrowsing()
        print("\n🛑 Discovery stopped")
        
        print("\n" + "=".repeating(60))
        print("✅ Discovery example complete!")
    }
}

extension String {
    func repeating(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}

