# BlazeDB

**Version:** 2.7.0
**Status:** Core modules Swift 6 strict concurrency compliant
**License:** MIT

An encrypted embedded document store for Swift — designed for application state, indexed metadata, and deterministic recovery.

**ACID transactions, AES-256-GCM encryption, no external service dependencies.**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Mikedan37/BlazeDB)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 60-Second Quick Start

```swift
import BlazeDB

let db = try BlazeDBClient.open(named: "myapp", password: "MyApp-Password-2026A!")

try db.insert(BlazeDataRecord(["name": .string("Alice"), "role": .string("engineer")]))

let users = try db.query().execute().records
print("Users: \(users.count)")

try db.close()
```

If this runs, BlazeDB is working. [Next: HelloBlazeDB example](Examples/HelloBlazeDB/)

### New here? Start with this path

1. **Run the 60-second quick start** above (or `swift run HelloBlazeDB` from this repo).
2. **Explore `Examples/HelloBlazeDB/`** to see an end-to-end open → insert → query → export → health → close flow using `BlazeDBClient`.
3. **Read `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`** for the complete guide (schema, queries, backups, health, sharp edges).

---

## Install

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.0")
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

### Default durability (BlazeDBClient)

- **Binary WAL:** The default client path uses `PageStore` with `WALMode.legacy` and a page-level binary `WriteAheadLog` before writes hit the main data file. Crash recovery replays that WAL during `PageStore` initialization (see `Docs/Status/DURABILITY_MODE_SUPPORT.md`).
- **Unified WAL:** An optional `WALMode.unified` path exists for callers that construct `PageStore` explicitly; it is **not** selected by `BlazeDBClient`’s default initializer.
- **NDJSON transaction logs:** High-level NDJSON transaction logs are **not** part of normal document durability for the client API; obsolete legacy sidecar files may be removed on open.

BlazeDB encrypts data and overflow pages at rest using AES-GCM, and the page-level write-ahead log stores only those encrypted page frames. Metadata is HMAC-signed for tamper detection but remains in plaintext, and rollback to older valid snapshots is not cryptographically prevented. Legacy NDJSON transaction logs are not used by the default `BlazeDBClient` path and, when present from older or advanced tooling (`BlazeDBManager`, legacy page-level `BlazeTransaction`), are plaintext artifacts that should be treated as sensitive cleartext.

> **Note:** Distributed sync and telemetry features are planned for a future release. This version ships the core embedded engine only, and transport integration is intentionally gated off until a public transport dependency is reintroduced.

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

## Documentation

- [API Reference](Docs/DEVELOPER_GUIDE.md)
- [Architecture](Docs/Architecture/)
- [Performance](Docs/Performance/)
- [Open-Source Readiness Checklist](Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md) _(internal process checklist)_
- [Release Rollback Procedure](Docs/Status/RELEASE_ROLLBACK.md)
- [Key Management and Compatibility Modes](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)
- [Legacy Layout Migration Guidance](Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md)
- [Durability Mode Support Policy](Docs/Status/DURABILITY_MODE_SUPPORT.md)
- [Tests directory layout (BlazeDBTests vs Tests/)](Docs/Testing/TESTS_DIRECTORY.md)
- [OSS core build excludes](Docs/Contributing/OSS_CORE_BUILD_EXCLUDES.md)
- [Cross-Version Compatibility Harness](Docs/Status/COMPATIBILITY_HARNESS.md)
- [Release Evidence Blockers](Docs/Archive/RELEASE_EVIDENCE_BLOCKERS.md)
- [Open-Source Re-Audit (2026-03-16)](Docs/Archive/OPEN_SOURCE_REAUDIT_2026-03-16.md)
- [External Security Review Plan](Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md)
- [Distributed Transport Deferred Status](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Compatibility Matrix](Docs/COMPATIBILITY.md)

**Requirements:** Swift 6.0+, macOS 15+ / iOS 15+ / Linux (experimental)

### Security and Benchmark Mode Note

BlazeDB is encryption-on by default. The benchmark-only flag `BLAZEDB_BENCHMARK_NO_ENCRYPTION` is for performance isolation and must not be used with production data.

**License:** MIT
