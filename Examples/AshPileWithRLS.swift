//
//  AshPileWithRLS.swift
//  Complete example of AshPile bug tracker with RLS
//

import Foundation
import BlazeDB

// MARK: - Models

struct Bug {
    let id: UUID
    let title: String
    let description: String
    let status: String  // "open", "in_progress", "closed"
    let priority: String  // "low", "medium", "high", "critical"
    let teamId: UUID
    let createdBy: UUID
    let createdAt: Date
}

// MARK: - AshPile Database

class AshPileDB {
    let db: BlazeDBClient
    private(set) var currentUser: User?
    
    init() throws {
        // Create encrypted database
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ashpile.blazedb")
        
        db = try BlazeDBClient(
            name: "AshPile",
            fileURL: dbURL,
            password: "your-secure-password-here"  // ← AES-256 encryption!
        )
        
        // Enable RLS
        db.rls.enable()
        
        // Add policies
        db.rls.addPolicy(.userInTeam(teamIDField: "teamId"))
        db.rls.addPolicy(.adminFullAccess())
        db.rls.addPolicy(.viewerReadOnly())
        
        print("✅ AshPile initialized with RLS + Encryption")
    }
    
    // MARK: - Auth
    
    func signUp(name: String, email: String, teamName: String) throws -> User {
        // Create team
        let team = Team(name: teamName)
        let teamID = db.rls.createTeam(team)
        
        // Create user as team admin
        let user = User(
            name: name,
            email: email,
            roles: ["admin", "developer"],
            teamIDs: [teamID]
        )
        
        let userID = db.rls.createUser(user)
        db.rls.addUserToTeam(userID: userID, teamID: teamID, asAdmin: true)
        
        print("✅ User '\(name)' created with team '\(teamName)'")
        return user
    }
    
    func login(userID: UUID) throws {
        guard let user = db.rls.getUser(id: userID) else {
            throw NSError(domain: "AshPile", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not found"
            ])
        }
        
        // Set security context
        db.rls.setContext(user.toSecurityContext())
        currentUser = user
        
        print("✅ Logged in as '\(user.name)'")
    }
    
    func inviteToTeam(email: String, name: String, role: String = "developer") throws {
        guard let currentUser = currentUser else {
            throw NSError(domain: "AshPile", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Not logged in"
            ])
        }
        
        guard let teamID = currentUser.teamIDs.first else {
            throw NSError(domain: "AshPile", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "User has no team"
            ])
        }
        
        // Create invited user
        let invitedUser = User(
            name: name,
            email: email,
            roles: [role],
            teamIDs: [teamID]
        )
        
        let userID = db.rls.createUser(invitedUser)
        db.rls.addUserToTeam(userID: userID, teamID: teamID)
        
        print("✅ Invited '\(name)' (\(email)) to team as '\(role)'")
    }
    
    // MARK: - Bug Management
    
    func createBug(title: String, description: String, priority: String = "medium") throws -> UUID {
        guard let currentUser = currentUser else {
            throw NSError(domain: "AshPile", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Not logged in"
            ])
        }
        
        guard let teamID = currentUser.teamIDs.first else {
            throw NSError(domain: "AshPile", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "User has no team"
            ])
        }
        
        // Create bug record
        let bug = BlazeDataRecord([
            "title": .string(title),
            "description": .string(description),
            "status": .string("open"),
            "priority": .string(priority),
            "teamId": .uuid(teamID),
            "createdBy": .uuid(currentUser.id),
            "createdAt": .date(Date())
        ])
        
        let bugID = try db.insert(bug)
        
        // ✅ NO persist() needed! Auto-saved!
        
        print("✅ Bug created: '\(title)' (\(priority))")
        return bugID
    }
    
    func getBugs(status: String? = nil) throws -> [BlazeDataRecord] {
        // ✅ Automatically filtered to current user's team!
        
        if let status = status {
            return try db.query()
                .where("status", .equals, status)
                .sort(by: "createdAt", ascending: false)
                .execute()
                .asRecords() ?? []
        } else {
            return try db.fetchAll()
        }
    }
    
    func updateBugStatus(bugID: UUID, newStatus: String) throws {
        // ✅ Can only update if bug is in user's team
        // ✅ RLS prevents updating other teams' bugs!
        
        let updates = BlazeDataRecord([
            "status": .string(newStatus),
            "updatedAt": .date(Date())
        ])
        
        try db.update(id: bugID, with: updates)
        
        print("✅ Bug \(bugID) updated to '\(newStatus)'")
    }
    
    func deleteBug(bugID: UUID) throws {
        // ✅ Can only delete if bug is in user's team
        // ✅ RLS blocks deletion of other teams' bugs!
        
        try db.delete(id: bugID)
        
        print("✅ Bug \(bugID) deleted")
    }
    
    func searchBugs(query: String) throws -> [BlazeDataRecord] {
        // Enable search if not already
        try? db.collection.enableSmartSearch(on: ["title", "description"])
        
        // Search (automatically filtered by RLS!)
        let results = try db.collection.smartSearch(query: query, limit: 20)
        
        return results.map { $0.record }
    }
    
    // MARK: - Analytics
    
    func getTeamStats() throws -> [String: Any] {
        let allBugs = try db.fetchAll()
        
        let openBugs = allBugs.filter { $0.storage["status"]?.stringValue == "open" }.count
        let inProgressBugs = allBugs.filter { $0.storage["status"]?.stringValue == "in_progress" }.count
        let closedBugs = allBugs.filter { $0.storage["status"]?.stringValue == "closed" }.count
        
        let highPriority = allBugs.filter { $0.storage["priority"]?.stringValue == "high" }.count
        let criticalPriority = allBugs.filter { $0.storage["priority"]?.stringValue == "critical" }.count
        
        return [
            "total": allBugs.count,
            "open": openBugs,
            "inProgress": inProgressBugs,
            "closed": closedBugs,
            "highPriority": highPriority,
            "critical": criticalPriority
        ]
    }
}

