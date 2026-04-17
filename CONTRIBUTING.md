# Contributing to BlazeDB

**Thank you for considering contributing to BlazeDB!**

This guide explains how to add tests, what will be accepted, and what will be rejected.

## PR expectations

Keep PRs **narrow** and **self-contained**.

For **most** PRs:

- Use **one branch** for **one concern**
- Run **`./Scripts/preflight.sh`**
- In the PR description, **list the exact validation commands** you ran (not just “tests pass”)
- **Update docs in the same PR** if behavior or public usage changed
- Prefer **squash merge** when merging to `main`

**Also update these only when your change is relevant:**

| File | When |
|------|------|
| [`Docs/SYSTEM_MAP.md`](Docs/SYSTEM_MAP.md) | Material changes to architecture, platforms, modules, or **public** feature surface (see that file for what counts as material) |
| [`Docs/Testing/CI_AND_TEST_TIERS.md`](Docs/Testing/CI_AND_TEST_TIERS.md) | Changes to **test lanes**, **tier** meaning, or **CI** job behavior |

**If two docs disagree about CI** (blocking jobs, tier scope, workflows), treat **[`Docs/Testing/CI_AND_TEST_TIERS.md`](Docs/Testing/CI_AND_TEST_TIERS.md)** plus **`.github/workflows/*.yml`** as the detailed source of truth—not this paragraph alone.

