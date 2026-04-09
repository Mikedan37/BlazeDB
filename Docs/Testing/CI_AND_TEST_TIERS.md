# CI And Test Tiers

This file is the single source of truth for BlazeDB CI lanes and test-tier intent.

If this file conflicts with other docs, treat this file and `.github/workflows/*.yml` as authoritative.

For branch discipline and PR hygiene, see `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md`.

## CI Lane Snapshot

Use this table for day-to-day expectations.

| Lane | Goal | Trigger | Blocking | Current workflow(s) |
| ---- | ---- | ------- | -------- | ------------------- |
| PR fast gate | Catch obvious breakage quickly | `pull_request`, `push` | Yes | `ci.yml` |
| Tier1 depth | Broader Tier1 confidence | Weekly + manual | No | `tier1-depth.yml` |
| Release validation | Validate tagged releases | `v*` tag + manual | Release-only | `release.yml` |
| Tag probe | Check older tags still build | Manual | No | `tag-probe.yml` |

### Rollout status

- Completed:
  - PR gate caching and verify-step trim in `ci.yml`
  - Tier1 PR gate reduction (`BlazeDB_Tier1Fast`) + broader deterministic lane (`BlazeDB_Tier1FastFull`)
- In rollout:
  - nightly confidence lane (`nightly.yml`)
  - deep soak lane (`deep-validation.yml`)

## Workflow Inventory

- `.github/workflows/ci.yml`
- Triggers: push and pull_request on `main`, `develop`
- All jobs use **`actions/checkout` with `fetch-depth: 0`** so tags and worktree scripts match a full clone.
- **Primary check (blocking):** `macOS 15 — build, CLI, tests`
- Runner: `macos-15`; **does not** use `swift-actions/setup-swift` — tests run with **Xcode’s** `swift` so XCTest/`XCTestCore` resolves (OSS Swift on macOS does not).
- `actions/cache` on `.build` (keyed by `runner.os`, `Package.swift`, `Package.resolved`)
- `swift build --target BlazeDBCore`, CLI targets (`BlazeDoctor`, `BlazeDump`, `BlazeInfo`)
- `BLAZEDB_TEST_SCOPE=tier0 swift test --filter BlazeDB_Tier0`, then `swift test --skip-build --filter BlazeDB_Tier1Fast`
- `verify-clean-checkout.sh` and `verify-readme-quickstart.sh` are **not** part of the blocking PR lane (they remain in-repo and move to deeper lanes)
- **Secondary (blocking):** `Linux (Swift 6.2) — core + Tier 0`
- Runner: `ubuntu-22.04`
- `actions/cache` on `.build` (same key shape), then `swift build` + CLI targets + `swift test --filter BlazeDB_Tier0`

- `.github/workflows/tag-probe.yml`
- Trigger: **manual** (`workflow_dispatch`) only
- Runs `./Scripts/check-release-tag-builds.sh` (last three `v*` tags) on Ubuntu; use when you care about old tag buildability, not on every push

- `.github/workflows/tier1-depth.yml`
- Trigger: **weekly schedule** and **manual** (`workflow_dispatch`)
- Runs **`BlazeDB_Tier1Extended`** and **`BlazeDB_Tier1Perf`** only (not `BlazeDB_Tier1Fast`; that is the PR-critical lane). This remains available during nightly rollout.

- `.github/workflows/nightly.yml`
- Trigger: **daily schedule** and **manual** (`workflow_dispatch`)
- Runs medium-confidence coverage:
  - `BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf`
  - `BlazeDB_Tier1FastFull` (from `BlazeDBExtraTests`)
  - Tier2 integration/recovery via `./Scripts/run-tier2.sh --strict` (blocking in nightly lane)
  - `verify-clean-checkout.sh` and `verify-readme-quickstart.sh`
  - ThreadSanitizer on `BlazeDB_Tier0`
  - Linux depth run: `BlazeDB_Tier0` + `BlazeDB_Tier1Fast`
- **Operational policy:** nightly failures are triaged within 24–48 hours.

### Nightly stability trade-offs (documented)

