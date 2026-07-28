# BlazeDB Benchmarks

**Purpose:** Honest, reproducible performance comparisons between BlazeDB and SQLite.

Engine (in-process) numbers and daemon-mediated numbers measure different boundaries. Do not mix them: [ENGINE_VS_DAEMON_BENCHMARKS.md](../Guarantees/ENGINE_VS_DAEMON_BENCHMARKS.md).

---

## What BlazeDB Is Optimized For

**Honest label:** [point reads are fast; durable writes are expensive and currently scale poorly with database size](HONEST_PERFORMANCE.md) — not “generally fast,” and not merely a fixed durability tax.

| Strength | Weakness / cost |
|----------|-----------------|
| Point reads | Durable `insert()` latency rises sharply with DB size (~0.7 ms empty → ~483 ms @100K small rows) |
| Concurrent reads (MVCC on) | Cold open (600k PBKDF2 ~1 s) |
| Encrypted-at-rest by default | Write path vs **plaintext** SQLite (no SQLCipher peer yet) |
| Crash-safe / deterministic exports | `insertMany` rejects overflow-sized records that `insert()` accepts ([#434](https://github.com/Mikedan37/BlazeDB/issues/434)) |

Do **not** claim broadly fast durable writes until size-scaling work under [#425](https://github.com/Mikedan37/BlazeDB/issues/425) explains the slope and the path improves. Published curves: [db_size_sweep.md](db_size_sweep.md), [payload_size_sweep.md](payload_size_sweep.md).

Also optimized for:

- **Embedded single-process workloads**
- **Schema versioning**
- **Local apps that batch writes** (`insertMany` / transactions)

---

## Where SQLite Still Wins

- **Raw durable insert throughput** (especially plaintext WAL — not a crypto-fair match)
- **Query planner sophistication** (SQLite has decades of optimization)
- **Memory footprint** (SQLite is smaller)
- **Network filesystem compatibility** (SQLite handles NFS better)

---

## Why BlazeDB Uses Less Power Under Real Workloads

BlazeDB's design choices can reduce CPU burn in **read-heavy** embedded scenarios:

1. **No query planner overhead** - Queries are explicit, not optimized
2. **Batch operations** - Prefer `insertMany()` / transactions over single durable inserts (the single-write path is currently expensive — see [HONEST_PERFORMANCE.md](HONEST_PERFORMANCE.md))
3. **Deterministic encoding** - No schema inference at runtime
4. **Explicit indexes** - No automatic index creation/removal

**Trade-off:** More upfront design; do not equate “less power on reads” with “fast durable writes.”

---

## Running Benchmarks

```bash
# Front door (preferred)
chmod +x ./bench ./Scripts/bench.sh
./bench honesty          # docs + result-shape lint (fast)
./bench smoke            # honesty + short sweeps → benchmark_results/ (debug; not canonical)
./bench payload --release
./bench db-size --release
./bench full             # honesty + release db-size + all payload paths (long)
./bench publish          # full + copy sweep tables into Docs/Benchmarks/ (canonical only after this)

# Side-by-side secure vs engine-only vs SQLite (recommended; publishes RESULTS.md)
chmod +x ./Scripts/run_comparison_benchmarks.sh ./Scripts/run_concurrent_mvcc_comparison.sh
./Scripts/run_comparison_benchmarks.sh --release
# or: ./bench comparison --release

# MVCC on vs off under concurrent load (8 readers + 1 writer, ~2 min)
./Scripts/run_concurrent_mvcc_comparison.sh --release

# Full condition matrix (baseline + mvcc_off + encryption_off) — long run (~45 min)
python3 Scripts/run_core_benchmark_matrix.py

python3 Scripts/generate_latency_report.py
```

Core harness rows publish **`encodedPayloadBytes`** / **`recordShape`**, plus **p50/p95/p99**. Standard insert/read row ≈ **53 B** — **not** the 1 MB growth profile. Framing: [HONEST_PERFORMANCE.md](HONEST_PERFORMANCE.md). Size details: [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md).

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
- `Docs/Benchmarks/HONEST_PERFORMANCE.md` (read-optimized / expensive durability diagnosis)
- `Docs/Benchmarks/results.json` (machine-readable baseline rows; includes `encodedPayloadBytes` / `recordShape`)
- `Docs/Benchmarks/PAYLOAD_SIZE.md` (how size relates to latency; sweep instructions)
- `benchmark_results/payload_size/` (payload-size sweep outputs)
- `benchmark_results/db_size/` (write latency vs DB size outputs)
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

### MVCC and concurrent reads

MVCC is **off by default** in production. The old `setMVCCEnabled` doc claimed "10–100× faster" concurrent reads — that was unverified. Benchmark **#12** (`./Scripts/run_concurrent_mvcc_comparison.sh --release`) measures **8 concurrent readers + 1 writer** for 5 seconds.

See `benchmark_results/concurrent/CONCURRENT_MVCC.md` after running the script. Single-threaded benchmarks are not representative of MVCC; use #12 for MVCC claims.

---

## Benchmark Methodology

- **Same hardware** - All benchmarks run on the same machine
- **Same dataset** - Identical data for BlazeDB and SQLite
- **Same language** - Swift for both (SQLite via C API)
- **Cold caches** - Each benchmark starts fresh (unless noted)
- **Condition matrix** - Core benchmarks are run under requested permutations (MVCC/WAL/encryption requests) with support status attached per row.
- **Fair SQLite pairing**
  - **Per-row insert:** BlazeDB `insert()` vs SQLite `BEGIN IMMEDIATE` + `INSERT` + `COMMIT` per row (`synchronous=FULL`, WAL).
  - **Batch insert:** BlazeDB `insertMany(batch)` vs SQLite `BEGIN` + N× `INSERT` + `COMMIT` per batch (same batch size).
- **Record size:** core rows publish `encodedPayloadBytes` / `recordShape` (standard small `id`+`index`+short string — **not** 1 MB). Size vs latency is non-linear; see [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md) and `./Scripts/run_payload_size_sweep.sh`.

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

- **Canonical published numbers** live in `Docs/Benchmarks/` files produced by an explicit comparison / `./bench publish` path (for example [RESULTS.md](RESULTS.md), [COMPARISON.md](COMPARISON.md)). Timestamp and harness notes in those files matter.
- **Smoke / local sweeps** (`./bench smoke`, default `./Scripts/run_*_sweep.sh` without publish) write under `benchmark_results/` only. One host and one quick sweep can motivate a concern; they do **not** establish a full scaling curve or replace published baselines.
- For **durable write stage attribution**, use [WRITE_PATH_PROFILE.md](WRITE_PATH_PROFILE.md) (`BLAZEDB_BENCH_MODE=write_profile`) — investigation only, not product telemetry. Publish stage % is [#425](https://github.com/ProjectBlaze/BlazeDB/issues/425).
- For **payload size vs latency**, use [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md) (`BLAZEDB_BENCH_MODE=payload_size_sweep`) — do not infer core-row size from the 1 MB growth limit. Tables report **encoded** bytes alongside requested payload field bytes.
- For **write latency vs DB size**, use `./Scripts/run_db_size_sweep.sh` (`BLAZEDB_BENCH_MODE=db_size_sweep`) — each seed point uses a fresh temporary database.
- Prefer [COMPARISON.md](COMPARISON.md) and [HONEST_PERFORMANCE.md](HONEST_PERFORMANCE.md) over March-era `LATENCY.md` for cold-open / insert headlines (see issue #272).
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
