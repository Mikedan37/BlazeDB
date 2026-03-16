#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blazedb-quickstart-XXXXXX")"
MAX_SECONDS=300

cleanup() {
  git -C "$ROOT_DIR" worktree remove --force "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== BlazeDB README quickstart verification ==="
echo "Creating detached worktree at: $TMP_DIR"
git -C "$ROOT_DIR" worktree add --detach "$TMP_DIR" HEAD >/dev/null

echo "Syncing local working-tree changes into quickstart snapshot"
while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  src="$ROOT_DIR/$relpath"
  dst="$TMP_DIR/$relpath"
  mkdir -p "$(dirname "$dst")"
  if [ -d "$src" ]; then
    rm -rf "$dst"
    cp -R "$src" "$dst"
  elif [ -f "$src" ]; then
    cp "$src" "$dst"
  fi
done < <(
  {
    git -C "$ROOT_DIR" diff --name-only
    git -C "$ROOT_DIR" diff --cached --name-only
    git -C "$ROOT_DIR" ls-files --others --exclude-standard
  } | sort -u
)

echo "Running HelloBlazeDB quickstart from clean snapshot"
START_TS="$(date +%s)"
if (
  cd "$TMP_DIR"
  env -i PATH="$PATH" HOME="$HOME" TERM="${TERM:-dumb}" swift run HelloBlazeDB
); then
  END_TS="$(date +%s)"
  ELAPSED="$((END_TS - START_TS))"
  echo "Quickstart runtime: ${ELAPSED}s"
  if [ "$ELAPSED" -gt "$MAX_SECONDS" ]; then
    echo "FAILED: Quickstart exceeded ${MAX_SECONDS}s target"
    exit 1
  fi
  echo "PASS: README quickstart is functional within ${MAX_SECONDS}s"
else
  echo "FAILED: HelloBlazeDB quickstart did not complete successfully"
  exit 1
fi

echo "=== README quickstart verification complete ==="
