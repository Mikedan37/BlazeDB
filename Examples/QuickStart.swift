//
//  QuickStart.swift
//  BlazeDB Examples
//
//  Quick start guide showing basic BlazeDB usage
//
//  Created: 2025-11-13
//

import Foundation
import BlazeDB

/// Quick start example
func quickStartExample() throws {
    print("🔥 BlazeDB Quick Start Example\n")
    
    // 1. Create database (super simple - just a name!)
    let db = try BlazeDBClient(name: "QuickStart", password: "secure-password-123")
    // Database automatically stored in: ~/Library/Application Support/BlazeDB/QuickStart.blazedb
    
    print("✅ Database created\n")
    
    // 2. Insert a record
    let userID = try db.insert(BlazeDataRecord([
        "name": .string("Alice"),
        "age": .int(30),
        "email": .string("alice@example.com"),
        "active": .bool(true)
    ]))
    
    print("✅ Inserted user: \(userID)\n")
    
    // 3. Fetch the record
    if let user = try db.fetch(id: userID) {
        print("📖 Fetched user:")
        print("   Name: \(user["name"]?.stringValue ?? "unknown")")
        print("   Age: \(user["age"]?.intValue ?? 0)")
        print("")
    }
    
    // 4. Update the record
    try db.update(id: userID, with: BlazeDataRecord([
        "age": .int(31),
        "lastLogin": .date(Date())
    ]))
    
    print("✅ Updated user\n")
    
    // 5. Query records
    // Insert more users first
    try db.insert(BlazeDataRecord([
        "name": .string("Bob"),
        "age": .int(25),
        "active": .bool(true)
    ]))
    
    try db.insert(BlazeDataRecord([
        "name": .string("Charlie"),
        "age": .int(35),
        "active": .bool(false)
    ]))
    
    let activeUsers = try db.query()
        .where("active", equals: .bool(true))
        .where("age", greaterThan: .int(20))
        .execute()
    
    print("📊 Found \(activeUsers.count) active users over 20\n")
    
    // 6. Aggregation
    let stats = try db.query()
        .where("active", equals: .bool(true))
        .sum("age", as: "totalAge")
        .count(as: "userCount")
        .executeAggregation()
    
    if let avgAge = stats.sum("totalAge"), let count = stats.count("userCount") {
        print("📈 Average age: \(avgAge / Double(count))\n")
    }
    
    // 7. Delete a record
    try db.delete(id: userID)
    print("✅ Deleted user\n")
    
    // 8. Persist to disk
    try db.persist()
    print("💾 Database persisted to disk\n")
    
    // 9. MVCC: Enable concurrent access (optional)
    db.setMVCCEnabled(true)
    print("🚀 MVCC enabled (20-100x faster concurrent reads!)\n")
    
    // 10. Discover databases
    let databases = try BlazeDBClient.discoverDatabases()
    print("📦 Found \(databases.count) databases in default location\n")
    
    print("✅ Example complete!")
}

// Run the example
do {
    try quickStartExample()
} catch {
    print("❌ Error: \(error)")
}

