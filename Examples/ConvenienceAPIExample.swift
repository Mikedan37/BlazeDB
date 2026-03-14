//
//  ConvenienceAPIExample.swift
//  BlazeDB Examples
//
//  Example demonstrating the new convenience API
//  Just provide a name - no file paths needed!
//
//  Created: 2025-01-XX
//

import Foundation
import BlazeDB

/// Example demonstrating the convenience API
func convenienceAPIExample() throws {
    print("🔥 BlazeDB Convenience API Example\n")
    
    // MARK: - 1. Create Database by Name (Super Simple!)
    
    print("1. Creating database by name...")
    let db = try BlazeDBClient.open(named: "MyApp", password: "secure-password-123")
    print("✅ Database created at: \(db.fileURL.path)\n")
    
    // Database is automatically stored in:
    // ~/Library/Application Support/BlazeDB/MyApp.blazedb
    
    // MARK: - 2. Use Database
    
    print("2. Inserting data...")
    let id = try db.insert(BlazeDataRecord([
        "title": .string("Hello BlazeDB!"),
        "value": .int(42)
    ]))
    print("✅ Inserted record: \(id)\n")
    
    // MARK: - 3. Discover Databases
    
    print("3. Discovering databases...")
    let databases = try BlazeDBClient.discoverDatabases()
    print("📦 Found \(databases.count) databases:")
    for dbInfo in databases {
        print("   - \(dbInfo.name): \(dbInfo.recordCount) records, \(ByteCountFormatter.string(fromByteCount: dbInfo.fileSizeBytes, countStyle: .file))")
    }
    print()
    
    // MARK: - 4. Find Specific Database
    
    print("4. Finding specific database...")
    if let found = try BlazeDBClient.findDatabase(named: "MyApp") {
        print("✅ Found: \(found.name) at \(found.path)")
        print("   Records: \(found.recordCount)")
        print("   Size: \(ByteCountFormatter.string(fromByteCount: found.fileSizeBytes, countStyle: .file))")
    }
    print()
    
    // MARK: - 5. Check if Database Exists
    
    print("5. Checking if database exists...")
    if BlazeDBClient.databaseExists(named: "MyApp") {
        print("✅ Database 'MyApp' exists!")
    }
    if !BlazeDBClient.databaseExists(named: "NonExistent") {
        print("✅ Database 'NonExistent' does not exist (as expected)")
    }
    print()
    
    // MARK: - 6. Database Registry
    
    print("6. Using database registry...")
    
    // Register database for easy lookup
    BlazeDBClient.registerDatabase(name: "MyApp", client: db)
    print("✅ Registered database 'MyApp'")
    
    // Get registered database
    if let registered = BlazeDBClient.getRegisteredDatabase(named: "MyApp") {
        print("✅ Retrieved registered database: \(registered.name)")
    }
    
    // List all registered databases
    let registered = BlazeDBClient.registeredDatabases()
    print("📋 Registered databases: \(registered)")
    print()
    
    // MARK: - 7. Multiple Databases
    
    print("7. Creating multiple databases...")
    let userDB = try BlazeDBClient.open(named: "UserData", password: "password1")
    let cacheDB = try BlazeDBClient.open(named: "Cache", password: "password2")
    
    // Insert data in each
    _ = try userDB.insert(BlazeDataRecord(["type": .string("user")]))
    _ = try cacheDB.insert(BlazeDataRecord(["type": .string("cache")]))
    
    print("✅ Created UserData and Cache databases")
    print()
    
    // MARK: - 8. Server Discovery Example
    
    print("8. Server discovery example...")
    let allDatabases = try BlazeDBClient.discoverDatabases()
    print("📊 Server found \(allDatabases.count) databases:")
    
    for dbInfo in allDatabases {
        print("""
            Database: \(dbInfo.name)
              Path: \(dbInfo.path)
              Records: \(dbInfo.recordCount)
              Size: \(ByteCountFormatter.string(fromByteCount: dbInfo.fileSizeBytes, countStyle: .file))
              Created: \(dbInfo.createdAt?.formatted() ?? "unknown")
              Modified: \(dbInfo.lastModified?.formatted() ?? "unknown")
            """)
    }
    print()
    
    print("✅ Convenience API example complete!")
    print("\n💡 Tip: Databases are stored in ~/Library/Application Support/BlazeDB/")
    print("   This makes them easy to find for servers and tools!")
}

// Run the example
do {
    try convenienceAPIExample()
} catch {
    print("❌ Error: \(error)")
}

