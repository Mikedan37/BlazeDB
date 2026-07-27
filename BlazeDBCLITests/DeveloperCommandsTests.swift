import XCTest
@testable import BlazeCLICore

final class DeveloperCommandsTests: XCTestCase {
    func testFindRepositoryRootReturnsNilWithoutMarkers() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dev-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertNil(DeveloperCommands.findRepositoryRoot(startingAt: tmp))
    }

    func testFindRepositoryRootFindsMarkersInParent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dev-root-\(UUID().uuidString)", isDirectory: true)
        let child = root.appendingPathComponent("nested/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: scripts.appendingPathComponent("run-tier0.sh"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let found = DeveloperCommands.findRepositoryRoot(startingAt: child)
        XCTAssertEqual(found?.standardizedFileURL.path, root.standardizedFileURL.path)
    }

    func testFindRepositoryRootRejectsDirectoryNamedRunTier0() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dev-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let fake = root.appendingPathComponent("Scripts/run-tier0.sh", isDirectory: true)
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(DeveloperCommands.findRepositoryRoot(startingAt: root))
    }

    func testParseTestListLineStripsTargetAndParens() {
        let line = "BlazeDB_Tier0.BPlusTreeNodeTests/createsSimpleTree()"
        let parsed = DeveloperCommands.parseTestListLine(line)
        XCTAssertEqual(parsed?.rawIdentifier, line)
        XCTAssertEqual(parsed?.displayName, "BPlusTreeNodeTests.createsSimpleTree")
    }

    func testParseTestListLineSkipsNoise() {
        XCTAssertNil(DeveloperCommands.parseTestListLine(""))
        XCTAssertNil(DeveloperCommands.parseTestListLine("Building for debugging..."))
    }

    func testFilterTestsMatchesDisplayOrRawCaseInsensitive() {
        let tests = [
            DiscoveredTest(
                rawIdentifier: "BlazeDB_Tier0.BPlusTreeNodeTests/createsSimpleTree()",
                displayName: "BPlusTreeNodeTests.createsSimpleTree"
            )
        ]
        XCTAssertEqual(DeveloperCommands.filterTests(tests, matching: "bplus").count, 1)
        XCTAssertEqual(DeveloperCommands.filterTests(tests, matching: "nope").count, 0)
    }

    // MARK: - Experiment discovery / safety

    func testIsValidExperimentNameMatchesRegex() {
        XCTAssertTrue(DeveloperCommands.isValidExperimentName("btree-search"))
        XCTAssertTrue(DeveloperCommands.isValidExperimentName("a"))
        XCTAssertTrue(DeveloperCommands.isValidExperimentName("1bad"))
        XCTAssertFalse(DeveloperCommands.isValidExperimentName("-x"))
        XCTAssertFalse(DeveloperCommands.isValidExperimentName("Upper"))
        XCTAssertFalse(DeveloperCommands.isValidExperimentName("BTree"))
        XCTAssertFalse(DeveloperCommands.isValidExperimentName(""))
        XCTAssertFalse(DeveloperCommands.isValidExperimentName("has_underscore"))
    }

    func testDiscoverExperimentsFindsValidMatchingManifest() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExecutable(at: root.appendingPathComponent("bin/ok.sh"), contents: "#!/bin/sh\nexit 0\n")
        try writeExperiment(
            root: root,
            directoryName: "btree-search",
            name: "btree-search",
            summary: "Search benchmark",
            command: "bin/ok.sh"
        )

        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertEqual(found, [
            DeveloperExperiment(name: "btree-search", summary: "Search benchmark", command: "bin/ok.sh")
        ])
    }

    func testDiscoverExperimentsSkipsInvalidName() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExecutable(at: root.appendingPathComponent("bin/ok.sh"), contents: "#!/bin/sh\nexit 0\n")
        try writeExperiment(
            root: root,
            directoryName: "BTree",
            name: "BTree",
            summary: "bad name",
            command: "bin/ok.sh"
        )

        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertTrue(found.isEmpty)
    }

    func testDiscoverExperimentsSkipsDirectoryNameMismatch() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExecutable(at: root.appendingPathComponent("bin/ok.sh"), contents: "#!/bin/sh\nexit 0\n")
        try writeExperiment(
            root: root,
            directoryName: "wrong-dir",
            name: "btree-search",
            summary: "mismatch",
            command: "bin/ok.sh"
        )

        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertTrue(found.isEmpty)
    }

    func testDiscoverExperimentsRejectsAllDuplicateNames() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExecutable(at: root.appendingPathComponent("bin/ok.sh"), contents: "#!/bin/sh\nexit 0\n")
        try writeExperiment(
            root: root,
            directoryName: "dup-a",
            name: "dup",
            summary: "first",
            command: "bin/ok.sh"
        )
        try writeExperiment(
            root: root,
            directoryName: "dup-b",
            name: "dup",
            summary: "second",
            command: "bin/ok.sh"
        )
        try writeExperiment(
            root: root,
            directoryName: "keep-me",
            name: "keep-me",
            summary: "unique",
            command: "bin/ok.sh"
        )

        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertEqual(found.map(\.name), ["keep-me"])
        XCTAssertFalse(found.contains(where: { $0.name == "dup" }))
    }

    func testDiscoverExperimentsRejectsAbsoluteCommand() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExperiment(
            root: root,
            directoryName: "abs-cmd",
            name: "abs-cmd",
            summary: "absolute",
            command: "/usr/bin/true"
        )

        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertTrue(found.isEmpty)
        XCTAssertNil(
            DeveloperCommands.resolvedExecutableURL(command: "/usr/bin/true", repositoryRoot: root)
        )
    }

    func testResolvedExecutableURLRejectsSymlinkEscapingRepo() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let outsideScript = outside.appendingPathComponent("escape.sh")
        try writeExecutable(at: outsideScript, contents: "#!/bin/sh\nexit 0\n")

        let link = root.appendingPathComponent("bin/escape.sh")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: outsideScript.path
        )

        XCTAssertNil(
            DeveloperCommands.resolvedExecutableURL(command: "bin/escape.sh", repositoryRoot: root)
        )
    }

    func testResolvedExecutableURLAcceptsInRepoExecutable() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("bin/ok.sh")
        try writeExecutable(at: script, contents: "#!/bin/sh\nexit 0\n")

        let resolved = DeveloperCommands.resolvedExecutableURL(command: "bin/ok.sh", repositoryRoot: root)
        XCTAssertEqual(
            resolved?.resolvingSymlinksInPath().standardizedFileURL.path,
            script.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testResolvedExecutableURLAcceptsInRepoViaSymlinkRoot() throws {
        let realRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: realRoot) }
        try writeExecutable(at: realRoot.appendingPathComponent("bin/ok.sh"), contents: "#!/bin/sh\nexit 0\n")

        let linkRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-exp-link-\(UUID().uuidString)", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            atPath: linkRoot.path,
            withDestinationPath: realRoot.path
        )
        defer { try? FileManager.default.removeItem(at: linkRoot) }

        let resolved = DeveloperCommands.resolvedExecutableURL(
            command: "bin/ok.sh",
            repositoryRoot: linkRoot
        )
        XCTAssertNotNil(resolved)
        XCTAssertEqual(
            resolved?.resolvingSymlinksInPath().standardizedFileURL.path,
            realRoot.appendingPathComponent("bin/ok.sh").resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testResolvedExecutableURLRejectsRelativeParentEscape() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(
            DeveloperCommands.resolvedExecutableURL(
                command: "bin/../../outside",
                repositoryRoot: root
            )
        )
    }

    func testDiscoverExperimentsSortsByName() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExecutable(at: root.appendingPathComponent("bin/ok.sh"), contents: "#!/bin/sh\nexit 0\n")
        try writeExperiment(
            root: root,
            directoryName: "zeta",
            name: "zeta",
            summary: "z",
            command: "bin/ok.sh"
        )
        try writeExperiment(
            root: root,
            directoryName: "alpha",
            name: "alpha",
            summary: "a",
            command: "bin/ok.sh"
        )

        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertEqual(found.map(\.name), ["alpha", "zeta"])
    }

    func testDiscoverExperimentsMissingDirectoryReturnsEmpty() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try DeveloperCommands.discoverExperiments(repositoryRoot: root)
        XCTAssertTrue(found.isEmpty)
    }

    func testListExperimentsEmptyPointsToReadme() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let status = try captureStdout {
            try DeveloperCommands.listExperiments(repositoryRoot: root)
        }
        XCTAssertEqual(status.code, 0)
        XCTAssertTrue(status.output.contains("Experiments/README.md"))
    }

    func testRunExperimentForwardsArgsAndPropagatesExitCode() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeExecutable(
            at: root.appendingPathComponent("bin/echo-args.sh"),
            contents: """
            #!/bin/sh
            printf '%s\\n' "$@"
            exit 7
            """
        )
        try writeExperiment(
            root: root,
            directoryName: "echo-args",
            name: "echo-args",
            summary: "echo",
            command: "bin/echo-args.sh"
        )

        let status = try captureStdout {
            try DeveloperCommands.runExperiment(
                name: "echo-args",
                forwardedArgs: ["--records", "10000"],
                repositoryRoot: root
            )
        }
        XCTAssertEqual(status.code, 7)
        XCTAssertTrue(status.output.contains("--records"))
        XCTAssertTrue(status.output.contains("10000"))
    }

    func testRunExperimentUnknownNameReturnsOne() throws {
        let root = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let code = try DeveloperCommands.runExperiment(
            name: "missing",
            forwardedArgs: [],
            repositoryRoot: root
        )
        XCTAssertEqual(code, 1)
    }

    // MARK: - Experiment fixtures

    private func makeTempRepoRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-exp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: scripts.appendingPathComponent("run-tier0.sh"), atomically: true, encoding: .utf8)
        return root
    }

    private func writeExperiment(
        root: URL,
        directoryName: String,
        name: String,
        summary: String,
        command: String
    ) throws {
        let dir = root.appendingPathComponent("Experiments/\(directoryName)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"name":"\(name)","summary":"\(summary)","command":"\(command)"}
        """
        try json.write(to: dir.appendingPathComponent("experiment.json"), atomically: true, encoding: .utf8)
    }

    private func writeExecutable(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func captureStdout(_ body: () throws -> Int32) throws -> (code: Int32, output: String) {
        let pipe = Pipe()
        let original = dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(original, 0)
        // fflush(nil) avoids referencing Glibc's non-Sendable `stdout` under Swift 6.2.
        fflush(nil)
        XCTAssertEqual(dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO), STDOUT_FILENO)
        let code: Int32
        do {
            code = try body()
        } catch {
            fflush(nil)
            _ = dup2(original, STDOUT_FILENO)
            close(original)
            try? pipe.fileHandleForWriting.close()
            throw error
        }
        fflush(nil)
        try? pipe.fileHandleForWriting.close()
        _ = dup2(original, STDOUT_FILENO)
        close(original)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (code, output)
    }
}
