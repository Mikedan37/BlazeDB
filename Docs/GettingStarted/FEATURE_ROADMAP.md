# Feature Roadmap

**Status:** Phase 1 frozen. Shipping features that don't touch concurrency core.

## This Week's Deliverables

### 1. `blazedb doctor` CLI Tool
**Goal:** Quick health check for databases

**Features:**
- Open database and verify layout integrity
- Check encryption key validity
- Run quick read/write cycle
- Report page count, WAL size, cache stats
- Exit with non-zero code on errors

**Implementation:**
- New executable target: `BlazeDoctor`
- Uses existing `BlazeDBClient` API (no core changes)
- Output: human-readable + JSON option

### 2. `db.stats()` Diagnostics API
**Goal:** Expose internal metrics for monitoring

**API:**
```swift
public struct DatabaseStats {
    public let pageCount: Int
    public let walSize: Int64?
    public let lastCheckpoint: Date?
    public let cacheHitRate: Double
    public let indexCount: Int
    public let recordCount: Int
}

extension BlazeDBClient {
    public func stats() throws -> DatabaseStats
}
```

**Implementation:**
- Add to `BlazeDBClient+Monitoring.swift` (already exists)
- Read-only access to existing metrics
- No storage mutations

### 3. Crash Recovery Test
**Goal:** Validate database survives unclean shutdown

**Test:**
- Create database with data
- Simulate crash (kill process, remove lock file)
- Reopen database
- Verify all committed data intact
- Verify WAL recovery works

**Implementation:**
- New test: `BlazeDBTests/Persistence/CrashRecoveryTests.swift`
- Uses existing recovery code paths
- No core changes needed

### 4. README Quick Start Section
**Goal:** 3 copy-paste examples that work immediately

**Examples:**
1. **Basic CRUD** (30 seconds)
2. **Query with filters** (1 minute)
3. **Batch operations** (1 minute)

**Implementation:**
- Add to root `README.md` or `Docs/README.md`
- Test each example before committing
- Link to full docs

## Future Features (Post-Freeze)

### Reliability Polish
- Fuzz encoder/decoder (round-trip testing)
- Migration test harness (old → new layout)
- Corruption detection improvements
- Better error messages (readable corruption/schema errors)

### Packaging & Adoption
- Versioning + CHANGELOG automation
- Bench script producing CSV output
- GitHub Actions for releases
- Swift Package Manager optimization

### Developer Experience
- Better error messages throughout
- Diagnostic logging improvements
- Performance profiling helpers
- Migration guides

## What We're NOT Doing

**Out of scope (respects Phase 1 freeze):**
-  Performance optimizations (wait for Phase 2)
-  Concurrency changes (Phase 1 is frozen)
-  Storage layer refactoring
-  Query engine rewrites

**Principle:** Ship features that operate "outside the heart." Core is frozen for good reason.

## Success Criteria

Each feature must:
-  Not touch frozen core modules
-  Pass all existing tests
-  Include tests for new functionality
-  Update documentation
-  Work on macOS and Linux (where applicable)

**Ship features. Not optimizations.**
