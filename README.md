# BlazeDB

**Version:** 2.7.4 &nbsp;|&nbsp; **License:** MIT &nbsp;|&nbsp; **Swift 6 strict concurrency compliant**

An encrypted, embedded document database for Swift. Single-process, zero external dependencies. Production runtime is always encrypted at rest.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS%20%7C%20visionOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg)](Docs/COMPATIBILITY.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Quick Navigation

- [Start Here (New Users)](#start-here-new-users)
- [Quick Start](#quick-start)
- [Model Nested Data (One-to-Many)](#model-nested-data-one-to-many)
- [Install](#install)
- [API Overview](#api-overview)
- [Current Limitations](#current-limitations)
- [Documentation](#documentation)

## Start Here (New Users)

If you are new, use this path first and ignore the advanced sections until you need them.

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDBClient.open(named: "demo", password: "DemoPass123!")
let bug = Bug(title: "Crash on launch", status: "open")
let bugID = try db.insert(bug)

let loaded = try db.fetch(Bug.self, id: bugID)
let openBugs = try db.query(Bug.self)
    .where(\.status, equals: "open")
    .all()
```

That is the default beginner workflow: `open -> insert -> fetch -> query`.

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
| **Default API (recommended)** | `BlazeDB.open(...)` + `db.put` / `db.get` / `db.query(namespace)` | Fastest path for most app code |
| **TypedStore (secondary)** | `db.typed(T.self)` → scoped handle | View models or service layers that want a bound store |
| **Raw (advanced)** | `BlazeDataRecord` + `db.insert(record)` | Dynamic schemas, migrations |
| **Manual mapping (advanced)** | `BlazeDocument` | Custom storage control and manual serialization |

---

## Quick Start

Run the included example directly from this repository:

```bash
swift run HelloBlazeDB
```

Or add BlazeDB to your own project and use this minimal example:

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")
let bug = Bug(title: "Crash on launch", status: "open")

try db.put(bug)

let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

### Getting started path

1. **Run `swift run HelloBlazeDB`** from this repo to verify your environment.
2. **Read [Examples/HelloBlazeDB/main.swift](Examples/HelloBlazeDB/main.swift)** — canonical `open → put → get → query` flow.
3. **Read [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md)** for the complete guide.

---

## Model Nested Data (One-to-Many)

A common use case is building a to-do list or any list with items inside it.  
For example, you might have a "Groceries" list with items like Milk and Eggs.

At first, you might think to store one big `List` object that contains `[ListItem]` inside it. That seems simpler, but it causes problems.

The easier model is:
- each `List` is its own record
- each `ListItem` is its own record
- each item stores the parent list's id in `listID`
- that shared id is the link between them

```swift
import Foundation
import BlazeDB

struct List: BlazeStorable {
    var id: UUID = UUID()
    var name: String
}

struct ListItem: BlazeStorable {
    var id: UUID = UUID()
    var listID: UUID   // ID of the parent list
    var name: String
    var isDone: Bool = false
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")

let groceries = List(name: "Groceries")
try db.put(groceries)

// Save the parent list ID once so it's obvious what links records together.
let groceriesListID = groceries.id

try db.put(ListItem(listID: groceriesListID, name: "Milk"))
try db.put(ListItem(listID: groceriesListID, name: "Eggs"))

let lists: [List] = try db.query("list").all()

let groceryItems: [ListItem] = try db.query("listitem")
    .where("listID", equals: groceriesListID)
    .all()
```

Mental model:
- `List` = parent
- `ListItem` = child
- `listID` = the link

To get the items for a list, query `listitem` where `listID` matches the list's `id`.

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

BlazeDB stores all records in one encrypted document collection per database file. All typed APIs (`db.insert(model)`, `db.typed(T.self)`, etc.) encode/decode through the `BlazeStorable` Codable bridge and filter records by decodability — they are not separate physical tables.

### Two typed protocols

| Protocol | Purpose | Used with |
|----------|---------|-----------|
| **`BlazeStorable`** | Automatic Codable serialization, KeyPath queries | `db.insert(model)`, `db.fetch(T.self, id:)`, `db.query(T.self)`, `db.typed(T.self)` |
| **`BlazeDocument`** | Manual `toStorage()`/`init(from:)` mapping, more control | `@BlazeQueryTyped` SwiftUI wrapper |

`BlazeStorable` is the recommended starting point. `BlazeDocument` is for when you need manual control over how your model maps to `BlazeDataRecord` storage. Both require `Codable` and `Identifiable` with `ID == UUID`.

> **`BlazeDocument` persistence:** Prefer `try model.toStorage()` or `try model.resolveStorage()` (or typed client APIs like `insert(model)`) when encoding can fail. The `storage` property is a **deprecated** compatibility shim: if `toStorage()` throws, it **logs** and falls back to an empty record — **do not** persist that value. Typed insert/update paths already use `toStorage()` and are unaffected.

> **Do not use `@BlazeQueryTyped` with `BlazeStorable`-only models. It will not compile.** The `@BlazeQueryTyped` SwiftUI property wrapper requires `BlazeDocument`. If your model only conforms to `BlazeStorable`, you must add `BlazeDocument` conformance (with manual `toStorage()`/`init(from:)`) before you can use it in SwiftUI typed query wrappers.

### Encryption

The production runtime is always encrypted at rest. Every data page is sealed with AES-256-GCM. A password is required to open any database (minimum 8 characters). Metadata is HMAC-SHA256 signed for tamper detection. A benchmark-only flag (`BLAZEDB_BENCHMARK_NO_ENCRYPTION`) exists for performance isolation testing but must not be used with real data.

---

## API Overview

### Default API (recommended)

Use these as the default path in app code:

```swift
let db = try BlazeDB.open(name: "myapp", password: "secure-password-123")
try db.put(user)
let loaded: User? = try db.get("user:\(user.id.uuidString)")

let activeUsers: [User] = try db.query("user")
    .where("active", equals: true)
    .all()
```

### Direct CRUD (secondary)

If you are new, use this section and skip ahead only when you need more control.
Call typed methods directly on `BlazeDBClient`:

```swift
try db.insert(user)                              // Insert one
try db.insertMany([user1, user2])                // Insert batch
let user = try db.fetch(User.self, id: userId)   // Fetch by UUID
let all = try db.fetchAll(User.self)             // Fetch all
try db.update(user)                              // Update by id
try db.upsert(user)                              // Insert or update
try db.delete(user)                              // Delete by model

let results = try db.query(User.self)
    .where(\.age, greaterThanOrEqual: 21)
    .orderBy(\.name, descending: false)
    .all()
```

## Advanced APIs (Optional)

### TypedStore

`TypedStore<T>` wraps the same operations into a scoped handle, useful when you want to pass a "users store" to a view model:

```swift
let users = db.typed(User.self)
try users.insert(user)
let all = try users.fetchAll()
```

### Raw API (advanced)

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
// By name (recommended for most apps)
let db = try BlazeDB.open(name: "myapp", password: "secure-password-123")

// At a specific file URL (when your app controls the path)
let db = try BlazeDB.open(at: fileURL, password: "secure-password-123")

// Advanced/testing utility
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
| Linux | Core support | Swift 6.2 in CI; nightly runs Tier0+Tier1, deep validation runs Tier0+Tier1+Tier2; SwiftUI wrappers excluded |
| Android | Core support | `BLAZEDB_LINUX_CORE` path; Swift 6.3+ / Android NDK; best-effort CI |

SwiftUI query wrappers (`@BlazeQuery`, `@BlazeQueryTyped`) are only available on Apple platforms. On Linux and Android, the `swift-crypto` package is used in place of Apple CryptoKit.

See [Compatibility Matrix](Docs/COMPATIBILITY.md) for details.

---

## Testing And CI

- PR/release validation on macOS runs `BlazeDB_Tier0`, `BlazeDB_Tier1`, and `BlazeDB_Tier2` as the main gate.
- Nightly confidence runs macOS Tier1/Tier2 strict/Tier3 heavy lanes plus Linux Tier0 and Tier1 lanes.
- Weekly deep validation runs broader coverage: macOS Tier0/1/2/3 + destructive + TSan, and Linux Tier0/1/2 (+ extended companion).
- Additional nightly checks verify clean checkout and README quickstart scripts.
- Entry docs for test/CI structure: `Docs/Testing/CI_AND_TEST_TIERS.md` and `Docs/Testing/README.md`.

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
- **Nested Codable types are not individually queryable.** Nested structs/classes are stored as `BlazeDocumentField.dictionary` values. Round-tripping works, but nested fields cannot be filtered via KeyPath queries. Flatten nested fields into top-level properties if you need to query them.
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
