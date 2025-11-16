import Foundation
import BlazeDB

// MARK: - AshPile Bug Tracker Example

/// This example shows how AshPile would use BlazeDB with RLS for multi-tenant bug tracking
func ashPileExample() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ashpile.blazedb")
    
    let db = try BlazeDBClient(
        name: "ashpile",
        fileURL: fileURL,
        password: "ashpile-password"
    )
    
    // MARK: - Setup Teams
    
    let teamEngineering = UUID()
    let teamDesign = UUID()
    let teamMarketing = UUID()
    
    // MARK: - Setup Users
    
    let userAlice = UUID()
    let userBob = UUID()
    let userCharlie = UUID()
    
    // Alice: Engineering + Design
    let aliceContext = SecurityContext(
        userID: userAlice,
        teamIDs: [teamEngineering, teamDesign],
        roles: ["member", "team_lead"]
    )
    
    // Bob: Engineering only, Admin
    let bobContext = SecurityContext(
        userID: userBob,
        teamIDs: [teamEngineering],
        roles: ["admin"]
    )
    
    // Charlie: Marketing only
    let charlieContext = SecurityContext(
        userID: userCharlie,
        teamIDs: [teamMarketing],
        roles: ["member"]
    )
    
    // MARK: - Insert Test Data
    
    // Engineering bugs
    let bug1 = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("Login broken"),
        "team_id": .uuid(teamEngineering),
        "created_by": .uuid(userAlice),
        "status": .string("open"),
        "priority": .int(1)
    ])
    
    let bug2 = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("Slow query"),
        "team_id": .uuid(teamEngineering),
        "created_by": .uuid(userBob),
        "status": .string("in_progress"),
        "priority": .int(2)
    ])
    
    // Design bug
    let bug3 = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("Button color wrong"),
        "team_id": .uuid(teamDesign),
        "created_by": .uuid(userAlice),
        "status": .string("open"),
        "priority": .int(3)
    ])
    
    // Marketing bug
    let bug4 = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("Typo in email"),
        "team_id": .uuid(teamMarketing),
        "created_by": .uuid(userCharlie),
        "status": .string("open"),
        "priority": .int(4)
    ])
    
    // Roadmap items (can be shared across teams)
    let roadmap1 = BlazeDataRecord([
        "type": .string("roadmap"),
        "title": .string("Q1 2025 Goals"),
        "owner_id": .uuid(userAlice),
        "shared_with": .array([.uuid(teamEngineering), .uuid(teamDesign)]),
        "status": .string("active")
    ])
    
    _ = try db.insert(bug1)
    _ = try db.insert(bug2)
    _ = try db.insert(bug3)
    _ = try db.insert(bug4)
    _ = try db.insert(roadmap1)
    
    print("✅ Inserted test data (4 bugs, 1 roadmap)")
    
    // MARK: - Setup RLS Policies
    
    func setupRLS() {
        db.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { record, context in
            let type = record.storage["type"]?.stringValue
            
            switch type {
            case "bug":
                // Check team membership
                guard let teamID = record.storage["team_id"]?.uuidValue else {
                    return false
                }
                return context.teamIDs.contains(teamID)
                
            case "roadmap":
                // Check ownership OR shared teams
                let ownerID = record.storage["owner_id"]?.uuidValue
                if ownerID == context.userID {
                    return true
                }
                
                let sharedWith = record.storage["shared_with"]?.arrayValue?.compactMap {
                    $0.uuidValue
                } ?? []
                
                return !Set(sharedWith).isDisjoint(with: Set(context.teamIDs))
                
            default:
                return false
            }
        })
        
        db.addPolicy(SecurityPolicy(
            name: "admin_bypass",
            operation: .select,
            type: .permissive
        ) { _, context in
            return context.hasRole("admin")
        })
    }
    
    // MARK: - Test Queries
    
    print("\n--- Alice (Engineering + Design, Team Lead) ---")
    db.setSecurityContext(aliceContext)
    setupRLS()
    
    let aliceBugs = try db.fetchAll()
    print("Alice sees \(aliceBugs.count) items") // Should see: bug1, bug2, bug3, roadmap1
    
    let aliceBugTitles = aliceBugs.compactMap { $0.storage["title"]?.stringValue }
    print("Titles: \(aliceBugTitles)")
    
    print("\n--- Bob (Engineering only, Admin) ---")
    db.setSecurityContext(bobContext)
    setupRLS()
    
    let bobBugs = try db.fetchAll()
    print("Bob sees \(bobBugs.count) items") // Should see: ALL (admin bypass)
    
    print("\n--- Charlie (Marketing only, Member) ---")
    db.setSecurityContext(charlieContext)
    setupRLS()
    
    let charlieBugs = try db.fetchAll()
    print("Charlie sees \(charlieBugs.count) items") // Should see: bug4 only
    
    let charlieBugTitles = charlieBugs.compactMap { $0.storage["title"]?.stringValue }
    print("Titles: \(charlieBugTitles)")
    
    // MARK: - Test Insert Policy
    
    print("\n--- Testing Insert Policy ---")
    
    db.addPolicy(SecurityPolicy(
        name: "create_in_own_teams",
        operation: .insert,
        type: .restrictive
    ) { record, context in
        guard let teamID = record.storage["team_id"]?.uuidValue else {
            return false
        }
        return context.teamIDs.contains(teamID) || context.hasRole("admin")
    })
    
    // Alice tries to create bug in Engineering (success)
    db.setSecurityContext(aliceContext)
    let newBug = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("New bug"),
        "team_id": .uuid(teamEngineering)
    ])
    
    do {
        _ = try db.insert(newBug)
        print("✅ Alice created bug in Engineering (her team)")
    } catch {
        print("❌ Failed: \(error)")
    }
    
    // Alice tries to create bug in Marketing (fail)
    let marketingBug = BlazeDataRecord([
        "type": .string("bug"),
        "title": .string("Marketing bug"),
        "team_id": .uuid(teamMarketing)
    ])
    
    do {
        _ = try db.insert(marketingBug)
        print("❌ Alice created bug in Marketing (should fail!)")
    } catch {
        print("✅ Blocked: Alice can't create bugs in Marketing")
    }
    
    // Bob (admin) tries to create bug in Marketing (success)
    db.setSecurityContext(bobContext)
    do {
        _ = try db.insert(marketingBug)
        print("✅ Bob (admin) created bug in Marketing")
    } catch {
        print("❌ Failed: \(error)")
    }
    
    // MARK: - Clean up
    try? FileManager.default.removeItem(at: fileURL)
}

// Run the example
// try? ashPileExample()

