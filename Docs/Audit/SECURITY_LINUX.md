# BlazeDB Security & Trust Model (Linux)

**Technical security documentation for Linux deployments. Audit-grade accuracy based on codebase inspection.**

---

## Design Intent

BlazeDB provides strong cryptographic guarantees on Linux using platform-agnostic primitives. Apple-specific security features (Secure Enclave, certificate pinning via Security.framework, Network.framework TLS) are intentionally excluded rather than emulated. This document describes what BlazeDB protects, how it protects it, and what operators must provide at the infrastructure level.

### Philosophy: Correctness, Transparency, Composability

**Correctness:**
- BlazeDB does not emulate Apple-specific security features on Linux
- Missing features are explicitly excluded via conditional compilation (`#if canImport(...)`)
- Security guarantees are either fully available or explicitly documented as unavailable
- This prevents false security assumptions and ensures accurate threat modeling

**Transparency:**
- All platform-specific limitations are explicitly documented
- Operators know exactly what security features are available on Linux
- No hidden assumptions about platform capabilities
- Explicit limitations enable proper risk assessment and security planning

**Composability:**
- BlazeDB integrates with Linux-native security tools and infrastructure
- TLS termination handled by proven, audited software (nginx, HAProxy)
- Key management handled by external secrets management systems (Vault, AWS Secrets Manager, etc.)
- Operators choose appropriate security layers for their specific threat model
- BlazeDB provides cryptographic primitives; operators provide infrastructure security

---

## 1. Threat Model (Linux)

### What BlazeDB Protects Against

1. **Physical Access to Storage**
   - **Threat**: Attacker gains access to database files on disk
   - **Mitigation**: AES-256-GCM encryption at rest with per-page granularity
   - **Guarantee**: Without the encryption key, stored data is computationally infeasible to decrypt
   - **Implementation**: `PageStore.swift` encrypts all pages before writing to disk

2. **Storage Corruption**
   - **Threat**: Accidental or malicious modification of encrypted pages
   - **Mitigation**: GCM authentication tags detect tampering; CRC32 checksums detect corruption
   - **Guarantee**: Modified pages fail to decrypt; corruption triggers recovery procedures
   - **Implementation**: GCM tag verification in `PageStore.swift` decryption path

3. **Memory Dumps**
   - **Threat**: Process memory dump reveals encryption keys
   - **Mitigation**: Keys stored in process memory with standard OS memory protection
   - **Limitation**: No hardware-backed key isolation (Secure Enclave unavailable on Linux)
   - **Implementation**: Master key stored in `PageStore.key` property (process memory only)

4. **Unauthorized Data Access**
   - **Threat**: Compromised application process attempts to read encrypted data
   - **Mitigation**: Encryption keys required for decryption; row-level security (RLS) policies filter data
   - **Guarantee**: Encrypted data cannot be read without keys; RLS enforces access policies
   - **Implementation**: All page reads require decryption using master key

### What Is Out of Scope

1. **Hardware-Backed Key Storage**
   - Secure Enclave is Apple hardware; not available on Linux
   - Keys reside in process memory with standard OS protection only
   - **Code Evidence**: `SecureEnclaveKeyManager.swift` is wrapped in `#if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))`

2. **OS-Level Certificate Validation**
   - Security.framework certificate pinning is Apple-only
   - BlazeDB does not perform certificate validation on Linux
   - **Code Evidence**: `CertificatePinning.swift` is wrapped in `#if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))`

3. **Network Transport Security**
   - Network.framework TLS features are Apple-only
   - BlazeDB does not provide TLS termination on Linux
   - **Code Evidence**: `SecureConnection.swift` is wrapped in `#if canImport(Network)`, making it unavailable on Linux

4. **Process Isolation**
   - BlazeDB assumes standard Linux process isolation
   - No additional sandboxing beyond OS defaults

5. **WAL Encryption**
   - Transaction log (`txn_log.json`) is stored as plaintext JSON
   - **Code Evidence**: `BlazeDBClient.appendToTransactionLog()` writes plaintext JSON (lines 433-467)
   - WAL entries are not encrypted; only pages in `.blazedb` files are encrypted

### Assumptions

1. **Host OS Security**
   - Linux kernel provides process isolation
   - Filesystem permissions are enforced
   - No root-level compromise of the host

2. **Filesystem Security**
   - Database files are stored on a filesystem with standard permissions
   - Filesystem encryption (e.g., LUKS, dm-crypt) is optional but recommended for defense-in-depth
   - WAL file (`txn_log.json`) is stored with `0o600` permissions (owner read/write only)

