# BlazeDB Documentation

This index separates the main public documentation path from maintainer-only or historical material.

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
- [Distributed Transport Deferred Status](Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) for features intentionally out of the OSS core build.
- [Architecture](Architecture/README.md) for system design and internals.
- [Performance](Performance/README.md) for benchmark and performance guidance.

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

## Historical And Internal Material

- [Archive](Archive/) for historical release and design records (see [Archive README](Archive/README.md)).
- [Meta](Meta/README.md) for internal project-management documentation.
- [Audit](Audit/README.md) for audit snapshots and internal review artifacts.
- [Project](Project/README.md) for project status and assessment notes.
- [Tools](Tools/README.md) for tool-specific documentation.

Use the sections above as the default path. Archive and internal folders are useful for maintainers, but they are not the recommended starting point for new adopters.
