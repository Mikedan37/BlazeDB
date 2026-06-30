#!/usr/bin/env bash
# Cross-compile BlazeDBCore for Android (aarch64 + x86_64 for CI emulator).
# Requires OSS Swift matching android-swift-config.sh — not Xcode's swift.
# See Docs/android-status.md and Docs/COMPATIBILITY.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

# GitHub Actions runner images pre-set ANDROID_NDK_ROOT; the Swift Android SDK bundle conflicts with it.
unset ANDROID_NDK_ROOT

resolve_android_sdk_root() {
  local cache_dir="${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$ROOT/.artifacts/android-sdk}"
  local bundle_name="${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}"
  local candidate base

  for base in \
    "${HOME}/.config/swiftpm/swift-sdks" \
    "${HOME}/.swiftpm/swift-sdks" \
    "${HOME}/Library/org.swift.swiftpm/swift-sdks" \
    "$cache_dir"; do
    [[ -d "$base" ]] || continue
    candidate="$base/$bundle_name/swift-android/scripts/setup-android-sdk.sh"
    if [[ -f "$candidate" ]]; then
      echo "$(cd "$(dirname "$candidate")/.." && pwd)"
      return 0
    fi
  done

  for base in \
    "${HOME}/.config/swiftpm/swift-sdks" \
    "${HOME}/.swiftpm/swift-sdks" \
    "${HOME}/Library/org.swift.swiftpm/swift-sdks" \
    "$cache_dir"; do
    [[ -d "$base" ]] || continue
    candidate="$(find "$base" -path "*/swift-android/scripts/setup-android-sdk.sh" 2>/dev/null | head -1)"
    if [[ -n "$candidate" ]]; then
      echo "$(cd "$(dirname "$candidate")/.." && pwd)"
      return 0
    fi
  done

  return 1
}

echo ">>> Swift host toolchain"
swift --version

if swift --version 2>&1 | grep -q "Apple Swift"; then
  echo "error: Android cross-compilation requires the OSS Swift toolchain, not Xcode/Apple Swift." >&2
  echo "       Run ./Scripts/install-android-swift.sh (Linux CI) or install from https://www.swift.org/install/" >&2
  exit 1
fi

android_sdk_bundle_dir() {
  local cache_dir="${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$ROOT/.artifacts/android-sdk}"
  echo "$cache_dir/${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}"
}

android_sdk_swift_android_dir() {
  echo "$(android_sdk_bundle_dir)/swift-android"
}

install_android_sdk() {
  local cache_dir="${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$ROOT/.artifacts/android-sdk}"
  local tarball_path="$cache_dir/$BLAZEDB_ANDROID_SDK_ARTIFACT"
  local swift_android
  swift_android="$(android_sdk_swift_android_dir)"
  mkdir -p "$cache_dir"

  if [[ -f "$tarball_path" ]] && verify_android_sdk_artifact "$tarball_path"; then
    echo ">>> Reusing cached Android Swift SDK artifact at $tarball_path"
  else
    rm -f "$tarball_path"
    download_android_sdk_artifact "$tarball_path"
  fi

  if [[ ! -f "$swift_android/scripts/setup-android-sdk.sh" ]]; then
    echo ">>> Extracting Android Swift SDK bundle"
    tar -xzf "$tarball_path" -C "$cache_dir"
  else
    echo ">>> Android Swift SDK bundle already present at $swift_android"
  fi

  if [[ ! -f "$swift_android/scripts/setup-android-sdk.sh" ]]; then
    echo "error: Android Swift SDK bundle missing at $swift_android/scripts/setup-android-sdk.sh after extract" >&2
    ls -la "$cache_dir" >&2 || true
    exit 1
  fi

  if ! swift sdk list 2>/dev/null | grep -qx "$BLAZEDB_ANDROID_SDK_NAME"; then
    echo ">>> Registering Android Swift SDK with SwiftPM"
    swift sdk install "$tarball_path" --checksum "$BLAZEDB_ANDROID_SDK_CHECKSUM"
  fi
}

echo ">>> Swift Android SDK"
install_android_sdk

if ! SDK_ROOT="$(resolve_android_sdk_root)"; then
  echo "error: could not locate installed Swift Android SDK under ~/.config/swiftpm/swift-sdks, ~/.swiftpm/swift-sdks, or .artifacts/android-sdk" >&2
  ls -la "${BLAZEDB_ANDROID_SDK_CACHE_DIR:-$ROOT/.artifacts/android-sdk}" >&2 || true
  exit 1
fi
echo ">>> Swift Android SDK root: $SDK_ROOT"

NDK_OS="linux"
case "$(uname -s)" in
  Darwin) NDK_OS="darwin" ;;
  Linux) NDK_OS="linux" ;;
esac

NDK_HOME="$SDK_ROOT/android-ndk-$BLAZEDB_ANDROID_NDK_VERSION"
if [[ ! -d "$NDK_HOME" ]]; then
  echo ">>> Download Android NDK $BLAZEDB_ANDROID_NDK_VERSION"
  (
    cd "$SDK_ROOT"
    curl -fSL --retry 3 --retry-all-errors --retry-delay 5 \
      -o ndk.zip "https://dl.google.com/android/repository/android-ndk-${BLAZEDB_ANDROID_NDK_VERSION}-${NDK_OS}.zip"
    unzip -qo ndk.zip
    rm -f ndk.zip
  )
