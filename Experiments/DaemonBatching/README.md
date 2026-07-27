# DaemonBatching (research harness)

**Research harness only. Not a supported BlazeDB product or compatibility surface.**

Do not list this in README tools. Do not ship an SDK. Do not invent a BlazeServer brand here.

## What this is not proving

The architecture pattern already works. Owning services such as BlazeAgent show:

```text
clients → daemon / agent service → one BlazeDB owner
```

That is a real application that owns BlazeDB through a daemon. It is not this harness, and it is not a BlazeDB daemon product.

## Purpose

Answer one narrower question:

> How much performance do batching, group commit, and queue coordination add compared with direct embedding and unbatched daemon access?

Prefer realistic request patterns (replay from an owning service when available) over synthetic banana traffic.

Not: “Can one owner mediate many clients?” (already proven)  
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
2. A real generalized multi-process product need exists that application-owned services (BlazeAgent, Vapor, C ABI embed) do not already cover

See: [ENGINE_VS_DAEMON_BENCHMARKS.md](../../Docs/Guarantees/ENGINE_VS_DAEMON_BENCHMARKS.md)

## Status

Scaffold / decision placeholder. Harness code may land later as an experiment. Until then, this directory documents scope only.