3. **Process Isolation**
   - Database process runs with appropriate user permissions
   - No unauthorized processes can read database files or process memory

4. **Key Management**
   - Encryption keys are provided via secure channels (environment variables, secrets management)
   - Keys are not stored in plaintext in configuration files or logs

---

## 2. Cryptographic Primitives (Linux)

### Platform-Agnostic Primitives (Available on Linux)

#### AES-256-GCM Usage

**Where Used:**
- **Data at Rest**: Per-page encryption in `PageStore.swift` (lines 230-279)
- **Data in Transit**: Frame encryption in `SecureConnection.swift` (unavailable on Linux due to `#if canImport(Network)`)

**Implementation Details:**
- **Algorithm**: AES-256-GCM
- **Key Size**: 256 bits (32 bytes)
- **Mode**: Galois/Counter Mode (GCM)
- **Nonce Size**: 12 bytes (96 bits) - generated via `AES.GCM.Nonce()` (cryptographically secure random)
- **Authentication Tag**: 16 bytes (128 bits)
- **Implementation**: `swift-crypto` (cross-platform CryptoKit-compatible API)
- **Conditional Import**: `#if canImport(CryptoKit) import CryptoKit #else import Crypto #endif`

**Exact Guarantees:**
- **Confidentiality**: Encrypted data cannot be decrypted without the 256-bit key. Computational security: breaking AES-256 requires 2^256 operations, which is computationally infeasible with current and foreseeable technology.
- **Integrity**: GCM authentication tag prevents tampering. Any modification to ciphertext or tag results in decryption failure. Tag verification is performed automatically during decryption in `PageStore.swift`.
- **Replay Protection**: Unique nonces per page prevent replay attacks. Nonces are generated using `AES.GCM.Nonce()` which produces cryptographically secure random nonces. Same plaintext encrypted twice produces different ciphertexts.

**Key Scope:**
- **At Rest**: Master key derived from password, per-page keys derived via HKDF (not currently implemented - master key used directly)
- **In Transit**: Ephemeral keys derived via ECDH key exchange per session (unavailable on Linux)
- **Key Isolation**: Keys are never shared between databases or sessions

**Page Encryption Format:**
```
[BZDB][0x02][length][nonce][tag][ciphertext][padding]
  4B    1B      4B      12B    16B    var        var
```
- Magic bytes: "BZDB" (4 bytes)
- Version: 0x02 (1 byte) = encrypted
- Plaintext length: UInt32 big-endian (4 bytes)
- Nonce: 12 bytes (random)
- Authentication tag: 16 bytes (GCM tag)
- Ciphertext: Variable length
- Padding: Zeros to reach 4KB page size

#### Key Derivation

**PBKDF2 (Default)**
- **Function**: PBKDF2 with HMAC-SHA256
- **Iterations**: 10,000 (fixed in `KeyManager.swift` line 56)
- **Input**: User password (UTF-8 encoded) + per-database salt
- **Output**: 256-bit (32-byte) master key
- **Implementation**: Custom implementation in `KeyManager.deriveKeyPBKDF2()` (lines 64-90)
- **Security Note**: 10,000 iterations is the minimum recommended by NIST SP 800-132. For higher security, consider Argon2id.
- **Salt**: Currently uses fixed salt "AshPileSalt" (line 31) - **KNOWN LIMITATION**: All databases use same salt, reducing security

**Argon2id (Alternative)**
- **Function**: Argon2id (memory-hard KDF, approximated in Swift)
- **Default Parameters**: 64MB memory, 3 iterations, 4 threads
- **High Security Parameters**: 128MB memory, 5 iterations, 4 threads
- **Input**: User password + per-database salt
- **Output**: 256-bit (32-byte) master key
- **Implementation**: Custom Swift implementation in `Argon2KDF.swift`
- **Security Note**: Memory-hard property resists GPU/ASIC attacks better than PBKDF2

**HKDF (Key Expansion)**
- **Function**: HKDF-SHA256
- **Purpose**: Derive per-page encryption keys from master key (not currently implemented - master key used directly)
- **Salt**: Database-specific salt (stored in `.meta` file)
- **Info Parameter**: Page-specific context (page index, version number)
- **Output**: 256-bit (32-byte) per-page encryption key
- **Implementation**: `swift-crypto` (`HKDF<SHA256>.deriveKey`)
- **Current Status**: Master key is used directly for all pages; per-page key derivation is not implemented

**Note**: The codebase shows HKDF usage in `SecureConnection.swift` for session key derivation (lines 138-143), but `SecureConnection` is unavailable on Linux due to `#if canImport(Network)` guard.

