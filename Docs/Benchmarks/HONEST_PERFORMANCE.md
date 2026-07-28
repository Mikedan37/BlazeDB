# Honest performance label

**BlazeDB is read-optimized and currently has an expensive durability path.**

That is more useful than “BlazeDB is fast” or “BlazeDB is slow.”

## What the current evidence looks like

| Area | Reading (secure release, July 2026 host) |
|------|------------------------------------------|
| Point reads | Very fast (~105k ops/s indexed UUID read) |
| Concurrent reads | Promising (~3.3k reads/s with a writer; ~34× vs plaintext SQLite under the same harness) |
| Batch writes | Usable, not exceptional (`insertMany` durable/max profiles) |
| Single durable writes | Slow (~2.5 ms/op on 1K; ~274 ops/s) |
| Cold open | Very slow (~1.0 s) because of 600k PBKDF2 |
| Warm reopen | Acceptable (~25 ms) with in-process session keys |
| Large sequential growth | Respectable for local storage (~6 ms/op at 1 MB × ~1 GiB growth) |

For durable single-row writes: yes, it is slow.

A measured ~2.5 ms per insert implies a theoretical ceiling near **~400 writes/sec**. The actual 1K durable row reported about **274 ops/sec**. Beside **plaintext** SQLite WAL, that is not impressive.

Calling the *entire* database slow is too broad. The write path is a **weakness**, not a footnote — and BlazeDB can still be usable for many local apps that are read-heavy or batch their writes.

## Record size must be stated

Core harness insert/read/delete rows use the **standard** shape (`id` + `index` + short `data` string), typically **~53 B** BlazeBinary-encoded — **not** 1 MB.

**Conservative claim for product docs:**

> Core durable insert latency was measured using a standard record with a median encoded size of approximately 53 bytes. Larger payloads incur additional encoding, encryption, page, and I/O work, but latency does not necessarily scale linearly with encoded size. See [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md) for payload-specific measurements.

Do not claim “each write was 2 KB” (or any other size) without `encodedPayloadBytes` / the payload-size sweep.

Do **not** publish a “~20,000× bytes vs ~2.4× latency” product claim from comparing the core ~53 B durable insert to the separate 1 MB growth profile — those are different harnesses. Treat that only as motivation for a controlled payload-size sweep and [#425](https://github.com/ProjectBlaze/BlazeDB/issues/425) stage attribution.

## Scaling concern (not just fixed fsync)

The 10K-row durable insert result degrades toward **~24 ms/op**. That suggests scaling or persistence overhead beyond a simple fixed fsync cost. Treat averages alone as insufficient; prefer **p50 / p95 / p99**, and measure write latency **versus database size**.

Quick `./bench smoke` / short `db_size_sweep` runs on a single laptop (for example empty DB vs after a 1K seed) are useful **smoke evidence** that the concern is real. They are **not** a published scaling curve until a controlled release publish lands under `Docs/Benchmarks/` (and even then, prefer p50/p95/p99 across hosts — one machine loves sounding authoritative).

## Before claiming “high performance”

| Need | Tooling status |
|------|----------------|
| Payload-size sweeps | `./bench payload` / `./bench publish` → [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md) |
| Write latency vs DB size | `./bench db-size` → `benchmark_results/db_size/` |
| p50 / p95 / p99 (not only averages) | Core harness + `Scripts/generate_latency_report.py` |
| Transaction / fsync counts | `./bench write-profile` → [WRITE_PATH_PROFILE.md](WRITE_PATH_PROFILE.md) |
| Page / WAL growth per write | Write profile bytes + write/fsync syscall counts; deepen under [#425](https://github.com/ProjectBlaze/BlazeDB/issues/425) |
| Stage profile (encode / index / encrypt / WAL / persist / sync) | Same write profile; **publish % table** is [#425](https://github.com/ProjectBlaze/BlazeDB/issues/425) |
| Comparison vs **encrypted** SQLite (e.g. SQLCipher), not only plaintext | **Gap** — current COMPARISON is vs plaintext SQLite + BlazeDB `engine_only`. Do not treat that as crypto-fair. |
| Front door | `./bench honesty|smoke|full|publish` (see [README.md](README.md)) |

Do not claim broadly fast durable writes until [#425](https://github.com/ProjectBlaze/BlazeDB/issues/425) explains where the time goes and the path improves.

## How to read published tables

- Prefer [COMPARISON.md](COMPARISON.md) + [RESULTS.md](RESULTS.md) over marketing copy.
- SQLite columns are **plaintext WAL + `synchronous=FULL`** unless a future encrypted-SQLite condition lands.
- Cold open ≠ storage-engine latency.
- `engine_only` is a compile-time benchmark flag, not a production mode.

## Related

- [#425](https://github.com/ProjectBlaze/BlazeDB/issues/425) — publish stage % for durable `insert()`
- [#424](https://github.com/ProjectBlaze/BlazeDB/issues/424) / [#276](https://github.com/ProjectBlaze/BlazeDB/issues/276) — insertMany amortization after measurement
- [#291](https://github.com/ProjectBlaze/BlazeDB/issues/291) — widen condition matrix
- [WRITE_PATH_PROFILE.md](WRITE_PATH_PROFILE.md), [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md), [LIMITS.md](LIMITS.md)
