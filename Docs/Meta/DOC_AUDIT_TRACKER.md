# BlazeDB Documentation Audit Tracker

| Path | Category | Chunk | Status | Notes |
|--------------------------------------------------------|-----------------|--------|--------------|-------|
| README.md | onboarding | CHUNK1 | AUDITED | Core entry, aligned with BlazeDBClient, durability/security truth, sidecar labels. |
| SECURITY.md | security | CHUNK1 | AUDITED | Disclosure policy and scope match current security posture. |
| CONTRIBUTING.md | testing/contrib | CHUNK1 | AUDITED | CI tier descriptions and scripts match Package.swift and Scripts/. |
| CHANGELOG.md | release/status | CHUNK1 | AUDITED | Release history and unreleased notes consistent with current repo; legacy tag validation called out via manual `tag-probe` workflow / scripts where relevant. |
| CODE_OF_CONDUCT.md | other | CHUNK1 | AUDITED | Standard Contributor Covenant; no code claims. |
| Docs/GettingStarted/README.md | onboarding | CHUNK1 | AUDITED | Install/run examples and starter code use current BlazeDBClient API. |
| Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md | onboarding/api | CHUNK1 | AUDITED | Complete guide uses BlazeDBClient, advanced API fencing matches core code. |
| BlazeDB/BlazeDB.docc/BlazeDB.md | architecture | CHUNK1 | AUDITED | Banner + architecture story aligned; historical GitBlaze/CBOR context clearly marked. |
| Docs/Architecture/ARCHITECTURE.md | architecture | CHUNK2 | NEEDS-FIX | MVCC perf/index type claims overstated; needs “experimental/benchmark” labeling. |
| Docs/Status/DURABILITY_MODE_SUPPORT.md | durability | CHUNK2 | AUDITED | Precise description of WAL modes, overflow behavior, and visibility; matches core code. |
| Docs/Features/TRANSACTIONS.md | transactions | CHUNK2 | NEEDS-FIX | Semantics correct; performance tables should be framed as benchmark examples. |
| Docs/Status/CRASH_SURVIVAL.md | durability | CHUNK2 | AUDITED | Crash scenarios and invariants consistent with WAL/recovery design and tests. |
| Docs/Audit/SECURITY_LINUX.md | security | CHUNK2 | AUDITED | Detailed, code-backed Linux security model; matches PageStore/crypto/KDF behavior. |
| Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md | security | CHUNK2 | AUDITED | Key-management modes and compatibility paths aligned with implementation. |
| Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md | migration | CHUNK2 | AUDITED | Migration-only fallback guidance matches secure layout loader behavior. |
| Docs/Guarantees/SAFETY_MODEL.md | guarantees | CHUNK2 | AUDITED | Strong but consistent with durability/crash docs; “no partial records” is catalog-level. |

