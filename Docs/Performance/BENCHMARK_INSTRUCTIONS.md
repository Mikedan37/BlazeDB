# How to Run BlazeDB Benchmarks and Get Actual Performance Numbers

## Quick Start

Run this command in your terminal:

```bash
cd /path/to/your/BlazeDB/clone
swift test --filter ComprehensiveBenchmarks
```

## What You'll See

The benchmarks will output actual measured performance like:

```
 BlazeDB Batch Insert 1,000 records: 0.234ms (avg over 5 runs)
 BlazeDB Batch Insert 10,000 records: 5234 ops/sec (1.91s for 10000 ops)
 BlazeDB Fetch 1,000 records: 2847 ops/sec (0.35s for 1000 ops)
 BlazeDB Query with filter (10,000 records): 45.2ms
```

## All Benchmark Commands

### 1. Comprehensive Benchmarks (Main Performance Tests)
```bash
swift test --filter ComprehensiveBenchmarks
```

**Measures:**
- Insert throughput (ops/sec)
- Fetch throughput (ops/sec)
- Query latency (ms)
- Update throughput (ops/sec)
- Delete throughput (ops/sec)
- Comparison with SQLite (if available)

### 2. Performance Benchmarks (Detailed Metrics)
```bash
swift test --filter PerformanceBenchmarks
```

**Saves JSON results to:** `.build/test-metrics/*.json`

**Measures:**
- Insert performance
- Indexed query performance
- Spatial query performance
- Vector query performance
- Ordering move performance
- RLS filter performance
- Lazy decode performance
- Query planner performance

### 3. Baseline Tests (Regression Detection)
```bash
BLAZEDB_RUN_BASELINE_TESTS=1 swift test --filter BaselinePerformanceTests
```

**Saves results to:** `/tmp/blazedb_baselines.json`

**Measures:**
- Insert 1,000 records
- Batch insert 10,000 records
- Fetch all 10,000 records
- Query with filter
- Aggregation
- Update 1,000 records
- Delete 1,000 records
- Concurrent operations

## Using the Benchmark Script

I've created `run_benchmarks.sh` that runs all benchmarks automatically:

```bash
chmod +x run_benchmarks.sh
./run_benchmarks.sh
```

This will:
1. Run all performance benchmarks
2. Extract key metrics
3. Save results to `benchmark_results/performance_results_TIMESTAMP.txt`
4. Show JSON metrics

## Expected Results (Based on Test Targets)

Based on the test code assertions, here's what the benchmarks expect:

| Operation | Target | Notes |
|-----------|--------|-------|
| Batch Insert (1K) | < 0.5 seconds | 5 iterations |
| Batch Insert (10K) | > 5,000 ops/sec | Throughput |
| Fetch (1K) | > 2,000 ops/sec | Throughput |
| Fetch All (10K) | < 1 second | Latency |
| Query with Filter (10K) | < 500ms | Latency |
| Indexed Query (10K) | < 2 seconds | Latency |
| Query with Sort (10K) | < 1 second | Latency |
| Batch Update (1K) | > 2,000 ops/sec | Throughput |
| Batch Delete (1K) | > 2,000 ops/sec | Throughput |

**Note:** These are test targets/assertions, not actual measured values. Run the benchmarks to get real numbers!

## After Running Benchmarks

1. Copy the actual measured numbers from the test output
2. Update `PERFORMANCE_AUDIT.md` with the real values
3. Convert ops/sec to ops/min (multiply by 60)
4. Document the test environment (hardware, OS version)

## Troubleshooting

If you get library loading errors:
```bash
# Try using Xcode's Swift instead
export DEVELOPER_DIR=$(xcode-select -p)
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
swift test --filter ComprehensiveBenchmarks
```

If tests fail:
- Make sure you're in the project root directory
- Ensure all dependencies are resolved: `swift package resolve`
- Try building first: `swift build`

## Open Profiler (Cold-Start Breakdown)

Use this **before** optimizing startup latency. It answers: "where did every millisecond go?"

```bash
./Scripts/run_open_profile.sh
```

Outputs:
- `benchmark_results/open_profile/open_profile.md` — phase table (PBKDF2, layout, indexes, PageStore, …)
- `benchmark_results/open_profile/open_profile.json` — machine-readable spans + RSS

Enable spans in your own code with `BLAZEDB_PROFILE_OPEN=1` (zero overhead when unset).

### Scale / memory

```bash
# RSS after open with a larger on-disk dataset
BLAZEDB_OPEN_PROFILE_RECORDS=100000 ./Scripts/run_open_profile.sh
```

### XCTest diagnostic (100k PBKDF2 iterations)

```bash
swift test --filter OpenProfileBenchmarks/testPrintColdOpenBreakdown
```

Prints `OPEN_PROFILE_SPAN|…` lines to the test log. Not a CI gate — iteration count differs from release.

### Interpreting the March 2026 baseline (~55 ms cold open)

That number is **not** comparable to current release cold open (~1.1 s on this host):

| Factor | March baseline | Current release |
|--------|----------------|-----------------|
| Path key cache across `close()` | Reused (no PBKDF2 on reopen) | Session store reuses key; `clearSessionKeys()` forces cold |
| Password verification | Skipped when cache hit | HMAC verifier on warm path; PBKDF2 on cold |
| KDF | Legacy static salt path | Per-DB salt, 600k iterations |

The open profiler shows **~97% of cold wall time is PBKDF2**; engine init is ~28 ms. Policy: [DATABASE_SESSION_KEY_LIFECYCLE.md](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md).

### BlazeDB vs SQLite (apples-to-apples + secure baseline)

Run both production-secure and engine-only (no encryption) conditions, with SQLite cold-open and read columns:

```bash
chmod +x ./Scripts/run_comparison_benchmarks.sh
./Scripts/run_comparison_benchmarks.sh --release
```

Outputs:
- `benchmark_results/comparison/baseline.json` — encryption on (production path)
- `benchmark_results/comparison/engine_only.json` — `BLAZEDB_BENCHMARK_NO_ENCRYPTION` compile flag
- `benchmark_results/comparison/COMPARISON.md` — side-by-side headline table

SQLite uses `journal_mode=WAL` and `synchronous=FULL` in the harness (still no encryption).

### Priority order (agreed)

1. Approve session key lifecycle policy — [DATABASE_SESSION_KEY_LIFECYCLE.md](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md)
2. Implement session cache per policy; re-run open profiler (cold ~1s, warm ~30ms)
3. Single-write path overhead
4. Persist defaults (batch-friendly API)
5. Leave reads/queries alone


