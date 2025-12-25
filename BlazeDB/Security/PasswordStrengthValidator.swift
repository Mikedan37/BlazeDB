//
//  PasswordStrengthValidator.swift
//  BlazeDB
//
//  Enhanced password strength validation (security audit recommendation)
//  Validates complexity, not just length
//
//  Created by Michael Danylchuk on 1/15/25.
//

import Foundation

/// Password strength levels
public enum PasswordStrength: Int, Comparable {
    case veryWeak = 0
    case weak = 1
    case fair = 2
    case good = 3
    case strong = 4
    case veryStrong = 5
    
    public static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    public var description: String {
        switch self {
        case .veryWeak: return "Very Weak"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        case .veryStrong: return "Very Strong"
        }
    }
    
    public var recommendation: String {
        switch self {
        case .veryWeak, .weak:
            return "Use at least 12 characters with uppercase, lowercase, numbers, and symbols"
        case .fair:
            return "Consider adding more complexity (symbols, longer length)"
        case .good:
            return "Good password! Consider 16+ characters for maximum security"
        case .strong, .veryStrong:
            return "Excellent password strength!"
        }
    }
}

/// Enhanced password strength validator
public struct PasswordStrengthValidator {
    
    /// Minimum password requirements
    public struct Requirements {
        public let minLength: Int
        public let requireUppercase: Bool
        public let requireLowercase: Bool
        public let requireNumbers: Bool
        public let requireSymbols: Bool
        public let minStrength: PasswordStrength
        
        public init(
            minLength: Int = 8,
            requireUppercase: Bool = false,
            requireLowercase: Bool = false,
            requireNumbers: Bool = false,
            requireSymbols: Bool = false,
            minStrength: PasswordStrength = .fair
        ) {
            self.minLength = minLength
            self.requireUppercase = requireUppercase
            self.requireLowercase = requireLowercase
            self.requireNumbers = requireNumbers
            self.requireSymbols = requireSymbols
            self.minStrength = minStrength
        }
        
        /// Recommended requirements for production
        nonisolated(unsafe) public static let recommended = Requirements(
            minLength: 12,
            requireUppercase: true,
            requireLowercase: true,
            requireNumbers: true,
            requireSymbols: false,  // Optional for usability
            minStrength: .good
        )
        
        /// Strict requirements for high-security
        nonisolated(unsafe) public static let strict = Requirements(
            minLength: 16,
            requireUppercase: true,
            requireLowercase: true,
            requireNumbers: true,
            requireSymbols: true,
            minStrength: .strong
        )
    }
    
    /// Validate password against requirements
    public static func validate(_ password: String, requirements: Requirements = .recommended) throws {
        // Check length
        guard password.count >= requirements.minLength else {
            throw KeyManagerError.passwordTooWeak
        }
        
        // Check character requirements
        if requirements.requireUppercase && !password.contains(where: { $0.isUppercase }) {
            throw KeyManagerError.passwordTooWeak
        }
        
        if requirements.requireLowercase && !password.contains(where: { $0.isLowercase }) {
            throw KeyManagerError.passwordTooWeak
        }
        
        if requirements.requireNumbers && !password.contains(where: { $0.isNumber }) {
            throw KeyManagerError.passwordTooWeak
        }
        
        if requirements.requireSymbols && !password.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) {
            throw KeyManagerError.passwordTooWeak
        }
        
        // Check strength
        let strength = calculateStrength(password)
        guard strength >= requirements.minStrength else {
            throw KeyManagerError.passwordTooWeak
        }
    }
    
    /// Calculate password strength (0-5)
    public static func calculateStrength(_ password: String) -> PasswordStrength {
        var score = 0
        
        // Length scoring
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        if password.count >= 20 { score += 1 }
        
        // Character variety
        var hasUppercase = false
        var hasLowercase = false
        var hasNumbers = false
        var hasSymbols = false
        
        for char in password {
            if char.isUppercase { hasUppercase = true }
            if char.isLowercase { hasLowercase = true }
            if char.isNumber { hasNumbers = true }
            if !char.isLetter && !char.isNumber && !char.isWhitespace { hasSymbols = true }
        }
        
        var varietyCount = 0
        if hasUppercase { varietyCount += 1 }
        if hasLowercase { varietyCount += 1 }
        if hasNumbers { varietyCount += 1 }
        if hasSymbols { varietyCount += 1 }
        
        // Variety bonus
        if varietyCount >= 2 { score += 1 }
        if varietyCount >= 3 { score += 1 }
        if varietyCount >= 4 { score += 1 }
        
        // Common patterns penalty
        let commonPatterns = ["123", "abc", "password", "qwerty", "admin"]
        let lowerPassword = password.lowercased()
        for pattern in commonPatterns {
            if lowerPassword.contains(pattern) {
                score = max(0, score - 1)  // Penalty
                break
            }
        }
        
        // Clamp to valid range
        score = min(5, max(0, score))
        
        return PasswordStrength(rawValue: score) ?? .veryWeak
    }
    
    /// Get password strength with recommendations
    public static func analyze(_ password: String) -> (strength: PasswordStrength, recommendations: [String]) {
        let strength = calculateStrength(password)
        var recommendations: [String] = []
        
        if password.count < 12 {
            recommendations.append("Use at least 12 characters (16+ recommended)")
        }
        
        if !password.contains(where: { $0.isUppercase }) {
            recommendations.append("Add uppercase letters")
        }
        
        if !password.contains(where: { $0.isLowercase }) {
            recommendations.append("Add lowercase letters")
        }
        
        if !password.contains(where: { $0.isNumber }) {
            recommendations.append("Add numbers")
        }
        
        if !password.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) {
            recommendations.append("Consider adding symbols for extra security")
        }
        
        if strength < .good {
            recommendations.append(strength.recommendation)
        }
        
        return (strength, recommendations)
    }
}

extension Character {
    var isUppercase: Bool {
        return self.isLetter && self.uppercased() == String(self) && self.lowercased() != String(self)
    }
    
    var isLowercase: Bool {
        return self.isLetter && self.lowercased() == String(self) && self.uppercased() != String(self)
    }
}

