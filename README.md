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

> **Note:** Distributed sync and telemetry features are planned for a future release. This version ships the core embedded engine only, and transport integration is intentionally gated off until a public transport dependency is reintroduced.

---

## Learn More

| Resource | Description |
|----------|-------------|
| [Getting Started Guide](Docs/GettingStarted/README.md) | Step-by-step setup in 5 minutes |
| [Complete Reference](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) | Migrations, backups, health checks |
| [Examples](Examples/) | Working code for common patterns |
| [Linux Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md) | Linux-specific setup |

---

## Documentation

- [API Reference](Docs/DEVELOPER_GUIDE.md)
- [Architecture](Docs/Architecture/)
- [Performance](Docs/Performance/)
- [Open-Source Readiness Checklist](Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md)
- [Release Rollback Procedure](Docs/Status/RELEASE_ROLLBACK.md)
- [Key Management and Compatibility Modes](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)
- [Legacy Layout Migration Guidance](Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md)
- [Durability Mode Support Policy](Docs/Status/DURABILITY_MODE_SUPPORT.md)
- [Cross-Version Compatibility Harness](Docs/Status/COMPATIBILITY_HARNESS.md)
- [Release Evidence Blockers](Docs/Status/RELEASE_EVIDENCE_BLOCKERS.md)
- [Open-Source Re-Audit (2026-03-16)](Docs/Status/OPEN_SOURCE_REAUDIT_2026-03-16.md)
- [External Security Review Plan](Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md)
- [Distributed Transport Deferred Status](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Compatibility Matrix](Docs/COMPATIBILITY.md)

**Requirements:** Swift 6.0+, macOS 15+ / iOS 15+ / Linux (experimental)

### Security and Benchmark Mode Note

BlazeDB is encryption-on by default. The benchmark-only flag `BLAZEDB_BENCHMARK_NO_ENCRYPTION` is for performance isolation and must not be used with production data.

**License:** MIT
