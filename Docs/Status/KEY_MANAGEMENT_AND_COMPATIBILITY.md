# Key Management and Compatibility Modes

This note defines supported key-management behavior for OSS users and explicitly flags unsafe compatibility paths.

## Supported Key Management Modes

BlazeDB supports:

- password-derived keys via PBKDF2-SHA256 with per-database `.salt`,
- compatibility key-derivation attempts for legacy material where applicable,
- optional Secure Enclave integration where platform support exists.

Operational default is password-derived keys unless the application configures a different key source.

## Compatibility Fallbacks (Use With Care)

The following are compatibility paths for legacy data and migrations:

- `allowUnsignedLayoutFallback` in secure layout loading,
- legacy metadata/layout normalization decode paths,
- alternate KDF verification attempts when signature verification fails.

These paths are intended for controlled migration and recovery scenarios, not steady-state production operation.

## Explicitly Unsafe / Non-Production Flags

- `BLAZEDB_BENCHMARK_NO_ENCRYPTION` disables encryption for benchmark isolation.

This flag must never be enabled for production data.

## Operational Recommendations

1. Keep compatibility fallback paths disabled in normal production startup.
2. Use fallback modes only during one-time migration windows.
3. Validate and re-save metadata in current secure format after migration.
4. Track KDF/crypto policy changes in `CHANGELOG.md`.
