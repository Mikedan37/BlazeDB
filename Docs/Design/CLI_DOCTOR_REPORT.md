# CLI Doctor + Sanitized Local Report

**Status:** Approved design (not yet implemented)  
**Date:** 2026-07-26  
**Scope:** `blazedb doctor`, shared doctor runner, sanitized `--json` / `--report`  
**Non-goals:** Ambient telemetry, hosted upload, Core networking, `blazedb diagnostics` synonym

---

## Summary

Ship a real top-level `blazedb doctor` command that runs health checks offline and can write a **sanitized local JSON report** for attaching to GitHub issues. Nothing is uploaded. The embedded engine and normal app opens never transmit data.

This also resolves CLI honesty for doctor: public help and docs may advertise `blazedb doctor` once the subcommand exists. Standalone `BlazeDoctor` remains a thin compatibility wrapper until docs deprecate it.

---

## Product commands

| Invocation | Behavior |
|------------|----------|
| `blazedb doctor <db>` | Read-only checks → human terminal output → nothing uploaded |
| `blazedb doctor <db> --json` | Same checks → **sanitized** `DoctorReport` JSON on stdout |
| `blazedb doctor <db> --report` | Same checks → write **same** sanitized JSON to a file → print path + “Nothing was uploaded.” |
| `blazedb doctor <db> --report <path>` | Same as `--report`, with explicit output path |
| `blazedb doctor <db> --write-check` | Opt-in temporary write/read/delete probe (in addition to read-only checks) |
| `blazedb doctor --help` | Documented; also listed from global `blazedb --help` |

Flags combine as expected (`--report` with `--write-check`, `--json` with `--write-check`). `--json` and `--report` both emit the **identical** sanitized model; only the destination differs (stdout vs file).

Human terminal output may be richer (formatting, suggested actions) but must not print secrets, document keys/values, passwords, or full absolute paths. Prefer basename-only or “user-provided path” wording on the terminal.

### `--report` footer (required)

```
Diagnostic report written to:
./blazedb-diagnostics-2026-07-26T183015Z.json
Review the file before sharing it.
Nothing was uploaded.
```

---

## Trust and packaging boundaries

| Layer | Telemetry / report upload | Doctor |
|-------|---------------------------|--------|
| `BlazeDBCore` | Never | No networking; no report I/O beyond what public APIs already do |
| Public `BlazeDB` library | Never by default | Not in scope |
| `blazedb` CLI | No ambient telemetry in this design | Doctor + local report only |
| `BlazeDoctor` executable | N/A | Compatibility wrapper over shared runner |
| Future `doctor --share` | Deferred | Two-step generate → confirm → upload; **out of scope** |

Governing principle: **BlazeDB never transmits data merely because an application uses the database.**

---

## Architecture

Extract one reusable implementation in **`BlazeCLICore`** (`BlazeShell/`). Do not duplicate logic across entry points.

```text
BlazeCLICore
  DoctorRunning / DoctorRunner
  DoctorOptions
  DoctorReport          // Codable; sanitized by construction
  DoctorCheck
  DoctorWriteCheck
  DoctorStatus          // "ok" | "warnings" | "failed"

BlazedbCLI (blazedb doctor …)     → thin dispatch
BlazeDoctor/main.swift            → compatibility wrapper
BlazeShell REPL (doctor)          → same runner
```

`BlazeDoctor` adds a dependency on `BlazeCLICore` and calls the shared runner. Docs deprecate the standalone binary once `blazedb doctor` is stable.

Suggested shapes (illustrative, not mandated API names):

```swift
struct DoctorOptions {
    var databasePath: String
    var password: String
    var writeCheck: Bool
    var reportPath: URL?           // nil unless --report
    var outputFormat: DoctorOutputFormat  // human | json
}

struct DoctorReport: Codable { /* sanitized fields only */ }

protocol DoctorRunning {
    func run(options: DoctorOptions) throws -> DoctorRunResult
}
```

Sanitize **at the model boundary**. The Codable report type must not have fields for absolute paths, usernames, home directories, document keys, argv, env, or secrets. Do not rely on post-hoc string replacement as the primary control; a encode-time redaction pass is only a safety net for messages.

---

## Password resolution

Documented order for `blazedb doctor`:

1. **Secure interactive prompt** when stdin is a TTY
2. **`BLAZEDB_PASSWORD`** when stdin is **not** a TTY (automation / CI)
3. **Legacy argv password** only in the `BlazeDoctor` compatibility wrapper

