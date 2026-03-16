# Legacy Layout Migration Guidance

Use this process when opening older databases that may contain legacy metadata/layout encodings.

## When You Need This

You likely need migration guidance if:

- secure layout decode fails on metadata shape mismatch,
- layout uses tuple/array legacy forms instead of canonical object forms,
- compatibility fallback mode is required for initial load.

## Recommended Migration Procedure

1. Back up the database files and `.salt` sidecar.
2. Open in a controlled maintenance run with compatibility fallback enabled.
3. Read and validate core metadata (schema version, record count, index definitions).
4. Re-save layout using current secure canonical format.
5. Disable compatibility fallback and reopen normally.
6. Run golden-path verification (`swift test --filter GoldenPathIntegrationTests`) against migrated artifacts.

## Safety Rules

- Treat compatibility fallback as a temporary migration-only mode.
- Do not leave fallback mode enabled in steady-state production startup.
- If verification fails after migration, restore from backup and investigate before retry.
