# BlazeDB Product and Repository Audit

**Audit date:** 2026-07-26  
**Current release context:** v2.8.1 (dynamic `BlazeDBC`)  
**Method:** Evidence from implementation, tests, `Package.swift`, CI, docs, examples, git history, and local validation commands. Source-of-truth order matches the audit brief (code > tests > package/CI > architecture docs > examples > README > release prose > archive).

This document is the grounded product audit. Directional priorities live in [`ROADMAP.md`](../../ROADMAP.md). Detailed candidates that do not fit the concise roadmap live in [`ROADMAP_BACKLOG.md`](ROADMAP_BACKLOG.md).

---

## Executive summary

BlazeDB today is a **Swift-first encrypted embedded document database**. The default OSS product is the embedded engine (`BlazeDB` / `BlazeDBCore`), the `blazedb` CLI, and a documented byte-oriented C ABI packaged as a **dynamic** library (`BlazeDBC`). Distributed sync, discovery, server, and full telemetry packaging are **in-tree but excluded** from the default product. Android/KMM paths have real CI proof and remain **experimental**.

Recent public docs (README, Docs index, RELEASE, ROADMAP) are substantially more honest than the historical Status/Archive surface. The remaining gaps are mostly **correctness/compatibility gates**, **contributor safety**, **release artifact hygiene**, and a few **overclaims** that survived the cleanup.

### Highest-priority findings

1. **No checked-in Go sources** despite README/Examples/Go claiming a “working end-to-end Go integration.” C ABI E2E is real (`hello_blazedb.c`, `BlazeDBCSmokeTests`). Go packaging must start with sources + a CI gate, not release prose.
2. **No prior-release on-disk compatibility fixtures** in CI. Golden-path dump/restore tests create fresh DBs; they do not prove v2.7.x files still open under v2.8.x.
3. **Storage-change contributor checklist is still missing** while CONTRIBUTING hard-rejects “frozen” PageStore/WAL/encoding changes without an affirmative allowed-change process.
4. **`ExperimentalBPlusTree` is a print-only stub**; production indexing is hash secondary + `BTreeIndex`, and many queries still scan. “Finish B+ tree” was overstated as near-term completion.
5. **CLI docs/help drift:** Doctor/Dump/Info are separate executables; many docs still say `blazedb doctor|dump|…`.
6. **COMPATIBILITY.md still says iOS is “Fully supported”** while CI Apple jobs are **compile-only** for BlazeDBCore (README is more accurate).
7. **Release packaging tars the entire `.build/release` tree** on macOS only; not a curated `BlazeDBC` + header layout, and not a Linux `.so` publish lane.
8. **Benchmarks are mature locally** (JSON, matrix, comparison docs) but **not a CI regression gate**.

### Major strengths

- Clear product identity after README/Docs rewrite
- Durable default path documented and covered by crash-recovery tests
- Tiered CI (PR / nightly / deep) with Linux Tier0 runtime
- Dynamic `BlazeDBC` fixes real FFI linking pain (`swift_retain` / `swift_release`)
- `./dev` + lean schemes improve contributor UX
- Explicit deferred story for distributed transport

---

## Current product identity

| Question | Answer |
|----------|--------|
| What is BlazeDB? | Encrypted embedded document DB in Swift; single-process; password-required AES-GCM pages; WAL-backed default durability |
| Primary product | Embedded Swift engine (`BlazeDB` product → `BlazeDBCore`) |
| Interop product | Documented C ABI via dynamic `BlazeDBC` (+ optional `BlazeDBCStatic`) |
| Operator product | `blazedb` CLI (picker/REPL); companion tools Doctor/Dump/Info as local targets |
| Not the default product | Distributed sync/discovery/server/full telemetry packaging; Android/KMM as production SDK |

---

## Product inventory (condensed)

