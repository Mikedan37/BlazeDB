# Tour 06 — CLI and operator tools

~15 minutes. Goal: know what `blazedb` actually dispatches versus separate tool executables.

## Start here

1. `./dev` → exec `.build/debug/blazedb dev …`
2. `BlazedbCLI/BlazedbEntry.swift`
3. `BlazeShell/CLIHelp.swift`, `BlazeShell/DeveloperCommands.swift`
4. `BlazeShell/BlazedbRepl.swift` (in-REPL `doctor`)
5. `BlazeDoctor/main.swift`, `BlazeDump/main.swift`, `BlazeInfo/main.swift`
6. `Docs/Guides/CLI_REFERENCE.md` (may drift — #259)

## Follow this symbol

`blazedb` argv → `BlazedbEntry.main` → `help` | `dev` (`DeveloperCommands`) | open DB → REPL.  
**Not** routed today: top-level `doctor` / `dump` / `info` as subcommands — use `swift run BlazeDoctor|BlazeDump|BlazeInfo`.

## Invariants

- `./dev` must not silently run the wrong-arch binary without a clear error (#289).
- Password handling in tools must not grow new argv exposure without review.
- Destructive dump/restore needs clear commands and confirmation story.

## Associated tests

- `BlazeDBCLITests/DeveloperCommandsTests.swift`
- `BlazeDBCLITests/BlazeCLICoreTests.swift`
- `BlazeDBTests/Tier0Core/Gate/CLISmokeTests.swift` / Tier1 Integration CLI smoke

## Try it

```bash
./dev help
./dev tiers
swift run blazedb help
# Tools:
swift run BlazeInfo   # see main.swift usage
```

## Open work

#258 (`--version`), #259 (docs honesty), #289 (arch mismatch), #290 (JSON Dump/Info).

## Extension ideas

1. `--version` — **already tracked** (#258).
2. Structured `--json` — **already tracked** (#290).
3. Unify tools as `blazedb` subcommands — **requires maintainer design**.
