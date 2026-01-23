# Production-Grade Testing Infrastructure

**Comprehensive test suites for BlazeDB production readiness**

---

## Overview

BlazeDB includes six production-grade test suites designed to catch bugs, validate consistency, and ensure reliability under extreme conditions. These tests are **additive only** - they don't modify existing tests and are completely opt-in.

---

## Test Suites

### 1. Chaos Engine Tests (`BlazeDBTests/Chaos/ChaosEngineTests.swift`)

**Purpose:** Randomly generate operations to find edge cases that humans would never think of.

**Features:**
- Deterministic seed for reproducibility (set `CHAOS_SEED` environment variable)
- 1,000+ random operations per test run
- Random field generation (all data types)
- Schema change simulation
- Trigger firing simulation
- Post-operation consistency validation

**Tests:**
- `testChaosEngine_1000RandomOperations` - 1,000 random insert/update/delete/query operations
- `testChaosEngine_SchemaChanges` - Random index creation/dropping
- `testChaosEngine_TriggerSimulation` - Event trigger firing during chaos
- `testChaosEngine_ExtremeStress` - 5,000 operations for extreme stress

**Usage:**
```bash
# Run with default seed
swift test --filter ChaosEngineTests

# Run with custom seed (for reproducibility)
CHAOS_SEED=12345 swift test --filter ChaosEngineTests
```

**What it validates:**
- No crashes
- No corrupted layouts
- No invalid records
- No missing indexes
- No negative side effects

---

### 2. Concurrency Torture Tests (`BlazeDBTests/Concurrency/ConcurrencyStressTests.swift`)

**Purpose:** Extreme concurrency scenarios to detect deadlocks, starvation, and index corruption.

**Features:**
- 50-200 concurrent writers
- Simultaneous queries during writes
- Deadlock detection (timeout-based)
- Starvation detection
- Index corruption validation
- Partial write detection
- RLS bypass detection
- Spatial/vector index drift detection

**Tests:**
- `testConcurrencyStress_50Writers` - 50 concurrent writers, 20 records each
- `testConcurrencyStress_200Writers` - 200 concurrent writers (EXTREME)
- `testConcurrencyStress_SimultaneousQueries` - Queries during writes
- `testConcurrencyStress_IndexCorruption` - Index integrity under concurrency
- `testConcurrencyStress_VectorIndexDrift` - Vector index consistency
- `testConcurrencyStress_SpatialIndexDrift` - Spatial index consistency
- `testConcurrencyStress_StarvationDetection` - Writer starvation prevention

**Usage:**
```bash
swift test --filter ConcurrencyStressTests
```

**What it validates:**
- No deadlocks
- No starvation
- No index corruption
- No partial writes
- No RLS bypass
- No spatial/vector index drift

---

### 3. Model-Based Testing (`BlazeDBTests/ModelBased/StateModelTests.swift`)

**Purpose:** Compare BlazeDB behavior to a pure Swift Dictionary as "ground truth" to detect divergence.

**Features:**
- Pure Swift Dictionary as reference model
- Mirror operations (insert/update/delete/query)
- Compare BlazeDB to model after each operation
- Detect divergence (missing rows, inconsistent values, index mismatch)

**Tests:**
- `testModelBased_InsertAndFetch` - 100 insert/fetch operations
- `testModelBased_UpdateOperations` - 50 update operations
- `testModelBased_DeleteOperations` - 30 delete operations
- `testModelBased_QueryOperations` - 100 query operations
- `testModelBased_MixedOperations` - 200 mixed operations
- `testModelBased_IndexMismatchDetection` - Index consistency validation

**Usage:**
```bash
swift test --filter StateModelTests
```

**What it validates:**
- No missing rows
- No inconsistent values
- No index mismatch
- Perfect consistency with ground truth

---

### 4. Index Consistency Tests (`BlazeDBTests/Indexes/IndexConsistencyTests.swift`)

**Purpose:** Verify consistency across all index types.

**Features:**
- Primary index validation
- Secondary index validation
- Full-text index validation
- Spatial index validation
- Vector index validation
- Ordering index validation
- Cross-index validation
- Index drift detection

**Tests:**
- `testPrimaryIndex_Insert/Delete` - Primary index consistency
- `testSecondaryIndex_Insert/Update/Delete` - Secondary index consistency
- `testFullTextIndex_Insert/Update` - Full-text index consistency
- `testSpatialIndex_Insert/Update` - Spatial index consistency
- `testVectorIndex_Insert/Delete` - Vector index consistency
- `testOrderingIndex_Insert/Move` - Ordering index consistency
- `testCrossIndex_AllIndexesMatch` - Cross-index validation
- `testCrossIndex_IndexDriftDetection` - Index drift detection