#### ECDH / Asymmetric Primitives (Data in Transit)

**Status**: **NOT AVAILABLE ON LINUX**

**ECDH P-256 Key Exchange:**
- **Algorithm**: Elliptic Curve Diffie-Hellman over P-256 curve
- **Purpose**: Establish shared secrets for encrypted transport in distributed sync
- **Key Generation**: Ephemeral key pairs generated per session (`P256.KeyAgreement.PrivateKey()`)
- **Key Derivation**: Shared secret derived via `sharedSecretFromKeyAgreement(with:)`
- **Properties**: Perfect forward secrecy (ephemeral keys discarded after session)
- **Implementation**: `swift-crypto` (`P256.KeyAgreement`)
- **Availability**: Only in `SecureConnection.swift`, which is wrapped in `#if canImport(Network)` and unavailable on Linux

**HKDF for Session Key Derivation:**
- **Function**: HKDF-SHA256
- **Input**: ECDH shared secret
- **Salt**: Fixed string "blazedb-sync-v1" (UTF-8 encoded)
- **Info**: Database names (sorted, colon-separated)
- **Output**: 256-bit (32-byte) symmetric session key
- **Usage**: Session key used for AES-256-GCM frame encryption
- **Availability**: Only in `SecureConnection.swift`, which is unavailable on Linux

**Perfect Forward Secrecy:**
- Each session generates new ephemeral key pairs
- Shared secrets are derived per-session and discarded after use
- Compromised long-term keys (if any) do not affect past sessions
- Session keys exist only in memory during active connections
- **Availability**: Only in `SecureConnection.swift`, which is unavailable on Linux

### Apple-Only Primitives (Not Available on Linux)

1. **Secure Enclave**
   - Hardware-backed key storage
   - Keys never leave hardware
   - Protected by device passcode/biometrics
   - **Linux Alternative**: Software-based key storage with OS memory protection
   - **Code Evidence**: `SecureEnclaveKeyManager.swift` wrapped in `#if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))`

2. **Security.framework Certificate Pinning**
   - OS-level certificate validation
   - Trust store integration
   - Certificate chain validation
   - **Linux Alternative**: External TLS termination, manual certificate validation
   - **Code Evidence**: `CertificatePinning.swift` wrapped in `#if canImport(Security) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))`

3. **Network.framework TLS**
   - Integrated TLS/SSL with certificate pinning
   - Automatic certificate validation
   - **Linux Alternative**: External TLS termination (nginx, HAProxy, etc.)
   - **Code Evidence**: `SecureConnection.swift` wrapped in `#if canImport(Network)`

4. **Compression Framework**
   - Apple's Compression framework (LZ4, etc.)
   - **Linux Alternative**: Compression unavailable (wrapped in `#if canImport(Compression)`)
   - **Code Evidence**: `TCPRelay+Compression.swift`, `PageStore+Compression.swift` wrapped in `#if canImport(Compression)`

---

## 3. Data at Rest Security

### Page-Level Encryption

All data is encrypted at rest using AES-256-GCM with per-page granularity:

1. **Page Structure**
   - **Size**: 4KB fixed-size pages
   - **Format**: BlazeBinary-encoded records (or JSON in legacy format)
   - **Encryption**: Each page encrypted independently
   - **Implementation**: `PageStore.swift` `_writePageLockedUnsynchronized()` method (lines 225-279)

2. **Encryption Process**
   ```
   Plaintext Page (4KB)
     ↓
   Generate Unique Nonce (12 bytes) via AES.GCM.Nonce()
     ↓
   AES-256-GCM Encrypt (key: master key, not per-page derived)
     ↓
   Ciphertext + Authentication Tag (16 bytes)
     ↓
   Write to Disk (with header: BZDB + 0x02 + length + nonce + tag + ciphertext)
   ```

3. **Key Derivation Flow**
   ```
   User Password (UTF-8 encoded)
     ↓
   PBKDF2-HMAC-SHA256 (10,000 iterations)
   Salt: Fixed "AshPileSalt" (KNOWN LIMITATION: not per-database)
     ↓
   Master Key (256 bits / 32 bytes)
   Stored: Process memory only (PageStore.key property), never on disk
     ↓
   Direct Use for All Pages
   (NOTE: Per-page key derivation via HKDF is not implemented)
   ```