If stdin is not interactive and `BLAZEDB_PASSWORD` is unset/empty: **fail immediately** with exit `64` and a useful message. Do not block waiting for a terminal that does not exist.

Do **not** record how the password was supplied in the report (no `password_source`, no env hints).

Note: environment variables can still leak via process inspection or CI logs; docs should prefer the prompt for interactive use and warn about env in shared runners.

---

## Read-only by default; explicit write probe

`blazedb doctor` runs **read-only** checks by default. It must not insert or delete records unless the user passes `--write-check`.

When `--write-check` is set, print before mutating:

```
Running temporary write check...
A probe record will be created and removed.
```

Acceptance sequence for `--write-check`:

1. Create probe record  
2. Read probe back  
3. Delete probe  
4. Verify probe is absent  

If create/read/delete fails → `write_check.status = "failed"` with a stable code (`write_check.insert_failed`, `write_check.read_failed`, `write_check.delete_failed`).  
If delete succeeds but the probe is still present → **overall report `status: "failed"`**, check code `write_check.cleanup_failed`. Doctor must not report healthy while leaving a diagnostic corpse in the database.

Report field:

```json
"write_check": {
  "requested": false,
  "status": "not_run"
}
```

Possible `write_check.status` values: `not_run` | `passed` | `failed` | `skipped` (e.g. database not open).

---

## Sanitized report schema (v1)

`schema_version` starts at **1**. Unknown future fields are allowed for forward compatibility. Required top-level fields are tested. Enum values are stable. Machine-readable fields must not depend on locale.

### Required top-level fields

| Field | Type | Notes |
|-------|------|--------|
| `schema_version` | Int | `1` |
| `report_id` | String (UUID) | Random per generation; not derived from path/hardware |
| `generated_at` | String | UTC ISO-8601 (`…Z`) |
| `upload` | Bool | Always `false` in this design |
| `status` | String | `ok` \| `warnings` \| `failed` |
| `blazedb_version` | String | Product / package version |
| `cli_version` | String | CLI identity (may match blazedb_version) |
| `platform` | String | e.g. `macos`, `linux` |
| `architecture` | String | e.g. `arm64`, `x86_64` |
| `swift_version` | String | Toolchain if known; else stable `"unknown"` |
| `path_scope` | String | `user-provided` \| `missing` \| `unreadable` |
| `database_open` | Bool | |
| `wal_status` | String | Stable enum; use `unknown` when APIs do not expose detail |
| `recovery_required` | Bool | |
| `write_check` | Object | See above |
| `checks` | Array | Structured checks |

Omit entirely in v1:

- Absolute paths
- Basename and basename hashes
- Usernames / home directory fragments
- Document keys or values
- Command arguments / environment variables
- Passwords, keys, salt material
- Repository names
- Password source

Use a random `report_id` so users can reference multiple reports without encoding filename shadows.

### Example

```json
{
  "schema_version": 1,
  "report_id": "550e8400-e29b-41d4-a716-446655440000",
  "generated_at": "2026-07-26T18:30:15Z",
  "upload": false,
  "status": "failed",
  "blazedb_version": "2.8.1",
  "cli_version": "2.8.1",
  "platform": "linux",
  "architecture": "x86_64",
  "swift_version": "6.2",
  "path_scope": "user-provided",
  "database_open": false,
  "wal_status": "unknown",
  "recovery_required": false,
  "write_check": {
    "requested": false,
    "status": "not_run"
  },
  "checks": [
    {
      "name": "database_open",
      "status": "failed",
      "code": "open.authentication_failed",
      "message": "Database could not be opened."
    }
  ]
}
```

### Check objects

| Field | Role |
|-------|------|
| `name` | Stable check id (`database_open`, `file_readable`, …) |
| `status` | `passed` \| `failed` \| `warning` \| `skipped` |
| `code` | Stable machine code (`open.authentication_failed`) |
| `message` | Human text; no paths, keys, or secrets |

`code` is for tools; `message` is for humans. Prefer category-mapped codes from existing error taxonomy where possible.

### Checks to implement (shared runner)

1. File exists / readable  
2. Permissions summary (mode bits only — not UID/username)  
3. Database open / decrypt  
4. Layout / count readable  
5. Health probe (read-only APIs)  
6. Monitoring snapshot if available  
7. Read path  
8. WAL / recovery signal when public APIs expose it; otherwise `unknown`  
9. Write/read/delete probe **only** if `--write-check`

