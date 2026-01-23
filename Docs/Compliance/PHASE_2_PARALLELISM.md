# Phase 2: Controlled Parallelism

## Goal

Get measurable throughput gains without touching storage correctness.

## What Phase 2 Actually Delivers (Numbers, Not Vibes)

These are CPU-side wins only. Storage and IO remain serial.

### Baseline (Phase 1, Current State)

Assuming:
- Serial encoding
- Serial compression
- Serial write

Typical numbers (rough but realistic):

| Stage | Cost per batch (50 records) |
|-------|----------------------------|
| Encode | ~1.5–2 ms |
| Compress | ~0.5–1 ms |
| Storage write | ~3–6 ms |
| **Total** | **~6–9 ms / batch** |

**Throughput:**
- 110–160 batches/sec
- 5,500–8,000 ops/sec

This matches what you already measured. Good.

### Phase 2 Target (Parallel CPU, Serial Storage)

Parallelize encoding + compression only.

Expected improvements on a 6–8 core machine:

| Stage | New cost |
|-------|----------|
| Encode (parallel) | ~0.4–0.7 ms |
| Compress (parallel) | ~0.2–0.4 ms |
| Storage write | ~3–6 ms |
| **Total** | **~3.6–7 ms / batch** |

**Throughput gain:**
- 1.4× – 1.8× ops/sec
- ~8,000 → 12,000–14,000 ops/sec
- Latency reduced ~30–40% for write-heavy workloads

**Anything beyond 2× is fantasy unless storage changes. Period.**

## What Phase 2 Explicitly Does NOT Improve

Zero gains here:
- WAL fsync latency
- Page cache contention
- Disk throughput
- mmap fault latency
- Distributed sync

**If profiling shows storage is dominant, stop Phase 2 early.**

## Implementation Prompt

```
You are working in the BlazeDB repository.

GOAL:
Implement Phase 2: controlled, isolated parallelism for CPU-bound work
while preserving all Phase 1 concurrency guarantees.

STRICT SCOPE:
- Encoding (BlazeBinary)
- Compression
- Hashing / checksums (if present)

OUT OF SCOPE (DO NOT TOUCH):
- PageStore
- WAL
- PageCache
- Index mutation
- Layout persistence
- Distributed sync / networking
- Cross-app replication

NON-NEGOTIABLE RULES:
1. No parallel code may mutate storage.
2. No parallel code may call PageStore methods.
3. Parallel code must operate on immutable inputs and return new values.
4. Storage writes remain serial and guarded.
5. Swift 6 strict concurrency checks must still pass.

ARCHITECTURE PATTERN:
Parallel at the edges, serial at the core.

IMPLEMENTATION STEPS:

STEP 1: Introduce worker isolation
- Create actor-based workers:
  - EncodingWorker
  - CompressionWorker
- Each actor:
  - Holds no shared mutable state
  - Exposes async methods like:
    encode(records) -> [UInt8]
    compress(bytes) -> [UInt8]

STEP 2: Add a lightweight worker pool
- Use a small fixed pool (e.g. min(cores, 4))
- Do NOT create unbounded Tasks
- Ensure workers are reused, not recreated per call

STEP 3: Refactor write pipeline
- Change the pipeline shape to:
  1) await encoding in parallel
  2) await compression in parallel
  3) call PageStore synchronously with final bytes
- Storage remains fully serial

STEP 4: Eliminate Task.detached
- Use structured concurrency only
- No detached tasks
- No @unchecked Sendable additions

STEP 5: Instrument performance
- Add lightweight timing logs around:
  - encode
  - compress
  - write
- Print per-batch timings in DEBUG builds

STEP 6: Verification
- Re-run existing durability tests
- Add a performance smoke test:
  - Insert 1,000+ records
  - Verify correctness
  - Log batch timing deltas vs Phase 1

EXPECTED OUTCOME:
- Encoding + compression parallelized
- Storage remains serial and guarded
- Swift 6 concurrency checks still pass
- Measurable throughput improvement (~1.4×–1.8×)
- No new Sendable or deadlock issues

DO NOT:
- Parallelize PageStore
- Parallelize WAL writes
- Add speculative writes
- Introduce background flushing
- Touch distributed code
```

## When Phase 2 is "Done"

Phase 2 is complete when all of these are true:
-  Encoding/compression are parallel
-  PageStore unchanged
-  Swift 6 still trusts the code
-  Durability tests still pass
-  Throughput improved measurably
-  No new concurrency warnings

**If you don't see at least ~30% throughput gain, stop. The bottleneck moved.**

## Final Warning

Phase 2 is where smart people ruin clean systems by chasing numbers past diminishing returns.

The moment you think:

> "What if we parallelize writes just a little…"

**Close Cursor. Walk away. You're done for the day.**

That's the real Phase 2 plan, with numbers that won't lie to you.
