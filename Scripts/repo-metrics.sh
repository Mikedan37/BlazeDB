#!/usr/bin/env bash
# repo-metrics.sh — BlazeDB repository size + health metrics.
#
# Sole inventory: git ls-files (via Scripts/generate_repository_metrics.py).
# Writes:
#   .metrics/repository-metrics.json   (source of truth)
#   Docs/Meta/REPOSITORY_METRICS.md    (rendered from JSON)
#
# Usage:
#   ./Scripts/repo-metrics.sh           # regenerate JSON + Markdown
#   ./Scripts/repo-metrics.sh --check   # fail if committed/working snapshots are stale
#   ./Scripts/repo-metrics.sh --diff    # compare to previous snapshot without writing
#
# Refresh on releases / major cleanups — not every commit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not a git repository: $ROOT" >&2
  exit 2
fi

exec python3 "$ROOT/Scripts/generate_repository_metrics.py" "$@"
