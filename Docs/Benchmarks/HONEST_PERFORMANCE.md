# Honest performance label

**BlazeDB point reads are fast, but durable insert latency currently increases sharply with database size.**

In the published release sweep ([db_size_sweep.md](db_size_sweep.md)), median insert latency rose from approximately **0.70 ms** on an empty database to **483 ms** after seeding **100,000** small (~53 B) records (~2 durable inserts/sec). That is an application-limiting scalability defect, not merely a fixed fsync tax.

Saying only “expensive durability path” sounds like a design trade-off. The accurate wording is:

**durable writes are expensive and currently scale poorly with database size.**

That is more useful than “BlazeDB is fast” or “BlazeDB is slow.”

## What the current evidence looks like

| Area | Reading (secure release, July 2026 host) |
|------|------------------------------------------|
| Point reads | Very fast (~105k ops/s indexed UUID read) |
| Concurrent reads | Promising (~3.3k reads/s with a writer; ~34× vs plaintext SQLite under the same harness) |
| Batch writes | Usable for small rows; `insertMany` rejects overflow-sized records ([#434](https://github.com/Mikedan37/BlazeDB/issues/434)) |
| Single durable writes (empty / small DB) | Slow vs plaintext SQLite (~2.5 ms/op on core 1K RESULTS row) |
| Single durable writes vs **DB size** | Catastrophic slope: ~0.7 ms → ~5 ms @1K → ~47 ms @10K → **~483 ms @100K** ([db_size_sweep.md](db_size_sweep.md)) |
| Cold open | Very slow (~1.0 s) because of 600k PBKDF2 |
| Warm reopen | Acceptable (~25 ms) with in-process session keys |
| Payload size (controlled sweep) | Nonlinear but believable: ~0.72 ms @307 B → ~5.3 ms @1 MB → ~23 ms @4 MB ([payload_size_sweep.md](payload_size_sweep.md)) |
| Large sequential growth | Respectable for local storage (~6 ms/op at 1 MB × ~1 GiB growth) |

Calling the *entire* database slow is still too broad. Point/concurrent reads remain strengths. The write path is a **scalability defect**, not a footnote.

## Record size must be stated

Core harness insert/read/delete rows use the **standard** shape (`id` + `index` + short `data` string), typically **~53 B** BlazeBinary-encoded — **not** 1 MB.

**Conservative claim for product docs:**

> Core durable insert latency was measured using a standard record with a median encoded size of approximately 53 bytes. Larger payloads incur additional encoding, encryption, page, and I/O work, but latency does not necessarily scale linearly with encoded size. See [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md) for payload-specific measurements. Separately, durable insert latency currently increases sharply with database row count — see [db_size_sweep.md](db_size_sweep.md).

Do not claim “each write was 2 KB” (or any other size) without `encodedPayloadBytes` / the payload-size sweep.

Do **not** publish a “~20,000× bytes vs ~2.4× latency” product claim from comparing the core ~53 B durable insert to the separate 1 MB growth profile — those are different harnesses.

## Scaling with database size (the real fire)

The payload curve is nonlinear but not alarming by itself. The **database-size** curve is:

| Seed rows | p50 insert ms (standard ~53 B) |
|----------:|-------------------------------:|
| 0 | ~0.70 |
| 1K | ~4.93 |
| 10K | ~46.7 |
| 100K | ~483 |

Roughly **~10× latency for each ~10× row count** after 1K. That strongly suggests near-linear work over existing contents (index rebuild/rewrite, metadata serialization, scan, pathological page lookup, etc.) — **not** fixed fsync.

[#425](https://github.com/Mikedan37/BlazeDB/issues/425) / follow-up size-scaling work should profile **work versus database size**, not only stages of one write on an empty DB. Useful per seed size: encode, encrypt, lookup/index mutation, page allocation, WAL append, main-store mutation, metadata serialization, fsync, bytes written, pages read/written.

## insertMany overflow (separate correctness bug)

`insertMany([record])` fails at ≥ ~4 KB (`Page too large`) while `insert(record)` accepts up to ~4 MB. That is API parity breakage — tracked in [#434](https://github.com/Mikedan37/BlazeDB/issues/434). Benchmark FAILED rows (ops/s `0` + note) are intentional; do not mistake them for legitimate zero throughput.

## Before claiming “high performance”

| Need | Tooling status |
|------|----------------|
| Payload-size sweeps | `./bench payload` / `./bench publish` → [payload_size_sweep.md](payload_size_sweep.md) |
| Write latency vs DB size | `./bench db-size` → [db_size_sweep.md](db_size_sweep.md) |
| p50 / p95 / p99 (not only averages) | Core harness + `Scripts/generate_latency_report.py` |
| Stage profile **vs DB size** | Extend write profile under [#435](https://github.com/Mikedan37/BlazeDB/issues/435) / [#425](https://github.com/Mikedan37/BlazeDB/issues/425) |
| Comparison vs **encrypted** SQLite | **Gap** — current COMPARISON is plaintext SQLite + `engine_only` |
| Front door | `./bench` or `./dev bench` (see README / `./dev help`) |

## How to read published tables

- Prefer [COMPARISON.md](COMPARISON.md) + [RESULTS.md](RESULTS.md) + [db_size_sweep.md](db_size_sweep.md) over marketing copy.
- Smoke under `benchmark_results/` is not canonical until `./bench publish`.
- SQLite columns are **plaintext** unless a future encrypted peer lands.
- Cold open ≠ storage-engine latency.

## Related

- [#435](https://github.com/Mikedan37/BlazeDB/issues/435) — durable insert scales poorly with DB size (primary)
- [#425](https://github.com/Mikedan37/BlazeDB/issues/425) — stage attribution (extend to vs-DB-size)
- [#434](https://github.com/Mikedan37/BlazeDB/issues/434) — insertMany rejects overflow-sized records
- [#424](https://github.com/Mikedan37/BlazeDB/issues/424) / [#276](https://github.com/Mikedan37/BlazeDB/issues/276) — insertMany amortization
- [WRITE_PATH_PROFILE.md](WRITE_PATH_PROFILE.md), [PAYLOAD_SIZE.md](PAYLOAD_SIZE.md), [LIMITS.md](LIMITS.md)
