import Foundation
#if canImport(Security)
import Security
#endif

enum SecureRandomError: LocalizedError {
    case systemRandomFailure(status: Int32)

    var errorDescription: String? {
        switch self {
        case .systemRandomFailure(let status):
            return "Secure random generation failed with status \(status)"
        }
    }
}

enum SecureRandom {
    /// Returns cryptographically secure random bytes.
    ///
    /// On Apple platforms we use `SecRandomCopyBytes` first. If it fails,
    /// we log and fall back to `SystemRandomNumberGenerator`.
    static func bytes(count: Int) -> Data {
        precondition(count >= 0, "Byte count must be non-negative")
        guard count > 0 else { return Data() }

        var bytes = [UInt8](repeating: 0, count: count)

#if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        BlazeLogger.error("SecRandomCopyBytes failed (status: \(status)); falling back to SystemRandomNumberGenerator")
#endif

        var rng = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max, using: &rng)
        }
        return Data(bytes)
    }

    /// Strict variant for critical key/salt creation.
    ///
    /// On Apple platforms, this requires `SecRandomCopyBytes` success.
    /// On non-Apple platforms, `SystemRandomNumberGenerator` is used.
    static func bytesStrict(count: Int) throws -> Data {
        precondition(count >= 0, "Byte count must be non-negative")
        guard count > 0 else { return Data() }

#if canImport(Security)
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SecureRandomError.systemRandomFailure(status: status)
        }
        return Data(bytes)
#else
        return bytes(count: count)
#endif
    }
}
