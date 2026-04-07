# BlazeDB README Audit

**Date:** 2026-04-07
**Branch:** `main` (at the time of audit, the repo was at tag v2.7.3 while the README still referenced 2.7.2)
**Auditor methodology:** Every claim verified against source files, Package.swift, tests, and examples.

---

## 1. Executive Summary

The README is **partially accurate but stale by one version**, contains several **misleading simplifications**, and has **onboarding problems** that would confuse a new developer.

Specific issues:

- **Version is wrong.** README says 2.7.2; the latest tag is v2.7.3, which is the release that added `TypedStore` — the very API the README promotes as the primary interface.
- **The two typed protocols (`BlazeStorable` vs `BlazeDocument`) are never distinguished.** These are separate protocols with different capabilities: `BlazeStorable` enables KeyPath queries and automatic Codable bridging; `BlazeDocument` requires manual `toStorage()`/`init(from:)` mapping. The `@BlazeQueryTyped` wrapper requires `BlazeDocument`, *not* `BlazeStorable`. A new user following the README's SwiftUI example with a `BlazeStorable` model would hit a compile error.
- **The Quick Start example is functionally correct** but the HelloBlazeDB example linked immediately below uses a different `open(at:)` API, not `open(named:)`. This inconsistency will confuse anyone who runs the example expecting to see the same code.
- **Platform badges are incomplete.** `Package.swift` declares watchOS 8+, tvOS 15+, visionOS 1.0+ — none of which are in the badge.
- **Performance claims are unverifiable from the README.** "Sub-millisecond reads" is stated without benchmark evidence or methodology.
- **The single-collection architecture is never explained.** All records (regardless of type) share one encrypted document collection. A user expecting per-type tables will be surprised.
- **Multiple important features are present in code but either not mentioned or inaccurately categorized:** MVCC (opt-in), full-text search, B-tree/vector/spatial indexes, and more exist in source but the README places "indexing" in the "deferred" category.

The README is good enough for someone who already knows BlazeDB. It is **not good enough for first-time onboarding** due to the protocol confusion, version staleness, and missing architectural context.

---

## 2. Verified Claims

| # | README Claim | Evidence | Status | Notes |
|---|-------------|----------|--------|-------|
| 1 | "Encrypted embedded document store for Swift" | `PageStore` uses `AES.GCM.seal`/`open` in `PageStore.swift`, `PageStore+Overflow.swift`, `PageStore+Compression.swift`. Key derived via `KeyManager.getKey(from:salt:)` → 32-byte key. | **Verified** | |
| 2 | "ACID transactions" | `BlazeDBClient` implements `beginTransaction`/`commitTransaction`/`rollbackTransaction` with snapshot-based rollback (`BlazeDBClient.swift` ~lines 249–1742). Savepoints in `Savepoints.swift`. | **Verified** | No formal isolation level enum; snapshot-style rollback. |
| 3 | "AES-256-GCM encryption" | `_encryptPageBuffer` in `PageStore.swift` uses CryptoKit `AES.GCM.seal`. Key length enforced at 128/192/256 bits; `KeyManager` derives 32-byte (256-bit) keys. | **Verified** | |
| 4 | "WAL-backed durability and crash recovery" | `WriteAheadLog.swift` (legacy) with CRC32 framing, fsync-on-append, replay-on-init. `DurabilityManager`/`RecoveryManager` for unified mode. `CrashRecoveryHarness/` tests. | **Verified** | |
| 5 | "No external service dependencies" | `Package.swift` has one dependency: `swift-crypto` (only for Linux/Android). No database servers, no network services required. | **Verified** | |
| 6 | "`BlazeStorable` + `db.typed(T.self)`" | `BlazeStorable` at `Codable/CodableIntegration.swift:31-33`. `typed()` at `Codable/TypedStore.swift:144-146` returning `TypedStore<T>`. | **Verified** | |
| 7 | "`BlazeDBClient.open(named:password:)`" | `Exports/BlazeDBClient+EasyOpen.swift:31-38` | **Verified** | |
| 8 | "BlazeDoctor, BlazeDump, BlazeInfo" tools | All three exist as executable targets in `Package.swift` (lines 141–152) with `main.swift` source files. | **Verified** | |
| 9 | "SwiftUI query wrappers (`@BlazeQuery`, `@BlazeQueryTyped`)" | `SwiftUI/BlazeQuery.swift`, `SwiftUI/BlazeQueryTyped.swift`. Gated by `#if canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))`. | **Verified** | Apple platforms only. |
| 10 | "Change-observation refresh" for SwiftUI wrappers | `BlazeQueryTypedObserver` subscribes via `db.observe { ... }` in `BlazeQueryTyped.swift:209`. `ChangeObservation.swift:257` defines `observe(_:)`. | **Verified** | |
| 11 | "`db.export(to:)`, `BlazeDBImporter.verify`" | Used in `HelloBlazeDB/main.swift:107-108`. | **Verified** | |
| 12 | "`db.stats()`, `db.health()`" | Used in `HelloBlazeDB/main.swift:114-128`. | **Verified** | |
| 13 | "HMAC-signed for tamper detection" | `StorageLayout+Security.swift` — `HMAC<SHA256>.authenticationCode` in `SecureLayout.create`, `verify(using:)`. | **Verified** | |
| 14 | "MIT License" | `LICENSE` file exists at repo root. | **Verified** | |
| 15 | Community files (CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, THIRD_PARTY_NOTICES) | All exist at repo root. | **Verified** | |
| 16 | "BlazeStudio/ is optional, experimental" | `BlazeStudio/` exists with Xcode project. Not in root `Package.swift` products. | **Verified** | |
| 17 | "Deterministic import/export/verify/restore workflows" | `BlazeDump/main.swift` implements `dump`, `restore`, `verify` subcommands. `HelloBlazeDB` demonstrates export+verify. | **Verified** | |
| 18 | "Swift 6.0+" requirement | `Package.swift` line 1: `// swift-tools-version:6.0` | **Verified** | |
| 19 | "`BLAZEDB_LINUX_CORE` define for Linux/Android" | `Package.swift:94`: `.define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))` | **Verified** | |
| 20 | "Benchmark-only flag `BLAZEDB_BENCHMARK_NO_ENCRYPTION`" | Used in `PageStore.swift` and `BlazeDBBenchmarks/main.swift`. | **Verified** | |