| Name | Type | Default package? | Maturity | CI | Notes |
|------|------|------------------|----------|----|-------|
| `BlazeDB` | library | Yes | Stable / default | PR build+tests | Umbrella re-export |
| `BlazeDBCore` | library | Yes (advanced) | Stable | PR + Apple cross-compile + Linux | Implementation module |
| `BlazeDBC` | dynamic library | Yes | Supported ABI | Indirect via Tier1 smoke (macOS PR) | Header `blazedb.h` |
| `BlazeDBCStatic` | static library | Yes (optional) | Supported | Buildable | Prefer dynamic for FFI |
| `blazedb` | executable product | Yes | Supported | PR build + CLITests | Shell/REPL |
| `BlazeDoctor` / `Dump` / `Info` | executables | No (local targets) | Supported tools | PR compile | Not `blazedb` subcommands |
| `BlazeDBBenchmarks` | executable | No | Internal | Not in CI | Preferred Profile entry |
| `HelloBlazeDB`, `ReadmeSamples`, `CorePathSmoke`, `MVVMPattern`, `BasicExample`, `ReferenceConsumer` | examples | No | Default/experimental labeled | README verify jobs | |
| `Examples/C/hello_blazedb.c` | C example | N/A | Supported sample | Not linked in CI | Verified locally this audit |
| `Examples/Go/` | docs only | N/A | Preview docs | None | **No `.go` files** |
| `BlazeDBAndroidBridge` / KMM | libraries + sample | Yes products / experimental | Experimental | PR compile + emulator + packaging | Not production SDK |
| `BlazeDBSyncStaging` / `TelemetryStaging` | staging targets | No | Deferred stubs | Staging tests not in PR map | |
| Distributed / Telemetry source trees | excluded dirs | No | Deferred | Excluded from core | |
| `BlazeStudio` / `BlazeDBVisualizer` | Xcode apps | Outside SPM | Companion / beta | No PR runtime jobs found | Shared schemes missing on disk |

Full scheme/CI/target detail: see inventory notes in audit working papers; authoritative maps are `Package.swift`, `.github/workflows/*`, `Docs/Testing/CI_AND_TEST_TIERS.md`.

---

## Support-state matrix

| Area | State | Evidence |
|------|-------|----------|
| Embedded storage, typed/raw APIs, transactions, WAL durability, import/export, inspection | Default shipped | Package products, Tier0/1, README |
| Migrations, indexing, search tuning, manual mapping, schema validation APIs | Advanced supported | APIs + tests; schema **docs** under consolidation |
| C ABI byte KV | Supported | Header + smoke + C example |
| CLI | Supported | Product + CLITests |
| Doctor/Dump/Info | Supported tools, local targets | Built in CI; doc/dispatch drift |
| Go module | Not shipped | Docs only; no sources |
| Android/KMM | Experimental | android-status + CI |
| Distributed sync / discovery / server / full telemetry packaging | Deferred | Package excludes + DISTRIBUTED_TRANSPORT_DEFERRED |
| Status/Archive “COMPLETE” narratives | Historical | Docs/README authority map |

---

## Engine audit (summary)

### Storage / durability

- Default path: legacy binary WAL, page AES-GCM, publish-last overflow (orphans possible). Documented in `Docs/Status/DURABILITY_MODE_SUPPORT.md`.
- Dual mode (legacy vs unified) is a compatibility footgun if mixed on one file.
- Crash recovery tests exist and passed in this audit (`CrashRecoveryTests`, 6 cases).
- Gap: **no checked-in DBs from prior tags** opened in CI.

### Transactions / concurrency

- Client transactions: one at a time; savepoints exist; ACID wording is stronger than snapshot+backup mechanics.
- Exclusive `flock`; multi-process writers rejected.
- MVCC opt-in / experimental posture.

### Query / indexes

- Typed namespace query + raw builders work; HelloBlazeDB matches recommended happy path.
- Indexes: hash secondary + `BTreeIndex` range support; planner still often scans.
- `Indexing/ExperimentalBPlusTree.swift`: node + `printTree` only.
- C ABI reserves `BlazeDBIterator` with **no functions**.

### Models / schema

- Default schemaless + `BlazeStorable`; opt-in schema validation and migrations exist and have tests.
- Docs still fragmented (“under consolidation”).

### Encryption

- PBKDF2-HMAC-SHA256 + AES-GCM pages; session key cache across close.
- No in-place rekey API; “rotation” tests are export/reimport style.
- ForwardSecrecy / Argon2 helpers are not the production open path.

