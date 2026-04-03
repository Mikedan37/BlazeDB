# BlazeDB Documentation

This index separates the main public documentation path from maintainer-only or historical material.

## Support-State Framing

Use this quick framing before diving into detailed docs:

- **Default shipped core:** embedded encrypted engine, typed/raw APIs, durability, import/export, health/stats, CLI tooling.
- **Advanced but supported:** migrations, schema validation, indexing/search tuning, manual mapping.
- **Conditional/deferred:** distributed sync/server/discovery and full telemetry path outside default OSS runtime packaging.
- **Historical/internal:** archive and project-management docs are non-authoritative for first-time adopters.

## Audience Segmentation

- **Public product docs:** what BlazeDB is, how to use it, what is supported now.
- **Public maintainer docs:** release/testing/CI operations for contributors.
- **Internal analysis docs:** branch/capability/positioning analysis artifacts for maintainers.

Internal analysis material lives under [`Docs/Internal/`](Internal/README.md) and should not be treated as onboarding guidance.

## Documentation guide

BlazeDB documentation is organized into:

- **Canonical docs (current, maintained)** — Use these first for behavior and APIs:
  - [Repository README](../README.md) (install, quickstart, product summary)
  - [Getting Started](GettingStarted/) (first run, HOW_TO_USE, Linux notes)
  - [Testing / CI](Testing/) (tiers, test layout, execution model)
  - [Release](Release/) (release-facing checklists and notes)
  - [Architecture](Architecture/) — **core embedded runtime** (storage, queries, durability); prefer these over informal design notes for “what ships” in OSS.

- **Design / forward-looking docs** — Distributed transport, sync topology, and related material may describe **non-default** or **deferred** surfaces. Always cross-check [Distributed transport deferred](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) and the root `README.md` for what the default SwiftPM product includes.

- **Archived / historical docs** — [`Archive/`](Archive/) holds snapshots, old milestones, and superseded write-ups. **Not authoritative** for current OSS behavior unless explicitly cross-linked from a maintained doc.

## Start Here

- [Getting Started](GettingStarted/README.md) for first install, first run, and starter code.
- [Developer Guide](DEVELOPER_GUIDE.md) for the main public API walkthrough.
- [API Reference](API/API_REFERENCE.md) for reference-style documentation.
- [Examples](../Examples/) for runnable usage patterns.

## Core Product Docs

- [Compatibility](COMPATIBILITY.md) for supported platforms and release expectations.
- [Security](../SECURITY.md) for vulnerability reporting and disclosure expectations.
- [Durability Mode Support](Status/DURABILITY_MODE_SUPPORT.md) for WAL and recovery guarantees.
- [Key Management and Compatibility](Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) for password and key-handling behavior.
- [Legacy Layout Migration Guidance](Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md) for migration-sensitive upgrades.
- [Architecture](Architecture/README.md) for system design and internals.
- [Performance](Performance/README.md) for benchmark and performance guidance.

## Advanced Features (Supported)

- [Developer Guide](DEVELOPER_GUIDE.md) (advanced API sections)
- [API Reference](API/API_REFERENCE.md) (full reference; includes advanced and conditional surfaces)
- [Performance](Performance/README.md) (benchmark and tuning guidance)

## Conditional / Deferred Features

- [Distributed Transport Deferred Status](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
- [Sync Docs](Sync/README.md) - design and deferred transport context; not default OSS onboarding
- Telemetry and staging-related surfaces in source are conditional and should be treated as non-default runtime behavior

## Contributing And Project Policies

- [Contributing Guide](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Security Policy](../SECURITY.md)
- [Support Policy](SUPPORT_POLICY.md)
- [API Stability](API_STABILITY.md)
- [Third-Party Notices](../THIRD_PARTY_NOTICES.md)

## Maintainer Docs

- [CI and Test Tiers](Testing/CI_AND_TEST_TIERS.md)
- [Testing Guide](TESTING_GUIDE.md)
- [Release Rollback Procedure](Status/RELEASE_ROLLBACK.md)
- [Open-Source Readiness Checklist](Status/OPEN_SOURCE_READINESS_CHECKLIST.md) (hosted CI expectations and local validation paths)
- [External Security Review Plan](Status/EXTERNAL_SECURITY_REVIEW_PLAN.md)
- [Master Documentation Index](MASTER_DOCUMENTATION_INDEX.md)
- [Agents Guide](AGENTS_GUIDE.md)

## Internal Analysis Docs

- [Internal Docs Index](Internal/README.md)
- Analysis-style status artifacts are maintainer-facing and intentionally separated from user onboarding flow.

## Historical And Internal Material

- [Archive](Archive/) for historical release and design records (see [Archive README](Archive/README.md)).
- [Meta](Meta/README.md) for internal project-management documentation.
- [Audit](Audit/README.md) for audit snapshots and internal review artifacts.
- [Project](Project/README.md) for project status and assessment notes.
- [Tools](Tools/README.md) for tool-specific documentation.

Use the sections above as the default path. Archive and internal folders are useful for maintainers, but they are not the recommended starting point for new adopters.
