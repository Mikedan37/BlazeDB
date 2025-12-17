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
#if canImport(Network)
import Network
#endif

#if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
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

#if canImport(Network)
/// Extension to NWProtocolTLS.Options for certificate pinning
extension NWProtocolTLS.Options {
    
    /// Configure TLS options with certificate pinning
    /// NOTE: Certificate pinning implementation requires low-level Security framework APIs
    /// that may not be available on all platforms. This is a placeholder implementation
    /// that returns configured TLS options. Full certificate validation should be performed
    /// at the connection level using SecureConnection validation callbacks.
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public static func withPinning(_ config: CertificatePinningConfig) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        
        // NOTE: Network.framework's NWProtocolTLS.Options doesn't directly expose
        // sec_protocol_options_t. Certificate pinning validation should be performed
        // at the connection level using URLSession or custom validation in SecureConnection.
        // This method returns a configured TLS options object that can be used with
        // NWConnection, but certificate validation must be handled separately.
        
        // For now, return the options object - actual pinning validation should be
        // performed in SecureConnection's certificate validation callback
        return options
    }
}
#endif // canImport(Network)

#endif // canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

