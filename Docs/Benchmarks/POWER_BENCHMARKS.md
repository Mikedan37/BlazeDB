# Resource and Power Proxy Benchmarks

_Auto-generated on 2026-03-14T08:15:48+00:00 by `Scripts/refresh_benchmark_suite.py`._

| Benchmark | Status | Seconds | Summary |
|---|---|---:|---|
| `resource_insert_perf` | `pass` | `3.803` | Executed 1 test, with 0 failures |
| `resource_bulk_insert_perf` | `pass` | `2.696` | Executed 1 test, with 0 failures |
| `opt_async_io_perf` | `pass` | `1.188` | Executed 1 test, with 0 failures |
| `opt_write_batching_perf` | `pass` | `1.233` | Executed 1 test, with 0 failures |
| `opt_combined_perf` | `pass` | `1.294` | Executed 1 test, with 0 failures |
| `opt_compression_storage` | `pass` | `1.174` | Executed 1 test, with 0 failures |

## Extracted XCT Metrics

| Step | Metric | Unit | Average | Samples |
|---|---|---|---:|---:|
| `resource_insert_perf` | Memory Physical | `kB` | `8886.754` | `5` |
| `resource_insert_perf` | CPU Cycles | `kC` | `1690043.064` | `5` |
| `resource_insert_perf` | Clock Monotonic Time | `s` | `0.431` | `5` |
| `resource_insert_perf` | CPU Time | `s` | `0.010` | `5` |
| `resource_insert_perf` | CPU Instructions Retired | `kI` | `8999014.829` | `5` |
| `resource_insert_perf` | Memory Peak Physical | `kB` | `38402.373` | `5` |
| `resource_bulk_insert_perf` | Disk Logical Writes | `kB` | `13220.528` | `3` |
| `resource_bulk_insert_perf` | Clock Monotonic Time | `s` | `0.425` | `3` |
| `resource_bulk_insert_perf` | CPU Time | `s` | `0.010` | `3` |
| `resource_bulk_insert_perf` | Memory Physical | `kB` | `22238.637` | `3` |
| `resource_bulk_insert_perf` | CPU Instructions Retired | `kI` | `8905268.303` | `3` |
| `resource_bulk_insert_perf` | Memory Peak Physical | `kB` | `77775.261` | `3` |
| `resource_bulk_insert_perf` | CPU Cycles | `kC` | `1676594.793` | `3` |

## Extracted Custom Performance Numbers

| Step | Metric | Value |
|---|---|---:|
| `opt_async_io_perf` | `async_sync_ms` | `5.340` |
| `opt_async_io_perf` | `async_async_ms` | `0.380` |
| `opt_async_io_perf` | `speedup_x` | `14.060` |
| `opt_write_batching_perf` | `speedup_x` | `4.770` |
| `opt_write_batching_perf` | `batch_individual_ms` | `39.920` |
| `opt_write_batching_perf` | `batch_batch_ms` | `8.373` |
| `opt_combined_perf` | `combined_records` | `1000.000` |
| `opt_combined_perf` | `combined_time_ms` | `117.789` |
| `opt_combined_perf` | `combined_ops_per_sec` | `8490.000` |
| `opt_compression_storage` | `compression_without` | `85 KB` |
| `opt_compression_storage` | `compression_with` | `167 KB` |
| `opt_compression_storage` | `compression_savings_percent` | `-96.400` |

## Notes

- These are resource/power proxy runs from performance tests that instrument clock/CPU/memory/storage metrics.
- CLI `swift test` exposes wall-clock summaries; for full Xcode metric distributions use result bundles in Xcode/CI.
