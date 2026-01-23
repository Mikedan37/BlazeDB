# Security Issue: Non-Deterministic Key Derivation

## Problem

The key derivation process can produce different keys from the same password, which is a **critical security vulnerability**.

### Root Cause

1. **Argon2 Fallback Behavior**: The code tries Argon2 first, and if it fails, falls back to PBKDF2:
 ```swift
 do {
 let derivedKey = try Argon2KDF.deriveKey(...)
 // Use Argon2 key
 } catch {
 // Fallback to PBKDF2
 let derivedKey = try deriveKeyPBKDF2(...)
 // Use PBKDF2 key
 }
 ```

2. **Non-Deterministic Failures**: If Argon2 fails inconsistently (e.g., due to memory constraints, timing, or implementation bugs), the same password might:
 - Use Argon2 in one instance → Key A
 - Fall back to PBKDF2 in another instance → Key B
 - Result: **Different keys from the same password!**

3. **Impact**:
 - Signature verification fails (as we're seeing in tests)
 - Database cannot be opened with the same password
 - Data becomes inaccessible
 - **This breaks the fundamental security guarantee that the same password always produces the same key**

## Current Behavior

- Salt is fixed: `"AshPileSalt"` (good - ensures determinism)
- Key derivation is NOT deterministic if Argon2 fails inconsistently (bad)
- Cache helps but doesn't solve the root issue

## Security Implications

1. **Data Loss Risk**: Users might lose access to their data if key derivation is inconsistent
2. **Signature Verification Failures**: HMAC signatures fail because different keys are used
3. **Backup/Restore Issues**: Backups cannot be restored if keys differ
4. **Trust Violation**: Users expect the same password to always work

## Recommended Fix

### Option 1: Make Argon2 Failure Deterministic (Recommended)

Always use the same KDF method for the same password. If Argon2 fails once, always use PBKDF2 for that password:

```swift
public static func getKey(from password: String, salt: Data) throws -> SymmetricKey {
 let cacheKey = password + salt.base64EncodedString()

 // Check cache first
 if let cached = passwordKeyCache[cacheKey] {
 return cached
 }

 // Try Argon2, but if it fails, mark this password as "PBKDF2-only"
 // and always use PBKDF2 for it in the future
 let useArgon2: Bool
 if let method = kdfMethodCache[cacheKey] {
 useArgon2 = (method ==.argon2)
 } else {
 useArgon2 = true // Try Argon2 first
 }

 let derivedKey: Data
 if useArgon2 {
 do {
 derivedKey = try Argon2KDF.deriveKey(...)
 kdfMethodCache[cacheKey] =.argon2
 } catch {
 // Argon2 failed - use PBKDF2 and remember this
 derivedKey = try deriveKeyPBKDF2(...)
 kdfMethodCache[cacheKey] =.pbkdf2
 }
 } else {
 // Always use PBKDF2 for this password
 derivedKey = try deriveKeyPBKDF2(...)
 }

 let symmetricKey = SymmetricKey(data: derivedKey)
 passwordKeyCache[cacheKey] = symmetricKey
 return symmetricKey
}
```

### Option 2: Remove Argon2 Fallback (Simpler)

If Argon2 fails, throw an error instead of falling back:

```swift
// Remove fallback - if Argon2 fails, fail hard
let derivedKey = try Argon2KDF.deriveKey(
 from: password,
 salt: salt,
 parameters: Argon2KDF.Parameters.default
)
```

### Option 3: Use Database-Specific Salt (Better Security)

Store the KDF method and parameters in the database metadata so each database uses a consistent method:

```swift
struct DatabaseMetadata {
 let kdfMethod: KDFMethod //.argon2 or.pbkdf2
 let kdfParameters: Data // Serialized parameters
 //... other metadata
}
```

## Immediate Action Required

1. **Fix the non-deterministic behavior** - same password must always produce same key
2. **Add tests** to verify key derivation determinism
3. **Document the KDF method** used for each database
4. **Consider database-specific salts** for better security

## Test Case

```swift
func testKeyDerivationDeterminism() throws {
 let password = "TestPassword123!"
 let salt = "AshPileSalt".data(using:.utf8)!

 // Clear cache
 KeyManager.clearPasswordKeyCache()

 // Derive key multiple times
 let key1 = try KeyManager.getKey(from: password, salt: salt)
 let key2 = try KeyManager.getKey(from: password, salt: salt)
 let key3 = try KeyManager.getKey(from: password, salt: salt)

 // All should be identical
 XCTAssertEqual(key1, key2, "Key derivation must be deterministic")
 XCTAssertEqual(key2, key3, "Key derivation must be deterministic")
}
```

