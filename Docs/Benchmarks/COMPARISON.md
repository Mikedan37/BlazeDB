# BlazeDB vs SQLite — Comparison Report

_Generated 2026-07-01T06:19:57+00:00_

Two BlazeDB conditions vs plain SQLite (WAL + `synchronous=FULL`, no encryption):

| Condition | Encryption | Purpose |
|-----------|------------|---------|
| `baseline` | on (AES-256-GCM + PBKDF2) | Production-secure path (MVCC on in harness) |
| `engine_only` | off (benchmark compile flag) | Engine overhead without crypto |
| SQLite | n/a | Reference embedded store |

## Headline metrics

| Benchmark | BlazeDB secure avg ms | BlazeDB engine-only avg ms | SQLite avg ms | Secure vs SQLite | Engine vs SQLite |
|-----------|----------------------:|---------------------------:|--------------:|-----------------:|-----------------:|
| Insert per-row durable (1K records) | 2.44 | 2.50 | 0.0032 | 761.9× slower | 786.7× slower |
| InsertMany (10K records, batch 100) | 117.68 | 118.77 | 0.07 | 1700.7× slower | 1752.3× slower |
| Read (1K records) | 0.0097 | N/A | 0.0015 | 6.5× slower | N/A |
| Cold open (PBKDF2 each reopen) | 1136.16 | 1152.52 | 0.85 | 1337.3× slower | 981.0× slower |
| Warm reopen (session cache) | 26.86 | 27.31 | N/A | N/A | N/A |
| InsertMany (max profile, batch 1000) | 335.81 | 304.92 | 0.65 | 513.5× slower | 477.4× slower |

## Concurrent read (from full baseline run)

| Concurrent read (8 readers + 1 writer, 5s) | BlazeDB 2,887 reads/s | SQLite 45 reads/s | 64.3× faster |

## How to read this

- **Secure vs SQLite** / **Engine vs SQLite** show latency ratio (e.g. `3.6× slower` = BlazeDB took 3.6× longer than SQLite).
- **Insert per-row durable** compares BlazeDB `insert()` to SQLite `BEGIN IMMEDIATE` + `INSERT` + `COMMIT` per row (one fsync each).
- **InsertMany** compares BlazeDB `insertMany(batch)` to SQLite one transaction per batch (fair bulk throughput).
- **Warm reopen** has no SQLite column (SQLite has no in-process session cache).
- Do not use `engine_only` with real data — compile-time benchmark flag only.
- For MVCC on vs off under contention, run `./Scripts/run_concurrent_mvcc_comparison.sh --release`.

## Source files

- `benchmark_results/comparison/baseline.json`
- `benchmark_results/comparison/engine_only.json`
