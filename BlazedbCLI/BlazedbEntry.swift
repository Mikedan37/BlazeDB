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

private func runStartFlow(masterMode: Bool = false) {
    runPickerThenRepl(startHomeScan: true, showStartupSplash: true, masterMode: masterMode)
}

private func readDatabasePasswordPrompt() throws -> String {
    try CLIPasswordReader.readLineHidden(prompt: "Database password: ")
}

private struct MasterLookupResult {
    let password: String?
    let passphraseUsed: String?
    let keyringExists: Bool
}

private struct PasswordResolutionResult {
    let password: String
    let source: String
    let enrolledInMasterLock: Bool
}

private func resolveViaMasterKeyring(path: String, masterMode: Bool) throws -> MasterLookupResult {
    let status = try CLIMasterKeyringStore.status()
    guard status.exists else {
        return MasterLookupResult(password: nil, passphraseUsed: nil, keyringExists: false)
    }

    let passphrase: String
    if masterMode {
        passphrase = try readMasterPassphrase(confirm: false)
    } else if let envPassword = ProcessInfo.processInfo.environment["BLAZEDB_MASTER_PASSWORD"], !envPassword.isEmpty {
        passphrase = envPassword
    } else {
        let maybePassphrase = try CLIPasswordReader.readLineHidden(prompt: "Master passphrase (press Enter to skip): ")
        guard !maybePassphrase.isEmpty else {
            return MasterLookupResult(password: nil, passphraseUsed: nil, keyringExists: true)
        }
        passphrase = maybePassphrase
    }

    do {
        let resolved = try CLIMasterKeyringStore.resolveSecret(passphrase: passphrase, dbPath: path)
        return MasterLookupResult(password: resolved, passphraseUsed: passphrase, keyringExists: true)
    } catch CLIMasterKeyringError.invalidPassphrase {
        if masterMode {
            let retry = try readMasterPassphrase(confirm: false)
            let resolved = try CLIMasterKeyringStore.resolveSecret(passphrase: retry, dbPath: path)
            return MasterLookupResult(password: resolved, passphraseUsed: retry, keyringExists: true)
        }
        print("⚠️ Invalid master passphrase. Falling back to database password.")
        return MasterLookupResult(password: nil, passphraseUsed: nil, keyringExists: true)
    } catch CLIMasterKeyringError.notInitialized {
        return MasterLookupResult(password: nil, passphraseUsed: nil, keyringExists: false)
    }
}

private func maybeSavePasswordToMasterLock(
    dbPath: String,
    dbPassword: String,
    masterMode: Bool,
    keyringExists: Bool,
    lookupPassphrase: String?
) -> Bool {
    do {
        let passphrase: String?
        let hasEnvPassphrase = ProcessInfo.processInfo.environment["BLAZEDB_MASTER_PASSWORD"]?.isEmpty == false
        // In normal picker mode, do not force users through master setup prompts.
        // Auto-enroll only when keyring already exists or when user explicitly opts into master mode.
        if !masterMode && !keyringExists && lookupPassphrase == nil && !hasEnvPassphrase {
            return false
        }
        if let envPassphrase = ProcessInfo.processInfo.environment["BLAZEDB_MASTER_PASSWORD"], !envPassphrase.isEmpty {
            passphrase = envPassphrase
        } else if let lookupPassphrase, !lookupPassphrase.isEmpty {
            passphrase = lookupPassphrase
        } else if masterMode {
            if keyringExists {
                passphrase = try CLIPasswordReader.readLineHidden(prompt: "Master passphrase (save for future opens): ")
            } else {
                let first = try CLIPasswordReader.readLineHidden(prompt: "Create master passphrase to save this DB (or press Enter to skip): ")
                if first.isEmpty {
                    passphrase = nil
                } else {
                    let confirm = try CLIPasswordReader.readLineHidden(prompt: "Confirm master passphrase: ")
                    if first != confirm {
                        print("⚠️ Master passphrases did not match. Skipped auto-save to Master Lock.")
                        return false
                    }
                    passphrase = first
                }
            }
        } else if keyringExists {
            let maybe = try CLIPasswordReader.readLineHidden(prompt: "Save this password to master lock? Enter master passphrase (or press Enter to skip): ")
            passphrase = maybe.isEmpty ? nil : maybe
        } else {
            let first = try CLIPasswordReader.readLineHidden(prompt: "Create master passphrase to auto-save this DB (or press Enter to skip): ")
            if first.isEmpty {
                passphrase = nil
            } else {
                let confirm = try CLIPasswordReader.readLineHidden(prompt: "Confirm master passphrase: ")
                if first != confirm {
                    print("⚠️ Master passphrases did not match. Skipped auto-save to Master Lock.")
                    return false
                }
                passphrase = first
            }
        }

        guard let passphrase, !passphrase.isEmpty else { return false }

        if !keyringExists {
            _ = try CLIMasterKeyringStore.initialize(passphrase: passphrase)
        }

        _ = try CLIMasterKeyringStore.addEntry(
            passphrase: passphrase,
            dbPath: dbPath,
            dbSecret: dbPassword,
            scope: .persistent,
            label: nil
        )
        return true
    } catch {
        print("⚠️ Could not save password to Master Lock: \(error.localizedDescription)")
        return false
    }
}

