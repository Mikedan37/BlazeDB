# Full Benchmark Suite Summary

_Auto-generated on 2026-03-14T09:07:05+00:00 by `Scripts/refresh_benchmark_suite.py`._

## Core Performance and Latency

| Condition | Support | Benchmark | BlazeDB ops/sec | avg ms | p50 ms | p95 ms | p99 ms |
|---|---|---|---:|---:|---:|---:|---:|
| baseline | supported | Insert (1K records) | 162 | 5.999 | 6.032 | 11.305 | 14.814 |
| baseline | supported | Insert (10K records) | 16 | 61.841 | 60.925 | 113.924 | 128.836 |
| baseline | supported | Read (1K records) | 314663 | 0.003 | 0.003 | 0.003 | 0.004 |
| baseline | supported | InsertMany (10K records, batch 100) | 193 | 514.313 | 522.712 | 925.493 | 990.908 |
| baseline | supported | DeleteMany (10K records, batch 100) | 810 | 123.357 | 122.901 | 215.263 | 224.654 |
| baseline | supported | InsertMany (durable profile, batch 100) | 159 | 625.991 | 625.524 | 1139.999 | 1208.928 |
| baseline | supported | InsertMany (max profile, batch 1000) | 341 | 2892.608 | 3149.518 | 4680.696 | 4680.696 |
| baseline | supported | DeleteMany (durable profile, batch 100) | 355 | 281.517 | 275.137 | 536.757 | 583.420 |
| baseline | supported | DeleteMany (max profile, batch 1000) | 4117 | 241.410 | 258.686 | 333.789 | 333.789 |
| baseline | supported | Cold open | 18 | 54.684 | 54.663 | 56.637 | 56.637 |
| mvcc_off | supported | Insert (1K records) | 147 | 6.599 | 6.205 | 12.276 | 14.764 |
| mvcc_off | supported | Insert (10K records) | 18 | 54.820 | 52.416 | 97.269 | 103.854 |
| mvcc_off | supported | Read (1K records) | 286203 | 0.003 | 0.003 | 0.004 | 0.005 |
| mvcc_off | supported | InsertMany (10K records, batch 100) | 201 | 493.892 | 479.952 | 935.599 | 974.842 |
| mvcc_off | supported | DeleteMany (10K records, batch 100) | 880 | 113.534 | 111.296 | 206.124 | 217.224 |
| mvcc_off | supported | InsertMany (durable profile, batch 100) | 166 | 598.727 | 596.381 | 1111.660 | 1151.946 |
| mvcc_off | supported | InsertMany (max profile, batch 1000) | 382 | 2575.766 | 2915.454 | 4396.211 | 4396.211 |
| mvcc_off | supported | DeleteMany (durable profile, batch 100) | 430 | 232.718 | 225.870 | 466.554 | 603.933 |
| mvcc_off | supported | DeleteMany (max profile, batch 1000) | 6800 | 144.959 | 156.277 | 232.721 | 232.721 |
| mvcc_off | supported | Cold open | 15 | 67.009 | 56.129 | 59.140 | 59.140 |
| encryption_off_requested | supported | Insert (1K records) | 156 | 6.227 | 6.479 | 11.605 | 13.767 |
| encryption_off_requested | supported | Insert (10K records) | 16 | 63.231 | 61.983 | 118.686 | 130.571 |
| encryption_off_requested | supported | Read (1K records) | 293606 | 0.003 | 0.003 | 0.004 | 0.004 |
| encryption_off_requested | supported | InsertMany (10K records, batch 100) | 186 | 532.852 | 538.744 | 1013.571 | 1083.913 |
| encryption_off_requested | supported | DeleteMany (10K records, batch 100) | 815 | 122.493 | 118.409 | 219.406 | 226.536 |
| encryption_off_requested | supported | InsertMany (durable profile, batch 100) | 154 | 648.263 | 641.844 | 1220.957 | 1387.281 |
| encryption_off_requested | supported | InsertMany (max profile, batch 1000) | 347 | 2833.653 | 3215.981 | 4710.831 | 4710.831 |
| encryption_off_requested | supported | DeleteMany (durable profile, batch 100) | 435 | 229.817 | 231.208 | 419.947 | 435.398 |
| encryption_off_requested | supported | DeleteMany (max profile, batch 1000) | 6693 | 147.359 | 153.535 | 235.145 | 235.145 |
| encryption_off_requested | supported | Cold open | 18 | 54.557 | 54.750 | 55.384 | 55.384 |

## Benchmark Environment

- Device ID: `ae4ee458c66596a255d5`
- Host: `MacBook-Pro-2.local`
- OS: `Darwin 25.4.0`
- Arch: `x86_64`
- Git: `week1/stabilization-20260308` @ `8664b1bef7245963965b65cd510e94f35e9bc116`

## Real Limits and Growth

- Max blob round-trip: `40523994` bytes
- Max string round-trip: `40523994` bytes
- Growth final size: `1076461568` bytes
- Growth elapsed: `8.850` seconds
- Growth throughput: `120.23` records/sec
- Growth average write latency: `8.318` ms/op

## GC Benchmark Signals

| Benchmark | Status | Seconds |
|---|---|---:|
| `gc_mark_reuse` | `pass` | `29.485` |
| `gc_multiple_pages` | `pass` | `1.385` |
| `gc_reuse_rate` | `pass` | `1.365` |

## Resource/Power Proxy Signals

| Benchmark | Status | Seconds |
|---|---|---:|
| `resource_insert_perf` | `pass` | `4.165` |
| `resource_bulk_insert_perf` | `pass` | `3.010` |
| `opt_async_io_perf` | `pass` | `1.296` |
| `opt_write_batching_perf` | `pass` | `1.314` |
| `opt_combined_perf` | `pass` | `1.436` |
| `opt_compression_storage` | `pass` | `1.316` |

### Power/Resource Metric Highlights

- `resource_insert_perf` `Memory Physical` avg `10901.190 kB`
- `resource_insert_perf` `CPU Cycles` avg `1830281.195 kC`
- `resource_insert_perf` `Clock Monotonic Time` avg `0.479 s`
- `resource_insert_perf` `CPU Time` avg `0.011 s`
- `resource_insert_perf` `Memory Peak Physical` avg `44102.558 kB`
- `resource_bulk_insert_perf` `Disk Logical Writes` avg `13307.909 kB`
- `resource_bulk_insert_perf` `Clock Monotonic Time` avg `0.485 s`
- `resource_bulk_insert_perf` `CPU Time` avg `0.011 s`
- `resource_bulk_insert_perf` `Memory Physical` avg `31278.541 kB`
- `resource_bulk_insert_perf` `Memory Peak Physical` avg `87390.115 kB`
- `resource_bulk_insert_perf` `CPU Cycles` avg `1814995.708 kC`

## Missing Metrics

- None reported.

## Source Docs

- `Docs/Benchmarks/RESULTS.md`
- `Docs/Benchmarks/LATENCY.md`
- `Docs/Benchmarks/LIMITS.md`
- `Docs/Benchmarks/SQLITE_LIMITS_COMPARISON.md`
- `Docs/Benchmarks/BENCHMARK_ENVIRONMENT.md`
- `Docs/Benchmarks/GC_BENCHMARKS.md`
- `Docs/Benchmarks/POWER_BENCHMARKS.md`
- `Docs/Benchmarks/ENERGY.md`
- `Docs/Benchmarks/OBSERVABILITY_BENCHMARKS.md`
