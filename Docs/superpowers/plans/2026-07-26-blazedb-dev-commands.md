# BlazeDB `dev` Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repo-gated `blazedb dev` commands for tiers, focused tests, and discovered experiments, with conditional help and real child exit-code propagation.

**Architecture:** Resolve `repositoryRoot` once in `BlazedbEntry`, pass it into `CLIHelp` and `DeveloperCommands`. Built-in workflows live in `BlazeShell/DeveloperCommands.swift` (`BlazeCLICore`); experiments are discovered from `Experiments/*/experiment.json` with path/symlink/name safety rules. Focused tests use `swift test --filter`; full tiers call existing `Scripts/run-tierN.sh`.

**Tech Stack:** Swift 6 / SwiftPM, Foundation `Process`, XCTest (`BlazeDB_CLITests`), existing `CLIHelp` / `CLIColors`.

## Global Constraints

- Only expose `dev` when both `Package.swift` and `Scripts/run-tier0.sh` (regular file) exist after upward walk from cwd.
- Resolve repository root once per invocation; pass `URL?` through.
- `DeveloperCommands.run(...) throws -> Int32` — propagate child exit codes unchanged; use `1` only for CLI/usage/validation failures.
- `dev test` defaults to Tier 0 via `BLAZEDB_TEST_SCOPE=tier0`; do not modify tier scripts for `--filter`.
- Experiments: scan only `Experiments/*/experiment.json`; name `^[a-z0-9][a-z0-9-]*$`; dir name must match; reject duplicate names entirely; resolve symlinks and require final path inside repo; declared executable must exist, be a regular file, and be executable.
- `dev experiments` with no manifests → exit `0` + point to `Experiments/README.md`.
- `swift test list`: capture stdout; inherit stderr.
- Scaffold-only: `Experiments/README.md`, no runnable example experiment.
- Do not open PRs or push unless the user asks; commit only when the user asks (plan steps may stage commit messages for later).

## File structure

| File | Responsibility |
|---|---|
| `BlazeShell/DeveloperCommands.swift` | Root discovery, dispatch, tiers, tests, experiments |
| `BlazeShell/CLIHelp.swift` | Conditional global Developer block + full `printDeveloper` |
| `BlazedbCLI/BlazedbEntry.swift` | Early `help`/`dev` dispatch, exit-code wiring |
| `BlazeDBCLITests/DeveloperCommandsTests.swift` | Unit tests for pure helpers + discovery |
| `Experiments/README.md` | Contributor docs for adding experiments |

---

### Task 1: Repository root discovery (TDD)

**Files:**
- Create: `BlazeShell/DeveloperCommands.swift`
- Create: `BlazeDBCLITests/DeveloperCommandsTests.swift`
- Test: `BlazeDB_CLITests` (path `BlazeDBCLITests`)

**Interfaces:**
- Produces: `public enum DeveloperCommands` with `public static func findRepositoryRoot(startingAt: URL = ...) -> URL?`

- [ ] **Step 1: Write failing tests for root discovery**

```swift
import XCTest
@testable import BlazeCLICore

final class DeveloperCommandsTests: XCTestCase {
    func testFindRepositoryRootReturnsNilWithoutMarkers() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dev-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertNil(DeveloperCommands.findRepositoryRoot(startingAt: tmp))
    }

    func testFindRepositoryRootFindsMarkersInParent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dev-root-\(UUID().uuidString)", isDirectory: true)
        let child = root.appendingPathComponent("nested/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: scripts.appendingPathComponent("run-tier0.sh"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let found = DeveloperCommands.findRepositoryRoot(startingAt: child)
        XCTAssertEqual(found?.standardizedFileURL.path, root.standardizedFileURL.path)
    }

    func testFindRepositoryRootRejectsDirectoryNamedRunTier0() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dev-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let fake = root.appendingPathComponent("Scripts/run-tier0.sh", isDirectory: true)
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(DeveloperCommands.findRepositoryRoot(startingAt: root))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter DeveloperCommandsTests
```

Expected: FAIL (type/method missing) or compile error for missing `DeveloperCommands`.

- [ ] **Step 3: Implement `findRepositoryRoot`**

In `BlazeShell/DeveloperCommands.swift`:

