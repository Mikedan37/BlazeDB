# BlazeDB Security

**Encryption model, threat model, and cryptographic pipelines.**

---

## Design Intent

BlazeDB encrypts all data at rest by default using AES-256-GCM with per-page granularity. The system assumes encryption is mandatory, not optional, and integrates key management with the storage layer. This design enables efficient garbage collection of encrypted pages and hardware-backed key storage where available.

---

## Encryption Model

### Per-Page Encryption

All data is encrypted at rest using AES-256-GCM with unique nonces per page:

- **Algorithm**: AES-256-GCM
- **Key Derivation**: PBKDF2 (10,000 iterations) by default; Argon2id available as alternative
- **Key Size**: 256 bits
- **Authentication**: GCM auth tag (prevents tampering)
- **Nonce**: Unique per page (prevents replay attacks)

### Key Management

```swift
// Key derivation from user password (PBKDF2 default)
let key = try KeyManager.getKey(
 from:.password(password),
 createIfMissing: false
)

// Alternative: Argon2id for enhanced security
let argon2Key = try KeyManager.getKeyArgon2(
 from: password,
 salt: databaseSalt,
 parameters:.default
)

// Secure Enclave integration (iOS/macOS)
let secureKey = try KeyManager.getKey(
 from:.secureEnclave(label: "com.app.blazedb"),
 createIfMissing: true
)
```

**Secure Enclave**: Hardware-backed key storage on iOS/macOS devices. Keys never leave the Secure Enclave.

### Encryption Pipeline

Records are encoded to BlazeBinary, assembled into 4KB pages, encrypted with AES-256-GCM using a unique nonce per page, then written to disk. Each page is encrypted independently, enabling efficient garbage collection.

---

## Threat Model

### Threat Actors

1. **Physical Access**: Attacker has device access
 - Mitigation: Encryption at rest, Secure Enclave

2. **Network Interception**: Attacker intercepts sync traffic
 - Mitigation: TLS/SSL, ECDH key exchange, end-to-end encryption

3. **Malicious Application**: Compromised app process
 - Mitigation: Row-level security, policy evaluation

4. **Storage Corruption**: Accidental or malicious data corruption
 - Mitigation: CRC32 checksums, corruption detection, automatic recovery

### Attack Surfaces

- **Local Storage**: Encrypted pages prevent plaintext access
- **Network Sync**: TLS + E2E encryption prevent interception
- **Query Interface**: RLS policies filter unauthorized data
- **Key Storage**: Secure Enclave prevents key extraction

---

## Cryptographic Architecture

### Data at Rest: Local Encryption Pipeline

User passwords are processed through PBKDF2 (10,000 iterations) by default to derive a master key. Argon2id is available as an alternative for enhanced security. HKDF derives per-page keys from the master key. Each 4KB page is encrypted with AES-256-GCM using its derived key and a unique nonce.

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
| Network interception | TLS/SSL |  Required |
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

For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md).
For protocol security, see [PROTOCOL.md](PROTOCOL.md).

