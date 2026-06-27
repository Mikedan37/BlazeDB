# CorePathSmoke

Smoke test for the **portable core path** (`BLAZEDB_LINUX_CORE` — the same compile-time mode used for Linux and Android cross-compiles).

This is **not** an Android example. It runs on the host (macOS/Linux) and exercises:

- `BlazeDBClient.open(at:password:)`
- `put` / `get` / `query`
- `db.observe` (requires a short run-loop pump in CLI tools)

```bash
swift run CorePathSmoke
```

Expected output:

```
core-path-smoke: ok observed=1 queried=1
```

For Android cross-compilation verification, see `./Scripts/ci-android-cross-compile.sh` and [Docs/android-status.md](../../Docs/android-status.md).