private func satisfiesPasswordPolicyShape(_ password: String) -> Bool {
    if password.count < 12 { return false }
    let hasUpper = password.rangeOfCharacter(from: .uppercaseLetters) != nil
    let hasLower = password.rangeOfCharacter(from: .lowercaseLetters) != nil
    let hasDigit = password.rangeOfCharacter(from: .decimalDigits) != nil
    return hasUpper && hasLower && hasDigit
}

private func readValidatedPasswordOrCancel() throws -> String {
    var prompted = try readDatabasePasswordPrompt()
    if prompted.isEmpty {
        throw CLIError.cancelled
    }
    while !satisfiesPasswordPolicyShape(prompted) {
        print("Password format looks invalid (need 12+ chars with uppercase, lowercase, number). Press Enter to cancel.")
        prompted = try readDatabasePasswordPrompt()
        if prompted.isEmpty {
            throw CLIError.cancelled
        }
    }
    return prompted
}

private enum PasswordValidationResult {
    case valid
    case invalid
    case locked(String)
    case signatureMismatch
}

private func validateDatabasePassword(path: String, password: String) -> PasswordValidationResult {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else { return .invalid }
    let previousLogLevel = BlazeLogger.level
    BlazeLogger.level = .silent
    defer { BlazeLogger.level = previousLogLevel }
    do {
        _ = try BlazeDBClient(name: "cli_password_probe", fileURL: url, password: password)
        return .valid
    } catch {
        let ns = error as NSError
        let message = error.localizedDescription
        if ns.code == 10 || message.localizedCaseInsensitiveContains("Concurrent process access") || message.localizedCaseInsensitiveContains("held by another process") {
            return .locked(message)
        }
        if ns.domain == "StorageLayout" && ns.code == 1 {
            return .signatureMismatch
        }
        if message.localizedCaseInsensitiveContains("signature verification failed")
            || message.localizedCaseInsensitiveContains("signing key mismatch")
            || message.localizedCaseInsensitiveContains("metadata may have been tampered with") {
            return .signatureMismatch
        }
        return .invalid
    }
}

