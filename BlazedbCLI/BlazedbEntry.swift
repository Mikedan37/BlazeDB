//  BlazedbEntry.swift
//  blazedb — BlazeDB CLI (discover, pick, unlock, REPL)

import Foundation
import BlazeDBCore
import BlazeCLICore

private func printHelp() {
    CLIHelp.printGlobal()
}

/// Write a line to stderr without touching the C `stderr` global, which Swift 6
/// strict-concurrency on Linux rejects as a non-Sendable mutable extern.
private func writeStderrLine(_ message: String) {
    guard let data = (message + "\n").data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
}

private func handleRestoreBackup(dest: String) {
    let fileManager = FileManager.default
    let backupURL = URL(fileURLWithPath: "./lastKnownGood.blazedb")
    let destinationURL = URL(fileURLWithPath: dest)
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
}

private func handleCreateTest() throws {
    print("📦 Creating test database for BlazeDBVisualizer...")
    let testPassword = "BlazeViz2026!TestOk"
    let testPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazedb-test-visualizer.blazedb")
    let testDB = try BlazeDBClient(
        name: "test_visualizer",
        fileURL: testPath,
        password: testPassword
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
    print("✅ SUCCESS! Created test database!")
    print("📍 Location: \(testPath.path)")
    print("🔑 Password: \(testPassword)")
    print("📊 Records: 50")
}

private func runStartFlow() {
    runPickerThenRepl(startHomeScan: true, showStartupSplash: true, masterMode: false)
}

private func readDatabasePasswordPrompt() throws -> String {
    try CLIPasswordReader.readLineHidden(prompt: "Database password: ")
}

private func resolvePasswordForDatabase(path: String, masterMode: Bool, fallbackPrompt: Bool = true) throws -> String {
    if let envPassword = ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"], !envPassword.isEmpty {
        return envPassword
    }

    guard masterMode else {
        if fallbackPrompt { return try CLIPasswordReader.readLineHidden(prompt: "Password: ") }
        throw NSError(domain: "blazedb.password", code: 1, userInfo: [NSLocalizedDescriptionKey: "Password required"])
    }

    let passphrase = try readMasterPassphrase(confirm: false)
    if let stored = try CLIMasterKeyringStore.resolveSecret(passphrase: passphrase, dbPath: path) {
        return stored
    }
    if fallbackPrompt {
        return try readDatabasePasswordPrompt()
    }
    throw NSError(domain: "blazedb.master", code: 2, userInfo: [NSLocalizedDescriptionKey: "No stored secret for this database"])
}

private func runPickerThenRepl(startHomeScan: Bool, showStartupSplash: Bool = false, masterMode: Bool) {
    #if os(macOS) || os(Linux)
    do {
        let registryURL = try CLIPaths.registryURL()
        var registry = try CLIRegistry.load(from: registryURL)
        let picked = try BlazedbPicker.pickDatabase(
            registry: &registry,
            registryURL: registryURL,
            startHomeScanImmediately: startHomeScan,
            showStartupSplash: showStartupSplash
        )
        guard let url = picked else { exit(0) }
        let shellPassword = try resolvePasswordForDatabase(path: url.path, masterMode: masterMode, fallbackPrompt: true)
        try BlazedbRepl.runShell(dbPath: url.path, password: shellPassword, registryURL: registryURL)
    } catch {
        print("💥 \(error)")
        exit(1)
    }
    #else
    print("Interactive blazedb picker requires macOS or Linux. Pass a database path and password instead.")
    exit(1)
    #endif
}

private func readMasterPassphrase(confirm: Bool) throws -> String {
    if let envPassword = ProcessInfo.processInfo.environment["BLAZEDB_MASTER_PASSWORD"], !envPassword.isEmpty {
        return envPassword
    }
    let passphrase = try CLIPasswordReader.readLineHidden(prompt: "Master passphrase: ")
    if confirm {
        let again = try CLIPasswordReader.readLineHidden(prompt: "Confirm passphrase: ")
        if passphrase != again {
            throw NSError(domain: "blazedb.master", code: 1, userInfo: [NSLocalizedDescriptionKey: "Passphrases do not match."])
        }
    }
    return passphrase
}