Forks, billing limits, and hosted CI availability can prevent Actions from running; use the same commands locally if needed ([Hosted CI status](Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md#hosted-ci-status)).

---

## CI at a glance

The PR workflow is [`.github/workflows/ci.yml`](.github/workflows/ci.yml). Scheduled and weekly workflows add coverage on top; they are documented in [CI and test tiers](Docs/Testing/CI_AND_TEST_TIERS.md). Scripts such as `verify-clean-checkout.sh` and `verify-readme-quickstart.sh` are **not** part of the blocking PR gate unless that doc explicitly says otherwise. **`v*`** tag buildability uses the manual [tag-probe workflow](.github/workflows/tag-probe.yml).

---

## Test Tiers

Also see [Tests directory layout (BlazeDBTests vs Tests/)](Docs/Testing/TESTS_DIRECTORY.md).

BlazeDB uses a tiered test model:

### Tier 0: PR Gate (`BlazeDB_Tier0`)

**Location:** `BlazeDBTests/Tier0Core/`

**What goes here:**
- Fast deterministic correctness checks
- Tests that must pass for PR merge
- Public API and critical behavior coverage

**Run (preferred):**
```bash
./Scripts/preflight.sh
```

**Run (direct):**
```bash
swift test --filter BlazeDB_Tier0
```

### Tier 1: Canonical confidence target (`BlazeDB_Tier1`)

**Canonical Tier1 gate — `BlazeDB_Tier1`:** `BlazeDBTests/Tier1Core/` — deterministic correctness; no `measure()`, no timing-dependent sleeps, no benchmark-shaped workloads.

`BlazeDB_Tier1Extended` and `BlazeDB_Tier1Perf` target names were retired; their suites now run under Tier2/Tier3 ownership via **transitional companion targets** (`BlazeDB_Tier2_Extended`, `BlazeDB_Tier3_Heavy_Perf`) pending PR4 normalization.

**What goes in the fast lane:**
- Core contracts that must stay green on every PR (persistence/security/features) without heavy timing or perf noise

**Run (preferred Tier 1 gate):**
```bash
./Scripts/run-tier1.sh
```

**Run depth locally (extended + perf):**
```bash
./Scripts/run-tier2-tier3-companions.sh
```

### Tier 2: Integration/Recovery (`BlazeDB_Tier2`, `BlazeDB_Tier2_Extended`)

**Location:** `BlazeDBTests/Tier2Integration/`
`BlazeDB_Tier2_Extended` is transitional (PR3 bridge), not an additional canonical tier.

**What goes here:**
- Integration, recovery, cross-feature interactions
- Longer-running scenarios

### Tier 3: Heavy/Destructive (`BlazeDB_Tier3_Heavy`, `BlazeDB_Tier3_Heavy_Perf`, `BlazeDB_Tier3_Destructive`)

**Location:** `BlazeDBTests/Tier3Heavy/`, `BlazeDBTests/Tier3Destructive/`
`BlazeDB_Tier3_Heavy_Perf` is transitional (PR3 bridge), not an additional canonical tier.

**What goes here:**
- Stress/fuzz/performance and destructive fault-injection
- Manual/explicit lanes, not normal PR gate

---

## Adding New Tests

### Step 1: Determine Tier

**Ask yourself:**
- Does this test validate fast deterministic gate behavior? → Tier 0
- Does this test validate deeper core contracts without measure/sleep/stress? → Tier 1 (`BlazeDB_Tier1`)
- Does it use `measure()`, fixed sleeps, sync integration, or large-N stress? → Tier2 or Tier3 Heavy (depending on test intent)
- Does this test validate integration/recovery scenarios? → Tier 2
- Does this test belong to heavy/destructive/manual lanes? → Tier 3

**When in doubt, start in Tier 1; move to Tier2/Tier3 Heavy only when required by test intent.**

### Step 2: Write Test

**For Tier 0 tests:**
- Use only public APIs
- Test end-to-end behavior
- No access to internals
- Must always pass and stay fast

**For Tier 1 tests:**
- Canonical lane (`BlazeDB_Tier1`): default PR gate; avoid `measure()`, fixed sleeps, and stress-scale workloads.
- Deeper integration/recovery belongs in `BlazeDB_Tier2` / `BlazeDB_Tier2_Extended`; perf/stress belongs in `BlazeDB_Tier3_Heavy` / `BlazeDB_Tier3_Heavy_Perf`.
- May test edge cases; use public APIs freely unless you intentionally need internals.

**For Tier 2 tests:**
- Focus on integration/recovery and longer scenarios
- Keep deterministic where possible

**For Tier 3 tests:**
- Add Tier 3 header comment
- Document why it's Tier 3
- May fail without blocking

### Step 3: Wire the test target

- **Tier 0 / Tier 1 (`BlazeDB_Tier1`) / Tier 2 / Tier 3 / `BlazeDB_Staging`:** declared in root `Package.swift`.
- **`DistributedSecuritySPMTests`:** remains declared in `BlazeDBExtraTests/Package.swift` (nested package).

Place test files under the correct `BlazeDBTests/...` paths; target names remain:
- `BlazeDB_Tier0`, `BlazeDB_Tier1`, `BlazeDB_Tier2`, `BlazeDB_Tier2_Extended`, `BlazeDB_Tier3_Heavy`, `BlazeDB_Tier3_Heavy_Perf`, `BlazeDB_Tier3_Destructive` (root package)
- `DistributedSecuritySPMTests` (extra package)

---

## What Will Be Accepted

### Code Changes

- Bug fixes
- Performance improvements (with benchmarks)
- API improvements (with migration path)
- Documentation improvements
- Test additions

### Test Additions

- Tests for new features
- Tests for bug fixes
- Tests for edge cases
- Performance benchmarks

---

## What Will Be Rejected

### Code Changes

- Changes to frozen core files (PageStore, WAL, encoding)
- Breaking API changes without migration path
- Changes that weaken safety guarantees
- Changes that add `fatalError` to production code
- Changes that add `Task.detached` to core

### Test Additions

- Tests that require modifying frozen core
- Tests that weaken assertions
- Tests that use deprecated APIs (unless Tier 3)
- Tests that access internals (unless Tier 3)

---

## Development workflow

Normal PRs: follow **[PR expectations](#pr-expectations)** (`./Scripts/preflight.sh` + listed commands in the PR).

### 1. Make changes

```bash
# Make your changes
# ...

# Run OSS readiness local checks (recommended before PR)
./Scripts/oss-readiness-local.sh

# Run clean-checkout verification (recommended before release)
./Scripts/verify-clean-checkout.sh

# Verify README quickstart behavior and runtime budget
./Scripts/verify-readme-quickstart.sh

# Run local preflight (required)
./Scripts/preflight.sh

# Run deeper lanes (optional)
./Scripts/run-tier1.sh
./Scripts/run-tier2.sh
```

### 2. Verify Frozen Core

```bash
# Check that frozen core wasn't modified
./Scripts/check-freeze.sh HEAD^
```

### 3. Commit

```bash
git add -A
git commit -m "Description of changes"
```

---

## Release Tagging Policy

- Use semantic tags in `vX.Y.Z` format only.
- Do not publish non-`v` release tags; release automation triggers on `v*`.

---

## Code Style

### Swift Style

- Follow Swift API Design Guidelines
- Use explicit types when clarity is needed
- Prefer `guard` over `if let` for early returns
- Document public APIs

### Error Handling

- Use `BlazeDBError` for runtime errors
- Use `preconditionFailure` for invariant violations (debug only)
- Never use `fatalError` in production code

### Concurrency

- Prefer structured concurrency (`Task { }`)
- Avoid `Task.detached` in core
- Use `@Sendable` only where Swift requires it
- Document `@unchecked Sendable` usage

---

## Documentation

### Adding Documentation

- Update relevant docs in `Docs/`
- Add examples to `Examples/`
- Update README if adding features

### Documentation Style

- Be explicit, not clever
- Show examples, not just descriptions
- Explain "why" not just "how"

---

## Change discipline

See **[PR expectations](#pr-expectations)** for branch scope, docs-with-code, and when to touch `SYSTEM_MAP` / `CI_AND_TEST_TIERS`.

### Source of truth

[`Docs/SYSTEM_MAP.md`](Docs/SYSTEM_MAP.md) is the engineering map for what exists, where it lives, and support status. Read it before large or cross-cutting changes.

### Feature surface

- Do not advertise internal or deferred features as shipped in `README.md` or other public onboarding.
- If something exists in source but is not stable for end users, say so in the system map.
- Tests prove behavior in CI; they are not by themselves proof of “product ready.”

### Reconciliation

If multiple PRs touch `SYSTEM_MAP.md`, reconcile carefully. CI/tier conflicts: **`CI_AND_TEST_TIERS.md`** + **workflows** win.

---

## Questions?

- Start with **[PR expectations](#pr-expectations)** above
- Check `Docs/SYSTEM_MAP.md` for the canonical feature inventory and status map
- Check `Docs/Testing/CI_AND_TEST_TIERS.md` for CI jobs, tiers, and cadence
- Check `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md` for branch naming and local workflow
- Check `Docs/Guarantees/SAFETY_MODEL.md` for safety guarantees
- Check `Docs/Compliance/PHASE_1_FREEZE.md` for frozen core details

---

## Thank You

Contributions make BlazeDB better. Thank you for taking the time to contribute!
