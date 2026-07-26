# BlazeDB Documentation

This index is the navigation and authority map for BlazeDB docs. The [root README](../README.md) is the product homepage. This file tells you which guides are current, which are advanced, which are deferred, and which are historical or internal.

Skim the headings. You do not need to read every linked page.

## Support state (verify against Package.swift and CI)

| Label | Meaning |
|-------|---------|
| **Default shipped core** | Built and intended for normal OSS use: embedded encrypted engine, typed/raw APIs, durability, import/export, health/stats, CLI |
| **Advanced but supported** | Public and usable, not day-one reading: migrations, schema validation, indexing/search tuning, manual mapping |
| **Conditional / deferred** | May exist in source or docs; not the default product story (distributed sync/server/discovery, full telemetry packaging) |
| **Historical / internal** | Archaeology or maintainer analysis; not the contract for current behavior |

Source on disk does not automatically mean default support. Prefer `Package.swift`, tests, and CI over folder names.

## Audiences

| Audience | Start here |
|----------|------------|
| New Swift app developer | [Getting Started](GettingStarted/README.md) → [HOW_TO_USE](GettingStarted/HOW_TO_USE_BLAZEDB.md) |
| Contributor | [CONTRIBUTING.md](../CONTRIBUTING.md) → `./dev help` → [CI and Test Tiers](Testing/CI_AND_TEST_TIERS.md) |
| Maintainer / release | [Maintainer docs](#maintainer-docs) |
| Embedder (C / FFI) | [C ABI + Byte KV](Architecture/C_ABI_BYTE_KV.md) |
| Historian | [Archive](Archive/) · [Internal](Internal/README.md) (non-authoritative) |

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
| [Examples](../Examples/README.md) | Runnable samples by support state |
| [Architecture](Architecture/) | Core embedded runtime (storage, queries, durability) |
| [C ABI + Byte KV](Architecture/C_ABI_BYTE_KV.md) | Frozen embedder contract |
| [Compatibility](COMPATIBILITY.md) | Platforms and expectations |
| [Security](../SECURITY.md) | Vulnerability reporting |
| [Durability Mode Support](Status/DURABILITY_MODE_SUPPORT.md) | WAL and recovery contract |
| [Key Management](Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) | Password and key behavior |
| [Performance](Performance/README.md) | Performance guidance |
| [Benchmarks](Benchmarks/README.md) | Methodology and how to run workloads |
| [Tools](Tools/README.md) | CLI and companion tools |

## Start here (happy path)

1. [Getting Started](GettingStarted/README.md): install, run `HelloBlazeDB`, paste the starter snippet.
2. [Default storage paths](GettingStarted/DEFAULT_STORAGE_PATHS.md): where files land on each platform.
3. [Developer Guide](DEVELOPER_GUIDE.md): fuller API prose after something has run once.
4. [API Reference](API/API_REFERENCE.md): when you already know the call you need.
5. [Examples](../Examples/README.md): concrete files to copy or run.

## Advanced but supported

Still supported; not the first day of reading:

- [Developer Guide](DEVELOPER_GUIDE.md) (advanced sections)
- [API Reference](API/API_REFERENCE.md)
- [Performance](Performance/README.md)
- Migration and schema material under Architecture / Status (cross-check currency before relying on older Status notes)

## Conditional / deferred

May exist in the repo or docs without being the default OSS story:

- [Distributed Transport Deferred](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Sync Docs](Sync/README.md): design context; not default onboarding
- Staging targets such as `BlazeDBSyncStaging` / `BlazeDBTelemetryStaging` in `Package.swift`: non-default packaging
- Sync and telemetry examples under `Examples/`: treat as gated or design-oriented unless a maintained doc says otherwise

## Contributing and project policies

- [Contributing Guide](../CONTRIBUTING.md) (includes `./dev` workflows)
- [Xcode schemes](Build/XCODE_SCHEMES.md) (lean shared schemes vs `./dev`)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Security Policy](../SECURITY.md)
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
- [Master Documentation Index](MASTER_DOCUMENTATION_INDEX.md)
- [Agents Guide](AGENTS_GUIDE.md)

## Internal analysis (non-authoritative)

- [Internal Docs Index](Internal/README.md)

Useful for maintainers. Not the contract for current public behavior.

## Historical material (non-authoritative)

- [Archive](Archive/) and [Archive README](Archive/README.md)
- [Meta](Meta/README.md)
- [Audit](Audit/README.md)
- [Project](Project/README.md)

Old milestones and superseded designs can explain intent. They are not “current truth” unless a maintained doc explicitly points at them.

## Documentation audit

The latest onboarding and authority audit (with history findings and validation commands) is [README_AUDIT.md](README_AUDIT.md).