private func printMasterStatus(_ status: CLIMasterKeyringStatus) {
    print("Master keyring path: \(status.path)")
    print("Initialized: \(status.exists ? "yes" : "no")")
    if let perms = status.permissionsOctal {
        print("Permissions: \(perms)\(status.securePermissions0600 ? " (secure)" : " (expected 0600)")")
    }
    if let schema = status.schemaVersion {
        print("Schema version: \(schema)")
    }
    if let algorithm = status.kdfAlgorithm {
        print("KDF: \(algorithm)")
    }
    if let entries = status.entryCountHint {
        print("Entries: \(entries)")
    }
}

private func parseMasterScope(args: [String]) -> CLIMasterStorageScope {
    guard let idx = args.firstIndex(of: "--scope"), idx + 1 < args.count else { return .persistent }
    return CLIMasterStorageScope(rawValue: args[idx + 1]) ?? .persistent
}

private func parseMasterLabel(args: [String]) -> String? {
    guard let idx = args.firstIndex(of: "--label"), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

private func parseMasterTargetPath(args: [String]) -> String? {
    let ignored = Set(["--scope", "--label", "session", "device", "persistent"])
    var i = 0
    while i < args.count {
        let token = args[i]
        if token == "--scope" || token == "--label" {
            i += 2
            continue
        }
        if token.hasPrefix("--") || ignored.contains(token) {
            i += 1
            continue
        }
        return token
    }
    return nil
}

private func handleMasterCommand(_ args: [String]) {
    let sub = args.first ?? "help"
    do {
        switch sub {
        case "init":
            let passphrase = try readMasterPassphrase(confirm: ProcessInfo.processInfo.environment["BLAZEDB_MASTER_PASSWORD"] == nil)
            let status = try CLIMasterKeyringStore.initialize(passphrase: passphrase)
            print("✅ Master keyring initialized.")
            printMasterStatus(status)
            print("")
            print("Security guardrails:")
            for item in CLIMasterGuardrails.forbiddenBehaviors {
                print("  - \(item)")
            }
        case "status":
            let status = try CLIMasterKeyringStore.status()
            printMasterStatus(status)
        case "add":
            let subArgs = Array(args.dropFirst())
            guard let path = parseMasterTargetPath(args: subArgs) else {
                print("Usage: blazedb master add <db-path> [--scope session|device|persistent] [--label <name>]")
                exit(1)
            }
            let scope = parseMasterScope(args: subArgs)
            let label = parseMasterLabel(args: subArgs)
            let providedSecret = ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"]
            if scope == .session {
                let secret = providedSecret?.isEmpty == false ? providedSecret! : (try readDatabasePasswordPrompt())
                let entry = try CLIMasterKeyringStore.addEntry(
                    passphrase: "",
                    dbPath: path,
                    dbSecret: secret,
                    scope: .session,
                    label: label
                )
                print("✅ Added session-scoped secret for \(entry.canonicalPath).")
                print("   Note: session scope is in-memory only and clears when process exits.")
                return
            }
            let passphrase = try readMasterPassphrase(confirm: false)
            let secret = providedSecret?.isEmpty == false ? providedSecret! : (try readDatabasePasswordPrompt())
            let entry = try CLIMasterKeyringStore.addEntry(
                passphrase: passphrase,
                dbPath: path,
                dbSecret: secret,
                scope: scope,
                label: label
            )
            print("✅ Added \(scope.rawValue)-scoped key entry for \(entry.canonicalPath)")
        case "remove":
            let subArgs = Array(args.dropFirst())
            guard let key = parseMasterTargetPath(args: subArgs) else {
                print("Usage: blazedb master remove <db-path|db-id>")
                exit(1)
            }
            let passphrase = try readMasterPassphrase(confirm: false)
            let removed = try CLIMasterKeyringStore.removeEntry(passphrase: passphrase, dbPathOrID: key)
            if removed {
                print("✅ Removed entry \(key)")
            } else {
                print("ℹ️ No entry found for \(key)")
            }
        case "list":
            let passphrase = try readMasterPassphrase(confirm: false)
            let entries = try CLIMasterKeyringStore.listEntries(passphrase: passphrase)
            if entries.isEmpty {
                print("No master keyring entries.")
            } else {
                for entry in entries {
                    let label = entry.label ?? "—"
                    print("\(entry.dbID)  [\(entry.scope.rawValue)]  \(label)  \(entry.canonicalPath)")
                }
            }
        case "help", "--help", "-h":
            CLIHelp.printMaster()
        default:
            print("Unknown master subcommand: \(sub)")
            CLIHelp.printMaster()
            exit(1)
        }
    } catch {
        print("💥 \(error.localizedDescription)")
        exit(1)
    }
}

@main
enum BlazedbEntry {
    static func main() {
        let argv = Array(CommandLine.arguments.dropFirst())

        if argv.isEmpty || argv == ["start"] || argv == ["--scan-home"] {
            runStartFlow()
            return
        }

        if argv.first == "start" {
            runPickerThenRepl(
                startHomeScan: true,
                showStartupSplash: true,
                masterMode: argv.contains("--master")
            )
            return
        }

        if argv.first == "--help" || argv.first == "-h" {
            printHelp()
            return
        }

        if argv.first == "restore-backup" {
            guard argv.count >= 2 else {
                print("Usage: blazedb restore-backup <destination-path>")
                exit(1)
            }
            handleRestoreBackup(dest: argv[1])
            return
        }

        if argv.first == "show-backup" {
            print("📁 Backup located at:", FileManager.default.currentDirectoryPath + "/lastKnownGood.blazedb")
            return
        }

        if argv.first == "bookmark" {
            guard argv.count >= 3 else {
                print("Usage: blazedb bookmark add <path>  |  blazedb bookmark remove <path>")
                exit(1)
            }
            let sub = argv[1]
            let path = argv[2]
            do {
                let url = try CLIPaths.registryURL()
                var reg = try CLIRegistry.load(from: url)
                switch sub {
                case "add":
                    reg.addBookmark(path: path)
                    try reg.save(to: url)
                    print("✅ Bookmarked \(path)")
                case "remove":
                    reg.removeBookmark(path: path)
                    try reg.save(to: url)
                    print("✅ Removed bookmark \(path)")
                default:
                    print("Usage: blazedb bookmark add <path>  |  blazedb bookmark remove <path>")
                    exit(1)
                }
            } catch {
                print("💥 \(error)")
                exit(1)
            }
            return
        }

        if argv.first == "master" {
            handleMasterCommand(Array(argv.dropFirst()))
            return
        }

        if argv.contains("--manager") {
            BlazedbRepl.runManager()
            return
        }

        if argv.contains("--create-test") {
            do {
                try handleCreateTest()
            } catch {
                print("💥 Error: \(error)")
                exit(1)
            }
            return
        }

        let scanHome = argv.contains("--scan-home")
        let masterMode = argv.contains("--master")
        let filtered = argv.filter { $0 != "--scan-home" && $0 != "--master" }

        if filtered.isEmpty {
            if scanHome {
                runStartFlow()
            } else {
                runPickerThenRepl(startHomeScan: false, masterMode: masterMode)
            }
            return
        }

        if filtered.first?.hasPrefix("-") == true {
            writeStderrLine("Unknown option: \(filtered[0])")
            writeStderrLine("Try `blazedb --help`.")
            exit(1)
        }

        guard let dbPath = filtered.first else {
            printHelp()
            exit(1)
        }

        let shellPassword: String
        if filtered.count >= 2 {
            shellPassword = filtered[1]
        } else {
            do {
                shellPassword = try resolvePasswordForDatabase(path: dbPath, masterMode: masterMode, fallbackPrompt: true)
            } catch {
                print("Error: password required. Set BLAZEDB_PASSWORD env var, use --master, or pass as second argument.")
                exit(1)
            }
        }

        do {
            let registryURL = try CLIPaths.registryURL()
            try BlazedbRepl.runShell(dbPath: dbPath, password: shellPassword, registryURL: registryURL)
        } catch {
            print("💥 Error: \(error)")
            exit(1)
        }
    }
}
