# CLI Doctor Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship discoverable `blazedb doctor` with a shared sanitized local report (`--json` / `--report`), read-only by default, optional `--write-check`, no upload/telemetry.

**Architecture:** Put the sanitized `DoctorReport` model, runner, password resolver, and atomic report writer in `BlazeCLICore` (`BlazeShell/`). Make `BlazedbCLI`, `BlazeDoctor`, and REPL thin dispatch over that runner. Discoverability (help, errors, README, bug template, migration notice) is part of the same issue (#300), not a follow-up.

**Tech Stack:** Swift 6, Foundation, XCTest (`BlazeDB_CLITests`), existing `BlazeDBClient` public APIs, `CLIPasswordReader` / `CLIError`.

**Spec:** [`Docs/Design/CLI_DOCTOR_REPORT.md`](CLI_DOCTOR_REPORT.md) · Tracking: [#300](https://github.com/Mikedan37/BlazeDB/issues/300)

## Global Constraints

- No networking in Core or doctor path; `"upload": false` always.
- Same sanitized Codable model for `--json` and `--report` (destination only differs).
- Read-only default; mutate only with `--write-check`.
- No basename / path / secrets in report; random `report_id`; `schema_version = 1`.
- Exit codes: `0` = completed (ok or warnings), `1` = failed checks or report I/O after run, `64` = usage/path/password policy.
- No `--overwrite` in v1; existing report path → exit `64`.
- Temp file for report must live in the **same directory** as the destination so `rename` is atomic.
- Do not split #300 into microscopic tickets; keep one end-to-end issue with the phases below.

---

## File map

| Path | Role |
|------|------|
| **Create** `BlazeShell/Doctor/DoctorReport.swift` | Sanitized Codable schema + enums |
| **Create** `BlazeShell/Doctor/DoctorOptions.swift` | Options + output format |
| **Create** `BlazeShell/Doctor/DoctorEnvironment.swift` | Injectable version/platform/swift metadata |
| **Create** `BlazeShell/Doctor/DoctorPasswordResolver.swift` | TTY prompt → env → fail |
| **Create** `BlazeShell/Doctor/DoctorReportWriter.swift` | Atomic same-dir temp → rename |
| **Create** `BlazeShell/Doctor/DoctorRunner.swift` | `DoctorRunning` + checks + write-check |
| **Create** `BlazeShell/Doctor/DoctorCLI.swift` | Arg parse, human/`--json`/`--report` presentation, exit codes |
| **Create** `BlazeDBCLITests/Doctor/DoctorReportModelTests.swift` | Schema / redaction / golden |
| **Create** `BlazeDBCLITests/Doctor/DoctorReportWriterTests.swift` | Atomic write / exists / missing parent |
| **Create** `BlazeDBCLITests/Doctor/DoctorRunnerTests.swift` | Read-only + write-check cleanup |
| **Create** `BlazeDBCLITests/Doctor/DoctorPasswordResolverTests.swift` | Non-interactive fail |
| **Create** `BlazeDBCLITests/Fixtures/doctor_report_golden_v1.json` | Golden fixture |
| **Modify** `Package.swift` | `BlazeDoctor` depends on `BlazeCLICore` |
| **Modify** `BlazedbCLI/BlazedbEntry.swift` | Dispatch `doctor` before other flows |
| **Modify** `BlazeShell/CLIHelp.swift` | Global + doctor help copy |
| **Modify** `BlazeShell/BlazedbRepl.swift` | REPL `doctor` → shared runner |
| **Modify** `BlazeDoctor/main.swift` | Compat wrapper + migration notice |
| **Modify** `BlazeDB/Exports/BlazeDBError+Categories.swift` | Suggest `blazedb doctor` + `--report` |
| **Modify** `BlazeDB/Exports/BlazeDBError+Suggestions.swift` | Same |
| **Modify** `BlazeDB/Exports/DatabaseHealth.swift` | Same |
| **Modify** `README.md` | Troubleshooting section |
| **Modify** `CONTRIBUTING.md` | Point at doctor / report |
| **Modify** `Docs/Contributing/ISSUE_GUIDE.md` | Ask for report attachment |
| **Modify** `.github/ISSUE_TEMPLATE/bug_report.md` | Ask for `--report` |
| **Modify** `Docs/Architecture/TOURS/06_CLI.md` | Doctor is top-level |
| **Modify** `Docs/Tools/BLAZEDOCTOR_DOCUMENTATION.md` | Prefer `blazedb doctor` |
| **Modify** `Docs/Architecture/CODEBASE_MAP.md` | Reflect shared runner |
| **Later (ship)** `RELEASE.md` / `CHANGELOG.md` | When cutting the release that includes this |

## Commit sequence (before / during product code)

Do **not** start by rewriting `BlazeDoctor/main.swift`. Smallest prep sequence:

1. **docs:** refresh design locks + add this plan (already partly done).
2. **test:** add failing model/writer/password tests + golden fixture (no runner yet).
3. **feat:** report model + writer + password resolver (make those tests pass).
4. **test+feat:** runner (read-only + write-check) + runner tests.
5. **feat:** `DoctorCLI` + `blazedb doctor` dispatch + help.
6. **feat:** `BlazeDoctor` wrapper + REPL reuse.
7. **docs+discoverability:** README, templates, error strings, tour, tools doc.
8. **chore:** close loop on #259 note / CODEBASE_MAP; RELEASE/CHANGELOG only when shipping.

---

### Task 0: Lock design deltas into the spec (docs only)

**Files:**
- Modify: `Docs/Design/CLI_DOCTOR_REPORT.md` (password non-interactive fail; no overwrite; write-check cleanup; report path table; discoverability)
- Modify: `Docs/Design/README.md` (link this plan)

- [ ] **Step 1:** Confirm design doc matches Global Constraints above (already updated in the planning session; re-read and fix any drift).

- [ ] **Step 2:** Commit docs-only if uncommitted:

```bash
git add Docs/Design/CLI_DOCTOR_REPORT.md Docs/Design/CLI_DOCTOR_REPORT_PLAN.md Docs/Design/README.md
git commit -m "$(cat <<'EOF'
docs: lock CLI doctor report design and implementation plan

EOF
)"
```

---

### Task 1: Sanitized report model + golden fixture (TDD)

**Files:**
- Create: `BlazeShell/Doctor/DoctorReport.swift`
- Create: `BlazeShell/Doctor/DoctorEnvironment.swift`
- Create: `BlazeDBCLITests/Doctor/DoctorReportModelTests.swift`
- Create: `BlazeDBCLITests/Fixtures/doctor_report_golden_v1.json`
- Test target: `BlazeDB_CLITests` (`Package.swift` path `BlazeDBCLITests`)

**Interfaces:**
- Produces:
  - `public struct DoctorReport: Codable, Equatable`
  - `public struct DoctorCheck: Codable, Equatable`
  - `public struct DoctorWriteCheckInfo: Codable, Equatable`
  - `public enum DoctorOverallStatus: String, Codable` — `ok`, `warnings`, `failed`
  - `public enum DoctorCheckStatus: String, Codable` — `passed`, `failed`, `warning`, `skipped`
  - `public struct DoctorEnvironmentMetadata` — injectable `blazedbVersion`, `cliVersion`, `platform`, `architecture`, `swiftVersion`
  - `DoctorReport.makeStubForTests(...)` or builder used by golden encoding

- [ ] **Step 1: Write golden fixture** at `BlazeDBCLITests/Fixtures/doctor_report_golden_v1.json` with fixed `report_id` / `generated_at` / versions (no host paths). Use the example shape from the design doc (`upload: false`, one failed `database_open` check).

- [ ] **Step 2: Write failing tests**

```swift
func testRequiredTopLevelKeysPresent() throws { /* decode golden; assert keys */ }
func testUploadIsAlwaysFalse() throws { /* encode stub; XCTAssertFalse(report.upload) */ }
func testEncodedJSONContainsNoAbsolutePathOrHome() throws {
    // Build report with messages that attempted path injection via safety net if any;
    // assert encoded string has no "/Users/", "/home/", "\\" drive paths
}
func testGoldenFixtureRoundTrip() throws {
    // Load fixture Data; decode DoctorReport; re-encode sorted keys; compare semantic equality
}
func testSchemaVersionIsOne() throws { XCTAssertEqual(report.schemaVersion, 1) }
```

CodingKeys must be **snake_case JSON** (`schema_version`, `report_id`, …) matching the design.

- [ ] **Step 3: Run tests — expect FAIL** (types missing)

```bash
swift test --filter DoctorReportModelTests
```

- [ ] **Step 4: Implement `DoctorReport.swift` + `DoctorEnvironment.swift`** with public Codable types, snake_case keys, no `path`/`basename` properties.

- [ ] **Step 5: Re-run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(cli): add sanitized DoctorReport schema and golden fixture

EOF
)"
```

---

### Task 2: Atomic report writer + path policy (TDD)

**Files:**
- Create: `BlazeShell/Doctor/DoctorReportWriter.swift`
- Create: `BlazeDBCLITests/Doctor/DoctorReportWriterTests.swift`

**Interfaces:**
- Produces:
  - `public enum DoctorReportPathPolicy`
  - `public static func defaultReportURL(now: Date = Date(), cwd: URL = …) -> URL`
  - `public struct DoctorReportWriter`
  - `func write(_ report: DoctorReport, to destination: URL) throws`
  - Errors map to usage vs I/O (caller maps to exit `64` vs `1`)

**Path behavior to implement exactly:**

| CLI | Destination |
|-----|-------------|
| `--report` | `cwd/blazedb-diagnostics-YYYY-MM-DDTHHmmssZ.json` (UTC, no fractional seconds) |
| `--report custom.json` | `custom.json` resolved against cwd if relative |

Rules:
- Parent directory must exist → else throw usage error.
- Destination exists → throw usage error (no overwrite).
- Write `destinationDir / ".\(destination.lastPathComponent).tmp-\(uuid)"` (or similar) in **same directory**, encode JSON pretty-printed, synchronize file, `rename` to destination.
- Clean up temp on failure.

- [ ] **Step 1: Failing tests** for: successful write + `upload==false` on disk; existing file fails; missing parent fails; default name pattern regex `^blazedb-diagnostics-\\d{4}-\\d{2}-\\d{2}T\\d{6}Z\\.json$`.

- [ ] **Step 2: Run — FAIL**

```bash
swift test --filter DoctorReportWriterTests
```

- [ ] **Step 3: Implement writer**

- [ ] **Step 4: Run — PASS** → commit

```bash
git commit -m "$(cat <<'EOF'
feat(cli): add atomic DoctorReport writer with no-overwrite policy

EOF
)"
```

---

### Task 3: Password resolver (TDD)

**Files:**
- Create: `BlazeShell/Doctor/DoctorPasswordResolver.swift`
- Create: `BlazeDBCLITests/Doctor/DoctorPasswordResolverTests.swift`
- May extend: `BlazeShell/CLIPasswordReader.swift` only if you need `stdinIsTTY` helper (prefer keeping helper next to resolver)

**Interfaces:**
- Produces:
  - `public enum DoctorPasswordSource` — internal only; **never** put in report
  - `public struct DoctorPasswordResolver`
  - `func resolve(environment: [String: String], stdinIsTTY: Bool, prompt: () throws -> String) throws -> String`

Order for **`blazedb doctor`** (not BlazeDoctor argv):
1. If `stdinIsTTY` → `prompt()` (secure interactive)
2. Else if `environment["BLAZEDB_PASSWORD"]` non-empty → use it
3. Else throw usage error: explain set `BLAZEDB_PASSWORD` or run interactively

- [ ] **Step 1: Tests** — TTY calls prompt; non-TTY uses env; non-TTY without env throws; empty env treated as missing.

- [ ] **Step 2: Implement** → PASS → commit

```bash
git commit -m "$(cat <<'EOF'
feat(cli): resolve doctor passwords without hanging in CI

