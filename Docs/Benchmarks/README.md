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
# Side-by-side secure vs engine-only vs SQLite (recommended; publishes RESULTS.md)
chmod +x ./Scripts/run_comparison_benchmarks.sh
./Scripts/run_comparison_benchmarks.sh --release

# Full condition matrix (baseline + mvcc_off + encryption_off) — long run (~45 min)
python3 Scripts/run_core_benchmark_matrix.py

python3 Scripts/generate_latency_report.py
```

Run the full suite refresh (core + limits + sqlite + latency + GC + resource/power proxies + live status docs):

```bash
python3 Scripts/refresh_benchmark_suite.py
```

Fast refresh variants:

```bash
# Only resource/power proxy metrics
python3 Scripts/refresh_benchmark_suite.py --skip-core --skip-gc

# Only core docs (no GC/power test runs)
python3 Scripts/refresh_benchmark_suite.py --skip-gc --skip-power
```

Results are saved to:
- `Docs/Benchmarks/RESULTS.md` (human-readable; published by comparison script)
- `Docs/Benchmarks/COMPARISON.md` (BlazeDB vs SQLite headline table)
- `Docs/Benchmarks/results.json` (machine-readable baseline rows)
- `Docs/Benchmarks/results_matrix.json` (condition run metadata + sanitized per-condition excerpts)
- `Docs/Benchmarks/BENCHMARK_ENVIRONMENT.md` (device fingerprint + supported toggle matrix)
- `Docs/Benchmarks/benchmark_environment.json` (machine-readable benchmark environment metadata)
- `Docs/Benchmarks/LATENCY.md` (latency-focused report with p50/p95/p99 when available)
- `Docs/Benchmarks/latency_measurements.json` (machine-readable latency report)
- `Docs/Benchmarks/FULL_BENCHMARK_SUMMARY.md` (consolidated benchmark view)
- `Docs/Benchmarks/GC_BENCHMARKS.md` (garbage collection / vacuum benchmark results)
- `Docs/Benchmarks/POWER_BENCHMARKS.md` (resource/power-proxy benchmark results)
- `Docs/Benchmarks/ENERGY.md` (first-class numeric energy/resource metrics and proxy index)
- `Docs/Benchmarks/OBSERVABILITY_BENCHMARKS.md` (logging/observability measurement coverage)
- `Docs/Benchmarks/RUN_STATUS.md` (live status while refresh script runs)

Local run logs are written under `Docs/Benchmarks/logs/` during refreshes for debugging, but that directory is intentionally ignored and should not be committed.

To include optional percentile test captures:

```bash
python3 Scripts/generate_latency_report.py --run-query-percentiles --run-telemetry-percentiles
```

---

## What changed since March 2026

Historical benchmark numbers dropped sharply after security hardening — not because the storage engine regressed.

| Date | Change | Effect on metrics |
|------|--------|-------------------|
| Mar 14 AM | Last pre-600k `RESULTS.md` refresh (`18f0ceb5`) | Cold open ~55 ms (10k PBKDF2, warm-ish averaging) |
| Mar 14 PM | Per-DB salt + 600k PBKDF2 (`7b198dea`) | Cold open ~1.1 s; inserts/reads largely unchanged |
| Jun 29 | In-process session keys (`5dd4da82`) | Warm reopen ~26 ms; cold open still ~1.1 s |

**KDF policy (current):** Release builds use **600,000** PBKDF2-HMAC-SHA256 iterations. Cold open always pays full KDF. Warm reopen in the same process reuses the verified session key. This matches OWASP guidance for password-based key derivation while keeping steady-state opens fast. Lowering iterations requires an explicit threat-model decision — see [`DATABASE_SESSION_KEY_LIFECYCLE.md`](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md).

**Do not cite** pre-June-2026 cold-open numbers or `PERFORMANCE.md` design targets as current production performance.

---

## Benchmark Methodology

- **Same hardware** - All benchmarks run on the same machine
- **Same dataset** - Identical data for BlazeDB and SQLite
- **Same language** - Swift for both (SQLite via C API)
- **Cold caches** - Each benchmark starts fresh (unless noted)
- **Condition matrix** - Core benchmarks are run under requested permutations (MVCC/WAL/encryption requests) with support status attached per row.

### Condition Coverage

- `mvcc on/off`: supported and measured.
- `wal off`: currently not supported in core engine (rows marked `partially_supported` with effective `wal=on`).
- `encryption off`: supported for benchmarks only via compile-time flag (`BLAZEDB_BENCHMARK_NO_ENCRYPTION`), never as a runtime production toggle.

### Batch Throughput Profiles

- `durable profile` rows: persist after every batch (closer to durability-first behavior).
- `max profile` rows: larger batches with one persist at the end (peak throughput mode).
- Both are measured and published together so throughput claims always include durability context.

---

## Interpreting Results

**Higher is better** for throughput benchmarks (ops/sec).

**Lower is better** for latency benchmarks (ms).

## Source-of-Truth Notes

- Treat `Docs/Benchmarks/*.md` and `Docs/Benchmarks/*.json` generated by scripts as the canonical current numbers.
- Older architecture/audit/archive documents may include historical or theoretical throughput figures that are not directly comparable to current durability-enabled local benchmark runs.
- In particular, batch throughput claims from older docs should be validated against current `RESULTS.md`, `LATENCY.md`, and `FULL_BENCHMARK_SUMMARY.md`.

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
