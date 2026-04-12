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
  - Tier1 canonical target naming cleanup (`BlazeDB_Tier1`) in active workflows/scripts/docs
  - Nightly confidence split into isolated failure-domain jobs in `nightly.yml`
- In rollout:
  - deep soak lane (`deep-validation.yml`)

## CI Philosophy: Tiered, Not Sequential

BlazeDB uses a tiered testing model where tiers represent signal class and runtime cost, **not** promotion order.

- Tiers are classification labels, not execution stages.
- Linux nightly lanes run as independent sibling jobs.
- There is no Linux Tier1 -> Tier2 -> Tier3 dependency chain.

This is intentional:

- Tier surfaces validate different behavior classes and do not consume each other's artifacts.
- Sequential staging would add wall-clock without adding correctness.
- Parallel sibling lanes maximize nightly signal by exposing failures across all surfaces in the same run.

Design tradeoff (intentional):

- Favor: broader signal per run + faster critical-path completion.
- Accept: higher runner concurrency consumption versus staged early-exit gating.

In short: nightly confidence optimizes for coverage visibility and time-to-signal, not strict tier promotion.

## Workflow Inventory

- `.github/workflows/ci.yml`
- Triggers: push and pull_request on `main`, `develop`
- All jobs use **`actions/checkout` with `fetch-depth: 0`** so tags and worktree scripts match a full clone.
- **Primary check (blocking):** `macOS 15 — build, CLI, tests`
- Runner: `macos-15`; **does not** use `swift-actions/setup-swift` — tests run with **Xcode’s** `swift` so XCTest/`XCTestCore` resolves (OSS Swift on macOS does not).
- `actions/cache` on `.build` (keyed by `runner.os`, `Package.swift`, `Package.resolved`)
- `swift build --target BlazeDBCore`, CLI targets (`BlazeDoctor`, `BlazeDump`, `BlazeInfo`)
- `BLAZEDB_TEST_SCOPE=tier0 swift test --filter BlazeDB_Tier0`, then `swift test --skip-build --filter BlazeDB_Tier1` (macOS PR). **Nightly:** on macOS, `nightly-macos-tier3-heavy` is **quarantined** (`continue-on-error: true`, non-blocking for the workflow); **Linux** adds split Tier1 / Tier2 / Tier3 jobs — see `nightly.yml`.
- `verify-clean-checkout.sh` and `verify-readme-quickstart.sh` are **not** part of the blocking PR lane (they remain in-repo and move to deeper lanes)
- **Secondary (blocking):** `Linux (Swift 6.2) — core + Tier 0`
- Runner: `ubuntu-22.04`
- `actions/cache` on `.build` (same key shape), then `swift build` + CLI targets + `swift test --filter BlazeDB_Tier0`

- `.github/workflows/tag-probe.yml`
- Trigger: **manual** (`workflow_dispatch`) only
- Runs `./Scripts/check-release-tag-builds.sh` (last three `v*` tags) on Ubuntu; use when you care about old tag buildability, not on every push

- `.github/workflows/tier1-depth.yml`
- Trigger: **weekly schedule** and **manual** (`workflow_dispatch`)
- Runs `BlazeDB_Tier2` + `BlazeDB_Tier2_Extended` and `BlazeDB_Tier3_Heavy` + `BlazeDB_Tier3_Heavy_Perf` (legacy workflow name retained pending PR4 cleanup).

- `.github/workflows/nightly.yml`
- Trigger: **daily schedule** and **manual** (`workflow_dispatch`)
- Job naming convention: **`<Platform> — <Tier> (<variant/policy when needed>)`**
- Runs medium-confidence coverage in **separate rerunnable jobs**:
  - `macOS 15 — Tier3 (heavy, non-blocking)`: root targets `BlazeDB_Tier3_Heavy` + `BlazeDB_Tier3_Heavy_Perf`
  - `macOS 15 — Tier1`: root target `BlazeDB_Tier1`
  - `macOS 15 — Tier2 (strict)`: root targets `BlazeDB_Tier2` + `BlazeDB_Tier2_Extended` via `./Scripts/run-tier2.sh --strict` (blocking in nightly lane)
  - `macOS 15 — clean checkout verification`: `./Scripts/verify-clean-checkout.sh`
  - `macOS 15 — README quickstart verification`: `./Scripts/verify-readme-quickstart.sh`
  - `macOS 15 — Tier0 (ThreadSanitizer)`: `swift test --sanitize thread --filter BlazeDB_Tier0`
  - `Linux (Swift 6.2) — Tier0`: `BlazeDB_Tier0`
  - `Linux (Swift 6.2) — Tier1`: `BlazeDB_Tier1` via filter `'BlazeDB_Tier1\.'` (fast nightly signal)
  - `Linux (Swift 6.2) — Tier2 (core)`: `BlazeDB_Tier2` (Linux-only nightly split job; deeper suites)
  - `Linux (Swift 6.2) — Tier2 (extended)`: `BlazeDB_Tier2_Extended` (Linux-only nightly split job; deeper suites)
  - `Linux (Swift 6.2) — Tier3 (heavy)`: `BlazeDB_Tier3_Heavy` (Linux-only nightly split job)
  - `Linux (Swift 6.2) — Tier3 (perf)`: `BlazeDB_Tier3_Heavy_Perf` (Linux-only nightly split job)
