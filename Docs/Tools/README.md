# Tools

Use these **exact** status words everywhere (README, this map, issues). Do not invent synonyms like "available," "supported," or "companion" as status.

| Status | Meaning |
|--------|---------|
| **shipped** | In the default OSS package / documented product path; safe to tell users to run it |
| **beta** | Real code you can open; useful, incomplete; not a production support claim |
| **experimental** | CI-validated or engineering path; not a published consumer SDK |
| **in-tree, not packaged** | Sources or design docs exist in the repo; not a SwiftPM product / install path |
| **deferred** | Explicitly not part of the default OSS product right now |

## Tools map

| Tool | How to run | Role | Status |
|------|------------|------|--------|
| `blazedb` | `swift build --product blazedb` then `.build/debug/blazedb` | Interactive picker / REPL | **shipped** |
| `BlazeDoctor` | `swift run BlazeDoctor <db-path> <password>` | Health checks (separate executable, not a `blazedb` subcommand) | **shipped** |
| `BlazeDump` | `swift run BlazeDump <command> <args>` | Export / restore (separate executable) | **shipped** |
| `BlazeInfo` | `swift run BlazeInfo <db-path> <password>` | Quick snapshot (separate executable) | **shipped** |
| `./dev` | `./dev help` | Contributor tests, tiers, experiments, **benchmarks** (`dev bench`) | **shipped** |
| `./bench` | `./bench` / `./bench honesty` | Benchmark front door (payload / DB-size sweeps, publish) | **shipped** |
| `BlazeDBBenchmarks` | `swift run BlazeDBBenchmarks` or via `./bench` | Methodology workloads (not README vanity numbers) | **shipped** |
| [BlazeStudio](../../BlazeStudio/) | Open `BlazeStudio/BlazeStudio.xcodeproj` | macOS visual / browser aid | **beta** |
| [BlazeDBVisualizer](../../BlazeDBVisualizer/) | Open `BlazeDBVisualizer/BlazeDBVisualizer.xcodeproj` | macOS storage inspection UI | **beta** |
| BlazeMCP | Sources under `BlazeMCP/`; see [MCP_SERVER.md](MCP_SERVER.md) | MCP protocol design / in-tree sources | **in-tree, not packaged** |
| Distributed sync / server / discovery tooling | See [DISTRIBUTED_TRANSPORT_DEFERRED.md](../Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) | Networked sync product surfaces | **deferred** |
| Android / KMM sample paths | See [android-status.md](../android-status.md) | Cross-compile + KMM sample | **experimental** |

### Naming note

`BlazeShell/` holds implementation sources for the **`blazedb`** product (`BlazeCLICore` / `BlazedbCLI`). There is no separate "BlazeShell" executable to ship.

Doctor, Dump, and Info are **shipped** SwiftPM executables. They are not `blazedb` subcommands today (see issues #259, #300).

All three require arguments and exit 1 with a usage message when run bare, so `swift run BlazeDoctor` on its own is not a working invocation. Pass `--help` to see the full argument list, or read the per-tool docs linked below. This also means their Xcode Run schemes need arguments set to do anything useful.

### Benchmarks

From a checkout:

```bash
./dev help                 # lists bench commands
./bench honesty            # or: ./dev bench honesty
./bench smoke              # short local sweeps → benchmark_results/
./bench payload --release  # size vs latency
./bench db-size --release  # insert latency vs DB size
./bench publish            # maintainers: Docs/Benchmarks/*.md tables
```

Canonical docs: [../Benchmarks/README.md](../Benchmarks/README.md) · [../Benchmarks/HONEST_PERFORMANCE.md](../Benchmarks/HONEST_PERFORMANCE.md). Not part of normal unit-test CI.

## Canonical tool docs

- [BLAZEDOCTOR_DOCUMENTATION.md](BLAZEDOCTOR_DOCUMENTATION.md)
- [BLAZEDUMP_DOCUMENTATION.md](BLAZEDUMP_DOCUMENTATION.md)
- [BLAZEINFO_DOCUMENTATION.md](BLAZEINFO_DOCUMENTATION.md)
- [BLAZESHELL_DOCUMENTATION.md](BLAZESHELL_DOCUMENTATION.md) (`blazedb` CLI)
- [MCP_SERVER.md](MCP_SERVER.md) (**in-tree, not packaged**)
- [BLAZESTUDIO_DOCUMENTATION.md](BLAZESTUDIO_DOCUMENTATION.md) (**beta**)
- [BLAZEDBVISUALIZER_DOCUMENTATION.md](BLAZEDBVISUALIZER_DOCUMENTATION.md) (**beta**)
- [USING_BLAZELOGGER_IN_VISUALIZER.md](USING_BLAZELOGGER_IN_VISUALIZER.md)
