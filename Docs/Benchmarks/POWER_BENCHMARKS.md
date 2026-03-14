# Resource and Power Proxy Benchmarks

_Auto-generated on 2026-03-14T09:07:05+00:00 by `Scripts/refresh_benchmark_suite.py`._

| Benchmark | Status | Seconds | Summary |
|---|---|---:|---|
| `resource_insert_perf` | `pass` | `4.165` | Executed 1 test, with 0 failures |
| `resource_bulk_insert_perf` | `pass` | `3.010` | Executed 1 test, with 0 failures |
| `opt_async_io_perf` | `pass` | `1.296` | Executed 1 test, with 0 failures |
| `opt_write_batching_perf` | `pass` | `1.314` | Executed 1 test, with 0 failures |
| `opt_combined_perf` | `pass` | `1.436` | Executed 1 test, with 0 failures |
| `opt_compression_storage` | `pass` | `1.316` | Executed 1 test, with 0 failures |

## Extracted XCT Metrics

| Step | Metric | Unit | Average | Samples |
|---|---|---|---:|---:|
| `resource_insert_perf` | Memory Physical | `kB` | `10901.190` | `5` |
| `resource_insert_perf` | CPU Cycles | `kC` | `1830281.195` | `5` |
| `resource_insert_perf` | Clock Monotonic Time | `s` | `0.479` | `5` |
| `resource_insert_perf` | CPU Time | `s` | `0.011` | `5` |
| `resource_insert_perf` | CPU Instructions Retired | `kI` | `9035924.813` | `5` |
| `resource_insert_perf` | Memory Peak Physical | `kB` | `44102.558` | `5` |
| `resource_bulk_insert_perf` | Disk Logical Writes | `kB` | `13307.909` | `3` |
| `resource_bulk_insert_perf` | Clock Monotonic Time | `s` | `0.485` | `3` |
| `resource_bulk_insert_perf` | CPU Time | `s` | `0.011` | `3` |
| `resource_bulk_insert_perf` | Memory Physical | `kB` | `31278.541` | `3` |
| `resource_bulk_insert_perf` | CPU Instructions Retired | `kI` | `8942682.843` | `3` |
| `resource_bulk_insert_perf` | Memory Peak Physical | `kB` | `87390.115` | `3` |
| `resource_bulk_insert_perf` | CPU Cycles | `kC` | `1814995.708` | `3` |

## Extracted Custom Performance Numbers

| Step | Metric | Value |
|---|---|---:|
| `opt_async_io_perf` | `async_sync_ms` | `5.940` |
| `opt_async_io_perf` | `async_async_ms` | `0.420` |
| `opt_async_io_perf` | `speedup_x` | `14.140` |
| `opt_write_batching_perf` | `speedup_x` | `4.640` |
| `opt_write_batching_perf` | `batch_individual_ms` | `46.462` |
| `opt_write_batching_perf` | `batch_batch_ms` | `10.017` |
| `opt_combined_perf` | `combined_records` | `1000.000` |
| `opt_combined_perf` | `combined_time_ms` | `139.666` |
| `opt_combined_perf` | `combined_ops_per_sec` | `7160.000` |
| `opt_compression_storage` | `compression_without` | `85 KB` |
| `opt_compression_storage` | `compression_with` | `167 KB` |
| `opt_compression_storage` | `compression_savings_percent` | `-96.400` |

## Notes

- These are resource/power proxy runs from performance tests that instrument clock/CPU/memory/storage metrics.
- CLI `swift test` exposes wall-clock summaries; for full Xcode metric distributions use result bundles in Xcode/CI.
