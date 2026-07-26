# Xcode schemes (lean set)

BlazeDB uses two complementary surfaces:

| Surface | Owns |
|---|---|
| `./dev …` | Repeatable repo workflows: focused tests, tiers, experiments |
| Xcode schemes | Interactive IDE: Run, Profile, Analyze, Archive |

Do **not** create a scheme for every target or every ritual. Xcode already auto-generates a local zoo under `.swiftpm/`; only a small curated set is shared in git.

## Shared schemes to use

| Scheme | Where | Primary actions |
|---|---|---|
| `BlazeDB` | `BlazeDB.xcodeproj` | Test, Analyze |
| `BlazeDBCore` | Swift package (shared) | Analyze; optional Tier0 / CLI Test |
| `blazedb` | Swift package (shared) | Run, Analyze |
| `BlazeDBBenchmarks` | Swift package (shared) | Run, **Profile** (Release) |
| `BlazeStudio` | `BlazeStudio/*.xcodeproj` | Run, Profile, Analyze, Archive |
| `BlazeDBVisualizer` | `BlazeDBVisualizer/*.xcodeproj` | Run, Profile, Analyze, Archive |

## What `./dev` owns instead

```bash
./dev help
./dev tests [search]
./dev test <filter>
./dev tier0 … tier3
./dev experiments
./dev experiment <name>
```

Do not put `dev test …` arguments on the `blazedb` scheme Profile action. That profiles the dispatcher / `swift test` glue, not the workload.

## Profile workloads, not dispatchers

Good Profile targets:

- `BlazeDBBenchmarks` (preferred)
- `BlazeStudio` / `BlazeDBVisualizer` with a real session
- `blazedb` with a real database path and password (not `dev …`)

Useful Instruments templates: Time Profiler, Allocations, Leaks, File Activity, System Trace.

## Routine

| When | Do |
|---|---|
| Normal commit | `./dev test <focused>` then `./dev tier0` |
| Substantial storage change | `./dev tier1`, Analyze on `BlazeDB`/`BlazeDBCore`, run/Profile benchmarks if perf-sensitive |
| Release | `./dev tier2` / `tier3`, `swift build -c release`, Archive apps, packaging / Homebrew checks |

## Managing the local scheme zoo

Opening the package in Xcode recreates many local schemes. That is fine. Keep Manage Schemes tidy by unchecking **Shared** on anything outside the table above, and prefer `./dev` for tier / experiment workflows.
