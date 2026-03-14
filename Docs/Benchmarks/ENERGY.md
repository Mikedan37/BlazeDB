# Energy and Resource Metrics

_Auto-generated on 2026-03-14T09:07:05+00:00 by `Scripts/refresh_benchmark_suite.py`._

## Raw Metrics

| Step | Clock avg (s) | CPU time avg (s) | CPU cycles avg (kC) | Memory avg (kB) | Memory peak avg (kB) | Disk writes avg (kB) |
|---|---:|---:|---:|---:|---:|---:|
| `resource_insert_perf` | `0.479` | `0.011` | `1830281.195` | `10901.190` | `44102.558` | `0.000` |
| `resource_bulk_insert_perf` | `0.485` | `0.011` | `1814995.708` | `31278.541` | `87390.115` | `13307.909` |

## Energy Proxy Index

_Not a battery-joules measurement; use for relative comparisons on the same machine only._

| Step | Energy proxy index |
|---|---:|
| `resource_bulk_insert_perf` | `1924.334` |
| `resource_insert_perf` | `1884.350` |

## Notes

- This document is first-class numeric output for energy/resource reporting in CLI runs.
- For true device battery/energy instrumentation, use Xcode Instruments energy profiling.
