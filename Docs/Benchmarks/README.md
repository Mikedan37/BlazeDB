# BlazeDB Benchmarks

**Purpose:** Honest, reproducible performance comparisons between BlazeDB and SQLite.

---

## What BlazeDB Is Optimized For

- **Embedded single-process workloads**
- **Encrypted storage by default**
- **Deterministic exports**
- **Schema versioning**
- **Crash-safe writes**

---

## Where SQLite Still Wins

- **Raw insert throughput** (SQLite's B-tree is highly optimized)
- **Query planner sophistication** (SQLite has decades of optimization)
- **Memory footprint** (SQLite is smaller)
- **Network filesystem compatibility** (SQLite handles NFS better)

---

## Why BlazeDB Uses Less Power Under Real Workloads

BlazeDB's design choices reduce CPU burn in typical embedded scenarios:

1. **No query planner overhead** - Queries are explicit, not optimized
2. **Batch operations** - `insertMany()` is 3-5x faster than individual inserts
3. **Deterministic encoding** - No schema inference at runtime
4. **Explicit indexes** - No automatic index creation/removal

**Trade-off:** BlazeDB requires more upfront design, but uses less CPU during steady-state operation.

---

## Running Benchmarks

```bash
swift run BlazeDBBenchmarks
```

Results are saved to:
- `Docs/Benchmarks/RESULTS.md` (human-readable)
- `Docs/Benchmarks/results.json` (machine-readable)

---

## Benchmark Methodology

- **Same hardware** - All benchmarks run on the same machine
- **Same dataset** - Identical data for BlazeDB and SQLite
- **Same language** - Swift for both (SQLite via C API)
- **Cold caches** - Each benchmark starts fresh (unless noted)

---

## Interpreting Results

**Higher is better** for throughput benchmarks (ops/sec).

**Lower is better** for latency benchmarks (ms).

If SQLite shows "N/A", SQLite3 was not available during build.

---

## Reproducing Results

To reproduce these benchmarks:

1. Run on the same hardware class
2. Use the same Swift version
3. Ensure no other processes are competing for resources
4. Run multiple times and average results

**Note:** Absolute numbers will vary by hardware. Focus on relative performance (BlazeDB vs SQLite ratio).

---

## Current Results

See `RESULTS.md` for latest benchmark results.

These benchmarks are updated periodically as BlazeDB evolves.
