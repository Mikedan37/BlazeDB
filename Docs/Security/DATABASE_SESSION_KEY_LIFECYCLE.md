# Database Session and Key Lifecycle Policy

**Status:** Implemented (Jun 2026)  
**Last updated:** 2026-06-30

This document defines when BlazeDB derives encryption keys, how long derived keys live in memory, and what `close()` means for secrets. It exists so performance work on startup latency does not accidentally weaken security—or burn CPU on policy nobody wrote down.

Related: [KEY_MANAGEMENT_AND_COMPATIBILITY.md](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md), [BLAZEDB_THREAT_MODEL.md](BLAZEDB_THREAT_MODEL.md)

---

## Definitions

| Term | Meaning |
|------|---------|
| **Process session** | From process start until process exit. |
| **Database session** | A verified derived encryption key for one database, held in volatile process memory until explicitly invalidated or process exit. |
| **Handle lifetime** | One `BlazeDBClient` instance from `init` until `close()`. Releasing file locks and flushing writes. **Not** the same as end of database session. |
| **Cold open** | First successful open of a database in this process, or open after explicit cache invalidation. Requires full PBKDF2 (600k iterations in release). |
| **Warm reopen** | Open after a prior verified open of the same database in the same process. May reuse in-memory derived key without full PBKDF2. |

**Default mental model for app developers:**

By default, a database session lasts for the lifetime of the process unless explicitly invalidated (`clearSessionKeys()`). Within that window:

```
App launch → open DB → use → close handle → open again → still same session
→ quit app → process session ends → all derived keys gone
```

`close()` ends a **handle**, not the **database session**.

---

## Assets

1. **Plaintext records** — in memory while the database is in use.
2. **Derived encryption key** — AES-256 key from PBKDF2-HMAC-SHA256 over password + per-DB salt.
3. **Password** — caller-supplied unlock secret; should not persist in plaintext longer than necessary.

---

## Threat model (scope for this policy)

### In scope

| Attacker capability | Mitigation |
|---------------------|------------|
| Steals disk / backup | Per-page AES-256-GCM; key derived from password + salt not stored on disk |
| Reads swap after process exit | Keys exist only in RAM; destroyed on process termination |
| Opens DB with wrong password | Reject at open (verifier or full KDF on cold open) |
| Tampering with metadata | HMAC-SHA256 on signed layout |

### Non-goals

| Scenario | Rationale |
|----------|-----------|
| Arbitrary code execution **inside the BlazeDB host process** | Attacker can read any in-memory derived key. Re-running PBKDF2 on every handle reopen does not materially help. |
| Cross-process secret sharing | Each process derives or holds its own session state. No Keychain persistence in this policy. |
| Offline password guessing | Bounded by PBKDF2 cost on **cold open** and password policy—not by reopen frequency. |

### Question this policy must answer

> What attack does clearing the in-memory derived key on every `close()` actually stop?

**Answer:** None of the in-scope threats above, once the key is already verified and held in RAM for this process. Clearing on `close()` only forces redundant PBKDF2 work on reopen. It does **not** protect against memory scraping while the process is alive, and it does **not** erase secrets if another handle or cache still holds them.

---

## Intended behavior (target policy)

### When full PBKDF2 runs

- First open of a database in this process (cold open).
- After `BlazeDBClient.clearCachedKey()` or per-path invalidation.
- After password change for that database (must invalidate old session entry).
- When no matching session entry exists for `(database identity, salt)`.

Release builds use **600,000** iterations. Tests may use lower counts via XCTest detection or explicit overrides; that is test infrastructure, not this policy.

### When warm reopen is allowed

After a successful cold open, the process may retain for that database:

- the **derived key** (volatile memory only), and
- a **session verifier** (volatile memory only) used to confirm a supplied password without repeating PBKDF2.

Warm reopen must **not** persist derived keys to disk, Keychain, or shared containers.

### What `close()` must do

- Flush pending writes (`persist()` best-effort).
- Release file locks and file handles.
- Clear `password` on the client instance (reduce plaintext lifetime on the handle).
- Mark the handle unusable.

### What `close()` must not do (under this policy)

- Wipe process-wide session keys for other databases.
- Force full PBKDF2 on the next open of the same database in the same process.

---

## Caches (two layers, different keys)

| Cache | Key | Purpose |
|-------|-----|---------|
| `KeyManager.passwordKeyCache` | Hash of `(password, salt)` | Avoid repeat PBKDF2 for same password+salt within the process |
| `BlazeDBClient._cachedKeys` | Database path (or stable DB identity) | Bind verified derived key to a specific database |

**Implementation note:** Today `clearCachedKey(for: path)` removes one path entry but also calls `KeyManager.clearKeyCache()`, wiping **every** database’s KDF cache. That is broader than this policy and is not multi-database-friendly. Future implementation should invalidate **only** the affected database session (or use scoped KeyManager eviction).

---

## Password on reopen

### Preferred API direction

If the process session already holds a verified entry for this database:

- Reopen may **omit** the password (reuse session key), or
- Accept an optional password for explicit re-authentication.

Requiring password on every reopen is an **API convention**, not a security requirement, once cold open has verified the secret.

### If password is supplied on warm reopen

Do **not** run full PBKDF2. Compare against the session verifier (constant-time). On mismatch, fail closed with `passwordMismatch` (or equivalent)—do not fall back to decrypting with a stale key.

Verifier construction (to be finalized at implementation time):

- Must be derivable from the successful cold-open KDF output or password+salt.
- Must never be written to disk.
- Must be invalidated with the session entry on password change or explicit cache clear.

---

## Explicit invalidation

Session entries must be removed when:

1. Process exits (automatic).
2. Caller invokes `BlazeDBClient.clearCachedKey()` (all) or scoped per-database clear.
3. Password change for that database is detected or requested.
4. Tests call clear helpers in `setUp`/`tearDown` (test hygiene only).

Session entries must **not** be removed merely because one handle called `close()`.

---

## Out of scope (separate decisions)

| Idea | Why deferred |
|------|----------------|
| **Keychain / Secure Enclave persistence of derived key** | Credential lifecycle (biometrics, restore, multi-process, invalidation) is a product feature, not a reopen optimization. |
| **Lowering PBKDF2 iteration count** | Security tradeoff; requires explicit threat-model sign-off, not benchmark-driven change. |
| **Skipping password on cold open** | Never. Cold open always proves knowledge of the secret. |

---

## Verification

After implementation:

```bash
./Scripts/run_open_profile.sh
```

Expect:

| Scenario | Wall time (order of magnitude) |
|----------|--------------------------------|
| Cold open (release, 600k) | ~1 s dominated by PBKDF2 |
| Warm reopen (same process) | ~30 ms engine init, PBKDF2 ≈ 0 |
| After `clearSessionKeys()` | Cold again |

Benchmark docs must label cold vs warm explicitly. Historical ~55 ms “cold open” numbers measured handle reopen with path cache—not comparable to true cold open under this policy.

---

## Implementation status

1. ✅ Stop clearing process session caches in `BlazeDBClient.close()`.
2. ✅ Scoped `clearSessionKeys(for:)` / `clearCachedKey(for:)` — evicts one database + its KDF cache entry only.
3. ✅ Session verifier on warm reopen when password is supplied.
4. ⏳ Optional-password reopen when session entry exists (future API).
5. ⏳ Document API in README and `API_REFERENCE.md`.
6. ✅ Tests in `DatabaseSessionKeyLifecycleTests`.

**Verified:** `./Scripts/run_open_profile.sh` — cold ~1.2s (PBKDF2), warm ~28ms (no `open.pbkdf2` span).