- **Associated object storage model:**
  - Apple platforms use Objective-C associated objects (standard extension-storage pattern).
  - Linux uses the `AssociatedObjects` dictionary fallback (no Objective-C runtime available).
  - To remove TSan races from concurrent first access, manager creation now uses an atomic `getOrCreate(...)` path guarded by `NSLock`.
  - Trade-off: first-time associated-object initialization is globally serialized per process; expected contention is low and chosen for correctness.

- **Observer-removal test determinism:**
  - `ChangeObservationTests.testObserverRemoval` uses explicit expectations and synchronized state checks instead of sleep-only timing.
  - Trade-off: test logic is slightly more verbose, but avoids scheduler-dependent flakes in nightly lanes.

- **Cross-platform default-path assertions:**
  - `ConvenienceAPITests.testDefaultDatabaseURL` validates against `defaultDatabaseDirectory` semantics instead of hardcoded `"Application Support/BlazeDB"` text.
  - Trade-off: less strict about path string formatting, more correct across Linux/macOS path conventions.

- `.github/workflows/deep-validation.yml`
- Trigger: **weekly schedule** and **manual** (`workflow_dispatch`)
- Runs deep/manual soak coverage:
  - Full Tier1 (`BlazeDB_Tier1Fast` + `BlazeDB_Tier1FastFull` + `BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf`)
  - Tier2 via `./Scripts/run-tier2.sh`
  - Tier3 heavy (`BlazeDB_Tier3_Heavy` with `RUN_HEAVY_STRESS=1`) and Tier3 destructive (`./Scripts/run-tier3.sh`)
  - ThreadSanitizer on `BlazeDB_Tier0` and `BlazeDB_Tier1Fast`
  - Linux extended lane (`BlazeDB_Tier0` + `BlazeDB_Tier1Fast` + `BlazeDB_Tier1Extended`)

- `.github/workflows/release.yml`
- Trigger: tag push `v*`
- Behavior:
- Run `BlazeDB_Tier0`, `BlazeDB_Tier1Fast`, `BlazeDB_Tier1Extended`, `BlazeDB_Tier1Perf`, `BlazeDB_Tier3_Heavy`
- Build release artifact
- Generate release notes
- Publish GitHub release
- Blocking: release-only

## Tier Purposes

- `BlazeDB_Tier0`
- Fast deterministic correctness gate for PRs and local preflight.
- Must stay bounded and stable.

- `BlazeDB_Tier1Fast`
- Default PR correctness gate from `BlazeDBTests/Tier1Core/`.
- Sources: `BlazeDBTests/Tier1Core/` in root package.
- Only three files remain excluded (see `Package.swift` excludes below).

- `BlazeDB_Tier1FastFull`
- Broader deterministic Tier1 lane from the same `Tier1Core` sources, defined under `BlazeDBExtraTests/Package.swift` for deeper/manual lanes.

- `BlazeDB_Tier1Extended`
- Integration, distributed sync, sleep-dependent timing, and large-N stress that should stay in CI but not in the default fast loop.
- Sources: `BlazeDBTests/Tier1Extended/` (includes most of `Sync/`). Shared helpers via symlink to `Tier1Core/Helpers`.
- **`Package.swift` excludes** a few sync harnesses that depend on distributed-only types (`InMemoryRelay`, cross-app sync, topology) until those are wired against a non–core-only build.

- `BlazeDB_Tier1Perf`
- XCTest `measure()` and benchmark-shaped suites.
- Sources: `BlazeDBTests/Tier1Perf/`. Shared helpers via symlink to `Tier1Core/Helpers`.

- `BlazeDB_Tier2`
- Integration and recovery scenarios.
- **Built from nested package** `BlazeDBExtraTests/` (not part of root `swift test` graph).
- Non-blocking by default in script form; enforced in nightly via strict mode.

- `BlazeDB_Tier3_Heavy` / `BlazeDB_Tier3_Destructive`
- Stress, fuzz, and destructive/fault-injection lanes.
- Declared under `BlazeDBExtraTests/Package.swift`; run via `cd BlazeDBExtraTests && swift test …`.
- Manual/explicit use only; never default PR gate.

## Reporting vocabulary

Use precise language so status and dashboards do not blur the PR gate with deeper lanes.

