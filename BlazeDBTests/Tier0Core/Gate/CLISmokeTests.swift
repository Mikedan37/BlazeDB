//
//  CLISmokeTests.swift
//  BlazeDBTests
//
//  Automated CLI smoke tests for BlazeDB command-line tools
//  Created to verify CLI tools work correctly without manual testing
//

import XCTest
import Foundation
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    
    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }
    
    func snapshot() -> Data {
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }
}

final class CLISmokeTests: XCTestCase {
    var tempDir: URL!
    private let testPassword = "TestPass123!"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeDB_CLISmoke_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let requiredExecutables = ["BlazeDoctor", "BlazeInfo", "BlazeDump"]
        let missing = requiredExecutables.filter { resolveExecutablePath($0) == nil }
        if !missing.isEmpty {
            throw XCTSkip("Skipping CLI smoke tests; missing executables: \(missing.joined(separator: ", "))")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func resolveExecutablePath(_ executable: String) -> String? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var projectRoot: URL?
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                projectRoot = dir
                break
            }
            dir.deleteLastPathComponent()
        }
        guard let projectRoot else { return nil }
        
        let buildRoot = projectRoot.appendingPathComponent(".build")
        let candidateDirs = [
            buildRoot.appendingPathComponent("debug"),
            buildRoot.appendingPathComponent("release"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/debug"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/release"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/debug"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/release")
        ]
        
        for dir in candidateDirs {
            let path = dir.appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Fallback: search .build recursively for executable name.
        if let enumerator = FileManager.default.enumerator(at: buildRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent == executable else { continue }
                let path = fileURL.path
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        
        return nil
    }
    
    private func cliEnvironment(_ overrides: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["BLAZEDB_PASSWORD"] = testPassword
        for (key, value) in overrides {
            if value.isEmpty {
                env.removeValue(forKey: key)
            } else {
                env[key] = value
            }
        }
        return env
    }

    private func runCommand(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) -> (exitCode: Int32, output: String, error: String) {
        let process = Process()
        
        guard let finalPath = resolveExecutablePath(executable) else {
            return (127, "", "Executable '\(executable)' not found in .build outputs")
        }
        
        process.executableURL = URL(fileURLWithPath: finalPath)
        process.arguments = arguments
        process.environment = environment ?? cliEnvironment()
        return runProcess(process)
    }
    
    private func runProcess(_ process: Process) -> (exitCode: Int32, output: String, error: String) {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        inputPipe.fileHandleForWriting.closeFile()

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        do {
            try process.run()
        } catch {
            return (1, "", "Failed to run process: \(error)")
        }

        // Drain each pipe to EOF on its own thread. `readDataToEndOfFile()` returns
        // only at EOF, which arrives once the child has exited and Foundation has
        // closed this process's copy of the write end. Draining concurrently with
        // the child also keeps a child that writes more than the pipe buffer
        // (64 KiB) from blocking forever on a full pipe.
        //
        // A readability handler must NOT be used here: tearing one down does not
        // wait for an already-dispatched block, so a chunk read by that block can
        // land in the buffer after the snapshot below has been taken and be lost.
        let drained = DispatchGroup()
        for (handle, buffer) in [
            (outputPipe.fileHandleForReading, outputBuffer),
            (errorPipe.fileHandleForReading, errorBuffer)
        ] {
            DispatchQueue.global(qos: .userInitiated).async(group: drained) {
                buffer.append(handle.readDataToEndOfFile())
            }
        }

        let waitResult = completion.wait(timeout: .now() + .seconds(30))
        if waitResult == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + .seconds(2))
        }

        // The child is gone, so both readers observe EOF and finish. Joining them
        // before snapshotting is what makes the capture deterministic: every
        // append happens-before the reads below.
        let drainResult = drained.wait(timeout: .now() + .seconds(10))

        let output = String(data: outputBuffer.snapshot(), encoding: .utf8) ?? ""
        var error = String(data: errorBuffer.snapshot(), encoding: .utf8) ?? ""
        if drainResult == .timedOut {
            error += "\nPipe drain did not complete within 10s; output may be truncated"
        }
        if waitResult == .timedOut {
            return (124, output, error + "\nProcess timed out after 30s")
        }

        return (process.terminationStatus, output, error)
    }
    
    // MARK: - Test Database Setup
    
    private func createTestDatabase() throws -> URL {
        let dbPath = tempDir.appendingPathComponent("test.blazedb")
        let db = try BlazeDBClient(name: "TestDB", fileURL: dbPath, password: testPassword)
        
        // Insert test data
        for i in 1...10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("Record \(i)"),
                "value": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        try db.close()
        return dbPath
    }
    
    // MARK: - BlazeDoctor Tests
    
    func testBlazeDoctor_HappyPath() throws {
        let dbPath = try createTestDatabase()
        
        let (exitCode, output, error) = runCommand("BlazeDoctor", arguments: [dbPath.path])
        
        XCTAssertEqual(exitCode, 0, "BlazeDoctor should exit with code 0. Error: \(error)")
        XCTAssertTrue(output.contains("Health") || output.contains("OK") || output.contains("healthy"), 
                     "Output should contain health information. Output: \(output)")
    }
    
    func testBlazeDoctor_InvalidPath() {
        let invalidPath = tempDir.appendingPathComponent("nonexistent.blazedb").path
        
        let (exitCode, _, _) = runCommand("BlazeDoctor", arguments: [invalidPath])
        
        XCTAssertNotEqual(exitCode, 0, "BlazeDoctor should fail for invalid path")
    }
    
    // MARK: - BlazeInfo Tests
    
    func testBlazeInfo_HappyPath() throws {
        let dbPath = try createTestDatabase()
        
        let (exitCode, output, error) = runCommand("BlazeInfo", arguments: [dbPath.path])
        
        XCTAssertEqual(exitCode, 0, "BlazeInfo should exit with code 0. Error: \(error)")
        XCTAssertTrue(output.contains("Database") || output.contains("Path") || output.contains("Size"),
                     "Output should contain database info. Output: \(output)")
    }
    
    // MARK: - BlazeDump Tests
    
    func testBlazeDump_DumpAndVerify() throws {
        let dbPath = try createTestDatabase()
        let dumpPath = tempDir.appendingPathComponent("test.dump")
        
        // Dump
        let (dumpExitCode, _, dumpError) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        
        XCTAssertEqual(dumpExitCode, 0, "BlazeDump dump should exit with code 0. Error: \(dumpError)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dumpPath.path), "Dump file should exist")
        
        // Verify
        let (verifyExitCode, verifyOutput, verifyError) = runCommand("BlazeDump", arguments: ["verify", dumpPath.path])
        
        XCTAssertEqual(verifyExitCode, 0, "BlazeDump verify should exit with code 0. Error: \(verifyError)")
        XCTAssertTrue(verifyOutput.contains("verified") || verifyOutput.contains("valid") || verifyOutput.contains("OK"),
                     "Verify output should indicate success. Output: \(verifyOutput)")
    }
    
    func testBlazeDump_Restore() throws {
        let dbPath = try createTestDatabase()
        let dumpPath = tempDir.appendingPathComponent("test.dump")
        let restoredPath = tempDir.appendingPathComponent("restored.blazedb")
        
        // Dump
        let (dumpExitCode, _, _) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        XCTAssertEqual(dumpExitCode, 0, "Dump should succeed")
        
        // Restore
        let (restoreExitCode, _, restoreError) = runCommand("BlazeDump", arguments: ["restore", dumpPath.path, restoredPath.path])
        
        XCTAssertEqual(restoreExitCode, 0, "BlazeDump restore should exit with code 0. Error: \(restoreError)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPath.path), "Restored database should exist")
        
        // Verify restored database
        let restoredDB = try BlazeDBClient(name: "Restored", fileURL: restoredPath, password: testPassword)
        let records = try restoredDB.fetchAll()
        XCTAssertEqual(records.count, 10, "Restored database should have 10 records")
        try restoredDB.close()
    }
    
    func testBlazeDump_VerifyCorruptedDump() throws {
        let dbPath = try createTestDatabase()
        let dumpPath = tempDir.appendingPathComponent("corrupted.dump")
        
        // Create dump
        let (dumpExitCode, _, _) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        XCTAssertEqual(dumpExitCode, 0, "Dump should succeed")
        
        // Corrupt the dump file
        var dumpData = try Data(contentsOf: dumpPath)
        if dumpData.count > 10 {
            // Flip some bytes
            dumpData[5] ^= 0xFF
            try dumpData.write(to: dumpPath)
        }
        
        // Verify should fail
        let (verifyExitCode, _, _) = runCommand("BlazeDump", arguments: ["verify", dumpPath.path])
        
        XCTAssertNotEqual(verifyExitCode, 0, "BlazeDump verify should fail for corrupted dump")
    }
    
    // MARK: - CLI password source (#310/#313)

    func testBlazeInfo_PrefersBLAZEDBPasswordOverArgv() throws {
        let dbPath = try createTestDatabase()
        let wrongArgvPassword = "wrong-argv-password-should-be-ignored"

        let (exitCode, output, error) = runCommand(
            "BlazeInfo",
            arguments: [dbPath.path, wrongArgvPassword],
            environment: cliEnvironment()
        )

        XCTAssertEqual(exitCode, 0, "BLAZEDB_PASSWORD must unlock the DB. Error: \(error)")
        XCTAssertTrue(output.contains("Records:"), "Expected successful info output. Output: \(output)")
        XCTAssertTrue(error.contains("password argument ignored"), "Expected env-over-argv warning. stderr: \(error)")
        XCTAssertFalse(error.contains(wrongArgvPassword), "stderr must not echo argv password")
    }

    func testBlazeInfo_WarnsWhenPasswordPassedOnArgv() throws {
        let dbPath = try createTestDatabase()
        var env = cliEnvironment()
        env.removeValue(forKey: "BLAZEDB_PASSWORD")

        let (exitCode, _, error) = runCommand(
            "BlazeInfo",
            arguments: [dbPath.path, testPassword],
            environment: env
        )

        XCTAssertEqual(exitCode, 0, "argv password should still work for compatibility. stderr: \(error)")
        XCTAssertTrue(error.contains("BLAZEDB_PASSWORD"), "Expected argv deprecation warning. stderr: \(error)")
        XCTAssertFalse(error.contains(testPassword), "stderr must not echo the password")
    }

    // MARK: - Capture harness regression

    /// Regression guard for the `runProcess` capture race.
    ///
    /// Every CLI assertion in this file trusts that `runProcess` returns everything
    /// the child wrote. A child that writes its output and exits immediately —
    /// which is exactly what `BlazeInfo` does, printing its report and then calling
    /// `exit(0)` — leaves the last bytes in flight at the moment the process dies.
    /// If the capture snapshots its buffers before the pipe readers have finished
    /// draining, that tail is silently dropped and the caller sees empty or
    /// truncated output alongside a successful exit code.
    ///
    /// The payload is deliberately larger than the 64 KiB pipe buffer so a
    /// capture that only reads once, or that reads without draining concurrently,
    /// truncates or deadlocks rather than passing by luck.
    func testRunProcess_CapturesCompleteOutputWhenChildExitsImmediatelyAfterWriting() throws {
        let payload = String(repeating: "B", count: 256 * 1024)
        let payloadFile = tempDir.appendingPathComponent("capture_payload.txt")
        try payload.write(to: payloadFile, atomically: true, encoding: .utf8)
        let marker = "STDERR-MARKER"

        // The race is by nature probabilistic; iterate so a regression cannot
        // slip through on a single lucky scheduling outcome.
        for iteration in 1...200 {
            let (exitCode, output, error) = runShell(
                "printf '%s' '\(marker)' >&2; sleep 0.01; cat '\(payloadFile.path)'; exit 0"
            )

            XCTAssertEqual(exitCode, 0, "iteration \(iteration): child should exit cleanly")
            XCTAssertEqual(
                output.count,
                payload.count,
                "iteration \(iteration): stdout truncated — captured \(output.count) of \(payload.count) bytes"
            )
            XCTAssertEqual(error, marker, "iteration \(iteration): stderr not captured verbatim")
        }
    }

    /// Runs a shell script through the same `runProcess` capture path the CLI
    /// assertions use, so the harness itself can be exercised without depending
    /// on a built BlazeDB executable.
    private func runShell(_ script: String) -> (exitCode: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = ProcessInfo.processInfo.environment
        return runProcess(process)
    }

    // MARK: - Integration Test
    
    func testCLI_EndToEnd() throws {
        // Create database
        let dbPath = try createTestDatabase()
        
        // Run doctor
        let (doctorExitCode, _, _) = runCommand("BlazeDoctor", arguments: [dbPath.path])
        XCTAssertEqual(doctorExitCode, 0, "Doctor should pass")
        
        // Run info
        let (infoExitCode, _, _) = runCommand("BlazeInfo", arguments: [dbPath.path])
        XCTAssertEqual(infoExitCode, 0, "Info should pass")
        
        // Dump and restore
        let dumpPath = tempDir.appendingPathComponent("e2e.dump")
        let restoredPath = tempDir.appendingPathComponent("e2e_restored.blazedb")
        
        let (dumpExitCode, _, _) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        XCTAssertEqual(dumpExitCode, 0, "Dump should succeed")
        
        let (verifyExitCode, _, _) = runCommand("BlazeDump", arguments: ["verify", dumpPath.path])
        XCTAssertEqual(verifyExitCode, 0, "Verify should succeed")
        
        let (restoreExitCode, _, _) = runCommand("BlazeDump", arguments: ["restore", dumpPath.path, restoredPath.path])
        XCTAssertEqual(restoreExitCode, 0, "Restore should succeed")
        
        // Verify restored database works
        let restoredDB = try BlazeDBClient(name: "E2E", fileURL: restoredPath, password: testPassword)
        let records = try restoredDB.fetchAll()
        XCTAssertEqual(records.count, 10, "Restored database should have correct record count")
        try restoredDB.close()
    }
}
