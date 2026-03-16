# Durability Mode Support Policy

This policy describes supported durability behavior in current BlazeDB releases.

## Modes in Codebase

- **Unified durability path** (`DurabilityManager` + `RecoveryManager`):
  - transaction-aware WAL semantics,
  - replay of committed writes/deletes.
- **Legacy durability path** (`WriteAheadLog` and legacy transaction journaling):
  - CRC-validated entry replay,
  - compatibility path retained for historical behavior.

## Support Position

- Unified mode is the preferred path for current production deployments.
- Legacy paths are supported for compatibility and migration continuity.
- Behavior differences between unified and legacy paths are documented and tested in core integration suites.

## Operational Guidance

1. Use a single durability mode consistently per deployment.
2. Validate crash-recovery and restore workflows before production rollout.
3. Treat mixed legacy/unified migration windows as controlled operations with backup and post-migration verification.