EOF
)"
```

---

### Task 4: Shared `DoctorRunner` (read-only + write-check)

**Files:**
- Create: `BlazeShell/Doctor/DoctorOptions.swift`
- Create: `BlazeShell/Doctor/DoctorRunner.swift`
- Create: `BlazeDBCLITests/Doctor/DoctorRunnerTests.swift`
- Consumes: `BlazeDBClient` APIs already used by `BlazeDoctor/main.swift` and `BlazedbRepl.buildDoctorReport` — `stats()`, `health()`, `getMonitoringSnapshot()`, `count()`, `fetchPage`, `insert`, `fetch`, `delete`

**Interfaces:**
- Produces:
  - `public struct DoctorOptions`
  - `public struct DoctorRunResult { let report: DoctorReport; let exitCode: Int32 }`
  - `public protocol DoctorRunning { func run(options: DoctorOptions) throws -> DoctorRunResult }`
  - `public struct DoctorRunner: DoctorRunning`

**Check names (stable):** `file_exists`, `file_readable`, `permissions`, `database_open`, `layout`, `health`, `monitoring`, `read_path`, `write_check` (only when requested).

**Write-check sequence (mandatory):**
1. Print human notice only when `outputFormat == .human` (CLI layer may print; runner can return a flag — prefer CLI prints before calling runner when `writeCheck`).
2. Insert probe via `insert(_:id:)` with a **fixed well-known probe UUID** constant `DoctorRunner.probeRecordID` (not emitted in report).
3. Fetch probe; delete probe; fetch again and assert `nil`.
4. On leftover record → check `code: "write_check.cleanup_failed"`, overall `failed`, exit `1`.

Open failures must still return a `DoctorReport` (not throw past CLI) so `--report` / `--json` work on broken DBs. Throwing reserved for programmer/usage errors.

Map `BlazeDBError` to stable codes like `open.authentication_failed` using existing categories where possible (`BlazeDBError+Categories.swift`).

- [ ] **Step 1: Failing tests** with temp DB under `FileManager.default.temporaryDirectory` (paths allowed in test harness, never copied into report fields):
  - healthy read-only run → `status == ok`, `write_check.status == not_run`, exit `0`
  - wrong password → `database_open` failed, still returns report, exit `1`
  - `--write-check` happy path → `write_check.status == passed`, probe absent
  - simulate cleanup failure if feasible (injectable delete failure) → `cleanup_failed`

- [ ] **Step 2: Implement runner** (port logic from `BlazeDoctor/main.swift` / REPL; **do not** include write probe unless `options.writeCheck`)

- [ ] **Step 3: PASS** → commit

```bash
git commit -m "$(cat <<'EOF'
feat(cli): add shared DoctorRunner with optional write-check cleanup

