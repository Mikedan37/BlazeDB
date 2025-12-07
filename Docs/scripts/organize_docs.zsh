#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

echo "Organizing Docs under: $ROOT"

mkdir -p Sync Guides Security Architecture Performance Testing GC API Tools Archive

move_if_exists() {
  local target_dir="$1"; shift
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      echo "  mv $f -> $target_dir/"
      git mv "$f" "$target_dir/" >/dev/null
    fi
  done
}

echo "• Moving canonical Sync docs"
move_if_exists Sync \
  SYNC_TRANSPORT_GUIDE.md SYNC_EXAMPLES.md SYNC_TOPOLOGY.md \
  SYNC_TRANSPORT_SUMMARY.md SYNC_MEMORY_SAFETY.md \
  IN_MEMORY_VS_UNIX_SOCKETS.md UNIX_DOMAIN_SOCKETS.md

echo "• Moving core Guides"
move_if_exists Guides \
  DEVICE_DISCOVERY.md CONNECTING_DATABASES_GUIDE.md \
  CONVENIENCE_API_GUIDE.md QUICK_START_DISTRIBUTED.md README_SYNC.md

echo "• Moving Security docs"
move_if_exists Security \
  SECURITY_ANALYSIS.md ENCRYPTION_STRATEGY.md SECURE_TCP_HANDSHAKE.md \
  AUTH_TOKEN_MANAGEMENT.md COMPLETE_SHARED_SECRET_GUIDE.md \
  SECURITY_AND_APP_STORE_COMPLIANCE.md P2P_ENCRYPTION.md

echo "• Moving Architecture docs"
move_if_exists Architecture \
  ARCHITECTURE.md BLAZEBINARY_PROTOCOL.md BLAZEDB_RELAY.md \
  DISTRIBUTED_ARCHITECTURE.md SERVER_CLIENT_ARCHITECTURE.md

echo "• Moving Performance docs"
move_if_exists Performance \
  PERFORMANCE_ANALYSIS_AND_OPTIMIZATIONS.md PERFORMANCE_OPTIMIZATIONS.md \
  BANDWIDTH_ANALYSIS.md LATENCY_BREAKDOWN.md THROUGHPUT_ANALYSIS.md \
  REALISTIC_PERFORMANCE_ANALYSIS.md IMPROVEMENTS_SUMMARY.md \
  ASYNC_AND_SERVER_READINESS.md ULTRA_FAST_PROTOCOL.md TCP_RELIABILITY.md \
  RELIABILITY_COMPARISON.md

echo "• Moving Testing docs"
move_if_exists Testing \
  TEST_COVERAGE_DOCUMENTATION.md GC_TEST_COVERAGE.md \
  TEST_COVERAGE_DISTRIBUTED.md TEST_EXAMPLES_VISUAL_GUIDE.md \
  TEST_RUNNER_GUIDE.md TEST_RUNNER_DEBUGGING.md TEST_STABILITY_FIXES.md

echo "• Moving GC docs"
move_if_exists GC \
  GC_ENHANCEMENTS_NEEDED.md GC_IMPLEMENTATION_SUMMARY.md \
  GC_PROOF.md GC_TODO_CRITICAL.md

echo "• Moving API docs"
move_if_exists API \
  API_REFERENCE.md COMPLETE_PROJECT_DOCUMENTATION.md

echo "• Moving Tools docs"
move_if_exists Tools \
  BLAZESHELL_DOCUMENTATION.md BLAZESTUDIO_DOCUMENTATION.md \
  BLAZEDBVISUALIZER_DOCUMENTATION.md USING_BLAZELOGGER_IN_VISUALIZER.md

echo "• Archiving remaining top-level docs"
for f in *.md(.N); do
  case "$f" in
    README.md|MASTER_DOCUMENTATION_INDEX.md|ARCHIVE_INDEX.md) ;;
    *) echo "  mv $f -> Archive/"; git mv "$f" Archive/ >/dev/null ;;
  esac
done

echo "Done."