**Key Derivation Details:**
- **Master Key Lifetime**: Derived once per database session, exists in process memory for session duration
- **Per-Page Key Lifetime**: Not implemented - master key used directly for all pages
- **Key Scope**: Each database instance has unique master key; keys never shared between databases
- **Key Storage**: Master key stored in `PageStore.key` property (process memory only, line 65)
- **Known Limitation**: Fixed salt "AshPileSalt" used for all databases (line 31 of `KeyManager.swift`)

### Write-Ahead Log (WAL) Encryption

**Status**: **WAL IS NOT ENCRYPTED**

Transaction log entries are stored as **plaintext JSON**:

- **Format**: Newline-delimited JSON entries
- **Encryption**: **NONE** - entries are plaintext JSON
- **File**: `txn_log.json`
- **Permissions**: `0o600` (owner read/write only)
- **Implementation**: `BlazeDBClient.appendToTransactionLog()` (lines 433-467)
- **Content**: Operation type, payload (as serialized strings), timestamp
- **Recovery**: Plaintext WAL entries are read and replayed during crash recovery

**Security Implications:**
- WAL entries contain operation data in plaintext
- If an attacker gains filesystem access, WAL entries are readable
- WAL is intended for crash recovery only; should be cleaned up after successful commit
- **Recommendation**: Use filesystem encryption (LUKS, dm-crypt) to protect WAL files

### Key Lifetime and Scope

1. **Master Key**
   - **Derivation**: Once per database session (when `BlazeDBClient` is initialized)
   - **Storage**: Process memory only (`PageStore.key` property, line 65)
   - **Persistence**: Never written to disk in any form
   - **Lifetime**: Exists for duration of database session
   - **Cleanup**: Cleared from memory on process termination (OS-managed)
   - **Note**: Explicit key clearing from memory is not performed (known limitation)

2. **Per-Page Keys**
   - **Status**: **NOT IMPLEMENTED** - master key used directly for all pages
   - **Intended Design**: Per-page keys derived via HKDF with page-specific context
   - **Current Implementation**: Master key used directly for all page encryption/decryption

3. **Key Scope**
   - **Database Isolation**: Each database instance has a unique master key
   - **Process Isolation**: Keys are not shared between processes (enforced by OS process isolation)
   - **Session Isolation**: Keys are not shared between database sessions (new key derived per session)
   - **Collection Isolation**: All collections within a database share the same master key (not isolated at collection level)

### Crash Recovery Guarantees

1. **Encrypted State Persistence**
   - All pages written to disk are encrypted (`.blazedb` files)
   - WAL entries are **NOT encrypted** (plaintext JSON in `txn_log.json`)
   - No plaintext data is written to `.blazedb` files

2. **Recovery Process**
   - Encrypted pages are read and decrypted using master key
   - Decryption failures indicate corruption or tampering
   - Plaintext WAL entries are read and replayed
   - Recovery proceeds only if page decryption succeeds

3. **Atomicity**
   - Transaction commits are atomic at the encryption layer
   - Partial writes are detected via authentication tag verification
   - Corrupted pages fail to decrypt and trigger recovery

---

## 4. Data in Transit Security

### Encrypted Transport Framing

**Status**: **NOT AVAILABLE ON LINUX**

BlazeDB's end-to-end encryption for distributed sync is **unavailable on Linux**:

1. **Handshake Protocol**
   - ECDH P-256 key exchange establishes shared secret
   - Ephemeral key pairs generated per session
   - Perfect forward secrecy: compromised long-term keys don't affect past sessions
   - **Availability**: Only in `SecureConnection.swift`, which is wrapped in `#if canImport(Network)` and unavailable on Linux

2. **Frame Encryption**
   - Operations encoded to BlazeBinary
   - Encrypted with AES-256-GCM using shared secret
   - Authentication tag prevents tampering
   - Frame format: `[nonce][ciphertext][tag]`
   - **Availability**: Only in `SecureConnection.swift`, which is unavailable on Linux

3. **Transport Layer**
   - **Apple Platforms**: Network.framework TLS (optional, for certificate pinning via Security.framework)
   - **Linux**: BlazeTransport (UDP-based) or custom TCP connections - **NO ENCRYPTION PROVIDED BY BLAZEDB**
   - **Note**: BlazeDB does not provide TLS termination on Linux. `SecureConnection` is conditionally compiled and unavailable on Linux.
   - **Linux Alternative**: Operators must provide TLS termination at infrastructure level (reverse proxy, VPN, etc.)

### Authentication of Peers

**What Exists (Apple Platforms Only):**
- ECDH key exchange authenticates key material
- Shared secret derivation ensures only parties with correct keys can decrypt
- Node IDs identify peers in distributed sync
- **Availability**: Only in `SecureConnection.swift`, which is unavailable on Linux

