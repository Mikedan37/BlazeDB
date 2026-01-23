# Swift 6 Strict Concurrency Compliance

** Phase 1 is FROZEN. See `PHASE_1_FREEZE.md` for policy.**

## Status

**BlazeDB core compiles under Swift 6 strict concurrency**

- Parallel encoding/decoding temporarily disabled
- Detached tasks removed from core; Sendable closure requirements satisfied
- PageStore marked `@unchecked Sendable` due to internal queue serialization

 **Repository-wide Swift 6 concurrency compliance is not yet complete; distributed modules currently fail to compile under Swift 6 and are excluded from this phase.**

## Scope

This compliance applies to **BlazeDB core modules only**:
- Core (DynamicCollection, BlazeDBClient)
- Query (QueryBuilder)
- Storage (PageStore, PageCache)
- Utils
- Transactions

**Excluded modules** (not modified):
- Distributed sync/networking
- Cross-app synchronization
- Network transport layers

## Changes Made

### 1. Removed Parallel Processing

**Files**: `DynamicCollection+ParallelEncoding.swift`, `PageStore+Optimized.swift`, `PageCache.swift`

- Converted parallel batch operations to serial execution
- Removed `withThrowingTaskGroup` and `Task.detached` closures
- Removed `DispatchQueue.concurrentPerform` patterns

**Rationale**: Parallel processing requires careful Sendable conformance. Serial execution is safer and compiler-friendly.

### 2. Eliminated Task.detached in Core

**Files**: `DynamicCollection+Async.swift`, `PageStore+Async.swift`, `PageStore+Optimized.swift`

- Replaced `Task.detached` with direct sync method calls
- Sync methods use internal `queue.sync` which is safe from async contexts
- Removed delayed flush Tasks (durability guaranteed at commit boundaries)

**Rationale**: `Task.detached` requires `@Sendable` closures and careful capture management. Direct calls to thread-safe sync methods avoid these requirements.

### 3. Sendable Annotations

**Files**: `PageStore.swift`, `ChangeObservation.swift`, `BlazeTransaction+Extensions.swift`

- `PageStore`: `@unchecked Sendable` (thread-safe via internal `DispatchQueue`)
- `ChangeObserver`: `@Sendable` closure type
- Predicate parameters: `@Sendable` where required by Swift

**Rationale**: `@unchecked Sendable` is acceptable for `PageStore` because it uses internal queue serialization. Closure types require `@Sendable` when used in detached contexts.

## Safety Guarantees

### Deadlock Prevention

 **Verified**: No deadlock risk
- PageStore uses `.concurrent` queue with `.barrier` flags
- Async methods call sync methods directly (not from within `queue.async` blocks)
- No re-entrancy: sync methods are never called from within the queue itself
- **Guardrail**: `dispatchPrecondition(condition: .notOnQueue(queue))` added to all public `queue.sync` methods (DEBUG builds only)
  - Will crash loudly if re-entrancy is ever introduced
  - Internal helpers (`_writePageLocked`, `_writePageLockedUnsynchronized`) intentionally called from within queue context (documented as "assumes caller holds barrier")
  - All 8 public `queue.sync` entry points are guarded

### Durability Guarantees

 **Verified**: Durability maintained
- `commitTransaction()` → `persist()` → `store.synchronize()` 
- `saveLayout()` calls `store.synchronize()` 
- Batch operations call `store.synchronize()` 
- Removed delayed flush was optimization only, not a durability guarantee

## Future Work (Phase 2)

**See `PHASE_2_PARALLELISM.md` for detailed implementation plan with realistic throughput expectations.**

When reintroducing parallelism:

### Parallelism Rules

**Only parallelize pure steps:**
- Encoding
- Compression
- Hashing

**Never parallelize:**
- Page cache mutation
- WAL writes
- Index updates
- Layout saves

**Guidelines:**
1. **Isolated parallelism**: Use actors or dedicated queues
2. **CPU-bound only**: Parallelize encoding/compression, never mutable storage state
3. **Sendable compliance**: Ensure all parallel paths satisfy Sendable requirements

**Principle**: Parallelism belongs at the edges. Not in the heart.

## Testing

### Core-Only Tests

Core tests can run independently of distributed modules:

```bash
# Run core tests only (excludes distributed modules)
swift test --filter BlazeDBClientTests.testDurabilityAfterConcurrencyChanges
```

### Durability Test

Added `testDurabilityAfterConcurrencyChanges()`:
- Writes 25+ records to force page flush and layout save
- Closes and reopens database in new instance
- Verifies all records persist correctly

**Note**: Repository-wide `swift test` currently blocked by distributed module build failures (out of scope for Phase 1).

### CI Configuration

A GitHub Actions workflow (`.github/workflows/core-tests.yml`) is provided:
- **Core tests job**: Runs core tests independently, must pass
- **Distributed tests job**: Runs full test suite, allowed to fail (keeps visibility without blocking)

This provides clean CI signals for core while maintaining pressure on distributed module compliance.

## Summary

 **BlazeDB core compiles under Swift 6 strict concurrency**
 **Deadlock risk checked** (with runtime assertions to keep it that way)
 **Durability path still flushes at commit boundaries**
 **Minimal durability regression test added** (25+ records, full reopen cycle)
 **Repo-wide `swift test` currently blocked by distributed module build failures** (out of scope)

This is a real milestone. Core is correct and compiler-compliant. Ready for Phase 2 (reintroducing parallelism within isolated walls) when needed.
