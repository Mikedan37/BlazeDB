# README and documentation onboarding audit

Date: 2026-07-26  
Branch inspected: `feat/storable-query-keypath-sort` at work including `50f9041a` and later edits in this session  
Scope: public README, Docs index, adjacent onboarding links, contributor entry via `./dev`, scheme docs

This report records evidence used before rewriting the public homepage. It is not a substitute for canonical architecture or durability docs.

---

## Executive summary

The public README drifted twice in opposite directions. Mid-2026 Swift-first READMEs (`fb304374`, `16cc133f`) taught newcomers a clear mental model (one encrypted file, `put` / `get` / `query`) with Path A/B onboarding. The v2.8.x C ABI push (`ab941876`, `86344ee2`) made embeddability the identity. Commit `50f9041a` restored Swift-first ordering but stayed too terse, used em dashes, and did not recover the best historical teaching structure.

The documentation index already had a useful support-state and audience model. It needed tightening (Tools wrongly sat under Historical; `./dev` and scheme docs were under-linked) rather than replacement.

This pass:

- Rewrote `README.md` as a product homepage that routes readers and restores verified teaching structure from history
- Tightened `Docs/README.md` as the authority map without duplicating the README
- Reordered `Examples/README.md` so Swift onboarding leads and C ABI follows
- Verified `HelloBlazeDB`, `./dev help`, `./dev tiers`, and one focused `./dev test`
- Documented claims that were omitted or qualified for lack of clean evidence

---

## Current product identity

Verified description:

**BlazeDB is an encrypted embedded document database written in Swift.** It runs in-process, stores data in a local encrypted file, exposes typed and raw Swift APIs, ships a CLI, and optionally exposes the same engine through a stable C ABI (`BlazeDBC`).

It is not a client/server database in the default OSS product. Distributed sync/server/discovery remain deferred from default packaging ([Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md); `Package.swift` excludes `Distributed` / `Telemetry` from `BlazeDBCore` and keeps staging targets separate).

---

## Shipped-default boundary

| Claim | Evidence | Verdict |
|-------|----------|---------|
| Embedded encrypted engine | `BlazeDBCore` target; EasyOpen requires password; AES-256-GCM documented | Supported |
| Typed APIs (`BlazeStorable`, `BlazeDB.open`) | `PublicFacadeAPI.swift`, HelloBlazeDB, ReadmeSamples | Supported |
| Raw / byte APIs | `BlazeDBClient+ByteKV.swift`, C ABI wrapping byte KV | Supported |
| Durability / WAL | Durability status doc; Tier0 durability lane scripts | Supported (see exact contract doc) |
| Import/export | `BlazeDBClient+Export.swift`, importer types | Supported |
| Health / stats | `BlazeDBClient+Health.swift`, `stats()` usage in guides | Supported |
| CLI | `blazedb` product → `BlazedbCLI` | Supported |
| Migrations / schema validation / indexing / manual mapping | Examples + API reference + tests exist | Advanced but supported (not day-one README depth) |
| Distributed sync / server / discovery | Excluded from core target; deferred status doc | Conditional / deferred |
| Full telemetry packaging | Telemetry excluded from core; staging product | Conditional / deferred |
| Official `blazedb-go` | Examples/Go is preview; release notes say planned 2.9.0 | Not shipped |

---

## Documentation authority map (condensed)

| Area | Canonical entry | Notes |
|------|-----------------|-------|
| Product homepage | `README.md` | Routes; does not replace guides |
| Authority / navigation | `Docs/README.md` | Support-state + audience |
| Getting started | `Docs/GettingStarted/README.md` | Keep single first path |
| Longer usage | `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md` | |
| API lookup | `Docs/API/API_REFERENCE.md` | |
| Architecture | `Docs/Architecture/` | Prefer over informal Design notes for “what ships” |
| C ABI | `Docs/Architecture/C_ABI_BYTE_KV.md` | |
| Testing / CI | `Docs/Testing/CI_AND_TEST_TIERS.md` | |
| Schemes | `Docs/Build/XCODE_SCHEMES.md` | Commit `78016d75` |
| Contributor process | `CONTRIBUTING.md` | Owns full workflow |
| Benchmarks | `Docs/Benchmarks/README.md` | |
| Internal | `Docs/Internal/` | Non-authoritative |
| Historical | `Docs/Archive/`, Meta, Audit, Project | Non-authoritative |

