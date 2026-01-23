//  main.swift
//  BlazeShell
//  Created by Michael Danylchuk on 6/19/25.

import Foundation
import BlazeDBCore

func prompt(_ message: String = "> ") -> String? {
    print(message, terminator: "")
    return readLine()
}

func runShell(dbPath: String, password: String) {
    do {
        let url = URL(fileURLWithPath: dbPath)
        let client = try BlazeDBClient(name: "default", fileURL: url, password: password)

        print("🔥 BlazeDB Shell — type 'exit' to quit")
        while let input = prompt() {
            if input == "exit" { break }

            if input == "fetchAll" {
                let records = try client.fetchAll()
                for r in records {
                    print(r)
                }
            } else if input.starts(with: "insert ") {
                let json = input.replacingOccurrences(of: "insert ", with: "")
                if let data = json.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data){
                    let id = try client.insert(BlazeDataRecord(dict))
                    print("✅ Inserted with ID: \(id)")
                } else {
                    print("❌ Invalid JSON")
                }
            } else if input.starts(with: "fetch ") {
                let idStr = input.replacingOccurrences(of: "fetch ", with: "")
                if let id = UUID(uuidString: idStr),
                   let record = try? client.fetch(id: id) {
                    print(record ?? "❌ Record not found")
                } else {
                    print("❌ Invalid UUID or record not found")
                }
            } else if input.starts(with: "softDelete ") {
                let idStr = input.replacingOccurrences(of: "softDelete ", with: "")
                if let id = UUID(uuidString: idStr) {
                    try? client.softDelete(id: id)
                    print("🗑️ Soft deleted")
                } else {
                    print("❌ Invalid UUID")
                }
            } else if input.starts(with: "update ") {
                let parts = input.dropFirst("update ".count).split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2, let id = UUID(uuidString: parts[0]),
                   let data = parts[1].data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data) {
                    try? client.update(id: id, with: BlazeDataRecord(dict))
                    print("✏️ Updated record \(id)")
                } else {
                    print("❌ Invalid update format. Use: update <uuid> {\"key\": \"value\"}")
                }
            } else if input.starts(with: "delete ") {
                let idStr = input.replacingOccurrences(of: "delete ", with: "")
                if let id = UUID(uuidString: idStr) {
                    try? client.delete(id: id)
                    print("❌ Deleted record \(id)")
                } else {
                    print("❌ Invalid UUID")
                }
            } else {
                print("❓ Unknown command")
            }
        }

    } catch {
        print("💥 Error: \(error)")
    }
}


let args = CommandLine.arguments

// BlazeDBManager CLI
if args.contains("--manager") {
    func runManager() {
        let manager = BlazeDBManager.shared
        print("📂 BlazeDBManager CLI — type 'help' for commands")

        while let input = prompt() {
            let parts = input.split(separator: " ", maxSplits: 2).map(String.init)
            switch parts.first {
            case "exit":
                break
            case "help":
                print("""
                🔧 Commands:
                - list: Show all mounted DBs
                - mount <name> <path> <password>: Mount a DB
                - use <name>: Switch current DB
                - current: Show currently active DB
                - exit: Exit manager
                """)
            case "list":
                for name in manager.mountedDatabases.keys {
                    print("📁 \(name)")
                }
            case "mount":
                if parts.count == 4 {
                    try? manager.mountDatabase(named: parts[1], fileURL: URL(fileURLWithPath: parts[2]), password: parts[3])
                    print("✅ Mounted \(parts[1])")
                } else {
                    print("❌ Usage: mount <name> <path> <password>")
                }
            case "use":
                if parts.count == 2 {
                    try? manager.switchDatabase(to: parts[1])
                    print("🎯 Using \(parts[1])")
                } else {
                    print("❌ Usage: use <name>")
                }
            case "current":
                if let current = manager.currentDatabaseName {
                    print("🎯 Currently using:", current)
                } else {
                    print("❌ No active DB")
                }
            default:
                print("❓ Unknown command. Type 'help'.")
            }
            if parts.first == "exit" { break }
        }
    }
    runManager()
    exit(0)
}

// ========================================
// TEMP: Create test database for Visualizer
// (CHECK THIS FIRST, before usage guard!)
// ========================================
if args.contains("--create-test") {
    print("📦 Creating test database for BlazeDBVisualizer...")
    
    let testDB = try BlazeDBClient(
        name: "test_visualizer",
        fileURL: URL(fileURLWithPath: "/Users/mdanylchuk/Desktop/test.blazedb"),
        password: "test1234"  // ✅ 8 characters minimum!
    )
    
    print("✏️  Adding 50 test records...")
    
    for i in 0..<50 {
        _ = try testDB.insert(BlazeDataRecord([
            "id": .int(i),
            "name": .string("Test Item \(i)"),
            "email": .string("test\(i)@example.com"),
            "age": .int(20 + (i % 50)),
            "active": .bool(i % 2 == 0),
            "score": .double(Double(i) * 1.5),
            "created": .date(Date())
        ]))
    }
    
    try testDB.persist()
    
    print("")
    print("✅ SUCCESS! Created test.blazedb on Desktop!")
    print("📍 Location: /Users/mdanylchuk/Desktop/test.blazedb")
    print("🔑 Password: test1234")
    print("📊 Records: 50")
    print("")
    print("Now:")
    print("1. Switch scheme to 'BlazeDBVisualizer'")
    print("2. Run it (⌘R)")
    print("3. You'll see 'test_visualizer' in the list!")
    print("4. Click it and unlock with password: test1234")
    print("5. Watch the live dashboard! 🔥")
    
    exit(0)
}

guard args.count >= 3 else {
    print("Usage: BlazeShell <db-path> <password>")
    exit(1)
}

runShell(dbPath: args[1], password: args[2])

// MARK: - Recovery CLI Tool

if args.contains("restore-backup") {
    let fileManager = FileManager.default
    let backupURL = URL(fileURLWithPath: "./lastKnownGood.blazedb")
    let destinationURL = URL(fileURLWithPath: args[1])

    do {
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: backupURL, to: destinationURL)
            print("✅ Restored backup to:", destinationURL.path)
        } else {
            print("❌ No backup found at \(backupURL.path)")
        }
    } catch {
        print("💥 Failed to restore backup:", error)
    }
    exit(0)
}

if args.contains("show-backup") {
    print("📁 Backup located at:", FileManager.default.currentDirectoryPath + "/lastKnownGood.blazedb")
    exit(0)
}
