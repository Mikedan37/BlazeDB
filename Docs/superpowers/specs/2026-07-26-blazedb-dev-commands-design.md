# BlazeDB `dev` commands — design

Date: 2026-07-26  
Status: approved (post-review)

## Goal

Add a **repo-aware** contributor surface to the global `blazedb` CLI so developers can discover and run tests, tiers, and local experiments without memorizing SwiftPM env vars or script paths.

End users of an installed CLI never see this surface unless they are inside a BlazeDB checkout.

## Non-goals (v1)

- Extending tier scripts with `--filter`
- `--tier` flag on `dev test` (default Tier 0 only)
- Auto-discovering arbitrary scripts outside `Experiments/`
- Shipping a runnable example experiment
- Changing CI or the authoritative `Scripts/run-tierN.sh` behavior

## Repository gate

**Centralized discovery** (resolve once per invocation in `BlazedbEntry`):

```swift
let repositoryRoot = DeveloperCommands.findRepositoryRoot()
```

`findRepositoryRoot() -> URL?`:

1. Start at `FileManager.default.currentDirectoryPath`
2. Canonicalize with `standardizedFileURL`
3. Accept a directory only if it contains:
   - `Package.swift`
   - `Scripts/run-tier0.sh` **as a regular file** (not merely path existence)
4. Walk to parent; stop when `parent == current`
5. Return `nil` if none found

Pass `repositoryRoot` into help and `DeveloperCommands.run` — do not rediscover mid-invocation.

### Outside checkout

| Surface | Behavior |
|---|---|
| `blazedb --help` / `help` | Omit Developer section entirely |
| `blazedb dev …` | stderr: `Developer commands are available inside a BlazeDB repository checkout.` · non-zero exit |

### Inside checkout

Developer commands available; global help shows a compact Developer block.

## Architecture

```
BlazedbEntry
  → resolve repositoryRoot once
  → dispatch "dev" / "help" early (before picker / DB open)
DeveloperCommands (BlazeShell → BlazeCLICore)
  → execute built-in + discovered workflows
CLIHelp
  → printGlobal(includesDeveloperCommands:)
  → printDeveloper(experiments:) for full `dev help`
```

New file: `BlazeShell/DeveloperCommands.swift` (included via existing `path: "BlazeShell"` for `BlazeCLICore` — no Package.swift path change required).

Reuse existing helpers where possible: `CLIColors` / `CLIHelp` patterns, `Process` for subprocesses, stderr write helper style already in entry.

Keep `DeveloperCommands` modular:

| Responsibility | API sketch |
|---|---|
| Dispatch | `run(arguments:repositoryRoot:) throws -> Int32` |
| Root detection | `findRepositoryRoot() -> URL?` |
| Tiers | `listTiers()`, `runTierScript(tier:root:) throws -> Int32` |
| Tests | `listTests(matching:root:) throws -> Int32`, `runTest(filter:root:) throws -> Int32` |
| Experiments | `discoverExperiments(root:) throws -> [DeveloperExperiment]`, `listExperiments(root:) throws -> Int32`, `runExperiment(name:args:root:) throws -> Int32` |
| Help | delegate to `CLIHelp.printDeveloper(experiments:)` |

Avoid a giant switch that mixes process I/O with formatting — parse subcommand once, call focused helpers.

### Exit-code propagation

`DeveloperCommands.run` returns `Int32`. Callers in `BlazedbEntry` must `exit(code)` with that value (or `exit(1)` only for thrown CLI/usage errors that never reached a child process).

| Outcome | Exit code |
|---|---|
| Successful built-in listing / help | `0` |
| CLI usage / validation / unknown subcommand / no repo | `1` |
| `dev tests` with zero matches | `1` |
| Child process (`swift test`, tier script, experiment) | **child’s termination status unchanged** |

Do not collapse child failures to `1`. If the child exits `42`, `blazedb` exits `42`.

## Command surface (v1)

### Built-in

