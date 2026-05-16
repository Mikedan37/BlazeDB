//
//  BlazedbRepl.swift
//  BlazeCLICore
//

import Foundation
import BlazeDBCore

public enum BlazedbRepl {
    public static func prompt(_ message: String = "> ") -> String? {
        print(message, terminator: "")
        return readLine()
    }

    private static func printWelcome(databasePath: String) {
        let url = URL(fileURLWithPath: databasePath)
        let cols = CLITerminalDraw.layoutColumns()
        CLITerminalDraw.clearScreen()
        for line in CLIBranding.heroBlockLines(width: cols) { print(line) }
        print("")
        print(CLIColors.bold("  shell ready"))
        print(CLIColors.muted("  Connected to \(url.lastPathComponent)"))
        print(CLIColors.muted("  Type \(CLIColors.ice("help")) or \(CLIColors.ice("?")) for shortcuts"))
        print("")
        fflush(stdout)
    }

    private static func isHelpCommand(_ trimmed: String) -> Bool {
        switch trimmed.lowercased() {
        case "help", "?", "shortcuts", "keys":
            return true
        default:
            return false
        }
    }

    /// Opens the database, records successful open in registry when `registryURL` is set, then runs the REPL.
    public static func runShell(
        dbPath: String,
        password: String,
        registryURL: URL?
    ) throws {
        let url = URL(fileURLWithPath: dbPath)
        let client = try BlazeDBClient(name: "default", fileURL: url, password: password)

        if let registryURL {
            var reg = try CLIRegistry.load(from: registryURL)
            reg.recordSuccessfulOpen(path: url.path)
            try reg.save(to: registryURL)
        }

        printWelcome(databasePath: dbPath)

        while let input = prompt() {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "exit" { break }
            if isHelpCommand(trimmed) {
                CLIHelp.printRepl(databaseName: url.lastPathComponent, databasePath: dbPath)
                continue
            }
            if trimmed == "fetchAll" {
                let records = try client.fetchAll()
                for r in records { print(r) }
            } else if trimmed.starts(with: "insert ") {
                let json = String(trimmed.dropFirst("insert ".count))
                if let data = json.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data) {
                    let id = try client.insert(BlazeDataRecord(dict))
                    print("✅ Inserted with ID: \(id)")
                } else {
                    print("❌ Invalid JSON")
                }
            } else if trimmed.starts(with: "fetch ") {
                let idStr = String(trimmed.dropFirst("fetch ".count))
                if let id = UUID(uuidString: idStr),
                   let record = try? client.fetch(id: id) {
                    print(record)
                } else {
                    print("❌ Invalid UUID or record not found")
                }
            } else if trimmed.starts(with: "softDelete ") {
                let idStr = String(trimmed.dropFirst("softDelete ".count))
                if let id = UUID(uuidString: idStr) {
                    try? client.softDelete(id: id)
                    print("🗑️ Soft deleted")
                } else {
                    print("❌ Invalid UUID")
                }
            } else if trimmed.starts(with: "update ") {
                let parts = trimmed.dropFirst("update ".count).split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2, let id = UUID(uuidString: parts[0]),
                   let data = parts[1].data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: BlazeDocumentField].self, from: data) {
                    try? client.update(id: id, with: BlazeDataRecord(dict))
                    print("✏️ Updated record \(id)")
                } else {
                    print("❌ Invalid update format. Use: update <uuid> {\"key\": \"value\"}")
                }
            } else if trimmed.starts(with: "delete ") {
                let idStr = String(trimmed.dropFirst("delete ".count))
                if let id = UUID(uuidString: idStr) {
                    try? client.delete(id: id)
                    print("🗑️ Deleted record \(id)")
                } else {
                    print("❌ Invalid UUID")
                }
            } else if !trimmed.isEmpty {
                print("❓ Unknown command. Type \(CLIColors.ice("help")).")
            }
        }
    }

    public static func runManager() {
        let manager = BlazeDBManager.shared
        let cols = CLITerminalDraw.layoutColumns()
        CLITerminalDraw.clearScreen()
        for line in CLIBranding.heroBlockLines(width: cols) { print(line) }
        print("")
        print(CLIColors.bold("  manager"))
        print(CLIColors.muted("  Type \(CLIColors.ice("help")) for shortcuts"))
        print("")

        while let input = prompt() {
            let parts = input.split(separator: " ", maxSplits: 2).map(String.init)
            let head = parts.first?.lowercased() ?? ""
            switch head {
            case "exit":
                break
            case "help", "?", "shortcuts":
                CLIHelp.printManager()
            case "list":
                for name in manager.mountedDatabases.keys {
                    print("📁 \(name)")
                }
            case "mount":
                if parts.count == 4 {
                    do {
                        try manager.mountDatabase(
                            named: parts[1],
                            fileURL: URL(fileURLWithPath: parts[2]),
                            password: parts[3]
                        )
                        print("✅ Mounted \(parts[1])")
                    } catch {
                        print("❌ Failed to mount: \(error.localizedDescription)")
                    }
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
                if !head.isEmpty {
                    print("❓ Unknown command. Type \(CLIColors.ice("help")).")
                }
            }
            if head == "exit" { break }
        }
    }
}
