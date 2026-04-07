# Changelog

All notable changes to BlazeDB are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Linux CI: all test targets failed to compile due to Darwin-only `arc4random_buf` call.**
  `EncryptionRoundTripVerificationTests.swift` used `arc4random_buf`, a BSD/Darwin C
  function not available on Linux. Because SwiftPM builds *all* test targets during
  `swift test` (even when filtering to a single target — see
  [swiftlang/swift-package-manager#9272](https://github.com/swiftlang/swift-package-manager/issues/9272)),
  the `BlazeDB_Tier1Fast` compile failure prevented every Linux test run, including
  Tier 0. Replaced with `UInt8.random(in:)` which is cross-platform Swift stdlib.
  Affected Linux CI on Swift 6.0, 6.2, and 6.3.

---

## [2.7.2] - 2026-04-03

### Deprecated

- `BlazeDBClient.replayTransactionLogIfNeeded()` — use `removeLegacyNDJSONTransactionLogFilesIfPresent()` instead (same behavior: removes legacy NDJSON sidecar files only; does not replay binary WAL). The old symbol remains as a forwarding shim with a `renamed:` deprecation fix-it.

### Added

- `BlazeDBClient.removeLegacyNDJSONTransactionLogFilesIfPresent()` — public name for legacy NDJSON sidecar cleanup (replaces misleading `replayTransactionLogIfNeeded()` name; old method deprecated).
- OSS readiness documentation:
  - `Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md`
  - `Docs/Status/RELEASE_ROLLBACK.md`
  - `Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md`
- One-command local OSS verification script: `Scripts/oss-readiness-local.sh`.
- Clean-checkout verification script: `Scripts/verify-clean-checkout.sh`.
- Release-tag buildability probe script: `Scripts/check-release-tag-builds.sh`.
- Cross-version compatibility harness docs and fixture contract:
  - `Docs/Status/COMPATIBILITY_HARNESS.md`
  - `Tests/CompatibilityFixtures/README.md`
  - `BlazeDB_Tier2.CrossVersionExportRestoreHarnessTests`
- Released compatibility fixtures:
  - `Tests/CompatibilityFixtures/v0.1.3/dump.blazedump`
  - `Tests/CompatibilityFixtures/v2.7.0/dump.blazedump`
- External security-review planning and tracking:
  - `Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md`
  - `.github/ISSUE_TEMPLATE/security_review_tracking.md`
- README quickstart verification script:
  - `Scripts/verify-readme-quickstart.sh`
- Tier1 depth workflow and release-validation workflow updates:
  - `.github/workflows/tier1-depth.yml`
  - `.github/workflows/release.yml`

### Changed

- Golden-path gate coverage:
  - Tier0 golden-path test is enabled (no explicit skip).
  - Tier0/Tier1 golden-path tests now use deterministic restore verification on the restored handle.
  - Health assertion accepts `ok` or `warn` (e.g., post-restore vacuum suggestion).
- `README.md` now links OSS readiness docs and includes explicit non-production warning for `BLAZEDB_BENCHMARK_NO_ENCRYPTION`.
- `CONTRIBUTING.md` now includes `./Scripts/oss-readiness-local.sh` and `./Scripts/verify-clean-checkout.sh` in contributor workflow.
- `Docs/README.md` now distinguishes canonical docs, forward-looking design docs, and archived material; `Docs/Archive/README.md` marks historical content as non-authoritative.
- Hosted CI expectations are now documented as conditional on repository configuration, with local verification commands called out as the fallback source of truth.
- Tier1 naming is now consistently split as `BlazeDB_Tier1Fast`, `BlazeDB_Tier1Extended`, and `BlazeDB_Tier1Perf` in active scripts and maintainer docs.
- `Scripts/verify-clean-checkout.sh` now validates a clean worktree snapshot synced from local branch changes.
- `Examples/HelloBlazeDB/main.swift` now uses a password that satisfies the current password policy, so quickstart succeeds from a clean snapshot.
- `ci.yml` now runs Tier0 and `BlazeDB_Tier1Fast` on push and pull_request clean runners; deeper Tier1 lanes moved to depth/release workflows.
- OSS scripts now summarize warning counts and keep full logs in files to reduce terminal noise.
- Dump verification now includes a legacy hash compatibility path behind explicit opt-in (`allowLegacyHashMismatch`) for cross-version restore validation.
- `SECURITY.md` now includes explicit disclosure/response SLA targets.

### Upgrade Notes

- If your CI expected Tier0 golden-path to be skipped, update it; the test now executes.
- If your automation expected health status to be strictly `ok`, allow `warn` where suggested actions are non-fatal.
- Prefer running `./Scripts/oss-readiness-local.sh` before PR or release tagging.

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