### Health / diagnostics

- `health()` / `stats()` exist; cache hit rate not wired.
- Doctor mutates (probe write); deeper WAL/meta proofs limited.

---

## Public Swift API audit

**Happy path is good:** `BlazeDB.open` → `put` → `get` → `query` (README + HelloBlazeDB + ReadmeSamples).

| Issue | Kind |
|-------|------|
| `open(name:)` vs `open(at:)` vs deprecated overloads | Naming noise |
| Typed `put`/`get` vs byte KV `put(key:value:)` | Dual surface |
| Transactions not in onboarding samples | Doc gap |
| Silent drop of undecodable records on some bulk paths | Safety |
| HelloBlazeDB uses temp `open(at:)` while README shows `open(name:)` | Acceptable if both CI-covered |

No major breaking API change recommended without a compatibility plan. Prefer additive APIs and documentation.

---

## CLI / tools audit

| Surface | Finding |
|---------|---------|
| `blazedb help` | Discoverable for start/picker/REPL/dev |
| REPL | Has `--json` / `--ndjson` for some commands; `doctor --json` |
| Doctor/Dump/Info | Separate targets; help text often says `blazedb …` |
| Scripting | Partial JSON; Dump/Info lack `--json` |
| Exit codes / `--version` | `--version` missing |
| Destructive | Doctor write probe; Dump restore; restore-backup |

Roadmap need: align docs **or** wire real subcommands; add process smoke tests.

---

## FFI audit

| Topic | Status |
|-------|--------|
| Stable surface | open/put/get/delete/close/free + result codes |
| Missing | last_error, iterators, prefix scan, batch, transactions, open_ex |
| Dynamic packaging | Verified locally (`libBlazeDBC.dylib`) + RELEASE.md |
| Tests | `BlazeDBCSmokeTests` (macOS Tier1); thinner than Swift ByteKV |
| C example | Builds and runs (this audit) |
| Go | **Documentation only** — 0 `.go` files |
| ABI symbol diffs | Not automated |
| Release artifacts | Not curated FFI packages |

Distinguish roadmap work: engine vs C ABI vs Go packaging vs other languages.

---

## Platform audit

| Platform | Declared | CI compile | CI runtime | Public claim should be |
|----------|----------|------------|------------|------------------------|
| macOS 15+ | Yes | Yes | Yes (Tier0+1+CLI) | Supported |
| Linux | Implicit | Yes | Tier0 (+CLI); Tier1 nightly | Core supported |
| iOS / watchOS / tvOS / visionOS | Yes | Yes (cross-compile) | No BlazeDBCore XCTest in PR | Compile-tested / declared |
| Android / KMM | Via bridge | Yes | Emulator + iOS KMM tests | Experimental |
| Windows | Mentions only | No | No | Unsupported |

**Doc fix needed:** `Docs/COMPATIBILITY.md` “Fully supported” for iOS overstates CI.

---

## Testing / CI audit

| Gate | Catches | Gap |
|------|---------|-----|
| PR Tier0/1/CLI (macOS) | Core regressions | |
| Linux Tier0 | Linux core | BlazeDBC smoke not on Linux PR |
| Apple cross-compile | Platform compile | Not runtime |
| Nightly Tier2 / TSan | Integration / races | Flake history |
| Deep Tier3 | Stress/destructive | Non-blocking / optional on release |
| README verify | Snippet drift | |
| Missing | Prior-version DB open | Compatibility fixtures |
| Missing | `hello_blazedb.c` link | Packaging regressions |
| Missing | Go E2E | No sources |
| Missing | ABI symbol snapshot | Silent ABI churn |
| Missing | Short bench regression | Perf cliffs |

---

## Benchmark audit

- Strong local methodology: comparison scripts, JSON results, environment fingerprint, MVCC concurrent lane, Profile via `BlazeDBBenchmarks`.
- Dual entry scripts (`run_benchmarks.sh` vs comparison/refresh) confuse which numbers are authoritative.
- Not a CI gate. Do not publish headline numbers without methodology (already policy).

---

## Documentation audit

