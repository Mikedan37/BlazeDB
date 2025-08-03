# BlazeDB

**Swift-native. Encrypted. Fast. Yours.**  
BlazeDB is a blazing fast embedded database engine written entirely in Swift. It’s designed for security-conscious apps, cryptographic commit storage, and total local control.

> “The database Apple would build if it wasn’t scared of raw power.” — you, probably

## Features

- **Swift-native query DSL** — expressive, type-safe, and chainable
- **Secure Enclave & password encryption** — Touch ID backed or exportable key
- **CBOR-encoded records** — small, binary, and portable
- **Memory-mapped encrypted page storage** — fast as hell, built for low latency
- **BlazeExport** — optional encrypted backup/export support
- **Modular architecture** — clean separation of concerns
- **Tightly integrated with GitBlaze** — store commits as first-class database objects

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
    •    Every page is encrypted with AES-GCM, individually IV’d
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

This is early-stage, experimental software. It’s not yet optimized, audited, or production-tested. You’re the pioneer. You burn your own trail.

About

Built by Danylchuk Studios LLC
Designed for GitBlaze, AshPile, and future proof workflows.
Made in Silicon Valley. Raised in Xcode.

“The bugs may be dead, but the audit lives on.”
— BlazeDB’s sister project, AshPile
