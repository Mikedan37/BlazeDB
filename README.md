# BlazeDB

**Version:** 0.1.0 (Pre-User Hardening Release)  
**Status:** Core modules Swift 6 strict concurrency compliant  
**License:** [Your License]

BlazeDB is a Swift database with explicit trust features: query ergonomics, schema migrations, verifiable backups, and operational confidence.

**Embedded database for Swift with ACID transactions, encryption, and schema-less storage.**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Mikedan37/BlazeDB)
[![CI](https://img.shields.io/badge/CI-Passing-green.svg)](https://github.com/Mikedan37/BlazeDB/actions)
[![Encryption](https://img.shields.io/badge/Encryption-AES--256--GCM-blue.svg)](Docs/Security/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## What is BlazeDB?

BlazeDB is a page-based embedded database for Swift applications with ACID transactions, MVCC, and per-page encryption.

**Differentiator:** Storage engine, sync protocol, and binary format are designed as a single vertically-integrated system, eliminating impedance mismatches between components.

---

## Why BlazeDB Exists

BlazeDB combines MVCC concurrency control, write-ahead logging, operation-log synchronization, and a custom binary protocol in a single Swift-native package. This vertical integration eliminates the overhead and complexity of combining separate storage, sync, and encoding components.

---

## Key Features

- **ACID Transactions** - Write-ahead logging with crash recovery
- **Encryption by Default** - AES-256-GCM per-page encryption
- **MVCC** - Snapshot isolation with concurrent readers and writers
- **Swift-Native API** - Fluent query builder with automatic index selection
- **Predictable Performance** - Sub-millisecond queries, linear scaling
- **Backup & Restore** - Full database backup with metadata preservation
- **Distributed Sync** - Multi-node synchronization with ECDH key exchange
- **SwiftUI Integration** - `@BlazeQuery` property wrapper
- **Zero Dependencies** - Pure Swift

---

## Quick Start

### Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.0")
]
```

### Try It Now (Zero Configuration)

**Run the example:**
```bash
swift run HelloBlazeDB
```

This demonstrates: Open → Insert → Query → Export → Close

**If you don't know which method to use, use `openDefault()`. It's the recommended entry point.**

```swift
import BlazeDB

// Open database with defaults (automatic path, encryption enabled)
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password")

// Insert a record
let id = try db.insert(BlazeDataRecord(["name": .string("Alice")]))

// Query records
let results = try db.query()
    .where("name", equals: .string("Alice"))
    .execute()
    .records

// That's it! No configuration needed.
```

**Preset methods for specific use cases:**
- `openForCLI()` - Command-line tools
- `openForDaemon()` - Server processes (Vapor, daemons)
- `openForTesting()` - Tests (uses temporary directory)

**Platform Defaults:**
- **macOS:** `~/Library/Application Support/BlazeDB/mydb.blazedb`
- **Linux:** `~/.local/share/blazedb/mydb.blazedb`

Directories are created automatically. Encryption is enabled by default.

**New to BlazeDB?** Start with the [How to Use BlazeDB](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) guide - it's copy-paste friendly and gets you running in minutes.

**Linux Users:** See [Linux Getting Started Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md) for Linux-specific setup and examples.

Or in Xcode: **File → Add Package Dependencies** → paste the repository URL.

### Example 1: Basic CRUD (Simplest Way)

```swift
import BlazeDB

// Open database with defaults (zero configuration)
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password-123")

// Insert a record
let id = try db.insert(BlazeDataRecord([
    "name": .string("Alice"),
    "age": .int(30),
    "active": .bool(true)
]))

// Fetch by ID
if let record = try db.fetch(id: id) {
    print(record.string("name") ?? "Unknown")  // "Alice"
}

// Update
try db.update(id: id, with: BlazeDataRecord([
    "name": .string("Alice Updated"),
    "age": .int(31),
    "active": .bool(true)
]))

// Delete
try db.delete(id: id)
```

### Example 2: Query with Filters

```swift
import BlazeDB

// Open with defaults
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password-123")

// Insert sample data
try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30), "role": .string("admin")]))
try db.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25), "role": .string("user")]))
try db.insert(BlazeDataRecord(["name": .string("Charlie"), "age": .int(35), "role": .string("admin")]))

// Query: Find all admins over 30
let results = try db.query()
    .where("role", equals: .string("admin"))
    .where("age", greaterThan: .int(30))
    .orderBy("age", descending: true)
    .execute()
    .records

for record in results {
    print("\(record.string("name") ?? ""): \(record.int("age") ?? 0)")
}
// Output: Charlie: 35
```

### Example 3: Batch Operations

```swift
import BlazeDB

// Open with defaults
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password-123")

// Batch insert
let records = (1...100).map { i in
    BlazeDataRecord([
        "id": .int(i),
        "name": .string("Item \(i)"),
        "value": .double(Double(i) * 1.5)
    ])
}
let ids = try db.insertBatch(records)
print("Inserted \(ids.count) records")

