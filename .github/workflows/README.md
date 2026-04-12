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

## `nightly.yml`

Daily (`schedule`) + manual (`workflow_dispatch`) nightly confidence workflow with **failure-domain isolation**.

Jobs:

- `macOS 15 — Tier1 depth`
- `macOS 15 — Tier1`
- `macOS 15 — Tier2 strict`
- `macOS 15 — clean-checkout verification`
- `macOS 15 — README quickstart verification`
- `macOS 15 — Tier0 ThreadSanitizer`
- `Linux (Swift 6.2) — Tier0 + Tier1`

The nightly workflow runs root-owned targets only and avoids depending on `BlazeDBExtraTests`.
This split keeps nightly rerunnable by concern and avoids bundling Tier2/verify/docs into one giant macOS job.
