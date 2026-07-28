# Payload size and write latency

**Purpose:** Make record size an explicit part of BlazeDB benchmark claims — and stop implying that every durable `insert()` row is a megabyte.

## Conservative documentation claim

> Core durable insert latency was measured using a standard record with a median encoded size of approximately **53 bytes**. Larger payloads incur additional encoding, encryption, page, and I/O work, but latency does **not** necessarily scale linearly with encoded size. See this page for payload-specific measurements.

Do **not** turn a cross-harness observation (core ~53 B durable insert vs limits 1 MB growth write) into a product “bytes vs latency multiplier” claim. Use the controlled sweep below instead.

## Tooling layout (not XCTest / not the product API)

```text
./bench payload | smoke | full | publish
        ↓
Scripts/bench.sh  →  Scripts/run_payload_size_sweep.sh
        ↓
swift run -c release BlazeDBBenchmarks   (BLAZEDB_BENCH_MODE=payload_size_sweep)
        ↓
BenchPayload  →  BlazeBinary encode  →  measure encodedPayloadBytes
        ↓
PayloadSizeSweep times insert / batch / transaction / update
        ↓
benchmark_results/payload_size/…  (+ Docs on publish)
```

| Piece | Job |
|-------|-----|
| `BlazeDBBenchmarks/BenchPayload.swift` | Standard (~53 B) and sized records; measure **encoded** bytes (not requested field bytes alone) |
| `BlazeDBBenchmarks/PayloadSizeSweep.swift` | Size × path stopwatch mode |
| `Scripts/run_payload_size_sweep.sh` / `./bench payload` | Release runner + env |
| `Docs/Benchmarks/PAYLOAD_SIZE.md` | Methodology |
| `benchmark_results/payload_size/` | **Smoke / local** sweep outputs (default) |
| `Docs/Benchmarks/payload_size_sweep.md` | **Published** numbers only after explicit `./bench publish` |

Not part of normal unit-test CI by default — full sweeps through 4 MB are performance tooling.

**Smoke vs published:** `./bench smoke` and default sweep scripts write under `benchmark_results/`. Those runs support investigation (for example a single-host empty→seeded latency concern) but are **not** canonical product numbers until a controlled release publish lands them under `Docs/Benchmarks/`.

## What the core harness writes

Core `BlazeDBBenchmarks` insert / read / delete rows use the **standard** shape:

| Field | Type | Content |
|-------|------|---------|
| `id` | UUID | random |
| `index` | Int | row index |
| `data` | String | `"Record N"` / `"Batch Record N"` / similar |

Results JSON includes:

- `encodedPayloadBytes` — median **BlazeBinary-encoded** length of that shape (not “logical field bytes only”)
- `recordShape` — human description
- `datasetSize` — row **count**, not bytes

Page size is **4096** bytes. On a recent host the standard row measured **~53 B** encoded (median). It usually fits in far less than one full page of payload, but durable cost still includes WAL/page encryption and sync.

The **1 MB × N** figure belongs to the **limits growth** measurement (`RealLimitsMeasurementTests` / `LIMITS.md`), not to the core insert table.

## Why size does not scale linearly

Durable write latency is roughly:

```text
encode
+ index / metadata updates
+ encrypt affected pages (AES-GCM)
+ WAL / data writes
+ durability sync (often the fixed cliff)
```

| Record shape | Likely behavior |
|--------------|-----------------|
| Hundreds of bytes | Mostly fixed commit/fsync cost |
| A few KB | Often similar until extra pages / index work appear |
| Tens–hundreds of KB | Rising encode / encrypt / I/O |
| ~1 MB | Clearly slower (growth profile ~6 ms/write on one host) |
| Tens of MB | Heavy; max round-trip (~38.65 MiB) is a **limit**, not a workload recommendation |

Two records with the same byte size can still differ: one 20 KB blob vs 40 indexed fields totaling 20 KB. Updates may rewrite more than the changed field (new encoded record, index entry, WAL, encrypted pages).

## Payload-size sweep (tooling)

Paths (`BLAZEDB_PAYLOAD_SWEEP_PATH`):

| Path | Semantics |
|------|-----------|
| `durable_insert` (default) | Timed `insert()` per row + one `persist()` at end — matches core per-row harness timing |
| `insertMany_batch` | Timed `insertMany` batches (≤50) + final `persist` |
| `transaction_puts` | `begin` → timed `insert`s → `commit` |
| `update` | Seed once, then timed field update (`payload` rewrite) per row + final `persist` |

```bash
# Default sizes: 256 B … 4 MB (ASCII payload field) — release recommended
./Scripts/run_payload_size_sweep.sh --release

# Paths: durable_insert | insertMany_batch | transaction_puts | update
BLAZEDB_PAYLOAD_SWEEP_PATH=insertMany_batch ./Scripts/run_payload_size_sweep.sh --release

# Custom sizes (comma-separated payload field bytes)
BLAZEDB_PAYLOAD_SWEEP_SIZES=256,1024,4096,65536 ./Scripts/run_payload_size_sweep.sh --release
```

Outputs:

- `benchmark_results/payload_size/payload_size_sweep.md`
- `benchmark_results/payload_size/payload_size_sweep.json`

Optional publish into docs: `BLAZEDB_PAYLOAD_SWEEP_PUBLISH=1`.

For each size the sweep reports p50/p95/p99 insert latency (or per-batch latency for `insertMany_batch`), ops/sec, requested payload bytes, and encoded bytes.

The current evidence supports this conclusion:

Small writes appear dominated partly by fixed durability overhead, while larger records increase latency as more pages must be encoded, encrypted, and written.

But the normal benchmark row size must be stated (`encodedPayloadBytes`, typically **~53 B** for the standard harness shape), so you should not claim a precise byte-to-latency curve without a sweep.

## Performance framing

See [HONEST_PERFORMANCE.md](HONEST_PERFORMANCE.md): durable single-row writes are a **weakness**; point/concurrent reads are the strength. Also run `./Scripts/run_db_size_sweep.sh` when investigating 1K→10K durable degradation.

## Related

- [HONEST_PERFORMANCE.md](HONEST_PERFORMANCE.md) — read-optimized / expensive durability diagnosis
- `BlazeDBBenchmarks/BenchPayload.swift` — canonical shapes + encode measurement
- `BlazeDBBenchmarks/PayloadSizeSweep.swift` — sweep mode
- `BlazeDBBenchmarks/DbSizeSweep.swift` — write latency vs DB size
- [WRITE_PATH_PROFILE.md](WRITE_PATH_PROFILE.md) — stage attribution ([`performance`](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3Aperformance))
- [LIMITS.md](LIMITS.md) — max round-trip and growth profile
- [RESULTS.md](RESULTS.md) / [LATENCY.md](LATENCY.md) — published tables
- `Scripts/check_benchmark_honesty.py` — docs + result-shape lint
