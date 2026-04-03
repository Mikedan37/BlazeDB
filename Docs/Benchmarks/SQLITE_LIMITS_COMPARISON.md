# BlazeDB vs SQLite Limits (Measured, No Guesswork)

_Generated: 2026-03-13T23:53:34+00:00_

## Inputs Used (Exact)

### BlazeDB real measurement input
- Source: `Docs/Benchmarks/limits_measurements.json`
- Command:
- `cd BlazeDBExtraTests && BLAZEDB_REAL_LIMIT_TARGET_GIB=1.0 BLAZEDB_REAL_LIMIT_PAYLOAD_BYTES=1000000 BLAZEDB_REAL_LIMIT_BATCH_SIZE=8 swift test --filter "BlazeDB_Tier3_Heavy.RealLimitsMeasurementTests/testMeasure_RealLimitsAndGrowth"`

### SQLite comparison input (matched to BlazeDB)
- Target DB size: `1.003 GiB`
- Payload per record: `1000000` bytes
- Batch size per transaction: `8`
- Journal mode: `WAL`
- Table schema: `CREATE TABLE t(id INTEGER PRIMARY KEY, payload BLOB NOT NULL)`

## Results (Measured)

| Metric | BlazeDB | SQLite (local build) |
|---|---:|---:|
| Max blob round-trip | `40523994` bytes | `>= 256000000` bytes (probe max; no failure up to this point) |
| Max string round-trip | `40523994` bytes | `>= 128000000` bytes (probe max; no failure up to this point) |
| Growth final size | `1076461568` bytes | `1081610240` bytes |
| Growth final size (GiB) | `1.003` | `1.007` |
| Growth records inserted | `1064` | `1080` |
| Growth elapsed seconds | `8.850` | `2.199` |
| Growth throughput (MiB/s) | `116.00` | `469.01` |
| Growth throughput (records/s) | `120.2` | `491.1` |

## Hard Limit Boundary Check (SQLite)

- Checked boundary expression: `length(zeroblob(N))`
- At limit `N=2147483645`: `PASS` (returned `2147483645`)
- Over limit `N=2147483646`: `FAIL as expected`

## Hard Limit Gap (Single Value)

- BlazeDB measured max value in this repo/run: `40523994` bytes
- SQLite configured hard max length on this machine: `2147483645` bytes
- Ratio (SQLite / BlazeDB): **52.99x**
- Verdict: SQLite hard single-value limit is materially higher; BlazeDB is not close on this axis.

## Confidence Class Per Number

| Number type | Confidence | Why |
|---|---|---|
| SQLite hard max length (`MAX_LENGTH`) | hard-verified | explicit at-limit pass + over-limit fail check |
| BlazeDB max blob/string | measured | binary-search round-trip test against this build |
| SQLite blob/string probe maxima | measured-lower-bound | tested up to probe points; not full binary search to failure |
| Growth size/time throughput | measured | direct runtime timing on same machine |

## SQLite Build Limits (This Machine, Actual)

- SQLite version: `3.51.0`
- Page size: `4096` bytes
- `MAX_LENGTH`: `2147483645`
- `MAX_SQL_LENGTH`: `1000000000`
- `MAX_PAGE_COUNT`: `1073741823`
- `MAX_PAGE_SIZE`: `65536`

## What This Comparison Is / Is Not

- This is **real measured runtime output** for both engines on the same machine.
- SQLite single-value max here is a **probe lower bound** (`>= 256,000,000` bytes), not its absolute ceiling.
- SQLite hard limit line item is verified by explicit at/over boundary checks.
- BlazeDB max value comes from the real measurement test used in this repo (`RealLimitsMeasurementTests`).
- No cross-machine claims are made in this report.
