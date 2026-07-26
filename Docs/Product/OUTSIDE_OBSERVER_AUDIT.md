# BlazeDB Outside-Observer Audit

**Date:** 2026-07-26  
**Repo state:** `main` @ post product-audit merge (`0c6b9b70` era)  
**Question answered:** Not “what exists,” but **what another engineer concludes about the person and process behind the repository.**

Repositories are social evidence. This audit treats BlazeDB that way.

Raw exports used for metrics live under [`observer-audit-exports/`](observer-audit-exports/).  
Product existence audit (orthogonal): [`PRODUCT_AUDIT.md`](PRODUCT_AUDIT.md).

---

## Executive verdict

**Favorable reading (now defensible):**  
A systems-capable Swift engineer built an ambitious encrypted embedded database, expanded too far (APIs, docs, branches, claims), then began the harder maintainer work: narrowing the public product, installing evidence hierarchies, correcting overclaims, and protecting storage/ABI boundaries.

**Unfavorable reading (still available to a hostile skim):**  
Large AI-assisted bursts, marketing-as-docs archaeology, tag-version confusion, hundreds of stale branches, and a test/CI story that is serious but easy to mis-sell via raw counts.

**Net:** The *current homepage* supports the strong story. The *tree depth* still leaks the weak story. Recent July 2026 work is the right second half of the career narrative — incomplete until Archive/Status residue and a few residual “production-ready” leftovers stop ambushing searchers.

Your preliminary hypothesis was essentially correct.

---

## 1. First-impression audit (five audiences)

### Swift developer considering adoption

| | |
|--|--|
| **Believes** | In-process encrypted document DB; structs; `open`/`put`/`get`/`query`; CLI; optional C ABI. |
| **Trusts** | Root README, HelloBlazeDB, SPM tag, Docs support-state table. |
| **Inflated** | Apple platforms as “ready like Realm”; Go as a path; “advanced supported” schema while guides are consolidating. |
| **Can start?** | Yes on macOS; Linux core plausible. iOS runtime confidence is borrowed, not PR-gated for BlazeDBCore XCTest. |
| **Contribute?** | Examples/docs/tests yes; storage core intimidating. |
| **About Michael** | Productive solo maintainer who recently got honest. |

### Experienced database engineer

| | |
|--|--|
| **Believes** | Page store + AES-GCM + WAL + single-writer flock; real crash suites; not a distributed DB. |
| **Trusts** | Durability status doc, Tier0/1, product audit’s blunt risks. |
| **Inflated** | ACID theater vs snapshot/backup; `createIndex` ⇒ O(log n); “format stable” without CI open of prior native DBs; Archive million-ops fiction. |
| **Can start?** | For study, yes. For production bet, after reading overflow/WAL/fsync caveats. |
| **Contribute?** | Only with checklist + exact commands; freeze culture historically said “don’t touch.” |
| **About Michael** | Learned restraint late; engine seriousness outran compatibility gates. |

### Open-source contributor

| | |
|--|--|
| **Believes** | Serious package: `./dev`, tiers, CONTRIBUTING, Experiments. |
| **Trusts** | CI tier doc + workflows over Status COMPLETE pages. |
| **Inflated** | `blazedb doctor` as if dispatched; Go preview; KMM CI ≠ SDK. |
| **Can start?** | Yes for non-core; first hour may burn on CLI doc drift. |
| **Contribute?** | Docs/CI/examples likely; core only if process is respected. |
| **About Michael** | Process after overclaim era — good sign if residue shrinks. |

### Interviewer reviewing GitHub

| | |
|--|--|
| **Believes** | Nontrivial systems work: storage, crypto, FFI, multi-lane CI. |
| **Trusts** | Recent PRODUCT_AUDIT / ROADMAP / README narrowing. |
| **Inflated** | Archive titles (`INSANE_FEATURES`, crazy metrics); Status “Production Readiness Complete”; tag `1.0.0` “Production Ready” (2025-10). |
| **Signal** | **Strong story available:** breadth → honesty → maintainer policies. **Weak story still findable:** generated prose pile + branch zoo. |
| **Ask in interview** | “What do you no longer claim?” and “What gates a release?” — recent answers are good. |

