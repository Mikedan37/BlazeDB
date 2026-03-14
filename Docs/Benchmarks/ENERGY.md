# Energy and Resource Metrics

_Auto-generated on 2026-03-14T08:15:48+00:00 by `Scripts/refresh_benchmark_suite.py`._

## Raw Metrics

| Step | Clock avg (s) | CPU time avg (s) | CPU cycles avg (kC) | Memory avg (kB) | Memory peak avg (kB) | Disk writes avg (kB) |
|---|---:|---:|---:|---:|---:|---:|
| `resource_insert_perf` | `0.431` | `0.010` | `1690043.064` | `8886.754` | `38402.373` | `0.000` |
| `resource_bulk_insert_perf` | `0.425` | `0.010` | `1676594.793` | `22238.637` | `77775.261` | `13220.528` |

## Energy Proxy Index

_Not a battery-joules measurement; use for relative comparisons on the same machine only._

| Step | Energy proxy index |
|---|---:|
| `resource_bulk_insert_perf` | `1775.458` |
| `resource_insert_perf` | `1737.545` |

## Notes

- This document is first-class numeric output for energy/resource reporting in CLI runs.
- For true device battery/energy instrumentation, use Xcode Instruments energy profiling.
