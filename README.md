# BlazeDB

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

### Basic Usage

```swift
import BlazeDB

// Create or open a database
let db = try BlazeDBClient(
    name: "MyApp",
    password: "your-secure-password"
)

// Insert a record
let record = BlazeDataRecord([
    "title": .string("Hello, BlazeDB!"),
    "count": .int(42),
    "active": .bool(true)
])
let id = try db.insert(record)

// Query records
let results = try db.query()
    .where("active", equals: .bool(true))
    .orderBy("count", descending: true)
    .limit(10)
    .execute()
    .records

// Use in SwiftUI
struct ItemListView: View {
    @BlazeQuery(db: db, where: "active", equals: .bool(true))
    var items
    
    var body: some View {
        List(items) { item in
            Text(item.string("title") ?? "")
        }
    }
}
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

## License

BlazeDB is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
