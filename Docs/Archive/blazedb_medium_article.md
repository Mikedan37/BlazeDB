# BlazeDB — A Swift-Native Embedded Application Database

Most Swift applications today use SQLite for local persistence.

SQLite is extremely capable, but its primary interface is a C API. In Swift projects this usually means calling the C interface directly or using wrapper libraries such as GRDB or SQLite.swift. Frameworks like Core Data and SwiftData add another abstraction layer on top.

While working on Swift tooling and local systems projects, I kept wanting a database that behaved more like a native Swift library: something installable through Swift Package Manager, integrated into the language's type system, encrypted by default, and whose behavior could be inspected and measured.

BlazeDB is an experiment in building that kind of storage engine.

BlazeDB does not attempt to replace SQLite.

SQLite has decades of engineering behind it and remains stronger in raw throughput and maximum value limits. Instead, BlazeDB explores what an embedded database might look like if it were designed from the beginning as a Swift-native application storage engine with transparent limits and reproducible behavior.

## What BlazeDB Actually Is

BlazeDB is an embedded database engine written entirely in Swift, distributed through Swift Package Manager, and designed for secure, predictable local application storage. It runs on Apple platforms and Linux, supports encrypted persistence, and focuses on transparent behavior that developers can measure and reproduce.

It is a standalone storage engine. Not a wrapper, not an ORM, and not a framework layered on top of another database. It does not depend on any external database libraries.

It is built specifically for Swift applications that need:

- Local data storage
- Encryption at rest by default
- Queryable records with flexible structure
- Predictable behavior that can be tested and inspected

It has zero external dependencies.

## What It Looks Like

```swift
import BlazeDB

let db = try BlazeDBClient.open(named: "myapp", password: "your-password")

// Insert a record
let id = try db.insert(BlazeDataRecord([
 "name": .string("Alice"),
 "role": .string("engineer"),
 "active": .bool(true)
]))

// Query with the fluent builder
let results = try db.query()
 .where("role", equals: .string("engineer"))
 .where("active", equals: .bool(true))
 .orderBy("name")
 .limit(10)
 .execute()

// Batch insert
let ids = try db.insertMany([
 BlazeDataRecord(["name": .string("Bob"), "role": .string("designer")]),
 BlazeDataRecord(["name": .string("Carol"), "role": .string("pm")])
])

try db.close()
```

That's the actual API surface. Swift types go in and Swift types come out, without bridging headers, C bindings, or ORM configuration layers.

## Architecture

BlazeDB is structured as a layered engine. Each layer has a defined boundary and a specific job.

> IMAGE → blazedb_architecture.png

*BlazeDB architecture — from API surface down through query execution, collection storage, page management, and the WAL/encryption subsystems.*

At the top, **BlazeDBClient** is the public API surface. Queries flow through a fluent query layer that handles filtering, ordering, and limits, then into the collection engine which manages document records, indexes, and MVCC-style transaction isolation.

Underneath sits a page store built on fixed-size 4 KB pages with overflow chains for large values. This is where two subsystems that are critical in any storage engine live:

The **write-ahead log** handles durability. Every write hits the WAL before the page mutation. If the process crashes, recovery replays the log on startup.

The **encryption layer** handles security. Pages are encrypted with AES-GCM before they reach disk. Encryption is part of the storage path, not an optional layer added later.

The implementation includes a page-based storage layer, write-ahead logging for crash recovery, encrypted page persistence, and a query execution layer — implemented entirely in Swift.

One of the design goals behind BlazeDB is that the database should behave like a system whose internal state is understandable, not mysterious. Page layouts, write-ahead logging, overflow chains, and benchmark measurements are all implemented in ways that can be inspected directly in the source code and reproduced through the benchmark suite. The intention is not just to build a storage engine, but to make its behavior visible to the developers using it.

## Why Swift?

Most database engines are written in C, C++, or Rust. Those languages provide very direct control over memory layout, disk I/O, and concurrency. Swift is not the typical choice for storage engine internals.

But when the database is intended to run inside Swift applications, writing the engine in Swift introduces some practical advantages.

Because the engine itself is written in Swift, the API does not require bridging headers, C bindings, or ORM configuration layers. Swift types go in, Swift types come out. The storage layer, query system, and application code all live in the same language environment.

Distribution is simpler because BlazeDB is a pure Swift package. There is no need to compile C libraries, manage system-level database installations, or maintain platform-specific build scripts. Developers add it the same way they add any other Swift dependency.

Swift's type system helps enforce invariants inside the engine. Value types and enums make it easier to represent structured data records, page metadata, and log entries without relying on untyped memory buffers. This reduces an entire class of mistakes that are common in lower-level storage code.

Modern Swift also includes structured concurrency primitives that the engine uses for asynchronous write batching, checkpointing, and background cleanup — keeping those tasks integrated with the application's runtime rather than relying on external thread management.

And when the database and the application are written in the same language, debugging and profiling become simpler. Developers can step directly through storage code, query execution, and application logic within a single runtime and toolchain.

The tradeoff is real: Swift is not currently optimized for writing extremely high-throughput storage engines the way C or Rust are. BlazeDB does not attempt to compete with mature engines on raw performance. Instead, it explores whether a storage engine written entirely in Swift can provide simpler integration, strong safety guarantees, and transparent behavior — while still maintaining durability, crash recovery, and predictable performance characteristics.