Malformed or unopenable databases must still produce a report (or stdout JSON) rather than crash.

---

## Exit codes

Three-valued “warnings fail the shell” exit codes are intentionally **not** used. Warnings live in JSON `status`.

| Code | Meaning |
|------|---------|
| `0` | Checks completed (includes `status: "ok"` and `status: "warnings"`) |
| `1` | One or more failed checks (`status: "failed"`) |
| `64` | Invalid usage (missing args, bad flags, existing report path, missing parent directory, missing password in non-interactive mode) |

`--report` does not change the health exit code after a successful write. Failure to write the report file after checks ran is exit `1`. Path-policy / usage errors are exit `64`.

---

## Report file I/O

| Invocation | Output path |
|------------|-------------|
| `blazedb doctor db.blaze --report` | `./blazedb-diagnostics-<UTC-basic>.json` in the **current working directory** (example: `blazedb-diagnostics-2026-07-26T183015Z.json`) |
| `blazedb doctor db.blaze --report custom.json` | Exactly `custom.json` (relative to cwd unless absolute) |

Rules (v1):

- Parent directory of the destination **must already exist**; otherwise exit `64` with a clear message.
- If the destination file **already exists**: exit `64` with a clear failure. **No `--overwrite` flag in v1.** Never silently overwrite.
- Write via **temp file in the same directory as the destination** → flush → `fsync` if practical → **atomic `rename`** onto the final path (same-filesystem rename required for atomicity).
- Always set `"upload": false` in the file body.
- After success, print the footer with the relative or user-supplied path string and **Nothing was uploaded.**

---

## Relationship to existing tools

| Surface today | After this work |
|---------------|-----------------|
| Docs claim `blazedb doctor` but only REPL / `BlazeDoctor` exist (#259) | Wire real subcommand; update #259 acceptance to “subcommand exists” |
| `BlazeDoctor` embeds full `path` in JSON | Wrapper; sanitized model only |
| REPL `doctor` / `doctor --json` | Call shared runner; JSON path uses sanitized model |
| Ambient / hosted telemetry | Still deferred; local report only |

---

## Acceptance criteria

- [ ] `blazedb doctor` exists and appears in global `--help`
- [ ] Default doctor is read-only; write probe requires `--write-check`
- [ ] `--json` and `--report` emit the same sanitized `DoctorReport` schema
- [ ] `--report` prints the path and **Nothing was uploaded.**
- [ ] Report contains no absolute paths, home fragments, basenames, document keys/values, argv, env, or secrets
- [ ] Random `report_id`; `schema_version == 1`; `upload == false`
- [ ] `BlazeDoctor` and REPL doctor reuse the shared `BlazeCLICore` implementation
- [ ] Unopenable / missing DB still yields a report (or JSON) without crashing
- [ ] Exit codes: `0` / `1` / `64` as specified; warnings do not force exit `1`
- [ ] Atomic report writes; existing destination fails (no overwrite in v1); parent must exist
- [ ] `--write-check` verifies probe absent after delete; cleanup failure ⇒ `status: "failed"`
- [ ] Tests: redaction, required fields, stable enums/codes, one checked-in golden fixture, “nothing uploaded” footer / `upload: false`
- [ ] No networking added to Core or the doctor path
- [ ] Discoverability: global help, `doctor --help` examples, open-failure suggestions, README troubleshooting, CONTRIBUTING / ISSUE_GUIDE / bug template / CLI tour, `BlazeDoctor` migration notice, release notes when shipping

---

## Deferred

- `blazedb doctor --share` (generate → show summary → explicit confirm → upload)
- Anonymous CLI usage telemetry
- Crash report pipeline
- Basename or basename-hash correlation
- `--overwrite` for report files
- Deeper WAL/meta/orphan integrity walks (existing roadmap item)

---

## Implementation notes (non-normative)

- Prefer placing new types under `BlazeShell/Doctor/` (target `BlazeCLICore`) so CLI and REPL share them without pulling doctor I/O into `BlazeDBCore`.
- Map open failures through existing error categories to stable `code` strings.
- Keep golden fixture free of host-specific strings (versions may be stubbed in unit tests via injectable environment metadata).
- Implementation plan: [`CLI_DOCTOR_REPORT_PLAN.md`](CLI_DOCTOR_REPORT_PLAN.md)