```swift
import Foundation

public enum DeveloperCommands {
    public static func findRepositoryRoot(
        startingAt start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        var current = start.standardizedFileURL
        let fm = FileManager.default
        while true {
            let package = current.appendingPathComponent("Package.swift")
            let tier0 = current.appendingPathComponent("Scripts/run-tier0.sh")
            var isDir: ObjCBool = false
            let tier0IsFile = fm.fileExists(atPath: tier0.path, isDirectory: &isDir) && !isDir.boolValue
            if fm.fileExists(atPath: package.path) && tier0IsFile {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
```

Note: On Linux, `ObjCBool` may need `#if canImport(ObjectiveC)` — if the codebase already uses a portable `isDirectory` pattern elsewhere in `BlazeShell`, match that pattern instead of inventing a new one.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter DeveloperCommandsTests
```

Expected: PASS for the three root tests.

- [ ] **Step 5: Commit** (only if user requested commits)

```bash
git add BlazeShell/DeveloperCommands.swift BlazeDBCLITests/DeveloperCommandsTests.swift
git commit -m "$(cat <<'EOF'
Add repo-root discovery for blazedb developer commands.

EOF
)"
```

---

### Task 2: Entry dispatch, exit codes, and conditional help

**Files:**
- Modify: `BlazedbCLI/BlazedbEntry.swift` (top of `main`, before picker/DB open)
- Modify: `BlazeShell/CLIHelp.swift`
- Modify: `BlazeShell/DeveloperCommands.swift`
- Modify: `BlazeDBCLITests/BlazeCLICoreTests.swift` (source-guard for Developer help strings) and/or `DeveloperCommandsTests.swift`

**Interfaces:**
- Consumes: `findRepositoryRoot() -> URL?`
- Produces:
  - `DeveloperCommands.run(arguments: [String], repositoryRoot: URL?) throws -> Int32`
  - `CLIHelp.printGlobal(includesDeveloperCommands: Bool = false)`
  - `CLIHelp.printDeveloper(experiments: [DeveloperExperiment] = [])`

- [ ] **Step 1: Extend `CLIHelp.printGlobal` and add `printDeveloper`**

Change signature to:

```swift
public static func printGlobal(includesDeveloperCommands: Bool = false)
```

When `includesDeveloperCommands` is true, append:

```
Developer
  dev help                 Show repository developer commands
  dev tiers                List test tiers and runners
  dev tests [search]       Find tests by name
  dev test <filter>        Run one focused test
  dev experiments          List repository experiments
  dev experiment <name>    Run a discovered experiment
```

Add `printDeveloper(experiments:)` with examples from the spec and either listed experiments or a one-line pointer to `Experiments/README.md`.

- [ ] **Step 2: Stub `run` for help / missing root**

```swift
public static func run(arguments: [String], repositoryRoot: URL?) throws -> Int32 {
    guard let repositoryRoot else {
        FileHandle.standardError.write(Data(
            "Developer commands are available inside a BlazeDB repository checkout.\n".utf8
        ))
        return 1
    }
    let sub = arguments.first ?? "help"
    switch sub {
    case "help", "--help", "-h":
        CLIHelp.printDeveloper(experiments: [])
        return 0
    default:
        FileHandle.standardError.write(Data(
            "Unknown developer command: \(sub)\nTry `blazedb dev help`.\n".utf8
        ))
        return 1
    }
}
```

(Experiments list in help will be filled in Task 5.)

- [ ] **Step 3: Wire `BlazedbEntry.main` early dispatch**

Near the top of `main()`, after `argv` is built:

```swift
let repositoryRoot = DeveloperCommands.findRepositoryRoot()

if argv.first == "help" || argv.first == "--help" || argv.first == "-h" {
    CLIHelp.printGlobal(includesDeveloperCommands: repositoryRoot != nil)
    return
}

