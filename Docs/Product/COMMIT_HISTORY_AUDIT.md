# BlazeDB Commit-History Audit

**Date:** 2026-07-26  
**Measured repository state:** `main` @ `3ae19461` (metrics collected after stash-recovery cherry-picks)  
**Document last updated:** tip of this file on `main` (tighten pass after `618ae179`; `git log -1 -- Docs/Product/COMMIT_HISTORY_AUDIT.md`)  
**Companion:** social first-impression reading lives in [`OUTSIDE_OBSERVER_AUDIT.md`](OUTSIDE_OBSERVER_AUDIT.md). This document answers a narrower question: **does the Git history look like deliberate evolution, rapid expansion plus cleanup, or both?**

Method: live `git log` on `main` (non-merge unless noted). Heuristics are imperfect (especially “mixed concerns” and “fix-ish” subjects) but stable enough to compare periods.

---

## Verdict

**Both.**

- **Median history is disciplined:** ~2 files per commit over the last 400 non-merge commits; P90 ≈ 15 files; only **4.5%** exceed 30 files.
- **A minority of monsters and thrash periods dominate outsider skim:** mega docs/protocol dumps, multi-concern “fix everything” CI commits, and **April 2026** volume.
- **July 2026 is the strongest recent discipline window:** narrower subjects, **0** commits >30 files in the measured window, honesty/audit/tooling commits that preserve reviewable intent, and the stash-recovery series split by concern instead of one “restore WIP” blob.

An interviewer who samples the last month sees deliberate maintainer work. One who jumps to Nov 2025 / Apr 2026 still sees construction-site energy. That dual reading is accurate, not unfair.

**Honest interpretation:** BlazeDB expanded rapidly and accumulated cleanup work, but the repository was never uniformly chaotic. Most commits were already narrow; a minority of large or mixed commits created the messiest periods. Recent history shows much stronger maintainer discipline — maturation, not merely cleanup, and not either extreme of “always pristine” or “uncontrolled sludge.”

---

## Questions answered

### 1. How often are commits oversized?

| Window | n (non-merge) | Median files | >30 files |
|--------|--------------:|-------------:|----------:|
| Last 400 on `main` | 400 | **2** | **4.5%** (18) |
| 2026-07 | 32 | 3.5 | **0%** |
| 2026-06 | 47 | 4 | 2.1% |
| 2026-05 | 17 | 2 | 0% |
| 2026-04 | 145 | 2 | 1.4% |
| 2026-03 | 58 | 3 | **12.1%** |

Distribution (last 400): **1–3 files 65%**, 4–10 22%, 11–30 9%, 31–100 3%, 100+ 2%.

**July 2026 is a partial month through July 26;** its zero oversized commits is encouraging but should not be treated as a full-month rate comparison against complete earlier months.

**Oversized is rare but memorable.** Examples in recent history include CI stabilization blobs (40–80 files) and older docs mega-commits (hundreds of files / ~206k lines). Frequency is not the disease; **tail risk** is.

### 2. How many mix code, docs, tests, and tooling?

Heuristic over last **300** non-merge commits: path buckets `{code, docs, tests, tooling}`; count commits touching **≥3** buckets.

| Signal | Value |
|--------|------:|
| Mixed (≥3 concerns) | **60 / 300 (20%)** |
| Often legitimate | C ABI + docs + smoke; `./dev` + tests; product-audit truth fixes |
| Often noisy | `fix(ci): …` touching scripts, docs, and core together |

**Twenty percent is high relative to the repository’s stated preference for concern-split commits,** though not all mixed commits are undesirable. A cohesive feature often should touch code, tests, and docs together. The failure mode is not “docs with a test,” it is **unrelated residue riding a convenient commit**.

Recent recovery commits consciously avoided that: storage / MVCC docs / test fix / benches / examples / Homebrew / Xcode scheme each got their own commit — independently reviewable and easy to revert.

### 3. Which commits immediately repair the previous commit?

Proxy (last 300 subjects): **100** start with `fix` / `fix:` (~33%). **48** adjacent fix-ish pairs (newest-first).

This is a **maintenance-intensity signal, not a defect-rate measurement.** A `fix:` subject does not prove the immediately preceding commit introduced the problem — it can be an independently discovered bug, CI portability correction, historical debt, cleanup after another branch, or a genuine immediate repair. Adjacent pairs in newest-first history likewise do not prove causation; treat them as a **social / reviewability** signal.

Interpretation:

- High fix density in **May–June 2026** (≈62–65% fix-prefix) reads as **stabilization factory** after expansion.
- July fix-prefix drops to **~22%**, with more `Add` / `Clarify` / `Ground` / `Document` verbs — less ambulance, more stewardship.
- Chains of `fix(ci)` remain a social smell; prefer one commit with evidence or a PR series with named flakes.

