# BlazeDB Test Tiers

**Date:** 2025-01-22  
**Purpose:** Define which tests are required for production readiness vs optional/legacy

---

## Tier 1: Production Gate (MUST PASS)

These tests validate core guarantees that BlazeDB must uphold for production use.

**Status:** MUST pass for any release  
**CI:** Required, blocking

### Test Suites:
- `GoldenPathIntegrationTests` - End-to-end lifecycle (open → insert → query → export → restore → verify)
- `ImportExportTests` - Dump/restore integrity, corruption detection
- `SchemaMigrationTests` - Schema versioning, migration planning, execution
- `LifecycleTests` - Open/close correctness, idempotency, error handling
- `OperationalConfidenceTests` - Health reporting, stats interpretation
- `CLISmokeTests` - CLI tools (doctor, dump, restore, verify) work correctly

**What They Validate:**
- Database can be opened, used, and closed correctly
- Data survives process restarts
- Exports are deterministic and verifiable
- Restores validate integrity before accepting data
- Schema migrations are explicit and safe
- Health monitoring provides actionable feedback
- CLI tools work without distributed modules

---

## Tier 2: Important (SHOULD PASS)

These tests validate important features but aren't blocking for core functionality.

**Status:** Should pass, but not blocking  
**CI:** Run but allow failures (documented)

### Test Suites:
- `QueryErgonomicsTests` - Query validation, error messages, performance warnings
- `DXHappyPathTests` - Developer experience APIs
- `DXQueryExplainTests` - Query explainability
- `DXMigrationPlanTests` - Migration UX
- `DXErrorSuggestionTests` - Error guidance
- `ErrorSurfaceTests` - Error categorization and messages
- `LinuxCompatibilityTests` - Platform compatibility
- `CrashRecoveryTests` - Durability under crashes

**What They Validate:**
- Query APIs are ergonomic and provide good feedback
- Error messages are actionable
- Platform compatibility is maintained
- Crash recovery works correctly

---

## Tier 3: Legacy/Optional (MAY FAIL)

These tests may use deprecated APIs, access internals, or test experimental features.

**Status:** May fail or be skipped  
**CI:** Optional, non-blocking

### Test Suites:
- Tests accessing `PageStore` internals directly
- Tests using deprecated APIs
- Performance benchmarks (not correctness tests)
- Tests requiring distributed modules (when distributed is disabled)
- Tests accessing storage layout directly

**What They Validate:**
- Legacy behavior (may be removed in future versions)
- Internal implementation details (not user-facing guarantees)
- Experimental features

---

## Test Execution Strategy

### For Contributors:
```bash
# Run Tier 1 tests (required)
swift test --filter GoldenPathIntegrationTests
swift test --filter ImportExportTests
swift test --filter SchemaMigrationTests
swift test --filter LifecycleTests
swift test --filter OperationalConfidenceTests
swift test --filter CLISmokeTests

# Run Tier 2 tests (recommended)
swift test --filter QueryErgonomicsTests
swift test --filter DXHappyPathTests
# ... etc

# Run all tests (includes Tier 3)
swift test
```

### For CI:
- Tier 1: Required, must pass
- Tier 2: Run but allow failures (track separately)
- Tier 3: Optional, skip if they fail

---

## Migration Path

Tests currently failing compilation will be:
1. Fixed to use current APIs (if Tier 1 or 2)
2. Moved to Tier 3 (if they test deprecated behavior)
3. Removed (if they test removed features)

This document will be updated as tests are stabilized.