### Recruiter (README + commit graph only)

| | |
|--|--|
| **Believes** | Encrypted Swift DB, multi-platform, v2.8.1. |
| **Trusts** | Badges and release number. |
| **Misses** | Go emptiness; Archive; what Tier0 actually means. |
| **About Michael** | Busy indie OSS author; may oversell scope unless coached. |

**30-second skim verdict:** Homepage is mostly usable and sober. One click into Archive or a stale Summary line still discounts trust.

---

## 2. Documentation-history audit (identity arc)

Chronology from tags + commit themes (not mythology):

| Period | Identity the docs were selling | What the history shows |
|--------|--------------------------------|-------------------------|
| **2025-08** | Swift package structure | Real foundation. |
| **2025-10** | Tag `1.0.0` — “Production Ready Release” | Credibility landmine. Early “done” stamp. |
| **2025-11** | Mega README / protocol / sync / server dump | Largest churn commit in history (~206k lines, ~583 files) titled like a README update — classic expansion burst. |
| **2025-12** | Hardening / remove force unwraps | Serious corrective engineering wave (~119 non-merge commits that month). |
| **2026-01** | Parallel `v0.1.x` stream + fatalError rewrites | Versioning confusion; large mixed fix commits. |
| **2026-03** | OSS cleanup, WAL/security specs | Correctness-focused; still giant commits. |
| **2026-04** | Peak throughput month (**374** non-merge commits) | CI/OSS/Android energy; ~40% fix/ci-ish subjects — stabilization factory. |
| **2026-06** | Android/KMM runtime proof + honest benches | Capability expansion with experimental labeling improving. |
| **2026-07** | C ABI → dynamic BlazeDBC → **product narrowing + evidence roadmap** | Second half of the career story becomes visible on `main`. |

**Coherent maturation story?**  
Yes *if* you narrate it as: ambition → overclaim → hardening → OSS/CI → FFI → honesty.  
No *if* a stranger lands on Archive `DISTRIBUTED_COMPLETE` or Status `PRODUCTION_READINESS_COMPLETE` first.

**Doc volume signal:** ~481 markdown files under `Docs/` alone; ~136 in Archive, ~42 in Status, ~28 in Audit. Plus large `.claude` / artifact markdown noise if you `find` the whole tree. That is not “undocumented”; it is **under-curated**.

---

## 3. Commit-quality audit

### Scale (from live git, 2026-07-26)

| Metric | Value |
|--------|------:|
| Non-merge commits (`--all`) | **836** |
| Merge commits | **35** |
| Primary author | Michael Danylchuk (~817 via shortlog aliases) |
| Cursor Agent / cursor[bot] / cursor-agent | **~35** attributed commits |
| `Made-with: Cursor` in commit bodies | **97** |
| `Co-authored-by: Cursor…` | **16** |
| External (finagolfin) | **1** |

### Cadence

| Month | Non-merge commits |
|-------|------------------:|
| 2025-12 | 119 |
| 2026-01 | 71 |
| 2026-03 | 84 |
| **2026-04** | **374** |
| 2026-05 | 24 |
| 2026-06 | 66 |
| 2026-07 | 73 |

April 2026 is the social red flag: nearly half a year of commits in one month, heavy fix/CI ratio. Productive *or* uncontrolled — outsiders will pick based on whether outcomes stabilized (they mostly did) and whether claims narrowed (lagged until July).

### Size

| Metric | Value |
|--------|------:|
| Median files / commit | **2** |
| P90 files | **11** |
| Max files | **582** (README/protocol mega-commit) |
| Median line churn | **60** |
| P90 churn | **622** |
| Max churn | **~206k** |

Most commits are reviewable. A minority are unreviewable monsters. Those monsters dominate first impressions of `git log --stat`.

### Composition