### 4. Are messages specific enough to review later?

| Signal (last 300) | Value |
|-------------------|------:|
| Subjects shorter than 18 chars | **1** |
| Vague keywords (`wip` / `misc` / `stuff` / …) | **1** |
| Conventional-ish prefixes historically | common (`feat:` / `fix:` / `docs:` / `ci:`) |

**Yes for recent work.** July subjects name the *why* (“Batch WAL fsyncs…”, “Ground the roadmap in a product audit…”, salt preserved via merge rather than reintroducing an inline literal).  
**Weaker historically** when a subject says “README update” while the tree moves hundreds of files.

### 5. Do feature branches tell a coherent story?

**Mixed.**

- **Coherent recent examples:** `feat/storable-query-keypath-sort` → merge `0c6b9b70` with a single focused story; `recover-stashed-wip` as an isolated recovery lane then cherry-pick onto `main`.
- **Incoherent residue:** large remote branch zoo (see outside-observer metrics: many remotes 100+ commits behind). Stale branches do not narrate; they archive panic.
- **PR merges on `main`:** relatively sparse vs direct pushes; story often lives in commit subjects more than in long-lived branch names.

### 6. Which periods look strongest or most chaotic?

| Period | Character |
|--------|-----------|
| **Strongest (recent)** | **2026-07** (partial through July 26) — honesty docs, product boundaries, `./dev`, narrow commits, stash recovered as split cherry-picks |
| **Strong engineering, noisy packaging** | 2026-03 — correctness/WAL/security; highest oversized % in spring |
| **Most chaotic socially** | **2026-04** — 145 non-merge commits on this `main` sample path / ~374 `--all` in outsider audit; CI/OSS/Android energy |
| **Ambulance months** | 2026-05–06 — lower volume, majority `fix:` subjects |
| **Weakest identity** | 2025-10–11 — `1.0.0 Production Ready` + marketing mega-commit (documented in outside-observer audit) |

### 7. Does recent history show improving maintainer discipline?

**Yes, on the dimensions that matter to reviewers:**

| Dimension | Trend |
|-----------|--------|
| Scope | July measured window: **0** oversized commits; median still small |
| Honesty | Product audit, roadmap grounding, outside-observer, COMPATIBILITY residue cleanup |
| Boundaries | Support-state wording, C ABI as dynamic product surface, Go/iOS claims corrected |
| Evidence awareness | Tier language, durability caveats, recovery split validated under `arch -arm64` Tier0 / HelloBlazeDB |
| Commit craft | Recovery consciously split implementation / tests / docs / tooling instead of one restore commit |

Remaining gap: **history residue** (old mega commits, branch zoo) still exists. Older commit bodies sometimes contain **tool-attribution trailers**. These are not defects by themselves, but combined with oversized commits and rapid follow-up fixes they may reinforce an AI-assisted, low-review impression. The objective is demonstrating judgment, not hiding tooling. Do not rewrite published history; explain it and keep landing narrow commits.

---

## Deliberate evolution vs expansion + cleanup

```text
2025-10..11   expansion / marketing identity
2025-12..03   corrective engineering waves (still some giants)
2026-04       peak throughput / social red flag
2026-05..06   fix-heavy stabilization
2026-07       product honesty + maintainer discipline  ← current tip
```

**Path characterization:** rapid expansion → repeated cleanup → **recent deliberate narrowing**.  
The valuable interview claim is not “history was always clean.” It is: **recent commits increasingly have narrower scope, explicit evidence, compatibility awareness, and clean product boundaries** — and the July record supports that claim with measurements, not vibes.

---

## Practice going forward

1. Prefer **concern-split commits** (the stash recovery is the template).
2. Treat **>30 files** as exceptional; require a one-line justification in the subject or body.
3. Avoid **unrelated residue** on CI fixes; open a follow-up commit instead.
4. Keep **July-style subjects**; never “restore stuff” / “WIP” on `main`.
5. Leave ancient mega commits alone; point interviewers at **this audit + outside-observer** for the second half of the story.
6. Make `./dev tier0` (and similar runners) **detect host/tool architecture mismatch** and print a clear remediation (`arch -arm64 …` or rebuild) instead of an opaque loader error.

---

## Limits

- Sample is `main` lineage, not every remote branch tip.
- “Mixed concerns” and “fix-ish” are path/subject heuristics.
- Does not re-litigate every historical mega-commit body (see outside-observer exports).
- July comparisons use a **partial month** (through 2026-07-26).
- First `./dev tier0` attempt in the recovery session failed on **arch mismatch** (arm64 test bundle vs x86_64 loader); clean `arch -arm64` run executed **199** selected tests with **0 failures**, plus `swift run HelloBlazeDB` success — environment caveat, not a product regression signal. Contributor tooling should eventually surface this clearly (see practice item 6).