private func resolvePasswordForDatabase(path: String, masterMode: Bool, fallbackPrompt: Bool = true) throws -> PasswordResolutionResult {
    if let envPassword = ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"], !envPassword.isEmpty {
        return PasswordResolutionResult(password: envPassword, source: "BLAZEDB_PASSWORD", enrolledInMasterLock: false)
    }

    let masterLookup = try resolveViaMasterKeyring(path: path, masterMode: masterMode)
    if let fromMaster = masterLookup.password {
        return PasswordResolutionResult(password: fromMaster, source: "Master Lock", enrolledInMasterLock: false)
    }

    let discoveredCandidates = CLIProjectPasswordResolver.resolveCandidates(dbPath: path)
    var uniquePasswordsTried = Set<String>()
    let maxPasswordProbeAttempts = 8
    let maxSignatureMismatchAttempts = 3
    var sawSignatureMismatch = false
    var signatureMismatchCount = 0
    for discovered in discoveredCandidates {
        if !uniquePasswordsTried.insert(discovered.password).inserted {
            continue
        }
        if uniquePasswordsTried.count > maxPasswordProbeAttempts {
            break
        }
        switch validateDatabasePassword(path: path, password: discovered.password) {
        case .valid:
            let enrolled = maybeSavePasswordToMasterLock(
                dbPath: path,
                dbPassword: discovered.password,
                masterMode: masterMode,
                keyringExists: masterLookup.keyringExists,
                lookupPassphrase: masterLookup.passphraseUsed
            )
            return PasswordResolutionResult(password: discovered.password, source: discovered.source, enrolledInMasterLock: enrolled)
        case .invalid:
            continue
        case .signatureMismatch:
            sawSignatureMismatch = true
            signatureMismatchCount += 1
            if signatureMismatchCount >= maxSignatureMismatchAttempts {
                break
            }
            continue
        case .locked(let reason):
            throw NSError(domain: "blazedb.locked", code: 10, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    if fallbackPrompt {
        if sawSignatureMismatch {
            print("⚠️ Found candidate credentials, but metadata signature verification failed for this database. Using wrong password can trigger this; enter the correct DB password to continue.")
        }
        print("No saved or project-resolved password found. Enter DB password:")
        let prompted = try readValidatedPasswordOrCancel()
        let enrolled = maybeSavePasswordToMasterLock(
            dbPath: path,
            dbPassword: prompted,
            masterMode: masterMode,
            keyringExists: masterLookup.keyringExists,
            lookupPassphrase: masterLookup.passphraseUsed
        )
        return PasswordResolutionResult(password: prompted, source: "manual entry", enrolledInMasterLock: enrolled)
    }
    throw NSError(domain: "blazedb.master", code: 2, userInfo: [NSLocalizedDescriptionKey: "No stored secret for this database"])
}

private func runPickerThenRepl(startHomeScan: Bool, showStartupSplash: Bool = false, masterMode: Bool) {
    #if os(macOS) || os(Linux)
    do {
        let registryURL = try CLIPaths.registryURL()
        var registry = try CLIRegistry.load(from: registryURL)
        var preResolved: PasswordResolutionResult?
        let picked = try BlazedbPicker.pickDatabase(
            registry: &registry,
            registryURL: registryURL,
            startHomeScanImmediately: startHomeScan,
            showStartupSplash: showStartupSplash,
            onOpenSelected: { selectedURL in
                do {
                    let resolved = try resolvePasswordForDatabase(
                        path: selectedURL.path,
                        masterMode: masterMode,
                        fallbackPrompt: false
                    )
                    preResolved = resolved
                    return true
                } catch {
                    let ns = error as NSError
                    // No stored/project credential: open and fall back to prompt outside picker.
                    if ns.domain == "blazedb.master" && ns.code == 2 {
                        return true
                    }
                    // Locked/concurrency and other hard failures should bubble immediately.
                    throw error
                }
            }
        )
        guard let url = picked else { exit(0) }
        let resolved = if let preResolved {
            preResolved
        } else {
            try resolvePasswordForDatabase(path: url.path, masterMode: masterMode, fallbackPrompt: true)
        }
        let message = resolved.enrolledInMasterLock && resolved.source != "Master Lock"
            ? "✓ Opened \(url.lastPathComponent) · password source: \(resolved.source) · enrolled in Master Lock"
            : "✓ Opened \(url.lastPathComponent) · password source: \(resolved.source)"
        print(message)
        try BlazedbRepl.runShell(dbPath: url.path, password: resolved.password, registryURL: registryURL)
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

private enum CLIRLSError: LocalizedError {
    case missingDBPath
    case missingPreset
    case invalidPreset(String)
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .missingDBPath:
            return "Missing required --db <path> argument."
        case .missingPreset:
            return "Missing required --preset admin-owner|admin-team|viewer-readonly argument."
        case .invalidPreset(let value):
            return "Invalid preset '\(value)'. Expected admin-owner, admin-team, or viewer-readonly."
        case .missingPassword:
            return "Missing database password. Provide --password <value> or set BLAZEDB_PASSWORD."
        }
    }
}

private func parseFlagValue(_ args: [String], flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

private func parseRequiredDBPath(_ args: [String]) throws -> String {
    guard let value = parseFlagValue(args, flag: "--db"), !value.isEmpty else {
        throw CLIRLSError.missingDBPath
    }
    return value
}

private func parseDBPassword(_ args: [String]) throws -> String {
    if let value = parseFlagValue(args, flag: "--password"), !value.isEmpty {
        return value
    }
    if let envValue = ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"], !envValue.isEmpty {
        return envValue
    }
    throw CLIRLSError.missingPassword
}

private func openRLSClient(args: [String]) throws -> (dbPath: String, client: BlazeDBClient, config: CLIRLSConfig) {
    let dbPath = try parseRequiredDBPath(args)
    let password = try parseDBPassword(args)
    let dbURL = URL(fileURLWithPath: dbPath)
    let config = try CLIRLSConfigStore.load(forDBPath: dbPath)
    let client = try BlazeDBClient(name: "blazedb_rls_cli", fileURL: dbURL, password: password)
    CLIRLSConfigStore.apply(config, to: client)
    return (dbPath, client, config)
}

private func printRLSStatus(client: BlazeDBClient) {
    let names = client.listRLSPolicyNames().sorted()
    print("RLS: \(client.isRLSEnabled ? "enabled" : "disabled")")
    print("Policies: \(names.count)")
    if names.isEmpty {
        print("Policy names: (none)")
    } else {
        print("Policy names: \(names.joined(separator: ", "))")
    }
    print("Runtime context set: \(client.hasRLSContext ? "yes" : "no") (process-local only)")
}

private func handleRLSPolicyCommand(_ args: [String]) throws {
    let policySub = args.first ?? "list"
    let globalArgs = Array(args.dropFirst())
    switch policySub {
    case "list":
        let (_, client, _) = try openRLSClient(args: globalArgs)
        let names = client.listRLSPolicyNames().sorted()
        if names.isEmpty {
            print("No RLS policies configured.")
        } else {
            for name in names {
                print(name)
            }
        }
    case "clear":
        let (dbPath, client, loadedConfig) = try openRLSClient(args: globalArgs)
        var config = loadedConfig
        config.policies = []
        client.clearRLSPolicies()
        try CLIRLSConfigStore.save(config, forDBPath: dbPath)
        print("✅ RLS policies cleared.")
    case "add":
        let (dbPath, client, loadedConfig) = try openRLSClient(args: globalArgs)
        var config = loadedConfig
        guard let preset = parseFlagValue(globalArgs, flag: "--preset"), !preset.isEmpty else {
            throw CLIRLSError.missingPreset
        }
        let allowed = Set(["admin-owner", "admin-team", "viewer-readonly"])
        guard allowed.contains(preset) else {
            throw CLIRLSError.invalidPreset(preset)
        }
        let ownerField = parseFlagValue(globalArgs, flag: "--owner-field")
        let teamField = parseFlagValue(globalArgs, flag: "--team-field")
        let spec = CLIRLSPolicySpec(preset: preset, ownerField: ownerField, teamField: teamField)
        if !config.policies.contains(spec) {
            config.policies.append(spec)
        }
        CLIRLSConfigStore.apply(config, to: client)
        try CLIRLSConfigStore.save(config, forDBPath: dbPath)
        print("✅ Added RLS preset '\(preset)'.")
    default:
        throw NSError(domain: "blazedb.rls", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unknown rls policy subcommand: \(policySub)"
        ])
    }
}

private func handleRLSCommand(_ args: [String]) {
    let sub = args.first ?? "status"
    let subArgs = Array(args.dropFirst())
    do {
        switch sub {
        case "status":
            let (_, client, _) = try openRLSClient(args: subArgs)
            printRLSStatus(client: client)
        case "enable":
            let (dbPath, client, loadedConfig) = try openRLSClient(args: subArgs)
            var config = loadedConfig
            config.enabled = true
            client.enableRLS()
            try CLIRLSConfigStore.save(config, forDBPath: dbPath)
            print("✅ RLS enabled.")
        case "disable":
            let (dbPath, client, loadedConfig) = try openRLSClient(args: subArgs)
            var config = loadedConfig
            config.enabled = false
            client.disableRLS()
            try CLIRLSConfigStore.save(config, forDBPath: dbPath)
            print("✅ RLS disabled.")
        case "policy":
            try handleRLSPolicyCommand(subArgs)
        case "help", "--help", "-h":
            print("Usage:")
            print("  blazedb rls status --db <path> [--password <value>]")
            print("  blazedb rls enable --db <path> [--password <value>]")
            print("  blazedb rls disable --db <path> [--password <value>]")
            print("  blazedb rls policy list --db <path> [--password <value>]")
            print("  blazedb rls policy clear --db <path> [--password <value>]")
            print("  blazedb rls policy add --db <path> --preset admin-owner|admin-team|viewer-readonly [--owner-field <field>] [--team-field <field>] [--password <value>]")
            print("Note: Runtime security context is process-local and is not persisted.")
        default:
            throw NSError(domain: "blazedb.rls", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unknown rls subcommand: \(sub)"
            ])
        }
    } catch {
        print("💥 \(error.localizedDescription)")
        exit(1)
    }
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

        if argv.first == "rls" {
            handleRLSCommand(Array(argv.dropFirst()))
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
                runStartFlow(masterMode: masterMode)
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
        var passwordSource = "explicit argument"
        var enrolledInMasterLock = false
        if filtered.count >= 2 {
            shellPassword = filtered[1]
        } else {
            do {
                let resolved = try resolvePasswordForDatabase(path: dbPath, masterMode: masterMode, fallbackPrompt: true)
                shellPassword = resolved.password
                passwordSource = resolved.source
                enrolledInMasterLock = resolved.enrolledInMasterLock
            } catch {
                let ns = error as NSError
                if ns.code == 10 || error.localizedDescription.localizedCaseInsensitiveContains("Concurrent process access") {
                    print("Error: \(error.localizedDescription)")
                } else {
                    print("Error: password required. Set BLAZEDB_PASSWORD env var, use --master, or pass as second argument.")
                }
                exit(1)
            }
        }

        do {
            let registryURL = try CLIPaths.registryURL()
            let name = URL(fileURLWithPath: dbPath).lastPathComponent
            let message = enrolledInMasterLock && passwordSource != "Master Lock"
                ? "✓ Opened \(name) · password source: \(passwordSource) · enrolled in Master Lock"
                : "✓ Opened \(name) · password source: \(passwordSource)"
            print(message)
            try BlazedbRepl.runShell(dbPath: dbPath, password: shellPassword, registryURL: registryURL)
        } catch {
            print("💥 Error: \(error)")
            exit(1)
        }
    }
}
