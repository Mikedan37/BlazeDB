# Distributed Transport Deferred (Core OSS Path)

BlazeDB's current open-source release path is **core-only**. Distributed transport integration is intentionally deferred.

## Current State

- The main branch does not include a direct `BlazeTransport` package dependency.
- Distributed connection handling is compile-time gated behind `BLAZEDB_DISTRIBUTED_TRANSPORT`.
- Core storage, durability, indexing, and query features are unaffected by this gate.

## Why This Is Deferred

- Historical release tags used private SSH dependency URLs, which are not publicly reproducible in clean environments.
- Public OSS verification currently prioritizes deterministic core behavior and clean-clone buildability.

## TODO To Re-enable Transport

1. Add a public, fetchable transport dependency (HTTPS URL, no private SSH requirement).
2. Verify dependency manifests do not rely on local path-only transitive packages.
3. Enable `BLAZEDB_DISTRIBUTED_TRANSPORT` in the distributed build configuration.
4. Re-enable and validate the secure connection + relay pipeline (`SecureConnection` / `TCPRelay`).
5. Add clean-runner CI coverage for distributed transport flows.

## Scope Clarification

This is not a removal of distributed design intent. It is a temporary delivery boundary for OSS reliability and reproducibility.