- Linux Tier labels are grouping vocabulary, **not execution stages**: `linux-tier0`, `linux-tier1`, `linux-tier2-core`, `linux-tier2-extended`, `linux-tier3-heavy`, and `linux-tier3-perf` are independent sibling jobs in `nightly.yml` (no `needs` chain between Linux lanes).
- Independent Linux sibling jobs can start together; practical parallelism is still bounded by available GitHub runner capacity.
- Nightly confidence lanes are root-owned and do not depend on `BlazeDBExtraTests`.
- Temporary quarantine policy (current): `macOS 15 — Tier3 (heavy, non-blocking)` is non-blocking in nightly so Tier1/Tier2 gates stay authoritative; Tier3 remains monitored with post-failure diagnostics.
- **Operational policy:** nightly failures are triaged within 24–48 hours.

### Nightly lane quick reference

| Job label in Actions UI | Primary purpose | Blocking behavior |
| ---- | ---- | ---- |
| `macOS 15 — Tier0 (ThreadSanitizer)` | Tier0 correctness with sanitizer diagnostics on Apple toolchain | Blocking |
| `macOS 15 — Tier1` | Canonical macOS Tier1 correctness lane | Blocking |
| `macOS 15 — Tier2 (strict)` | Tier2/Tier2-extended strict enforcement on macOS | Blocking |
| `macOS 15 — Tier3 (heavy, non-blocking)` | Heavy+perf monitoring on macOS under quarantine policy | Non-blocking (`continue-on-error`) |
| `macOS 15 — README quickstart verification` | Verify README user path stays valid | Blocking |
| `macOS 15 — clean checkout verification` | Verify clean-checkout/dev-env assumptions | Blocking |
| `Linux (Swift 6.2) — Tier0` | Baseline Linux Tier0 signal | Blocking |
| `Linux (Swift 6.2) — Tier1` | Canonical Linux Tier1 signal | Blocking |
| `Linux (Swift 6.2) — Tier2 (core)` | Linux Tier2 core integration surface | Blocking |
| `Linux (Swift 6.2) — Tier2 (extended)` | Linux Tier2 extended integration surface | Blocking |
| `Linux (Swift 6.2) — Tier3 (heavy)` | Linux heavy stress/fuzz surface | Blocking |
| `Linux (Swift 6.2) — Tier3 (perf)` | Linux perf companion surface | Blocking |

### Tier 3 profiling: CI vs local (do not “restore rigor” on runners)

Treat CI as a **constrained environment that must produce trustworthy signal**, not a place where every XCTest metric runs at maximum intensity. More metrics on a hosted runner often means **benchmarking the runner dying** (process exit without assertion failures, OOM, or cumulative profiling load), not BlazeDB.

**Why CI is lighter (not taste):** Tier3 jobs were failing when XCTest `measure` used **multiple iterations** plus **`XCTMemoryMetric`** on large fixtures—logs showed extreme reported memory peaks followed immediately by the test process exiting with a non-zero code and **no** `XCTAssert` failure. That is the failure mode this policy prevents.

**Do not “fix” CI by increasing iterations or re-enabling full metrics for “rigor.”** That sentence is wrong here: rigor for profiling belongs on **local or manual runs**, where **`GITHUB_ACTIONS` is unset** and Tier3 sources keep **full `measure` iteration counts and full metric sets** (including memory where appropriate). If you change CI back toward heavier profiling, you must treat it as a **deliberate policy change**: re-measure runner memory and job duration, update this section with evidence, and expect red nightly Tier3 again.

**What `GITHUB_ACTIONS=1` does in Tier3 perf sources (summary):** one `measure` iteration on CI, omit or replace `XCTMemoryMetric` where it amplified peaks, smaller fixtures on the heaviest baselines, clock-only where memory measurement was hostile—**local stays full-fat.**

