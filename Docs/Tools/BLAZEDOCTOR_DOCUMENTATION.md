# BlazeDoctor - CLI Documentation

`BlazeDoctor` runs a health pass against an existing BlazeDB file and reports whether the database is usable.

## What it checks

- Database file exists at the provided path
- Database can be opened with the provided password (key/auth check)
- Basic layout/integrity path is readable (`count()` probe)
- Read/write cycle works (temporary insert, fetch validation, cleanup delete)
- Stats and health APIs can be queried

## Usage

```bash
swift run BlazeDoctor /path/to/database.blazedb "your-password"
```

JSON output for automation:

```bash
swift run BlazeDoctor /path/to/database.blazedb "your-password" --json
```

## Output behavior

- Exit code `0`: database passed health checks
- Exit code `1`: one or more checks failed
- `--json` prints a machine-readable report with checks, optional stats snapshot, and errors

## Notes

- Designed as an operational diagnostics tool, not as a data migration tool
- Uses public BlazeDB APIs and does not require internal engine hooks
