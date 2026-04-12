# Contributing to BlazeDB

**Thank you for considering contributing to BlazeDB!**

This guide explains how to add tests, what will be accepted, and what will be rejected.

## CI gate (GitHub Actions)

The default branch workflow (`.github/workflows/ci.yml`) runs on every push/PR **when hosted CI is available**: a **macOS 15** blocking job (core + CLI + Tier0 + `BlazeDB_Tier1`) and a **Linux 6.2** blocking job (core + Tier0). **`nightly.yml`** and **`deep-validation.yml`** add scheduled coverage; weekly deep is **delta-only** (does not repeat PR/nightly tiers—see [CI and test tiers](Docs/Testing/CI_AND_TEST_TIERS.md)). `verify-clean-checkout.sh` and `verify-readme-quickstart.sh` are intentionally **not** in the blocking PR gate. Legacy **`v*` tag buildability** is **not** part of that automatic gate; it runs only from the manual workflow [`.github/workflows/tag-probe.yml`](.github/workflows/tag-probe.yml). Checkouts use full git history (`fetch-depth: 0`). **Forks and billing limits** can prevent workflows from running; in that case use the same commands locally (see [Hosted CI status](Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md#hosted-ci-status)). The gate is **not** every test target or every file under `BlazeDBTests/` (some files are excluded per tier in `Package.swift`). Authoritative detail: [CI and test tiers](Docs/Testing/CI_AND_TEST_TIERS.md).

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

## Development Workflow

### 1. Make Changes

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

## Before Opening A PR

Run:

```bash
./Scripts/preflight.sh
```

If this fails locally, fix it before pushing.

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

## Change Discipline

### Source of truth

`Docs/SYSTEM_MAP.md` is the canonical engineering map for what exists, what state it is in, and where it lives. Read it before making major changes.

### When to update the system map

Any PR that materially changes feature surface, support status, platform support, or module boundaries must update `Docs/SYSTEM_MAP.md` in the same PR. See that file for what counts as "material."

### Branch and scope rules

- One branch per coherent unit of work. Do not mix unrelated changes.
- Docs and code must land together — do not ship a feature in one PR and document it in another.
- Test lane or target boundary changes must be documented in `Docs/Testing/CI_AND_TEST_TIERS.md`.
- Prefer narrow, surgical edits. Do not rewrite unrelated doc sections.

### Feature surface rules

- Do not advertise internal or deferred features as shipped in `README.md` or other public-facing docs.
- If a feature is in source but not in stable public onboarding, mark it accordingly in the system map.
- Tests are evidence of implementation, not automatic evidence of public product maturity.

### Reconciliation

- Rebase and reconcile `SYSTEM_MAP.md` carefully if multiple PRs touch it.
- If `CI_AND_TEST_TIERS.md` conflicts, the file plus `.github/workflows/*.yml` are authoritative.

---

## Questions?

- Check `Docs/SYSTEM_MAP.md` for the canonical feature inventory and status map
- Check `Docs/Testing/CI_AND_TEST_TIERS.md` for authoritative CI and tier mapping
- Check `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md` for branch/PR workflow and style expectations
- Check `Docs/Guarantees/SAFETY_MODEL.md` for safety guarantees
- Check `Docs/Compliance/PHASE_1_FREEZE.md` for frozen core details

---

## Thank You

Contributions make BlazeDB better. Thank you for taking the time to contribute!
