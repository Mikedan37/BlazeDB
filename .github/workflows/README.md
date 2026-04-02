# GitHub Actions Workflows

Authoritative detail: `Docs/Testing/CI_AND_TEST_TIERS.md`.

## `ci.yml` — only automatic workflow for `main` / `develop`

Checkouts use **`fetch-depth: 0`**.

| Job | Blocking |
|-----|----------|
| `macOS 15 — build, CLI, tests, clean-checkout, quickstart` | yes |
| `Linux (Swift 6) — best-effort` | no (`continue-on-error`) |

**Deleted from the repo (must not return on `main`):** `oss-readiness-evidence.yml`, duplicate CI files. If GitHub still shows “OSS Readiness Evidence” or “Build & Test”, `main` has not picked up the latest workflow commits — merge and push.

## `tag-probe.yml`

Manual only: legacy `v*` tag release builds. Not run on push.

## `release.yml`

Tag `v*` releases.