## Durability Model

The WAL design follows a well-understood pattern: log first, mutate the page, sync to disk.

> IMAGE → blazedb_wal.png

*Write path and recovery path. WAL entries are always written before page mutations, guaranteeing crash recovery by replaying the log.*

The invariant is simple: the WAL entry is durable before the page mutation is applied. This means regardless of where a crash happens — after the log, during the page update, before the fsync — recovery can detect dirty entries and replay them.

On startup, BlazeDB checks the WAL. Clean log means the database opens normally. Dirty entries get replayed and the page store comes back to a consistent state before anything else happens.

## Batch Operations

One of the design decisions that matters most in practice is how BlazeDB handles bulk work. Individual record inserts go through the full write path every time — WAL append, page update, sync. That's correct behavior, but it's not fast when you have a thousand records to write.

`insertMany()` and `deleteMany()` batch those operations into single transactional units. The WAL gets one entry for the batch instead of one per record, pages are updated together, and the sync happens once at the end.

Write batching is roughly 5x faster than individual inserts. With all optimizations enabled — async I/O, write batching, compression — combined throughput reaches over 7,600 ops/sec. Async I/O alone provides a 15x speedup over synchronous writes.

In many real workloads, data arrives in batches rather than single inserts. Applications load data sets, sync from APIs, import files. The batch path is where this design becomes important.

## Reads

Reads are where BlazeDB performs well in absolute terms. Indexed lookups by UUID consistently run in the sub-millisecond range — hundreds of thousands of operations per second. Concurrent query searches come in under 1 ms at the median.

These numbers shift between runs depending on system load, thermal state, and background processes. Rather than pinning a specific number in this article, the benchmark scripts in the repository produce current measurements on any machine.

## SQLite Comparison

I want to be direct about this: SQLite is faster than BlazeDB on raw throughput. Meaningfully faster.

> IMAGE → blazedb_benchmark.png

*Growth test throughput comparison. SQLite remains stronger in raw throughput. BlazeDB prioritizes Swift-native design, encryption defaults, and transparent behavior.*

On the same machine, same workload — 1 MB payload records, batch size 8, WAL journal mode, targeting about 1 GiB — SQLite completes the growth run roughly 4x faster and supports single values orders of magnitude larger than BlazeDB's current ~38.6 MiB ceiling.

SQLite has decades of storage engine optimization behind it, and BlazeDB does not attempt to compete with that level of maturity.

Instead, BlazeDB focuses on different priorities: Swift-native integration, encrypted persistence by default, and transparent behavior that can be measured and reproduced.

The honest framing is this: if your application needs maximum throughput above all else, use SQLite. If your application needs a Swift-native storage engine with encryption defaults and predictable behavior you can inspect, BlazeDB is worth looking at.

## Current Limitations

BlazeDB is still evolving and currently has several known limitations:

- Maximum single-value size of ~38.6 MiB
- Lower raw throughput than mature C-based engines
- Single-process embedded design (not distributed)
- Limited query planner sophistication
- Benchmark numbers vary depending on hardware

These constraints are documented in the repository and measured by the benchmark suite. The goal is to be transparent about what BlazeDB does and does not do well.

## How the Benchmarks Work

All performance measurements are produced by Swift XCTest performance tests that live in the repository alongside the engine code. The actual database operations being timed — inserts, reads, batch operations, growth runs — are executed in Swift against the real storage engine with encryption enabled.

The Python scripts in the `Scripts/` directory are orchestration tooling. They invoke `swift test` with the appropriate filter flags to run specific benchmark test targets, then parse the XCTest output — wall-clock timings, CPU cycles, memory counters, disk I/O — and generate the markdown documentation and JSON files that end up in `Docs/Benchmarks/`.

The pipeline is: Python calls `swift test` → Swift runs the actual benchmarks against BlazeDB → Swift outputs raw measurements → Python collects and formats the results into documentation.

Every performance claim in this article is generated from the benchmark suite in the BlazeDB repository. The full suite can be run with a single command:

```
python3 Scripts/refresh_benchmark_suite.py
```

This runs the full suite and produces consolidated documentation — latency percentiles, limits testing, SQLite head-to-head comparison, resource profiling, and garbage collection timing. The scripts also support selective runs:

```
python3 Scripts/refresh_benchmark_suite.py --skip-core --skip-gc
python3 Scripts/refresh_benchmark_suite.py --skip-gc --skip-power
```

The specific numbers will vary depending on hardware and system state. That's the point — the scripts are designed to produce honest measurements on whatever machine runs them, not to produce marketing numbers.

The project will be open sourced once the core APIs stabilize. When it does, the benchmark suite and all measurement tooling will be published alongside the engine.

## What's Next

BlazeDB is being integrated into a production application to validate its behavior under real user workloads. The goal is to move beyond synthetic benchmarks and observe how the engine performs with actual application data patterns — mixed reads and writes, varying record sizes, and long-running persistence across application lifecycles.

Results from that work will be shared once there's enough real-world data to report with confidence.

BlazeDB is an exploration of what an embedded database designed natively for Swift might look like. The project is still evolving, but the goal is simple: a storage engine whose behavior is transparent, measurable, and understandable by the developers using it.

---

*BlazeDB is maintained by Danylchuk Studios LLC.*
