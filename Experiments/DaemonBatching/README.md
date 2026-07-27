# DaemonBatching (research harness)

**Research harness only. Not a supported BlazeDB product or compatibility surface.**

Do not list this in README tools. Do not ship an SDK. Do not invent a BlazeServer brand here.

## Purpose

Answer one question:

> How much throughput can coordinated batching recover while preserving single-writer ownership?

Not: “Should BlazeDB become a server database?”

## Intended scope (when implemented)

- one daemon process owning one database
- Unix domain socket locally
- fixed request format
- put / get / batch only
- configurable batch window and client count
- compare: in-process vs daemon unbatched vs daemon batched
- report p50 / p95 / p99, throughput, queue depth, fsync count, batch size, crash/restart

## Product gate

Promote nothing from this folder unless **both** are true:

1. Measured benefit is material under a stated durability mode
2. A real multi-process ownership need exists that embedding (Vapor, C ABI, one owning service) does not already cover

See: [ENGINE_VS_DAEMON_BENCHMARKS.md](../../Docs/Guarantees/ENGINE_VS_DAEMON_BENCHMARKS.md)

## Status

Scaffold / decision placeholder. Harness code may land later as an experiment. Until then, this directory documents scope only.
