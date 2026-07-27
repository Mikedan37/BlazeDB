# Architecture Documentation

## Contributor entry (start here)

- **[CHANGE_MAP.md](CHANGE_MAP.md)** — mechanical blast radius per path (start here before changing code)
- **[CODEBASE_MAP.md](CODEBASE_MAP.md)** — product boundaries, targets, directories, execution paths
- **[TOURS/](TOURS/)** — short code-first walks (open, write, query, transactions, C ABI, CLI, tests)
- Learning paths + issue→code index: [LEARNING_PATHS](../Contributing/LEARNING_PATHS.md), [ISSUE_CODE_INDEX](../Contributing/ISSUE_CODE_INDEX.md)

## Core Architecture

- **LIVE_QUERY_ARCHITECTURE.md** - Design of ``BlazeLiveQuery`` (observe → refresh → decode), adapters, and evidence hierarchy
- **ARCHITECTURE.md** - Main architecture overview
- **ARCHITECTURE_COMPARISON.md** - Comparison with other databases
- **ARCHITECTURE_DETAILED.md** - Detailed architecture documentation
- **BLAZEDB_ARCHITECTURE_AND_LIMITS.md** - Architecture and limitations
- **BLAZEDB_SYSTEM_DESIGN_DIAGRAM.md** - System design diagrams
- **STORAGE_ENGINE_NOTES.md** - WAL/encryption/page interaction and recovery design
- **C_ABI_BYTE_KV.md** - Stable C ABI (`blazedb.h`) + byte KV semantics (approved contract)

## Related Documentation

- See [Design](../Design/) for design documents
- See [Sync](../Sync/) for distributed architecture (deferred product)
- Historical or comparison docs in this folder may lag implementation — prefer CODEBASE_MAP + tours for contribution work