| Strength | Gap |
|----------|-----|
| Docs/README support-state map | Competing FEATURE_ROADMAP / Status COMPLETE piles |
| RELEASE packaging story | Go “working integration” overclaim |
| Durability + key lifecycle docs | Dual threat models (core vs distributed) |
| CONTRIBUTING + PR template | No storage checklist; Android wording drift |

Prefer canonicalization and superseded notices over rewriting every guide.

---

## Contributor audit

| Works | Friction |
|-------|----------|
| `./dev help`, focused tests, HelloBlazeDB | Storage changes: reject-only freeze language |
| Preflight + PR template | No storage/WAL fields in issue/PR templates |
| Experiments discovery | Orphan test trees outside Package.swift paths |
| | Studio/Visualizer schemes documented but missing shared files |

---

## Release audit

| Present | Missing |
|---------|---------|
| Tag SemVer gate | Curated BlazeDBC artifacts |
| Tier0–2 validate on tag | Linux `.so` publish |
| Tarball of `.build/release` | Checksums/signing story |
| Homebrew `Formula/blazerepl.rb` | Versioned bottles (head-only today) |
| Generated git-log notes | Prefer curated RELEASE.md body |

---

## Security / durability audit

| Verified-style | Untested / assumed | Missing policy |
|----------------|--------------------|----------------|
| Password + AES-GCM pages | Power-loss vs `fsync` only (no `F_FULLFSYNC`) | In-place rekey |
| Default WAL ordering + crash tests | Malicious-file fuzz breadth | External review completion (plan window overdue) |
| Auth fail vs corrupt codes (partial) | CLI password via env | GitHub security contact_links |
| Single-process flock | Distributed threat grades as product posture | |

Do not casually redesign crypto. Refresh external-review status as a maintainer decision.

---

## Git-history findings

- 2026 arc: doc honesty → `./dev` → C ABI → dynamic BlazeDBC → Android/KMM CI → session keys → benchmarks honesty.
- Repeated deferred: distributed transport, official Go module, B+ as real query index.
- C ABI briefly prepared as `v0.1.0` materials, then shipped in 2.8.0 stream.
- Do not revive BlazeServer / distributed without public deps + CI.

---

## Roadmap candidate table (scored)

Priority order used: correctness → durability → security → compatibility → contributor safety → release → performance evidence → DX → platforms → features.

| Candidate | Problem | Evidence | Complexity | Bucket |
|-----------|---------|----------|------------|--------|
| Storage-change checklist | Unsafe core edits | ROADMAP Now; CONTRIBUTING freeze-only | Small | **Now** |
| On-disk compatibility fixtures | Silent format break | No prior-tag DB fixtures in CI | Medium | **Now** |
| Honest Go sources + CI smoke | Docs > tree | 0 `.go` files; C path verified | Small–Medium | **Now** |
| Align CLI tool docs/dispatch | Dead `blazedb doctor` claims | BlazedbEntry vs tool help | Small | **Now** |
| Align COMPATIBILITY with CI | Overstated iOS | COMPATIBILITY vs README/CI | Small | **Now** |
| Quarantine Experimental B+; document real index path | False readiness | ExperimentalBPlusTree stub | Small | **Now** |
| Curate BlazeDBC release artifacts + C link CI | Packaging regressions | release.yml whole tree; no C link job | Medium | **Now** |
| Schema/migration doc consolidation | Advanced API confusion | Docs/README Advanced table | Medium | **Now** |
| `blazedb_last_error` + richer C smoke | Undebuggable open NULL | C_ABI_BYTE_KV deferred list | Medium | **Next** |
| C ABI iterators / prefix / batch | Host listing/batch gaps | Reserved iterator type | Large | **Next** |
| Short bench regression CI | Perf cliffs manual | No workflow runners | Medium | **Next** |
| More corruption / power-loss tests | Recovery blind spots | Overflow orphans; fsync-only | Medium | **Next** |
| Official versioned `blazedb-go` | Productization | After sources exist | Medium | **Next** |
| iOS simulator runtime Tier0 | Mobile runtime claim | Compile-only today | Medium | **Next** |
| Index execution vs planner honesty | O(n) surprise | SYSTEM_MAP / QueryPlanner | Large | **Next** |
| External security review refresh | Overdue plan | EXTERNAL_SECURITY_REVIEW_PLAN | Process | **Next** |
| Homebrew versioned formula | Tag vs head drift | Formula head-only | Small | **Next** |
| Relationship guidance | FK story incomplete | ForeignKeys stubs | Medium | **Later** |
| Optional modeling package | App-layer ORM | No BlazeDBRelations module | Research | **Later** |
| Android/KMM productization | Demand-gated | android-status frozen | Large | **Later** |
| Other language wrappers | After Go pattern | No demand proof | Large | **Later** |
| In-place key rotation | Password change UX | ForwardSecrecy unwired | Large | **Later** |
| Distributed capabilities | Multi-device product | Explicitly deferred | Research | **Not planned (default OSS)** |
| Cost-based optimizer / “AI” features | Marketing buffet | INSANE_FEATURES overclaim | Research | **Reject** |
| Advertise KMM as production SDK now | False support | Experimental CI | — | **Reject** |

