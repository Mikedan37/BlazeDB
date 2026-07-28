//
//  DeveloperCommands.swift
//  BlazeCLICore
//

import Foundation

public struct DeveloperExperiment: Decodable, Equatable {
    public let name: String
    public let summary: String
    public let command: String

    public init(name: String, summary: String, command: String) {
        self.name = name
        self.summary = summary
        self.command = command
    }
}

public struct DiscoveredTest: Equatable {
    public let rawIdentifier: String
    public let displayName: String

    public init(rawIdentifier: String, displayName: String) {
        self.rawIdentifier = rawIdentifier
        self.displayName = displayName
    }
}

public enum DeveloperCommands {
    public static func findRepositoryRoot(
        startingAt start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        var current = start.standardizedFileURL
        let fm = FileManager.default
        while true {
            let package = current.appendingPathComponent("Package.swift")
            let tier0 = current.appendingPathComponent("Scripts/run-tier0.sh")
            var isDir: ObjCBool = false
            let tier0IsFile = fm.fileExists(atPath: tier0.path, isDirectory: &isDir) && !isDir.boolValue
            if fm.fileExists(atPath: package.path) && tier0IsFile {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    public static func listTiers() -> Int32 {
        let rows: [(Int, String, String)] = [
            (0, "Fast local correctness", "Scripts/run-tier0.sh"),
            (1, "PR correctness gate", "Scripts/run-tier1.sh"),
            (2, "Integration/recovery", "Scripts/run-tier2.sh"),
            (3, "Stress/destructive", "Scripts/run-tier3.sh"),
        ]
        for (tier, summary, path) in rows {
            print("Tier \(tier)  \(summary)    \(path)")
        }
        return 0
    }

    public static func parseTestListLine(_ line: String) -> DiscoveredTest? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("/") else { return nil }
        // Require Type/method or Target.Type/method shape (reject free-form noise).
        let identifierPattern = #"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*/[A-Za-z_][A-Za-z0-9_]*(\(\))?$"#
        guard trimmed.range(of: identifierPattern, options: .regularExpression) != nil else {
            return nil
        }

        var display = trimmed
        if let match = display.range(of: #"^BlazeDB_Tier\d+\."#, options: .regularExpression) {
            display.removeSubrange(match)
        }
        display = display.replacingOccurrences(of: "/", with: ".")
        if display.hasSuffix("()") {
            display.removeLast(2)
        }
        return DiscoveredTest(rawIdentifier: trimmed, displayName: display)
    }

    public static func filterTests(_ tests: [DiscoveredTest], matching search: String?) -> [DiscoveredTest] {
        guard let search, !search.isEmpty else { return tests }
        return tests.filter { test in
            test.displayName.localizedCaseInsensitiveContains(search)
                || test.rawIdentifier.localizedCaseInsensitiveContains(search)
        }
    }

    public static func listTests(matching search: String?, repositoryRoot: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "test", "list"]
        process.currentDirectoryURL = repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["BLAZEDB_TEST_SCOPE"] = "tier0"
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        // Leave standardError nil so stderr stays inherited/visible.

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            return process.terminationStatus
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        let parsed = output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseTestListLine(String($0)) }
        let matches = filterTests(parsed, matching: search)

        guard !matches.isEmpty else {
            let label = search.map { " matching \"\($0)\"" } ?? ""
            FileHandle.standardError.write(Data("No matching tests\(label).\n".utf8))
            return 1
        }

        let noun = matches.count == 1 ? "test" : "tests"
        print("Found \(matches.count) matching \(noun):")
        for test in matches {
            print("  \(test.displayName)")
        }
        print("Run:")
        for test in matches {
            print("  blazedb dev test \(test.displayName)")
        }
        return 0
    }

    public static func runTest(filter: String, repositoryRoot: URL) throws -> Int32 {
        var environment = ProcessInfo.processInfo.environment
        environment["BLAZEDB_TEST_SCOPE"] = "tier0"
        return try runInheritedProcess(
            executable: "/usr/bin/env",
            arguments: ["swift", "test", "--filter", filter],
            currentDirectory: repositoryRoot,
            environment: environment
        )
    }

