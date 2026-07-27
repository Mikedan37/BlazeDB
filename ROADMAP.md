# BlazeDB Roadmap

> **This roadmap communicates direction, not guaranteed release dates.**
> Priorities may change based on correctness, compatibility, contributor feedback, and maintenance cost.

Use milestones or GitHub issues for concrete release commitments. Use this document for direction.

| Doc | Role |
|-----|------|
| **This file** | Committed product priorities for the supported OSS product |
| [`ROADMAP_BACKLOG.md`](Docs/Product/ROADMAP_BACKLOG.md) | Verified gaps worth retaining (not a public Now list) |
| [`PRODUCT_AUDIT.md`](Docs/Product/PRODUCT_AUDIT.md) | Full evidence and inventory |

## Current engineering focus

Correctness and packaging ahead of feature expansion:

- Crash-recovery correctness ([#277](https://github.com/Mikedan37/BlazeDB/issues/277))
- Lifecycle / concurrency hardening (recent: #278/#279/#295/#296 closed)
- Cache / isolation across databases ([#306](https://github.com/Mikedan37/BlazeDB/issues/306), [#280](https://github.com/Mikedan37/BlazeDB/issues/280), [#307](https://github.com/Mikedan37/BlazeDB/issues/307))
- API contract decisions ([#297](https://github.com/Mikedan37/BlazeDB/issues/297), [#309](https://github.com/Mikedan37/BlazeDB/issues/309)) and CLI secret handling ([#310](https://github.com/Mikedan37/BlazeDB/issues/310))
- Linux and C ABI packaging ([#51](https://github.com/Mikedan37/BlazeDB/issues/51), [#265](https://github.com/Mikedan37/BlazeDB/issues/265), [#312](https://github.com/Mikedan37/BlazeDB/issues/312))

The tracker mixes verified defects, contributor tasks, documentation work, and deferred platform improvements. **Not every open issue is a release blocker.** See [ISSUE_GUIDE](Docs/Contributing/ISSUE_GUIDE.md) for label navigation (`good first issue`, `help wanted`, `needs design`, durability/concurrency).

Suggested engineering sequence: **#277 → #306 (isolation) → #297/#309 contracts → #310 → measurement (#291) → amortize (#276)**.

## Now

Work that should happen next because it reduces breakage, overclaim, or contributor risk.

- **Add on-disk compatibility fixtures from supported prior releases**
  - Why: Prevent silent format/WAL breaks across tags. Fixtures may exist on disk without being a CI gate.
  - Exit criteria: CI opens fixtures from at least one prior supported release and verifies read (and a bounded write) behavior.
  - Dependency: Maintainer decision on which tags remain supported.

- **Land checked-in Go/cgo smoke sources and a CI gate**
  - Why: C ABI E2E is proven; Go was documented as working without any `.go` sources in tree.
  - Exit criteria: Example builds from a clean checkout against `BlazeDBC`; CI runs open/put/get/close; docs match reality.
  - Support-state impact: Moves Go from “docs-only preview” toward a real packaging candidate.

- **Align CLI Doctor/Dump/Info docs with actual dispatch**
  - Why: Help and guides still imply `blazedb doctor|dump|info` while those are separate executables (REPL `doctor` is different).
  - Exit criteria: Either wire subcommands or make every public doc/`--help` path say `swift run BlazeDoctor|BlazeDump|BlazeInfo`.
  - Evidence: `BlazedbEntry` vs tool help strings.

- **Curate BlazeDBC release artifacts and CI-link the C example**
  - Why: Tag releases currently tar the whole `.build/release` tree; C hello is not linked in CI despite being the FFI packaging proof.
  - Exit criteria: Release attaches shared library + `blazedb.h` (+ checksum); CI or release job compiles `Examples/C/hello_blazedb.c`.

- **Consolidate migration and schema documentation**
  - Why: APIs and tests exist; dedicated guides remain under consolidation and confuse schemaless-default vs opt-in schema.
  - Exit criteria: One canonical advanced entry for migrations and one for schema validation, linked from Docs/README Advanced table.

- **Remove remaining docs that imply production B+ readiness**
  - Why: `ExperimentalBPlusTree` is already marked non-product (print-only stub). Production indexes are hash secondary + `BTreeIndex`; many queries still scan. Residual docs may still imply a finished B+ product path.
  - Exit criteria: Public docs state what `createIndex` / range indexes actually accelerate; no guide treats the experimental stub as shipped indexing; any true B+ work has separate design exit criteria.
  - Dependency: Maintainer choice—invest in B+ later, or keep hash/`BTreeIndex` as the supported story.

### Recently completed (keep using)

- **Storage-change contributor checklist** — [Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md](Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md); linked from CONTRIBUTING and PR guidance. Tighten as compatibility fixtures land.
- **COMPATIBILITY iOS wording** — iOS / other Apple mobile platforms are declared and compile-tested; runtime CI remains macOS/Linux unless a runtime job is listed. Matches README.

## Next

Likely priorities after current work, not guaranteed for a specific version.

- **Expand C ABI additively** (`blazedb_last_error`, then iterators/prefix/batch as designed)
  - Why: Hosts cannot diagnose `NULL` opens; listing and batch workloads need more than single-key KV.
  - Exit criteria: Documented additive symbols; ownership tests; no signature changes to v1 functions.

- **Package an official versioned Go module** (after smoke sources exist)
  - Why: Remaining work is productization, not inventing FFI.
  - Exit criteria: Separate module SemVer, compatibility policy with BlazeDB tags, release-gated E2E.

- **Short benchmark regression lane + single authoritative bench entry path**
  - Why: Methodology exists locally; perf cliffs are manual-only; dual scripts confuse baselines.
  - Exit criteria: Small CI subset with environment capture; Docs/Benchmarks points to one primary runner.

- **Broader recovery and corruption testing** (including documented power-loss caveats)
  - Why: Crash suites exist; overflow orphans and `fsync`-only semantics still need sharper coverage/docs.
  - Exit criteria: Named failure modes covered by smallest possible tests; durability doc updated if semantics change.

- **Apple runtime validation where it matters** (for example iOS Simulator Tier0)
  - Why: Declared platforms are compile-tested; mobile runtime claims need proof or stay compile-tested.
  - Exit criteria: One runtime job that runs a bounded core suite, or wording stays compile-tested.

- **Index execution honesty / planner wiring**
  - Why: Callers assume `createIndex` makes filters O(log n); many paths still fetch+filter.
  - Exit criteria: Either wire secondary/range indexes into common query paths, or document scan fallbacks unmistakably.

- **Refresh external security review status**
  - Why: Written plan window is overdue; readiness checklist still “scheduled.”
  - Exit criteria: Public status is complete, rescheduled, or explicitly risk-accepted.

- **Version Homebrew or document head-only as intentional**
  - Why: Formula builds from `head`; tagged releases can diverge from brew installs.

## Later / Exploring

Ideas under investigation with no delivery commitment.

- Relationship modeling guidance or optional companion helpers
- Optional higher-level modeling packages
- Android/KMM productization (only with packaging + support-state upgrade)
- Additional language bindings (after Go packaging pattern exists)
- In-place password/rekey API
- Deeper doctor integrity proofs (WAL/meta/orphan walks)
- Overflow-in-WAL or stronger reclaim tooling

## Not planned / intentionally deferred

- **Distributed sync, discovery, server, and full telemetry packaging as default OSS** — deferred until public dependencies and CI exist ([DISTRIBUTED_TRANSPORT_DEFERRED](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)).
- **Advertising Android/KMM as a production-supported SDK** while experimental.
- **Ceremonial “support every platform with full runtime CI”** without a specific product need.
- **Marketing feature buffet** (cost-based optimizer theater, AI assistants, etc.) ahead of compatibility and recovery work.

---

## How to read this

A good roadmap helps contributors understand:

- what work matters now
- where help is useful
- what is intentionally deferred
- which ideas need design discussion
- what should not be mistaken for shipped functionality

It should not contain long lists of speculative features or assign version numbers unless those releases are genuinely scoped and actively managed. Orphaned but verified gaps live in the backlog, not here.
