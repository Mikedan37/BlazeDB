//
//  main.swift
//  BlazeDBServer
//
//  Minimal BlazeDB server process for Linux bring-up.
//  Proves persistence: start → write → persist → restart → read.
//

import Foundation
import BlazeDB

@main
struct BlazeDBServerMain {
    static func main() {
        // Parse data directory from environment
        let dataDir = ProcessInfo.processInfo.environment["BLAZEDB_DATA_DIR"] ?? "./data"
        let dataURL = URL(fileURLWithPath: dataDir, isDirectory: true)
        
        // Ensure directory exists
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: dataURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fputs("ERROR: Failed to create data directory at \(dataDir): \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        
        // Database file path
        let dbURL = dataURL.appendingPathComponent("blazedb.blazedb")
        let password = ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"] ?? "default-password-change-in-production"
        
        // Startup banner
        let pid = ProcessInfo.processInfo.processIdentifier
        print("========================================")
        print("BlazeDB Server")
        print("========================================")
        print("Data Directory: \(dataDir)")
        print("Database Path: \(dbURL.path)")
        print("Process ID: \(pid)")
        print("========================================")
        
        // Open or initialize database
        let db: BlazeDBClient
        do {
            db = try BlazeDBClient(name: "BlazeDBServer", fileURL: dbURL, password: password, project: "Server")
            print("✓ Database opened successfully")
        } catch {
            fputs("ERROR: Failed to open database: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        
        // Persistence smoke test
        let testKey = "boot-test"
        let testRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        do {
            // Try to read existing boot-test record
            if let existing = try? db.fetch(id: testRecordID),
               let timestamp = existing.storage[testKey]?.stringValue {
                print("✓ Persistence verified: boot-test = \(timestamp) (from previous run)")
            } else {
                // No existing record, create one with boot-test
                try writeBootTest(db: db, key: testKey, recordID: testRecordID)
            }
        } catch {
            fputs("ERROR: Persistence test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        
        print("✓ Server ready")
        print("Heartbeat: every 10 seconds")
        print("Press Ctrl+C to stop")
        print("========================================")
        
        // Keep process alive with heartbeat
        var heartbeatCount = 0
        let heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            heartbeatCount += 1
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("[\(timestamp)] BlazeDB alive (heartbeat #\(heartbeatCount))")
        }
        
        // Run loop to keep process alive
        RunLoop.main.add(heartbeatTimer, forMode: .default)
        RunLoop.main.run()
    }
    
    private static func writeBootTest(db: BlazeDBClient, key: String, recordID: UUID) throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let record = BlazeDataRecord(storage: [
            "id": .uuid(recordID),
            key: .string(timestamp)
        ])
        
        // Insert with specific ID (insert will use the ID from the record)
        let id = try db.insert(record)
        try db.persist()
        
        // Read back to confirm
        guard let readBack = try? db.fetch(id: id),
              let readTimestamp = readBack.storage[key]?.stringValue else {
            throw NSError(domain: "BlazeDBServer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read back boot-test value"
            ])
        }
        
        print("✓ Persistence test: wrote boot-test = \(timestamp), read back = \(readTimestamp)")
    }
}
