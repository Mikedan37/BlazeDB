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
  echo "Running: swift build --target BlazeDBCore -Xswiftc -strict-concurrency=complete $*"

  if ! swift build --target BlazeDBCore -Xswiftc -strict-concurrency=complete "$@" >"$log_file" 2>&1; then
    echo "Build failed for '$label'. Showing last 120 log lines:"
    tail -n 120 "$log_file"
    rm -f "$log_file"
    exit 1
  fi

  local hits_file
  hits_file="$(mktemp)"

  # Focused regression gate: fail if strict concurrency emits Sendable diagnostics
  # for our SwiftUI observation wrappers or the change observation core file.
  if python3 - "$log_file" "$hits_file" <<'PY'
import re
import sys

log_path, hits_path = sys.argv[1], sys.argv[2]
pattern = re.compile(
    r"(BlazeDB/SwiftUI/BlazeQuery\.swift|BlazeDB/SwiftUI/BlazeQueryTyped\.swift|BlazeDB/Core/ChangeObservation\.swift):\d+:\d+: (warning|error): .*([sS]endable|#Sendable)"
)

hits = []
with open(log_path, "r", encoding="utf-8", errors="replace") as f:
    for i, line in enumerate(f, start=1):
        if pattern.search(line):
            hits.append(f"{i}:{line}")

if hits:
    with open(hits_path, "w", encoding="utf-8") as out:
        out.writelines(hits)
    sys.exit(0)
sys.exit(1)
PY
  then
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
