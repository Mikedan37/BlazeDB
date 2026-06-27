import XCTest
@testable import BlazeDBCore

final class RLSEnforcementClientTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLS-Enforcement-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    private func makeClient() throws -> BlazeDBClient {
        let dbURL = tempDir.appendingPathComponent("enforcement.blazedb")
        return try BlazeDBClient(name: "RLS-Client", fileURL: dbURL, password: "RLS-TrustPass_123")
    }

    func testFetchAllAppliesRLSFiltering() throws {
        let db = try makeClient()
        let teamA = UUID()
        let teamB = UUID()

        _ = try db.insert(BlazeDataRecord(["teamId": .uuid(teamA), "title": .string("A1")]))
        _ = try db.insert(BlazeDataRecord(["teamId": .uuid(teamB), "title": .string("B1")]))

        db.enableRLS()
        db.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        db.setRLSContext(userID: UUID(), teamIDs: [teamA], roles: ["member"])

        let visible = try db.fetchAll()
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.storage["teamId"]?.uuidValue, teamA)
    }

    func testFetchByIDReturnsNilWhenRLSDenies() throws {
        let db = try makeClient()
        let owner = UUID()
        let outsider = UUID()

        let id = try db.insert(
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "userId": .uuid(owner),
                "title": .string("secret"),
            ])
        )

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        db.setRLSContext(userID: outsider, roles: ["member"])

        let fetched = try db.fetch(id: id)
        XCTAssertNil(fetched)
    }

    func testUpdateThrowsPermissionDeniedWhenRLSBlocks() throws {
        let db = try makeClient()
        let owner = UUID()
        let outsider = UUID()

        let id = try db.insert(
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "userId": .uuid(owner),
                "title": .string("secret"),
            ])
        )

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        db.setRLSContext(userID: outsider, roles: ["member"])

        let updated = BlazeDataRecord(["title": .string("hacked"), "userId": .uuid(owner)])
        XCTAssertThrowsError(try db.update(id: id, with: updated)) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied UPDATE"))
        }
    }

    func testDeleteThrowsPermissionDeniedWhenRLSBlocks() throws {
        let db = try makeClient()
        let owner = UUID()
        let outsider = UUID()

        let id = try db.insert(
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "userId": .uuid(owner),
                "title": .string("secret"),
            ])
        )

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        db.setRLSContext(userID: outsider, roles: ["member"])

        XCTAssertThrowsError(try db.delete(id: id)) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied DELETE"))
        }
    }

    func testInsertThrowsPermissionDeniedWhenViewerReadOnly() throws {
        let db = try makeClient()
        db.enableRLS()
        db.configureRLSViewerReadOnlyPolicies(viewerRole: "viewer")
        db.setRLSContext(userID: UUID(), roles: ["viewer"])

        XCTAssertThrowsError(try db.insert(BlazeDataRecord(["title": .string("blocked")]))) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied INSERT"))
        }
    }

    func testQueryRespectsRLS() throws {
        let db = try makeClient()
        let teamA = UUID()
        let teamB = UUID()

        _ = try db.insert(BlazeDataRecord(["teamId": .uuid(teamA), "title": .string("A1")]))
        _ = try db.insert(BlazeDataRecord(["teamId": .uuid(teamB), "title": .string("B1")]))

        db.enableRLS()
        db.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        db.setRLSContext(userID: UUID(), teamIDs: [teamA], roles: ["member"])

        let result = try db.query().execute()
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.storage["teamId"]?.uuidValue, teamA)
    }

    func testRLSEnabledWithoutPoliciesDoesNotBlock() throws {
        let db = try makeClient()
        db.enableRLS()

        XCTAssertNoThrow(try db.insert(BlazeDataRecord(["title": .string("allowed")])))
        XCTAssertEqual(try db.fetchAll().count, 1)
    }

    func testPoliciesWithMissingContextFailClosed() throws {
        let db = try makeClient()
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "userId": .uuid(UUID()),
            "title": .string("secret")
        ]))

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")

        XCTAssertEqual(try db.fetchAll().count, 0)
        XCTAssertThrowsError(try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "userId": .uuid(UUID()),
            "title": .string("blocked")
        ])))
    }

    func testRestrictiveDenyOverridesPermissiveAllow() throws {
        let db = try makeClient()
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("record")
        ]))

        db.enableRLS()
        db.rls.addPolicy(
            SecurityPolicy(
                name: "allow_select",
                operation: .select,
                type: .permissive
            ) { _, _ in true }
        )
        db.rls.addPolicy(
            SecurityPolicy(
                name: "deny_select",
                operation: .select,
                type: .restrictive
            ) { _, _ in false }
        )
        db.setRLSContext(userID: UUID(), roles: ["member"])

        XCTAssertEqual(try db.fetchAll().count, 0)
        let result = try db.query().execute()
        XCTAssertEqual(try result.records.count, 0)
    }

    func testInsertManyThrowsPermissionDeniedWhenViewerReadOnly() throws {
        let db = try makeClient()
        db.enableRLS()
        db.configureRLSViewerReadOnlyPolicies(viewerRole: "viewer")
        db.setRLSContext(userID: UUID(), roles: ["viewer"])

        XCTAssertThrowsError(try db.insertMany([
            BlazeDataRecord(["title": .string("blocked-1")]),
            BlazeDataRecord(["title": .string("blocked-2")]),
        ])) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied INSERT"))
        }
    }

    func testUpdateManyThrowsPermissionDeniedWhenRLSBlocks() throws {
        let db = try makeClient()
        let owner = UUID()
        let outsider = UUID()

        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "userId": .uuid(owner), "title": .string("t1")]))
        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "userId": .uuid(owner), "title": .string("t2")]))

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        db.setRLSContext(userID: outsider, roles: ["member"])

        XCTAssertThrowsError(
            try db.updateMany(where: { _ in true }, set: ["title": .string("hacked")])
        ) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied UPDATE"))
        }
    }

    func testDeleteManyIDsThrowsPermissionDeniedWhenRLSBlocks() throws {
        let db = try makeClient()
        let owner = UUID()
        let outsider = UUID()
        let id1 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "userId": .uuid(owner), "title": .string("t1")]))
        let id2 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "userId": .uuid(owner), "title": .string("t2")]))

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        db.setRLSContext(userID: outsider, roles: ["member"])

        XCTAssertThrowsError(try db.deleteMany(ids: [id1, id2])) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied DELETE"))
        }
    }

    func testDeleteManyWhereThrowsPermissionDeniedWhenRLSBlocks() throws {
        let db = try makeClient()
        let owner = UUID()
        let outsider = UUID()

        _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "userId": .uuid(owner), "title": .string("t1")]))

        db.enableRLS()
        db.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
        db.setRLSContext(userID: outsider, roles: ["member"])

        XCTAssertThrowsError(try db.deleteMany(where: { _ in true })) { error in
            guard case BlazeDBError.permissionDenied(let operation, _) = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
            XCTAssertTrue(operation.contains("RLS denied DELETE"))
        }
    }

    func testCountDistinctFetchPageFetchBatchApplyRLS() throws {
        let db = try makeClient()
        let teamA = UUID()
        let teamB = UUID()
        let idA1 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "teamId": .uuid(teamA), "kind": .string("A")]))
        let idA2 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "teamId": .uuid(teamA), "kind": .string("A")]))
        let idB1 = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "teamId": .uuid(teamB), "kind": .string("B")]))

        db.enableRLS()
        db.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        db.setRLSContext(userID: UUID(), teamIDs: [teamA], roles: ["member"])

        XCTAssertEqual(try db.count(), 2)
        XCTAssertEqual(try db.fetchPage(offset: 0, limit: 10).count, 2)
        XCTAssertEqual(try db.fetchBatch(ids: [idA1, idA2, idB1]).count, 2)

        let distinct = try db.distinct(field: "kind")
        XCTAssertEqual(Set(distinct), Set([.string("A")]))
    }

    func testJoinAppliesRLSOnBothSides() throws {
        let issues = try makeClient()
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        let users = try BlazeDBClient(name: "Users", fileURL: usersURL, password: "RLS-TrustPass_123")

        let teamA = UUID()
        let teamB = UUID()
        let aliceID = UUID()
        let bobID = UUID()

        _ = try users.insert(BlazeDataRecord(["id": .uuid(aliceID), "teamId": .uuid(teamA), "name": .string("alice")]))
        _ = try users.insert(BlazeDataRecord(["id": .uuid(bobID), "teamId": .uuid(teamB), "name": .string("bob")]))
        _ = try issues.insert(BlazeDataRecord(["id": .uuid(UUID()), "authorId": .uuid(aliceID), "teamId": .uuid(teamA)]))
        _ = try issues.insert(BlazeDataRecord(["id": .uuid(UUID()), "authorId": .uuid(bobID), "teamId": .uuid(teamB)]))

        issues.enableRLS()
        users.enableRLS()
        issues.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        users.configureRLSAdminAndTeamPolicies(teamIDField: "teamId")
        issues.setRLSContext(userID: UUID(), teamIDs: [teamA], roles: ["member"])
        users.setRLSContext(userID: UUID(), teamIDs: [teamA], roles: ["member"])

        let joined = try issues.join(with: users, on: "authorId", equals: "id", type: .inner)
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined.first?.right?["name"]?.stringValue, "alice")
    }

    func testRLSContextDoesNotLeakAcrossClientInstances() throws {
        let dbURL = tempDir.appendingPathComponent("shared-instance.blazedb")
        let owner = UUID()
        let outsider = UUID()

        do {
            let first = try BlazeDBClient(name: "Shared", fileURL: dbURL, password: "RLS-TrustPass_123")
            _ = try first.insert(BlazeDataRecord(["id": .uuid(UUID()), "userId": .uuid(owner), "title": .string("secret")]))
            first.enableRLS()
            first.configureRLSAdminAndOwnerPolicies(userIDField: "userId")
            first.setRLSContext(userID: outsider, roles: ["member"])
            XCTAssertEqual(try first.fetchAll().count, 0)
            try first.close()
        }

        let reopened = try BlazeDBClient(name: "Shared", fileURL: dbURL, password: "RLS-TrustPass_123")
        XCTAssertFalse(reopened.isRLSEnabled)
        XCTAssertFalse(reopened.hasRLSContext)
        XCTAssertEqual(try reopened.fetchAll().count, 1)
    }
}

