# Legacy XCTest Performance Suites

These XCTest performance suites are legacy and non-gating.

- They are intentionally excluded from correctness targets.
- Canonical benchmark execution is `swift run BlazeDBBenchmarks`.
- Benchmark artifacts must be read from `.artifacts/benchmarks/<timestamp>/`.

Do not reintroduce these files into Tier0/Tier1 lanes.
