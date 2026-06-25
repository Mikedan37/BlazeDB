//
//  CLIProjectPasswordResolver.swift
//  BlazeCLICore
//

import Foundation

public struct CLIResolvedPassword {
    public let password: String
    public let source: String
    public let projectRoot: String
}

public enum CLIProjectPasswordResolver {
    public static func resolve(dbPath: String) -> CLIResolvedPassword? {
        resolveCandidates(dbPath: dbPath).first
    }

    public static func resolveCandidates(dbPath: String) -> [CLIResolvedPassword] {
        let dbURL = URL(fileURLWithPath: dbPath).standardizedFileURL
        var results: [CLIResolvedPassword] = []
        var seen = Set<String>()
        let started = Date()
        let maxResolutionSeconds: TimeInterval = 3.0
        let maxCandidates = 60

        func outOfBudget() -> Bool {
            Date().timeIntervalSince(started) >= maxResolutionSeconds || results.count >= maxCandidates
        }

        func appendUnique(_ value: CLIResolvedPassword?) {
            guard let value else { return }
            let key = "\(value.password)|\(value.source)|\(value.projectRoot)"
            if seen.insert(key).inserted {
                results.append(value)
            }
        }

        appendUnique(resolveFromDatabaseMetadata(dbURL: dbURL))
        if outOfBudget() { return results }

        if let projectRoot = locateProjectRoot(startingFrom: dbURL.deletingLastPathComponent()) {
            appendUnique(resolveFromBlazeConfig(projectRoot: projectRoot, dbURL: dbURL))
            if outOfBudget() { return results }
            appendUnique(resolveFromEnvFiles(projectRoot: projectRoot, dbURL: dbURL))
            if outOfBudget() { return results }
            appendUnique(resolveFromKnownConfigFiles(projectRoot: projectRoot, dbURL: dbURL))
            if outOfBudget() { return results }
            appendUnique(resolveFromLaunchConfig(projectRoot: projectRoot, dbURL: dbURL))
            if outOfBudget() { return results }
            appendUnique(resolveFromHomeScopedSecretFiles(projectRoot: projectRoot, dbURL: dbURL))
            if outOfBudget() { return results }

            // If structured config files did not produce a clear winner, inspect explicit
            // BlazeDB open/client literals from likely configuration Swift files.
            if results.isEmpty || results.count < 2 {
                for candidate in resolveAllFromSwiftSourceLiterals(
                    projectRoot: projectRoot,
                    dbURL: dbURL,
                    maxScannedFiles: 250
                ) {
                    appendUnique(candidate)
                    if outOfBudget() { return results }
                }
            }
            if outOfBudget() { return results }

            // Final scoped fallback for project-wide defaults.
            for candidate in resolveSharedProjectSecretFallbacks(projectRoot: projectRoot, includeSwiftLiterals: false) {
                appendUnique(candidate)
                if outOfBudget() { return results }
            }
        }

        // Detached DB fallback: scan common local dev roots in structured mode (known files only).
        for root in fallbackProjectRoots() {
            if outOfBudget() { break }
            appendUnique(resolveFromBlazeConfig(projectRoot: root, dbURL: dbURL))
            if outOfBudget() { break }
            appendUnique(resolveFromEnvFiles(projectRoot: root, dbURL: dbURL))
            if outOfBudget() { break }
            appendUnique(resolveFromKnownConfigFiles(projectRoot: root, dbURL: dbURL))
            if outOfBudget() { break }
            appendUnique(resolveFromLaunchConfig(projectRoot: root, dbURL: dbURL))
            if outOfBudget() { break }
            appendUnique(resolveFromHomeScopedSecretFiles(projectRoot: root, dbURL: dbURL))
            if outOfBudget() { break }

            // Detached-db fallback: lightweight scan of likely Swift config files.
            if results.isEmpty {
                for candidate in resolveAllFromSwiftSourceLiterals(
                    projectRoot: root,
                    dbURL: dbURL,
                    maxScannedFiles: 60
                ) {
                    appendUnique(candidate)
                    if outOfBudget() { break }
                }
            }
        }

        return results
    }

