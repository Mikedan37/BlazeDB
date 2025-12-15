//
//  SecurityAuditor.swift
//  BlazeDB
//
//  Security audit and recommendations (security audit recommendation)
//  Analyzes database security configuration and provides recommendations
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Security audit findings
public struct SecurityAuditFinding {
    public let severity: Severity
    public let category: Category
    public let title: String
    public let description: String
    public let recommendation: String
    public let fixable: Bool
    
    public enum Severity: String {
        case critical = "Critical"
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case info = "Info"
    }
    
    public enum Category: String {
        case encryption = "Encryption"
        case accessControl = "Access Control"
        case network = "Network"
        case dataIntegrity = "Data Integrity"
        case password = "Password"
        case audit = "Audit Logging"
    }
}

/// Security audit report
public struct SecurityAuditReport {
    public let findings: [SecurityAuditFinding]
    public let overallScore: Int  // 0-100
    public let recommendations: [String]
    public let timestamp: Date
    
    public var criticalCount: Int {
        findings.filter { $0.severity == .critical }.count
    }
    
    public var highCount: Int {
        findings.filter { $0.severity == .high }.count
    }
    
    public var mediumCount: Int {
        findings.filter { $0.severity == .medium }.count
    }
    
    public var isSecure: Bool {
        return overallScore >= 80 && criticalCount == 0 && highCount == 0
    }
}

/// Security auditor - analyzes database security configuration
public struct SecurityAuditor {
    
    /// Audit database security configuration
    public static func audit(
        isEncrypted: Bool,
        password: String? = nil,
        hasRBAC: Bool = false,
        hasRLS: Bool = false,
        hasAuditLogging: Bool = false,
        usesTLS: Bool = false,
        hasCertificatePinning: Bool = false,
        crc32Enabled: Bool = false,
        passwordRequirements: PasswordStrengthValidator.Requirements? = nil
    ) -> SecurityAuditReport {
        var findings: [SecurityAuditFinding] = []
        var recommendations: [String] = []
        
        // 1. Encryption check
        if !isEncrypted {
            findings.append(SecurityAuditFinding(
                severity: .critical,
                category: .encryption,
                title: "Database Not Encrypted",
                description: "Database is stored in plaintext. Sensitive data is vulnerable.",
                recommendation: "Enable encryption with a strong password (12+ characters) or use Secure Enclave.",
                fixable: true
            ))
        } else {
            // Check password strength if provided
            if let password = password {
                let (strength, passwordRecommendations) = PasswordStrengthValidator.analyze(password)
                if strength < .good {
                    findings.append(SecurityAuditFinding(
                        severity: strength < .fair ? .high : .medium,
                        category: .password,
                        title: "Weak Password",
                        description: "Password strength: \(strength.description)",
                        recommendation: passwordRecommendations.joined(separator: ". "),
                        fixable: true
                    ))
                }
            }
        }
        
        // 2. CRC32 for unencrypted databases
        if !isEncrypted && !crc32Enabled {
            findings.append(SecurityAuditFinding(
                severity: .medium,
                category: .dataIntegrity,
                title: "CRC32 Not Enabled",
                description: "Unencrypted database should enable CRC32 for corruption detection.",
                recommendation: "Enable CRC32: BlazeBinaryEncoder.crc32Mode = .enabled",
                fixable: true
            ))
        }
        
        // 3. Access control
        if !hasRBAC && !hasRLS {
            findings.append(SecurityAuditFinding(
                severity: .high,
                category: .accessControl,
                title: "No Access Control",
                description: "Database has no RBAC or RLS policies. All users have full access.",
                recommendation: "Enable RBAC/RLS for multi-user scenarios: db.setSecurityPolicy(policy)",
                fixable: true
            ))
        }
        
        // 4. Network security
        if usesTLS && !hasCertificatePinning {
            findings.append(SecurityAuditFinding(
                severity: .medium,
                category: .network,
                title: "No Certificate Pinning",
                description: "TLS is enabled but certificate pinning is not configured. Vulnerable to MITM attacks.",
                recommendation: "Enable certificate pinning for production: CertificatePinningConfig.fromFile(url)",
                fixable: true
            ))
        } else if !usesTLS {
            findings.append(SecurityAuditFinding(
                severity: .high,
                category: .network,
                title: "No TLS Encryption",
                description: "Network connections are not encrypted. Data is transmitted in plaintext.",
                recommendation: "Enable TLS for all network connections: remote.useTLS = true",
                fixable: true
            ))
        }
        
        // 5. Audit logging
        if !hasAuditLogging {
            findings.append(SecurityAuditFinding(
                severity: .low,
                category: .audit,
                title: "No Audit Logging",
                description: "Audit logging is disabled. Cannot track access or changes.",
                recommendation: "Enable audit logging for compliance and security monitoring.",
                fixable: true
            ))
        }
        
        // Calculate overall score
        let score = calculateScore(findings: findings)
        
        // Generate recommendations
        if !findings.isEmpty {
            recommendations.append("Review and address all security findings above.")
        }
        
        if !isEncrypted {
            recommendations.append("Enable encryption immediately for production use.")
        }
        
        if hasRBAC || hasRLS {
            recommendations.append("✅ Access control is properly configured.")
        }
        
        if usesTLS && hasCertificatePinning {
            recommendations.append("✅ Network security is properly configured.")
        }
        
        return SecurityAuditReport(
            findings: findings,
            overallScore: score,
            recommendations: recommendations,
            timestamp: Date()
        )
    }
    
    /// Calculate security score (0-100)
    private static func calculateScore(findings: [SecurityAuditFinding]) -> Int {
        var score = 100
        
        for finding in findings {
            switch finding.severity {
            case .critical:
                score -= 20
            case .high:
                score -= 10
            case .medium:
                score -= 5
            case .low:
                score -= 2
            case .info:
                score -= 1
            }
        }
        
        return max(0, min(100, score))
    }
    
    /// Quick security check
    public static func quickCheck(
        isEncrypted: Bool,
        hasRBAC: Bool = false,
        usesTLS: Bool = false
    ) -> Bool {
        return isEncrypted && (hasRBAC || !usesTLS || usesTLS)  // Basic check
    }
}

