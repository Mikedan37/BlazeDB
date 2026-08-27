//
//  RLSEnforcementGapTests.swift
//  BlazeDBTests
//
//  Regression tests for #334–#337: GraphQuery context, WITH CHECK on updates,
//  stats/count side channels, and filtered observer delete forwarding.
//

import XCTest
@testable import BlazeDBCore

final class RLSEnforcementGapTests: XCTestCase {
    private var tempDir: URL!
    private let password = "RLSEnforcementGap-Test-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLSGap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testGraphBuilderHonorsClientRLSContext() throws {
        let url = tempDir.appendingPathComponent("graph-builder-rls.blazedb")
        let db = try BlazeDBClient(name: "graph-builder-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let teamA = UUID()
        let teamB = UUID()
        let userA = UUID()

        db.enableRLS()
        db.rls.addPolicy(SecurityPolicy(
            name: "team_select",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let team = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(team)
        })

        db.setRLSContext(userID: userA, teamIDs: [teamA, teamB], roles: ["admin"])
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamA), "n": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamA), "n": .int(2)]))
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamB), "n": .int(3)]))

        db.setRLSContext(userID: userA, teamIDs: [teamA], roles: ["engineer"])
        let points = try db.graph {
            $0.x("team_id").y(.count)
        }.toPoints()
        XCTAssertEqual(points.count, 1, "graph { } builder must apply client RLS context (#334)")
        XCTAssertEqual(points.first?.y as? Int, 2)
    }

    func testPublicGraphHonorsClientRLSContext() throws {
        let url = tempDir.appendingPathComponent("graph-rls.blazedb")
        let db = try BlazeDBClient(name: "graph-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let teamA = UUID()
        let teamB = UUID()
        let userA = UUID()

        db.enableRLS()
        db.setRLSContext(userID: userA, teamIDs: [teamA], roles: ["engineer"])
        db.rls.addPolicy(SecurityPolicy(
            name: "team_select",
            operation: .select,
            type: .restrictive
        ) { context, record in
            guard let team = record.storage["team_id"]?.uuidValue else { return false }
            return context.teamIDs.contains(team)
        })

        db.setRLSContext(userID: userA, teamIDs: [teamA, teamB], roles: ["admin"])
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamA), "n": .int(1)]))
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamA), "n": .int(2)]))
        _ = try db.insert(BlazeDataRecord(["team_id": .uuid(teamB), "n": .int(3)]))

        db.setRLSContext(userID: userA, teamIDs: [teamA], roles: ["engineer"])
        let points = try db.graph().x("team_id").y(.count).toPoints()
        XCTAssertEqual(points.count, 1, "public graph() must apply client RLS context (#334)")
        XCTAssertEqual(points.first?.y as? Int, 2)
    }

    func testUpdateRejectsPostMutationRLSViolation() throws {
        let url = tempDir.appendingPathComponent("with-check.blazedb")
        let db = try BlazeDBClient(name: "with-check", fileURL: url, password: password)
        defer { try? db.close() }

        let owner = UUID()
        let other = UUID()
        db.enableRLS()
        db.setRLSContext(userID: owner, roles: ["admin"])
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_update",
            operation: .update,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID
        })
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_insert",
            operation: .insert,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID || context.hasRole("admin")
        })
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_select",
            operation: .select,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID || context.hasRole("admin")
        })

        let id = try db.insert(BlazeDataRecord(["userId": .uuid(owner), "note": .string("mine")]))
        db.setRLSContext(userID: owner, roles: ["member"])

        var stolen = try XCTUnwrap(try db.fetch(id: id))
        stolen.storage["userId"] = .uuid(other)
        XCTAssertThrowsError(try db.update(id: id, with: stolen), "WITH CHECK must reject ownership transfer (#335)")
        let still = try XCTUnwrap(try db.fetch(id: id))
        XCTAssertEqual(still.storage["userId"]?.uuidValue, owner)
    }

    func testUpdateManyRejectsPostMutationRLSViolation() throws {
        let url = tempDir.appendingPathComponent("with-check-many.blazedb")
        let db = try BlazeDBClient(name: "with-check-many", fileURL: url, password: password)
        defer { try? db.close() }

        let owner = UUID()
        let other = UUID()
        db.enableRLS()
        db.setRLSContext(userID: owner, roles: ["admin"])
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_update",
            operation: .update,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID
        })
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_insert",
            operation: .insert,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID || context.hasRole("admin")
        })
        db.rls.addPolicy(SecurityPolicy(
            name: "owner_select",
            operation: .select,
            type: .restrictive
        ) { context, record in
            record.storage["userId"]?.uuidValue == context.userID || context.hasRole("admin")
        })

        let id = try db.insert(BlazeDataRecord(["userId": .uuid(owner), "note": .string("mine")]))
        db.setRLSContext(userID: owner, roles: ["member"])

        XCTAssertThrowsError(
            try db.updateMany(where: { _ in true }, set: ["userId": .uuid(other)]),
            "updateMany WITH CHECK must reject ownership transfer (#335)"
        )
        let still = try XCTUnwrap(try db.fetch(id: id))
        XCTAssertEqual(still.storage["userId"]?.uuidValue, owner)
    }

    func testGetRecordCountRespectsRLS() throws {
        let url = tempDir.appendingPathComponent("count-rls.blazedb")
        let db = try BlazeDBClient(name: "count-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let user = UUID()
        let other = UUID()
        db.enableRLS()
        db.setRLSContext(userID: user, roles: ["admin"])
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        _ = try db.insert(BlazeDataRecord(["userId": .uuid(user)]))
        _ = try db.insert(BlazeDataRecord(["userId": .uuid(other)]))

        db.setRLSContext(userID: user, roles: ["member"])
        XCTAssertEqual(db.getRecordCount(), 1, "getRecordCount must not leak total rows under RLS (#336)")
        XCTAssertEqual(try db.stats().recordCount, 1)
    }

    func testFilteredObservationDoesNotForwardDeletes() throws {
        let url = tempDir.appendingPathComponent("observe-rls.blazedb")
        let db = try BlazeDBClient(name: "observe-rls", fileURL: url, password: password)
        defer { try? db.close() }

        let id = try db.insert(BlazeDataRecord(["tag": .string("keep")]))
        let exp = expectation(description: "no delete forwarded")
        exp.isInverted = true
        let token = db.observe(where: { ($0.storage["tag"]?.stringValue ?? "") == "keep" }) { changes in
            for change in changes {
                if case .delete = change.type {
                    exp.fulfill()
                }
            }
        }
        defer { token.invalidate() }

        try db.delete(id: id)
        wait(for: [exp], timeout: 0.3)
    }
}
