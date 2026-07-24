# Architecture Documentation

This directory contains architecture documentation for BlazeDB.

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

- See `../Architecture/` for protocol-specific architecture
- See `../Design/` for design documents
- See `../Sync/` for distributed architecture
