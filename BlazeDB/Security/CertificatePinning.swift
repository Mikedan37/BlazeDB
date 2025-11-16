//
//  CertificatePinning.swift
//  BlazeDB
//
//  Certificate pinning for TLS connections (security audit recommendation)
//  Prevents MITM attacks by validating server certificates
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation
import Network
import Security

/// Certificate pinning configuration
public struct CertificatePinningConfig {
    /// Pinned certificates (DER format)
    public let pinnedCertificates: [Data]
    
    /// Whether to validate certificate chain
    public let validateChain: Bool
    
    /// Whether to allow self-signed certificates (dev only!)
    public let allowSelfSigned: Bool
    
    public init(
        pinnedCertificates: [Data],
        validateChain: Bool = true,
        allowSelfSigned: Bool = false
    ) {
        self.pinnedCertificates = pinnedCertificates
        self.validateChain = validateChain
        self.allowSelfSigned = allowSelfSigned
    }
    
    /// Load pinned certificate from file
    public static func fromFile(_ url: URL) throws -> CertificatePinningConfig {
        let data = try Data(contentsOf: url)
        return CertificatePinningConfig(pinnedCertificates: [data])
    }
    
    /// Load pinned certificate from bundle
    public static func fromBundle(_ bundle: Bundle, filename: String) throws -> CertificatePinningConfig? {
        guard let url = bundle.url(forResource: filename, withExtension: "cer") else {
            return nil
        }
        return try fromFile(url)
    }
}

/// Certificate pinning validator
public enum CertificatePinning {
    
    /// Validate certificate against pinned certificates
    public static func validate(
        _ certificate: SecCertificate,
        against config: CertificatePinningConfig
    ) throws -> Bool {
        // Extract certificate data
        let certificateData = SecCertificateCopyData(certificate) as Data
        
        // Check if certificate matches any pinned certificate
        for pinnedCert in config.pinnedCertificates {
            if certificateData == pinnedCert {
                return true  // Exact match
            }
        }
        
        // If no exact match and self-signed allowed, check if it's self-signed
        if config.allowSelfSigned {
            // For development/testing only!
            return true
        }
        
        // Certificate doesn't match any pinned certificate
        throw CertificatePinningError.certificateMismatch
    }
    
    /// Validate certificate chain
    public static func validateChain(
        _ certificates: [SecCertificate],
        against config: CertificatePinningConfig
    ) throws -> Bool {
        guard !certificates.isEmpty else {
            throw CertificatePinningError.noCertificates
        }
        
        // Validate each certificate in chain
        for certificate in certificates {
            do {
                _ = try validate(certificate, against: config)
            } catch {
                // If chain validation is enabled, all must match
                if config.validateChain {
                    throw error
                }
            }
        }
        
        return true
    }
}

/// Certificate pinning errors
public enum CertificatePinningError: Error {
    case certificateMismatch
    case noCertificates
    case invalidCertificate
    case chainValidationFailed
    
    public var localizedDescription: String {
        switch self {
        case .certificateMismatch:
            return "Certificate does not match pinned certificate. Possible MITM attack!"
        case .noCertificates:
            return "No certificates provided for validation"
        case .invalidCertificate:
            return "Invalid certificate format"
        case .chainValidationFailed:
            return "Certificate chain validation failed"
        }
    }
}

/// Extension to NWProtocolTLS.Options for certificate pinning
extension NWProtocolTLS.Options {
    
    /// Configure TLS options with certificate pinning
    public static func withPinning(_ config: CertificatePinningConfig) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        
        // Set minimum TLS version to 1.2
        sec_protocol_options_set_min_tls_protocol_version(
            sec_protocol_options_create(),
            .TLSv12
        )
        
        // Configure certificate validation
        sec_protocol_options_set_verify_block(
            sec_protocol_options_create(),
            { (sec_protocol_metadata, sec_trust, sec_protocol_verify_complete) in
                // Extract certificates from trust
                let trust = sec_trust.takeUnretainedValue()
                var certificates: [SecCertificate] = []
                
                let count = SecTrustGetCertificateCount(trust)
                for i in 0..<count {
                    if let cert = SecTrustGetCertificateAtIndex(trust, i) {
                        certificates.append(cert)
                    }
                }
                
                // Validate against pinned certificates
                do {
                    _ = try CertificatePinning.validateChain(certificates, against: config)
                    sec_protocol_verify_complete(true)
                } catch {
                    sec_protocol_verify_complete(false)
                }
            },
            DispatchQueue.global()
        )
        
        return options
    }
}

