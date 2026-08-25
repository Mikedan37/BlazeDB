# BlazeDB Security

**Encryption model, threat model, and cryptographic pipelines.**

Canonical key-management vocabulary: [KEY_MANAGEMENT_AND_COMPATIBILITY.md](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md).

---

## Design Intent

BlazeDB encrypts all data at rest by default using AES-256-GCM with per-page granularity. The system assumes encryption is mandatory, not optional, and integrates key management with the storage layer. This design enables efficient garbage collection of encrypted pages and hardware-backed key storage where available.

---

## Encryption Model

### Per-Page Encryption

All data is encrypted at rest using AES-256-GCM with unique nonces per page:

- **Algorithm**: AES-256-GCM
- **Password KDF (production open path)**: PBKDF2-HMAC-SHA256 with **600,000** iterations (release default; `KeyManager.productionPBKDF2Iterations`). Under XCTest the default is 100,000 unless overridden. Override via `BLAZEDB_PBKDF2_ITERATIONS`.
- **Salt**: 16-byte per-database `.salt` sidecar (`SecureRandom`); legacy DBs without a sidecar may use a fixed compatibility salt.
- **Derived key size**: 32 bytes (AES-256 material)
- **Authentication**: GCM auth tag (detects ciphertext tampering)
- **Nonce**: Unique per page

There is **no** Argon2id on the production `BlazeDBClient` / `PageStore` open path. A proprietary memory-hard helper (`Argon2KDF`) exists for CLI master-keyring envelopes and layout-signature compatibility fallbacks; it is **not** RFC Argon2id and must not be documented as such.

### Key Management

```swift
// Production open path: password + per-DB salt → PBKDF2-HMAC-SHA256 → AES key
let salt = /* 16-byte .salt sidecar */
let key = try KeyManager.getKey(from: password, salt: salt)

// Secure Enclave integration (iOS/macOS) — platform key source, not the password KDF
let secureKey = try KeyManager.getKey(
 from: .secureEnclave(label: "com.app.blazedb"),
 createIfMissing: true
)
```

**Secure Enclave**: Hardware-backed key storage on iOS/macOS devices. Keys never leave the Secure Enclave.

### Encryption Pipeline

Records are encoded to BlazeBinary, assembled into 4KB pages, encrypted with AES-256-GCM using the database symmetric key and a unique nonce per page, then written to disk. Each page is encrypted independently, enabling efficient garbage collection.

---

## Threat Model

### Threat Actors

1. **Physical Access**: Attacker has device access
- Mitigation: Encryption at rest, Secure Enclave

2. **Network Interception**: Attacker intercepts sync traffic
- Mitigation: TLS/SSL, ECDH key exchange, end-to-end encryption

3. **Malicious Application**: Compromised app process
- Mitigation: Row-level security, policy evaluation (client-enforced)

4. **Storage Corruption**: Accidental or malicious data corruption
- Mitigation: GCM authentication tags, recovery tooling, binary WAL where enabled

### Attack Surfaces

- **Local Storage**: Encrypted pages prevent plaintext access without the key
- **Network Sync**: TLS + E2E encryption prevent interception
- **Query Interface**: RLS policies filter unauthorized data when enabled and configured
- **Key Storage**: Secure Enclave / keyring files (owner-only where platform supports it)
- **Legacy NDJSON `txn_log`**: Unauthenticated plaintext journals are **not** auto-applied into keyed stores (see issue #365)

---

## Cryptographic Architecture

### Data at Rest: Local Encryption Pipeline

User passwords are processed through **PBKDF2-HMAC-SHA256 (600,000 iterations in release)** with a per-database salt to derive a 256-bit AES key. That key seals each 4KB page with **AES-256-GCM** and a unique nonce.

### Data in Transit: Sync & Protocol Encryption

Operations are encoded to BlazeBinary, then encrypted with AES-256-GCM using a shared key established via ECDH P-256 key exchange. The encrypted payload is transmitted over TLS/SSL. Each session uses ephemeral keys for perfect forward secrecy.

### Perfect Forward Secrecy

ECDH key exchange provides perfect forward secrecy:
- Each session uses a new key pair
- Compromised long-term keys don't affect past sessions
- Keys are ephemeral and discarded after use

---

## Row-Level Security (RLS)

### Policy Engine

Fine-grained access control at the record level:

```swift
let policy = SecurityPolicy(
 name: "view_team_bugs",
 type:.restrictive,
 operation:.select
) { record, context in
 guard let teamID = record.storage["teamID"]?.uuidValue else { return false }
 return context.teamIDs.contains(teamID)
}
```

### Policy Types

- **Restrictive**: All policies must pass (AND logic)
- **Permissive**: Any policy can pass (OR logic)

### Security Context

```swift
struct SecurityContext {
 let userID: UUID
 let teamIDs: [UUID]
 let roles: Set<String>
 let customClaims: [String: Any]
}
```

---

## Security Control Matrix

| Threat | Control | Status |
|--------|---------|--------|
| Physical access | Encryption at rest | Implemented |
| Key extraction | Secure Enclave | Implemented |
| Network interception | TLS/SSL | Required |
| E2E encryption | ECDH + AES-256-GCM | Implemented |
| Unauthorized access | Row-level security | Implemented |
| Data tampering | GCM auth tag | Implemented |
| Corruption | CRC32 + detection | Implemented |

---

## Secure Enclave Integration

### iOS/macOS

Hardware-backed key storage:
- Keys never leave Secure Enclave
- Protected by device passcode/biometrics
- No software access to keys

### Linux

Software-based key storage:
- Keys stored in encrypted keychain
- Protected by OS-level encryption
- Fallback to password-based derivation

---

## Best Practices

1. **Use Strong Passwords**: Minimum 12 characters, mixed case, numbers, symbols
2. **Enable Secure Enclave**: Use hardware-backed keys on supported devices
3. **Use TLS**: Always use TLS/SSL for network sync
4. **Implement RLS**: Use row-level security for multi-tenant applications
5. **Regular Backups**: Encrypted backups preserve security guarantees
6. **Key Rotation**: Rotate keys periodically for long-lived databases

---

For architecture details, see [ARCHITECTURE.md](../Architecture/ARCHITECTURE.md).
For protocol security, see [PROTOCOL.md](../Design/PROTOCOL.md).

