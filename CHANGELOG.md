# Changelog

All notable changes to BlazeDB will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.2] - 2026-01-23

### Fixed

- **SwiftPM Dependency Resolution:** Verified and pinned SwiftCBOR to exact stable version (v0.6.0)
  - Resolves error: "package 'blazedb' depends on an unstable-version package 'swiftcbor'"
  - Ensures BlazeDB can be consumed with stable version requirements
  - All transitive dependencies verified stable
  - Version bump clears SwiftPM cache metadata

### Technical Details

When consumers pin BlazeDB to a stable version (e.g., `exact: "0.1.0"`), SwiftPM requires all transitive dependencies to also be stable. This patch release:
- Pins SwiftCBOR with `exact: "0.6.0"` (stable tagged version)
- Verifies no branch/revision references to SwiftCBOR
- Ensures only one SwiftCBOR dependency declaration exists
- Bumps version to clear SwiftPM cache for v0.1.1

---

## [0.1.1] - 2026-01-23

### Fixed

- **SwiftPM Dependency Resolution:** Pinned SwiftCBOR to stable tagged release (v0.6.0)
  - Initial fix for SwiftPM dependency resolution error
  - Superseded by v0.1.2 (cache clearing)

---

## [0.1.0] - 2025-01-23

### Added

**Core Functionality:**
- Embedded database with ACID transactions
- Write-ahead logging (WAL) with crash recovery
- AES-256-GCM per-page encryption (enabled by default)
- Schema-less storage with dynamic collections
- Fluent query builder API
- Export/restore functionality with integrity verification
- Health monitoring and diagnostics
- Schema versioning and migration system

**Developer Experience:**
- Zero-configuration entrypoint (`openDefault()`)
- Platform-safe path handling (macOS, Linux)
- Clear error messages with remediation guidance
- Query performance documentation
- Operational confidence tooling

**CLI Tools:**
- `blazedb doctor` - Database diagnostics
- `blazedb info` - Database information
- `blazedb dump` - Export database
- `blazedb restore` - Restore database
- `blazedb verify` - Verify dump integrity

**Examples:**
- `HelloBlazeDB` - Zero-config example (run with `swift run HelloBlazeDB`)
- `BasicExample` - Basic CRUD operations
- Multiple usage examples in `Examples/` directory

**Documentation:**
- Complete usage guide (`Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`)
- Safety model documentation (`Docs/Guarantees/SAFETY_MODEL.md`)
- Performance benchmarks (`Docs/Benchmarks/`)
- Development performance guide (`Docs/Guides/DEVELOPMENT_PERFORMANCE.md`)
- Adoption readiness guide (`Docs/Status/ADOPTION_READINESS.md`)

**Testing:**
- Three-tier test structure (Tier 1: Production Gate, Tier 2: Core, Tier 3: Legacy)
- Crash recovery tests
- Import/export round-trip tests
- Schema migration tests
- Health monitoring tests

### Known Limitations

**Excluded from this release:**
- Distributed modules (BlazeDBDistributed, BlazeServer) - Not yet Swift 6 compliant
- Multi-process access - Single-writer only
- Network filesystem support - Local filesystems only

**Known Issues:**
- Signature verification in export/verify path may fail (see `Docs/Status/KNOWN_ISSUES.md`)
  - Export works correctly (data is valid)
  - Verification step may report false positives
  - Does not affect core functionality

### Platform Support

- **macOS:** 12.0+
- **iOS:** 15.0+
- **Linux:** aarch64 (tested on Orange Pi 5 Ultra)
- **Swift:** 6.0+ (strict concurrency compliant for core modules)

### API Stability

**Stable APIs (v0.1.0):**
- Core CRUD operations (`insert`, `fetch`, `update`, `delete`)
- Query builder (`query().where().execute()`)
- Database lifecycle (`openDefault`, `close`, `persist`)
- Statistics and health (`stats()`, `health()`)
- Export/restore (`export()`, `BlazeDBImporter.restore()`)
- Schema migrations (`BlazeDBMigration` protocol)

**Experimental APIs:**
- Distributed sync modules
- Advanced query features
- Telemetry

### Breaking Changes

None - This is the initial stable release.

### Security

- Encryption enabled by default (AES-256-GCM)
- Password strength validation
- Per-page encryption keys
- Deterministic export format with integrity verification

### Performance

- Benchmarks available via `swift run BlazeDBBenchmarks`
- See `Docs/Benchmarks/README.md` for methodology and results
- Optimized for embedded single-process workloads

---

## [Unreleased]

### Planned

- Distributed modules Swift 6 compliance
- Additional platform support
- Performance optimizations based on real-world usage

---

**For detailed information:**
- Usage: `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`
- Safety: `Docs/Guarantees/SAFETY_MODEL.md`
- Compatibility: `Docs/COMPATIBILITY.md`
- API Stability: `Docs/API_STABILITY.md`
- Support: `Docs/SUPPORT_POLICY.md`
