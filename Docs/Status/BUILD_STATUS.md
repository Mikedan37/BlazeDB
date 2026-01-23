# Build Status

## Core Modules:  Compiles Successfully

All core modules compile cleanly under Swift 6 strict concurrency:
-  Core (DynamicCollection, BlazeDBClient)
-  Query (QueryBuilder, QueryBuilder+Validation)
-  Storage (PageStore, PageCache)
-  Utils
-  Transactions
-  Encoding (BlazeBinaryEncoder, BlazeBinaryDecoder)

## Hardening Features:  Compile Successfully

All hardening improvements compile:
- **BlazeDBClient+Lifecycle.swift** (explicit close(), idempotency, resource cleanup)
- **BlazeDBClient+Compatibility.swift** (format versioning and validation)
- **DatabaseHealth+Limits.swift** (resource bounds and warnings)
- **LifecycleTests.swift** (lifecycle safety tests)
- **LockingTests.swift** (file locking tests)
- **ResourceLimitsTests.swift** (resource limit tests)
- **CompatibilityTests.swift** (format version tests)

## New Features:  Compile Successfully

All Phase 1 feature work compiles:
-  **BlazeDoctor** CLI tool
-  **BlazeDump** CLI tool (dump/restore/verify)
-  **BlazeInfo** CLI tool (database info)
-  **BlazeDBClient+Stats.swift** (diagnostics API with prettyPrint)
-  **BlazeDBClient+Health.swift** (health reporting)
-  **BlazeDBClient+Migration.swift** (schema versioning)
-  **BlazeDBClient+Export.swift** (export API)
-  **BlazeDBImporter.swift** (import/restore API)
-  **BlazeDBError+Categories.swift** (error categorization and guidance)
-  **PathResolver.swift** (platform-safe paths)
-  **BlazeDBClient+EasyOpen.swift** (zero-config entrypoint)
-  **DumpFormat.swift** (deterministic dump format)
-  **SchemaVersion.swift** (schema versioning)
-  **DatabaseHealth.swift** (health classification)

## Test Suites:  Compile Successfully

All new test suites compile:
-  **QueryErgonomicsTests** (query validation, error messages)
-  **SchemaMigrationTests** (migration planning, execution)
-  **ImportExportTests** (round-trip, integrity verification)
-  **OperationalConfidenceTests** (health classification)
-  **LinuxCompatibilityTests** (platform-safe paths)
-  **CrashRecoveryTests** (durability across close/reopen)
-  **ErrorSurfaceTests** (error message stability)

## Distributed Modules:  Build Failures (Out of Scope)

Distributed modules currently fail to compile under Swift 6:
- BlazeSyncEngine
- CrossAppSync
- Network transport layers
- Telemetry (actor isolation issues)
- Discovery (Sendable conformance issues)

**Impact:** 
- Core functionality:  Works independently
- New features:  Compile
- Full test suite:  Blocked by distributed module errors
- CLI tools:  Build successfully (BlazeDoctor, BlazeDump, BlazeInfo)

## Testing Status

**Core tests can run individually:**
```bash
swift test --filter QueryErgonomicsTests
swift test --filter SchemaMigrationTests
swift test --filter ImportExportTests
swift test --filter OperationalConfidenceTests
swift test --filter LinuxCompatibilityTests
swift test --filter CrashRecoveryTests
```

**Note:** Running `swift test` without filters will attempt to build distributed modules and fail. Use individual test filters or the `Scripts/run-core-tests.sh` script.

**Full test suite blocked by distributed module build failures** (documented in CONCURRENCY_COMPLIANCE.md)

## CI Configuration

The `.github/workflows/core-tests.yml` workflow:
-  Builds core independently (`swift build --target BlazeDB`)
-  Runs core tests with filters (distributed errors filtered from output)
-  Builds CLI tools (BlazeDoctor, BlazeDump, BlazeInfo)
-  Distributed tests allowed to fail (visible but non-blocking)

This provides clean CI signals for core while maintaining visibility on distributed compliance.

## How to Build and Test

### Build Core Only
```bash
swift build --target BlazeDB
```

### Build CLI Tools
```bash
swift build --target BlazeDoctor
swift build --target BlazeDump
swift build --target BlazeInfo
```

### Run Core Tests
```bash
# Individual test suites
swift test --filter QueryErgonomicsTests

# Or use the convenience script
./Scripts/run-core-tests.sh
```

### Full Build (Includes Distributed - Will Fail)
```bash
swift build  # Will show distributed module errors (expected)
```

## Summary

**Core:**  Compiles cleanly  
**Features:**  All compile successfully  
**Tests:**  All compile, can run with filters  
**CLI Tools:**  All build successfully  
**Distributed:**  Fails to compile (out of scope, documented)

For detailed concurrency compliance status, see `CONCURRENCY_COMPLIANCE.md`.  
For testing instructions, see `TESTING_GUIDE.md`.