EOF
)"
```

---

### Task 5: `DoctorCLI` + `blazedb doctor` dispatch + help

**Files:**
- Create: `BlazeShell/Doctor/DoctorCLI.swift`
- Modify: `BlazedbCLI/BlazedbEntry.swift` (early in `main` argv switch, before treating argv as a DB path — see ~line 669)
- Modify: `BlazeShell/CLIHelp.swift` (`printGlobal`, add `printDoctor`)
- Modify: `BlazeDBCLITests/BlazeCLICoreTests.swift` (assert help strings contain doctor — existing pattern around doctor REPL help ~893)

**Interfaces:**
- Produces: `public enum DoctorCLI { public static func run(arguments: [String]) -> Int32 }`
  - Parses: `<db> [--json] [--report [path]] [--write-check] [--help]`
  - Resolves password via `DoctorPasswordResolver`
  - Builds `DoctorOptions`, runs `DoctorRunner`
  - `--json`: print sanitized JSON to stdout
  - `--report`: write file + footer (`Nothing was uploaded.`)
  - Human: readable checks without absolute paths (basename OK on terminal only)

**Help copy (required):**

Global `--help` includes:

```text
doctor    Check database health and generate a local diagnostic report
```

`blazedb doctor --help` examples:

```text
blazedb doctor my.db
blazedb doctor my.db --json
blazedb doctor my.db --report
blazedb doctor my.db --write-check
```

- [ ] **Step 1: Wire `if argv.first == "doctor"`** in `BlazedbEntry.swift` → `exit(DoctorCLI.run(...))`

- [ ] **Step 2: Update `CLIHelp.printGlobal`**

- [ ] **Step 3: Manual smoke**

```bash
swift build --product blazedb
.build/debug/blazedb doctor --help
.build/debug/blazedb --help | grep -i doctor
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(cli): wire blazedb doctor subcommand with help and report footer

