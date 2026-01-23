# Testing Guide

**Status:** Core tests pass, distributed tests blocked (expected)

---

## Running Core Tests

### Individual Test Suites

Run tests individually to avoid distributed module build failures:

```bash
# Query ergonomics
swift test --filter QueryErgonomicsTests

# Schema migrations
swift test --filter SchemaMigrationTests

# Import/export
swift test --filter ImportExportTests

# Operational confidence
swift test --filter OperationalConfidenceTests

# Linux compatibility
swift test --filter LinuxCompatibilityTests

# Crash recovery
swift test --filter CrashRecoveryTests

# Error surface
swift test --filter ErrorSurfaceTests
```

### Using Test Script

A convenience script filters out distributed module errors:

```bash
./Scripts/run-core-tests.sh
```

### Filtering Distributed Errors

When running tests, distributed module errors are expected and can be filtered:

```bash
swift test --filter QueryErgonomicsTests 2>&1 | grep -v "Distributed\|Telemetry\|InMemoryRelay\|BlazeTopology\|TCPRelay"
```

---

## Build Status

### Core Modules:  Compiles

```bash
swift build --target BlazeDB
```

**Status:** Core modules compile cleanly under Swift 6 strict concurrency.

### CLI Tools:  Compile

```bash
swift build --target BlazeDoctor
swift build --target BlazeDump
swift build --target BlazeInfo
```

**Status:** All CLI tools compile successfully.

### Full Build:  Distributed Errors (Expected)

```bash
swift build
```

**Status:** Distributed modules fail to compile (out of scope).

**Impact:** None for core functionality. Core works independently.

---

## Test Coverage

### Core Tests (Passing)

-  Query ergonomics (validation, error messages)
-  Schema migrations (versioning, planning, execution)
-  Import/export (round-trip, integrity verification)
-  Operational confidence (health classification)
-  Linux compatibility (path handling, round-trip)
-  Crash recovery (durability across close/reopen)
-  Error surface (message stability)

### Distributed Tests (Blocked)

-  Distributed sync (modules not Swift 6 compliant)
-  Network transport (actor isolation issues)
-  Telemetry (concurrency errors)

**Note:** Distributed tests are explicitly out of scope. They fail to compile but don't affect core functionality.

---

## CI Configuration

The `.github/workflows/core-tests.yml` workflow:

1. **Core Tests Job:**
   - Builds core only (`swift build --target BlazeDB`)
   - Runs core tests with filters
   - Builds CLI tools
   - **Must pass**

2. **Distributed Tests Job:**
   - Builds all targets (including distributed)
   - Runs full test suite
   - **Allowed to fail** (visible but non-blocking)

This provides clean CI signals for core while maintaining visibility on distributed compliance.

---

## Troubleshooting

### "error: fatalError" in Test Output

This usually means distributed modules failed to compile. This is expected.

**Solution:** Use test filters to run core tests only:
```bash
swift test --filter QueryErgonomicsTests
```

### Tests Hang or Timeout

This can happen if distributed modules are being built.

**Solution:** Use `--target BlazeDB` to build core only, then run filtered tests.

### Permission Errors on Linux

```bash
chmod 755 ~/.local/share/blazedb
```

---

## Summary

**Core Tests:**  Pass (run with filters)  
**Distributed Tests:**  Blocked (expected, out of scope)  
**Build:**  Core compiles cleanly  
**CLI Tools:**  All compile successfully

For questions, see `BUILD_STATUS.md` or `COMPATIBILITY.md`.
