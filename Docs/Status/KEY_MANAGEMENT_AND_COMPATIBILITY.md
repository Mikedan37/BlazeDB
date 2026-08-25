# Key Management and Compatibility Modes

This note defines supported key-management behavior for OSS users, separates the different “key” concepts that often get mashed together, and flags unsafe compatibility paths.

## One-sentence product claim (2.8.1)

BlazeDB derives its **normal database encryption key** from a **password** and a **per-database salt** using **PBKDF2-HMAC-SHA256** (600,000 iterations in release), then uses that **256-bit symmetric key** with **AES-256-GCM** for page encryption.

**PBKDF2 is not the encryption algorithm. AES-GCM is.** PBKDF2 is how a human password becomes a suitable AES key.

---

## Vocabulary: do not mash these together

Cryptography reuses the word “key” for several jobs. In BlazeDB they are distinct:

| Concept | What it is | Secret? |
|---------|------------|---------|
| **Password** | Human input | Yes (user secret) — **not** an encryption key |
| **Salt** | Random per-database bytes (`.salt` sidecar) | **No** — readable on disk is normal |
| **KDF output / derived key** | 32 bytes from password + salt via PBKDF2 | Yes |
| **AES key** | That same material as CryptoKit `SymmetricKey` | Yes — used for page seal/open |
| **`Argon2KDF` / CLI `blaze-memory-kdf`** | Proprietary memory-hard helper (legacy envelopes may still say `argon2id`) | Yes — **not Argon2id**; not the default DB open KDF |
| **Secure Enclave key** | Apple hardware/keychain-backed material | Platform-specific — usually **protects or unlocks** secrets; not “the AES page key” by itself |

### Normal open path

```text
password
   +
per-DB salt
   ↓
PBKDF2-HMAC-SHA256  (600,000 iterations in release)
   ↓
32 bytes
   ↓
SymmetricKey
   ↓
AES-256-GCM
   ↓
encrypted database pages
```

Code path: `BlazeDBClient.resolveEncryptionKey` → `KeyManager.getKey(from:salt:)` → `deriveKeyPBKDF2` → page crypto in `PageStore`.

Warm reopen in the same process may reuse a verified session key and skip the 600k stretch (see [DATABASE_SESSION_KEY_LIFECYCLE.md](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md)).

### Why PBKDF2 exists

A password like `hunter2-but-for-databases` is unsuitable as an AES key directly. Humans choose low-entropy strings. AES wants a uniformly distributed 256-bit key.

PBKDF2 repeatedly runs HMAC-SHA256 so guessing passwords is computationally expensive:

```text
PBKDF2(password, salt, 600_000) → 256 bits → AES key material
```

`SymmetricKey(data:)` is the Swift/CryptoKit wrapper around those bytes — not a second cryptographic key.

### What the salt changes

Same password on two databases **must** yield different keys:

```text
password123 + salt_A → key_A
password123 + salt_B → key_B
```

Without a salt, the same password would always produce the same key across databases. Stealing one derived key must not unlock every DB that shared a password. The `.salt` file being readable is expected: salt is not a secret.

### Where `Argon2KDF` differs

Both **PBKDF2** and **real Argon2id** are password-based KDFs. Real Argon2id also forces substantial **memory** cost to raise the price of GPU/ASIC cracking.

BlazeDB’s type named `Argon2KDF` is **not** RFC Argon2id. The file itself says it is Argon2-inspired / proprietary. Conceptually it is a **custom memory-buffer + HMAC/SHA256 construction**, not the Argon2 algorithm. Algorithms are defined constructions, not genres.

| Path | Uses this KDF? |
|------|----------------|
| Default DB open (`KeyManager.getKey`) | **No** — PBKDF2 @ 600k |
| `KeyManager.getKeyArgon2` | Defined; not the production open default |
| CLI master keyring / layout signature auto-detect | May invoke `Argon2KDF` for **compatibility** |

**Do not market or document BlazeDB as “Argon2id.”** Renaming/freezing the proprietary construction without silently changing bytes is tracked as [#316](https://github.com/Mikedan37/BlazeDB/issues/316). Swapping in real Argon2id under the same name would change keys and make existing material unreadable.

### Secure Enclave is a separate axis

- **PBKDF2 / custom KDF** answer: *How do I turn password material into key bytes?*
- **AES-GCM** answers: *How do I encrypt pages with that key?*
- **Secure Enclave / Keychain** answers: *Where can sensitive material or operations be protected on Apple hardware?*

They are not competing “encryption types.” Enclave support is optional and platform-gated (`KeySource.secureEnclave`), not the default password-open story on every OS.

---

## Supported Key Management Modes

BlazeDB supports:

- password-derived keys via **PBKDF2-HMAC-SHA256** with per-database `.salt` (**production default**),
- compatibility key-derivation attempts for legacy material where applicable (including alternate KDF tries),
- optional Secure Enclave integration where platform support exists.

Operational default is password-derived keys unless the application configures a different key source.

Iteration policy (approx.):

| Environment | PBKDF2 iterations |
|-------------|-------------------|
| Release / normal | **600,000** |
| XCTest (default) | 100,000 |
| Override | `BLAZEDB_PBKDF2_ITERATIONS` |

## Compatibility Fallbacks (Use With Care)

The following are compatibility paths for legacy data and migrations:

- `allowUnsignedLayoutFallback` in secure layout loading,
- legacy metadata/layout normalization decode paths,
- alternate KDF verification attempts when signature verification fails (may try proprietary `Argon2KDF` then PBKDF2 variants).

These paths are intended for controlled migration and recovery scenarios, not steady-state production operation.

## Explicitly Unsafe / Non-Production Flags

- `BLAZEDB_BENCHMARK_NO_ENCRYPTION` disables encryption for benchmark isolation.

This flag must never be enabled for production data.

## Operational Recommendations

1. Keep compatibility fallback paths disabled in normal production startup.
2. Use fallback modes only during one-time migration windows.
3. Validate and re-save metadata in current secure format after migration.
4. Track KDF/crypto policy changes in `CHANGELOG.md`.
5. Before changing open latency or key caching, read [DATABASE_SESSION_KEY_LIFECYCLE.md](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md).
6. When answering “what encryption does BlazeDB use?”, state **AES-256-GCM for pages** and **PBKDF2 for password→key** separately; do not claim Argon2id until a real Argon2 library is adopted and migrated under [#316](https://github.com/Mikedan37/BlazeDB/issues/316).

## Related

- Open tour: [Architecture/TOURS/01_OPEN_AND_RECOVERY.md](../Architecture/TOURS/01_OPEN_AND_RECOVERY.md)
- Session warm vs cold: [DATABASE_SESSION_KEY_LIFECYCLE.md](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md)
- Implementation: `BlazeDB/Crypto/KeyManager.swift`, `BlazeDB/Crypto/Argon2KDF.swift`, `BlazeDB/Storage/PageStore.swift`
