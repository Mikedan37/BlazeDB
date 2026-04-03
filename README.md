# BlazeDB

**Version:** 2.7.2
**Status:** Core modules Swift 6 strict concurrency compliant
**License:** MIT

An encrypted embedded document store for Swift — designed for application state, indexed metadata, and deterministic recovery.

**ACID transactions, AES-256-GCM encryption, no external service dependencies.**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Mikedan37/BlazeDB)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Product Focus (Current OSS Release)

BlazeDB is positioned as a **high-confidence embedded encrypted database** for Swift apps:

- Typed-first developer workflow (`BlazeStorable` + `db.typed(T.self)`)
- WAL-backed durability and crash recovery
- Deterministic import/export/verify/restore workflows
- Practical operator tooling (`health`, `stats`, `BlazeDoctor`, `BlazeDump`, `BlazeInfo`)
- SwiftUI query wrappers that can refresh from DB change notifications

### Shipped by default vs conditional/deferred

| Area | Status |
|------|--------|
| Embedded encrypted core, typed API, query/transactions, durability/recovery, import/export, health/stats, CLI tools | **Shipped by default** |
| Raw/manual APIs, migrations, schema validation, indexing/full-text, benchmark tooling | **Advanced but supported** |
| Distributed sync/server/discovery, full telemetry manager path, row-level security policy surfaces, staging modules | **Conditional, internal, or deferred** |

> Source-present code does not always mean default-shipped runtime behavior. The default SwiftPM OSS product is `BlazeDBCore`/`BlazeDB` as defined by `Package.swift`.

---

## 60-Second Quick Start

```swift
import BlazeDB

// 1. Define your model
struct User: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var role: String
}

// 2. Open + get a typed store
let db = try BlazeDBClient.open(named: "myapp", password: "MyApp-Password-2026A!")
let users = db.typed(User.self)

// 3. Insert, query, done
try users.insert(User(name: "Alice", role: "engineer"))

let everyone = try users.fetchAll()
print("Users: \(everyone.count)")

try db.close()
```

If this runs, BlazeDB is working. [Next: HelloBlazeDB example](Examples/HelloBlazeDB/)

### New here? Start with this path

1. **Run the 60-second quick start** above (or `swift run HelloBlazeDB` from this repo).
2. **Explore `Examples/HelloBlazeDB/`** — typed insert → query → fetch → export → health → close.
3. **Read `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`** for the complete guide (schema, queries, backups, health, sharp edges).

### API Tiers

| Tier | API | Best for |
|------|-----|----------|
| **Typed (recommended)** | `BlazeStorable` + `db.typed(T.self)` | Most apps — Codable models, KeyPath queries |
| **Raw explicit** | `BlazeDataRecord` + `db.insert(record)` | Dynamic schemas, migration scripts |
| **Manual mapping** | `BlazeDocument` | Custom serialization, non-Codable types |

---

## Install

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.2")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

Or in Xcode: File → Add Package Dependencies → paste the URL.

---

## What You Get

- ACID transactions with WAL-based crash recovery
- Always-on AES-256-GCM encryption
- Schema-less document storage with typed queries
- Sub-millisecond reads, no external service dependencies
- SwiftUI-friendly query wrappers (`@BlazeQuery`, `@BlazeQueryTyped`) with change-observation refresh

### SwiftUI Query Observation

BlazeDB includes change observation primitives plus SwiftUI query wrappers. In SwiftUI apps, wrappers can re-run queries after database write notifications so list UIs stay current without timer-only polling.

```swift
@BlazeQueryTyped(
    db: AppDatabase.shared.db,
    type: Bug.self,
    where: "status", equals: .string("open"),
    sortBy: "priority", descending: true
)
var openBugs: [Bug]
```

### Default durability (BlazeDBClient)

