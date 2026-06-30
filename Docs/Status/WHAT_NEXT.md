# What's Next for BlazeDB

**Date:** 2026-06-30  
**Status:** Production-ready core; adoption and platform work ongoing

> **Prioritized task list:** [`WORK_REMAINING.md`](WORK_REMAINING.md) — sprints, checkboxes, and issue filing template.

---

## Current State

BlazeDB has crossed from "ambitious personal system" to something other engineers can rationally choose.

**What we achieved:**
- Performance claims → measured (benchmarks)
- Safety model → explicit (SAFETY_MODEL.md)
- First-run experience → boring (HelloBlazeDB works)
- Development pain → acknowledged (DEVELOPMENT_PERFORMANCE.md)
- Adoption signals → present (badges, CONTRIBUTING, CI)

---

## What Gets You from "Good" to "Respected"

**Do these three things, in this order:**

### 1. Run it in one of your own apps
- AshPile, GitBlaze, whatever
- Let it live for weeks
- Fix only what reality breaks

**Goal:** Real-world validation, not theoretical perfection.

---

### 2. Write one sober essay

**Title suggestion:**
"Why BlazeDB exists (and when you should not use it)"

**Key points:**
- What BlazeDB is designed for
- What it explicitly refuses to be
- When to use alternatives
- Why restraint matters more than ambition

**Goal:** Engineers trust restraint more than ambition.

---

### 3. Get one external user

One GitHub issue from someone who isn't you is worth more than ten features.

**Goal:** External validation proves adoptability.

---

## What NOT to Do Next

**Do NOT:**
- Add distributed anything
- Add background threads "for performance"
- Chase micro-optimizations
- Rework the docs again
- Generalize the model

**Why:** That's how solid systems die.

BlazeDB is good because it says no.

---

## Known Issues to Address

**Dump signature / legacy hash on restore:**
- Cross-version restore may require explicit `allowLegacyHashMismatch` for older dumps.
- CLI surfaces signature failures when the wrong password is used vs true tampering.
- Track remediation in [`WORK_REMAINING.md`](WORK_REMAINING.md) (R-07) — fix cleanly or document as permanent policy in `KNOWN_ISSUES.md`.

---

## Final Note

This is no longer "AI-generated chaos".

This is a coherent, opinionated system with:
- Boundaries
- Guarantees
- Receipts

**Now the move is simple and boring:**
Use it, let others use it, and only change what reality forces you to change.

That's how projects earn respect.