---

## 3. Incorrect / Stale / Misleading Claims

### 3.1 — Version number is stale (High)

**Claim:** "Version: 2.7.2"
**Reality:** At the time of this audit, the repo was at tag v2.7.3 while the README still referenced 2.7.2. The v2.7.3 release is specifically the one that added `TypedStore` — the primary API the README promotes. The README is promoting an API that didn't exist in the version it claims to document.
**Evidence:** `git tag | sort -V | tail -1` → `v2.7.3` (as of 2026-04-07). Commit `4b9b187` on v2.7.3: "feat: add TypedStore ergonomic API and tests".

### 3.2 — `@BlazeQueryTyped` type constraint silently wrong (High)

**Claim:** The README shows `@BlazeQueryTyped` with `type: Bug.self` alongside `BlazeStorable` models, implying they work together.
**Reality:** `@BlazeQueryTyped<T: BlazeDocument>` requires `BlazeDocument`, not `BlazeStorable`. These are **different protocols**:
- `BlazeStorable` (in `CodableIntegration.swift:31`): `Codable, Identifiable where ID == UUID`. Used with `TypedStore` and KeyPath queries.
- `BlazeDocument` (in `BlazeDocument.swift:37`): `Codable, Identifiable where ID == UUID` plus `var storage: BlazeDataRecord`, `toStorage()`, and `init(from:)`. Used with `@BlazeQueryTyped`.

A user who defines `struct Bug: BlazeStorable` and tries to use `@BlazeQueryTyped(db:, type: Bug.self, ...)` will get a compile error. The README never explains this distinction.

### 3.3 — API Tiers table mischaracterizes `BlazeDocument` (Medium)

**Claim:** Table says `BlazeDocument` is for "Manual mapping" and "Custom serialization, non-Codable types."
**Reality:** `BlazeDocument` inherits from `Codable` (line 37 of `BlazeDocument.swift`). It is not for "non-Codable types." It is for models that need manual control over `BlazeDataRecord` mapping, not for avoiding Codable entirely.

### 3.4 — "Sub-millisecond reads" is unverified (Medium)

