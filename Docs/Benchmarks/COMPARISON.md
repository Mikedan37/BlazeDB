# BlazeDB vs SQLite — Comparison Report

_Generated 2026-06-30T19:07:34+00:00_

Two BlazeDB conditions vs plain SQLite (WAL + `synchronous=FULL`, no encryption):

| Condition | Encryption | Purpose |
|-----------|------------|---------|
| `baseline` | on (AES-256-GCM + PBKDF2) | Production-secure path |
| `engine_only` | off (benchmark compile flag) | Engine overhead without crypto |
| SQLite | n/a | Reference embedded store |

## Headline metrics

| Benchmark | BlazeDB secure avg ms | BlazeDB engine-only avg ms | SQLite avg ms | Secure vs SQLite | Engine vs SQLite |
|-----------|----------------------:|---------------------------:|--------------:|-----------------:|-----------------:|
| Insert (1K records) | 2.50 | 2.44 | 0.0007 | 3540.0× slower | 3989.4× slower |
| Read (1K records) | 0.0091 | N/A | 0.0013 | 6.9× slower | N/A |
| Cold open (PBKDF2 each reopen) | 1117.74 | 1138.05 | 0.59 | 1909.1× slower | 1503.0× slower |
| Warm reopen (session cache) | 26.23 | 26.80 | N/A | N/A | N/A |
| InsertMany (max profile, batch 1000) | 334.43 | 310.15 | 0.62 | 540.4× slower | 511.6× slower |

## How to read this

- **Secure vs SQLite** / **Engine vs SQLite** show latency ratio (e.g. `3.6× slower` = BlazeDB took 3.6× longer than SQLite).
- **Warm reopen** has no SQLite column (SQLite has no in-process session cache).
- Do not use `engine_only` with real data — compile-time benchmark flag only.

## Source files

- `benchmark_results/comparison/baseline.json`
- `benchmark_results/comparison/engine_only.json`
