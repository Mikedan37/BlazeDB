# BlazeDB

**Embedded database for Swift with ACID transactions, encryption, and schema-less storage.**

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Mikedan37/BlazeDB)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-907+-green.svg)](https://github.com/Mikedan37/BlazeDB)

BlazeDB is a page-based embedded database designed for predictable performance and operational simplicity. It provides ACID transaction guarantees, multi-version concurrency control, and per-page encryption using AES-256-GCM.

## Features

- **🔒 Encryption by Default** - AES-256-GCM per-page encryption with Argon2id key derivation
- **⚡ High Performance** - Sub-millisecond queries, linear scaling with cores
- **🔄 ACID Transactions** - Full atomicity, consistency, isolation, durability
- **📊 Rich Query API** - Fluent DSL with automatic index selection
- **🔍 Full-Text Search** - Inverted index with 50-1000× performance improvements
- **🌐 Distributed Sync** - Secure multi-node synchronization with ECDH key exchange
- **📱 SwiftUI Integration** - `@BlazeQuery` property wrapper for reactive views
- **🚀 Zero Dependencies** - Pure Swift, no external packages
- **📈 MVCC** - Multi-version concurrency control for snapshot isolation
- **🛡️ Row-Level Security** - Fine-grained access control policies

## Quick Start

### Installation

**Swift Package Manager:**

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

## Documentation

- **[Getting Started Guide](Docs/Guides/README.md)** - Step-by-step tutorials
- **[API Reference](Docs/API/)** - Complete API documentation
- **[Architecture Overview](Docs/Architecture/)** - System design and internals
- **[Security Guide](Docs/Security/README.md)** - Encryption and security model
- **[Performance Guide](Docs/Performance/README.md)** - Benchmarks and optimization
- **[Sync Documentation](Docs/Sync/README.md)** - Distributed synchronization

## Example Projects

See the [Examples/](Examples/) directory for complete working examples:

- Basic CRUD operations
- Query building and filtering
- SwiftUI integration
- Distributed sync
- Migration from SQLite/Core Data

## Requirements

- Swift 5.9+
- macOS 12+ / iOS 15+ / Linux
- Xcode 15+ (for macOS/iOS development)

## Architecture

BlazeDB uses a layered architecture:

- **Application Layer** - Public APIs and SwiftUI integration
- **Query Layer** - Query builder, optimizer, and index management
- **MVCC Layer** - Multi-version concurrency control
- **Storage Layer** - Page-based storage with WAL
- **Encryption Layer** - AES-256-GCM per-page encryption
- **Network Layer** - Distributed sync with BlazeBinary protocol

See [Architecture Documentation](Docs/Architecture/) for detailed information.

## Performance

Typical performance on Apple M4 Pro:

- **Insert**: 1,200–2,500 ops/sec (0.4–0.8ms latency)
- **Fetch**: 2,500–5,000 ops/sec (0.2–0.4ms latency)
- **Query**: 200–500 queries/sec (2–5ms latency)
- **Batch Insert**: 3,300–6,600 ops/sec (15–30ms for 100 records)

See [Performance Documentation](Docs/Performance/README.md) for detailed benchmarks.

## Security

- **Encryption**: AES-256-GCM per-page encryption
- **Key Derivation**: Argon2id + HKDF
- **Secure Enclave**: Hardware-backed key storage (iOS/macOS)
- **Network Security**: ECDH P-256 key exchange with perfect forward secrecy
- **Threat Model**: Comprehensive security analysis

See [Security Documentation](Docs/Security/README.md) and [Cryptographic Architecture](README.md#cryptographic-architecture) for details.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

BlazeDB is released under the MIT License. See [LICENSE](LICENSE) for details.

## Status

**Current Version**: 2.5.0-alpha

BlazeDB is in active development. The on-disk format is stable, but APIs may evolve during the alpha period. See [Versioning & Stability](README.md#versioning--stability) for details.

## Links

- [GitHub Repository](https://github.com/Mikedan37/BlazeDB)
- [Documentation](Docs/MASTER_DOCUMENTATION_INDEX.md)
- [Issue Tracker](https://github.com/Mikedan37/BlazeDB/issues)
- [Contributing Guide](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

---

For detailed technical documentation, architecture deep-dives, and advanced usage, see the [complete README](README.md) or browse the [documentation index](Docs/MASTER_DOCUMENTATION_INDEX.md).