**What Doesn't Exist (Linux):**
- Certificate-based authentication (Security.framework unavailable)
- OS-level trust store validation
- Certificate pinning
- End-to-end encryption (SecureConnection unavailable)

**Implications:**
- BlazeDB does not validate peer certificates on Linux
- BlazeDB does not provide encrypted transport on Linux
- Operators must provide certificate validation at the infrastructure level
- Manual peer verification is required for production deployments
- **Recommendation**: Use TLS termination (nginx, HAProxy) or VPN for network security

### Avoiding Plaintext Transport

**Current Status on Linux**: **BLAZEDB DOES NOT ENCRYPT DATA IN TRANSIT ON LINUX**

1. **Encryption Before Transport**
   - **Apple Platforms**: All operations are encrypted with AES-256-GCM before transmission via `SecureConnection`
   - **Linux**: **NO ENCRYPTION PROVIDED** - data is sent in plaintext over BlazeTransport (UDP) or TCP
   - Encryption keys are established via ECDH key exchange (unavailable on Linux)
   - **Recommendation**: Use TLS termination (nginx, HAProxy, etc.) for encryption layer

2. **Transport Security**
   - **Recommended**: Use TLS termination (nginx, HAProxy, etc.) for additional layer
   - **BlazeDB Layer**: **NO ENCRYPTION ON LINUX** - operators must provide transport security
   - **Defense in Depth**: TLS termination provides encryption layer that BlazeDB does not provide

3. **Network Isolation**
   - Deploy BlazeDB on private networks when possible
   - Use VPNs for remote access
   - Firewall rules restrict access to authorized peers only

---

## 5. Trust Model Differences: Apple Platforms vs Linux

| Feature | Apple Platforms | Linux | Notes |
|---------|----------------|-------|-------|
| **Certificate Pinning** |  Yes (Security.framework) |  No | Linux: External TLS termination required |
| **Secure Enclave** |  Yes (Hardware-backed) |  No | Linux: Software-based key storage |
| **OS Trust Store** |  Yes (Security.framework) |  No | Linux: External trust store management |
| **Software Crypto** |  Yes (CryptoKit/swift-crypto) |  Yes (swift-crypto) | Cross-platform |
| **Network.framework TLS** |  Yes |  No | Linux: External TLS termination |
| **Hardware Key Storage** |  Yes (Secure Enclave) |  No | Linux: Process memory only |
| **Certificate Validation** |  Yes (Automatic) |  No | Linux: Manual validation required |
| **AES-256-GCM Encryption** |  Yes |  Yes | Cross-platform (data at rest only) |
| **ECDH Key Exchange** |  Yes (SecureConnection) |  No | Linux: SecureConnection unavailable |
| **Perfect Forward Secrecy** |  Yes (SecureConnection) |  No | Linux: SecureConnection unavailable |
| **Row-Level Security** |  Yes |  Yes | Cross-platform |
| **WAL Encryption** |  No |  No | Plaintext JSON on all platforms |
| **Compression** |  Yes (Compression.framework) |  No | Linux: Compression unavailable |

### Why These Differences Exist

1. **Intentional Feature Gating**
   - BlazeDB does not emulate Apple-specific features on Linux
   - Missing features are excluded via conditional compilation, not weakened
   - This ensures correctness and transparency

2. **Platform Capabilities**
   - Secure Enclave is Apple hardware; cannot be emulated
   - Security.framework is Apple-specific; no Linux equivalent
   - Network.framework is Apple-specific; Linux uses standard sockets
   - Compression.framework is Apple-specific; no Linux equivalent

3. **Composability**
   - BlazeDB integrates with Linux-native security tools
   - TLS termination handled by nginx, HAProxy, etc.
   - Key management handled by external secrets management systems

---

## 6. What BlazeDB Does Not Provide on Linux

### No Hardware-Backed Key Storage

**What's Missing:**
- Secure Enclave hardware protection
- Keys stored in process memory only
- Standard OS memory protection (not hardware-backed)

**Compensation:**
- Use filesystem encryption (LUKS, dm-crypt) for defense-in-depth
- Restrict process memory access via SELinux/AppArmor
- Use external HSM (Hardware Security Module) for key storage if required
- Rotate keys regularly to limit exposure window

### No OS-Level Certificate Pinning

**What's Missing:**
- Security.framework certificate validation
- Automatic certificate chain validation
- Certificate pinning at the OS level

