# BlazeDB

**Version:** 0.1.0 (Pre-User Hardening Release)  
**Status:** Core modules Swift 6 strict concurrency compliant ✅  
**License:** [Your License]

BlazeDB is a Swift database with explicit trust features: query ergonomics, schema migrations, verifiable backups, and operational confidence.

**Embedded database for Swift with ACID transactions, encryption, and schema-less storage.**

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Mikedan37/BlazeDB)
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
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.5.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repository URL.

### Example 1: Basic CRUD (30 seconds)

```swift
import BlazeDB

// Create or open a database
let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("mydb.blazedb")
let db = try BlazeDBClient(name: "MyApp", fileURL: dbURL, password: "secure-password-123")

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

### Example 2: Query with Filters (1 minute)

```swift
import BlazeDB

let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("mydb.blazedb")
let db = try BlazeDBClient(name: "MyApp", fileURL: dbURL, password: "secure-password-123")

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

### Example 3: Batch Operations (1 minute)

```swift
import BlazeDB

let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("mydb.blazedb")
let db = try BlazeDBClient(name: "MyApp", fileURL: dbURL, password: "secure-password-123")

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

- **[Architecture](Docs/ARCHITECTURE.md)** - System layers, storage engine, MVCC, query execution
- **[Security](Docs/SECURITY.md)** - Encryption model, threat model, cryptographic pipelines
- **[Performance](Docs/PERFORMANCE.md)** - Benchmarks, methodology, performance invariants
- **[Transactions](Docs/TRANSACTIONS.md)** - WAL, ACID guarantees, crash recovery
- **[Protocol](Docs/PROTOCOL.md)** - BlazeBinary format, encoding rules, determinism
- **[Why Not SQLite](Docs/WHY_NOT_SQLITE.md)** - Comparisons and tradeoffs
- **[Compression Design](Docs/COMPRESSION_DESIGN.md)** - Compression strategy (optional, opt-in)
- **[Snapshot Sync Design](Docs/SNAPSHOT_SYNC_DESIGN.md)** - Snapshot-based initial sync (design only, not implemented)

See the [documentation index](Docs/MASTER_DOCUMENTATION_INDEX.md) for API reference, guides, and examples.

---

## Requirements

- Swift 5.9+
- macOS 12+ / iOS 15+ / Linux
- Xcode 15+ (for macOS/iOS development)

---

## Status

**Current Version:** 2.5.0-alpha

On-disk format is stable. APIs may evolve during the alpha period.

---

## Compatibility

**Core Modules:** ✅ Swift 6 strict concurrency compliant  
**Distributed Modules:** ⚠️ Not yet compliant (excluded from core)

See `COMPATIBILITY.md` for detailed compatibility information.

## API Stability

**Stable APIs:** Core CRUD, query builder, statistics, health, migrations, import/export  
**Experimental APIs:** Distributed sync, advanced queries, telemetry

See `API_STABILITY.md` for detailed API stability information.

## Support

**Early Adopter Phase:** Limited support for selected early adopters  
**Response Times:** Critical (24h), High (48h), Medium (1 week), Low (2 weeks)

See `SUPPORT_POLICY.md` for detailed support information.

## Documentation

- `QUERY_PERFORMANCE.md` - Query performance and best practices
- `OPERATIONAL_CONFIDENCE.md` - Health monitoring and when to investigate
- `PRE_USER_HARDENING.md` - Complete trust envelope documentation
- `CONCURRENCY_COMPLIANCE.md` - Swift 6 concurrency status
- `COMPATIBILITY.md` - Platform and API compatibility
- `API_STABILITY.md` - API stability policy
- `SUPPORT_POLICY.md` - Support policy and expectations

## License

BlazeDB is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
