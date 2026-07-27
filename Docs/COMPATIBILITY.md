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

## Platform support levels

Use these words consistently:

| Term | Meaning |
|------|---------|
| **Declared** | Appears in `Package.swift` `platforms:` |
| **CI-tested (runtime)** | Automated engine tests run on that OS in CI (host Tier0 / Tier1) |
| **CI-tested (compile)** | Cross-compile succeeds in CI without claiming full engine XCTest coverage |
| **CI-validated (experimental)** | PR-gate jobs prove a path works; not a published production SDK |

The root README summarizes this table. This document remains the detailed matrix.

### macOS
- **Minimum:** macOS 15.0
- **Status:** Fully supported
- **Notes:** All features available

### iOS
- **Minimum:** iOS 15.0
- **Status:** Declared and CI-tested (compile)
- **Notes:** `Package.swift` declares iOS 15+. PR CI cross-compiles `BlazeDBCore` for iOS; full XCTest runtime on iOS Simulator is not a PR gate. Prefer README wording: runtime CI is macOS/Linux; Apple mobile platforms are compile-tested unless a runtime job is explicitly listed.

### Linux
- **Platform:** aarch64 (tested on Orange Pi 5 Ultra)
- **Status:** Core supported
- **Notes:** Some advanced features disabled (`BLAZEDB_LINUX_CORE`). CI baseline lane targets Swift 6.0 for core + Tier 0 stability checks.

### Android
- **Status:** **CI-validated (experimental packaging)**: not “unsupported,” and not the same product tier as macOS/Linux
- **What PR CI proves today:**
  - Cross-compile `BlazeDBCore` / `BlazeDBAndroidBridge` for Android ABIs (`Android — Cross-Compile`)
  - KMM `:shared:compileDebugKotlinAndroid`
  - KMM x86_64 emulator instrumentation smoke (`KMM Android — x86_64 Emulator Runtime`: `open` / `put` / `query`)
  - Local packaging scripts / PR packaging job (AAR / native libs; **not** published to Maven Central)
- **What it is not:** Linux-style host `BlazeDB_Tier0` / `BlazeDB_Tier1` on an Android device; not a `Package.swift` `platforms:` entry; not a shipped consumer SDK
- **Notes:** Same compile-time core mode as Linux (`BLAZEDB_LINUX_CORE`). Cross-compilation requires **OSS Swift 6.3.2+** (matching the Android SDK bundle), the [Swift SDK for Android](https://swift.org/documentation/articles/swift-sdk-for-android-getting-started.html), and NDK r27d+.
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

**KMM:** Kotlin Multiplatform sample (`expect class BlazeDB` in `Examples/android/shared`) has **iOS simulator and Android emulator runtime in the PR gate**, plus local packaging scripts. That is **CI-validated experimental** integration: not a published KMM SDK (no Maven Central / CocoaPods trunk). See [android-status.md](android-status.md).

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

**Core:** Swift 6 compliant. **macOS** and **Linux** have host runtime CI for the embedded core (Tier0 / Tier1). **iOS / watchOS / tvOS / visionOS** are declared and compile-tested (not BlazeDBCore XCTest runtime on device/simulator in the PR gate). **Android / KMM** are **CI-validated (experimental packaging)**: PR-gate cross-compile + KMM emulator smoke, not a published SDK and not Linux-equivalent host Tier0. See [android-status.md](android-status.md).
**Distributed:** Deferred / excluded from default OSS packaging
**Storage:** Format intended to be stable; prior-release open fixtures exist under `Tests/CompatibilityFixtures/` but are not yet a CI release gate (see [ROADMAP.md](../ROADMAP.md))
**APIs:** Core APIs stable within the documented surface; experimental APIs must stay clearly marked

For detailed status, see:
- [android-status.md](android-status.md) — Android / Swift-on-Android / KMM status
- [Compliance/CONCURRENCY_COMPLIANCE.md](Compliance/CONCURRENCY_COMPLIANCE.md) — Concurrency details
- [Status/BUILD_STATUS.md](Status/BUILD_STATUS.md) — Current build state (may be historical; prefer CI workflows)