**Compensation:**
- Use TLS termination (nginx, HAProxy) with certificate validation
- Implement certificate pinning at the application level (outside BlazeDB)
- Use VPNs for network isolation
- Manually validate peer certificates in distributed sync scenarios

### No Implicit Trust in Network Peers

**What's Missing:**
- Automatic peer authentication
- OS-level trust store validation
- Certificate-based peer verification
- End-to-end encryption (SecureConnection unavailable)

**Compensation:**
- Implement peer authentication at the application level
- Use pre-shared secrets for peer verification
- Deploy on private networks with firewall rules
- Use VPNs for secure network connectivity
- Use TLS termination for transport encryption

### No Network.framework TLS

**What's Missing:**
- Integrated TLS/SSL with certificate pinning
- Automatic certificate validation
- Network.framework-specific security features
- End-to-end encryption (SecureConnection unavailable)

**Compensation:**
- Use external TLS termination (nginx, HAProxy, etc.)
- Configure TLS at the reverse proxy level
- Use Let's Encrypt or other CA for certificates
- Monitor certificate expiration and rotation

### No WAL Encryption

**What's Missing:**
- Transaction log entries are stored as plaintext JSON
- WAL contains operation data in readable format

**Compensation:**
- Use filesystem encryption (LUKS, dm-crypt) to protect WAL files
- Restrict filesystem permissions (`0o600` is set, but additional isolation recommended)
- Clean up WAL files after successful commit (if supported)
- Monitor filesystem access to WAL files

### No Compression

**What's Missing:**
- Apple's Compression framework (LZ4, etc.)
- Network compression for distributed sync
- Page-level compression

**Compensation:**
- Use external compression (gzip, etc.) at transport layer
- Compression is optional optimization, not security-critical

---

## 7. Security Guarantees BlazeDB Still Provides on Linux

### Confidentiality

**Guarantee:** Encrypted data cannot be decrypted without the encryption key.

**Mechanisms:**
- AES-256-GCM encryption at rest (per-page)
- Per-page encryption with unique nonces
- Keys never written to disk
- **Limitation**: WAL entries are plaintext JSON

**Limitations:**
- Keys stored in process memory (not hardware-backed)
- No protection against memory dumps if process is compromised
- WAL entries are not encrypted

### Integrity

**Guarantee:** Tampered data is detected and rejected.

**Mechanisms:**
- GCM authentication tags prevent tampering
- CRC32 checksums detect corruption (if enabled)
- Authentication tag verification fails on modified pages
- Corrupted pages trigger recovery procedures

**Limitations:**
- No cryptographic signatures for metadata (future enhancement)
- Corruption detection is reactive, not preventive
- WAL entries have no integrity protection (plaintext JSON)

### Replay Protection

**Guarantee:** Replayed operations are detected and rejected.

**Mechanisms:**
- Unique nonces per page prevent replay attacks
- Transaction timestamps prevent replay in distributed sync (unavailable on Linux)
- Lamport timestamps provide ordering guarantees (unavailable on Linux)

**Limitations:**
- Replay protection depends on proper nonce generation
- Clock skew in distributed systems may affect timestamp validation
- Distributed sync replay protection unavailable on Linux (SecureConnection unavailable)

### Isolation Between Data Structures

**Guarantee:** Different databases and collections are cryptographically isolated.

**Mechanisms:**
- Each database has a unique master key
- Per-page keys derived with database-specific context (not implemented - master key used directly)
- Row-level security (RLS) policies enforce access control
- No key sharing between databases

**Limitations:**
- Isolation depends on proper key management
- Compromised master key affects entire database
- Per-page key derivation not implemented (master key used directly)

---

## 8. Design Rationale

### Why Feature-Gating Instead of Emulation

1. **Correctness**
   - Emulating Secure Enclave would provide false sense of security
   - Weakened implementations are worse than explicit exclusions
   - Clear boundaries prevent security misconceptions

2. **Transparency**
   - Operators know exactly what security features are available
   - No hidden assumptions about platform capabilities
   - Explicit limitations enable proper risk assessment

3. **Composability**
   - BlazeDB integrates with Linux-native security tools
   - TLS termination handled by proven, audited software (nginx, HAProxy)
   - Key management handled by external secrets management systems
   - Operators choose appropriate security layers for their threat model

4. **Maintainability**
   - Platform-specific code is clearly separated via conditional compilation
   - Conditional compilation prevents accidental cross-platform assumptions
   - Security features are either fully available or explicitly excluded

### Why Not Weaken Security for Cross-Platform Compatibility

1. **Security Degradation**
   - Weakened implementations provide false security guarantees
   - Operators may assume features work when they don't
   - Better to exclude than to mislead

