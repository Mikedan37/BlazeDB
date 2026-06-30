#!/usr/bin/env bash
# Place Linux-built Android native libs where :app Gradle copySwiftJniLibs expects them.
#
# Usage:
#   ./Scripts/stage-kmm-android-native-for-gradle.sh <staging-dir> [abi-filter]
#
# Staging layout (from CI artifact):
#   <staging-dir>/lib/arm64-v8a/libBlazeDBAndroidBridge.so
#   <staging-dir>/lib/x86_64/libBlazeDBAndroidBridge.so
#   <staging-dir>/swift-runtime/arm64-v8a/*.so
#   <staging-dir>/swift-runtime/x86_64/*.so
#
# abi-filter: optional comma-separated Gradle ABI names (e.g. x86_64 or arm64-v8a)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${1:?staging directory required}"
ABI_FILTER="${2:-}"

# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

abi_allowed() {
  local abi="$1"
  if [[ -z "$ABI_FILTER" ]]; then
    return 0
  fi
  IFS=',' read -r -a wanted <<< "$ABI_FILTER"
  for item in "${wanted[@]}"; do
    item="${item//[[:space:]]/}"
    [[ "$item" == "$abi" ]] && return 0
  done
  return 1
}

stage_one_abi() {
  local abi="$1"
  local triple
  case "$abi" in
    arm64-v8a) triple="$BLAZEDB_ANDROID_SWIFT_TRIPLE" ;;
    x86_64) triple="$BLAZEDB_ANDROID_SWIFT_TRIPLE_X86_64" ;;
    *) echo "error: unsupported ABI: $abi" >&2; return 1 ;;
  esac

  local bridge_src="$STAGE/lib/$abi/libBlazeDBAndroidBridge.so"
  local runtime_src="$STAGE/swift-runtime/$abi"
  local bridge_dest="$ROOT/.build/$triple/debug/libBlazeDBAndroidBridge.so"
  local runtime_dest
  runtime_dest="$(android_swift_runtime_dir_for_triple "$triple")"

  [[ -f "$bridge_src" ]] || { echo "error: missing $bridge_src" >&2; return 1; }
  [[ -d "$runtime_src" ]] || { echo "error: missing $runtime_src" >&2; return 1; }

  mkdir -p "$(dirname "$bridge_dest")" "$runtime_dest"
  cp "$bridge_src" "$bridge_dest"
  cp "$runtime_src"/*.so "$runtime_dest/"

  echo ">>> Staged $abi"
  echo "    bridge: $bridge_dest"
  echo "    swift runtime: $runtime_dest"
}

staged_any=0
for abi in arm64-v8a x86_64; do
  if [[ -f "$STAGE/lib/$abi/libBlazeDBAndroidBridge.so" ]]; then
    if abi_allowed "$abi"; then
      stage_one_abi "$abi"
      staged_any=1
    fi
  fi
done

if [[ "$staged_any" -eq 0 ]]; then
  echo "error: no matching Android native libs staged from $STAGE (filter=${ABI_FILTER:-all})" >&2
  exit 1
fi
