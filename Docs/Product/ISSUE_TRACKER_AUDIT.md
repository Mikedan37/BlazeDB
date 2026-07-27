# BlazeDB Issue Tracker Audit

**Date:** 2026-07-26  
**Repo tip at audit:** `c2ad82cf`  
**Open issues counted:** 41  
**Method:** Live GitHub inventory + code/docs evidence + agent cross-checks. Mutations that close/relabel many issues are **proposed only** until maintainer approval (Phase 12).

Document roles (unchanged):

| Doc | Role |
|-----|------|
| [`ROADMAP.md`](../../ROADMAP.md) | Active supported-product priorities |
| [`ROADMAP_BACKLOG.md`](ROADMAP_BACKLOG.md) | Verified gaps awaiting promotion |
| [`PRODUCT_AUDIT.md`](PRODUCT_AUDIT.md) | Evidence inventory |
| **GitHub Issues** | Executable units of work |
| **This file** | Tracker health + proposed mutations |

---

## Executive summary

The tracker is **already strong**: most #258–#291 issues are evidence-backed, roadmap-aligned, and better than typical OSS noise. The main risks now are **volume without navigation**, a few **mis-scoped labels** (especially `good first issue` on security-adjacent tickets), **stale/superseded older issues**, and **missing contributor discoverability** (no `ISSUE_GUIDE`, no `contact_links` config yet as of audit start).

**Do not open another large issue flood.** Prefer triage + a handful of proven doc/tooling tickets + clear “start here” guidance.

### Highest-risk open work (keep prominent)

| Priority | Issues | Why |
|----------|--------|-----|
| P0 correctness | #277, #278, #279 | Data loss window; UB iteration; deadlock |
| P0 durability semantics | #276 (fix gated on #291), #281, #283 | Txn I/O, index/durability order, Linux barrier |
| P1 caches / API honesty | #280, #282, #274/#261 | Stale reads; silent drops; scan vs index claims |
| P1 product hardening (Now) | #263–#266, #259 | Fixtures, Go, BlazeDBC, schema docs, CLI honesty |
| Investigation | #291, #269→done-ish | Measure before amortize |

---

## Current issue inventory

Evidence quality: **proven** / **strong** / **weak** / **stale**.

| # | Category | Evidence | GFI OK? | Action |
|---|----------|----------|---------|--------|
| 30 | portability/decode | weak–stale | no | rewrite residual or close-done |
| 43 | compression portability | strong | no | relabel bug→enhancement; drop High Priority |
| 51 | Linux Tier1 | strong | no | keep; optional split docs vs enablement |
| 58 | shipped-core contract | **closed** | — | superseded by current docs |
| 73 | SecureConnectionTests lane | proven | no | keep |
| 173 | deprecated open docs | proven | **yes** | keep; add GFI |
| 174 | put=upsert docs | proven | **yes** | keep; add GFI |
| 258 | `--version` | proven | yes | keep |
| 259 | doctor docs | proven | yes | keep |
| 260 | contact_links | proven | yes | **keep open** until `config.yml` on `main` |
| 261 | QUERY_PERFORMANCE O(log n) | proven | yes | keep; link #274 |
| 262 | Homebrew head-only | proven | yes | keep |
| 263 | compat fixtures CI | proven | no | keep (Now) |
| 264 | Go smoke CI | proven | no | keep (Now) |
| 265 | BlazeDBC release+C | proven | no | keep (Now) |
| 266 | schema guide | strong | yes | keep (Now) |
| 267 | `last_error` | proven | no | keep (Next) |
| 268 | dead cacheHit | proven | yes (remove path) | keep |
| 269 | write-path profile | **closed** | — | done in `c2ad82cf`; continue #291/#276 |
| 270 | platform PBKDF2 | strong | no | keep; link #273 |
| 271 | engine_only KDF | proven | no | keep |
| 272 | stale LATENCY.md | proven | yes | keep |
| 273 | SECURITY.md 10k | proven | yes | keep; link #270 |
| 274 | wire indexes / honesty | strong | no | keep; link #261 |
| 275 | LiveQuery coalesce | strong | no | keep |
| 276 | txn fsync amortize | proven | no | rewritten; optimize **blocked on #291**; `durability` |
| 277 | crash lose commit | proven | no | keep; `durability` + release-blocking |
| 278 | live keys mutation | proven | no | keep |
| 279 | nested sync deadlock | proven | no | keep |
| 280 | fetchAll cache | proven | no | keep; optional split A/B |
| 281 | insertBatch index before sync | proven | no | keep |
| 282 | typed bulk silent drop | proven | no | keep |
| 283 | Linux overflow barrier | proven | no | keep |
| 284 | updateBatch not batched | proven | no | keep; link #276 |
| 285 | dead txnPagesWritten | proven | yes (remove/doc) | keep |
| 286 | RLS docs wrong | proven | yes | keep; link #288 |
| 287 | migrators “shipped” | proven | yes | keep |
| 288 | enableRLS fail-open | proven | **docs-only GFI** | rewritten; Non-goals; behavior change not filed |
| 289 | ./dev arch mismatch | strong | yes | keep |
| 290 | Dump/Info JSON | strong | yes | keep |
| 291 | widen write-profile | strong | no | keep; **blocks #276 optimize** |

