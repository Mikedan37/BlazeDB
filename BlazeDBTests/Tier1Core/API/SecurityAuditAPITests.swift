import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class SecurityAuditAPITests: XCTestCase {
    private var dbURL: URL!

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("security-audit-api-\(UUID().uuidString).blazedb")
    }

    override func tearDownWithError() throws {
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    func testQuickCheck_NotTautological() {
        XCTAssertFalse(
            SecurityAuditor.quickCheck(isEncrypted: true, hasRBAC: false, usesTLS: false),
            "Encrypted-only should not pass quick check when no access controls are configured"
        )
        XCTAssertTrue(
            SecurityAuditor.quickCheck(isEncrypted: true, hasRBAC: true, usesTLS: false),
            "Encrypted + access control should pass quick check"
        )
    }

    func testPerformSecurityAudit_RLSPoliciesCountAsAccessControl() throws {
        let db = try BlazeDBClient(name: "audit-rls", fileURL: dbURL, password: "AuditRLS-123!")
        defer { try? db.close() }

        db.rls.enable()
        db.rls.addPolicy(.publicRead)

        let report = db.performSecurityAudit()
        let noAccessControlFinding = report.findings.first { $0.title == "No Access Control" }
        XCTAssertNil(noAccessControlFinding, "Enabled RLS policies should count as access control in security audit")
    }
}
