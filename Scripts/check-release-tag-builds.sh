#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAGS=("$@")

if [ "${#TAGS[@]}" -eq 0 ]; then
  # Last three semver tags present in this clone (requires full clone: fetch-depth: 0 in CI).
  # Portable for bash 3.2 (macOS): no mapfile.
  TAGS=()
  while IFS= read -r line; do
    [ -n "$line" ] && TAGS+=("$line")
  done < <(git -C "$ROOT_DIR" tag -l 'v*' | sort -V | tail -n 3)
  if [ "${#TAGS[@]}" -eq 0 ]; then
    echo "=== BlazeDB release-tag buildability check ==="
    echo "Repo: $ROOT_DIR"
    echo "No v* tags in this clone — ensure checkout uses fetch-depth: 0 (or fetch tags)."
    echo "Nothing to probe."
    exit 0
  fi
fi

FAILED=0

echo "=== BlazeDB release-tag buildability check ==="
echo "Repo: $ROOT_DIR"
echo "Tags: ${TAGS[*]}"
echo

for TAG in "${TAGS[@]}"; do
  if ! git -C "$ROOT_DIR" rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "ERROR: tag '$TAG' not found in this clone."
    echo "Use: git fetch --tags, or actions/checkout with fetch-depth: 0."
    exit 1
  fi

  WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/blazedb-tagcheck-${TAG//./_}-XXXXXX")"
  HOME_ISO="$(mktemp -d "${TMPDIR:-/tmp}/blazedb-home-tagcheck-${TAG//./_}-XXXXXX")"
  TMP_ISO="$(mktemp -d "${TMPDIR:-/tmp}/blazedb-tmp-tagcheck-${TAG//./_}-XXXXXX")"
  LOG="$ROOT_DIR/.tagcheck-${TAG}.log"

  echo "[$TAG] preparing clean worktree..."
  git -C "$ROOT_DIR" worktree add --detach "$WORKTREE" "$TAG" >/dev/null

  set +e
  (
    cd "$WORKTREE"
    env -i PATH="$PATH" HOME="$HOME_ISO" TMPDIR="$TMP_ISO" TERM="${TERM:-dumb}" \
      swift build -c release
  ) >"$LOG" 2>&1
  CODE=$?
  set -e

  if [ "$CODE" -eq 0 ]; then
    echo "[$TAG] PASS"
  else
    FAILED=1
    echo "[$TAG] FAIL (exit $CODE)"
    echo "[$TAG] First error lines:"
    rg -n "error:|fatal error|Permission denied|Could not read from remote repository|invalid custom path" "$LOG" --max-count 5 || true
  fi

  git -C "$ROOT_DIR" worktree remove --force "$WORKTREE" >/dev/null
  rm -rf "$HOME_ISO" "$TMP_ISO"
  echo
done

echo "Logs written to .tagcheck-<tag>.log in repo root."
echo "=== Tag buildability check complete ==="
exit "$FAILED"
