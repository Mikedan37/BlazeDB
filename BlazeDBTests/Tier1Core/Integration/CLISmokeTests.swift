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
    private var tempDir: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeDB_CLISmoke_\(UUID().uuidString)")
        tempDir = dir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let requiredExecutables = ["BlazeDoctor", "BlazeInfo", "BlazeDump"]
        let missing = requiredExecutables.filter { resolveExecutablePath($0) == nil }
        if !missing.isEmpty {
            throw XCTSkip("Skipping CLI smoke tests; missing executables: \(missing.joined(separator: ", "))")
        }
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func resolveExecutablePath(_ executable: String) -> String? {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        
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
    
    private func runCommand(_ executable: String, arguments: [String] = []) -> (exitCode: Int32, output: String, error: String) {
        let process = Process()
        
        guard let finalPath = resolveExecutablePath(executable) else {
            return (127, "", "Executable '\(executable)' not found in .build outputs")
        }
        
        process.executableURL = URL(fileURLWithPath: finalPath)
        process.arguments = arguments
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
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputBuffer.append(chunk)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errorBuffer.append(chunk)
        }
        
        do {
            let completion = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                completion.signal()
            }
            try process.run()
            
            let waitResult = completion.wait(timeout: .now() + .seconds(30))
            if waitResult == .timedOut {
                process.terminate()
                _ = completion.wait(timeout: .now() + .seconds(2))
            }
            
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            
            let outputData = outputBuffer.snapshot()
            let errorData = errorBuffer.snapshot()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            if waitResult == .timedOut {
                return (124, output, error + "\nProcess timed out after 30s")
            }
            
            return (process.terminationStatus, output, error)
        } catch {
            return (1, "", "Failed to run process: \(error)")
        }
    }
    
    // MARK: - Test Database Setup
    
    private func createTestDatabase() throws -> URL {
        let dbPath = try requireFixture(tempDir).appendingPathComponent("test.blazedb")
        let db = try BlazeDBClient(name: "TestDB", fileURL: dbPath, password: "TestPass123!")
        
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
        let invalidPath = (try? requireFixture(tempDir).appendingPathComponent("nonexistent.blazedb").path) ?? "/nonexistent.blazedb"
        
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
        let dumpPath = try requireFixture(tempDir).appendingPathComponent("test.dump")
        
        // Dump
        let (dumpExitCode, dumpOutput, dumpError) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        
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
        let dumpPath = try requireFixture(tempDir).appendingPathComponent("test.dump")
        let restoredPath = try requireFixture(tempDir).appendingPathComponent("restored.blazedb")
        
        // Dump
        let (dumpExitCode, _, _) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        XCTAssertEqual(dumpExitCode, 0, "Dump should succeed")
        
        // Restore
        let (restoreExitCode, restoreOutput, restoreError) = runCommand("BlazeDump", arguments: ["restore", dumpPath.path, restoredPath.path])
        
        XCTAssertEqual(restoreExitCode, 0, "BlazeDump restore should exit with code 0. Error: \(restoreError)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPath.path), "Restored database should exist")
        
        // Verify restored database
        let restoredDB = try BlazeDBClient(name: "Restored", fileURL: restoredPath, password: "TestPass123!")
        let records = try restoredDB.fetchAll()
        XCTAssertEqual(records.count, 10, "Restored database should have 10 records")
        try restoredDB.close()
    }
    
    func testBlazeDump_VerifyCorruptedDump() throws {
        let dbPath = try createTestDatabase()
        let dumpPath = try requireFixture(tempDir).appendingPathComponent("corrupted.dump")
        
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
        let dumpPath = try requireFixture(tempDir).appendingPathComponent("e2e.dump")
        let restoredPath = try requireFixture(tempDir).appendingPathComponent("e2e_restored.blazedb")
        
        let (dumpExitCode, _, _) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        XCTAssertEqual(dumpExitCode, 0, "Dump should succeed")
        
        let (verifyExitCode, _, _) = runCommand("BlazeDump", arguments: ["verify", dumpPath.path])
        XCTAssertEqual(verifyExitCode, 0, "Verify should succeed")
        
        let (restoreExitCode, _, _) = runCommand("BlazeDump", arguments: ["restore", dumpPath.path, restoredPath.path])
        XCTAssertEqual(restoreExitCode, 0, "Restore should succeed")
        
        // Verify restored database works
        let restoredDB = try BlazeDBClient(name: "E2E", fileURL: restoredPath, password: "TestPass123!")
        let records = try restoredDB.fetchAll()
        XCTAssertEqual(records.count, 10, "Restored database should have correct record count")
        try restoredDB.close()
    }
}
