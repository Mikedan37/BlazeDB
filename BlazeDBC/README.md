# BlazeDBC

Stable C ABI for embedding BlazeDB from any language that can call C.

| Item | Path |
|------|------|
| Header | [`include/blazedb.h`](include/blazedb.h) |
| Design | [`Docs/Architecture/C_ABI_BYTE_KV.md`](../Docs/Architecture/C_ABI_BYTE_KV.md) |
| Release | [`RELEASE.md`](../RELEASE.md) (v2.8.1) |
| C example | [`Examples/C`](../Examples/C) |

```bash
swift build -c release --product BlazeDBC
# → .build/release/libBlazeDBC.dylib   (macOS)
# → .build/release/libBlazeDBC.so      (Linux)

# Optional static archive:
swift build -c release --product BlazeDBCStatic
# → .build/release/libBlazeDBC.a
```

Do **not** use `BlazeDBAndroidBridge` / `blazedb_bridge_*` as the long-term ABI — that surface is JSON/demo-oriented for KMM samples.