| Say this | Meaning |
| -------- | ------- |
| **Tier1 PR gate** / **T1 fast** | `BlazeDB_Tier1Fast` only—the default blocking Tier1 lane on PRs. |
| **Tier1 depth** | `BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf` (weekly/manual `tier1-depth.yml`, or `./Scripts/run-tier1-depth.sh`). Does *not* by itself imply `BlazeDB_Tier1Fast` ran. |
| **Nightly confidence lane** | `nightly.yml`: Tier1 depth + `BlazeDB_Tier1FastFull` + strict Tier2 + verify scripts + Tier0 TSan + Linux Tier0/Tier1Fast. |
| **Deep validation lane** | `deep-validation.yml`: full Tier1 + Tier2 + Tier3 heavy/destructive + Tier0/Tier1Fast TSan + Linux extended lane. |
| **Full Tier1** / **Tier1 all lanes** | `BlazeDB_Tier1Fast` + `BlazeDB_Tier1FastFull` + `BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf` (broader deterministic coverage via `BlazeDBExtraTests`). |

Inventory/bootstrap code may still bucket all three SwiftPM modules under a single **`T1`** label for file-level manifests; that is a storage convenience. **Human-facing** summaries (CI names, release notes, team chat) should use the table above, not a vague “T1 passed.”

### Shared helpers (symlinks)

`Tier1Extended/Helpers` and `Tier1Perf/Helpers` symlink to `Tier1Core/Helpers` so helper sources stay single-sourced. SwiftPM generally handles this; if a platform or archive step misbehaves (often Linux or packaging), replace with a small **shared test-support target** and drop the symlinks—see `Package.swift` when that happens.

### `BlazeDB_Tier1Fast` excludes

Three files remain **excluded** from `BlazeDB_Tier1Fast` in `Package.swift`:

| File | Root cause | Issue | Fix |
| ---- | ---------- | ----- | --- |
| `Security/SecureConnectionTests.swift` | Wrong target ownership — tests `SecureConnection` (in `Distributed/`) + `import Network` (Apple-only). 3 of 4 tests are pure crypto. | [#73](https://github.com/Mikedan37/BlazeDB/issues/73) | Split: transport test → distributed lane, crypto tests → Tier1Core |
| `Security/KeyManagerTests.swift` | 2 of 7 tests call deleted `KeyManager.generateSalt(for:)`. Other 5 compile fine. | [#74](https://github.com/Mikedan37/BlazeDB/issues/74) | Replace `generateSalt` with manual salt, remove exclusion |
| `Concurrency/BlazeDBAsyncTests.swift` | Async APIs gated behind `#if !BLAZEDB_LINUX_CORE`; test has no matching guard. APIs are NOT removed. | [#75](https://github.com/Mikedan37/BlazeDB/issues/75) | Add `#if !BLAZEDB_LINUX_CORE` to test file, remove exclusion |

All other `Tier1Core` directories and files (Aggregation, API, Query, Integration, Features, Migration, etc.) are now included in the PR gate.

## Local Entry Points

- `./Scripts/preflight.sh`
- Runs exactly the local gate expected before push:
- `swift build`
- `./Scripts/run-tier0.sh`

- Tier runners:
- `./Scripts/run-tier0.sh`
- `./Scripts/run-tier1.sh` (Tier 0 + `BlazeDB_Tier1Fast` + execution coverage)
- `./Scripts/run-tier1-depth.sh` (`BlazeDB_Tier1Extended` + `BlazeDB_Tier1Perf`)
- `./Scripts/run-tier2.sh`
- `./Scripts/run-tier3.sh`

## Nightly Triage Policy

- Nightly failures are treated as real work and triaged within **24–48 hours**.
- If nightly remains red beyond that window, either:
  - fix the failing lane, or
  - temporarily quarantine the failing job with an explicit issue link and owner.

## Before Merge Checklist

- Confirm working tree is intentional (`git status`, `git diff`).
- Run `./Scripts/preflight.sh`.
- Ensure required checks are green on PR (primary: `macOS 15 — build, CLI, tests`).
- Do not mix workflow behavior changes with docs-only cleanup in the same PR unless explicitly scoped.

## Maintenance Policy

- Any workflow trigger/job/command change must update this file in the same PR.
- Any test-tier target rename must update:
- this file
- `CONTRIBUTING.md`
- tier runner scripts under `Scripts/`