**Claim:** "Sub-millisecond reads" under "What You Get."
**Reality:** `BlazeDBBenchmarks/main.swift` measures insert/read/delete throughput and reports ops/sec, but there is no published benchmark result in the README nor any methodology disclosed. The claim may be true for hot-cache single-record fetches but is stated unconditionally.

### 3.5 — Platform badge is incomplete (Low)

**Claim:** Badge says "macOS | iOS | Linux | Android."
**Reality:** `Package.swift` declares: `.macOS(.v15)`, `.iOS(.v15)`, `.watchOS(.v8)`, `.tvOS(.v15)`, `.visionOS(.v1)`. Three platforms are missing from the badge.

### 3.6 — "macOS 15+" requirement is stricter than needed for some platforms (Low)

**Claim:** "Requirements: Swift 6.0+, macOS 15+ / iOS 15+"
**Reality:** `Package.swift` says `.macOS(.v15)` and `.iOS(.v15)` which is accurate. But watchOS 8, tvOS 15, and visionOS 1 are also specified and not mentioned.

### 3.7 — Indexing is listed as "deferred" but multiple index types exist (Medium)

**Claim:** Feature matrix lists "indexing/full-text" under "Advanced but supported."
**Reality:** The codebase contains fully implemented index types:
- B-tree: `Storage/BTreeIndex.swift`
- Full-text / inverted: `Storage/InvertedIndex.swift`, `Query/FullTextSearch.swift`
- Vector (cosine NN): `Storage/VectorIndex.swift`
- Spatial (R-tree): `Storage/SpatialIndex.swift`
- Compound indexes: `Core/CompoundIndexKey.swift`

These are real implementations with tests (e.g., `SearchPerformanceBenchmarks.swift`). However, the distinction between "code exists internally" and "public API is stable, documented, and onboarding-ready" matters. The README should not advertise these as primary stable onboarding surfaces unless public creation APIs, stable docs, and runnable examples exist for end users.

### 3.8 — MVCC is not mentioned anywhere (Low-Medium)

**Claim:** Not claimed — but MVCC is present.
**Reality:** Opt-in MVCC with snapshot isolation exists: `BlazeDBClient+MVCC.swift`, `MVCCTransaction.swift`, `VersionManager`, garbage collection. Tests at `MVCCFoundationTests.swift`, `MVCCIntegrationTests.swift`. The README doesn't mention it at all, which is a missed opportunity and an undisclosed capability.

### 3.9 — `swift run HelloBlazeDB` may not match Quick Start (Medium)

**Claim:** "Run the 60-second quick start above (or `swift run HelloBlazeDB` from this repo)."
**Reality:** The Quick Start uses `BlazeDBClient.open(named: "myapp", password: ...)` while HelloBlazeDB uses `BlazeDBClient.open(at: dbPath, password: ...)`. The User model in the Quick Start has `name` and `role` fields; HelloBlazeDB has `name`, `age`, `active`. These are different programs. Telling users they're equivalent is misleading.

### 3.10 — Install snippet uses stale version (Medium)

**Claim:** `from: "2.7.2"` in the install snippet.
**Reality:** Should be `"2.7.3"` or at least the current release. Users copying this will get v2.7.2, which does not include `TypedStore`.

---

## 4. Onboarding Failures

### 4.1 — No explanation of `BlazeStorable` vs `BlazeDocument` (Critical)

**Section:** Quick Start, API Tiers, SwiftUI examples
**Problem:** A new user sees `BlazeStorable` in the Quick Start and `@BlazeQueryTyped` in the SwiftUI section. They define their model as `BlazeStorable`, try to use `@BlazeQueryTyped`, and hit a compile error with no guidance.
**Why it matters:** This is the most likely path a new SwiftUI developer would follow. It fails silently at compile time with a generic constraint error.
**Fix needed:** Either (a) document both protocols clearly with when to use which, or (b) make `BlazeStorable` conform to `BlazeDocument`, or (c) add a `@BlazeQueryStorable` wrapper.

### 4.2 — Single-collection architecture is never explained

**Section:** Not present anywhere
**Problem:** `TypedStore` doc comment says "does not create a separate physical collection or table — BlazeDB stores all records in one encrypted document collection per database file." This fundamental architectural fact is invisible to README readers. If someone inserts `User` and `Order` records, they coexist in one flat collection. `fetchAll(User.self)` works by decoding every record and filtering by decodability.
**Why it matters:** Performance expectations, schema design, and query behavior all depend on understanding this. A user expecting separate tables per type will be surprised.
**Fix needed:** Add a short "Architecture at a Glance" section explaining the single-collection model.

