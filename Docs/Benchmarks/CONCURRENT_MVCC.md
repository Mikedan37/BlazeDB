# BlazeDB MVCC — Concurrent Read Comparison

_Generated 2026-06-30T19:59:01+00:00_

Benchmark workload: **8 concurrent readers + 1 writer**, 5 seconds, 1000 seeded records, encrypted release build.

**Benchmark:** `Concurrent read (8 readers + 1 writer, 5s)`

| Engine | MVCC | Read throughput | Implied avg read latency | vs SQLite reads | MVCC on vs off |
|--------|------|----------------:|-------------------------:|----------------:|---------------:|
| BlazeDB | on | 3,142 ops/s | 0.32 ms | 54.5× faster than SQLite | 4.4× faster (MVCC off) |
| BlazeDB | off (prod default) | 13,976 ops/s | 0.07 ms | 266.6× faster than SQLite | baseline |
| SQLite | n/a | 58 ops/s | 17.35 ms | — | — |

## Notes

- This is the workload MVCC is designed for: readers should not block on an active writer.
- Single-threaded sequential benchmarks (#3) are **not** representative of MVCC value.
- Production BlazeDB defaults to **MVCC off** unless `setMVCCEnabled(true)` is called.

## Source files

- `benchmark_results/concurrent/baseline.json`
- `benchmark_results/concurrent/mvcc_off.json`