if argv.first == "dev" {
    do {
        let code = try DeveloperCommands.run(
            arguments: Array(argv.dropFirst()),
            repositoryRoot: repositoryRoot
        )
        exit(code)
    } catch {
        writeStderrLine("💥 \(error.localizedDescription)")
        exit(1)
    }
}
```

Remove or replace the existing `--help`/`-h` block so it does not double-handle. Ensure this runs **before** any picker / DB open logic.

Update `printHelp()` helper if present to call `printGlobal(includesDeveloperCommands: repositoryRoot != nil)` — or inline and delete the thin wrapper.

- [ ] **Step 4: Add source-guard test for Developer help**

```swift
func testGlobalHelpIncludesConditionalDeveloperBlockSource() throws {
    let helpURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("BlazeShell/CLIHelp.swift")
    let source = try String(contentsOf: helpURL, encoding: .utf8)
    XCTAssertTrue(source.contains("includesDeveloperCommands"))
    XCTAssertTrue(source.contains("dev help"))
    XCTAssertTrue(source.contains("dev experiments"))
}
```

- [ ] **Step 5: Verify outside-repo behavior manually**

```bash
cd /tmp && swift run --package-path /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB blazedb --product BlazedbCLI -- help 2>/dev/null | head
# or build then:
cd /tmp && /path/to/.build/debug/blazedb help
cd /tmp && /path/to/.build/debug/blazedb dev; echo exit:$?
```

Expected: no Developer section; `dev` prints checkout message on stderr and exits `1`.

From repo root: `blazedb help` shows Developer block; `blazedb dev help` prints full help.

- [ ] **Step 6: Commit** (if user requested)

```bash
git add BlazedbCLI/BlazedbEntry.swift BlazeShell/CLIHelp.swift BlazeShell/DeveloperCommands.swift BlazeDBCLITests
git commit -m "$(cat <<'EOF'
Wire blazedb help/dev dispatch with conditional developer help.

EOF
)"
```

---

### Task 3: Tier listing and full tier runners

**Files:**
- Modify: `BlazeShell/DeveloperCommands.swift`
- Modify: `BlazeShell/CLIHelp.swift` (examples already cover tiers)

**Interfaces:**
- Produces: `listTiers() -> Int32`, `runTierScript(tier: Int, repositoryRoot: URL) throws -> Int32`
- Shared helper: `runInheritedProcess(executable:arguments:currentDirectory:environment:) throws -> Int32`

- [ ] **Step 1: Implement tier table + script runner**

```swift
public static func listTiers() -> Int32 {
    let rows: [(Int, String, String)] = [
        (0, "Fast local correctness", "Scripts/run-tier0.sh"),
        (1, "PR correctness gate", "Scripts/run-tier1.sh"),
        (2, "Integration/recovery", "Scripts/run-tier2.sh"),
        (3, "Stress/destructive", "Scripts/run-tier3.sh"),
    ]
    for (tier, summary, path) in rows {
        print("Tier \(tier)  \(summary)    \(path)")
    }
    return 0
}

static func runTierScript(tier: Int, repositoryRoot: URL) throws -> Int32 {
    let relative = "Scripts/run-tier\(tier).sh"
    let script = repositoryRoot.appendingPathComponent(relative)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: script.path, isDirectory: &isDir), !isDir.boolValue else {
        FileHandle.standardError.write(Data("Missing tier script: \(relative)\n".utf8))
        return 1
    }
    return try runInheritedProcess(
        executable: script.path,
        arguments: [],
        currentDirectory: repositoryRoot,
        environment: ProcessInfo.processInfo.environment
    )
}
```

Wire in `run`:

- `tiers` → `listTiers()`
- `tier0`…`tier3` → `runTierScript`

- [ ] **Step 2: Implement `runInheritedProcess`**

Use `Process`: set `executableURL`, `arguments`, `currentDirectoryURL`, `environment`; leave standardOutput/standardError as nil (inherit); `waitUntilExit()`; return `terminationStatus`.

- [ ] **Step 3: Smoke-check listing**

From repo root:

```bash
swift build --product BlazedbCLI
.build/debug/blazedb dev tiers
```

Expected: four lines matching the spec table.

- [ ] **Step 4: Commit** (if user requested)

```bash
git add BlazeShell/DeveloperCommands.swift
git commit -m "$(cat <<'EOF'
Add blazedb dev tiers and tier0–tier3 script runners.

EOF
)"
```

---

### Task 4: `dev tests` / `dev test` with `DiscoveredTest`

**Files:**
- Modify: `BlazeShell/DeveloperCommands.swift`
- Modify: `BlazeDBCLITests/DeveloperCommandsTests.swift`

**Interfaces:**
- Produces:

```swift
public struct DiscoveredTest: Equatable {
    public let rawIdentifier: String
    public let displayName: String
}

public static func parseTestListLine(_ line: String) -> DiscoveredTest?
public static func filterTests(_ tests: [DiscoveredTest], matching search: String?) -> [DiscoveredTest]
```

- [ ] **Step 1: Write failing parse/filter tests**

```swift
func testParseTestListLineStripsTargetAndParens() {
    let line = "BlazeDB_Tier0.BPlusTreeNodeTests/createsSimpleTree()"
    let parsed = DeveloperCommands.parseTestListLine(line)
    XCTAssertEqual(parsed?.rawIdentifier, line)
    XCTAssertEqual(parsed?.displayName, "BPlusTreeNodeTests.createsSimpleTree")
}

