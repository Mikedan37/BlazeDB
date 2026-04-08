# BlazeDB

**Version:** 2.7.4 &nbsp;|&nbsp; **License:** MIT &nbsp;|&nbsp; **Swift 6 strict concurrency compliant**

An encrypted, embedded document database for Swift. Single-process, zero external dependencies. Production runtime is always encrypted at rest.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS%20%7C%20visionOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg)](Docs/COMPATIBILITY.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## What BlazeDB Is

- An **embedded** database — runs in your process, no server required
- **Encrypted at rest** in production — AES-256-GCM on every data page
- **Document-oriented** — schema-less records with typed Codable overlays
- **ACID transactions** with WAL-backed crash recovery
- **Single-process** — one process owns the database file at a time
- **Single-collection** — all records (regardless of type) share one encrypted collection per database file; `TypedStore` is a typed lens, not a separate table

## What BlazeDB Is Not

- **Not SQL.** No relational schema, no SQL query language.
- **Not multi-process.** One process owns the database file. No concurrent access from separate processes.
- **Not client/server.** No network listener, no remote connections.
- **Not per-type table storage.** All record types coexist in a single encrypted collection.
- **Not distributed sync.** Sync infrastructure exists in source but is deferred and excluded from the default runtime.

### API tiers

| Tier | API | Use case |
|------|-----|----------|
| **Typed (recommended)** | `BlazeStorable` + `db.typed(T.self)` | Codable models, KeyPath queries |
| **Raw** | `BlazeDataRecord` + `db.insert(record)` | Dynamic schemas, migrations |
| **Manual mapping** | `BlazeDocument` | Custom storage control, `@BlazeQueryTyped` |

---

## Quick Start

Run the included example directly from this repository:

```bash
swift run HelloBlazeDB
```

Or add BlazeDB to your own project and use this minimal example:

```swift
import BlazeDB

struct User: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var age: Int
    var active: Bool
}

let db = try BlazeDBClient.open(named: "myapp", password: "MyApp-Password-2026A!")
let users = db.typed(User.self)

// Insert
try users.insert(User(name: "Alice", age: 30, active: true))

// Query with KeyPaths
let activeUsers = try users.query()
    .where(\.active, equals: true)
    .all()

// Fetch all
let everyone = try users.fetchAll()
print("Users: \(everyone.count)")

try db.close()
```

### Getting started path

1. **Run `swift run HelloBlazeDB`** from this repo to verify your environment.
2. **Read [Examples/HelloBlazeDB/main.swift](Examples/HelloBlazeDB/main.swift)** — covers typed insert, KeyPath query, fetch, raw API, export, health, and close.
3. **Read [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md)** for the complete guide.

---

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.4")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

Or in Xcode: **File → Add Package Dependencies** → paste `https://github.com/Mikedan37/BlazeDB.git`.

**Requirements:** Swift 6.0+, macOS 15+ / iOS 15+ / watchOS 8+ / tvOS 15+ / visionOS 1+ / Linux / Android

---

## Core Concepts

### Single-collection architecture

BlazeDB stores all records in one encrypted document collection per database file. When you call `db.typed(User.self)`, you get a typed lens (a `TypedStore<User>`) — not a separate physical table. The typed store encodes/decodes through the `BlazeStorable` Codable bridge and filters records by decodability.

### Two typed protocols

| Protocol | Purpose | Used with |
|----------|---------|-----------|
| **`BlazeStorable`** | Automatic Codable serialization, KeyPath queries | `TypedStore`, `db.typed(T.self)` |
| **`BlazeDocument`** | Manual `toStorage()`/`init(from:)` mapping, more control | `@BlazeQueryTyped` SwiftUI wrapper |

`BlazeStorable` is the recommended starting point. `BlazeDocument` is for when you need manual control over how your model maps to `BlazeDataRecord` storage. Both require `Codable` and `Identifiable` with `ID == UUID`.

> **`BlazeDocument` persistence:** Prefer `try model.toStorage()` or `try model.resolveStorage()` (or typed client APIs like `insert(model)`) when encoding can fail. The `storage` property is a **deprecated** compatibility shim: if `toStorage()` throws, it **logs** and falls back to an empty record — **do not** persist that value. Typed insert/update paths already use `toStorage()` and are unaffected.

> **Do not use `@BlazeQueryTyped` with `BlazeStorable`-only models. It will not compile.** The `@BlazeQueryTyped` SwiftUI property wrapper requires `BlazeDocument`. If your model only conforms to `BlazeStorable`, you must add `BlazeDocument` conformance (with manual `toStorage()`/`init(from:)`) before you can use it in SwiftUI typed query wrappers.

### Encryption

The production runtime is always encrypted at rest. Every data page is sealed with AES-256-GCM. A password is required to open any database (minimum 8 characters). Metadata is HMAC-SHA256 signed for tamper detection. A benchmark-only flag (`BLAZEDB_BENCHMARK_NO_ENCRYPTION`) exists for performance isolation testing but must not be used with real data.

---

## API Overview

### TypedStore (recommended)

`TypedStore<T>` provides full CRUD and query operations bound to a single `BlazeStorable` model type:

```swift
let users = db.typed(User.self)

try users.insert(user)                          // Insert one
try users.insertMany([user1, user2])             // Insert batch
let user = try users.fetch(id)                   // Fetch by UUID
let all = try users.fetchAll()                   // Fetch all
try users.update(user)                           // Update by id
try users.upsert(user)                           // Insert or update
try users.delete(id)                             // Delete by id
let count = try users.count()                    // Count all

let results = try users.query()
    .where(\.age, greaterThanOrEqual: 21)
    .orderBy(\.name, descending: false)
    .all()
```

### Raw API

For dynamic schemas or migration scripts, use `BlazeDataRecord` directly:

```swift
let record = BlazeDataRecord([
    "name": .string("Alice"),
    "age": .int(30),
    "active": .bool(true),
])
let id = try db.insert(record)

let results = try db.query()
    .where("active", equals: .bool(true))
    .execute()
    .records
```

### Opening a database

```swift
// By name (stored in platform default location)
let db = try BlazeDBClient.open(named: "myapp", password: "secure-password-123")

// At a specific file URL
let db = try BlazeDBClient.open(at: fileURL, password: "secure-password-123")

// For testing (uses temp directory)
let db = try BlazeDBClient.openForTesting()
```

Default storage locations: `~/Library/Application Support/BlazeDB/` (macOS), `~/.local/share/blazedb/` (Linux).

### SwiftUI query wrappers (Apple platforms only)

`@BlazeQuery` and `@BlazeQueryTyped` provide SwiftUI property wrappers that re-run queries when the database posts write notifications. These require Apple platforms (macOS, iOS, watchOS, tvOS).

**`@BlazeQueryTyped` requires `BlazeDocument`, not `BlazeStorable`. Using a `BlazeStorable`-only model will not compile.**

```swift
@BlazeQueryTyped(
    db: AppDatabase.shared.db,
    type: Bug.self,               // Bug must conform to BlazeDocument
    where: "status", equals: .string("open"),
    sortBy: "priority", descending: true
)
var openBugs: [Bug]
```

### Transactions

```swift
try db.beginTransaction()
try users.insert(user1)
try users.insert(user2)
try db.commitTransaction()
// Or: try db.rollbackTransaction()
```

### Utilities

```swift
let stats = try db.stats()          // Record count, database size
let health = try db.health()        // Health status + warnings
try db.export(to: exportURL)        // Export to file
let header = try BlazeDBImporter.verify(exportURL)
```

---

## Durability

The default `BlazeDBClient` uses a binary write-ahead log (`WALMode.legacy`) that fsyncs page frames before writing to the main data file. On crash, the WAL is replayed during the next `PageStore` initialization. See [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md) for details on the unified WAL mode and recovery guarantees.

---

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS 15+ | Full support | CI validated (GitHub Actions) |
| iOS 15+ | Full support | Xcode builds |
| watchOS 8+ | Builds | Declared in Package.swift; limited CI |
| tvOS 15+ | Builds | Declared in Package.swift; limited CI |
| visionOS 1+ | Builds | Declared in Package.swift; limited CI |
| Linux | Core support | Swift 6.0; CI runs Tier 0 tests; SwiftUI wrappers excluded |
| Android | Core support | `BLAZEDB_LINUX_CORE` path; Swift 6.3+ / Android NDK; best-effort CI |

SwiftUI query wrappers (`@BlazeQuery`, `@BlazeQueryTyped`) are only available on Apple platforms. On Linux and Android, the `swift-crypto` package is used in place of Apple CryptoKit.

See [Compatibility Matrix](Docs/COMPATIBILITY.md) for details.

---

## CLI Tools

| Tool | Purpose |
|------|---------|
| `BlazeDoctor` | Opens a database and runs diagnostic checks (insert/fetch/delete probe, stats, health) |
| `BlazeDump` | Export (`dump`), restore, and verify database backups |
| `BlazeInfo` | Print database stats, health, and schema version |
| `BlazeShell` | Interactive shell |

Run with `swift run <ToolName>`.

---

## Current Limitations

- **Single-process only.** Do not share database files between multiple processes. File-level locking prevents concurrent access, but the database is designed for single-process use.
- **Nested Codable types are not individually queryable.** Nested structs/classes are stored as serialized JSON strings inside `BlazeDocumentField.string`. Round-tripping works, but nested fields cannot be filtered via KeyPath queries. Flatten nested fields into top-level properties if you need to query them.
- **Password minimum 8 characters.** Enforced at open time.
- **`@BlazeQueryTyped` requires `BlazeDocument`.** It will not compile with `BlazeStorable`-only models. You must add `BlazeDocument` conformance with manual `toStorage()`/`init(from:)` implementations.
- **Android CI is best-effort.** Cross-compilation expects Swift 6.3+ with the Swift Android SDK + Android NDK in a manual lane.

---

## Advanced, Deferred, and Experimental Features

### Available but advanced / opt-in

- **MVCC (multi-version concurrency control)** — opt-in via `db.setMVCCEnabled(true)`. Provides snapshot isolation when enabled. See `BlazeDBClient+MVCC.swift`.
- **Full telemetry manager** — build-configuration dependent; core builds use stub/no-op telemetry.

### Present in source, not primary stable onboarding surfaces

- **Indexing** — B-tree, inverted (full-text), vector, and spatial index implementations exist in source. These are internal to the storage engine and do not yet have stable public creation APIs, onboarding docs, or runnable examples for end users.
- **Row-level security (RLS)** — policy infrastructure exists in source, but full CRUD/query enforcement is not enabled by default.

### Deferred / not part of default runtime

- **Distributed sync/transport** — infrastructure exists but is excluded from `BlazeDBCore`. See [Distributed Transport Status](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md).

---

## Documentation

| Resource | Description |
|----------|-------------|
| [Getting Started Guide](Docs/GettingStarted/README.md) | Step-by-step setup |
| [Complete Reference](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) | Full usage guide with queries, backups, and health checks |
| [API Reference](Docs/API/API_REFERENCE.md) | Public API documentation |
| [Examples](Examples/) | Working code (HelloBlazeDB, BasicExample, ReferenceConsumer) |
| [Linux Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md) | Linux-specific setup |
| [Developer Guide](Docs/DEVELOPER_GUIDE.md) | Contributing and development setup |
| [Architecture](Docs/Architecture/) | Storage engine and internal design |
| [Compatibility Matrix](Docs/COMPATIBILITY.md) | Platform and version support details |
| [Durability Modes](Docs/Status/DURABILITY_MODE_SUPPORT.md) | WAL modes and recovery guarantees |
| [System Map](Docs/SYSTEM_MAP.md) | Feature inventory, status, and code locations |
| [Design Overview (Medium)](https://medium.com/@DanylchukStudiosLLC/blazedb-a-swift-native-embedded-application-database-c0c762dee311) | Narrative architecture overview (March 2026) |

> **BlazeStudio:** This repository includes `BlazeStudio/`, an optional experimental visual companion app. It is not required to use the core database and is not part of the SwiftPM product.

---

## Community

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)

---

**License:** MIT
