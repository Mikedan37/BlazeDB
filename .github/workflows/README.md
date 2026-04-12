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

Jobs (see `nightly.yml` for ids): macOS Tier2 strict, clean-checkout verification, README quickstart, Tier0 ThreadSanitizer; Linux Tier1 and Tier2 **core**. Heavy/extended Tier3 companions run in weekly `deep-validation.yml`, not nightly.

Nightly confidence runs root-owned targets only and avoids depending on `BlazeDBExtraTests`.
This split keeps nightly rerunnable by concern and avoids bundling Tier2/verify/docs into one giant macOS job.