- **Binary WAL:** The default client path uses `PageStore` with `WALMode.legacy` and a page-level binary `WriteAheadLog` before writes hit the main data file. Crash recovery replays that WAL during `PageStore` initialization (see `Docs/Status/DURABILITY_MODE_SUPPORT.md`).
- **Unified WAL:** An optional `WALMode.unified` path exists for callers that construct `PageStore` explicitly; it is **not** selected by `BlazeDBClient`’s default initializer.
- **NDJSON transaction logs:** High-level NDJSON transaction logs are **not** part of normal document durability for the client API; obsolete legacy sidecar files may be removed on open.

BlazeDB encrypts data and overflow pages at rest using AES-GCM, and the page-level write-ahead log stores only those encrypted page frames. Metadata is HMAC-signed for tamper detection but remains in plaintext, and rollback to older valid snapshots is not cryptographically prevented. Legacy NDJSON transaction logs are not used by the default `BlazeDBClient` path and, when present from older or advanced tooling (`BlazeDBManager`, legacy page-level `BlazeTransaction`), are plaintext artifacts that should be treated as sensitive cleartext.

> **Note:** Distributed sync and transport-backed features are deferred for the default OSS runtime. Telemetry APIs are available in-core, but full telemetry behavior is build-configuration dependent (core builds can use stub/no-op telemetry behavior).
>
> Row-level security (RLS) policy infrastructure exists in source, but full public CRUD/query enforcement is not the default supported behavior in this release.

---

## Learn More

| Resource | Description |
|----------|-------------|
| [Getting Started Guide](Docs/GettingStarted/README.md) | Step-by-step setup in 5 minutes |
| [Complete Reference](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) | Migrations, backups, health checks |
| [Examples](Examples/) | Working code for common patterns |
| [Linux Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md) | Linux-specific setup |
| [Design overview (Medium, March 2026, updated)](https://medium.com/@DanylchukStudiosLLC/blazedb-a-swift-native-embedded-application-database-c0c762dee311) | Narrative architecture and durability overview; see this repo’s `Docs/` and `Docs/Benchmarks/` for current guarantees and measurements |

---

## Community

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)

---

## Documentation

- [Docs Index](Docs/README.md)
- [Developer Guide](Docs/DEVELOPER_GUIDE.md)
- [API Reference](Docs/API/API_REFERENCE.md)
- [Compatibility Matrix](Docs/COMPATIBILITY.md)
- [Durability Mode Support Policy](Docs/Status/DURABILITY_MODE_SUPPORT.md)
- [Key Management and Compatibility Modes](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)
- [Legacy Layout Migration Guidance](Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md)
- [Distributed Transport Deferred Status](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Architecture](Docs/Architecture/)
- [Performance](Docs/Performance/)

### Maintainer Docs

- [Open-Source Readiness Checklist](Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md) (hosted CI expectations and local validation)
- [CI and Test Tiers](Docs/Testing/CI_AND_TEST_TIERS.md)
- [Release Rollback Procedure](Docs/Status/RELEASE_ROLLBACK.md)
- [Cross-Version Compatibility Harness](Docs/Status/COMPATIBILITY_HARNESS.md)
- [OSS Core Build Excludes](Docs/Contributing/OSS_CORE_BUILD_EXCLUDES.md)
- [External Security Review Plan](Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md)

> **Note:** This repository also includes `BlazeStudio/`, an optional, experimental visual companion app built on
> BlazeDB. It is **not required** to use the core embedded database engine and is less battle-tested than the core
> library.

**Requirements:** Swift 6.0+, macOS 15+ / iOS 15+ / Linux (core engine supported; automated CI validation is lighter than on macOS — see [Linux guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md) and [Compatibility](Docs/COMPATIBILITY.md))

### Security and Benchmark Mode Note

BlazeDB is encryption-on by default. The benchmark-only flag `BLAZEDB_BENCHMARK_NO_ENCRYPTION` is for performance isolation and must not be used with production data.

**License:** MIT