// MARK: - Usage Example

func runAshPileExample() {
    print("\n🐛 AshPile with RLS - Complete Example\n")
    
    do {
        let ashpile = try AshPileDB()
        
        // 1. Sign up first user (creates team)
        print("--- Sign Up ---")
        let alice = try ashpile.signUp(
            name: "Alice",
            email: "alice@company.com",
            teamName: "Engineering"
        )
        
        // 2. Login as Alice
        print("\n--- Login ---")
        try ashpile.login(userID: alice.id)
        
        // 3. Create bugs
        print("\n--- Create Bugs ---")
        let bug1 = try ashpile.createBug(
            title: "App crashes on startup",
            description: "Users report app crashing immediately after launch",
            priority: "critical"
        )
        
        let bug2 = try ashpile.createBug(
            title: "Login button not responding",
            description: "Button doesn't respond to taps",
            priority: "high"
        )
        
        let bug3 = try ashpile.createBug(
            title: "Typo in settings page",
            description: "Settings says 'Prefernces' instead of 'Preferences'",
            priority: "low"
        )
        
        // 4. View team's bugs
        print("\n--- Team Bugs ---")
        let bugs = try ashpile.getBugs()
        print("Alice sees \(bugs.count) bugs (all team bugs)")
        
        // 5. Update bug
        print("\n--- Update Bug ---")
        try ashpile.updateBugStatus(bugID: bug1, newStatus: "in_progress")
        
        // 6. Invite teammate
        print("\n--- Invite Teammate ---")
        try ashpile.inviteToTeam(
            email: "bob@company.com",
            name: "Bob",
            role: "developer"
        )
        
        // 7. Search bugs
        print("\n--- Search ---")
        let searchResults = try ashpile.searchBugs(query: "crash")
        print("Found \(searchResults.count) bugs matching 'crash'")
        
        // 8. Team stats
        print("\n--- Team Stats ---")
        let stats = try ashpile.getTeamStats()
        print("Total bugs: \(stats["total"] ?? 0)")
        print("Open: \(stats["open"] ?? 0)")
        print("In Progress: \(stats["inProgress"] ?? 0)")
        print("Critical: \(stats["critical"] ?? 0)")
        
        // 9. Try to delete bug
        print("\n--- Delete Bug ---")
        try ashpile.deleteBug(bugID: bug3)
        
        print("\n✅ AshPile example complete!")
        
        // ✅ NO persist() calls anywhere!
        // ✅ Everything auto-saved!
        // ✅ RLS enforced automatically!
        
    } catch {
        print("❌ Error: \(error)")
    }
}

// Run example
// runAshPileExample()