    public static func isValidExperimentName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil
    }

    public static func resolvedExecutableURL(command: String, repositoryRoot: URL) -> URL? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let executableToken = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
        guard !executableToken.isEmpty else { return nil }
        if executableToken.hasPrefix("/") || executableToken.hasPrefix("~") {
            return nil
        }
        // Reject absolute and parent-escaping tokens before joining.
        if (executableToken as NSString).isAbsolutePath { return nil }

        let root = repositoryRoot.resolvingSymlinksInPath().standardizedFileURL
        let declared = root.appendingPathComponent(executableToken)
        let resolved = declared.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path
        if resolved.path == rootPath { return resolved }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard resolved.path.hasPrefix(prefix) else { return nil }
        return resolved
    }

    public static func discoverExperiments(repositoryRoot: URL) throws -> [DeveloperExperiment] {
        let fm = FileManager.default
        let experimentsDir = repositoryRoot.appendingPathComponent("Experiments", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: experimentsDir.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let decoder = JSONDecoder()
        var candidates: [(path: String, experiment: DeveloperExperiment)] = []

        let children = try fm.contentsOfDirectory(
            at: experimentsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for child in children {
            var childIsDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &childIsDir), childIsDir.boolValue else {
                continue
            }
            let manifestURL = child.appendingPathComponent("experiment.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }

            let data: Data
            do {
                data = try Data(contentsOf: manifestURL)
            } catch {
                warnExperiment("Skipping \(manifestURL.path): unable to read experiment.json (\(error))")
                continue
            }

            let experiment: DeveloperExperiment
            do {
                experiment = try decoder.decode(DeveloperExperiment.self, from: data)
            } catch {
                warnExperiment("Skipping \(manifestURL.path): invalid experiment.json (\(error))")
                continue
            }

            let directoryName = child.lastPathComponent
            if !isValidExperimentName(experiment.name) {
                warnExperiment(
                    "Skipping \(manifestURL.path): invalid experiment name \"\(experiment.name)\""
                )
                continue
            }
            if directoryName != experiment.name {
                warnExperiment(
                    "Skipping \(manifestURL.path): directory name \"\(directoryName)\" does not match name \"\(experiment.name)\""
                )
                continue
            }

            let command = experiment.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if command.isEmpty {
                warnExperiment("Skipping \(manifestURL.path): empty command")
                continue
            }
            if (command as NSString).isAbsolutePath || command.hasPrefix("/") || command.hasPrefix("~") {
                warnExperiment("Skipping \(manifestURL.path): command must be repository-relative")
                continue
            }
            guard resolvedExecutableURL(command: command, repositoryRoot: repositoryRoot) != nil else {
                warnExperiment(
                    "Skipping \(manifestURL.path): command resolves outside the repository"
                )
                continue
            }

            candidates.append((manifestURL.path, experiment))
        }

        var byName: [String: [(path: String, experiment: DeveloperExperiment)]] = [:]
        for candidate in candidates {
            byName[candidate.experiment.name, default: []].append(candidate)
        }

        var survivors: [DeveloperExperiment] = []
        for (name, group) in byName {
            if group.count > 1 {
                for item in group {
                    warnExperiment(
                        "Duplicate experiment name \"\(name)\" at \(item.path); omitting all duplicates"
                    )
                }
                continue
            }
            if let only = group.first {
                survivors.append(only.experiment)
            }
        }

        return survivors.sorted { $0.name < $1.name }
    }

    public static func listExperiments(repositoryRoot: URL) throws -> Int32 {
        let experiments = try discoverExperiments(repositoryRoot: repositoryRoot)
        if experiments.isEmpty {
            print("No repository experiments found. See Experiments/README.md for how to add one.")
            return 0
        }
        for experiment in experiments {
            print("\(experiment.name)    \(experiment.summary)")
        }
        return 0
    }

    public static func runExperiment(
        name: String,
        forwardedArgs: [String],
        repositoryRoot: URL
    ) throws -> Int32 {
        let experiments = try discoverExperiments(repositoryRoot: repositoryRoot)
        guard let experiment = experiments.first(where: { $0.name == name }) else {
            FileHandle.standardError.write(Data(
                "Unknown experiment: \(name)\nTry `blazedb dev experiments`.\n".utf8
            ))
            return 1
        }

        let tokens = experiment.command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let executableToken = tokens.first else {
            FileHandle.standardError.write(Data(
                "Experiment \"\(name)\" has an empty command.\n".utf8
            ))
            return 1
        }

        guard let resolved = resolvedExecutableURL(
            command: executableToken,
            repositoryRoot: repositoryRoot
        ) else {
            FileHandle.standardError.write(Data(
                "Experiment \"\(name)\" command resolves outside the repository.\n".utf8
            ))
            return 1
        }

        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), !isDir.boolValue else {
            FileHandle.standardError.write(Data(
                "Experiment \"\(name)\" executable not found: \(executableToken)\n".utf8
            ))
            return 1
        }
        guard fm.isExecutableFile(atPath: resolved.path) else {
            FileHandle.standardError.write(Data(
                "Experiment \"\(name)\" executable is not executable: \(executableToken)\n".utf8
            ))
            return 1
        }

        let commandArgs = Array(tokens.dropFirst()) + forwardedArgs
        return try runInheritedProcess(
            executable: resolved.path,
            arguments: commandArgs,
            currentDirectory: repositoryRoot,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private static func warnExperiment(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    /// Split `dev experiment <name> -- <args…>` into name and forwarded args.
    static func parseExperimentInvocation(_ arguments: ArraySlice<String>) -> (name: String, forwarded: [String])? {
        guard let name = arguments.first, !name.isEmpty else { return nil }
        let rest = Array(arguments.dropFirst())
        if let dashDash = rest.firstIndex(of: "--") {
            return (name, Array(rest[(dashDash + 1)...]))
        }
        return (name, rest)
    }

    static func runTierScript(tier: Int, repositoryRoot: URL) throws -> Int32 {
        let relative = "Scripts/run-tier\(tier).sh"
        let script = repositoryRoot.appendingPathComponent(relative)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: script.path, isDirectory: &isDir), !isDir.boolValue else {
            FileHandle.standardError.write(Data("Missing tier script: \(relative)\n".utf8))
            return 1
        }
        return try runInheritedProcess(
            executable: script.path,
            arguments: [],
            currentDirectory: repositoryRoot,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func runInheritedProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment
        // Leave standardOutput/standardError nil to inherit parent stdio.
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    public static func run(arguments: [String], repositoryRoot: URL?) throws -> Int32 {
        guard let repositoryRoot else {
            FileHandle.standardError.write(Data(
                "Developer commands are available inside a BlazeDB repository checkout.\n".utf8
            ))
            return 1
        }
        let sub = arguments.first ?? "help"
        switch sub {
        case "help", "--help", "-h":
            let experiments = (try? discoverExperiments(repositoryRoot: repositoryRoot)) ?? []
            CLIHelp.printDeveloper(experiments: experiments)
            return 0
        case "tiers":
            return listTiers()
        case "tier0":
            return try runTierScript(tier: 0, repositoryRoot: repositoryRoot)
        case "tier1":
            return try runTierScript(tier: 1, repositoryRoot: repositoryRoot)
        case "tier2":
            return try runTierScript(tier: 2, repositoryRoot: repositoryRoot)
        case "tier3":
            return try runTierScript(tier: 3, repositoryRoot: repositoryRoot)
        case "tests":
            let search = arguments.dropFirst().first
            return try listTests(matching: search, repositoryRoot: repositoryRoot)
        case "test":
            guard let filter = arguments.dropFirst().first, !filter.isEmpty else {
                FileHandle.standardError.write(Data(
                    "Usage: blazedb dev test <filter>\n".utf8
                ))
                return 1
            }
            return try runTest(filter: filter, repositoryRoot: repositoryRoot)
        case "experiments":
            return try listExperiments(repositoryRoot: repositoryRoot)
        case "experiment":
            guard let parsed = parseExperimentInvocation(arguments.dropFirst()) else {
                FileHandle.standardError.write(Data(
                    "Usage: blazedb dev experiment <name> [-- <args>]\n".utf8
                ))
                return 1
            }
            return try runExperiment(
                name: parsed.name,
                forwardedArgs: parsed.forwarded,
                repositoryRoot: repositoryRoot
            )
        case "bench":
            return try runBench(
                arguments: Array(arguments.dropFirst()),
                repositoryRoot: repositoryRoot
            )
        default:
            FileHandle.standardError.write(Data(
                "Unknown developer command: \(sub)\nTry `blazedb dev help`.\n".utf8
            ))
            return 1
        }
    }

    /// Forwards to the repo-root `./bench` / `Scripts/bench.sh` front door.
    static func runBench(arguments: [String], repositoryRoot: URL) throws -> Int32 {
        let bench = repositoryRoot.appendingPathComponent("bench")
        let script = repositoryRoot.appendingPathComponent("Scripts/bench.sh")
        let executable: String
        if FileManager.default.isExecutableFile(atPath: bench.path) {
            executable = bench.path
        } else if FileManager.default.isExecutableFile(atPath: script.path) {
            executable = script.path
        } else {
            FileHandle.standardError.write(Data(
                "Benchmark front door missing (expected ./bench or Scripts/bench.sh).\nSee Docs/Benchmarks/README.md.\n".utf8
            ))
            return 1
        }
        return try runInheritedProcess(
            executable: executable,
            arguments: arguments,
            currentDirectory: repositoryRoot,
            environment: ProcessInfo.processInfo.environment
        )
    }
}
