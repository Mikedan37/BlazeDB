# BlazeDB

> **Status (2026 OSS core):** This page contains historical and architecture-level context. For the **current, supported onboarding path**, start with:
> 1. `README.md` (60-second quick start)
> 2. `Examples/HelloBlazeDB/` (canonical start example)
> 3. `Docs/GettingStarted/README.md` (getting-started path)
>
> The default public API for new applications is `import BlazeDB` + `BlazeDB.open(...)` + `db.put/get/query`.
> Lower-level `BlazeDBClient`, `TypedStore`, and raw record APIs remain available as secondary/advanced paths.

**Swift-native. Encrypted. Fast. Yours.**
BlazeDB is a blazing fast embedded database engine written entirely in Swift. It's designed for security-conscious apps, cryptographic commit storage, and total local control.

> "The database Apple would build if it wasn't scared of raw power." — you, probably

## Features

- **Swift-native query DSL** — expressive, type-safe, and chainable
- **Secure Enclave & password encryption** — Touch ID backed or exportable key
- **CBOR-encoded records** — small, binary, and portable
- **Memory-mapped encrypted page storage** — fast as hell, built for low latency
- **BlazeExport** — optional encrypted backup/export support
- **Modular architecture** — clean separation of concerns
- **Tightly integrated with GitBlaze** — store commits as first-class database objects

## Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ BLAZEDB DATA FLOW │
└─────────────────────────────────────────────────────────────────────────────────┘

 APPLICATION LAYER
├── AshPile Bug Tracker
├── BlazeDBVisualizer
├── BlazeStudio
└── Custom Swift Apps

 ↓ API Calls (insert, fetch, update, delete, query)

 CLIENT INTERFACE LAYER
├── BlazeDBClient (Public API)
├── BlazeDBManager (Multi-DB Management)
└── BlazeQuery DSL (Type-safe queries)

 ↓ Method Calls & Data Serialization

 CORE ENGINE LAYER
├── DynamicCollection (documents, index maps, queries)
├── BlazeBinary encode/decode (record bytes on the default insert/fetch path)
└── Optional: MVCC, explicit client transactions when enabled

 ↓ Encoding, index updates, staged page writes

 METADATA LAYER
├── StorageLayout (signed layout, index maps, secondary indexes)
└── Persistence to `.meta` (and `.meta.indexes` when used)

 ↓ Encrypted pages + binary WAL (default durability)

 STORAGE LAYER
├── PageStore (4KB pages, queue-synchronized I/O)
├── WriteAheadLog (binary `.wal` — default `WALMode.legacy`)
├── File I/O (pread/pwrite)
└── Encryption (AES-GCM per page)

 TYPICAL ON-DISK FILES (default client path)
├── `<name>.blazedb` — encrypted main data pages
├── `<name>.meta` — signed layout / indexes
├── `<name>.wal` — binary write-ahead log (crash recovery replay on open)
└── Legacy / optional: NDJSON `txn_log*.json` sidecars — **not** the default CRUD durability mechanism (see `Docs/Status/DURABILITY_MODE_SUPPORT.md`)
```

## File Data Flow Details

### 1. WRITE OPERATION FLOW (default `BlazeDBClient`, MVCC off)
```
User Call: db.insert(record)
 ↓
BlazeDBClient.insert()
 ↓
DynamicCollection.insert() (legacy single-version path)
 ↓
BlazeBinaryEncoder.encode(record) → Data
 ↓
PageStore.writePageWithOverflow / writePage
 → encrypt page (AES-GCM, "BZDB" header) → append to binary WriteAheadLog → pwrite main .blazedb
 ↓
Update indexMap, secondaryIndexes
 ↓
StorageLayout.saveSecure (or save) → .meta
```
NDJSON `txn_log.json` is **not** written on this path for normal CRUD. Optional legacy sidecar cleanup may run at open (`removeLegacyNDJSONTransactionLogFilesIfPresent()`; `replayTransactionLogIfNeeded()` is deprecated).

### 2. READ OPERATION FLOW
```
User Call: db.fetch(id)
 ↓
BlazeDBClient.fetch()
 ↓
DynamicCollection.fetch()
 ↓
indexMap[id] → pageIndex
 ↓
