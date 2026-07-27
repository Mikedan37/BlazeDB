# BlazeDB Roadmap

> **This roadmap answers: what should a contributor or maintainer work on next?**
> It communicates direction, not guaranteed release dates. Priorities may change based on
> correctness, compatibility, contributor feedback, and maintenance cost.

Use milestones or GitHub issues for concrete delivery commitments. Use this document for navigation.

Audits answer a different question — *what have we discovered?* — and belong in the evidence locker, not here.

| Doc | Role |
|-----|------|
| **This file** | What to work on next (supported OSS product) |
| [`ROADMAP_BACKLOG.md`](Docs/Product/ROADMAP_BACKLOG.md) | Verified gaps worth retaining (not a public Now list) |
| [`PRODUCT_AUDIT.md`](Docs/Product/PRODUCT_AUDIT.md) | Product inventory and evidence |
| [`POST_AUDIT_FINDINGS_2026_07.md`](Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md) | Verified defect inventory (maintainer tracking) |

## Maintainer priorities

These items primarily affect correctness, durability, or security.
Most are already represented by tracked GitHub issues or audit findings.

**Priority order:**

1. **Security correctness** — RLS and related API contracts ([#334](https://github.com/Mikedan37/BlazeDB/issues/334)–[#337](https://github.com/Mikedan37/BlazeDB/issues/337); soft-delete / count → [#297](https://github.com/Mikedan37/BlazeDB/issues/297))
2. **Continuous verification** — crash, rollback, and reclaim invariants as permanent tests ([#322](https://github.com/Mikedan37/BlazeDB/issues/322), [#326](https://github.com/Mikedan37/BlazeDB/issues/326), [#328](https://github.com/Mikedan37/BlazeDB/issues/328), [#331](https://github.com/Mikedan37/BlazeDB/issues/331))
3. **Durability invariants** — checkpoint, overflow, and crypto continuity (see [post-audit maintainer queue](Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md#maintainer-only-do-not-promote-without-maintainer-review); crash-recovery umbrella [#277](https://github.com/Mikedan37/BlazeDB/issues/277))
4. **Performance work** — only after measurement owns the wall ([#291](https://github.com/Mikedan37/BlazeDB/issues/291)); amortize hot paths ([#276](https://github.com/Mikedan37/BlazeDB/issues/276))

The tracker mixes verified defects, contributor tasks, documentation work, and deferred platform improvements. **Not every open issue is a release blocker.** See [ISSUE_GUIDE](Docs/Contributing/ISSUE_GUIDE.md) for label navigation.

## Now

Work that should happen next because it reduces breakage, overclaim, or contributor risk.
Grouped by theme; pick any item in a theme that matches your skill set.

### Packaging

- **Land checked-in Go/cgo smoke sources and a CI gate**
  - Why: C ABI E2E is proven; Go was documented as working without any `.go` sources in tree.
  - Exit criteria: Example builds from a clean checkout against `BlazeDBC`; CI runs open/put/get/close; docs match reality.
  - Support-state impact: Moves Go from “docs-only preview” toward a real packaging candidate.

- **Curate BlazeDBC release artifacts and CI-link the C example**
  - Why: Tag releases currently tar the whole `.build/release` tree; C hello is not linked in CI despite being the FFI packaging proof.
  - Exit criteria: Release attaches shared library + `blazedb.h` (+ checksum); CI or release job compiles `Examples/C/hello_blazedb.c`.

### CI

- **Add on-disk compatibility fixtures from supported prior releases**
  - Why: Prevent silent format/WAL breaks across tags. Fixtures may exist on disk without being a CI gate.
  - Exit criteria: CI opens fixtures from at least one prior supported release and verifies read (and a bounded write) behavior.
  - Dependency: Maintainer decision on which tags remain supported.

### Documentation

- **Align CLI Doctor/Dump/Info docs with actual dispatch**
  - Why: Help and guides still imply `blazedb doctor|dump|info` while those are separate executables (REPL `doctor` is different).
  - Exit criteria: Either wire subcommands or make every public doc/`--help` path say `swift run BlazeDoctor|BlazeDump|BlazeInfo`.

- **Consolidate migration and schema documentation**
  - Why: APIs and tests exist; dedicated guides remain under consolidation and confuse schemaless-default vs opt-in schema.
  - Exit criteria: One canonical advanced entry for migrations and one for schema validation, linked from Docs/README Advanced table.

- **Remove remaining docs that imply production B+ readiness**
  - Why: `ExperimentalBPlusTree` is already marked non-product (print-only stub). Production indexes are hash secondary + `BTreeIndex`; many queries still scan.
  - Exit criteria: Public docs state what `createIndex` / range indexes actually accelerate; no guide treats the experimental stub as shipped indexing.

### Recently completed (keep using)

- **Storage-change contributor checklist** — [Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md](Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md)
- **Crypto-change checklist** — [#330](https://github.com/Mikedan37/BlazeDB/issues/330)
- **Benchmark-change checklist** — [#333](https://github.com/Mikedan37/BlazeDB/issues/333)
- **COMPATIBILITY iOS wording** — compile-tested / declared; runtime CI remains macOS/Linux unless a runtime job is listed

## Next

Likely priorities after current work, not guaranteed for a specific version.

### Correctness and verification

- **RLS correctness**
  - Why: Public GraphQuery, update WITH CHECK, count/stats, and filtered observe paths can bypass or leak under client RLS.
  - Exit criteria: Issues [#334](https://github.com/Mikedan37/BlazeDB/issues/334)–[#337](https://github.com/Mikedan37/BlazeDB/issues/337) closed with tests; product decision on caller-trusted vs AccessManager-bound context documented.
  - Evidence: [post-audit RLS cluster](Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md)

- **Continuous verification**
  - Why: Confirmed defects must become permanent regression tests (or documented as non-automatable).
  - Exit criteria: Process-boundary crash harness in CI ([#322](https://github.com/Mikedan37/BlazeDB/issues/322)); rollback restores secondary indexes ([#326](https://github.com/Mikedan37/BlazeDB/issues/326)); vacuum reopen durability ([#328](https://github.com/Mikedan37/BlazeDB/issues/328)); overflow orphan reclaim ([#331](https://github.com/Mikedan37/BlazeDB/issues/331)).

- **Durability verification**
  - Why: Crash suites exist; checkpoint, overflow, and reopen-after-vacuum/backup paths still need sharper coverage and docs.
  - Exit criteria: Named failure modes covered by the smallest possible tests; durability docs updated if semantics change. See continuous-verification priorities in the [post-audit](Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md#continuous-verification-priorities).

### Product and packaging

- **Expand C ABI additively** (`blazedb_last_error`, then iterators/prefix/batch as designed)
  - Exit criteria: Documented additive symbols; ownership tests; no signature changes to v1 functions.

- **Package an official versioned Go module** (after smoke sources exist)
  - Exit criteria: Separate module SemVer, compatibility policy with BlazeDB tags, release-gated E2E.

- **Short benchmark regression lane + single authoritative bench entry path**
  - Exit criteria: Small CI subset with environment capture; Docs/Benchmarks points to one primary runner.

- **Apple runtime validation where it matters** (for example iOS Simulator Tier0)
  - Exit criteria: One runtime job that runs a bounded core suite, or wording stays compile-tested.

- **Index execution honesty / planner wiring**
  - Exit criteria: Either wire secondary/range indexes into common query paths, or document scan fallbacks unmistakably ([#292](https://github.com/Mikedan37/BlazeDB/issues/292), [#261](https://github.com/Mikedan37/BlazeDB/issues/261)).

- **Refresh external security review status**
  - Exit criteria: Public status is complete, rescheduled, or explicitly risk-accepted.

- **Version Homebrew or document head-only as intentional**
  - Why: Formula builds from `head`; tagged releases can diverge from brew installs.

## Later / Exploring

Ideas under investigation with no delivery commitment. Categories only — detailed findings live in the audit.

### Durability deep work (maintainer-owned)

- **WAL overflow durability** — overflow pages on the durable write path; stronger reclaim tooling. Evidence: [post-audit maintainer queue](Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md#maintainer-only-do-not-promote-without-maintainer-review).
- **Checkpoint durability** — checkpoint must not discard unflushed WAL. Same evidence locker.
- **Crypto continuity** — vacuum / backup-restore must preserve KDF material. Same evidence locker.

### Product exploration

- Relationship modeling guidance or optional companion helpers
- Optional higher-level modeling packages
- Android/KMM productization (only with packaging + support-state upgrade)
- Additional language bindings (after Go packaging pattern exists)
- In-place password/rekey API
- Deeper doctor integrity proofs (WAL/meta/orphan walks)

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

It should not mirror audit IDs, dump every discovered defect, or assign version numbers unless those releases are genuinely scoped and actively managed.

- **Roadmap** = navigation (“work on this next”)
- **Issues** = delivery commitments and acceptance criteria
- **Audits** = evidence locker (“we discovered this”)

Orphaned but verified gaps live in the [backlog](Docs/Product/ROADMAP_BACKLOG.md) or [post-audit findings](Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md), not here.

Historical planning docs (not current): [FEATURE_ROADMAP](Docs/GettingStarted/FEATURE_ROADMAP.md), [PRODUCTION_READINESS_ROADMAP](Docs/Status/PRODUCTION_READINESS_ROADMAP.md), [OPTIMIZATION_ROADMAP](Docs/Project/OPTIMIZATION_ROADMAP.md).