    private static func resolveFromDatabaseMetadata(dbURL: URL) -> CLIResolvedPassword? {
        let sidecars = [
            dbURL.appendingPathExtension("meta.json"),
            dbURL.deletingPathExtension().appendingPathExtension("blaze-meta.json"),
        ]

        for sidecar in sidecars {
            guard let data = try? Data(contentsOf: sidecar),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let password = object["password"] as? String, !password.isEmpty {
                return CLIResolvedPassword(
                    password: password,
                    source: "database metadata (\(sidecar.lastPathComponent))",
                    projectRoot: dbURL.deletingLastPathComponent().path
                )
            }

            if let envKey = (object["passwordEnvKey"] as? String) ?? (object["password_env_key"] as? String),
               let value = ProcessInfo.processInfo.environment[envKey], !value.isEmpty {
                return CLIResolvedPassword(
                    password: value,
                    source: "database metadata env key \(envKey)",
                    projectRoot: dbURL.deletingLastPathComponent().path
                )
            }
        }

        return nil
    }

    private static func resolveAllFromSwiftSourceLiterals(
        projectRoot: URL,
        dbURL: URL,
        maxScannedFiles: Int
    ) -> [CLIResolvedPassword] {
        let targetNames = Set(dbNameCandidates(dbURL: dbURL).map { $0.lowercased() })
        guard !targetNames.isEmpty else { return [] }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let openRegex = try? NSRegularExpression(
            pattern: #"(?s)BlazeDB\.open\(\s*name:\s*"([^"]+)"\s*,\s*password:\s*"([^"]+)""#
        )
        let clientRegex = try? NSRegularExpression(
            pattern: #"(?s)BlazeDBClient\([^)]*?name:\s*"([^"]+)"[^)]*?password:\s*"([^"]+)""#
        )
        guard let openRegex, let clientRegex else { return [] }

        var matches: [CLIResolvedPassword] = []
        var seen = Set<String>()

        var scanned = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let filename = fileURL.lastPathComponent
            let likely = filename == "main.swift"
                || filename.hasSuffix("App.swift")
                || filename.contains("Config")
                || filename.contains("Settings")
                || filename.contains("DB")
            guard likely else { continue }

            scanned += 1
            if scanned > maxScannedFiles { break }

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for resolved in extractAllNamePasswords(from: text, with: openRegex, targetNames: targetNames)
                + extractAllNamePasswords(from: text, with: clientRegex, targetNames: targetNames) {
                let candidate = CLIResolvedPassword(
                    password: resolved.password,
                    source: "Swift config literal (\(fileURL.lastPathComponent))",
                    projectRoot: projectRoot.path
                )
                let key = "\(candidate.password)|\(candidate.source)|\(candidate.projectRoot)"
                if seen.insert(key).inserted {
                    matches.append(candidate)
                }
            }
            if matches.count >= 30 {
                return matches
            }
        }
        return matches
    }

    private static func resolveSharedProjectSecretFallbacks(projectRoot: URL, includeSwiftLiterals: Bool) -> [CLIResolvedPassword] {
        var out: [CLIResolvedPassword] = []
        var seen = Set<String>()

        func append(password: String, source: String) {
            guard !password.isEmpty else { return }
            let key = "\(password)|\(source)|\(projectRoot.path)"
            if seen.insert(key).inserted {
                out.append(
                    CLIResolvedPassword(
                        password: password,
                        source: source,
                        projectRoot: projectRoot.path
                    )
                )
            }
        }

        // Shared env keys (non-db-specific) as deterministic project defaults.
        for envName in [".env.local", ".env"] {
            let envURL = projectRoot.appendingPathComponent(envName)
            guard let data = try? Data(contentsOf: envURL),
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            for key in ["BLAZEDB_PASSWORD", "DB_PASSWORD", "DATABASE_PASSWORD"] {
                if let value = resolveFromKeyValueText(text, keys: [key]) {
                    append(password: value, source: "\(envName) (\(key))")
                }
            }
        }

        guard includeSwiftLiterals else { return out }

        // Shared Swift literals from explicit BlazeDB open/client construction.
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return out }

        let openRegex = try? NSRegularExpression(
            pattern: #"(?s)BlazeDB\.open\(\s*name:\s*"([^"]+)"\s*,\s*password:\s*"([^"]+)""#
        )
        let clientRegex = try? NSRegularExpression(
            pattern: #"(?s)BlazeDBClient\([^)]*?name:\s*"([^"]+)"[^)]*?password:\s*"([^"]+)""#
        )
        guard let openRegex, let clientRegex else { return out }

        var scanned = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            scanned += 1
            if scanned > 300 { break }

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for resolved in extractAllNamePasswords(from: text, with: openRegex, targetNames: Set(["*"]))
                + extractAllNamePasswords(from: text, with: clientRegex, targetNames: Set(["*"])) {
                append(password: resolved.password, source: "shared Swift config literal")
                if out.count >= 40 { return out }
            }
        }

        return out
    }

    private static func extractAllNamePasswords(
        from text: String,
        with regex: NSRegularExpression,
        targetNames: Set<String>
    ) -> [(name: String, password: String)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        var out: [(name: String, password: String)] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let passwordRange = Range(match.range(at: 2), in: text)
            else { continue }
            let name = String(text[nameRange]).lowercased()
            let password = String(text[passwordRange])
            let wildcard = targetNames.contains("*")
            guard (wildcard || targetNames.contains(name)), !password.isEmpty else { continue }
            out.append((name, password))
        }
        return out
    }

    private static func dbNameCandidates(dbURL: URL) -> [String] {
        let base = dbURL.deletingPathExtension().lastPathComponent
        var names = [base]

        let pattern = #"^(.*)-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(base.startIndex..<base.endIndex, in: base)
            if let match = regex.firstMatch(in: base, range: range),
               match.numberOfRanges >= 2,
               let prefixRange = Range(match.range(at: 1), in: base) {
                let prefix = String(base[prefixRange])
                if !prefix.isEmpty {
                    names.append(prefix)
                }
            }
        }
        return names
    }

    private static func looksLikeUUIDString(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        return value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil
    }

    private static func locateProjectRoot(startingFrom directoryURL: URL) -> URL? {
        let fm = FileManager.default
        var current = directoryURL

        for _ in 0..<12 {
            let markers = [
                current.appendingPathComponent(".git").path,
                current.appendingPathComponent("Package.swift").path,
                current.appendingPathComponent(".blaze/config").path,
                current.appendingPathComponent(".env").path,
            ]
            if markers.contains(where: { fm.fileExists(atPath: $0) }) {
                return current
            }

            if let files = try? fm.contentsOfDirectory(atPath: current.path),
               files.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }

        return nil
    }

    private static func fallbackProjectRoots() -> [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL?) {
            guard let url else { return }
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted { roots.append(URL(fileURLWithPath: path)) }
        }

        add(URL(fileURLWithPath: fm.currentDirectoryPath))

        let home = fm.homeDirectoryForCurrentUser
        let topLevelBases = [
            home.appendingPathComponent("Developer", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Projects", isDirectory: true),
        ]

        for base in topLevelBases {
            guard let entries = try? fm.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if looksLikeProjectRoot(entry) {
                    add(entry)
                }
                // Include one nested level (workspace style: ~/Developer/Org/Repo)
                if let nested = try? fm.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for child in nested {
                        guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                        if looksLikeProjectRoot(child) {
                            add(child)
                        }
                    }
                }
            }
        }

        return roots
    }

    private static func looksLikeProjectRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return true }
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return true }
        if fm.fileExists(atPath: url.appendingPathComponent(".blaze/config").path) { return true }
        if fm.fileExists(atPath: url.appendingPathComponent(".env").path) { return true }
        if let names = try? fm.contentsOfDirectory(atPath: url.path), names.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            return true
        }
        return false
    }

    private static func resolveFromBlazeConfig(projectRoot: URL, dbURL: URL) -> CLIResolvedPassword? {
        let configURL = projectRoot.appendingPathComponent(".blaze/config")
        guard let data = try? Data(contentsOf: configURL) else { return nil }

        // JSON path (preferred)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let password = firstPasswordLikeValue(in: object, dbURL: dbURL), !password.isEmpty {
                return CLIResolvedPassword(password: password, source: ".blaze/config", projectRoot: projectRoot.path)
            }
        }

        // Fallback: env-like KEY=VALUE path
        if let text = String(data: data, encoding: .utf8),
           let password = resolveFromKeyValueText(text, keys: candidatePasswordKeys(dbURL: dbURL)),
           !password.isEmpty {
            return CLIResolvedPassword(password: password, source: ".blaze/config", projectRoot: projectRoot.path)
        }

        return nil
    }

    private static func resolveFromEnvFiles(projectRoot: URL, dbURL: URL) -> CLIResolvedPassword? {
        let candidates = [".env.local", ".env"]
        let keys = candidatePasswordKeys(dbURL: dbURL)

        for name in candidates {
            let fileURL = projectRoot.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8)
            else { continue }

            if let value = resolveFromKeyValueText(text, keys: keys), !value.isEmpty {
                return CLIResolvedPassword(password: value, source: name, projectRoot: projectRoot.path)
            }
        }

        return nil
    }

    private static func resolveFromKnownConfigFiles(projectRoot: URL, dbURL: URL) -> CLIResolvedPassword? {
        let files = [
            "config.json",
            "appsettings.json",
            "app.config.json",
            "blaze.config.json",
            "blazedb.config.json",
        ]

        for name in files {
            let fileURL = projectRoot.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else { continue }

            if let password = firstPasswordLikeValue(in: object, dbURL: dbURL), !password.isEmpty {
                return CLIResolvedPassword(password: password, source: name, projectRoot: projectRoot.path)
            }
        }

        return nil
    }

    private static func resolveFromLaunchConfig(projectRoot: URL, dbURL: URL) -> CLIResolvedPassword? {
        let launchURL = projectRoot.appendingPathComponent(".vscode/launch.json")
        guard let data = try? Data(contentsOf: launchURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let configurations = object["configurations"] as? [[String: Any]] {
            let keys = candidatePasswordKeys(dbURL: dbURL)
            for config in configurations {
                if let env = config["env"] as? [String: Any] {
                    for key in keys {
                        if let value = env[key] as? String, !value.isEmpty {
                            return CLIResolvedPassword(password: value, source: ".vscode/launch.json env.\(key)", projectRoot: projectRoot.path)
                        }
                    }
                }
            }
        }

        return nil
    }

    private static func resolveFromHomeScopedSecretFiles(projectRoot: URL, dbURL: URL) -> CLIResolvedPassword? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectName = projectRoot.lastPathComponent.lowercased()
        let dbNames = dbNameCandidates(dbURL: dbURL).map { $0.lowercased() }

        var hiddenDirs = Set<String>()
        if !projectName.isEmpty { hiddenDirs.insert(".\(projectName)") }
        for db in dbNames where !db.isEmpty { hiddenDirs.insert(".\(db)") }

        let keyFiles = [".store-key", "store.key", "store-key", ".db-password", "db-password", "password"]
        for dir in hiddenDirs {
            let base = home.appendingPathComponent(dir, isDirectory: true)
            for keyFile in keyFiles {
                let fileURL = base.appendingPathComponent(keyFile)
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                return CLIResolvedPassword(
                    password: value,
                    source: "\(dir)/\(keyFile)",
                    projectRoot: projectRoot.path
                )
            }
        }

        return nil
    }

    private static func candidatePasswordKeys(dbURL: URL) -> [String] {
        let base = dbURL.deletingPathExtension().lastPathComponent
        let sanitized = base.uppercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        let normalized = String(sanitized)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        var keys = ["BLAZEDB_PASSWORD", "DB_PASSWORD", "DATABASE_PASSWORD"]
        if !normalized.isEmpty {
            keys.append("BLAZEDB_PASSWORD_\(normalized)")
            keys.append("\(normalized)_BLAZEDB_PASSWORD")
            keys.append("\(normalized)_DB_PASSWORD")
            keys.append("\(normalized)_DATABASE_PASSWORD")
        }
        return keys
    }

    private static func resolveFromKeyValueText(_ text: String, keys: [String]) -> String? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key) else { continue }
            let unquoted = valuePart.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !unquoted.isEmpty { return unquoted }
        }
        return nil
    }

    private static func firstPasswordLikeValue(in object: Any, dbURL: URL) -> String? {
        let keys = Set(candidatePasswordKeys(dbURL: dbURL).map { $0.lowercased() } + [
            "password", "dbpassword", "databasepassword", "blazedbpassword", "blazedb_password",
        ])
        return walkJSON(object: object, keyMatchers: keys)
    }

    private static func walkJSON(object: Any, keyMatchers: Set<String>) -> String? {
        if let dict = object as? [String: Any] {
            for (k, v) in dict {
                let lower = k.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
                let normalizedMatchers = Set(keyMatchers.map { $0.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") })
                if normalizedMatchers.contains(lower), let text = v as? String, !text.isEmpty {
                    return text
                }
                if let nested = walkJSON(object: v, keyMatchers: keyMatchers) { return nested }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = walkJSON(object: item, keyMatchers: keyMatchers) { return nested }
            }
        }
        return nil
    }
}