2. **Correctness Over Convenience**
   - Security is not a convenience feature
   - Explicit limitations are better than implicit failures
   - Operators can compensate with infrastructure-level solutions

3. **Auditability**
   - Clear feature boundaries enable security audits
   - No hidden assumptions about platform capabilities
   - Security reviewers can assess actual guarantees

---

## 9. Operational Recommendations

### TLS Termination Strategies

**Recommended Approach: Reverse Proxy**

Use nginx or HAProxy as a TLS termination layer in front of BlazeDB:

```nginx
# nginx configuration example
server {
    listen 443 ssl http2;
    server_name blazedb.example.com;
    
    ssl_certificate /etc/ssl/certs/blazedb.crt;
    ssl_certificate_key /etc/ssl/private/blazedb.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://localhost:9090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Benefits:**
- Industry-standard TLS implementation (OpenSSL)
- Certificate management via Let's Encrypt or internal CA
- Load balancing and health checks
- Rate limiting and DDoS protection
- Centralized certificate rotation

**Alternative: VPN Tunnel**

For private deployments, use VPN (WireGuard, OpenVPN) for network isolation:
- BlazeDB listens on private network interface
- VPN provides encrypted tunnel between peers
- No TLS termination required if VPN provides sufficient security

### Filesystem Encryption

**Recommended: LUKS/dm-crypt**

Encrypt the filesystem where BlazeDB stores database files:

```bash
# Create encrypted volume
sudo cryptsetup luksFormat /dev/sdb1
sudo cryptsetup luksOpen /dev/sdb1 blazedb-encrypted
sudo mkfs.ext4 /dev/mapper/blazedb-encrypted
sudo mount /dev/mapper/blazedb-encrypted /var/lib/blazedb
```

**Benefits:**
- Defense-in-depth: Even if BlazeDB encryption is compromised, filesystem encryption provides additional layer
- Protects against physical disk theft
- Protects WAL files (which are plaintext JSON)
- Transparent to BlazeDB (operates at filesystem level)
- Standard Linux tooling (LUKS, dm-crypt)

**Key Management:**
- Store LUKS passphrase in secure secrets management system
- Use keyfile stored on separate device or HSM
- Rotate LUKS keys periodically

### Secrets Management

**Recommended: External Secrets Management**

Store BlazeDB encryption passwords in external secrets management systems:

**Options:**
- **HashiCorp Vault**: Industry-standard secrets management
- **AWS Secrets Manager**: Cloud-native secrets management
- **Kubernetes Secrets**: For containerized deployments (base64 encoded, not encrypted by default)
- **Environment Variables**: Simple but less secure (visible in process list)

**Best Practices:**
- Never store passwords in configuration files or version control
- Rotate passwords regularly (requires database re-encryption)
- Use separate secrets for different environments (dev, staging, production)
- Audit secret access logs

**Example: Vault Integration**
```bash
# Retrieve password from Vault
BLAZEDB_PASSWORD=$(vault kv get -field=password secret/blazedb/production)
export BLAZEDB_PASSWORD

