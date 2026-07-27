# BlazeRecord encoder/decoder notes

This page previously published free-floating percentage tables for “JSON intermediate” vs “direct” BlazeRecord encoding. Those numbers were **not** tied to the maintained benchmark suite and must not be cited as product performance claims (including any “faster than SQLite” reading).

## What is real

BlazeDB includes direct record encode/decode paths in the core engine so typed storage does not require a JSON round-trip for every write or read. That architectural choice is real; inventing fixed “20–50% faster” marketing tables is not.

## Where measured numbers live

For reproducible performance discussion, use:

- [Docs/Benchmarks/README.md](../Benchmarks/README.md) — methodology and how to run
- [Docs/Benchmarks/COMPARISON.md](../Benchmarks/COMPARISON.md) — BlazeDB vs SQLite headline metrics
- [Docs/Benchmarks/RESULTS.md](../Benchmarks/RESULTS.md) — published result tables
- [Docs/Benchmarks/LATENCY.md](../Benchmarks/LATENCY.md) — latency-focused reports

If you need encoder-specific microbenchmarks, add them to the benchmark harness and publish through that path. Do not restore unsupported percentage slogans to this file.