Duplicate risk remains across some `Docs/Status/*` notes and Getting Started roadmaps. Follow-up: mark stale Status files superseded rather than rewriting all of them in this pass.

---

## Public API findings

- Recommended opener for apps: `BlazeDB.open(name:password:)` in `PublicFacadeAPI.swift`.
- HelloBlazeDB uses `BlazeDB.open(at:password:)` with a temp URL for deterministic demos. Both are valid.
- README sample matches the public facade and historical Start Here teaching (includes `get`).
- Package products for consumers: `BlazeDB`, `BlazeDBCore`, `BlazeDBC` (dynamic), `BlazeDBCStatic`, Android bridge products, `blazedb` executable.

---

## Examples inventory (onboarding-relevant)

| Example | Audience | Command verified this session |
|---------|----------|-------------------------------|
| HelloBlazeDB | First Swift run | `swift run HelloBlazeDB` → Success |
| CorePathSmoke | Portable core | Not re-run this session; listed in Package.swift |
| MVVMPattern | Architecture pattern | Not re-run |
| ReadmeSamples | Doc CI fixtures | Relies on `#start-here-new-users` (restored) |
| Examples/C | Embedders | Not compiled this session |
| SyncExample_* | Deferred | Documented as non-default |

`Examples/README.md` previously led with C ABI; reordered so Start Here is first.

---

## Tools inventory

| Tool | Role | Notes |
|------|------|------|
| `blazedb` | Interactive CLI | Shared scheme cleaned in `78016d75` |
| `./dev` | Contributor workflows | Verified help/tiers/focused test |
| BlazeDoctor / Dump / Info | Maintenance | Package executables |
| BlazeStudio / Visualizer | Apps | Archive stays in their Xcode projects |
| BlazeDBBenchmarks | Perf | Shared scheme Profile Release |

---

## Tests and quality gates

| Command | Result this session |
|---------|---------------------|
| `./dev help` | Printed expected developer command surface |
| `./dev tiers` | Listed tiers 0–3 with script paths |
| `./dev test BPlusTreeNodeTests.createsSimpleTree` | Passed (1 test) |
| `./dev tier0` | Not re-run full suite this session (expensive); documented as PR gate |

Policy reminder: focused edit → `./dev test`; small PR → `./dev tier0`; storage/WAL/encryption changes → escalate per `CI_AND_TEST_TIERS.md` and CONTRIBUTING. No new governance invented here.

---

## Benchmarks and profiling

- Target `BlazeDBBenchmarks` exists; Docs/Benchmarks describe SQLite comparison methodology.
- Shared scheme `BlazeDBBenchmarks` is committed under `.swiftpm/.../xcschemes/` with Release Profile.
- README intentionally omits raw ops/sec claims without environment capture.
- Profiling `dev test` through the CLI scheme is explicitly discouraged in scheme docs and README.

---

## Metrics audit

| Metric type | Historical? | Action |
|-------------|-------------|--------|
| Release badge / version | Yes | Keep (v2.8.1) |
| Platform badge | Yes | Keep; link COMPATIBILITY |
| Test count / LOC / stars | Sometimes | Rejected as vanity / brittle |
| Benchmark numbers in README | Sometimes | Link methodology instead of pasting stale figures |
| Support-state table | `aa1dedd4` | Restored conceptually on README |

---

## Git-history findings

| Commit / era | What it did | Value |
|--------------|-------------|-------|
| `fb304374` / `16cc133f` | Swift-first teaching, Path A/B, mental model, recap table | **Restored selectively** into README Start Here |
| `aa1dedd4` | Explicit shipped vs advanced vs deferred table | **Restored** as README support table |
| `ab941876` / `86344ee2` | C ABI homepage dominance | Keep C content; demote from identity |
| `50f9041a` | Swift-first reorder after C ABI era | Correct direction; expanded in this pass |
| `78016d75` | Lean shared Xcode schemes | Documented; verified files exist |
| `f0038050` / `00ba6100` / `fd9d1988` | `./dev` contributor surface | Front-door in README + CONTRIBUTING |