| Metric | Value |
|--------|------:|
| Docs-only commits | **~25%** |
| Giant (files≥50 or churn≥2000) | **~4%** |
| Conventional prefixes (`feat:`/`fix:`/…) | **~60%** |
| Vague/very short subjects | **~4%** (better than feared) |

### Branch zoo

| Metric | Value |
|--------|------:|
| Local branches (approx) | **268** |
| Remote refs | **171** |
| Remotes **100+ commits behind** `origin/main` | **123** |
| Remotes at tip of main | **2** |

This is the strongest “process outran review” signal. Historical WIP is not deleted; it reads like a second repository glued to the first.

### Tag narrative (outsider confusion)

- `1.0.0` (2025-10) — “Production Ready”
- `v0.1.0`–`v0.1.3` (2026-01) — “first stable” *after* 1.0.0
- `v2.5`–`v2.8.1` — current line
- `ci-android-sdk-6.3.2` — tooling tag in the release namespace

Interviewers notice this. Explain it as early versioning mistakes + later SemVer discipline — or clean up the story in RELEASE/CHANGELOG FAQ.

### Can another engineer review safely?

**Often yes** on median commits. **No** on the mega commits and on “fix after fix” CI thrash without reading the failure.  
**July 2026 commits** (dev tooling, README honesty, product audit) are among the *most* reviewable and purpose-clear in the history.

Central answer: frequency is not the problem. **Context preservation and residue cleanup** are.

---

## 4. Claim-to-evidence audit

| Claim (as heard) | Class | Notes |
|------------------|-------|-------|
| AES-GCM at rest, password required | **Verified** | Implementation + tests; external review still incomplete |
| WAL / crash recovery | **Narrowly tested** | Real suites; fsync-only / overflow orphans / dual WAL modes |
| C ABI byte KV + dynamic `BlazeDBC` | **Verified** (narrow) | Header + smoke + C example; packaging/CI gaps remain |
| Go integration | **Experimental / docs-only** | **0 `.go` files**; recipe only |
| macOS / Linux runtime | **Verified** (core) | PR/nightly lanes |
| iOS “supported / production-ready” | **Was overstated** | Compile-tested; Summary line corrected in this pass |
| Huge test count ⇒ confidence | **Misleading if unsourced** | Ask what *gates* releases (Tier0/1 PR; Tier0–3 on tags). Deep is non-blocking. |
| Distributed sync | **Deferred** now; **Historical-overstated** in Archive | |
| B+ tree product | **Experimental stub** | Print-tree only |
| Benchmarks / 833x / millions ops/sec | **Local/narrow** vs **Historical fiction** | Current README avoids theater; Archive does not |
| Migrations / schema | **Narrowly tested** | Docs consolidating |
| On-disk compatibility across releases | **Partial** | Dump fixtures under `Tests/CompatibilityFixtures/` (`v0.1.3`, `v2.7.0`); harness **skips if absent**; **not** a hard CI proof of native prior-tag `.blazedb` open |
| “Production ready” (Status COMPLETE / old tags) | **Historical-overstated** | |

Classification key matches the product audit: Verified / Narrowly tested / Experimental / Historical-overstated.

---

## 5. Maintainer-signal audit (what this says about you)

| Signal | Grade | Comment |
|--------|-------|---------|
| Systems understanding | **Strong** | Storage, crypto, WAL, FFI, multi-platform CI are not CRUD cosplay. |
| Ability to scope | **Improving** | July product narrowing is the evidence; Archive is the counter-evidence. |
| Code-review discipline | **Mixed** | Median commits fine; mega commits and branch zoo say otherwise. |
| Ownership | **Strong** | Solo authorship, security email, freeze policy, reject-bot automation. |
| Debugging ability | **Strong** | Long CI/WAL/KMM fix arcs; willingness to thrash until green. |
| Correcting mistakes | **Strong (recent)** | Claim rollback, dynamic BlazeDBC after static FFI pain, honest Go demotion. |
| Dependence on generated prose | **Historically high** | 97× `Made-with: Cursor`; Archive tone; INSANE_FEATURES. **Recently restrained** on the homepage. |
| Prototype vs supported product | **Improving** | Support-state table + ROADMAP Not-planned. Residue remains. |
| Stable public contract | **Emerging** | C ABI rules, SemVer tags, CONTRIBUTING; fixtures/checklist/release artifacts still catching up. |

