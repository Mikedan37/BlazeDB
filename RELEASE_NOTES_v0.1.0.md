# BlazeDB v0.1.0 Release Notes

**Release Date:** January 23, 2026  
**Tag:** v0.1.0

---

## First Stable Release

BlazeDB v0.1.0 is the first stable release, marking the completion of the Production Readiness phase.

---

## What's New

### Core Functionality
- ✅ Embedded database with ACID transactions
- ✅ Write-ahead logging (WAL) with crash recovery
- ✅ AES-256-GCM per-page encryption (enabled by default)
- ✅ Schema-less storage with dynamic collections
- ✅ Fluent query builder API
- ✅ Export/restore functionality with integrity verification
- ✅ Health monitoring and diagnostics
- ✅ Schema versioning and migration system

### Developer Experience
- ✅ Zero-configuration entrypoint (`openDefault()`)
- ✅ Platform-safe path handling (macOS, Linux)
- ✅ Clear error messages with remediation guidance
- ✅ Query performance documentation
- ✅ Operational confidence tooling
- ✅ SwiftUI integration (`@BlazeQuery` property wrapper)

### CLI Tools
- ✅ `blazedb doctor` - Database diagnostics
- ✅ `blazedb info` - Database information
- ✅ `blazedb dump` - Export database
- ✅ `blazedb restore` - Restore database
- ✅ `blazedb verify` - Verify dump integrity

### Examples
- ✅ `HelloBlazeDB` - Zero-config example (`swift run HelloBlazeDB`)
- ✅ `BasicExample` - Basic CRUD operations
- ✅ Multiple usage examples in `Examples/` directory

### Documentation
- ✅ Complete usage guide (`HOW_TO_USE_BLAZEDB.md`)
- ✅ Safety model (`SAFETY_MODEL.md`)
- ✅ Performance benchmarks (`Benchmarks/`)
- ✅ SwiftUI integration guide (`SWIFTUI_INTEGRATION.md`)
- ✅ Development performance guide
- ✅ Adoption readiness guide

---

## Platform Support

- **macOS:** 12.0+
- **iOS:** 15.0+
- **Linux:** aarch64 (tested on Orange Pi 5 Ultra)
- **Swift:** 6.0+ (strict concurrency compliant for core)

---

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repository URL.

---

## Quick Start

```swift
import BlazeDBCore

let db = try BlazeDBClient.openDefault(name: "mydb", password: "secure-password")
let id = try db.insert(BlazeDataRecord(["name": .string("Alice")]))
let results = try db.query().where("name", equals: .string("Alice")).execute().records
try db.close()
```

**Or run the example:**
```bash
swift run HelloBlazeDB
```

---

## Known Limitations

**Excluded from this release:**
- Distributed modules (BlazeDBDistributed, BlazeServer) - Not yet Swift 6 compliant
- Multi-process access - Single-writer only
- Network filesystem support - Local filesystems only

**Known Issues:**
- Signature verification in export/verify path may fail (see `KNOWN_ISSUES.md`)
  - Export works correctly (data is valid)
  - Verification step may report false positives
  - Does not affect core functionality

---

## What's Next

1. **Use it in real apps** - AshPile, GitBlaze, etc.
2. **Get external users** - One GitHub issue from a non-author is worth more than ten features
3. **Fix signature verification** - Tracked in `KNOWN_ISSUES.md`

**Do NOT:**
- Add distributed features
- Add background threads
- Chase micro-optimizations
- Rework docs again

BlazeDB is good because it says no.

---

## Documentation

- **Usage:** `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`
- **Safety:** `Docs/Guarantees/SAFETY_MODEL.md`
- **SwiftUI:** `Docs/Guides/SWIFTUI_INTEGRATION.md`
- **Compatibility:** `Docs/COMPATIBILITY.md`
- **API Stability:** `Docs/API_STABILITY.md`
- **Support:** `Docs/SUPPORT_POLICY.md`

---

## Full Changelog

See `CHANGELOG.md` for complete details.

---

**BlazeDB v0.1.0 is ready for use!**