EOF
)"
```

---

### Task 6: `BlazeDoctor` compatibility wrapper + REPL reuse

**Files:**
- Modify: `Package.swift` — `BlazeDoctor` dependencies: `["BlazeDBCore", "BlazeCLICore"]`
- Modify: `BlazeDoctor/main.swift` — replace inline report with:
  1. Print migration notice to stderr once:

```text
BlazeDoctor is now available through the main CLI:
  blazedb doctor <database>
```

  2. Parse legacy `BlazeDoctor <db> <password> [--json] [--report …] [--write-check]`
  3. Pass argv password into options **only here** (compat mode)
  4. Call `DoctorRunner` / `DoctorCLI` shared path
- Modify: `BlazeShell/BlazedbRepl.swift` — replace `buildDoctorReport` / `printDoctor` JSON path with shared runner; keep REPL UX, but JSON must be sanitized `DoctorReport`

- [ ] **Step 1: Update Package.swift dependency**

- [ ] **Step 2: Slim `BlazeDoctor/main.swift`**

- [ ] **Step 3: REPL uses `DoctorRunner`** with password already unlocked (no re-prompt)

- [ ] **Step 4: Build both**

```bash
swift build --target BlazeDoctor
swift build --product blazedb
swift test --filter Doctor
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(cli): route BlazeDoctor and REPL doctor through shared runner