func testParseTestListLineSkipsNoise() {
    XCTAssertNil(DeveloperCommands.parseTestListLine(""))
    XCTAssertNil(DeveloperCommands.parseTestListLine("Building for debugging..."))
}

func testFilterTestsMatchesDisplayOrRawCaseInsensitive() {
    let tests = [
        DiscoveredTest(
            rawIdentifier: "BlazeDB_Tier0.BPlusTreeNodeTests/createsSimpleTree()",
            displayName: "BPlusTreeNodeTests.createsSimpleTree"
        )
    ]
    XCTAssertEqual(DeveloperCommands.filterTests(tests, matching: "bplus").count, 1)
    XCTAssertEqual(DeveloperCommands.filterTests(tests, matching: "nope").count, 0)
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter DeveloperCommandsTests
```

- [ ] **Step 3: Implement parse/filter + list/run**

`parseTestListLine`:
- trim
- require something that looks like `Type/method` or `Target.Type/method`
- `rawIdentifier` = trimmed line (or identifier token)
- `displayName` = drop leading `BlazeDB_Tier0.` / other `BlazeDB_TierN.` prefixes if present; replace `/` with `.`; strip trailing `()`

`listTests(matching:repositoryRoot:)`:
- `Process` with `/usr/bin/env`, `["swift","test","list"]`
- `environment` = process env + `BLAZEDB_TEST_SCOPE=tier0`
- `standardOutput = Pipe()`; leave `standardError` nil (inherit)
- parse lines → filter → print UX from spec
- 0 matches → message, return `1`
- list process failure → return child `terminationStatus`

`runTest(filter:repositoryRoot:)`:
- inherit both streams
- args: `swift test --filter <filter>`
- env includes `BLAZEDB_TEST_SCOPE=tier0`
- return child status

Wire `tests` / `test` in `run`. Missing filter on `test` → usage, return `1`.

- [ ] **Step 4: Run unit tests — expect PASS**

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter DeveloperCommandsTests
```

- [ ] **Step 5: Optional local smoke** (not required in CI)

```bash
.build/debug/blazedb dev tests bplus
.build/debug/blazedb dev test BPlusTreeNodeTests.createsSimpleTree
```

- [ ] **Step 6: Commit** (if user requested)

```bash
git add BlazeShell/DeveloperCommands.swift BlazeDBCLITests/DeveloperCommandsTests.swift
git commit -m "$(cat <<'EOF'
Add blazedb dev tests discovery and focused Tier 0 test runs.

EOF
)"
```

---

### Task 5: Experiment discovery + run (safety rules)

**Files:**
- Modify: `BlazeShell/DeveloperCommands.swift`
- Modify: `BlazeDBCLITests/DeveloperCommandsTests.swift`
- Modify: `BlazeShell/CLIHelp.swift` / `run` help path to pass discovered experiments

**Interfaces:**
- Produces:

```swift
public struct DeveloperExperiment: Decodable, Equatable {
    public let name: String
    public let summary: String
    public let command: String
}

public static func discoverExperiments(repositoryRoot: URL) throws -> [DeveloperExperiment]
public static func isValidExperimentName(_ name: String) -> Bool
public static func resolvedExecutableURL(command: String, repositoryRoot: URL) -> URL?
```

- [ ] **Step 1: Write failing discovery/safety tests**

Cover at least:
1. Valid manifest with matching dir name is discovered
2. Invalid name (e.g. `BTree`) skipped
3. Dir name ≠ manifest name skipped
4. Two dirs somehow claiming same name → both rejected (simulate by writing two JSON files under differently named dirs that both claim `"name":"dup"` — expect neither in result + you can assert warnings separately if you capture stderr; at minimum assert empty for that name)
5. Absolute command rejected
6. Symlink escaping repo rejected (`resolvedExecutableURL` returns nil)
7. `isValidExperimentName("btree-search") == true`, `"1bad"` / `"-x"` / `"Upper"` false as appropriate for `^[a-z0-9][a-z0-9-]*$`

Use a temp repo root with `Experiments/<name>/experiment.json`.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter DeveloperCommandsTests
```

- [ ] **Step 3: Implement discovery + run**

Discovery algorithm:
1. If `Experiments/` missing → return `[]`
2. Enumerate immediate subdirectories
3. Read `experiment.json`; decode `DeveloperExperiment`
4. Validate name regex; dir lastPathComponent == name; command relative (no absolute, no empty)
5. Resolve command’s first token against repo root; `resolvingSymlinksInPath()`; ensure `resolved.path.hasPrefix(repositoryRoot.standardizedFileURL.path + "/")` or equal
6. Collect candidates; group by name; if count > 1 for a name, warn each path on stderr and **omit all** of that name
7. Sort unique survivors by name

`listExperiments`:
- if empty: print pointer to `Experiments/README.md`, return `0`
- else print name + summary, return `0`

`runExperiment(name:forwardedArgs:repositoryRoot:)`:
- find in discovered set or error + return `1`
- split command on whitespace; first token = executable relative path
- resolve + symlink check again
- require exists, regular file, executable (`FileManager.isExecutableFile`)
- append args after `--`
- inherit stdio; return child status

Wire `experiments` / `experiment` in `run`. Update `dev help` to call `discoverExperiments` and pass into `CLIHelp.printDeveloper`.

- [ ] **Step 4: Run tests — expect PASS**

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter DeveloperCommandsTests
```

- [ ] **Step 5: Commit** (if user requested)

```bash
git add BlazeShell/DeveloperCommands.swift BlazeShell/CLIHelp.swift BlazeDBCLITests/DeveloperCommandsTests.swift
git commit -m "$(cat <<'EOF'
Add discovered blazedb experiment commands with path safety checks.

EOF
)"
```

---

### Task 6: Experiments scaffold README + final wiring polish

**Files:**
- Create: `Experiments/README.md`
- Modify: `BlazeShell/DeveloperCommands.swift` / `CLIHelp.swift` only if copy still drifts from spec

- [ ] **Step 1: Write `Experiments/README.md`**

Content must include (from approved design):

```markdown
# BlazeDB Experiments

Experiments are repository-local developer workflows discovered by:

```bash
blazedb dev experiments
```

Each experiment lives in its own directory:

```text
Experiments/<name>/
  experiment.json
  run.sh
```

Example manifest:

```json
{
  "name": "btree-search",
  "summary": "Run experimental B+ tree search checks",
  "command": "./Experiments/btree-search/run.sh"
}
```

Run it with:

```bash
blazedb dev experiment btree-search
```

Forward arguments with:

```bash
blazedb dev experiment btree-search -- --records 10000
```

## Rules

* Directory name must match the manifest `name`
* `name` must match `[a-z0-9][a-z0-9-]*`
* Commands must be relative to the repository root
* After resolving symlinks, the executable must stay inside the repository
* The declared executable must exist, be a regular file, and be executable
* Duplicate names are rejected
* Experiments are not tests; use `blazedb dev test` for tests
```

(Fix markdown fence nesting carefully when writing the real file.)

- [ ] **Step 2: Verify empty experiments UX**

```bash
.build/debug/blazedb dev experiments; echo exit:$?
```

Expected: exit `0`, points at `Experiments/README.md`.

- [ ] **Step 3: Full CLITests filter run**

```bash
BLAZEDB_TEST_SCOPE=tier0 swift test --filter BlazeDB_CLITests
```

Expected: PASS (or only pre-existing failures unrelated to this work — fix any new ones).

- [ ] **Step 4: Commit** (if user requested)

```bash
git add Experiments/README.md BlazeShell BlazedbCLI BlazeDBCLITests docs/superpowers
git commit -m "$(cat <<'EOF'
Scaffold Experiments docs and finish blazedb developer command surface.

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| One-shot root discovery + file check | 1 |
| Early help/dev dispatch, conditional global help | 2 |
| Exit code propagation via `run -> Int32` | 2–5 |
| `tiers` / `tier0`–`tier3` via scripts | 3 |
| `DiscoveredTest` + tolerant list parse | 4 |
| stdout capture / stderr inherit for list | 4 |
| Focused `swift test --filter` Tier 0 | 4 |
| Experiment discovery + name regex | 5 |
| Duplicate name rejection | 5 |
| Symlink resolve + stay in repo | 5 |
| Executable must exist / regular / executable | 5 |
| Empty experiments exit 0 + README pointer | 5–6 |
| `Experiments/README.md` scaffold only | 6 |

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-26-blazedb-dev-commands.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with checkpoints  

Which approach?
