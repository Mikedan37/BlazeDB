# Contributing to BlazeDB

**Thank you for considering contributing to BlazeDB!**

This guide explains how to add tests, what will be accepted, and what will be rejected.

---

## Test Tiers

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

### Tier 1: Core Contracts (`BlazeDB_Tier1`)

**Location:** `BlazeDBTests/Tier1Core/`

**What goes here:**
- Deeper correctness contracts (persistence/security/features)
- Non-trivial behavior that should remain stable release-to-release

### Tier 2: Integration/Recovery (`BlazeDB_Tier2`)

**Location:** `BlazeDBTests/Tier2Integration/`

**What goes here:**
- Integration, recovery, cross-feature interactions
- Longer-running scenarios

### Tier 3: Heavy/Destructive (`BlazeDB_Tier3_Heavy`, `BlazeDB_Tier3_Destructive`)

**Location:** `BlazeDBTests/Tier3Heavy/`, `BlazeDBTests/Tier3Destructive/`

**What goes here:**
- Stress/fuzz/performance and destructive fault-injection
- Manual/explicit lanes, not normal PR gate

---

## Adding New Tests

### Step 1: Determine Tier

**Ask yourself:**
- Does this test validate fast deterministic gate behavior? → Tier 0
- Does this test validate deeper core contracts? → Tier 1
- Does this test validate integration/recovery scenarios? → Tier 2
- Does this test belong to heavy/destructive/manual lanes? → Tier 3

**When in doubt, choose Tier 1.**

### Step 2: Write Test

**For Tier 0 tests:**
- Use only public APIs
- Test end-to-end behavior
- No access to internals
- Must always pass and stay fast

**For Tier 1 tests:**
- May test edge cases
- Should pass in deep CI lanes
- Can use public APIs freely

**For Tier 2 tests:**
- Focus on integration/recovery and longer scenarios
- Keep deterministic where possible

**For Tier 3 tests:**
- Add Tier 3 header comment
- Document why it's Tier 3
- May fail without blocking

### Step 3: Add to Package.swift

Tier targets are already declared in `Package.swift`.

Place test files under the correct `BlazeDBTests/Tier*` path and keep naming aligned with:
- `BlazeDB_Tier0`
- `BlazeDB_Tier1`
- `BlazeDB_Tier2`
- `BlazeDB_Tier3_Heavy`
- `BlazeDB_Tier3_Destructive`

---

## What Will Be Accepted

### Code Changes

- ✅ Bug fixes
- ✅ Performance improvements (with benchmarks)
- ✅ API improvements (with migration path)
- ✅ Documentation improvements
- ✅ Test additions

### Test Additions

- ✅ Tests for new features
- ✅ Tests for bug fixes
- ✅ Tests for edge cases
- ✅ Performance benchmarks

---

## What Will Be Rejected

### Code Changes

- ❌ Changes to frozen core files (PageStore, WAL, encoding)
- ❌ Breaking API changes without migration path
- ❌ Changes that weaken safety guarantees
- ❌ Changes that add `fatalError` to production code
- ❌ Changes that add `Task.detached` to core

### Test Additions

- ❌ Tests that require modifying frozen core
- ❌ Tests that weaken assertions
- ❌ Tests that use deprecated APIs (unless Tier 3)
- ❌ Tests that access internals (unless Tier 3)

---

## Development Workflow

### 1. Make Changes

```bash
# Make your changes
# ...

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

## Questions?

- Check `Docs/Testing/CI_AND_TEST_TIERS.md` for authoritative CI and tier mapping
- Check `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md` for branch/PR workflow and style expectations
- Check `Docs/Guarantees/SAFETY_MODEL.md` for safety guarantees
- Check `Docs/PHASE_1_FREEZE.md` for frozen core details

---

## Thank You

Contributions make BlazeDB better. Thank you for taking the time to contribute!
