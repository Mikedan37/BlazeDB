# Compatibility Statement

## Core Modules: Swift 6 Strict Concurrency Compliant 

**Status:** Core modules compile cleanly under Swift 6 strict concurrency.

**Compliant Modules:**
- Core (DynamicCollection, BlazeDBClient)
- Query (QueryBuilder)
- Storage (PageStore, PageCache)
- Encoding (BlazeBinaryEncoder, BlazeBinaryDecoder)
- Transactions
- Utils

**Compliance Method:**
- Explicit `@Sendable` annotations where required
- `@unchecked Sendable` for PageStore (justified by internal DispatchQueue serialization)
- Deadlock prevention guards (`dispatchPrecondition` in DEBUG builds)
- No `Task.detached` in core (replaced with direct sync calls)

**Verification:**
- Core builds cleanly: `swift build --target BlazeDB`
- Core tests compile: `swift test --filter BlazeDBClientTests`
- See `CONCURRENCY_COMPLIANCE.md` for detailed analysis

---

## Distributed Modules: Not Yet Compliant 

**Status:** Distributed modules currently fail to compile under Swift 6 strict concurrency.

**Affected Modules:**
- BlazeSyncEngine
- CrossAppSync
- DiscoveryProvider
- Network transport layers
- Telemetry (actor isolation issues)

**Impact:**
- Core functionality:  Works independently
- Distributed sync:  Not available
- Full test suite:  Blocked by distributed module errors

**Strategy:**
- Core and distributed are isolated
- Core CI runs independently
- Distributed modules excluded from core builds
- See `BUILD_STATUS.md` for current state

---

## Platform Support

### macOS
- **Minimum:** macOS 14.0
- **Status:**  Fully supported
- **Notes:** All features available

### iOS
- **Minimum:** iOS 15.0
- **Status:**  Fully supported
- **Notes:** All features available

### Linux
- **Platform:** aarch64 (tested on Orange Pi 5 Ultra)
- **Status:**  Core supported
- **Notes:** Some advanced features disabled (`BLAZEDB_LINUX_CORE`)

---

## Storage Format Compatibility

### Current Format: v1.0
- **Status:** Stable
- **Breaking Changes:** None planned
- **Migration Path:** Schema versioning system supports upgrades

### Dump Format: v1.0
- **Status:** Stable
- **Deterministic:** Yes (same DB state → same dump bytes)
- **Verifiable:** Yes (hash-based integrity checking)

---

## API Stability

### Stable APIs (v0.1.0+)
These APIs are stable and will not change in breaking ways:

- Core CRUD operations (`insert`, `fetch`, `update`, `delete`)
- Query builder (`query().where().orderBy().execute()`)
- Statistics API (`db.stats()`)
- Health API (`db.health()`)
- Migration system (`SchemaVersion`, `BlazeDBMigration`)
- Import/export (`db.export(to:)`, `BlazeDBImporter.restore()`)

### Experimental APIs
These APIs may change:

- Distributed sync modules (not included in core)
- Advanced query features (spatial, vector - Linux disabled)
- Telemetry APIs (actor isolation issues)

---

## Swift Version Requirements

- **Minimum:** Swift 6.0
- **Recommended:** Latest Swift 6.x
- **Strict Concurrency:** Enabled for core modules

---

## Migration Compatibility

### Schema Versioning
- **Format:** `SchemaVersion(major:minor)`
- **Current:** v1.0 (default for new databases)
- **Legacy:** v0.0 (databases without explicit versioning)

### Migration System
- **Protocol:** `BlazeDBMigration`
- **Execution:** Explicit (no automatic migrations)
- **Reversibility:** Optional (`down()` method)

---

## Support Policy

### What We Support
-  Core functionality bugs
-  Data corruption issues
-  Migration failures
-  Import/export failures
-  Documentation improvements

### What We Don't Support (Yet)
-  Distributed sync issues (modules not compliant)
-  Performance optimization requests (Phase 2 not started)
-  Feature requests for experimental APIs

### Reporting Issues
See `CONTRIBUTING.md` for bug report templates and guidelines.

---

## Breaking Changes Policy

### v0.x Releases
- May include breaking changes
- Will be documented in CHANGELOG.md
- Migration paths provided where possible

### v1.0+ Releases
- Stable APIs will not break
- Breaking changes will increment major version
- Deprecation warnings before removal

---

## Summary

**Core:**  Swift 6 compliant, stable, production-ready  
**Distributed:**  Not yet compliant, excluded from core  
**Storage:**  Stable format, migration support  
**APIs:**  Core APIs stable, experimental APIs clearly marked

For detailed status, see:
- `CONCURRENCY_COMPLIANCE.md` - Concurrency details
- `BUILD_STATUS.md` - Current build state
- `PRE_USER_HARDENING.md` - Trust features
