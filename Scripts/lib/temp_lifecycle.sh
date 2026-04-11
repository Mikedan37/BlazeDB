#!/bin/bash

# Shared temp lifecycle management for local/CI harness scripts.
# - Creates a per-run TMPDIR under .artifacts/tmp
# - Reaps stale BlazeDB-owned temp roots
# - Removes the run temp root on exit and fails loudly on leaks

blazedb_temp_setup() {
  local purpose="${1:-run}"
  local base_dir="${2:-$(pwd)/.artifacts/tmp}"
  local threshold_minutes="${BLAZEDB_TMP_REAP_MINUTES:-60}"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"

  mkdir -p "$base_dir"

  BLAZEDB_TEMP_ROOT="${base_dir}/blazedb-${purpose}-$$-${ts}"
  export BLAZEDB_TEMP_ROOT
  mkdir -p "$BLAZEDB_TEMP_ROOT"
  export TMPDIR="$BLAZEDB_TEMP_ROOT"

  echo "[temp] root=$BLAZEDB_TEMP_ROOT"

  local reaped_total=0
  reaped_total=$(( reaped_total + $(blazedb_reap_stale_tmpdirs "/tmp" "$threshold_minutes") ))
  reaped_total=$(( reaped_total + $(blazedb_reap_stale_tmpdirs "$base_dir" "$threshold_minutes") ))
  echo "[temp] reaped_stale=${reaped_total}"

  trap 'blazedb_temp_teardown $?' EXIT INT TERM
}

blazedb_reap_stale_tmpdirs() {
  local parent="$1"
  local threshold_minutes="$2"
  local now
  now="$(date +%s)"
  local removed=0
  local skipped_live=0

  if [[ ! -d "$parent" ]]; then
    echo 0
    return
  fi

  shopt -s nullglob
  for d in "$parent"/blazedb-*; do
    [[ -d "$d" ]] || continue
    [[ -n "${BLAZEDB_TEMP_ROOT:-}" && "$d" == "$BLAZEDB_TEMP_ROOT" ]] && continue

    local mtime age_min
    mtime="$(stat -c %Y "$d" 2>/dev/null || echo 0)"
    age_min=$(( (now - mtime) / 60 ))
    if (( age_min > threshold_minutes )); then
      # Name format: blazedb-<purpose>-<pid>-<timestamp>; skip live PIDs when parseable.
      local base pid
      base="$(basename "$d")"
      pid="$(echo "$base" | sed -nE 's/^blazedb-[^-]+-([0-9]+)-[0-9]{8}-[0-9]{6}$/\1/p')"
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        skipped_live=$((skipped_live + 1))
        continue
      fi
      if rm -rf "$d"; then
        removed=$((removed + 1))
      fi
    fi
  done
  shopt -u nullglob

  if (( skipped_live > 0 )); then
    echo "[temp] skipped_live_pid=${skipped_live} parent=${parent}" >&2
  fi
  echo "$removed"
}

blazedb_temp_teardown() {
  local status="${1:-$?}"
  if [[ "${BLAZEDB_TEMP_TEARDOWN_DONE:-0}" == "1" ]]; then
    return
  fi
  BLAZEDB_TEMP_TEARDOWN_DONE=1
  export BLAZEDB_TEMP_TEARDOWN_DONE

  if [[ -n "${BLAZEDB_TEMP_ROOT:-}" && -d "${BLAZEDB_TEMP_ROOT}" ]]; then
    rm -rf "${BLAZEDB_TEMP_ROOT}" || true
    if [[ -d "${BLAZEDB_TEMP_ROOT}" ]]; then
      echo "[temp] teardown=failed root=${BLAZEDB_TEMP_ROOT}"
      if [[ "$status" -eq 0 ]]; then
        status=99
      fi
    else
      echo "[temp] teardown=ok root=${BLAZEDB_TEMP_ROOT}"
    fi
  else
    echo "[temp] teardown=ok root_missing_or_already_removed"
  fi

  trap - EXIT INT TERM
  exit "$status"
}