### 4.3 — Nested Codable types are not queryable

**Section:** Not present
**Problem:** `TypedStore` doc comment (line 38-43 of `TypedStore.swift`) says: "Nested Codable structs/classes are currently stored as serialized JSON strings inside BlazeDocumentField.string. Round-tripping works, but the nested fields are not individually queryable via KeyPath filters."
**Why it matters:** Any user with nested models will discover this the hard way. This is a significant "sharp edge" that should be in the README.
**Fix needed:** Mention this limitation in a "Current Limitations" section.

### 4.4 — No "first successful run" validation

**Section:** Quick Start
**Problem:** The Quick Start code snippet is not runnable as-is because it requires a Swift package context (cannot just paste into a playground or single file without SPM setup). The instruction "If this runs, BlazeDB is working" doesn't explain *how* to run it.
**Why it matters:** A truly new user needs to know: create a new Swift package, add the dependency, create `main.swift`, paste the code, run `swift run`.
**Fix needed:** Either show the full setup steps or point to `swift run HelloBlazeDB` as the actual first-run path (and fix HelloBlazeDB to match the Quick Start).

### 4.5 — Durability section is too detailed for a README

**Section:** "Default durability (BlazeDBClient)"
**Problem:** The durability section dives into `PageStore`, `WALMode.legacy` vs `.unified`, NDJSON transaction logs, HMAC signing, and rollback caveats — all before the user has learned the basic API. This is internal architecture documentation in a user-facing README.
**Why it matters:** A new user reading top-to-bottom hits a wall of storage engine internals before they understand how to query data. This should be in `Docs/`, not the README.
**Fix needed:** Move to a linked architecture doc. README should say "WAL-backed durability — see [Durability Details](Docs/...)" and nothing more.

---

## 5. Missing But Important Information

### 5.1 — Single-process constraint

`PageStore.swift:467` documents "single-process only" file locking. `BlazeDBClient+EasyOpen.swift:159` says "BlazeDB is single-process only. Do not share database files between multiple processes." This is a critical limitation never stated in the README.

### 5.2 — Password minimum length

`BlazeDBClient+EasyOpen.swift:25` doc comment says "minimum 8 characters." This constraint is not in the README.

### 5.3 — Default storage locations

`BlazeDBClient+EasyOpen.swift:29-30`: macOS stores at `~/Library/Application Support/BlazeDB/`, Linux at `~/.local/share/blazedb/`. Not mentioned in README.

### 5.4 — `openForTesting()` convenience

A dedicated `openForTesting()` factory method exists (`BlazeDBClient+EasyOpen.swift:207-221`) for test contexts. Not mentioned in README.

### 5.5 — MVCC is opt-in

`BlazeDBClient+MVCC.swift` provides `setMVCCEnabled(_:)` / `isMVCCEnabled()`. This is a meaningful capability that users may want but don't know exists.

### 5.6 — `@Field` property wrapper is unavailable

`BlazeDocument.swift:97`: `@available(*, unavailable, message: "Macro support is not implemented.")`. Dead code that may confuse someone browsing the source. Not mentioned in README, but should not be advertised either.

### 5.7 — Full CRUD on TypedStore

`TypedStore` provides `insert`, `insertMany`, `fetch`, `fetchAll`, `update`, `updateMany`, `upsert`, `delete`, `query`, `count`. The README only shows `insert` and `fetchAll`.

### 5.8 — Concurrency model

`BlazeDBClient` is `@unchecked Sendable`. `DynamicCollection` uses GCD barrier queues for thread safety. `MemoryPool` is an actor. The README says "Swift 6 strict concurrency compliant" in the status line but doesn't explain what that means for callers (can you use it from multiple tasks?).

---

## 6. Recommended README Restructure

