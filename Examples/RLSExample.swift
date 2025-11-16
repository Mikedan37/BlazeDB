import Foundation
import BlazeDB

// MARK: - Row-Level Security Example

/// This example demonstrates how to use RLS for multi-tenant applications
func rlsExample() throws {
    // 1. Setup database
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("bugs.blazedb")
    
    let db = try BlazeDBClient(
        name: "bugs",
        fileURL: fileURL,
        password: "secure-password"
    )
    
    // 2. Insert bugs from different teams
    let bugTeamA = BlazeDataRecord([
        "title": .string("Login broken"),
        "team_id": .uuid(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
        "status": .string("open")
    ])
    
    let bugTeamB = BlazeDataRecord([
        "title": .string("Slow query"),
        "team_id": .uuid(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
        "status": .string("open")
    ])
    
    _ = try db.insert(bugTeamA)
    _ = try db.insert(bugTeamB)
    
    print("✅ Inserted bugs from Team A and Team B")
    
    // 3. Query without RLS (sees all bugs)
    let allBugs = try db.fetchAll()
    print("Without RLS: \(allBugs.count) bugs") // Shows 2 bugs
    
    // 4. Enable RLS for Team A user
    let teamA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let userAlice = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    
    db.setSecurityContext(SecurityContext(
        userID: userAlice,
        teamIDs: [teamA],
        roles: ["member"]
    ))
    
    // Add team access policy
    db.addPolicy(SecurityPolicy(
        name: "team_access",
        operation: .select,
        type: .restrictive
    ) { record, context in
        guard let teamID = record.storage["team_id"]?.uuidValue else {
            return false
        }
        return context.teamIDs.contains(teamID)
    })
    
    // 5. Query with RLS (only sees Team A bugs)
    let teamABugs = try db.fetchAll()
    print("With RLS (Team A): \(teamABugs.count) bugs") // Shows 1 bug
    
    // 6. Try as admin (sees all)
    db.setSecurityContext(SecurityContext(
        userID: userAlice,
        teamIDs: [teamA],
        roles: ["admin"]
    ))
    
    db.addPolicy(SecurityPolicy(
        name: "admin_bypass",
        operation: .select,
        type: .permissive
    ) { _, context in
        return context.hasRole("admin")
    })
    
    let adminBugs = try db.fetchAll()
    print("With RLS (Admin): \(adminBugs.count) bugs") // Shows 2 bugs
    
    // 7. Clean up
    try? FileManager.default.removeItem(at: fileURL)
}

// Run the example
// try? rlsExample()

