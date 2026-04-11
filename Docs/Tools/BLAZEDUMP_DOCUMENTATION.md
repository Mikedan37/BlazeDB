# BlazeDump - CLI Documentation

`BlazeDump` handles backup export/import flows for BlazeDB databases.

## Commands

- `dump <db-path> <dump-path> <password>`
  - Exports a database to a dump artifact
- `restore <dump-path> <db-path> <password> [--allow-schema-mismatch]`
  - Restores a dump into a target database path
- `verify <dump-path>`
  - Validates dump header and format metadata

## Usage

```bash
swift run BlazeDump dump /path/to/source.blazedb /path/to/backup.blazedump "your-password"
swift run BlazeDump verify /path/to/backup.blazedump
swift run BlazeDump restore /path/to/backup.blazedump /path/to/target.blazedb "your-password"
```

## Schema mismatch option

`restore` accepts `--allow-schema-mismatch` for controlled recovery scenarios where version alignment is intentionally bypassed.

## Exit behavior

- Exit code `0`: operation succeeded
- Exit code `1`: operation failed

## Notes

- Intended for operational backup/restore workflows
- Uses `BlazeDBImporter` and `BlazeDBClient` APIs in `BlazeDBCore`
