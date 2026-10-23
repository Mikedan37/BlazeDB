#!/usr/bin/env bash
# Run the Android CI script with local SDK bundles and fail-closed tool stubs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=android-swift-config.sh
source "$ROOT/Scripts/android-swift-config.sh"

mkdir -p "$ROOT/.artifacts"
TEST_ROOT="$(mktemp -d "$ROOT/.artifacts/android-cross-compile-test.XXXXXX")"
echo "Sandbox logs: $TEST_ROOT"
FAILED=0

check() {
  local description="$1"
  shift
  if "$@"; then
    echo "PASS: $description"
  else
    echo "FAIL: $description"
    FAILED=1
  fi
}

run_scenario() {
  local scenario="$1" sdk_base="${2:-.config/swiftpm/swift-sdks}"
  local sandbox="$TEST_ROOT/$scenario/$sdk_base"
  local bundle_name="${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}"
  local seed installed ndk host_tag checksum status final_root installs
  mkdir -p "$sandbox/repo/Scripts" "$sandbox/home" "$sandbox/bin" "$sandbox/tmp" "$sandbox/cache"
  cp "$ROOT/Scripts/ci-android-cross-compile.sh" "$sandbox/repo/Scripts/"

  seed="$sandbox/payload/$bundle_name/swift-android"
  mkdir -p "$seed/scripts" "$seed/ndk-sysroot"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$seed/scripts/setup-android-sdk.sh"
  chmod +x "$seed/scripts/setup-android-sdk.sh"
  tar -czf "$sandbox/cache/$BLAZEDB_ANDROID_SDK_ARTIFACT" -C "$sandbox/payload" "$bundle_name"
  checksum="$(shasum -a 256 "$sandbox/cache/$BLAZEDB_ANDROID_SDK_ARTIFACT" | awk '{print $1}')"
  # Keep the real config helpers, with checksum/size pins for the tiny local artifact.
  sed -e "s/^readonly BLAZEDB_ANDROID_SDK_CHECKSUM=.*/readonly BLAZEDB_ANDROID_SDK_CHECKSUM=\"$checksum\"/" \
    -e 's/^readonly BLAZEDB_ANDROID_SDK_MIN_BYTES=.*/readonly BLAZEDB_ANDROID_SDK_MIN_BYTES=1/' \
    "$ROOT/Scripts/android-swift-config.sh" > "$sandbox/repo/Scripts/android-swift-config.sh"

  installed="$sandbox/home/$sdk_base/$bundle_name/swift-android"
  if [[ "$scenario" == sdk-hit || "$scenario" == sdk-miss-ndk-hit ]]; then
    mkdir -p "$(dirname "$installed")"
    cp -R "$seed" "$installed"
    touch "$installed/unregistered-state"
    ndk="$installed/android-ndk-$BLAZEDB_ANDROID_NDK_VERSION"
    case "$(uname -s)-$(uname -m)" in
      Darwin-arm64) host_tag="darwin-arm64" ;;
      Darwin-x86_64) host_tag="darwin-x86_64" ;;
      *) host_tag="linux-x86_64" ;;
    esac
    mkdir -p "$ndk/toolchains/llvm/prebuilt/$host_tag/bin" \
      "$ndk/toolchains/llvm/prebuilt/$host_tag/sysroot/usr/include/c++/v1"
    printf 'restored NDK\n' > "$ndk/sentinel"
    local triple suffix
    for triple in "$BLAZEDB_ANDROID_SWIFT_TRIPLE" "$BLAZEDB_ANDROID_SWIFT_TRIPLE_X86_64"; do
      for suffix in clang clang++; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$ndk/toolchains/llvm/prebuilt/$host_tag/bin/${triple/-unknown-linux-/-linux-}-$suffix"
        chmod +x "$ndk/toolchains/llvm/prebuilt/$host_tag/bin/${triple/-unknown-linux-/-linux-}-$suffix"
      done
    done
  fi
  if [[ "$scenario" == sdk-hit ]]; then
    printf '%s\n' "$BLAZEDB_ANDROID_SDK_NAME" > "$sandbox/home/sdk-list"
  else
    printf 'unrelated-sdk\n' > "$sandbox/home/sdk-list"
  fi
  if [[ "$scenario" == sdk-list-error ]]; then
    touch "$sandbox/home/sdk-list-error"
  fi

  cat > "$sandbox/bin/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$HOME/../repo/Scripts/android-swift-config.sh"
