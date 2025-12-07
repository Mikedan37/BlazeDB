//
//  SyncExample_MasterSlave.swift
//  BlazeDB Examples
//
//  Example: Master-Slave sync pattern (one-way sync)
//  Master writes, Slave reads only
//
//  Usage: Perfect for read replicas, backup databases, etc.
//

import Foundation
import BlazeDB

@main
struct SyncExample_MasterSlave {
    static func main() async throws {
        print("🔥 BlazeDB Master-Slave Sync Example")
        print("=" .repeating(60))
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_masterslave_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create master database (writes only)
        print("\n👑 Creating Master database...")
        let masterURL = tempDir.appendingPathComponent("master.blazedb")
        let master = try BlazeDBClient(name: "Master", fileURL: masterURL, password: "test123")
        print("✅ Master database created")
        
        // Create slave database (reads only)
        print("\n📖 Creating Slave database...")
        let slaveURL = tempDir.appendingPathComponent("slave.blazedb")
        let slave = try BlazeDBClient(name: "Slave", fileURL: slaveURL, password: "test123")
        print("✅ Slave database created")
        
        // Register in topology
        print("\n🔗 Setting up topology...")
        let topology = BlazeTopology()
        let masterId = try await topology.register(db: master, name: "Master", role: .server)
        let slaveId = try await topology.register(db: slave, name: "Slave", role: .client)
        
        // Connect in read-only mode (slave can only read from master)
        print("\n📡 Connecting Master → Slave (read-only)...")
        try await topology.connectLocal(from: masterId, to: slaveId, mode: .readOnly)
        print("✅ Connected! Slave can only read from Master")
        
        // Master inserts data
        print("\n📝 Master: Inserting data...")
        var masterRecordIds: [UUID] = []
        
        for i in 1...10 {
            let id = try master.insert(BlazeDataRecord([
                "id": .int(i),
                "message": .string("Master record \(i)"),
                "timestamp": .date(Date()),
                "source": .string("master")
            ]))
            masterRecordIds.append(id)
            print("   ✅ Inserted record \(i)")
        }
        
        // Wait for sync
        print("\n⏳ Waiting for sync to Slave...")
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Slave reads data
        print("\n📖 Slave: Reading synced data...")
        var slaveRecordCount = 0
        for id in masterRecordIds {
            if let record = try slave.fetch(id: id) {
                slaveRecordCount += 1
                if slaveRecordCount <= 3 {
                    print("   ✅ Found: \(record.string("message") ?? "N/A")")
                }
            }
        }
        print("   Total synced records: \(slaveRecordCount)/10")
        
        // Try to write to slave (should work locally, but won't sync back)
        print("\n⚠️  Testing: Attempting to write to Slave...")
        let slaveRecordId = try slave.insert(BlazeDataRecord([
            "message": .string("This is from Slave"),
            "source": .string("slave")
        ]))
        print("   ✅ Inserted locally in Slave")
        
        // Wait and check if it synced to Master
        try await Task.sleep(nanoseconds: 100_000_000)
        if try master.fetch(id: slaveRecordId) != nil {
            print("   ⚠️  Record synced to Master (read-only mode may allow local writes)")
        } else {
            print("   ✅ Record did NOT sync to Master (read-only mode working)")
        }
        
        // Performance test
        print("\n🚀 Performance test (1000 records)...")
        let startTime = Date()
        
        for i in 0..<1000 {
            _ = try master.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
        }
        
        let insertTime = Date().timeIntervalSince(startTime)
        print("   Master inserted 1000 records in \(String(format: "%.2f", insertTime))s")
        
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let slaveCount = try slave.query().all().count
        print("   Slave has \(slaveCount) records")
        print("   Sync throughput: ~\(Int(1000 / insertTime)) ops/sec")
        
        print("\n" + "=".repeating(60))
        print("✅ Master-Slave sync example complete!")
        print("   Pattern: Master writes → Slave reads")
        print("   Use case: Read replicas, backup databases, analytics")
    }
}

extension String {
    func repeating(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}