### Nightly Tier3 policy

- **`nightly-macos-tier3-heavy`:** quarantined — `continue-on-error: true` in `nightly.yml`; a red Tier3 step does **not** fail the overall nightly workflow; logs and diagnostics still upload.
- **`linux-tier3-heavy`** and **`linux-tier3-perf`**: blocking — a red step fails the workflow (Linux depth lane).
- Any change to either policy should update **this file** and **`nightly.yml`** together so the two stay aligned.

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
  - macOS deep job: Tier1 `swift test --filter BlazeDB_Tier1`, Tier2 via `./Scripts/run-tier2.sh`, Tier3 heavy/destructive as in workflow (unchanged from prior release validation shape)
  - ThreadSanitizer on `BlazeDB_Tier0` and `BlazeDB_Tier1` (macOS)
  - Linux extended lane: Tier0, canonical Tier1 (`'BlazeDB_Tier1\.'`), Tier2 + Tier2 extended, Tier3 heavy + perf companion (Linux-only composition for long-running suites)

- `.github/workflows/release.yml`
- Trigger: tag push `v*`
- Behavior:
- Run `BlazeDB_Tier0`, `BlazeDB_Tier1`, `BlazeDB_Tier2`, `BlazeDB_Tier2_Extended`, `BlazeDB_Tier3_Heavy`, `BlazeDB_Tier3_Heavy_Perf`
- Build release artifact
- Generate release notes
- Publish GitHub release
- Blocking: release-only

## Tier Purposes

- **Canonical targets (end-state taxonomy):** `BlazeDB_Tier0`, `BlazeDB_Tier1`, `BlazeDB_Tier2`, `BlazeDB_Tier3_Heavy`, `BlazeDB_Tier3_Destructive`.
- **PR3 transitional companions (temporary, pending PR4 normalization):** `BlazeDB_Tier2_Extended`, `BlazeDB_Tier3_Heavy_Perf`.

- `BlazeDB_Tier0`
- Fast deterministic correctness gate for PRs and local preflight.
- Must stay bounded and stable.

- `BlazeDB_Tier1`
- Canonical PR correctness gate from `BlazeDBTests/Tier1Core/`.
- Sources: `BlazeDBTests/Tier1Core/` in root package.
- See `Package.swift` for the small exclude list (e.g. Darwin-only `SecureConnectionTests.swift`).

- `BlazeDB_Tier2`
- Integration and recovery scenarios.
- `BlazeDB_Tier2_Extended` is a **transitional companion target** containing reclassified legacy Tier1Extended suites under Tier2 ownership.
- Declared in root `Package.swift`.
- Non-blocking by default in script form; enforced in nightly via strict mode.

- `BlazeDB_Tier3_Heavy` / `BlazeDB_Tier3_Destructive`
- Stress, fuzz, and destructive/fault-injection lanes.
- `BlazeDB_Tier3_Heavy_Perf` is a **transitional companion target** containing reclassified legacy Tier1Perf suites under Tier3 ownership.
- Declared in root `Package.swift`; run via `swift test --filter BlazeDB_Tier3_Heavy` or `./Scripts/run-tier3.sh`.
- Manual/explicit use only; never default PR gate.

## Lane Contract And Budget Enforcement Policy

This section defines the behavioral contract for each lane. If observed behavior and lane name diverge, **behavior wins** and the test must move.

### Lane definitions (required semantics)

| Lane class | Purpose | Typical content | Not allowed |
| ---- | ---- | ---- | ---- |
| Tier1 fast signal | Fast breakage detection for PR feedback | Deterministic logic/invariant/regression checks with small fixtures | Long-running data/query/persistence/recovery or stress behavior |
| Extended / Integration | Heavier correctness across realistic data and storage behavior | Query-heavy integration, persistence/recovery, larger fixtures, cross-component flows | Destructive/fault-injection and benchmark-like stress |
| Perf / Stress | Long-running, scale-sensitive, destructive, or benchmark-adjacent behavior | High-cardinality datasets, soak runs, fuzz/stress, fault injection | Blocking fast-signal expectations |

### Hard budgets

These budgets are enforced as lane contracts, not suggestions.

| Budget type | Tier1 fast signal | Extended / Integration | Perf / Stress |
| ---- | ---- | ---- | ---- |
| Lane total wall clock | <= 15 minutes | <= 120 minutes | <= 240 minutes (or explicit manual lane) |
| Per-suite wall clock | <= 2 minutes | <= 20 minutes | no fixed cap; must be documented |
| Per-test wall clock | <= 90 seconds | <= 10 minutes | no fixed cap; must be documented |

