# C embedding example (BlazeDBC v0.1.0)

Complete sample: [`hello_blazedb.c`](hello_blazedb.c)

## 1. Build BlazeDB

From the repository root:

```bash
swift build -c release --product BlazeDBC
```

Produces:

- `.build/release/libBlazeDBC.a`
- Header: `BlazeDBC/include/blazedb.h`

## 2. Compile the example

Link against the **same Swift toolchain** that built the archive. Exact flags vary by OS.

### macOS (Xcode Swift)

```bash
cd Examples/C
cc -o hello_blazedb hello_blazedb.c \
  -I../../BlazeDBC/include \
  ../../.build/release/libBlazeDBC.a \
  -L$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx \
  -lswiftCore -lswiftFoundation -lc++ \
  -framework Foundation -framework Security
./hello_blazedb
```

### Linux / Raspberry Pi (Swift.org toolchain)

```bash
cd Examples/C
# Set SWIFT_PATH to your Swift install, e.g. /usr/share/swift or ~/swift
cc -o hello_blazedb hello_blazedb.c \
  -I../../BlazeDBC/include \
  ../../.build/release/libBlazeDBC.a \
  -L"$SWIFT_PATH/usr/lib/swift/linux" \
  -lswiftCore -lswift_Concurrency -lswiftFoundation -lswiftGlibc -lstdc++ -lm -ldl -lpthread
./hello_blazedb
```

If link errors mention missing Swift symbols, add the corresponding `-lswift*` libraries from `$SWIFT_PATH/usr/lib/swift/linux`.

## Expected output

```text
get: queued
ok
```

Creates `hello.blaze` (plus encryption sidecars such as `.salt` / `.meta`) in the current directory.
