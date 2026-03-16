#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAGS=("$@")
if [ "${#TAGS[@]}" -eq 0 ]; then
  TAGS=("v0.1.3" "v2.6.0" "v2.7.0")
fi

echo "=== BlazeDB release-tag buildability check ==="
echo "Repo: $ROOT_DIR"
echo "Tags: ${TAGS[*]}"
echo

for TAG in "${TAGS[@]}"; do
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