```
# BlazeDB
  - One-line description (encrypted embedded doc store for Swift)
  - Version / License / Badges (accurate)

## What BlazeDB Is (and Is Not)
  - What it is: embedded, encrypted, single-process, document-oriented
  - What it is not: a relational database, a distributed database, a server

## Quick Start
  - Minimal runnable example matching the actual current API
  - How to actually run it (swift run HelloBlazeDB)

## Install
  - SPM snippet with correct version
  - Xcode instructions

## Core Concepts
  - Single-collection architecture
  - BlazeStorable vs BlazeDocument (when to use which)
  - Encryption is always on

## API Reference Summary
  - TypedStore CRUD (insert, fetch, query, update, delete)
  - Raw API (BlazeDataRecord)
  - SwiftUI wrappers (note: BlazeDocument required)

## Platform Support
  - Full table: macOS, iOS, watchOS, tvOS, visionOS, Linux, Android
  - What works where (SwiftUI wrappers are Apple-only)

## Current Limitations
  - Single-process only
  - Nested Codable types not queryable via KeyPath
  - Password minimum 8 characters
  - Android is best-effort CI

## CLI Tools
  - BlazeDoctor, BlazeDump, BlazeInfo

## Learn More
  - Links to docs, architecture, getting started guide

## Community
  - Contributing, CoC, Security, License

## Roadmap / Future Work
  - Distributed sync (deferred)
  - Full telemetry (conditional)
  - RLS (infrastructure exists, not default)
```

**Rationale:** The current README front-loads internal durability details before a new user understands the basic model. The restructure puts "what is this" and "how do I use it" first, architectural details in linked docs, and honest limitations before the fold.

---

## 7. Rewrite Plan

### Delete entirely:
- "Default durability (BlazeDBClient)" section — move to `Docs/Architecture/DURABILITY.md` or link to existing `Docs/Status/DURABILITY_MODE_SUPPORT.md`
- The long paragraph about HMAC signing, NDJSON logs, and legacy sidecar files
- The note about distributed sync / telemetry / RLS in the "What You Get" section (move to a "Roadmap" section at the bottom)

### Rewrite:
- Version number: 2.7.2 → 2.7.3
- Install snippet version: `from: "2.7.2"` → `from: "2.7.3"`
- Quick Start: align with HelloBlazeDB or vice versa; show a coherent single example
- API Tiers table: fix `BlazeDocument` description; add note about `@BlazeQueryTyped` constraint
- Platform badge: add watchOS, tvOS, visionOS
- "Product Focus" section: replace with "What BlazeDB Is / Is Not"

### Add new sections:
- "What BlazeDB Is (and Is Not)"
- "Core Concepts" with single-collection architecture explanation
- "Current Limitations" (single-process, nested Codable, password length)
- "`BlazeStorable` vs `BlazeDocument`" comparison
- Full `TypedStore` API summary (not just insert/fetchAll)

### Claims needing proof or removal:
- "Sub-millisecond reads" — either link to reproducible benchmark results or remove
- "Schema-less document storage with typed queries" — accurate but needs the single-collection caveat

---

## 8. Code Evidence Appendix

### Protocols
| Symbol | File | Line(s) |
|--------|------|---------|
| `BlazeStorable` | `BlazeDB/Codable/CodableIntegration.swift` | 31–33 |
| `BlazeDocument` | `BlazeDB/TypeSafety/BlazeDocument.swift` | 37–48 |

### Client API
| Symbol | File | Line(s) |
|--------|------|---------|
| `BlazeDBClient` class | `BlazeDB/Exports/BlazeDBClient.swift` | 184 |
| `open(named:password:)` | `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift` | 31–38 |
| `open(at:password:)` | `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift` | 54–61 |
| `openForTesting()` | `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift` | 207–221 |
| `close()` | `BlazeDB/Exports/BlazeDBClient+Lifecycle.swift` | 29–80 |
| `typed(_:)` | `BlazeDB/Codable/TypedStore.swift` | 144–146 |

### TypedStore
| Symbol | File | Line(s) |
|--------|------|---------|
| `TypedStore<T>` struct | `BlazeDB/Codable/TypedStore.swift` | 44 |
| `insert(_:)` | `BlazeDB/Codable/TypedStore.swift` | 55–56 |
| `fetchAll()` | `BlazeDB/Codable/TypedStore.swift` | 73–74 |
| `fetch(_:)` | `BlazeDB/Codable/TypedStore.swift` | 68–69 |
| `update(_:)` | `BlazeDB/Codable/TypedStore.swift` | 80–81 |
| `upsert(_:)` | `BlazeDB/Codable/TypedStore.swift` | 93–94 |
| `delete(_:)` | `BlazeDB/Codable/TypedStore.swift` | 100–101 |
| `query()` | `BlazeDB/Codable/TypedStore.swift` | 114–116 |
| `count()` | `BlazeDB/Codable/TypedStore.swift` | 121–123 |

