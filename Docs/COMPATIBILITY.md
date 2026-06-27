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
- Core functionality: Works independently
- Distributed sync: Not available
- Full test suite: Blocked by distributed module errors

**Strategy:**
- Core and distributed are isolated
- Core CI runs independently
- Distributed modules excluded from core builds
- See `BUILD_STATUS.md` for current state

---

## Platform Support

### macOS
- **Minimum:** macOS 15.0
- **Status:** Fully supported
- **Notes:** All features available

### iOS
- **Minimum:** iOS 15.0
- **Status:** Fully supported
- **Notes:** All features available

### Linux
- **Platform:** aarch64 (tested on Orange Pi 5 Ultra)
- **Status:** Core supported
- **Notes:** Some advanced features disabled (`BLAZEDB_LINUX_CORE`). CI baseline lane targets Swift 6.0 for core + Tier 0 stability checks.

### Android
- **Status:** Core path only — **not yet officially supported** for app integration
- **Notes:** Same compile-time mode as Linux (`BLAZEDB_LINUX_CORE`). Cross-compilation requires **OSS Swift 6.3.2+** (matching the Android SDK bundle), the [Swift SDK for Android](https://swift.org/documentation/articles/swift-sdk-for-android-getting-started.html), and NDK r27d+. PR CI cross-compiles `BlazeDBCore` on Linux with OSS Swift.
- **Detail:** [android-status.md](android-status.md)

#### OSS Swift vs Xcode Swift (Android cross-compile)

Android cross-compilation **must** use the **open-source Swift toolchain** from [swift.org](https://www.swift.org/install/), not the `swift` bundled with Xcode on macOS.

If you run:

```bash
swift build --swift-sdk aarch64-unknown-linux-android28 --static-swift-stdlib
```

with **Apple Swift**, the build typically fails inside dependencies (`swift-crypto`, etc.) with:

```text
compiled module was created by an older version of the compiler; rebuild 'Foundation' ...
```

That is a toolchain mismatch, not a BlazeDB bug. Install OSS Swift 6.3.2+ (for example via [swiftly](https://www.swift.org/install/)) and ensure `swift --version` does **not** report `Apple Swift`. Use `./Scripts/ci-android-cross-compile.sh` on CI or locally.

**KMM:** BlazeDB does **not** support Kotlin Multiplatform today. Swift-on-Android (native library + JNI) is the realistic integration path; see [android-status.md](android-status.md).

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

### Stable APIs (v2.x)
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
- **CI lane policy:** Linux CI runs a Swift 6.2 baseline lane for deterministic core validation; Android cross-compile CI uses OSS Swift 6.3.2 + Android SDK on Ubuntu (see `ci.yml` and [android-status.md](android-status.md)).

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
- Core functionality bugs
- Data corruption issues
- Migration failures
- Import/export failures
- Documentation improvements

### What We Don't Support (Yet)
- Distributed sync issues (modules not compliant)
- Performance optimization requests (Phase 2 not started)
- Feature requests for experimental APIs

### Reporting Issues
See `CONTRIBUTING.md` for bug report templates and guidelines.

---

## Breaking Changes Policy

### Stable Release Policy (2.x)
- Stable APIs do not break within the major line
- Deprecation warnings before removal
- Migration paths provided when behavior changes

### Major Release Policy (3.x+)
- Breaking changes require a major version bump
- Breaking changes must be documented in `CHANGELOG.md`

---

## Summary

**Core:** Swift 6 compliant, stable, production-ready on macOS/iOS; core-path supported on Linux (CI); Android cross-compile verified in CI — app integration not yet officially supported (see [android-status.md](android-status.md))
**Distributed:** Not yet compliant, excluded from core
**Storage:** Stable format, migration support
**APIs:** Core APIs stable, experimental APIs clearly marked

For detailed status, see:
- `android-status.md` - Android / Swift-on-Android / KMM status (not full platform docs)
- `CONCURRENCY_COMPLIANCE.md` - Concurrency details
- `BUILD_STATUS.md` - Current build state
- `PRE_USER_HARDENING.md` - Trust features
