# Workflow And Style Guide

This guide defines the expected day-to-day development workflow for BlazeDB.

Use it to keep `main` stable, avoid CI drift, and keep PRs reviewable.

## Core Model

- `main` is stable and releasable.
- Branches are isolated experiments.
- Pull requests are the only path to `main`.
- CI is the safety gate, not the debugging environment.

## Branching Style

Use one concern per branch.

Recommended prefixes:

- `feature/<name>` for product/engine changes
- `test/<name>` for test stabilization/refactors
- `ci/<name>` for workflow/pipeline changes
- `docs/<name>` for documentation-only updates

Examples:

- `feature/page-cache-lru`
- `test/fix-encryption-roundtrip`
- `ci/linux-tier0-gate`
- `docs/ci-inventory-refresh`

## One Branch, One Idea

Good:

- branch contains one coherent change set
- commits are explainable and scoped

Bad:

- branch mixes feature logic + CI edits + broad test rewrites
- branch accumulates unrelated changes from multiple sessions

## Standard Flow

```bash
git switch main
git pull --ff-only
git switch -c <prefix>/<topic>
```

Then iterate locally:

```bash
./Scripts/preflight.sh
```

Preflight must pass before opening a PR.

## Local vs CI Responsibilities

- Local preflight (`Scripts/preflight.sh`):
  - `swift build`
  - Tier 0 gate (`Scripts/run-tier0.sh`)
- PR CI (`.github/workflows/ci.yml`):
  - build + Tier 0 gate
- Deep validation (`core-tests.yml`):
  - Tier 0 + Tier 1 (nightly/manual)

## Commit Style

- Keep commits small and intention-revealing.
- Prefer subject format:
  - `fix(...)`
  - `ci(...)`
  - `test(...)`
  - `docs(...)`
- Do not bundle unrelated file changes into one commit.

## PR Style

A PR should state:

- what changed
- why it changed
- what was intentionally out of scope
- how it was validated

If the PR is docs-only, say so explicitly.

## Containment Rule

Before commit:

```bash
git status
git diff
```

If unexpected files appear:

- stop
- inspect
- restore or stash unrelated changes
- continue only with intentional files

## CI Drift Rule

Any workflow behavior change must update:

- `Docs/Testing/CI_AND_TEST_TIERS.md`
- `.github/workflows/README.md`
- `CONTRIBUTING.md` (if contributor behavior changes)