### Duplicate / linkage map

```
#261 (docs O(log n)) ──complements──► #274 (execution)
#269 (profiler landed) ──feeds──► #291 (matrix) ──blocks──► #276 (amortize fix)
#276 ──related──► #277 (commit restore) / #281 / #284
#286 ──related──► #288 (fail-open docs)
#270 ──related──► #273 (doc iterations)
```

---

## Label inventory

**Present and useful:** `bug`, `documentation`, `enhancement`, `good first issue`, `help wanted`, `ci`, `tests`, `security`, `storage-engine`, `reliability`, `concurrency`, `api-correctness`, `linux`, `Portability`, `High Priority`, `tech-debt`, `cleanup`, `typed-store`, …

**Gaps (optional, do not explode taxonomy):**

| Proposed | Purpose |
|----------|---------|
| `durability` | Crash/WAL/commit window issues (#277, #276, #281) |
| `performance` | Measured perf work (#269–#276, #291) |
| `ffi` / reuse release | C ABI (#264–#267) |
| `needs design` | Before coding (#276 after #291, #274 wire path) |
| `roadmap` / `backlog` | Navigation only if used sparingly |

**Rules for `good first issue`:** no storage-format, ABI, crypto behavior, authorization semantics, or concurrency redesign. Docs/config/tooling diagnostics only unless Non-goals are explicit.

---

## Missing candidates (verified, not auto-flooded)

| ID | Candidate | Evidence | GFI? | Propose |
|----|-----------|----------|------|---------|
| N1 | `QUERY_PLANNER.md` still claims O(log n) index execution | Proven | yes | **File** (docs) |
| N2 | `DURABILITY_MODE_SUPPORT` claims WAL fsync before page write; code uses `appendDeferred` | Proven | yes | **File** (docs) |
| N3 | `SAFETY_MODEL` “operations buffered” vs write-through txn | Proven | yes | **File** (docs; link #276) |
| N4 | Contributor `ISSUE_GUIDE` + Finding work in CONTRIBUTING | Proven DX gap | yes | **Land docs** (this pass) |
| N5 | Crypto-change checklist + PR checkbox (S3) | Proven | yes | Propose issue after approval |
| N6 | CLI password on argv (`BlazeDoctor`/`Dump`/`Info`) | Proven | partial | Propose after approval (security-sensitive) |
| N7 | BlazeDBC use-after-close / raw handle | Proven | no | Propose after approval |
| N8 | Refactor: centralize durability publish boundary | Strong (cluster #276/#277/#281) | no | Propose after approval |
| N9 | Refactor: centralize read-cache invalidation | Strong (#280) | no | Propose after approval |
| N10 | C3 overflow orphan reclaim test | Strong | no | Propose after approval |
| N11 | P1 short CI bench regression | Roadmap Next | no | Propose after approval |
| N12 | R2 Linux `.so` release | Deferred from #265 | no | Propose after approval |

**Not filing now:** N5–N12 await approval (Phase 12).

---

## Refactor candidates (max 6 — proposals only)

1. **Centralize durability commit boundary** — single insert / insertBatch / txn commit share stage→sync→publish→clear-artifacts. Invariants: crash recovery, publish-last overflow. Grounded in #276/#277/#281.
2. **Centralize read-cache invalidation** — one `invalidateReadCaches()` on all mutations; remove unused Performance duplicate. Grounded in #280.
3. **Unify batch mutation durability** — insertBatch vs updateBatch. Grounded in #284.
4. **Centralize FFI handle validation** — generation/magic; safe double-close. Grounded in N7.
5. **CLI output encoding helper** — JSON/text for Doctor/Dump/Info. Grounded in #290/#259.
6. **Doc support-state banner** — one include for experimental/deferred. Grounded in #286/#287/#58.

---

## Contributor suitability review

**Safe GFI pool today:** #173, #174, #258–#262, #266, #268 (remove path), #272, #273, #285 (doc/remove), #286–#287, #288 (docs-only), #289–#290, plus N1–N3.

**Mis-risk GFI:** #288 if contributor changes fail-open to fail-closed without design. Fix: title/Non-goals.

**Never GFI:** #276–#283, #264–#265, #267, #270, crypto redesigns.

---

## High-risk triage recommendations

| Issue | Recommendation |
|-------|----------------|
| #277 | Add `durability` + treat as **release-blocking** until fixed or explicitly risk-accepted |
| #278/#279 | Keep High Priority; ensure reproduction snippets in body (already code-proven) |
| #288 | Docs-only Non-goals; remove implication of auth redesign |
| #276 | State: **optimize blocked on #291**; measurement already sufficient for “defect exists” |
| #291 | Investigation only — no optimization acceptance criteria |
| #269 | Close as completed instrumentation; point to #291/#276 |

---

## Approved mutations (this gardening pass)

| Action | Issue | Status |
|--------|-------|--------|
| Close completed | #269 | Applied (comment → `c2ad82cf`; opt remains #291/#276) |
| Close superseded | #58 | Applied (canonical docs pointers) |
| Hold open | #260 | **Open until** `config.yml` is on `main`; then close with merge SHA |
| Rewrite | #276 | Applied (contract vs optimize; blocked on #291; `durability`) |
| Rewrite | #288 | Applied (docs-only + Non-goals; GFI retained) |
| Relabel | #43 | Applied (`enhancement`; drop `High Priority`) |
| Add GFI | #173, #174 | Applied after body sharpening |
| Label `durability` | #276, #277, #281, #283 | Applied |
| Refactors / N5–N12 | — | **Not filed** (remain proposals below) |

### B. New issues already filed (prior pass)

| # | Title |
|---|-------|
| [#292](https://github.com/Mikedan37/BlazeDB/issues/292) | Docs: Correct QUERY_PLANNER O(log n) claims |
| [#293](https://github.com/Mikedan37/BlazeDB/issues/293) | Docs: Fix DURABILITY_MODE_SUPPORT WAL fsync wording |
| [#294](https://github.com/Mikedan37/BlazeDB/issues/294) | Docs: SAFETY_MODEL buffered txn I/O honesty |

### Still proposed only (do not file yet)

N5–N12 and refactor candidates 1–6 above. Existing defects remain the executable units.

### Contributor docs landed this pass

- `Docs/Contributing/ISSUE_GUIDE.md`
- `.github/ISSUE_TEMPLATE/config.yml` (closes #260 **after merge to main**)
- CONTRIBUTING “Finding work”
- Docs/README link to this audit + ISSUE_GUIDE

---

## Validation commands

```bash
git rev-parse --short HEAD   # c2ad82cf at audit start
git status --short
git diff --check
./dev help
arch -arm64 swift run HelloBlazeDB
# Full: arch -arm64 ./dev tier0
# Write profile: BLAZEDB_BENCH_MODE=write_profile swift run -c release BlazeDBBenchmarks
```

**Run this audit:** `./dev help` OK; `HelloBlazeDB` OK. Full tier0 not re-run in this pass (recently green under `arch -arm64`). Local dirty files `BlazeDBCLITests/DeveloperCommandsTests.swift` and `BlazeMCP/MCPServer.swift` were **not** touched (unrelated WIP).

---

## Unverified areas

- Full external `fs_usage`/`strace` confirmation of #291 (still open).
- Whether #30 residual `load(fromByteOffset:)` sites are still unsafe on Linux.
- Whether #43 High Priority still matches maintainer intent.
- Live GitHub Discussions usage (none assumed).

---

## Suggested commit message

```text
Audit the issue tracker and add contributor issue navigation.

Document inventory and triage proposals, add ISSUE_GUIDE and security
contact_links, and file a few proven documentation truth fixes.
```