EOF
)"
```

---

### Task 7: Discoverability (errors, README, templates, tours)

**Files:**
- Modify: `BlazeDB/Exports/BlazeDBError+Categories.swift` (line ~71)
- Modify: `BlazeDB/Exports/BlazeDBError+Suggestions.swift` (lines ~43, ~112)
- Modify: `BlazeDB/Exports/DatabaseHealth.swift` (line ~118)
- Modify: `README.md` (Troubleshooting near Start Here / install)
- Modify: `CONTRIBUTING.md`
- Modify: `Docs/Contributing/ISSUE_GUIDE.md`
- Modify: `.github/ISSUE_TEMPLATE/bug_report.md`
- Modify: `Docs/Architecture/TOURS/06_CLI.md`
- Modify: `Docs/Tools/BLAZEDOCTOR_DOCUMENTATION.md`
- Modify: `Docs/Architecture/CODEBASE_MAP.md`
- Optional same PR: `Docs/Guides/CLI_REFERENCE.md` if it still contradicts

**Error suggestion text (stable):**

```text
Database could not be opened.
Run:
  blazedb doctor <database>
For a shareable local report:
  blazedb doctor <database> --report
```

(Use a generic `<database>` placeholder in library strings if the concrete path must not be echoed; CLI open failures may substitute basename only.)

**Bug template addition:**

```markdown
## Diagnostics (optional)

If you can open or point at the database file safely:

1. Run `blazedb doctor <db> --report`
2. Review the JSON (no secrets / paths should be present)
3. Attach the file to this issue

Nothing is uploaded by BlazeDB; you choose what to attach.
```

**README Troubleshooting (short):**

```markdown
## Troubleshooting

Run a local health check:

\`\`\`bash
blazedb doctor path/to/database.blaze
\`\`\`

Generate a sanitized report you can attach to a GitHub issue:

\`\`\`bash
blazedb doctor path/to/database.blaze --report
\`\`\`

Nothing is uploaded automatically.
```

- [ ] **Step 1: Apply doc/help/error edits**

- [ ] **Step 2: Assert suggestion strings in a small unit test** if one already covers `BlazeDBError` suggestions; else add `BlazeDBCLITests` or Tier1 string assert sparingly

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs: make blazedb doctor discoverable from help, errors, and issue templates

EOF
)"
```

---

### Task 8: Acceptance gate + #259/#300 hygiene

- [ ] **Step 1: Run focused tests**

```bash
swift test --filter Doctor
swift test --filter BlazeCLICoreTests
```

- [ ] **Step 2: Manual acceptance checklist** (from design + discoverability)

  - [ ] `blazedb --help` lists doctor
  - [ ] `blazedb doctor --help` shows examples
  - [ ] `--json` and `--report` identical schema; `upload: false`
  - [ ] Existing report path → exit `64`
  - [ ] Non-interactive without password → exit `64`, no hang
  - [ ] Write-check cleanup failure → failed status
  - [ ] `BlazeDoctor` prints migration notice and still works
  - [ ] Bug template / README / tour updated

- [ ] **Step 3: Comment on #300** with terminal transcript excerpt; link plan + design. Note #259: doctor honesty path is now “wire subcommand” (docs-only path obsolete for doctor).

- [ ] **Step 4: Do not cut RELEASE.md until the change is on the release train**; when shipping, add CHANGELOG/RELEASE bullets and optionally a short terminal GIF on #300.

---

## Exit code mapping (implementer cheat sheet)

| Situation | Exit |
|-----------|------|
| All checks passed or warnings only | `0` |
| Any failed check / write-check cleanup failed | `1` |
| Report write I/O failure after checks | `1` |
| Bad argv, missing db arg, `--help` only is `0` | `64` for bad usage; `0` for help |
| Report destination exists | `64` |
| Parent dir missing | `64` |
| Non-interactive, no `BLAZEDB_PASSWORD` | `64` |

---

## Spec coverage self-check

| Spec item | Task |
|-----------|------|
| Shared runner / sanitized model | 1, 4 |
| `--json` == `--report` model | 5 |
| Read-only + `--write-check` + cleanup | 4 |
| Password order + non-interactive fail | 3, 5 |
| Report path default/explicit/parent/exists/atomic | 2, 5 |
| No overwrite v1 | 2 |
| Exit 0/1/64 | 4, 5 |
| BlazeDoctor + REPL | 6 |
| Discoverability | 5, 7 |
| Golden + redaction tests | 1 |
| No Core networking / no upload | Global + 1 |

---

## Out of scope (do not implement in #300)

- `doctor --share` upload
- Ambient telemetry
- `--overwrite`
- Basename hashing
- Wiring `dump` / `info` as `blazedb` subcommands (still separate; #259 remainder / #290)
