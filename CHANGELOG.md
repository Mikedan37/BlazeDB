# Changelog

All notable changes to BlazeDB are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Distributed modules Swift 6 compliance
- Additional platform support
- Performance optimizations based on real-world usage

---

## [2.7.0] - 2026-03-13

### Changed

- Platform requirements: macOS 15+, iOS 15+ (updated from macOS 14+)
- Always-on AES-256-GCM encryption (cannot be disabled)
- Package cleanup: removed commented-out distributed module references from `Package.swift`
- API behavior: `softDelete` records are hidden from `fetch(id:)`, `fetchAll()`, and queries
- Bug fix: `insertMany` records are immediately visible to queries/fetches
- Bug fix: `deleteMany` returns count of actually deleted records
- New API: `mvccStatusDescription()` (replaces stdout-printing status helper)
- Library hygiene: removed `print()` calls from library code

### Added

- `CODE_OF_CONDUCT.md` (Contributor Covenant v2.1)
- `SECURITY.md` (vulnerability disclosure policy)
- `PublicAPIVerificationTests` (47 tests)

### Removed

- Distributed module stubs from `Package.swift` (code still in repo, excluded from build)
- `README_NEW.md` (outdated)

### Notes

- BlazeDB moved from the early `0.1.x` line to the current `2.x` release line.

---

## [0.1.2] - 2026-01-23

### Fixed

- SwiftPM dependency stability issue by pinning SwiftCBOR to stable `0.6.0`.

## [0.1.1] - 2026-01-23

### Fixed

- Initial SwiftPM dependency stability fix for SwiftCBOR.

## [0.1.0] - 2025-01-23

### Added

- Initial stable embedded database release (ACID, WAL, AES-256-GCM, query builder, migration, import/export).

---

**For detailed information:**
- Usage: `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`
- Safety: `Docs/Guarantees/SAFETY_MODEL.md`
- Compatibility: `Docs/COMPATIBILITY.md`
- API Stability: `Docs/API_STABILITY.md`
- Support: `Docs/SUPPORT_POLICY.md`
