import Foundation
import BlazeDBCore

// MARK: - Basic Example

@main
struct BasicExample {
    static func main() async throws {
        print("🔥 BlazeDB Basic Example\n")
        
        // Create or open a database
        let db = try BlazeDBClient(
            name: "BasicExample",
            password: "example-password-123"
        )
        
        print("✅ Database opened: \(db.name)")
        
        // Insert a record
        let record = BlazeDataRecord([
            "title": .string("Hello, BlazeDB!"),
            "count": .int(42),
            "active": .bool(true),
            "createdAt": .date(Date())
        ])
        
        let id = try await db.insert(record)
        print("✅ Inserted record with ID: \(id.uuidString.prefix(8))")
        
        // Query records
        let results = try await db.query()
            .where("active", equals: .bool(true))
            .orderBy("count", descending: true)
            .limit(10)
            .execute()
            .records
        
        print("✅ Found \(results.count) active record(s)")
        
        // Update a record
        var updated = record.storage
        updated["count"] = .int(100)
        try db.update(id: id, with: BlazeDataRecord(updated))
        print("✅ Updated record")
        
        // Fetch the updated record
        if let fetched = try await db.fetch(id: id) {
            print("✅ Fetched record: count = \(fetched.storage["count"]?.intValue ?? 0)")
        }
        
        // Delete the record
        try await db.delete(id: id)
        print("✅ Deleted record")
        
        // Verify deletion
        let deleted = try await db.fetch(id: id)
        print("✅ Record after deletion: \(deleted == nil ? "nil (deleted)" : "still exists")")
        
        print("\n🎉 Example completed successfully!")
    }
}