| Command | Behavior |
|---|---|
| `blazedb help` / `--help` / `-h` | Global help; Developer block iff root ≠ nil |
| `blazedb dev` / `dev help` | Full developer workflow help |
| `blazedb dev tiers` | Print tier 0–3 table + script paths |
| `blazedb dev tier0` … `tier3` | Run `Scripts/run-tierN.sh` unchanged, cwd = repo root |
| `blazedb dev tests [search]` | List Tier 0 tests; optional case-insensitive substring filter |
| `blazedb dev test <filter>` | Focused run via `swift test --filter` |

### Discovered

| Command | Behavior |
|---|---|
| `blazedb dev experiments` | List `Experiments/*/experiment.json` |
| `blazedb dev experiment <name>` | Run declared command from repo root |
| `blazedb dev experiment <name> -- <args…>` | Forward args after `--` |

## Help UX

### Global (inside checkout only)

```
Developer
  dev help                 Show repository developer commands
  dev tiers                List test tiers and runners
  dev tests [search]       Find tests by name
  dev test <filter>        Run one focused test
  dev experiments          List repository experiments
  dev experiment <name>    Run a discovered experiment
```

### `blazedb dev help`

Explain workflows with examples:

```
blazedb dev tiers
blazedb dev tests BPlusTree
blazedb dev test BPlusTreeNodeTests.createsSimpleTree
blazedb dev tier0
blazedb dev experiments
blazedb dev experiment btree-search -- --records 10000
```

Include an **Experiments** section populated at runtime from discovery. If none found, print a one-line pointer to `Experiments/README.md` (do not invent fake entries).

## Test listing and focused run

### Discovered test model

Parsing must be tolerant of SwiftPM list noise. Keep both forms:

```swift
struct DiscoveredTest {
    let rawIdentifier: String   // as listed, e.g. BlazeDB_Tier0.BPlusTreeNodeTests/createsSimpleTree()
    let displayName: String     // friendly, e.g. BPlusTreeNodeTests.createsSimpleTree
}
```

- `displayName`: strip known target prefixes (`BlazeDB_Tier0.` etc.), convert `/` to `.`, strip trailing `()`
- `rawIdentifier`: preserve the original line token used for filtering when useful; `dev test` still accepts the human filter form (`Type.method`)
- Skip blank lines and lines that do not look like test identifiers (no hard crash on banner/noise)

### `dev tests [search]`

1. Run at repo root with env `BLAZEDB_TEST_SCOPE=tier0`:
   - executable `/usr/bin/env`, args `["swift", "test", "list"]`
   - set env via `process.environment`, not as argv
2. **Capture stdout** for parsing; **stderr remains inherited/visible** (do not pipe stderr away)
3. Parse lines into `[DiscoveredTest]`; filter case-insensitively on both `rawIdentifier` and `displayName` when search is provided
4. Print:

```
Found N matching test(s):
  TypeName.methodName
Run:
  blazedb dev test TypeName.methodName
```

5. Zero matches → clear message, exit `1`
6. If the list process itself fails → propagate **child exit code**

### `dev test <filter>`

```
BLAZEDB_TEST_SCOPE=tier0 swift test --filter <filter>
```

- cwd = repository root
- inherit stdout/stderr
- exit code = child exit code
- **v1 default = Tier 0 only** (no `--tier` yet)

### Full tiers

`dev tierN` runs `./Scripts/run-tierN.sh` with inherited stdio — CI-aligned source of truth. Do not reimplement coverage/durability gates in Swift. Propagate child exit code.

## Experiments discovery

### Layout (v1 scaffold)

```
Experiments/
  README.md
```

No runnable example in v1.

### Manifest

`Experiments/<name>/experiment.json`:

```json
{
  "name": "btree-search",
  "summary": "Run experimental B+ tree search checks",
  "command": "./Experiments/btree-search/run.sh"
}
```

```swift
struct DeveloperExperiment: Decodable {
    let name: String
    let summary: String
    let command: String
}
```

### Name validation

Experiment `name` (and therefore directory name) must match:

