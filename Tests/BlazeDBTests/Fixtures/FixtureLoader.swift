//
//  FixtureLoader.swift
//  BlazeDBTests
//
//  Utility for loading and validating BlazeBinary fixtures
//
//  Created by Auto on 1/XX/25.
//

import Foundation
@testable import BlazeDB

/// Utility for loading and validating BlazeBinary fixtures
enum FixtureLoader {
    
    /// Load a fixture file from the fixtures directory
    static func loadFixture(name: String, version: String = "v1") throws -> Data {
        // UPDATED: Use FixtureValidationTests as bundle reference after reorganization
        let bundle = Bundle(for: FixtureValidationTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "bin", subdirectory: "Fixtures/BlazeBinary/\(version)") else {
            throw FixtureError.fileNotFound(name)
        }
        return try Data(contentsOf: url)
    }
    
    /// Validate that a fixture decodes identically with both codecs
    static func validateFixture(name: String, version: String = "v1") throws {
        let data = try loadFixture(name: name, version: version)
        
        // Decode with both codecs
        let stdDecoded = try BlazeBinaryDecoder.decode(data)
        let armDecoded = try BlazeBinaryDecoder.decodeARM(data)
        
        // Verify identical results
        assertRecordsEqual(stdDecoded, armDecoded)
    }
    
    /// Create a fixture file from a record
    static func createFixture(record: BlazeDataRecord, name: String, version: String = "v1") throws {
        // UPDATED: Use ARM codec (both produce identical output)
        let encoded = try BlazeBinaryEncoder.encodeARM(record)
        
        // Create fixtures directory if needed
        // UPDATED: Use FixtureValidationTests as bundle reference after reorganization
        let bundle = Bundle(for: FixtureValidationTests.self)
        let fixturesDir = bundle.bundleURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("BlazeBinary")
            .appendingPathComponent(version)
        
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        
        // Write fixture
        let fixtureURL = fixturesDir.appendingPathComponent("\(name).bin")
        try encoded.write(to: fixtureURL)
    }
    
    /// Validate all fixtures in a directory
    static func validateAllFixtures(version: String = "v1") throws {
        // UPDATED: Use FixtureValidationTests as bundle reference after reorganization
        let bundle = Bundle(for: FixtureValidationTests.self)
        guard let fixturesDir = bundle.url(forResource: nil, withExtension: nil, subdirectory: "Fixtures/BlazeBinary/\(version)") else {
            return // No fixtures directory
        }
        
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
        
        for file in files where file.pathExtension == "bin" {
            let data = try Data(contentsOf: file)
            
            // Decode with both codecs
            let stdDecoded = try BlazeBinaryDecoder.decode(data)
            let armDecoded = try BlazeBinaryDecoder.decodeARM(data)
            
            // Verify identical results
            assertRecordsEqual(stdDecoded, armDecoded)
        }
    }
}

enum FixtureError: Error {
    case fileNotFound(String)
}