printf '%s\n' "$*" >> "$HOME/swift.log"
case "$*" in
  --version) echo 'Swift version 6.3.2 (OSS fixture)' ;;
  'sdk list')
    if [[ -f "$HOME/sdk-list-error" ]]; then
      echo 'SDK_LIST_ERROR_STUB' >&2
      exit 42
    fi
    cat "$HOME/sdk-list"
    ;;
  sdk\ install\ *)
    [[ $# -eq 5 && "$3" == "$BLAZEDB_ANDROID_SDK_CACHE_DIR/$BLAZEDB_ANDROID_SDK_ARTIFACT" &&
      "$4" == --checksum && "$5" == "$BLAZEDB_ANDROID_SDK_CHECKSUM" ]] || {
      touch "$HOME/unexpected-swift.called"
      echo 'UNEXPECTED_SWIFT_INSTALL' >&2; exit 90;
    }
    base="$HOME/.config/swiftpm/swift-sdks"
    if [[ -e "$base/${BLAZEDB_ANDROID_SDK_ARTIFACT%.tar.gz}" ]]; then
      echo 'SDK_DESTINATION_ALREADY_EXISTS' >&2
      exit 91
    fi
    mkdir -p "$base"
    tar -xzf "$3" -C "$base"
    ;;
  "sdk configure --reset $BLAZEDB_ANDROID_SDK_NAME $BLAZEDB_ANDROID_SWIFT_TRIPLE"|\
  "sdk configure --reset $BLAZEDB_ANDROID_SDK_NAME $BLAZEDB_ANDROID_SWIFT_TRIPLE_X86_64") ;;
  "build --swift-sdk $BLAZEDB_ANDROID_SWIFT_TRIPLE --static-swift-stdlib"|\
  "build --product BlazeDBAndroidBridge --swift-sdk $BLAZEDB_ANDROID_SWIFT_TRIPLE"|\
  "build --product BlazeDBAndroidBridge --swift-sdk $BLAZEDB_ANDROID_SWIFT_TRIPLE_X86_64") ;;
  *) touch "$HOME/unexpected-swift.called"; echo "UNEXPECTED_SWIFT: $*" >&2; exit 92 ;;
esac
EOF
  local tool
  for tool in curl unzip; do
    cat > "$sandbox/bin/$tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tool="$(basename "$0")"
printf '%s\n' "$*" > "$HOME/$tool.called"
echo "FORBIDDEN_DOWNLOAD: $tool $*" >&2
exit 93
EOF
    chmod +x "$sandbox/bin/$tool"
  done
  chmod +x "$sandbox/bin/swift"

  status=0
  env -i PATH="$sandbox/bin:$PATH" HOME="$sandbox/home" TMPDIR="$sandbox/tmp" \
    BLAZEDB_ANDROID_SDK_CACHE_DIR="$sandbox/cache" \
    bash "$sandbox/repo/Scripts/ci-android-cross-compile.sh" > "$sandbox/output.log" 2>&1 || status=$?
  echo ">>> $scenario ($sdk_base): script exit $status"
  cat "$sandbox/output.log"
  installs="$(awk '/^sdk install / { n++ } END { print n+0 }' "$sandbox/home/swift.log")"
  check "$scenario: no unexpected Swift invocation" test ! -e "$sandbox/home/unexpected-swift.called"
  if [[ "$scenario" == sdk-hit || "$scenario" == sdk-miss-ndk-hit ]]; then
    check "$scenario: script completes" test "$status" -eq 0
    if [[ "$scenario" == sdk-hit ]]; then
      check "$scenario: no SDK install" test "$installs" -eq 0
      check "$scenario: registered bundle is untouched" test -f "$installed/unregistered-state"
    else
      check "$scenario: SDK installed once" test "$installs" -eq 1
      check "$scenario: unregistered bundle was removed" test ! -e "$installed/unregistered-state"
    fi
    check "$scenario: no curl download" test ! -e "$sandbox/home/curl.called"
    check "$scenario: no unzip" test ! -e "$sandbox/home/unzip.called"
    final_root="$(sed -n 's/^>>> Swift Android SDK root: //p' "$sandbox/output.log")"
    check "$scenario: final SDK root is the installed bundle" test "$final_root" = "$sandbox/home/.config/swiftpm/swift-sdks/$bundle_name/swift-android"
    check "$scenario: NDK sentinel survives at final SDK root" \
      grep -Fxq 'restored NDK' "$final_root/android-ndk-$BLAZEDB_ANDROID_NDK_VERSION/sentinel"
    check "$scenario: both cross-compiles finish" grep -Fxq '>>> Android cross-compile: ok' "$sandbox/output.log"
  elif [[ "$scenario" == total-miss ]]; then
    check "$scenario: exits on forbidden download" test "$status" -eq 93
    check "$scenario: SDK installed once" test "$installs" -eq 1
    check "$scenario: NDK curl download attempted" grep -Fq "android-ndk-$BLAZEDB_ANDROID_NDK_VERSION-" "$sandbox/home/curl.called"
    check "$scenario: unzip not reached after curl failure" test ! -e "$sandbox/home/unzip.called"
  else
    check "$scenario: hard failure" test "$status" -ne 0
    check "$scenario: reports sdk list error" grep -Fq 'error: failed to list installed Swift SDKs' "$sandbox/output.log"
    check "$scenario: no SDK install" test "$installs" -eq 0
    check "$scenario: no curl download" test ! -e "$sandbox/home/curl.called"
    check "$scenario: no unzip" test ! -e "$sandbox/home/unzip.called"
  fi
}

case "${1:-all}" in
  all)
    run_scenario sdk-hit
    run_scenario sdk-miss-ndk-hit
    run_scenario sdk-miss-ndk-hit .swiftpm/swift-sdks
    run_scenario sdk-miss-ndk-hit Library/org.swift.swiftpm/swift-sdks
    run_scenario total-miss
    run_scenario sdk-list-error
    ;;
  sdk-hit|sdk-miss-ndk-hit|total-miss|sdk-list-error) run_scenario "$1" ;;
  *) echo "Usage: $0 [all|sdk-hit|sdk-miss-ndk-hit|total-miss|sdk-list-error]" >&2; exit 2 ;;
esac
exit "$FAILED"
