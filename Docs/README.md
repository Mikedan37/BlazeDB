# BlazeDB Documentation

This index is the navigation and authority map for BlazeDB docs. The [root README](../README.md) is the product homepage. This file tells you which guides are current, which are advanced, which are deferred, and which are internal or historical.

Skim the headings. You do not need to read every linked page.

## Support state

`Package.swift`, tests, and CI are the source of truth when documentation and source layout disagree.

| Label | Meaning |
|-------|---------|
| **Default shipped core** | Built for normal open-source use: embedded storage, typed and raw APIs, transactions and durability, import/export, inspection APIs, and CLI tooling |
| **Advanced but supported** | Public and usable, but not required for first use. Some topics still have documentation under consolidation (see below) |
| **Conditional or deferred** | Source or design material that is not part of the default product, including distributed sync, server/discovery, and full telemetry packaging |
| **Internal** | Maintainer analysis, audits, project records, and operational material; not a public behavior contract |
| **Historical** | Superseded designs, milestones, and archived releases retained for context |

## Audiences

| Audience | Start here |
|----------|------------|
| New Swift app developer | [Getting Started](GettingStarted/README.md) → [HOW_TO_USE](GettingStarted/HOW_TO_USE_BLAZEDB.md) |
| Contributor | [CONTRIBUTING.md](../CONTRIBUTING.md) → `./dev help` → [CI and Test Tiers](Testing/CI_AND_TEST_TIERS.md) |
| Maintainer / release | [Maintainer docs](#maintainer-docs) |
| Embedder (C / FFI) | [C ABI + Byte KV](Architecture/C_ABI_BYTE_KV.md) |
| Historian | [Historical material](#historical-material-non-authoritative) |

Internal analysis lives under [`Docs/Internal/`](Internal/README.md). It can contain useful reasoning, but it is not onboarding and not the behavior contract.

## Canonical public product docs

Use these first for current behavior:

| Doc | Subject |
|-----|---------|
| [Repository README](../README.md) | Product homepage and path chooser |
| [RELEASE.md](../RELEASE.md) | Current release notes |
| [Getting Started](GettingStarted/) | First run, Linux notes, storage paths |
| [HOW_TO_USE_BLAZEDB.md](GettingStarted/HOW_TO_USE_BLAZEDB.md) | Longer usage guide |
| [Developer Guide](DEVELOPER_GUIDE.md) | Public API walkthrough |
| [API Reference](API/API_REFERENCE.md) | Lookup tables and signatures |
| [Examples](../Examples/README.md) | Runnable samples labeled by support state |
| [Architecture](Architecture/) | Core embedded runtime (storage, queries, durability) |
| [C ABI + Byte KV](Architecture/C_ABI_BYTE_KV.md) | Documented C interoperability surface (published symbols: signature and behavior do not change; see that doc for scope) |
| [Compatibility](COMPATIBILITY.md) | Platforms and expectations |
| [Security architecture](Security/README.md) | Encryption, keys, and threat-model docs |
| [Security policy](../SECURITY.md) | Vulnerability reporting and disclosure |
| [Durability Mode Support](Status/DURABILITY_MODE_SUPPORT.md) | WAL, durability modes, and recovery behavior (includes default-path guarantees) |
| [Key Management](Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) | Password and key behavior |
| [Performance](Performance/README.md) | Tuning and performance concepts |
| [Benchmarks](Benchmarks/README.md) | Executable workloads, methodology, and results |
| [Tools](Tools/README.md) | CLI and companion tools |

## Start here (happy path)

1. [Getting Started](GettingStarted/README.md): install, run `HelloBlazeDB`, paste the starter snippet.
2. [Default storage paths](GettingStarted/DEFAULT_STORAGE_PATHS.md): where files land on each platform.
3. [Developer Guide](DEVELOPER_GUIDE.md): fuller API prose after something has run once.
4. [API Reference](API/API_REFERENCE.md): when you already know the call you need.
5. [Examples](../Examples/README.md): concrete files to copy or run (labeled Default / Advanced / Conditional / Experimental).

## Advanced but supported

Still public and usable; not the first day of reading:

| Topic | Where to start | Doc status |
|-------|----------------|------------|
| API / password migration notes | [Docs/MIGRATION.md](MIGRATION.md) | Maintained for public API churn |
| Schema validation APIs | [API Reference](API/API_REFERENCE.md) · `SchemaValidation` in source | Implemented; dedicated guide under consolidation |
| Indexing and search tuning | [Developer Guide](DEVELOPER_GUIDE.md) · [Performance](Performance/README.md) | Supported; prefer these over older Status notes |
| Manual mapping (`BlazeDocument`) | [Developer Guide](DEVELOPER_GUIDE.md) · [API Reference](API/API_REFERENCE.md) | Supported |

SQLite/Core Data migrator write-ups and older Status migration notes may still exist. Treat them as historical or incomplete unless a maintained doc above links to them. Do not treat folder presence as a promise of a finished migration product experience.

## Conditional / deferred

May exist in the repo or docs without being the default OSS story:

- [Distributed Transport Deferred](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Sync Docs](Sync/README.md): design context; not default onboarding
- Staging targets such as `BlazeDBSyncStaging` / `BlazeDBTelemetryStaging` in `Package.swift`: non-default packaging
- Examples labeled Conditional, Deferred, or Experimental in [Examples/README.md](../Examples/README.md)

## Contributing and project policies

- [Contributing Guide](../CONTRIBUTING.md) (includes `./dev` workflows)
- [Xcode schemes](Build/XCODE_SCHEMES.md) (lean shared schemes vs `./dev`)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Security policy](../SECURITY.md) (reporting and disclosure)
- [Support Policy](SUPPORT_POLICY.md)
- [API Stability](API_STABILITY.md)
- [Third-Party Notices](../THIRD_PARTY_NOTICES.md)
- [Experiments](../Experiments/README.md)

## Maintainer docs

- [CI and Test Tiers](Testing/CI_AND_TEST_TIERS.md)
- [Testing Guide](TESTING_GUIDE.md)
- [Build docs](Build/README.md)
- [Release Rollback](Status/RELEASE_ROLLBACK.md)
- [Open-Source Readiness Checklist](Status/OPEN_SOURCE_READINESS_CHECKLIST.md)
- [External Security Review Plan](Status/EXTERNAL_SECURITY_REVIEW_PLAN.md)
- [Maintainer documentation inventory](MASTER_DOCUMENTATION_INDEX.md) (complete file inventory; **not** the curated public authority map; this Docs/README.md is)
- [Agents Guide](AGENTS_GUIDE.md)

## Internal and project records

These may include current maintainer work. They are not public behavior contracts.

- [Internal Docs Index](Internal/README.md)
- [Meta](Meta/README.md)
- [Audit](Audit/README.md)
- [Project](Project/README.md)
- [README onboarding audit](README_AUDIT.md) (current; documents how the public homepage and index were verified)

## Historical material (non-authoritative)

Old milestones and superseded designs can explain intent. They are not current truth unless a maintained doc explicitly points at them.

- [Archive](Archive/) and [Archive README](Archive/README.md)
- Superseded Status snapshots and legacy migration notes not linked from the Advanced table above

## Documentation audit

The latest onboarding and authority audit (with history findings and validation commands) is [README_AUDIT.md](README_AUDIT.md).
