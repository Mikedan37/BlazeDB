#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run_and_check() {
  local label="$1"
  shift

  local log_file
  log_file="$(mktemp)"

  echo "=== $label ==="
  echo "Running: swift build --build-tests -Xswiftc -strict-concurrency=complete $*"

  if ! swift build --build-tests -Xswiftc -strict-concurrency=complete "$@" >"$log_file" 2>&1; then
    echo "Build failed for '$label'. Showing last 120 log lines:"
    tail -n 120 "$log_file"
    rm -f "$log_file"
    exit 1
  fi

  local hits_file
  hits_file="$(mktemp)"

  # Focused regression gate: fail if strict concurrency emits Sendable diagnostics
  # for our SwiftUI observation wrappers or the change observation core file.
  if rg -n \
    "(BlazeDB/SwiftUI/BlazeQuery\\.swift|BlazeDB/SwiftUI/BlazeQueryTyped\\.swift|BlazeDB/Core/ChangeObservation\\.swift):[0-9]+:[0-9]+: (warning|error): .*([sS]endable|#Sendable)" \
    "$log_file" >"$hits_file"; then
    echo "Sendable regression detected in observation files:"
    cat "$hits_file"
    rm -f "$log_file" "$hits_file"
    exit 1
  fi

  echo "OK: no Sendable diagnostics in observation files for '$label'."
  rm -f "$log_file" "$hits_file"
}

run_and_check "Strict concurrency (default)"
run_and_check "Strict concurrency (BLAZEDB_LINUX_CORE)" -Xswiftc -DBLAZEDB_LINUX_CORE

echo "=== Sendable observation checks passed ==="