Notes:
- Any suite consistently above Tier1 thresholds is integration or stress by behavior and must be moved.
- If CI hardware changes materially, rerun baseline and adjust thresholds in this file in the same PR.

### Default enforcement rule (move by default)

If a test or suite exceeds its lane budget:
1. It moves to the appropriate heavier lane by default.
2. It may remain only with a written exemption that includes:
   - explicit reason it must stay in the current lane,
   - measured timing evidence,
   - owner,
   - expiry/review date.

No open-ended "temporary" exemptions.

### CI rollout behavior

Budget enforcement is staged to avoid noisy rollout:

1. Baseline phase (warn-only):
   - collect per-test and per-suite durations,
   - publish over-budget warnings in CI summary/artifacts,
   - open migration issues for repeated offenders.
2. Enforcement phase (fail):
   - fail CI when Tier1 budgets are exceeded without active exemption,
   - fail CI when exemption metadata is missing or expired.

Policy: once baseline is established, do not revert from fail -> warn without an explicit incident note and owner.

### Migration checklist (required when moving tests)

When re-tiering a test/suite:
1. Move file/target ownership to the correct lane.
2. Update `Package.swift` target membership/excludes as needed.
3. Update lane runner scripts under `Scripts/`.
4. Update workflow invocations under `.github/workflows/`.
5. Update this file and any user-facing testing docs in the same PR.
6. Capture before/after runtime evidence in the PR description.

### Exemption checklist (only when necessary)

A valid exemption must include:
- suite/test identifier,
- measured p50/p95 runtime,
- reason it must stay in-lane,
- risk of moving lanes,
- owner and review date.

If review date passes, exemption is invalid and CI should fail until renewed or removed.

### Naming must match behavior

Lane names are contracts. If a suite behaves like integration/stress, do not label it "Tier1."

Mislabeling creates false expectations for developer feedback and hides CI cost. Rename lanes/targets when behavior changes.

## Reporting vocabulary

Use precise language so status and dashboards do not blur the PR gate with deeper lanes.

| Say this | Meaning |
| -------- | ------- |
| **Tier1 PR gate** / **Tier1** | `BlazeDB_Tier1` only—the default blocking Tier1 lane on PRs. |
| **Canonical tiers** | `BlazeDB_Tier0`, `BlazeDB_Tier1`, `BlazeDB_Tier2`, `BlazeDB_Tier3_Heavy`, `BlazeDB_Tier3_Destructive` (end-state model). |
| **PR3 transitional companions** | `BlazeDB_Tier2_Extended`, `BlazeDB_Tier3_Heavy_Perf`; temporary bridge targets slated for PR4 filesystem/target normalization. |
| **Depth lane** | `tier1-depth.yml` currently runs `BlazeDB_Tier2` + `BlazeDB_Tier2_Extended` + `BlazeDB_Tier3_Heavy` + `BlazeDB_Tier3_Heavy_Perf` (workflow filename kept for compatibility until PR4). |
| **Nightly confidence lane** | `nightly.yml`: macOS Tier1, Tier2 (strict), **Tier3 (heavy, non-blocking)**; **Linux** adds separate blocking jobs for Tier1, Tier2 (core), Tier2 (extended), Tier3 (heavy), and Tier3 (perf). |
| **Nightly macOS Tier3 heavy** | Job `nightly-macos-tier3-heavy`: `continue-on-error: true` — red tests are monitored (logs/artifacts/diagnostics) but **do not** turn the nightly run red. Not the same as Linux Tier3 nightly (blocking). |
| **Deep validation lane** | `deep-validation.yml`: macOS full stack; **Linux extended** runs Tier0 → canonical Tier1 → Tier2/Tier2_Extended → Tier3 heavy/perf (see workflow). |
| **Canonical Tier1** | `BlazeDB_Tier1` (single canonical Tier1 target). |

Inventory/bootstrap code may still bucket all three SwiftPM modules under a single **`T1`** label for file-level manifests; that is a storage convenience. **Human-facing** summaries (CI names, release notes, team chat) should use the table above, not a vague “T1 passed.”

### Suites relocated off canonical Tier1 (inventory)

These used to inflate Linux Tier1 wall-clock; they now live in **`BlazeDB_Tier2`** or **`BlazeDB_Tier3_Heavy`** and are exercised on **Linux** by `linux-tier2-core`, `linux-tier2-extended`, `linux-tier3-heavy`, `linux-tier3-perf`, and `deep-validation` → `deep-linux-extended`. macOS release/nightly still runs the same SPM targets—only Linux splits jobs for scheduling.

