# BlazeDB vs SQLite — Comparison Report

_Generated 2026-07-28T04:01:21+00:00_

Two BlazeDB conditions vs plain SQLite (WAL + `synchronous=FULL`, no encryption):

| Condition | Encryption | Purpose |
|-----------|------------|---------|
| `baseline` | on (AES-256-GCM + PBKDF2) | Production-secure path (MVCC on in harness) |
| `engine_only` | off (benchmark compile flag) | Engine overhead without crypto |
| SQLite | n/a | Reference embedded store |

## Headline metrics

| Benchmark | BlazeDB secure avg ms | BlazeDB engine-only avg ms | SQLite avg ms | Secure vs SQLite | Engine vs SQLite |
|-----------|----------------------:|---------------------------:|--------------:|-----------------:|-----------------:|
| Insert per-row durable (1K records) | 2.53 | 2.50 | 0.0030 | 830.3× slower | 886.2× slower |
| InsertMany (10K records, batch 100) | 124.07 | 121.22 | 0.08 | 1515.1× slower | 1828.3× slower |
| Read (1K records) | 0.0095 | N/A | 0.0012 | 7.7× slower | N/A |
| Cold open (PBKDF2 each reopen) | 1045.14 | 1060.78 | 0.59 | 1760.4× slower | 3266.0× slower |
| Warm reopen (session cache) | 24.77 | 24.77 | N/A | N/A | N/A |
| InsertMany (max profile, batch 1000) | 408.24 | 391.26 | 0.62 | 657.2× slower | 659.5× slower |

## Concurrent read (from full baseline run)

| Concurrent read (8 readers + 1 writer, 5s) | BlazeDB 3,349 reads/s | SQLite 97 reads/s | 34.6× faster |

## How to read this

- **Honest label:** BlazeDB is **read-optimized** with an **expensive durability path** — see `Docs/Benchmarks/HONEST_PERFORMANCE.md`. Do not treat this table as “BlazeDB is slow” or “BlazeDB is fast.”
- **Secure vs SQLite** / **Engine vs SQLite** show latency ratio (e.g. `3.6× slower` = BlazeDB took 3.6× longer than SQLite).
- **Insert per-row durable** compares BlazeDB `insert()` to SQLite `BEGIN IMMEDIATE` + `INSERT` + `COMMIT` per row (one fsync each). ~2.5 ms on 1K (~274 ops/s) is a real write-path weakness; 10K degrading toward ~24 ms/op needs size-scaling investigation (`./Scripts/run_db_size_sweep.sh`).
- **InsertMany** compares BlazeDB `insertMany(batch)` to SQLite one transaction per batch (fair bulk throughput).
- **Warm reopen** has no SQLite column (SQLite has no in-process session cache).
- SQLite here is **plaintext**. A crypto-fair peer (SQLCipher / encrypted SQLite) is still a **gap** — do not claim encryption is free or that the gap is only crypto.
- Prefer **p50/p95/p99** from RESULTS / LATENCY over averages alone. Core row size is `encodedPayloadBytes` (~53 B standard), not the 1 MB growth profile.
- Do not use `engine_only` with real data — compile-time benchmark flag only.
- Stage attribution for durable inserts: `BLAZEDB_BENCH_MODE=write_profile` / issue #425.
- For MVCC on vs off under contention, run `./Scripts/run_concurrent_mvcc_comparison.sh --release`.

## Source files

- `benchmark_results/comparison/baseline.json`
- `benchmark_results/comparison/engine_only.json`