**Usage:**
```bash
swift test --filter IndexConsistencyTests
```

**What it validates:**
- Insert → index.has(id) must be true
- Delete → index.has(id) must be false
- Update → index reflects new fields
- Move ordering → ordering index sorted and stable
- All indexes match data (no drift)

---

### 5. Replay & Crash Recovery Tests (`BlazeDBTests/Recovery/ReplayTests.swift`)

**Purpose:** Validate crash recovery and operation replay.

**Features:**
- Operation log generator
- Log replay engine
- Crash simulation (cut DB mid-write and reload)
- Orphaned overflow page detection
- Dangling ordering index detection
- Spatial/vector index synchronization validation
- Lazy decoding validity post-recovery

**Tests:**
- `testReplay_OperationLogGenerator` - Generate and replay operation logs
- `testReplay_CrashSimulation` - Simulate crash and recover
- `testReplay_NoCorruption` - Verify no corruption after recovery
- `testReplay_NoOrphanedOverflowPages` - Overflow page integrity
- `testReplay_SpatialIndexSynchronized` - Spatial index after recovery
- `testReplay_VectorIndexSynchronized` - Vector index after recovery
- `testReplay_LazyDecodingValid` - Lazy decoding after recovery
- `testReplay_NoDanglingOrderingIndices` - Ordering index integrity

**Usage:**
```bash
swift test --filter ReplayTests
```

**What it validates:**
- No corruption
- No orphaned overflow pages
- No dangling ordering indices
- Spatial/vector indexes synchronized
- Lazy decoding valid post-recovery

---

### 6. Performance Baselines (`BlazeDBTests/Performance/PerformanceBenchmarks.swift`)

**Purpose:** Microbenchmarks for all operations with CI-safe JSON output.

**Features:**
- Debug-only mode (never blocks CI)
- JSON output to `.build/test-metrics/`
- Microbenchmarks for all operations
- Throughput measurements

**Tests:**
- `testBenchmark_Insert_1000` - Insert performance
- `testBenchmark_Query_Indexed` - Indexed query performance
- `testBenchmark_Spatial_Query` - Spatial query performance
- `testBenchmark_Vector_Query` - Vector query performance
- `testBenchmark_Ordering_Move` - Ordering move performance
- `testBenchmark_RLS_Filter` - RLS filter performance
- `testBenchmark_LazyDecode_Projection` - Lazy decode performance
- `testBenchmark_QueryPlanner_Decision` - Query planner performance

**Usage:**
```bash
# Only runs in DEBUG mode
swift test --filter PerformanceBenchmarks
```

**Output:**
- JSON files in `.build/test-metrics/`
- Each benchmark includes:
 - Time (ms)
 - Throughput (ops/sec)
 - Metadata (record count, etc.)

**What it measures:**
- Insert latency and throughput
- Query latency (indexed, spatial, vector)
- Ordering move latency
- RLS filter overhead
- Lazy decode performance
- Query planner decision time

---

## Running All Tests

```bash
# Run all production-grade tests
swift test --filter "ChaosEngineTests|ConcurrencyStressTests|StateModelTests|IndexConsistencyTests|ReplayTests|PerformanceBenchmarks"

# Run specific suite
swift test --filter ChaosEngineTests

# Run with custom seed
CHAOS_SEED=12345 swift test --filter ChaosEngineTests
```

---

## CI Integration

**Performance Benchmarks:**
- Only run in DEBUG mode (skipped in release)
- Never block CI pipelines
- Output JSON metrics for tracking

**Other Tests:**
- Run in all configurations
- Should complete in reasonable time (< 5 minutes total)
- Can be run in parallel

---

## Best Practices

1. **Reproducibility:** Use deterministic seeds for chaos tests
2. **Isolation:** Each test suite is self-contained
3. **No Breaking Changes:** All tests are additive only
4. **CI Safety:** Performance tests never block CI
5. **Documentation:** All tests are documented

---

## Troubleshooting

**Tests failing?**
- Check logs for specific error messages
- Verify database files are cleaned up
- Check for file permission issues

**Performance tests not running?**
- Ensure DEBUG mode is enabled
- Check `.build/test-metrics/` directory exists

**Chaos tests non-deterministic?**
- Set `CHAOS_SEED` environment variable
- Use same seed for reproducibility

---

## Summary

These six test suites provide comprehensive coverage for:
- Random operation generation (chaos)
- Extreme concurrency (torture)
- Model-based validation (ground truth)
- Index consistency (all types)
- Crash recovery (replay)
- Performance baselines (metrics)

All tests are **production-ready**, **self-contained**, and **backward compatible**.