---

## Rejected / intentionally deferred ideas

- **Distributed sync in default OSS** until public dependencies and CI exist (`DISTRIBUTED_TRANSPORT_DEFERRED.md`).
- **KMM/Android as “fully supported SDK”** while experimental.
- **Speculative language bindings** before Go packaging exists.
- **Production B+ completion as near-term certainty** — current code is a stub; real work needs design + exit criteria.
- **Ceremonial “support every Apple platform with full runtime CI”** without product value — prefer targeted simulator gates.
- **Publishing raw throughput headlines** without methodology.

---

## Validation commands run

| Command | Result |
|---------|--------|
| `git diff --check` | Clean |
| `./dev help` | OK |
| `./dev test BPlusTreeNodeTests.createsSimpleTree` | Pass (1 test) |
| `swift run HelloBlazeDB` | Pass |
| `swift build -c release --product BlazeDBC` | Pass → `libBlazeDBC.dylib` |
| `swift build -c release --product BlazeDBBenchmarks` | Pass |
| `.build/debug/blazedb help` | OK |
| `swift test --filter BlazeDBCSmokeTests` | Pass (2 tests) |
| `swift test --filter CrashRecoveryTests` | Pass (6 tests) |
| `swift test --filter 'SchemaValidation\|Migration'` | Pass (EXIT 0; long suite) |
| `swift test --filter DataTypeCompoundIndexTests` | Pass |
| `cc … Examples/C/hello_blazedb.c` + run | Pass (`get: queued` / `ok`) |
| `./dev tier0` | EXIT 0; noted arch `arm64` vs `x86_64` dlopen warnings under the tier runner — treat full Tier0 content as **partially noisy** in this environment |
| Go E2E from repo sources | **Not possible** — no `.go` files |
| Full PR Tier1 / Linux CI / release workflow | Not run locally |

Shared schemes inspected under `.swiftpm/xcode/xcshareddata/xcschemes/`. README/release/roadmap links reviewed manually (not a full Docs link crawler).

---

## Unverified areas

- Live GitHub Actions green/red for every named job
- Whether `BlazeDB_Staging` runs anywhere in CI
- Orphan top-level `BlazeDBTests/*` trees vs dead code
- BlazeStudio/Visualizer runtime quality
- Power-loss / `F_FULLFSYNC` behavior on Apple storage
- Homebrew tap install from a clean machine
- External security review actual engagement status beyond checklist text
- Whether any out-of-tree Go code exists on the maintainer’s machine

---

## Maintainer decisions required

1. **Go story:** land checked-in `Examples/Go` sources + CI, or keep docs as “cgo recipe only” until then (this audit applies the latter wording until sources exist).
2. **Compatibility fixtures:** which prior tags are supported for open/read/write?
3. **CLI tools:** subcommands on `blazedb` vs docs-only `swift run`?
4. **B+ indexing:** invest in production B+, or delete/quarantine the experimental stub and document hash/`BTreeIndex` as the real path?
5. **External security review:** complete, reschedule, or risk-accept with public wording?
6. **Release artifacts:** keep whole-tree tarball or ship curated FFI + CLI packages (macOS + Linux)?