PageStore.readPage / readPageWithOverflow → decrypt AES-GCM → BlazeBinary payload
 ↓
BlazeBinaryDecoder.decode → BlazeDataRecord
```

### 3. INDEX QUERY FLOW
```
User Call: db.query().where("status" == "open")
 ↓
BlazeQuery.apply()
 ↓
DynamicCollection.fetchAll()
 ↓
For each record: indexMap[id] → pageIndex → PageStore.readPage()
 ↓
Filter by predicate: record["status"] == "open"
 ↓
Return filtered results
```

### 4. INDEXED QUERY FLOW (Fast Path)
```
User Call: db.fetch(byIndexedField: "status", value: "open")
 ↓
DynamicCollection.fetch(byIndexedField)
 ↓
secondaryIndexes["status"]["open"] → Set<UUID>
 ↓
For each UUID in Set: indexMap[UUID] → pageIndex
 ↓
PageStore.readPage(pageIndex) → BlazeDataRecord
 ↓
Return indexed results (no full table scan!)
```

### 5. DURABILITY AND TRANSACTIONS (summary)

**Default document path:** Durability is **page-level**: binary `WriteAheadLog` + encrypted `.blazedb` pages + signed `.meta`, as in §1. Normal CRUD does **not** append to NDJSON `txn_log.json`.

**Explicit `BlazeDBClient` transactions** (when used) may use `txn_in_progress-*` backup files and related lifecycle; see client transaction implementation.

**Legacy NDJSON:** Obsolete sidecar files may be deleted on open; they are not the engine’s primary replay source for default CRUD. Details: `Docs/Status/DURABILITY_MODE_SUPPORT.md`.

### 6. CRASH RECOVERY (summary)

- **Binary WAL:** On open, `PageStore` replays the legacy binary `WriteAheadLog` so committed encrypted pages are restored after a crash. See `WriteAheadLog.swift` and `PageStore` initialization.
- **Legacy NDJSON files:** `BlazeDBClient.removeLegacyNDJSONTransactionLogFilesIfPresent()` removes obsolete newline-delimited JSON transaction log sidecars when present; it does **not** replay document operations into the engine. (`replayTransactionLogIfNeeded()` is deprecated.) See `Docs/Status/DURABILITY_MODE_SUPPORT.md`.
- **Explicit transactions:** Separate durable transaction backup restore may run during client init when `txn_in_progress-*` artifacts exist (see client initialization and vacuum recovery).

## Structure

BlazeDB/
├── Core/ # Record management and DB logic
├── Query/ # Swift-native DSL for blazing queries
├── Storage/ # Encrypted page system (mmap-based)
├── Crypto/ # Key handling, AES-GCM
├── Utils/ # CBOR and low-level helpers
├── Exports/ # Optional backup format
└── BlazeDB.swift # Public interface

## Usage Example (default API first)

```swift
import BlazeDB

// Open database (creates if needed, always encrypted)
let db = try BlazeDB.open(name: "myapp", password: "your-secure-password")

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let bug = Bug(title: "Crash", status: "open")
try db.put(bug)

let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
let recent: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

Encryption Model (current core engine)
 • Each database is encrypted with AES-GCM at the page level
 • Keys are derived from a password (or key material) via KDF
 • Every page is encrypted individually with its own nonce
 • Default durability uses a binary write-ahead log (`.wal`) plus signed metadata

Historical GitBlaze Integration (legacy context)

BlazeDB originated as the primary storage engine for GitBlaze:
 • Commits stored as encrypted records
 • Local-first workflows with optional sync
 • Product-specific integrations built on top of the core engine, not part of the OSS default path

Roadmap
 • Page-level encryption with AES-GCM
 • CBOR-backed record format
 • Record-level indexing
 • Transaction log for rollback/replay
 • Encrypted search support
 • WAL mode for durability
 • Query compiler for blazing fast filters

Disclaimer

This is early-stage, experimental software. It's not yet optimized, audited, or production-tested. You're the pioneer. You burn your own trail.

About

Built by Danylchuk Studios LLC
Designed for GitBlaze, AshPile, and future proof workflows.
Made in Silicon Valley. Raised in Xcode.

"The bugs may be dead, but the audit lives on."
— BlazeDB's sister project, AshPile