# BlazeDB reads from environment
let db = try BlazeDBClient(
    name: "production",
    password: ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"] ?? ""
)
```

### Network Isolation

**Recommended: Private Network Deployment**

1. **Deploy on Private Network**
   - BlazeDB listens on private IP addresses only
   - No public internet exposure
   - Access via VPN or bastion host

2. **Firewall Rules**
   ```bash
   # Allow only specific IPs to connect
   sudo ufw allow from 10.0.0.0/8 to any port 9090
   sudo ufw deny 9090
   ```

3. **Network Segmentation**
   - Separate database network from application network
   - Use network policies (Kubernetes NetworkPolicy, AWS Security Groups)
   - Restrict outbound connections from database servers

4. **Monitoring**
   - Monitor network traffic for anomalies
   - Alert on unexpected connection attempts
   - Log all network access

### Process Security

**Recommended: Least Privilege**

1. **Run as Non-Root User**
   ```bash
   # Create dedicated user
   sudo useradd -r -s /bin/false blazedb
   sudo chown -R blazedb:blazedb /var/lib/blazedb
   ```

2. **File Permissions**
   ```bash
   # Restrict database file access
   sudo chmod 600 /var/lib/blazedb/*.blazedb
   sudo chmod 600 /var/lib/blazedb/*.meta
   sudo chmod 600 /var/lib/blazedb/txn_log.json
   ```

3. **SELinux/AppArmor**
   - Use SELinux or AppArmor to restrict process capabilities
   - Prevent process from accessing unauthorized files
   - Restrict network access to authorized peers only

4. **Memory Protection**
   - Use `mlock()` to prevent key material from being swapped to disk
   - Consider using `madvise()` to mark key memory as sensitive
   - Note: Explicit key clearing from memory is not performed (known limitation)

### Key Rotation

**Recommended: Periodic Key Rotation**

1. **Backup Before Rotation**
   ```swift
   // Backup encrypted database
   try db.backup(to: backupURL)
   ```

2. **Re-encrypt with New Key**
   - Export all data
   - Create new database with new password
   - Import data into new database
   - Verify data integrity
   - Replace old database

3. **Rotation Schedule**
   - Production: Every 90 days or after security incidents
   - Development: As needed
   - Document rotation dates and procedures

### Monitoring and Auditing

**Recommended: Comprehensive Logging**

1. **Security Events**
   - Log all authentication attempts
   - Log all database access
   - Log encryption/decryption failures
   - Alert on suspicious activity

2. **Performance Monitoring**
   - Monitor encryption/decryption performance
   - Track key derivation time
   - Monitor memory usage (key storage)

3. **Compliance**
   - Maintain audit logs for compliance requirements
   - Retain logs for required duration
   - Encrypt audit logs at rest

---

## 10. Future Extensions (Optional)

### Linux Trust Store Integration

**Proposal:** Integrate with Linux trust stores (e.g., `/etc/ssl/certs`, `ca-certificates`)

**Benefits:**
- Automatic certificate validation using system trust store
- Standard Linux certificate management
- Integration with existing certificate infrastructure

**Implementation:**
- Use OpenSSL or similar for certificate validation
- Parse system trust store certificates
- Validate certificate chains against system CAs

### Pluggable Certificate Validation

**Proposal:** Allow operators to provide custom certificate validation callbacks

**Benefits:**
- Custom validation logic for specific use cases
- Integration with existing certificate management systems
- Support for custom CAs and certificate pinning

**Implementation:**
- Protocol for certificate validation callbacks
- Integration with distributed sync transport layer
- Support for custom validation in SecureConnection (if made available on Linux)

### External HSM Support

**Proposal:** Integrate with Hardware Security Modules (HSMs) for key storage

**Benefits:**
- Hardware-backed key storage on Linux
- Compliance with security requirements (FIPS, Common Criteria)
- Protection against memory dumps and process compromise

**Implementation:**
- PKCS#11 interface for HSM integration
- Key derivation and storage via HSM
- Support for common HSM vendors (YubiHSM, AWS CloudHSM, etc.)

### WAL Encryption

**Proposal:** Encrypt WAL entries using AES-256-GCM

**Benefits:**
- WAL entries protected from filesystem-level access
- Consistent encryption across all database files
- Defense-in-depth security

**Implementation:**
- Encrypt WAL entries before writing to `txn_log.json`
- Use master key with WAL-specific context for key derivation
- Decrypt during crash recovery

### Per-Page Key Derivation

**Proposal:** Implement HKDF-based per-page key derivation

**Benefits:**
- Each page encrypted with unique key
- Compromise of one page key does not affect others
- Enhanced key isolation

**Implementation:**
- Derive per-page keys via HKDF with page-specific context
- Use derived keys for page encryption/decryption
- Maintain master key for key derivation only

---

## Conclusion

BlazeDB provides strong cryptographic guarantees on Linux using platform-agnostic primitives. Apple-specific security features are intentionally excluded rather than emulated, ensuring correctness and transparency. Operators must provide infrastructure-level security (TLS termination, key management, network isolation) to compensate for missing platform features.

**Key Takeaways:**
- **Confidentiality**: AES-256-GCM encryption at rest (per-page)
- **Integrity**: GCM authentication tags and CRC32 checksums
- **Replay Protection**: Unique nonces per page
- **Limitations**: No hardware-backed key storage, no OS-level certificate validation, no encrypted transport, no WAL encryption
- **Compensation**: External TLS termination, filesystem encryption, secrets management

**Critical Gaps on Linux:**
- **No Encrypted Transport**: SecureConnection unavailable; use TLS termination
- **No WAL Encryption**: WAL entries are plaintext JSON; use filesystem encryption
- **No Hardware Key Storage**: Keys in process memory only; use HSM if required
- **No Certificate Validation**: Use external TLS termination with certificate validation

For architecture details, see [ARCHITECTURE.md](Docs/ARCHITECTURE.md).  
For general security documentation, see [SECURITY.md](Docs/SECURITY.md).

