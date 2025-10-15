# BlazeDB

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
│                              BLAZEDB DATA FLOW                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

📱 APPLICATION LAYER
├── AshPile Bug Tracker
├── BlazeDBVisualizer  
├── BlazeStudio
└── Custom Swift Apps

    ↓ API Calls (insert, fetch, update, delete, query)

🔌 CLIENT INTERFACE LAYER
├── BlazeDBClient (Public API)
├── BlazeDBManager (Multi-DB Management)
└── BlazeQuery DSL (Type-safe queries)

    ↓ Method Calls & Data Serialization

🧠 CORE ENGINE LAYER
├── DynamicCollection (Schema-less document storage)
├── BlazeTransaction (ACID compliance)
└── TransactionContext (Write-ahead logging)

    ↓ JSON Encoding & Index Management

📊 METADATA LAYER
├── StorageLayout (Index maps, page tracking)
├── SecondaryIndexes (Compound & single-field)
└── TransactionLog (Crash recovery)

    ↓ Layout Persistence & Index Updates

💾 STORAGE LAYER
├── PageStore (4KB page management)
├── File I/O (Raw disk operations)
└── Encryption (AES-GCM per page)

    ↓ Binary Data & File Headers

🗄️ PERSISTENT STORAGE
├── database.blaze (Main data file)
├── database.meta (Layout & indexes)
└── txn_log.json (Transaction log)
```

## File Data Flow Details

### 1. WRITE OPERATION FLOW
```
User Call: db.insert(record)
    ↓
BlazeDBClient.insert()
    ↓
DynamicCollection.insert()
    ↓
JSONEncoder.encode(document) → Data
    ↓
PageStore.writePage(index, plaintext)
    ↓
[Header: "BZDB" + Version: 0x01] + [JSON Data] + [Padding to 4KB]
    ↓
FileHandle.write() → disk.blaze
    ↓
Update indexMap[UUID: pageIndex]
    ↓
Update secondaryIndexes[field: CompoundIndexKey: Set<UUID>]
    ↓
StorageLayout.save() → disk.meta
    ↓
TransactionLog.append() → txn_log.json
```

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
PageStore.readPage(pageIndex)
    ↓
FileHandle.read(4KB) → [Header + Data + Padding]
    ↓
Validate "BZDB" header
    ↓
Extract JSON data (skip 5-byte header)
    ↓
JSONDecoder.decode() → BlazeDocumentField
    ↓
Return BlazeDataRecord
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

### 5. TRANSACTION FLOW
```
User Call: db.beginTransaction()
    ↓
BlazeDBClient.beginTransaction()
    ↓
FileManager.copyItem(db.blaze → txn_in_progress.blaze)
    ↓
All subsequent writes logged to txn_log.json
    ↓
User Call: db.commitTransaction()
    ↓
FileManager.removeItem(txn_in_progress.blaze)
    ↓
FileManager.removeItem(txn_log.json)
```

### 6. CRASH RECOVERY FLOW
```
App Startup
    ↓
BlazeDBClient.replayTransactionLogIfNeeded()
    ↓
Check if txn_log.json exists
    ↓
If exists: txn_in_progress.blaze exists → ROLLBACK
    ↓
FileManager.removeItem(txn_log.json)
    ↓
If exists: txn_log.json only → REPLAY
    ↓
Parse txn_log.json operations
    ↓
Replay insert/update/delete operations
    ↓
FileManager.removeItem(txn_log.json)
```

## Structure

BlazeDB/
├── Core/           # Record management and DB logic
├── Query/          # Swift-native DSL for blazing queries
├── Storage/        # Encrypted page system (mmap-based)
├── Crypto/         # Key handling, AES-GCM
├── Utils/          # CBOR and low-level helpers
├── Exports/        # Optional backup format
└── BlazeDB.swift   # Public interface

## Usage Example

```swift
let db = try BlazeDB.open(at: "/Users/me/gitblaze.db", keySource: .secureEnclave)

try db.collection("commits")
    .insert(CommitObject(...))

let recent = db.collection("commits")
    .query()
    .where("author" == .string("michael"))
    .order(by: "timestamp", descending: true)
    .limit(25)
    .run()

Encryption Model
    •    Each database has a master key
    •    Stored in Secure Enclave (Touch ID required), or
    •    Encrypted with a password-derived key (PBKDF2)
    •    Every page is encrypted with AES-GCM, individually IV'd
    •    Backups use a .blazeexport file (fully encrypted)

GitBlaze Integration

BlazeDB is the primary storage engine for GitBlaze:
    •    Commits are stored as CBOR-encoded encrypted records
    •    Drag-and-merge, decrypt-on-touch, all driven by BlazeDB
    •    Local-first with optional Raspberry Pi syncing

Roadmap
    •    Page-level encryption with AES-GCM
    •    CBOR-backed record format
    •    Record-level indexing
    •    Transaction log for rollback/replay
    •    Encrypted search support
    •    WAL mode for durability
    •    Query compiler for blazing fast filters

Disclaimer

This is early-stage, experimental software. It's not yet optimized, audited, or production-tested. You're the pioneer. You burn your own trail.

About

Built by Danylchuk Studios LLC
Designed for GitBlaze, AshPile, and future proof workflows.
Made in Silicon Valley. Raised in Xcode.

"The bugs may be dead, but the audit lives on."
— BlazeDB's sister project, AshPile