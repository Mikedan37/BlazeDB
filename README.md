# BlazeDB

**Embedded, encrypted, single-process.** A document database for Swift with ACID transactions, WAL-backed crash recovery, and AES-256-GCM at rest. One encrypted file per database name; no standalone server and no required network calls.

*MIT · Swift 6+ · current release **2.7.5** · [Add BlazeDB to your app](#add-blazedb-to-your-app)*

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS%20%7C%20visionOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg)](Docs/COMPATIBILITY.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Quick Navigation

*Primary links; everything else (examples, API details, deeper sections) is further down.*

### How you move through this README

**Onboarding first:** read [Start Here](#start-here-new-users) for the mental model and a full copy-paste sample. After that, pick a lane:

- **Path A:** Clone, then [Try BlazeDB from this repo](#try-blazedb-from-this-repo) (`swift run HelloBlazeDB`).
- **Path B:** [Add BlazeDB to your app](#add-blazedb-to-your-app) (SwiftPM or Xcode), then reuse [that sample](#start-here-new-users), follow [SwiftUI patterns](#swiftui-path), or open the [full usage guide](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md).

### Jump to

- [Start Here](#start-here-new-users)
- [Try BlazeDB from this repo](#try-blazedb-from-this-repo)
- [Add BlazeDB to your app](#add-blazedb-to-your-app)
- [What to do next](#what-to-do-next)
- [SwiftUI path](#swiftui-path)
- [Documentation](#documentation)

## Start Here (New Users)

If you are new, use this path first and ignore the advanced sections until you need them.

**No database experience needed.** BlazeDB stores everything in **one encrypted file** per app name (`"demo"` here), like a save slot on disk, not a separate server. You describe data with ordinary Swift structs: **`put`** saves a value, **`get`** loads one item when you know its id string, **`query`** returns a list you can filter (e.g. only open bugs). Nothing is sent over the network.

**`put`** accepts either a single **`BlazeStorable`** model or a flat array of the same model type. If you need nested arrays, store them as fields inside a model rather than passing nested arrays directly to **`put`**.

Read the sample **top to bottom**: `open` → `put` → `get` → `query`.

```swift
import BlazeDB

// One Bug’s shape in Swift
struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

// Open or create the file (password encrypts it; nothing leaves your machine)
let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")
let bug = Bug(title: "Crash on launch", status: "open")
try db.put(bug)  // save

// Load by id: "bug" + this bug’s uuid
let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
// All bugs with status "open"
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

The `"bug"` in `query("bug")` is a **label for which kind of record** (bugs vs notes vs something else). It is **not** a separate table; every record still lives in **one** collection inside that file.

**Think:** one file, one collection, many labeled records.

**Recap**

| Step | What it does |
|------|----------------|
| `open` | Opens your encrypted file |
| `put` | Saves a struct |
| `get("bug:…")` | Loads one bug by id |
| `query("bug")…` | Lists or filters bugs |

Id strings look like `"bug:<uuid>"`: `bug` = kind, uuid = which one.

---

## Try BlazeDB from this repo

**Path A (repo demo).** From a clone of this repo (no `Package.swift` edit needed), run:

```bash
swift run HelloBlazeDB
```

**Minimal sample** (after adding the package), same shape as [the opening sample](#start-here-new-users), shorter:

```swift
import BlazeDB

struct Note: BlazeStorable {
    var id: UUID = UUID()
    var text: String
}

let db = try BlazeDB.open(name: "quickstart", password: "DemoPass123!")
try db.put(Note(text: "Ship first BlazeDB build"))  // save

let notes: [Note] = try db.query("note").all()  // all notes (or [] if empty)
```

For the full beginner walkthrough (`open` → `put` → `get` → `query`), use [the section above](#start-here-new-users).
For deeper coverage, see [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md).

## Add BlazeDB to your app

**Path B (consumer integration).** Add the package to your project, then paste from [the opening sample](#start-here-new-users) or from [Try BlazeDB from this repo](#try-blazedb-from-this-repo) (minimal sample).

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.5")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

Or in Xcode: **File → Add Package Dependencies** → paste `https://github.com/Mikedan37/BlazeDB.git`.

**Requirements:** Swift 6.0+, macOS 15+ / iOS 15+ / watchOS 8+ / tvOS 15+ / visionOS 1+ / Linux / Android

---

## What to do next

After `open` → `put` → `get` → `query` makes sense, pick **one** path:

1. **SwiftUI app** → [SwiftUI DB Patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) (how to hold `BlazeDBClient` in an app and level-up patterns).

2. **UIKit / CLI / server-style app**  
   → [Try BlazeDB from this repo](#try-blazedb-from-this-repo) (`swift run HelloBlazeDB` from a clone)  
   → [Add BlazeDB to your app](#add-blazedb-to-your-app) (SwiftPM or Xcode)  
   → [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md)

3. **How storage actually works** (single file, single collection, why there’s no SQL) → [Core Concepts](#core-concepts) below.

If you skip straight to API tiers or raw APIs without that bridge, you’ll feel lost. That’s normal; come back to step 1–3.

## SwiftUI Path

If you are building a SwiftUI app, use:

- [SwiftUI DB Patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md): beginner-first setup, then Level 1 through Level 4.

---

## What BlazeDB Is

> **Optional background.** Read [What to do next](#what-to-do-next) first if you only care about getting code running. This section is the mental model (embedded, encrypted, no SQL).

- An **embedded** database: runs in your process, no server required
- **Encrypted at rest** in production: AES-256-GCM on every data page
- **Document-oriented:** schema-less records with typed Codable overlays
- **ACID transactions** with WAL-backed crash recovery
- **Single-process:** one process owns the database file at a time
- **Single-collection:** all records (regardless of type) share one encrypted collection per database file; `TypedStore` is a typed lens, not a separate table

## What BlazeDB Is Not

- **Not SQL commands.** You do not write `SELECT` statements here; you use BlazeDB's Swift query methods instead (see [the sample above](#start-here-new-users) and [Querying Data](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md#6-querying-data)).
- **Not multi-process.** One process owns the database file. No concurrent access from separate processes.
- **Not client/server.** No network listener, no remote connections.
- **Not per-type table storage.** All record types coexist in a single encrypted collection.
- **Not distributed sync.** Sync infrastructure exists in source but is deferred and excluded from the default runtime.

### API tiers

*Skip this table until the default `open` / `put` / `get` / `query` flow feels boring. You don’t need to pick a “tier” on day one.*

| Tier | API | Use case |
|------|-----|----------|
| **Default API (recommended)** | `BlazeDB.open(...)` + `db.put` / `db.get` / `db.query(namespace)` | Fastest path for most app code |
| **TypedStore (secondary)** | `db.typed(T.self)` → scoped handle | View models or service layers that want a bound store |
| **Raw (advanced)** | `BlazeDataRecord` + `db.insert(record)` | Dynamic schemas, migrations |
| **Manual mapping (advanced)** | `BlazeDocument` | Custom storage control and manual serialization |

---

## Example: Lists and List Items

### One list, many items

A common BlazeDB use case is building something like a to-do list.

For example, you might have:
- one list called Groceries
- several items inside it, like Milk and Eggs

At first, you might try to store the whole thing as one big object with an array of items inside it. That seems simpler, but it makes real app behavior harder: changing one item means rewriting the whole list, and querying items by themselves becomes awkward.

A better pattern is:
- store the list as one record
- store each list item as its own record
- give each item a `listID` field
- set `listID` to the `id` of the list that item belongs to

That shared value is the connection.

```swift
import Foundation
import BlazeDB

struct List: BlazeStorable {
    var id: UUID = UUID()
    var name: String
}

struct ListItem: BlazeStorable {
    var id: UUID = UUID()
    var listID: UUID   // The ID of the list this item belongs to
    var name: String
    var isDone: Bool = false
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")

// Save the Groceries list first.
// BlazeDB gives it a unique id that we can use to link items to it.
let groceries = List(name: "Groceries")
try db.put(groceries)

// These items belong to the Groceries list because they store groceries.id
// in their listID field.
try db.put(ListItem(listID: groceries.id, name: "Milk"))
try db.put(ListItem(listID: groceries.id, name: "Eggs"))

// Load all lists
let lists: [List] = try db.query("list").all()

// Load only the items whose listID matches the Groceries list id
let groceryItems: [ListItem] = try db.query("listitem")
    .where("listID", equals: groceries.id)
    .all()
```

When you save the Groceries list, it gets an ID.  
When you save Milk and Eggs, you give them that same ID in `listID`.  
Later, BlazeDB can find all items with that ID and return the items for Groceries.

---

## Advanced Usage (Optional)

If you're new, [What to do next](#what-to-do-next) and [the opening sample](#start-here-new-users) are enough to ship something. Everything from **Core Concepts** downward is deeper architecture, alternate APIs, and ops. Read when you need it, not in order.

## Core Concepts

### Single-collection architecture

BlazeDB stores all records in one encrypted document collection per database file. All typed APIs (`db.insert(model)`, `db.typed(T.self)`, etc.) encode/decode through the `BlazeStorable` Codable bridge and filter records by decodability; they are not separate physical tables.

### Two typed protocols

| Protocol | Purpose | Used with |
|----------|---------|-----------|
| **`BlazeStorable`** | Automatic Codable serialization, KeyPath queries | `db.insert(model)`, `db.fetch(T.self, id:)`, `db.query(T.self)`, `db.typed(T.self)` |
| **`BlazeDocument`** | Manual `toStorage()`/`init(from:)` mapping, more control | `@BlazeQueryTyped` SwiftUI wrapper |

`BlazeStorable` is the recommended starting point. `BlazeDocument` is for when you need manual control over how your model maps to `BlazeDataRecord` storage. Both require `Codable` and `Identifiable` with `ID == UUID`.

> **`BlazeDocument` persistence:** Prefer `try model.toStorage()` or `try model.resolveStorage()` (or typed client APIs like `insert(model)`) when encoding can fail. The `storage` property is a **deprecated** compatibility shim: if `toStorage()` throws, it **logs** and falls back to an empty record. **Do not** persist that value. Typed insert/update paths already use `toStorage()` and are unaffected.

> **Do not use `@BlazeQueryTyped` with `BlazeStorable`-only models. It will not compile.** The `@BlazeQueryTyped` SwiftUI property wrapper requires `BlazeDocument`. If your model only conforms to `BlazeStorable`, you must add `BlazeDocument` conformance (with manual `toStorage()`/`init(from:)`) before you can use it in SwiftUI typed query wrappers.

### Encryption

The production runtime is always encrypted at rest. Every data page is sealed with AES-256-GCM. A password is required to open any database (minimum 8 characters). Metadata is HMAC-SHA256 signed for tamper detection. A benchmark-only flag (`BLAZEDB_BENCHMARK_NO_ENCRYPTION`) exists for performance isolation testing but must not be used with real data.

---

## API Overview

*Same idea as the [API tiers](#api-tiers) table above, with code. Skip until the default API feels limiting.*

### Default API (recommended)

Use this as your default app path. The full end-to-end example is [in the first section](#start-here-new-users).

### Direct CRUD (secondary)

If you need more control than the default API, you can call typed methods directly on `BlazeDBClient`:

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
| Linux | Core support | Swift 6.2 in CI: PR Tier0, nightly Tier1 + Tier2 core, weekly delta Tier2 extended + Tier3 heavy/perf; SwiftUI wrappers excluded |
| Android | Core support | `BLAZEDB_LINUX_CORE` path; Swift 6.3+ / Android NDK; best-effort CI |

SwiftUI query wrappers (`@BlazeQuery`, `@BlazeQueryTyped`) are only available on Apple platforms. On Linux and Android, the `swift-crypto` package is used in place of Apple CryptoKit.

See [Compatibility Matrix](Docs/COMPATIBILITY.md) for details.

---

## Testing And CI

- **PR gate** (macOS): `BlazeDB_Tier0` and `BlazeDB_Tier1` on every push/PR; Linux runs `BlazeDB_Tier0`. See `Docs/Testing/CI_AND_TEST_TIERS.md` for the full matrix.
- **Release validation** (tagged releases): macOS runs Tier0–Tier2 (+ extended companion targets as defined in the release workflow), not the same cadence as the PR gate.
- **Nightly Confidence (daily)** runs macOS Tier2 strict, clean checkout, README quickstart, Tier0 TSan, and Linux Tier1/Tier2 core lanes (see `Docs/Testing/CI_AND_TEST_TIERS.md`).
- **Deep Validation (weekly)** is **delta-only**: surfaces not already run by the PR gate and nightly (macOS Tier3 heavy + destructive, Tier1 TSan; Linux Tier2 extended + Tier3 heavy/perf). See `Docs/Testing/CI_AND_TEST_TIERS.md`.
- Additional nightly checks verify clean checkout and README quickstart scripts.
- Entry docs for test/CI structure: `Docs/Testing/CI_AND_TEST_TIERS.md` and `Docs/Testing/README.md`.

---

## Tools And Apps

| Tool/App | Type | What it does | Location | Status | Docs |
|----------|------|--------------|----------|--------|------|
| `BlazeDoctor` | CLI tool | Runs health diagnostics: open/auth check, layout integrity, read/write probe, stats + health output (`text` or `--json`) | `BlazeDoctor/` | Complete | [BlazeDoctor docs](Docs/Tools/BLAZEDOCTOR_DOCUMENTATION.md) |
| `BlazeDump` | CLI tool | Backup lifecycle tool with `dump`, `restore`, and `verify` commands for `.blazedump` files | `BlazeDump/` | Complete | [BlazeDump docs](Docs/Tools/BLAZEDUMP_DOCUMENTATION.md) |
| `BlazeInfo` | CLI tool | Prints database metadata and runtime state (size, records/pages/indexes, WAL size, health, schema version) | `BlazeInfo/` | Complete | [BlazeInfo docs](Docs/Tools/BLAZEINFO_DOCUMENTATION.md) |
| `BlazeShell` | CLI tool | Interactive REPL for CRUD operations, plus manager mode for mounting/switching multiple databases | `BlazeShell/` | Complete | [BlazeShell docs](Docs/Tools/BLAZESHELL_DOCUMENTATION.md) |
| `BlazeMCP` | MCP server tool | JSON-RPC MCP bridge exposing BlazeDB operations (schema/query/mutation/aggregation/index suggestions) to AI clients | `BlazeMCP/` | In repo (not in current `Package.swift` target graph) | [BlazeMCP docs](Docs/Tools/MCP_SERVER.md) |
| `BlazeStudio` | Companion app (macOS) | Visual block/workspace companion focused on modeling and code generation workflows | `BlazeStudio/` | In repo, experimental companion app | [BlazeStudio docs](Docs/Tools/BLAZESTUDIO_DOCUMENTATION.md) |
| `BlazeDBVisualizer` | Companion app (macOS) | GUI for browsing/editing data, running queries, and monitoring operational metrics | `BlazeDBVisualizer/` | In repo as separate app project | [BlazeDBVisualizer docs](Docs/Tools/BLAZEDBVISUALIZER_DOCUMENTATION.md) |

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

- **MVCC (multi-version concurrency control):** opt-in via `db.setMVCCEnabled(true)`. Provides snapshot isolation when enabled. See `BlazeDBClient+MVCC.swift`.
- **Full telemetry manager:** build-configuration dependent; core builds use stub/no-op telemetry.

### Present in source, not primary stable onboarding surfaces

- **Indexing:** B-tree, inverted (full-text), vector, and spatial index implementations exist in source. These are internal to the storage engine and do not yet have stable public creation APIs, onboarding docs, or runnable examples for end users.
- **Row-level security (RLS):** policy infrastructure exists in source, but full CRUD/query enforcement is not enabled by default.

### Deferred / not part of default runtime

- **Distributed sync/transport:** infrastructure exists but is excluded from `BlazeDBCore`. See [Distributed Transport Status](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md).

---

## Documentation

| Resource | Description |
|----------|-------------|
| [Getting Started Guide](Docs/GettingStarted/README.md) | Step-by-step setup |
| [SwiftUI DB Patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) | Practical SwiftUI patterns for passing and using `BlazeDBClient` |
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

**Maintained by:** Danylchuk Studios, LLC