**Interview framing that works:**

> I built an ambitious embedded database, discovered that breadth and aspirational docs undermined trust, audited the repository against implementation and CI, narrowed the public product to the encrypted Swift core plus a documented C ABI, and put maintenance policies around storage changes and release honesty.

**Interview framing that fails:**

> I have 2,000+ tests and every database feature.

---

## 6. What to squash, archive, rename, or leave alone

| Action | Target | Why |
|--------|--------|-----|
| **Leave alone** | Root README, ROADMAP, PRODUCT_AUDIT, RELEASE v2.8.1 story | Current trust surface. |
| **Leave alone (history)** | Old mega commits | Rewriting published history is worse than explaining it. |
| **Archive harder** | `Docs/Archive/*`, Status `*_COMPLETE*`, `INSANE_FEATURES.md`, competing FEATURE_ROADMAP | Add unmistakable banners; remove from default Docs search paths if possible; do not delete without backup. |
| **Delete or hide remote** | Stale branches 100+ behind | Social noise; keep a few named historical refs if needed. |
| **Rename / FAQ** | Tag confusion (`1.0.0` vs `v0.1.x` vs `v2.x`) | One paragraph in RELEASE or CONTRIBUTING. |
| **Do not squash** | July honesty + audit commits | They *are* the second half of the story. |
| **Prioritize next** | Compatibility fixture **CI gate**, curated BlazeDBC artifacts, Go sources or Go demotion everywhere, CLI dispatch honesty | Converts narrative into mechanical trust. |

---

## 7. Periods: strongest vs weakest

| Period | Outsider grade |
|--------|----------------|
| **Weakest** | 2025-10–11 (`1.0.0` production-ready + mega marketing commit) |
| **Painful but real** | 2025-12 / 2026-03–04 (hardening + CI thrash) |
| **Capability without identity control** | 2026-06 (KMM/Android) |
| **Strongest public signal** | **2026-07** (C ABI practicality + README narrowing + evidence roadmap + storage checklist) |

---

## 8. Recommendations (observer → maintainer)

1. Keep the homepage boring and true.  
2. Make Archive/Status COMPLETE impossible to mistake for current truth (banner + Docs index already help; search/discoverability still hurts).  
3. Gate releases on **at least one** prior-version dump/DB open path (fixtures exist; skipping is not proof).  
4. Either land Go sources + CI or remove Go from “choose your path” until then.  
5. Prune remote branches aggressively.  
6. In interviews, lead with the **correction arc**, not the feature buffet.  
7. Stop measuring progress in test counts and commit volume; measure **gates and unbroken on-disk files**.

---

## 9. Validation / method notes

Exports generated:

- `observer-audit-exports/blazedb-history.txt`
- `observer-audit-exports/blazedb-commit-details.txt`
- `observer-audit-exports/blazedb-contributors.txt`
- `observer-audit-exports/blazedb-tags.txt`
- `observer-audit-exports/blazedb-doc-files.txt` (includes noise paths; prefer `find Docs -name '*.md'`)

Also used: live `git log`/`shortlog`/`for-each-ref`, pattern scan of Docs for 833x / theoretical / production-ready / CTE-spatial-vector language, and the first-impression pass summarized above.

**Not claimed:** full human reading of all 836 commit bodies; live CI job colors; external recruiter interviews.

---

## Bottom line

BlazeDB’s history communicates exactly the dual story you hypothesized:

1. **Builder who can go deep and wide**, sometimes faster than validation.  
2. **Maintainer who noticed**, installed evidence rules, and started deleting false confidence from the public surface.

The product audit answered *what ships*.  
This observer audit answers *whether a stranger believes you*.  

Belief is rising. Residue still sets the ceiling.
