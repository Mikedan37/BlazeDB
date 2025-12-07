//
//  SyncExample_HubAndSpoke.swift
//  BlazeDB Examples
//
//  Example: Hub-and-Spoke sync pattern (one server, multiple clients)
//  Perfect for centralized data distribution
//
//  Usage: One central database syncs to multiple client databases
//

import Foundation
import BlazeDB

@main
struct SyncExample_HubAndSpoke {
    static func main() async throws {
        print("🔥 BlazeDB Hub-and-Spoke Sync Example")
        print("=" .repeating(60))
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_hubspoke_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create hub (server)
        print("\n🔄 Creating Hub (server)...")
        let hubURL = tempDir.appendingPathComponent("hub.blazedb")
        let hub = try BlazeDBClient(name: "Hub", fileURL: hubURL, password: "test123")
        print("✅ Hub database created")
        
        // Create multiple spokes (clients)
        print("\n📡 Creating Spokes (clients)...")
        var spokes: [BlazeDBClient] = []
        var spokeURLs: [URL] = []
        
        for i in 1...5 {
            let url = tempDir.appendingPathComponent("spoke\(i).blazedb")
            let spoke = try BlazeDBClient(name: "Spoke\(i)", fileURL: url, password: "test123")
            spokes.append(spoke)
            spokeURLs.append(url)
            print("   ✅ Created Spoke\(i)")
        }
        
        // Register in topology
        print("\n🔗 Setting up topology...")
        let topology = BlazeTopology()
        let hubId = try await topology.register(db: hub, name: "Hub", role: .server)
        
        var spokeIds: [UUID] = []
        for (index, spoke) in spokes.enumerated() {
            let id = try await topology.register(db: spoke, name: "Spoke\(index + 1)", role: .client)
            spokeIds.append(id)
        }
        
        // Connect all spokes to hub
        print("\n📡 Connecting Spokes to Hub...")
        for (index, spokeId) in spokeIds.enumerated() {
            try await topology.connectLocal(from: hubId, to: spokeId, mode: .bidirectional)
            print("   ✅ Spoke\(index + 1) connected to Hub")
        }
        
        print("✅ All \(spokes.count) spokes connected!")
        
        // Hub inserts data (broadcasts to all spokes)
        print("\n📝 Hub: Inserting data (will sync to all spokes)...")
        let broadcastRecordId = try hub.insert(BlazeDataRecord([
            "message": .string("Broadcast to all spokes!"),
            "timestamp": .date(Date()),
            "source": .string("hub")
        ]))
        print("✅ Inserted broadcast record")
        
        // Wait for sync
        print("\n⏳ Waiting for sync to all spokes...")
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Check all spokes received it
        print("\n✅ Verifying all spokes received data...")
        var receivedCount = 0
        for (index, spoke) in spokes.enumerated() {
            if try spoke.fetch(id: broadcastRecordId) != nil {
                receivedCount += 1
                print("   ✅ Spoke\(index + 1) received broadcast")
            } else {
                print("   ❌ Spoke\(index + 1) did NOT receive broadcast")
            }
        }
        print("   Total: \(receivedCount)/\(spokes.count) spokes received data")
        
        // Each spoke inserts data (syncs to hub and other spokes)
        print("\n📝 Testing: Each spoke inserting data...")
        var spokeRecordIds: [UUID] = []
        
        for (index, spoke) in spokes.enumerated() {
            let id = try spoke.insert(BlazeDataRecord([
                "message": .string("Hello from Spoke\(index + 1)!"),
                "spokeNumber": .int(index + 1),
                "timestamp": .date(Date())
            ]))
            spokeRecordIds.append(id)
            print("   ✅ Spoke\(index + 1) inserted record")
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Verify hub received all spoke records
        print("\n✅ Verifying Hub received all spoke records...")
        var hubReceivedCount = 0
        for id in spokeRecordIds {
            if try hub.fetch(id: id) != nil {
                hubReceivedCount += 1
            }
        }
        print("   Hub received: \(hubReceivedCount)/\(spokeRecordIds.count) records")
        
        // Verify spokes received each other's records
        print("\n✅ Verifying spokes received each other's records...")
        for (index, spoke) in spokes.enumerated() {
            var spokeReceivedCount = 0
            for id in spokeRecordIds {
                if try spoke.fetch(id: id) != nil {
                    spokeReceivedCount += 1
                }
            }
            print("   Spoke\(index + 1) has \(spokeReceivedCount)/\(spokeRecordIds.count) records")
        }
        
        // Performance test
        print("\n🚀 Performance test (Hub broadcasting 500 records)...")
        let startTime = Date()
        
        for i in 0..<500 {
            _ = try hub.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Broadcast \(i)")
            ]))
        }
        
        let insertTime = Date().timeIntervalSince(startTime)
        print("   Hub inserted 500 records in \(String(format: "%.2f", insertTime))s")
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check all spokes
        var totalSynced = 0
        for spoke in spokes {
            let count = try spoke.query().all().count
            totalSynced += count
        }
        
        print("   Total records across all spokes: \(totalSynced)")
        print("   Average per spoke: \(totalSynced / spokes.count)")
        print("   Broadcast throughput: ~\(Int(500 / insertTime)) ops/sec")
        
        print("\n" + "=".repeating(60))
        print("✅ Hub-and-Spoke sync example complete!")
        print("   Pattern: 1 Hub → \(spokes.count) Spokes")
        print("   Use case: Centralized data distribution, multi-client apps")
    }
}

extension String {
    func repeating(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}

