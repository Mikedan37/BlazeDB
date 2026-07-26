# Security

Canonical security architecture docs (encryption, keys, threat model):

- **DATABASE_SESSION_KEY_LIFECYCLE.md**: when derived keys live in memory; `close()` vs process session (read before changing startup/KDF behavior)
- SECURITY_ANALYSIS.md
- ENCRYPTION_STRATEGY.md
- SECURE_TCP_HANDSHAKE.md
- AUTH_TOKEN_MANAGEMENT.md
- SECURITY_AND_APP_STORE_COMPLIANCE.md
- P2P_ENCRYPTION.md

Vulnerability reporting and disclosure live in the repository root [SECURITY.md](../SECURITY.md) (security policy).

