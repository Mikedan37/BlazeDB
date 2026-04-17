# Default storage paths (macOS, iOS, Linux)

BlazeDB resolves default file locations through `PathResolver.defaultDatabaseDirectory()` and related helpers. This page is the **canonical reference** when documenting or debugging “where did my file go?”

## Design rules

1. **Do not use `FileManager.homeDirectoryForCurrentUser` on iOS** — it is unavailable. Apple platforms use **`FileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, …)`** so paths work in the iOS sandbox and match macOS’s `~/Library/Application Support` layout.
2. **Linux** continues to use `~/.local/share/blazedb/` (XDG-style) via the home directory.
3. **`BlazeDB.open(at:password:)`** is unchanged: your app supplies any valid URL (including App Group containers on iOS).

## Database files (`BlazeDB.open(name:password:)`)

| Platform | Directory | Example file |
|----------|-----------|----------------|
| **macOS** | `~/Library/Application Support/BlazeDB/` | `myapp.blazedb` |
| **iOS / iPadOS** | `<App Sandbox>/Library/Application Support/BlazeDB/` | `myapp.blazedb` |
| **Linux** | `~/.local/share/blazedb/` | `myapp.blazedb` |

On Apple platforms the implementation is: **Application Support** + **`BlazeDB`** (see `PathResolver.swift`).

## Telemetry metrics file (when telemetry is enabled)

Default metrics store path **changed** to live next to other app data under Application Support:

| Period | Default `metricsURL` |
|--------|----------------------|
| **Current** | `<Application Support>/BlazeDB/metrics/telemetry.blazedb` |
| **Legacy** | `~/.blazedb/metrics/telemetry.blazedb` (macOS/Linux only; not used on iOS) |

If you relied on the legacy `~/.blazedb` location, either migrate files manually or pass an explicit `TelemetryConfiguration(metricsURL:)` when constructing telemetry.

## Related code

- `BlazeDB/Utils/PathResolver.swift` — default database directory
- `BlazeDB/Telemetry/TelemetryConfiguration.swift` — default metrics URL
- `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift` — `open(named:password:)`
- `BlazeDB/Exports/BlazeDBClient+Convenience.swift` — `defaultDatabaseURL(for:)`

## See also

- [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md) § “Where the Database Lives”
- [USABILITY_PORTABILITY.md](USABILITY_PORTABILITY.md)
