# Workflow and style guide

**PR policy in one place:** [CONTRIBUTING.md — PR expectations](../../CONTRIBUTING.md#pr-expectations). This file is **branch naming**, **local habits**, and **style**—not a second copy of CI rules.

## Quick workflow

1. `git switch main && git pull --ff-only`
2. `git switch -c <feature|test|ci|docs>/<name>`
3. Implement one scoped change
4. `./Scripts/preflight.sh`
5. `git status && git diff` (no unrelated changes)
6. Commit, push, open PR
7. Wait for CI to pass
8. Squash merge

## Containment Rule

Before you commit, make sure only intentional changes are included.
Run `git status` and `git diff` to double-check.

## 1) Rule Of `main`

`main` is always releasable.
Please keep experimental work on a branch, not directly on `main`.

## 2) Branch Rule

One branch = one concern.

Use:

- `feature/`
- `test/`
- `ci/`
- `docs/`

## Commit Scope Rule

Try to keep each commit focused on one subsystem.

Examples:

- `feature/wal-batching`
- `test/encryption-roundtrip`
- `ci/pipeline-simplification`

## 3) Preflight Rule

Before opening a PR, run:

```bash
./Scripts/preflight.sh
```

If it fails, fix it locally before pushing.

## 4) CI (do not duplicate here)

- **Local:** `./Scripts/preflight.sh` (build + Tier0) before you push
- **On GitHub:** [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) — **both** the macOS and Linux jobs are part of the default PR gate when Actions runs
- **Authoritative narrative:** [`Docs/Testing/CI_AND_TEST_TIERS.md`](../Testing/CI_AND_TEST_TIERS.md) (if another doc disagrees, trust that file + the workflows)
