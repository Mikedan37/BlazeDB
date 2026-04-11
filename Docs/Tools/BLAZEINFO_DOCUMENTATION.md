# BlazeInfo - CLI Documentation

`BlazeInfo` prints a quick operational snapshot for a BlazeDB file.

## What it reports

- Database path and logical name
- File/database size
- Record count and page count
- Index count
- WAL size (when available)
- Health status and reason messages
- Schema version (when available)

## Usage

```bash
swift run BlazeInfo /path/to/database.blazedb "your-password"
```

## Exit behavior

- Exit code `0`: info retrieval succeeded
- Exit code `1`: open/stats/health retrieval failed

## Notes

- Intended for quick inspection in local/dev/ops flows
- Complements `BlazeDoctor` (diagnostics) and `BlazeDump` (backup/restore)