### Storage Engine
| Symbol | File |
|--------|------|
| `PageStore` | `BlazeDB/Storage/PageStore.swift` |
| `WALMode` enum | `BlazeDB/Storage/PageStore.swift` |
| `WriteAheadLog` | `BlazeDB/Storage/WriteAheadLog.swift` |
| `DurabilityManager` | `BlazeDB/Storage/DurabilityManager.swift` |
| `RecoveryManager` | `BlazeDB/Storage/RecoveryManager.swift` |
| `DynamicCollection` | `BlazeDB/Core/DynamicCollection.swift` |

### Indexes
| Symbol | File |
|--------|------|
| `BTreeIndex` / `BTreeIndexManager` | `BlazeDB/Storage/BTreeIndex.swift` |
| `InvertedIndex` | `BlazeDB/Storage/InvertedIndex.swift` |
| `VectorIndex` | `BlazeDB/Storage/VectorIndex.swift` |
| `SpatialIndex` | `BlazeDB/Storage/SpatialIndex.swift` |
| `CompoundIndexKey` | `BlazeDB/Core/CompoundIndexKey.swift` |
| `FullTextSearchEngine` | `BlazeDB/Query/FullTextSearch.swift` |

### Encryption / Security
| Symbol | File |
|--------|------|
| `_encryptPageBuffer` | `BlazeDB/Storage/PageStore.swift` |
| `KeyManager.getKey` | `BlazeDB/Crypto/KeyManager.swift` |
| `StorageLayout.SecureLayout` | `BlazeDB/Storage/StorageLayout+Security.swift` |

### MVCC
| Symbol | File |
|--------|------|
| `setMVCCEnabled` / `isMVCCEnabled` | `BlazeDB/Exports/BlazeDBClient+MVCC.swift` |
| `MVCCTransaction` | `BlazeDB/Core/MVCC/MVCCTransaction.swift` |
| `VersionManager` | `BlazeDB/Core/MVCC/RecordVersion.swift` |

### SwiftUI
| Symbol | File |
|--------|------|
| `@BlazeQuery` | `BlazeDB/SwiftUI/BlazeQuery.swift` |
| `@BlazeQueryTyped` | `BlazeDB/SwiftUI/BlazeQueryTyped.swift` |
| `ChangeObservation.observe` | `BlazeDB/Core/ChangeObservation.swift:257` |

### Examples
| Path | Purpose |
|------|---------|
| `Examples/HelloBlazeDB/main.swift` | Full typed + raw API demo |
| `Examples/BasicExample/` | Basic example target |
| `Examples/ReferenceConsumer/` | SPM consumer reference |

### Tests (selected)
| Path | What it tests |
|------|---------------|
| `BlazeDBTests/Tier0Core/Durability/` | WAL replay, transaction durability |
| `BlazeDBTests/Tier0Core/Gate/ImportExportTests.swift` | Import/export correctness |
| `BlazeDBTests/Tier1Core/Transactions/` | Transaction semantics |
| `BlazeDBTests/Tier1Core/MVCC/` | MVCC foundation |
| `BlazeDBTests/Tier1Core/Security/EncryptionRoundTripVerificationTests.swift` | Encryption correctness |
| `Tests/CrashRecoveryHarness/` | Kill -9 crash recovery |
| `BlazeDBBenchmarks/main.swift` | Insert/read/delete throughput |

### Package Manifest
| Item | Value | File |
|------|-------|------|
| Swift tools version | 6.0 | `Package.swift:1` |
| Platforms | macOS 15, iOS 15, watchOS 8, tvOS 15, visionOS 1 | `Package.swift:6-12` |
| External deps | `swift-crypto 3.0.0+` (Linux/Android only) | `Package.swift:50` |
| Products | BlazeDB, BlazeDBCore, BlazeShell, BasicExample, BlazeDoctor, BlazeDump, BlazeInfo, BlazeDBBenchmarks, HelloBlazeDB, ReferenceConsumer | `Package.swift:14-45` |