### Restored from history

- Plain-English “one encrypted file” teaching
- Recap table for open/put/get/query
- Path clarity (repo try vs add package)
- Support-state table
- Stronger documentation routing without duplicating Docs/README

### Deliberately not restored

- Giant badge walls / Sponsors spectacle as primary identity
- TypedStore-first 60-second sample that disagreed with current HelloBlazeDB facade
- Em dash heavy style (repo preference: avoid)
- Raw benchmark numbers without methodology
- Treating sync examples as core onboarding

---

## Storage-engine contributor risks

High-risk areas already have architecture / durability / key-management docs. CONTRIBUTING should keep pointing maintainers at explicit validation commands. Proposed follow-up (not implemented as policy text here): add a short “storage change checklist” subsection only after maintainers agree on required tiers for WAL/format changes.

---

## Broken links / versions corrected

| Issue | Fix |
|-------|-----|
| Getting Started pin `2.7.5` | Updated earlier to `2.8.1` |
| Dead `#start-here-new-users` | Anchor restored on README |
| Examples README led with C ABI | Reordered |
| Docs index put Tools under Historical | Moved to canonical product docs |
| Em dashes in prior README rewrite | Removed |

---

## Claims omitted or qualified

- Exact multi-platform Apple matrix wording beyond badge + COMPATIBILITY link (watchOS/tvOS/visionOS appear in older badges; confirm against current CI before restoring full badge string)
- Production readiness slogans from older Status docs
- RLS “not available” absolute language (CLI RLS was restored in history; examples marked “confirm against release notes”)
- Throughput / power claims from Benchmarks README copied into homepage

---

## Commands run

```text
./dev help
./dev tiers
./dev test BPlusTreeNodeTests.createsSimpleTree
swift run HelloBlazeDB
git log --oneline -- README.md Docs/README.md
git show fb304374:README.md (and 16cc133f, aa1dedd4, ab941876)
```

Not run this session: full `./dev tier0`, `swift build -c release --product BlazeDBC`, Instruments profiling, exhaustive Markdown link crawler.

---

## Remaining uncertainty / follow-ups

1. Exhaustive link check across entire `Docs/` tree.
2. Supersede or quarantine stale `Docs/Status/BETA_PRODUCTION_READINESS.md`-style notes.
3. Confirm Apple platform badge completeness against current CI matrix.
4. Optional: storage-change contributor checklist after maintainer agreement.
5. Examples single-file `swift Examples/QuickStart.swift` claim in Examples README may need verification (shebang / swift-sh).

---

## Follow-up pass (promise tightening)

Date: 2026-07-26 (same day as primary audit)

Applied reviewer corrections without inventing new product claims:

| Issue | Change |
|-------|--------|
| "verify against" heading | Renamed to **Support state** with Package.swift/tests/CI as source of truth |
| Migration/schema contradiction | Advanced table now links `Docs/MIGRATION.md` + API Reference; states schema guides are under consolidation; Status/SQLite migrator write-ups treated as historical unless linked |
| "Frozen" C ABI wording | Index uses **Documented C interoperability surface**; notes published-symbol rule lives in the ABI doc |
| Durability "contract" in index | Described as **WAL, durability modes, and recovery behavior** (doc still defines default-path guarantees) |
| Encryption wording | README: password required + encrypted at rest (matches EasyOpen) |
| health/stats prominence | Folded into **inspection APIs** in support table |
| Master Documentation Index | Retitled/described as **Maintainer documentation inventory** |
| Audit vs Historical | Split **Internal and project records** (includes current `README_AUDIT.md`) from **Historical** |
| Examples labeling | Explicit Default / Advanced / Conditional / Deferred / Experimental |
| Security naming | Distinguished architecture (`Docs/Security/`) vs policy (`SECURITY.md`) |

Remaining follow-ups unchanged: full link crawl, Apple platform badge vs CI, storage-change checklist.