```
^[a-z0-9][a-z0-9-]*$
```

Invalid names → skip + warn on stderr.

### Rules

1. Scan only `Experiments/*/experiment.json`
2. Directory name **must** equal `name` — else skip + warn on stderr
3. `name` must match `^[a-z0-9][a-z0-9-]*$` — else skip + warn
4. `command` must be **repository-relative** (reject absolute paths)
5. Resolve the declared executable path and **symlinks**, then verify the **final resolved path stays inside the repository root** — else skip at discovery / fail at run with a clear error
6. At run time, the declared executable **must exist, be a regular file, and be executable** — else fail with a clear message (do not “prefer” a conventional `run.sh`; enforce whatever path the manifest declares)
7. Experiments are **not** tests — `dev test` remains the test path
8. Sort discovered experiments by `name` after validation

### Duplicate names

If two or more manifests resolve to the same `name` (should be rare given dir==name, but possible via symlink/dir tricks or bad data):

- Emit a warning for each conflicting path on stderr
- **Reject all duplicates** — none of the conflicting names appear in the runnable set
- Other uniquely named experiments still load normally

### `dev experiments` empty state

When no valid manifests are found:

- exit `0`
- print a short message pointing at `Experiments/README.md`
- do not invent fake entries

### Execution

- Parse `command` into executable + argv (simple whitespace split is acceptable for v1 if commands stay simple `./path/run.sh` forms; document that complex shell quoting is not supported — use a script)
- Resolve executable + symlinks; require final path inside repo; require regular file + executable bit
- Append forwarded args after `--`
- cwd = repository root
- inherit stdio; propagate **child exit code** unchanged

## Error handling

| Case | Behavior |
|---|---|
| No repo root + `dev` | stderr message, exit `1` |
| Unknown `dev` subcommand | stderr + `dev help` hint, exit `1` |
| `dev test` missing filter | usage, exit `1` |
| `dev tests` no matches | message, exit `1` |
| `swift test list` / `swift test` / tier script / experiment child fails | **propagate child exit code** |
| `dev experiments` with no manifests | message + pointer to README, exit `0` |
| Unknown experiment | stderr + suggest `dev experiments`, exit `1` |
| Invalid / skipped manifest | warn, continue discovery |
| Duplicate experiment names | warn each path; exclude all duplicates from the set |
| Path escapes repo (after symlink resolve) | reject, exit `1` at run (or skip at discovery with warn) |
| Declared executable missing / not regular file / not executable | clear error, exit `1` |
| Tier script missing | clear error, exit `1` |

## Testing

Prefer small, fast unit-style checks in `BlazeDBCLITests` / existing CLI test target:

1. `findRepositoryRoot` — temp dirs with/without markers; parent walk; file-vs-directory for `run-tier0.sh`
2. `DiscoveredTest` parsing / filtering helpers (noise lines, prefixes, `()`)
3. Experiment discovery — name regex, dir==name, duplicates rejected, absolute/`..`/symlink escape rejected, executable checks
4. Help source assertions: conditional Developer strings present in `CLIHelp` when flag true (mirror existing help source tests)

Do not require a full `swift test list` integration in CI for v1 unless cheap; keep subprocess tests optional/local.

## Implementation order

1. `findRepositoryRoot` + entry dispatch (`dev`, `help`) + outside-repo behavior + exit-code wiring
2. `CLIHelp` conditional Developer block + `printDeveloper`
3. Built-in: `tiers`, `tier0`–`tier3` (propagate child codes)
4. Built-in: `tests` / `test` (`DiscoveredTest`, stdout capture + inherited stderr)
5. Experiments discovery + `experiments` / `experiment` (safety rules above)
6. `Experiments/README.md` scaffold
7. Unit tests for pure helpers + discovery

## Future (explicitly deferred)

- `blazedb dev test --tier 1 <filter>`
- `"enabled": false` in experiment manifests
- Richer command argv parsing / `args` array in JSON
- First real experiment (e.g. btree-search) when needed