fi

export ANDROID_NDK_HOME="$NDK_HOME"
"$SDK_ROOT/scripts/setup-android-sdk.sh"

run_android_toolchain_smoke() {
  local tmp
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    mkdir Sources
    cat > Package.swift <<'EOF'
// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "HelloAndroid",
    targets: [
        .executableTarget(
            name: "HelloAndroid",
            path: "Sources"
        )
    ]
)
EOF
    cat > Sources/main.swift <<'EOF'
print("Hello, Android!")
EOF
    swift build \
      --swift-sdk "$BLAZEDB_ANDROID_SWIFT_TRIPLE" \
      --static-swift-stdlib
  )
  rm -rf "$tmp"
}

resolve_ndk_host_tag() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "linux-x86_64" ;;
    Darwin-arm64) echo "darwin-arm64" ;;
    Darwin-x86_64) echo "darwin-x86_64" ;;
    *) echo "linux-x86_64" ;;
  esac
}

resolve_android_clang_include() {
  local host_tag ndk_prebuilt clang_root include_dir
  host_tag="$(resolve_ndk_host_tag)"
  ndk_prebuilt="$NDK_HOME/toolchains/llvm/prebuilt/$host_tag"
  clang_root="$ndk_prebuilt/lib/clang"
  include_dir="$(find "$clang_root" -maxdepth 2 -type d -name include 2>/dev/null | head -1)"
  if [[ -z "$include_dir" ]]; then
    echo "error: could not locate NDK clang include directory under $clang_root" >&2
    return 1
  fi
  echo "$include_dir"
}

resolve_ndk_cxx_include() {
  local host_tag
  host_tag="$(resolve_ndk_host_tag)"
  echo "$NDK_HOME/toolchains/llvm/prebuilt/$host_tag/sysroot/usr/include/c++/v1"
}

resolve_ndk_clang_binary() {
  local suffix="$1"
  local triple="${2:-$BLAZEDB_ANDROID_SWIFT_TRIPLE}"
  local bin_dir="$NDK_HOME/toolchains/llvm/prebuilt/$(resolve_ndk_host_tag)/bin"
  local short_triple="${triple/-unknown-linux-/-linux-}"
  local candidate name pattern arch_glob
  case "$triple" in
    x86_64-*)
      arch_glob="x86_64"
      ;;
    aarch64-*)
      arch_glob="aarch64"
      ;;
    *)
      echo "error: unsupported Android Swift triple: $triple" >&2
      return 1
      ;;
  esac
  for name in "${short_triple}-${suffix}" "${triple}-${suffix}"; do
    candidate="$bin_dir/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  if [[ "$suffix" == "clang" ]]; then
    pattern="${arch_glob}-*-android*-clang"
  else
    pattern="${arch_glob}-*-android*-clang++"
  fi
  candidate="$(find "$bin_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | sort | head -1)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  echo "error: no NDK ${suffix} wrapper in $bin_dir for $triple (tried ${short_triple}-${suffix}, then ${pattern})" >&2
  ls "$bin_dir" 2>/dev/null | grep -E 'android.*clang' | head -10 >&2 || true
  return 1
}

cross_compile_blazedb_for_triple() {
  local triple="$1"
  local ndk_clang ndk_clangxx
  ndk_clang="$(resolve_ndk_clang_binary clang "$triple")"
  ndk_clangxx="$(resolve_ndk_clang_binary clang++ "$triple")"

  if [[ ! -d "$SDK_ROOT/ndk-sysroot" ]]; then
    echo "error: missing Android C sysroot at $SDK_ROOT/ndk-sysroot" >&2
    exit 1
  fi
  if [[ ! -d "$(resolve_ndk_cxx_include)" ]]; then
    echo "error: missing NDK libc++ headers under $(resolve_ndk_cxx_include)" >&2
    exit 1
  fi

  export CC="$ndk_clang"
  export CXX="$ndk_clangxx"

  echo ">>> NDK CC=$CC"
  echo ">>> NDK CXX=$CXX"

  echo ">>> Reset Swift SDK configuration for $triple"
  swift sdk configure --reset "$BLAZEDB_ANDROID_SDK_NAME" "$triple" 2>/dev/null || true

  echo ">>> Cross-compile BlazeDBAndroidBridge (dynamic) for $triple"
  swift build \
    --product BlazeDBAndroidBridge \
    --swift-sdk "$triple"
}

echo ">>> Android toolchain smoke (hello world for $BLAZEDB_ANDROID_SWIFT_TRIPLE)"
run_android_toolchain_smoke

echo ">>> Clean SwiftPM build directory for Android cross-compile"
rm -rf .build

echo ">>> Cross-compile BlazeDBAndroidBridge for arm64 + x86_64 (CI emulator uses x86_64 on Linux KVM)"
cross_compile_blazedb_for_triple "$BLAZEDB_ANDROID_SWIFT_TRIPLE"
cross_compile_blazedb_for_triple "$BLAZEDB_ANDROID_SWIFT_TRIPLE_X86_64"

echo ">>> Android cross-compile: ok"
