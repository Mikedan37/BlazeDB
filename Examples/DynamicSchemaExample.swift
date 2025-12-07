import Foundation
import BlazeDB

// MARK: - Dynamic Schema Example

/// This example demonstrates how BlazeDB handles different document types in the same collection
func dynamicSchemaExample() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mixed.blazedb")
    
    let db = try BlazeDBClient(
        name: "mixed",
        fileURL: fileURL,
        password: "password"
    )
    
    // 1. Insert different document types
    
    // Bug document
    let bug = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("Login broken"),
        "team_id": .uuid(UUID()),
        "status": .string("open"),
        "priority": .int(1)
    ])
    
    // Feature document (different schema)
    let feature = BlazeDataRecord([
        "type": .string("feature"),
        "title": .string("Dark mode"),
        "team_id": .uuid(UUID()),
        "estimated_hours": .int(40),
        "tags": .array([.string("ui"), .string("accessibility")])
    ])
    
    // Comment document (different schema)
    let comment = BlazeDataRecord([
        "type": .string("comment"),
        "text": .string("This is urgent!"),
        "author_id": .uuid(UUID()),
        "parent_id": .uuid(UUID()),
        "created_at": .date(Date())
    ])
    
    // User document (different schema)
    let user = BlazeDataRecord([
        "type": .string("user"),
        "name": .string("Alice"),
        "email": .string("alice@example.com"),
        "teams": .array([.uuid(UUID()), .uuid(UUID())])
    ])
    
    _ = try db.insert(bug)
    _ = try db.insert(feature)
    _ = try db.insert(comment)
    _ = try db.insert(user)
    
    print("✅ Inserted 4 different document types")
    
    // 2. Query all documents
    let allDocs = try db.fetchAll()
    print("Total documents: \(allDocs.count)")
    
    // 3. Filter by type in application code
    let bugs = allDocs.filter { $0.storage["type"]?.stringValue == "bug" }
    let features = allDocs.filter { $0.storage["type"]?.stringValue == "feature" }
    let comments = allDocs.filter { $0.storage["type"]?.stringValue == "comment" }
    let users = allDocs.filter { $0.storage["type"]?.stringValue == "user" }
    
    print("Bugs: \(bugs.count)")
    print("Features: \(features.count)")
    print("Comments: \(comments.count)")
    print("Users: \(users.count)")
    
    // 4. RLS policy that handles different schemas
    db.setSecurityContext(SecurityContext(
        userID: UUID(),
        teamIDs: [UUID()],
        roles: ["member"]
    ))
    
    db.addPolicy(SecurityPolicy(
        name: "mixed_access",
        operation: .select,
        type: .restrictive
    ) { record, context in
        let type = record.storage["type"]?.stringValue
        
        switch type {
        case "bug", "feature":
            // Check team_id field
            guard let teamID = record.storage["team_id"]?.uuidValue else {
                return false
            }
            return context.teamIDs.contains(teamID)
            
        case "comment":
            // Check author_id field
            guard let authorID = record.storage["author_id"]?.uuidValue else {
                return false
            }
            return authorID == context.userID
            
        case "user":
            // Check if it's the current user's profile
            guard let userID = record.storage["id"]?.uuidValue else {
                return false
            }
            return userID == context.userID
            
        default:
            return false
        }
    })
    
    let filteredDocs = try db.fetchAll()
    print("✅ RLS filtered documents: \(filteredDocs.count)")
    
    // 5. Clean up
    try? FileManager.default.removeItem(at: fileURL)
}

// Run the example
// try? dynamicSchemaExample()

