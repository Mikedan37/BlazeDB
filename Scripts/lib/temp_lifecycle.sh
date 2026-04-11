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

  echo "[temp] created run temp root: $BLAZEDB_TEMP_ROOT"
  echo "[temp] TMPDIR set to: $TMPDIR"

  blazedb_reap_stale_tmpdirs "/tmp" "$threshold_minutes"
  blazedb_reap_stale_tmpdirs "$base_dir" "$threshold_minutes"

  trap 'blazedb_temp_teardown $?' EXIT INT TERM
}

blazedb_reap_stale_tmpdirs() {
  local parent="$1"
  local threshold_minutes="$2"
  local now
  now="$(date +%s)"
  local removed=0

  if [[ ! -d "$parent" ]]; then
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
      if rm -rf "$d"; then
        removed=$((removed + 1))
      fi
    fi
  done
  shopt -u nullglob

  if (( removed > 0 )); then
    echo "[temp] reaped $removed stale blazedb-* dir(s) in $parent (>${threshold_minutes}m old)"
  fi
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
      echo "[temp] ERROR: leaked temp root still exists: ${BLAZEDB_TEMP_ROOT}"
      if [[ "$status" -eq 0 ]]; then
        status=99
      fi
    else
      echo "[temp] removed run temp root: ${BLAZEDB_TEMP_ROOT}"
    fi
  fi

  trap - EXIT INT TERM
  exit "$status"
}
