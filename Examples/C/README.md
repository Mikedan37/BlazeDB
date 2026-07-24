# C embedding example (BlazeDBC v2.8.1)

Complete sample: [`hello_blazedb.c`](hello_blazedb.c)

## 1. Build BlazeDB

From the repository root:

```bash
swift build -c release --product BlazeDBC
```

Produces:

- `.build/release/libBlazeDBC.dylib` (macOS) or `libBlazeDBC.so` (Linux)
- Header: `BlazeDBC/include/blazedb.h`

## 2. Compile the example

Link the **shared** library and keep an rpath (or install into `/usr/local/lib`).

### macOS

```bash
cd Examples/C
cc -o hello_blazedb hello_blazedb.c \
  -I../../BlazeDBC/include \
  -L../../.build/release -lBlazeDBC \
  -Wl,-rpath,../../.build/release
./hello_blazedb
```

### Linux / Raspberry Pi

```bash
cd Examples/C
cc -o hello_blazedb hello_blazedb.c \
  -I../../BlazeDBC/include \
  -L../../.build/release -lBlazeDBC \
  -Wl,-rpath,../../.build/release
./hello_blazedb
```

If the loader cannot find Swift runtime libs, ensure your Swift toolchain’s `usr/lib/swift/linux` (or system Swift) is on `LD_LIBRARY_PATH` / rpath.

## Expected output

```text
get: queued
ok
```

Creates `hello.blaze` (plus encryption sidecars such as `.salt` / `.meta`) in the current directory.
