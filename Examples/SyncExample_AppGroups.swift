//
//  SyncExample_AppGroups.swift
//  BlazeDB Examples
//
//  Example: Cross-app sync using App Groups (iOS/macOS)
//  This is the recommended way for cross-app sync on Apple platforms
//
//  Usage: Configure App Groups in Xcode, then use this code
//

import Foundation
import BlazeDB

@main
struct SyncExample_AppGroups {
    static func main() async throws {
        print("🔥 BlazeDB App Groups Sync Example")
        print("=" .repeating(60))
        print("\n⚠️  Note: App Groups require configuration in Xcode:")
        print("   1. Add App Group capability to both apps")
        print("   2. Use the same App Group identifier")
        print("   3. Example: 'group.com.yourapp.blazedb'")
        print("=" .repeating(60))
        
        // App Group identifier (replace with your actual App Group)
        let appGroup = "group.com.yourapp.blazedb"
        
        // Get shared container
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            print("\n❌ App Group not configured!")
            print("   Please configure App Groups in Xcode:")
            print("   1. Select your target")
            print("   2. Go to 'Signing & Capabilities'")
            print("   3. Click '+ Capability'")
            print("   4. Add 'App Groups'")
            print("   5. Add group: \(appGroup)")
            return
        }
        
        print("\n✅ App Group configured: \(appGroup)")
        print("   Container URL: \(containerURL.path)")
        
        // Create socket path in shared container
        let socketPath = containerURL
            .appendingPathComponent("blazedb_sync.sock")
            .path
        
        print("\n📡 Socket path: \(socketPath)")
        
        // Create databases in shared container
        print("\n📦 Creating databases in shared container...")
        
        let app1DBURL = containerURL.appendingPathComponent("app1_db.blazedb")
        let app2DBURL = containerURL.appendingPathComponent("app2_db.blazedb")
        
        let app1DB = try BlazeDBClient.open(at: app1DBURL, password: "TestPass123!")
        let app2DB = try BlazeDBClient.open(at: app2DBURL, password: "TestPass123!")
        
        print("✅ App1DB created: \(app1DBURL.path)")
        print("✅ App2DB created: \(app2DBURL.path)")
        
        // Register in topology
        print("\n🔗 Setting up topology...")
        let topology = BlazeTopology()
        let app1Id = try await topology.register(db: app1DB, name: "App1DB", role: .server)
        let app2Id = try await topology.register(db: app2DB, name: "App2DB", role: .client)
        
        // Connect via Unix Domain Socket (using App Group path)
        print("\n📡 Connecting via Unix Domain Socket...")
        try await topology.connectCrossApp(
            from: app1Id,
            to: app2Id,
            socketPath: socketPath,
            mode: .bidirectional
        )
        
        print("✅ Connected! Using App Group shared container")
        
        // App 1 inserts data
        print("\n📝 App 1: Inserting data...")
        let recordId = try app1DB.insert(BlazeDataRecord([
            "message": .string("Hello from App 1 via App Groups!"),
            "appGroup": .string(appGroup),
            "timestamp": .date(Date()),
            "shared": .bool(true)
        ]))
        print("✅ Inserted record: \(recordId)")
        
        // Wait for sync
        print("\n⏳ Waiting for sync...")
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // App 2 receives data
        print("\n✅ App 2: Checking for synced data...")
        if let synced = try app2DB.fetch(id: recordId) {
            print("✅ Record synced successfully via App Groups!")
            print("   Message: \(synced.string("message") ?? "N/A")")
            print("   App Group: \(synced.string("appGroup") ?? "N/A")")
            print("   Shared: \(synced.bool("shared") ?? false)")
        } else {
            print("❌ Record not found in App 2")
        }
        
        // Bidirectional sync
        print("\n🔄 Testing bidirectional sync...")
        let recordId2 = try app2DB.insert(BlazeDataRecord([
            "message": .string("Hello from App 2 via App Groups!"),
            "source": .string("app2")
        ]))
        try await Task.sleep(nanoseconds: 100_000_000)
        
        if let synced = try app1DB.fetch(id: recordId2) {
            print("✅ Bidirectional sync working!")
            print("   Message: \(synced.string("message") ?? "N/A")")
        }
        
        print("\n" + "=".repeating(60))
        print("✅ App Groups sync example complete!")
        print("   App Group: \(appGroup)")
        print("   Socket: Unix Domain Socket in shared container")
        print("   Latency: ~0.3-0.5ms")
    }
}

extension String {
    func repeating(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}

