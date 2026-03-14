# Full Benchmark Suite Summary

_Auto-generated on 2026-03-14T08:15:48+00:00 by `Scripts/refresh_benchmark_suite.py`._

## Core Performance and Latency

| Condition | Support | Benchmark | BlazeDB ops/sec | avg ms | p50 ms | p95 ms | p99 ms |
|---|---|---|---:|---:|---:|---:|---:|
| baseline | supported | Insert (1K records) | 163 | 5.938 | 6.167 | 11.217 | 12.154 |
| baseline | supported | Insert (10K records) | 16 | 61.402 | 60.843 | 114.865 | 122.258 |
| baseline | supported | Read (1K records) | 324260 | 0.003 | 0.003 | 0.003 | 0.003 |
| baseline | supported | InsertMany (10K records, batch 100) | 184 | 537.712 | 521.469 | 1003.970 | 1083.476 |
| baseline | supported | DeleteMany (10K records, batch 100) | 800 | 124.889 | 123.574 | 221.825 | 231.239 |
| baseline | supported | InsertMany (durable profile, batch 100) | 154 | 648.817 | 639.536 | 1215.778 | 1256.710 |
| baseline | supported | InsertMany (max profile, batch 1000) | 333 | 2962.696 | 3344.067 | 4895.406 | 4895.406 |
| baseline | supported | DeleteMany (durable profile, batch 100) | 426 | 234.432 | 231.430 | 419.901 | 450.691 |
| baseline | supported | DeleteMany (max profile, batch 1000) | 4326 | 229.745 | 242.627 | 326.851 | 326.851 |
| baseline | supported | Cold open | 19 | 52.387 | 52.507 | 53.328 | 53.328 |
| mvcc_off | supported | Insert (1K records) | 167 | 5.795 | 5.632 | 11.361 | 13.104 |
| mvcc_off | supported | Insert (10K records) | 18 | 54.483 | 51.556 | 99.599 | 107.684 |
| mvcc_off | supported | Read (1K records) | 291798 | 0.003 | 0.003 | 0.005 | 0.008 |
| mvcc_off | supported | InsertMany (10K records, batch 100) | 199 | 497.570 | 510.684 | 919.450 | 989.313 |
| mvcc_off | supported | DeleteMany (10K records, batch 100) | 824 | 121.229 | 126.568 | 210.605 | 218.676 |
| mvcc_off | supported | InsertMany (durable profile, batch 100) | 168 | 592.995 | 588.620 | 1095.203 | 1154.493 |
| mvcc_off | supported | InsertMany (max profile, batch 1000) | 388 | 2535.989 | 2853.968 | 4447.802 | 4447.802 |
| mvcc_off | supported | DeleteMany (durable profile, batch 100) | 434 | 230.155 | 231.546 | 412.358 | 430.712 |
| mvcc_off | supported | DeleteMany (max profile, batch 1000) | 6910 | 142.878 | 147.137 | 229.467 | 229.467 |
| mvcc_off | supported | Cold open | 16 | 62.470 | 52.042 | 52.773 | 52.773 |

## Benchmark Environment

- Device ID: `ae4ee458c66596a255d5`
- Host: `MacBook-Pro-2.local`
- OS: `Darwin 25.4.0`
- Arch: `x86_64`
- Git: `week1/stabilization-20260308` @ `b551dd5d58d9232e5e9452c903ef4a00cb1882b2`

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
| `gc_mark_reuse` | `pass` | `31.250` |
| `gc_multiple_pages` | `pass` | `1.283` |
| `gc_reuse_rate` | `pass` | `1.272` |

## Resource/Power Proxy Signals

| Benchmark | Status | Seconds |
|---|---|---:|
| `resource_insert_perf` | `pass` | `3.803` |
| `resource_bulk_insert_perf` | `pass` | `2.696` |
| `opt_async_io_perf` | `pass` | `1.188` |
| `opt_write_batching_perf` | `pass` | `1.233` |
| `opt_combined_perf` | `pass` | `1.294` |
| `opt_compression_storage` | `pass` | `1.174` |

### Power/Resource Metric Highlights

- `resource_insert_perf` `Memory Physical` avg `8886.754 kB`
- `resource_insert_perf` `CPU Cycles` avg `1690043.064 kC`
- `resource_insert_perf` `Clock Monotonic Time` avg `0.431 s`
- `resource_insert_perf` `CPU Time` avg `0.010 s`
- `resource_insert_perf` `Memory Peak Physical` avg `38402.373 kB`
- `resource_bulk_insert_perf` `Disk Logical Writes` avg `13220.528 kB`
- `resource_bulk_insert_perf` `Clock Monotonic Time` avg `0.425 s`
- `resource_bulk_insert_perf` `CPU Time` avg `0.010 s`
- `resource_bulk_insert_perf` `Memory Physical` avg `22238.637 kB`
- `resource_bulk_insert_perf` `Memory Peak Physical` avg `77775.261 kB`
- `resource_bulk_insert_perf` `CPU Cycles` avg `1676594.793 kC`

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
