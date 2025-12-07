import Foundation
import BlazeDB

// MARK: - Basic Usage Example

/// This example demonstrates the most common BlazeDB operations
func basicUsageExample() throws {
    // 1. Create a database (super simple - just a name!)
    let db = try BlazeDBClient(name: "example", password: "my-secure-password")
    // Database automatically stored in: ~/Library/Application Support/BlazeDB/example.blazedb
    
    // 2. Insert a record
    let user = BlazeDataRecord([
        "name": .string("Alice"),
        "email": .string("alice@example.com"),
        "age": .int(30),
        "created_at": .date(Date())
    ])
    
    let userID = try db.insert(user)
    print("✅ Inserted user with ID: \(userID)")
    
    // 3. Fetch a record
    if let fetchedUser = try db.fetch(id: userID) {
        print("✅ Fetched user: \(fetchedUser.storage["name"]?.stringValue ?? "Unknown")")
    }
    
    // 4. Update a record
    var updatedUser = user
    updatedUser.storage["age"] = .int(31)
    try db.update(id: userID, with: updatedUser)
    print("✅ Updated user age")
    
    // 5. Fetch all records
    let allUsers = try db.fetchAll()
    print("✅ Total users: \(allUsers.count)")
    
    // 6. Delete a record
    try db.delete(id: userID)
    print("✅ Deleted user")
    
    // 7. Discover databases
    let databases = try BlazeDBClient.discoverDatabases()
    print("✅ Found \(databases.count) databases in default location")
}

// Run the example
// try? basicUsageExample()