// Batch fetch
let allRecords = try db.fetchAll()
print("Total records: \(allRecords.count)")

// Batch update (update all records)
for record in allRecords {
    if let id = record.id {
        try db.update(id: id, with: BlazeDataRecord([
            "updated": .bool(true),
            "timestamp": .date(Date())
        ]))
    }
}

// Get statistics
let stats = try db.stats()
print("Pages: \(stats.pageCount), Records: \(stats.recordCount), Indexes: \(stats.indexCount)")
```

---

## When to Use BlazeDB

**Use BlazeDB when:**
- Building Swift applications requiring encryption by default
- Need ACID transactions with predictable performance
- Want schema-less storage without migrations
- Building local-first apps with multi-device sync

**Use alternatives when:**
- Need SQL compatibility or complex joins (SQLite)
- Require maximum raw performance for simple key-value (LMDB)
- Building non-Swift applications (Realm, WatermelonDB)
- Need battle-tested stability for critical systems (SQLite)
- Need multi-process concurrent access (BlazeDB enforces exclusive process-level locking)

---

## Documentation

**Start here:**
- **[Usage by Task](Docs/Guides/USAGE_BY_TASK.md)** - Common tasks and APIs (start here)
- **[Getting Started](Docs/GettingStarted/)** - Getting started guides
- **[Linux Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md)** - Linux-specific setup

**Architecture & Design:**
- **[Architecture](Docs/Architecture/)** - System layers, storage engine, MVCC, query execution
- **[Extension Points](Docs/Architecture/EXTENSION_POINTS.md)** - Where to extend BlazeDB
- **[Security](Docs/Security/)** - Encryption model, threat model, cryptographic pipelines
- **[Performance](Docs/Performance/)** - Benchmarks, methodology, performance invariants
- **[Transactions](Docs/Features/TRANSACTIONS.md)** - WAL, ACID guarantees, crash recovery
- **[Protocol](Docs/Design/PROTOCOL.md)** - BlazeBinary format, encoding rules, determinism

**Guides:**
- **[Running in Servers](Docs/Guides/RUNNING_IN_SERVERS.md)** - Vapor/server integration
- **[Anti-Patterns](Docs/Guides/ANTI_PATTERNS.md)** - What NOT to do
- **[Why Not SQLite](Docs/GettingStarted/WHY_NOT_SQLITE.md)** - Comparisons and tradeoffs

See the [documentation index](Docs/MASTER_DOCUMENTATION_INDEX.md) for complete API reference.

---

## Requirements

- Swift 5.9+
- macOS 12+ / iOS 15+ / Linux
- Xcode 15+ (for macOS/iOS development)

---

## Status

**Current Version:** 0.1.0 (Pre-User Hardening Release)

Core modules are Swift 6 strict concurrency compliant. On-disk format is stable. APIs are stable for core CRUD, query builder, statistics, health, migrations, and import/export.

---

## Compatibility

**Core Modules:** Swift 6 strict concurrency compliant  
**Distributed Modules:** Not yet compliant (excluded from core)

See [Compatibility](Docs/COMPATIBILITY.md) for detailed compatibility information.

## API Stability

**Stable APIs:** Core CRUD, query builder, statistics, health, migrations, import/export  
**Experimental APIs:** Distributed sync, advanced queries, telemetry

See [API Stability](Docs/API_STABILITY.md) for detailed API stability information.

## Support

**Early Adopter Phase:** Limited support for selected early adopters  
**Response Times:** Critical (24h), High (48h), Medium (1 week), Low (2 weeks)

See [Support Policy](Docs/SUPPORT_POLICY.md) for detailed support information.

## Documentation

- **[Query Performance](Docs/GettingStarted/QUERY_PERFORMANCE.md)** - Query performance and best practices
- **[Operational Confidence](Docs/GettingStarted/OPERATIONAL_CONFIDENCE.md)** - Health monitoring and when to investigate
- **[Pre-User Hardening](Docs/Compliance/PRE_USER_HARDENING.md)** - Complete trust envelope documentation
- **[Concurrency Compliance](Docs/Compliance/CONCURRENCY_COMPLIANCE.md)** - Swift 6 concurrency status
- **[Compatibility](Docs/COMPATIBILITY.md)** - Platform and API compatibility
- **[API Stability](Docs/API_STABILITY.md)** - API stability policy
- **[Support Policy](Docs/SUPPORT_POLICY.md)** - Support policy and expectations
- **[Getting Started](Docs/GettingStarted/)** - Getting started guides
- **[Linux Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md)** - Linux-specific setup

## License

BlazeDB is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick start:**
- Run `swift run HelloBlazeDB` to see it work
- Read `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md` for usage
- Check `Docs/Status/ADOPTION_READINESS.md` for what BlazeDB is good for
- See `Docs/Guarantees/SAFETY_MODEL.md` for safety guarantees