| Logical area | File under `BlazeDBTests/…` | SPM module | Linux nightly |
| ------------ | --------------------------- | ---------- | ------------- |
| Type-safety edge cases | `Tier2Integration/BlazeDBIntegrationTests/EdgeCases/TypeSafetyEdgeCaseTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Codable integration | `…/Integration/CodableIntegrationTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Client API (`BlazeDBClientTests`) | `…/Core/BlazeDBTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Persist API | `…/Persistence/BlazeDBPersistAPITests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Data seeding | `…/DataSeedingTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Subqueries | `…/SQL/SubqueryTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Filesystem errors | `…/Core/BlazeFileSystemErrorTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Key-path query | `…/Features/KeyPathQueryTests.swift` | `BlazeDB_Tier2` | `linux-tier2-core` |
| Query EXPLAIN (scale-heavy) | `Tier3Heavy/Query/QueryExplainTests.swift` | `BlazeDB_Tier3_Heavy` | `linux-tier3-heavy` |

`Tier1Core/DXQueryExplainTests.swift` remains in **`BlazeDB_Tier1`** (different, lighter DX coverage)—do not confuse with `QueryExplainTests` in Tier3.

**Linux nightly closure (no accidental holes after re-tiering):** the old “everything in Tier1” shape is replaced by the **union** of canonical Tier1 (`'BlazeDB_Tier1\.'`), `BlazeDB_Tier2\.`, `BlazeDB_Tier2_Extended`, `BlazeDB_Tier3_Heavy\.`, and `BlazeDB_Tier3_Heavy_Perf` across the Linux nightly jobs—see `nightly.yml`.

### Shared helpers (symlinks)

- `Tier1Extended/Helpers` and `Tier1Perf/Helpers` symlink to `Tier1Core/Helpers` where those trees still use the legacy layout.
- **`BlazeDBIntegrationTests`** pulls only **`XCTestCase+FixtureRequire.swift`** and **`TypeSafetyTestBug.swift`** from `Tier1Core/Helpers` via `Tier1CoreHelpers/` symlinks (avoids duplicating `TestHelpers.swift` with the integration target’s own `TestHelpers.swift`).
- **`Tier3Heavy`** symlinks **`XCTestCase+FixtureRequire.swift`** at the target root for `Query/QueryExplainTests.swift` (Tier3 already has its own `Helpers/TestCleanupHelpers.swift`).

If a platform step misbehaves with symlinks, replace with a small **shared test-support target**—see `Package.swift`.

### `BlazeDB_Tier1` excludes

Three files remain **excluded** from `BlazeDB_Tier1` in `Package.swift`:

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
- `./Scripts/run-tier1.sh` (Tier 0 + `BlazeDB_Tier1` + execution coverage)
- `./Scripts/run-tier1-depth.sh` (`BlazeDB_Tier2` + `BlazeDB_Tier2_Extended` + `BlazeDB_Tier3_Heavy` + `BlazeDB_Tier3_Heavy_Perf`)
- `./Scripts/run-tier2.sh`
- `./Scripts/run-tier3.sh`

## Interpreting CI failures (first artifact, not last passer)

The **last passing test** in the log only identifies the **next execution candidate**, not necessarily the **root cause**. Sanitizer runs, worker death, and infra limits often make the “last green” line a red herring.

**Default hypothesis order for late failures when Tier0 Thread Sanitizer is currently green**

1. Real XCTest failure (assertion or thrown error with test context)
2. Order or shared-state contamination (parallel workers, globals, shared paths)
3. Late runtime or infra failure (timeout, SIGKILL, OOM, runner cancellation)
4. Sanitizer output — **only** when the **first** failing artifact is actually a sanitizer report (do not infer sanitizer from “we fixed a race once”)

Tier0 TSan being green does **not** prove there are no races anywhere, no sanitizer-only issues in other lanes, or no parallelism-dependent failures. It **does** mean you should not treat an older, fixed failure class (for example associated-object lazy-init races) as the automatic explanation for every later failure without matching log evidence.

**Buckets collapse only on the first failing artifact**, for example: first `XCTAssert…` line, first thrown error with test context, first TSan report block, first timeout or kill line, or first cancellation/OOM signal.

**Quick checklist when triaging**

- What is the **first** failing artifact (assertion, throw, timeout, kill, cancellation, sanitizer)?
- Was the failure **early**, **mid-run**, or **late**?
- Is Tier0 TSan green on the branch?
- Is the suspect test the **named failing test**, or merely the **next execution candidate** after an unrelated last pass?

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
