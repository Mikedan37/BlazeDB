//
//  RLSGraphQueryTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for RLS integration with GraphQuery
//  Tests role-based filtering, admin bypass, and graph query behavior
//

import XCTest
@testable import BlazeDB

final class RLSGraphQueryTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLSGraph-\(testID).blazedb")
        
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "rls_graph_test_\(testID)", fileURL: tempURL, password: "RLSGraphQueryTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? db?.persist()
        db = nil
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - No RLS Tests (Backward Compatibility)
    
    func testGraphQueryWithoutRLS_ReturnsAllResults() throws {
        // Insert test data
        let team1ID = UUID()
        let team2ID = UUID()
        
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(i < 3 ? team1ID : team2ID),
                "value": .int(i)
            ]))
        }
        
        // Query without RLS (no user context)
        let points = try db.graph()
            .x("team_id")
            .y(.count)
            .toPoints()
        
        // Should see all teams
        XCTAssertEqual(points.count, 2)
    }
    
    // MARK: - Admin Bypass Tests
    
    func testGraphQueryWithAdmin_BypassesRLS() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        let team2ID = UUID()
        
        // Add policy: users can only see their team's records
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert test data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(i < 3 ? team1ID : team2ID),
                "value": .int(i)
            ]))
        }
        
        // Query as admin
        let adminContext = BlazeUserContext.admin(userID: UUID())
        let points = try db.graph(for: adminContext) {
            $0.x("team_id")
              .y(.count)
        }.toPoints()
        
        // Admin should see all teams (bypasses RLS)
        XCTAssertEqual(points.count, 2)
    }
    
    // MARK: - Engineer Role Tests
    
    func testGraphQueryWithEngineer_SeesOnlyTeamRecords() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        let team2ID = UUID()
        
        // Add policy: users can only see their team's records
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert test data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(i < 3 ? team1ID : team2ID),
                "value": .int(i)
            ]))
        }
        
        // Query as engineer on team1
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team1ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("team_id")
              .y(.count)
        }.toPoints()
        
        // Engineer should see only team1 records
        XCTAssertEqual(points.count, 1)
        if let firstPoint = points.first,
           let teamID = firstPoint.x as? UUID {
            XCTAssertEqual(teamID, team1ID)
            XCTAssertEqual(firstPoint.y as? Int, 3)  // 3 records in team1
        }
    }
    
    // MARK: - Viewer Role Tests
    
    func testGraphQueryWithViewer_SeesOnlyAssignedRecords() throws {
        // Setup RLS
        db.rls.enable()
        let viewerID = UUID()
        let otherID = UUID()
        
        // Add policy: viewers see only assigned records
        db.rls.addPolicy(SecurityPolicy(
            name: "assigned_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let assignedTo = record.storage["assigned_to"]?.uuidValue else { return false }
            return assignedTo == context.userID
        })
        
        // Insert test data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "assigned_to": .uuid(i < 2 ? viewerID : otherID),
                "value": .int(i)
            ]))
        }
        
        // Query as viewer
        let viewerContext = BlazeUserContext.viewer(userID: viewerID)
        let points = try db.graph(for: viewerContext) {
            $0.x("assigned_to")
              .y(.count)
        }.toPoints()
        
        // Viewer should see only their assigned records
        XCTAssertEqual(points.count, 1)
        if let firstPoint = points.first,
           let assignedTo = firstPoint.x as? UUID {
            XCTAssertEqual(assignedTo, viewerID)
            XCTAssertEqual(firstPoint.y as? Int, 2)  // 2 records assigned to viewer
        }
    }
    
    // MARK: - Combined Filters Tests
    
    func testGraphQueryWithRLSAndUserFilters_CombinesCorrectly() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        let team2ID = UUID()
        
        // Add policy: users can only see their team's records
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert test data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(i < 5 ? team1ID : team2ID),
                "status": .string(i < 3 ? "active" : "inactive"),
                "value": .int(i)
            ]))
        }
        
        // Query as engineer on team1 with additional filter
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team1ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("status")
              .y(.count)
              .filter { $0.storage["status"]?.stringValue == "active" }
        }.toPoints()
        
        // Should see only active records from team1
        XCTAssertEqual(points.count, 1)
        if let firstPoint = points.first,
           let status = firstPoint.x as? String {
            XCTAssertEqual(status, "active")
            XCTAssertEqual(firstPoint.y as? Int, 3)  // 3 active records in team1
        }
    }
    
    // MARK: - Date Binning with RLS Tests
    
    func testGraphQueryWithRLSAndDateBinning_WorksCorrectly() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        let calendar = Calendar.current
        let baseDate = Date()
        
        // Add policy: users can only see their team's records
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert test data across multiple days
        for dayOffset in 0..<5 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: baseDate)!
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(team1ID),
                "createdAt": .date(date),
                "value": .int(dayOffset)
            ]))
        }
        
        // Query as engineer on team1 with date binning
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team1ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("createdAt", .day)
              .y(.count)
        }.toPoints()
        
        // Should see all days (RLS allows team1 records)
        XCTAssertGreaterThanOrEqual(points.count, 1)
        for point in points {
            XCTAssertTrue(point.x is Date)
            XCTAssertTrue(point.y is Int)
        }
    }
    
    // MARK: - Moving Window with RLS Tests
    
    func testGraphQueryWithRLSAndMovingAverage_WorksCorrectly() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        
        // Add policy: users can only see their team's records
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert sequential data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(team1ID),
                "day": .int(i),
                "value": .double(Double(i) * 10.0)
            ]))
        }
        
        // Query as engineer with moving average
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team1ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("day")
              .y(.sum("value"))
              .movingAverage(3)
        }.toPoints()
        
        // Should have 10 points with moving average applied
        XCTAssertEqual(points.count, 10)
    }
    
    // MARK: - RLS Disabled Tests
    
    func testGraphQueryWithRLSDisabled_IgnoresUserContext() throws {
        // RLS is disabled by default
        let team1ID = UUID()
        let team2ID = UUID()
        
        // Insert test data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(i < 3 ? team1ID : team2ID),
                "value": .int(i)
            ]))
        }
        
        // Query with user context but RLS disabled
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team1ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("team_id")
              .y(.count)
        }.toPoints()
        
        // Should see all teams (RLS not enabled)
        XCTAssertEqual(points.count, 2)
    }
    
    // MARK: - Multiple Roles Tests
    
    func testGraphQueryWithMultipleTeams_SeesAllTeamRecords() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        let team2ID = UUID()
        let team3ID = UUID()
        
        // Add policy: users can see records from any team they're a member of
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert test data
        for i in 0..<9 {
            let teamID = i < 3 ? team1ID : (i < 6 ? team2ID : team3ID)
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(teamID),
                "value": .int(i)
            ]))
        }
        
        // Query as engineer on team1 and team2
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team1ID, team2ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("team_id")
              .y(.count)
        }.toPoints()
        
        // Should see team1 and team2 records
        XCTAssertEqual(points.count, 2)
        
        let teamIDs = Set(points.compactMap { $0.x as? UUID })
        XCTAssertTrue(teamIDs.contains(team1ID))
        XCTAssertTrue(teamIDs.contains(team2ID))
        XCTAssertFalse(teamIDs.contains(team3ID))
    }
    
    // MARK: - Empty Results Tests
    
    func testGraphQueryWithRLS_ReturnsEmptyWhenNoAccess() throws {
        // Setup RLS
        db.rls.enable()
        let team1ID = UUID()
        let team2ID = UUID()
        
        // Add policy: users can only see their team's records
        db.rls.addPolicy(SecurityPolicy(
            name: "team_access",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(teamID)
        })
        
        // Insert test data for team1 only
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "team_id": .uuid(team1ID),
                "value": .int(i)
            ]))
        }
        
        // Query as engineer on team2 (no access to team1 records)
        let engineerContext = BlazeUserContext.engineer(userID: UUID(), teamIDs: [team2ID])
        let points = try db.graph(for: engineerContext) {
            $0.x("team_id")
              .y(.count)
        }.toPoints()
        
        // Should see no results
        XCTAssertEqual(points.count, 0)
    }
}

