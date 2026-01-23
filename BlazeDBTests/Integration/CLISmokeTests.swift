//
//  CLISmokeTests.swift
//  BlazeDBTests
//
//  Automated CLI smoke tests for BlazeDB command-line tools
//  Created to verify CLI tools work correctly without manual testing
//

import XCTest
import Foundation
@testable import BlazeDBCore

final class CLISmokeTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeDB_CLISmoke_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func runCommand(_ executable: String, arguments: [String] = []) -> (exitCode: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        
        // Find the built executable
        let buildDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
        
        let executablePath = buildDir.appendingPathComponent(executable).path
        
        // Fallback: try release build
        let releasePath = buildDir.deletingLastPathComponent()
            .appendingPathComponent("release")
            .appendingPathComponent(executable).path
        
        let finalPath: String
        if FileManager.default.fileExists(atPath: executablePath) {
            finalPath = executablePath
        } else if FileManager.default.fileExists(atPath: releasePath) {
            finalPath = releasePath
        } else {
            // Try swift run as fallback
            process.arguments = ["swift", "run", executable] + arguments
            return runProcess(process)
        }
        
        process.executableURL = URL(fileURLWithPath: finalPath)
        process.arguments = arguments
        return runProcess(process)
    }
    
    private func runProcess(_ process: Process) -> (exitCode: Int32, output: String, error: String) {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            return (process.terminationStatus, output, error)
        } catch {
            return (1, "", "Failed to run process: \(error)")
        }
    }
    
    // MARK: - Test Database Setup
    
    private func createTestDatabase() throws -> URL {
        let dbPath = tempDir.appendingPathComponent("test.blazedb")
        let db = try BlazeDBClient(name: "TestDB", fileURL: dbPath, password: "test123")
        
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
        let dumpPath = tempDir.appendingPathComponent("test.dump")
        let restoredPath = tempDir.appendingPathComponent("restored.blazedb")
        
        // Dump
        let (dumpExitCode, _, _) = runCommand("BlazeDump", arguments: ["dump", dbPath.path, dumpPath.path])
        XCTAssertEqual(dumpExitCode, 0, "Dump should succeed")
        
        // Restore
        let (restoreExitCode, restoreOutput, restoreError) = runCommand("BlazeDump", arguments: ["restore", dumpPath.path, restoredPath.path])
        
        XCTAssertEqual(restoreExitCode, 0, "BlazeDump restore should exit with code 0. Error: \(restoreError)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPath.path), "Restored database should exist")
        
        // Verify restored database
        let restoredDB = try BlazeDBClient(name: "Restored", fileURL: restoredPath, password: "test123")
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
        let restoredDB = try BlazeDBClient(name: "E2E", fileURL: restoredPath, password: "test123")
        let records = try restoredDB.fetchAll()
        XCTAssertEqual(records.count, 10, "Restored database should have correct record count")
        try restoredDB.close()
    }
}
