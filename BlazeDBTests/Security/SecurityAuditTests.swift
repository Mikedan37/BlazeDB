//
//  SecurityAuditTests.swift
//  BlazeDBTests
//
//  Tests for security audit recommendations
//
//  Created by Michael Danylchuk on 1/15/25.
//

import XCTest
@testable import BlazeDBCore

final class SecurityAuditTests: XCTestCase {
    
    var tempURL: URL!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecurityAudit-\(UUID().uuidString).blazedb")
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    // MARK: - Password Strength Tests
    
    func testPasswordStrength_WeakPassword() {
        let (strength, _) = PasswordStrengthValidator.analyze("12345678")
        XCTAssertEqual(strength, .veryWeak, "8 digits should be very weak")
    }
    
    func testPasswordStrength_GoodPassword() {
        let (strength, _) = PasswordStrengthValidator.analyze("MySecurePass123!")
        XCTAssertGreaterThanOrEqual(strength, .good, "Complex password should be good or better")
    }
    
    func testPasswordStrength_Validation_Weak() {
        XCTAssertThrowsError(try PasswordStrengthValidator.validate("12345678", requirements: .recommended)) { error in
            XCTAssertTrue(error is KeyManagerError)
        }
    }
    
    func testPasswordStrength_Validation_Strong() {
        XCTAssertNoThrow(try PasswordStrengthValidator.validate("MySecurePass123!", requirements: .recommended))
    }
    
    // MARK: - Security Audit Tests
    
    func testSecurityAudit_UnencryptedDatabase() {
        let report = SecurityAuditor.audit(
            isEncrypted: false,
            hasRBAC: false,
            hasRLS: false,
            crc32Enabled: false
        )
        
        XCTAssertGreaterThan(report.criticalCount, 0, "Unencrypted database should have critical findings")
        XCTAssertLessThan(report.overallScore, 80, "Unencrypted database should score low")
        XCTAssertFalse(report.isSecure, "Unencrypted database should not be secure")
    }
    
    func testSecurityAudit_EncryptedDatabase() {
        let report = SecurityAuditor.audit(
            isEncrypted: true,
            password: "MySecurePass123!",
            hasRBAC: true,
            hasRLS: true,
            usesTLS: true,
            hasCertificatePinning: true,
            crc32Enabled: true
        )
        
        XCTAssertEqual(report.criticalCount, 0, "Secure database should have no critical findings")
        XCTAssertGreaterThanOrEqual(report.overallScore, 80, "Secure database should score high")
        XCTAssertTrue(report.isSecure, "Secure database should be secure")
    }
    
    func testSecurityAudit_WeakPassword() {
        let report = SecurityAuditor.audit(
            isEncrypted: true,
            password: "12345678",
            hasRBAC: false,
            hasRLS: false
        )
        
        let passwordFinding = report.findings.first { $0.category == .password }
        XCTAssertNotNil(passwordFinding, "Should find weak password")
        XCTAssertGreaterThanOrEqual(passwordFinding!.severity, .medium, "Weak password should be medium or high severity")
    }
    
    func testSecurityAudit_NoTLS() {
        let report = SecurityAuditor.audit(
            isEncrypted: true,
            usesTLS: false
        )
        
        let networkFinding = report.findings.first { $0.category == .network }
        XCTAssertNotNil(networkFinding, "Should find no TLS")
        XCTAssertEqual(networkFinding!.severity, .high, "No TLS should be high severity")
    }
    
    func testSecurityAudit_NoCertificatePinning() {
        let report = SecurityAuditor.audit(
            isEncrypted: true,
            usesTLS: true,
            hasCertificatePinning: false
        )
        
        let pinningFinding = report.findings.first { $0.title.contains("Certificate") }
        XCTAssertNotNil(pinningFinding, "Should find no certificate pinning")
        XCTAssertEqual(pinningFinding!.severity, .medium, "No certificate pinning should be medium severity")
    }
    
    func testSecurityAudit_CRC32Recommendation() {
        let report = SecurityAuditor.audit(
            isEncrypted: false,
            crc32Enabled: false
        )
        
        let crc32Finding = report.findings.first { $0.title.contains("CRC32") }
        XCTAssertNotNil(crc32Finding, "Should recommend CRC32 for unencrypted DBs")
    }
}

extension SecurityAuditReport {
    var password: String? { nil }  // Helper for tests
}

