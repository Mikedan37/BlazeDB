# Contributing to BlazeDB

**Thank you for considering contributing to BlazeDB!**

This guide explains how to add tests, what will be accepted, and what will be rejected.

---

## Test Tiers

BlazeDB uses a three-tier test structure:

### Tier 1: Production Gate Tests (`BlazeDBCoreGateTests`)

**Location:** `BlazeDBTests/Gate/`

**What goes here:**
- Tests that validate core production safety guarantees
- Tests that MUST pass for any release
- Tests using only public APIs
- End-to-end behavior validation

**Examples:**
- Database lifecycle (open/close)
- Crash recovery
- Export/restore integrity
- Schema migrations

**Run:**
```bash
swift test --filter BlazeDBCoreGateTests
# or
./Scripts/test-gate.sh
```

### Tier 2: Core Tests (`BlazeDBCoreTests`)

**Location:** `BlazeDBTests/` (not in Gate or Legacy)

**What goes here:**
- Tests for important features
- Tests that should pass but aren't blocking
- Edge cases and stress tests

**Examples:**
- Query ergonomics
- Error messages
- Platform compatibility

### Tier 3: Legacy Tests (`BlazeDBLegacyTests`)

**Location:** `BlazeDBTests/Legacy/`

**What goes here:**
- Tests accessing internal APIs
- Tests using deprecated APIs
- Performance benchmarks (not correctness)

**Header required:**
```swift
// TIER 3 — Legacy / Internal / Non-blocking
// This test accesses internal APIs and may fail without blocking releases.
```

---

## Adding New Tests

### Step 1: Determine Tier

**Ask yourself:**
- Does this test validate production safety? → Tier 1
- Does this test validate an important feature? → Tier 2
- Does this test access internals? → Tier 3

**When in doubt, choose Tier 2.**

### Step 2: Write Test

**For Tier 1 tests:**
- Use only public APIs
- Test end-to-end behavior
- No access to internals
- Must always pass

**For Tier 2 tests:**
- May test edge cases
- Should pass but not blocking
- Can use public APIs freely

**For Tier 3 tests:**
- Add Tier 3 header comment
- Document why it's Tier 3
- May fail without blocking

### Step 3: Add to Package.swift

**If Tier 1:**
- Add to `BlazeDBCoreGateTests` target sources list

**If Tier 2:**
- Place in `BlazeDBTests/` (not Gate or Legacy)
- Will be included automatically

**If Tier 3:**
- Place in `BlazeDBTests/Legacy/`
- Will be included automatically

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

# Run Tier 1 tests (required)
./Scripts/test-gate.sh

# Run all tests (optional)
./Scripts/test-all.sh
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

- Check `Docs/Status/TEST_STABILIZATION_COMPLETE.md` for test structure
- Check `Docs/Guarantees/SAFETY_MODEL.md` for safety guarantees
- Check `Docs/PHASE_1_FREEZE.md` for frozen core details

---

## Thank You

Contributions make BlazeDB better. Thank you for taking the time to contribute!
