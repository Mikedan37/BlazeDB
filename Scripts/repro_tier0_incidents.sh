#!/bin/bash
set -euo pipefail

# Repro runner for current Tier 0 incidents.
# Runs failing tests repeatedly with hermetic per-iteration paths and structured artifacts.

ITERATIONS="${1:-50}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ROOT_ARTIFACT_DIR=".artifacts/quick/${RUN_ID}/incidents"
mkdir -p "${ROOT_ARTIFACT_DIR}"

SEED="${BLAZEDB_TEST_SEED:-1337}"
export BLAZEDB_TEST_SEED="${SEED}"

TESTS=(
  "BlazeDB_Tier0.TransactionDurabilityTests/testCrashRecovery_NoPartialOutcomes_AllOrNothing"
  "BlazeDB_Tier0.TransactionDurabilityTests/testStartupWithCorruptedWALDoesNotBrickDatabase"
  "BlazeDB_Tier0.TransactionRecoveryTests/testDoubleRecoveryIsIdempotent"
)

echo "=== Repro Tier0 incidents ==="
echo "iterations=${ITERATIONS}"
echo "seed=${SEED}"
echo "artifacts=${ROOT_ARTIFACT_DIR}"

for i in $(seq 1 "${ITERATIONS}"); do
  ITER_DIR="${ROOT_ARTIFACT_DIR}/iter-$(printf "%03d" "${i}")"
  TMP_DIR="${ITER_DIR}/tmp"
  DB_ROOT="${ITER_DIR}/dbroot"
  TRACE_DIR="${ITER_DIR}/trace"
  mkdir -p "${ITER_DIR}" "${TMP_DIR}" "${DB_ROOT}" "${TRACE_DIR}"

  export TMPDIR="$(pwd)/${TMP_DIR}"
  export BLAZEDB_REPRO_DB_ROOT="$(pwd)/${DB_ROOT}"
  export BLAZEDB_IO_TRACE_DIR="$(pwd)/${TRACE_DIR}"
  export BLAZEDB_REPRO_ITERATION="${i}"

  for test_id in "${TESTS[@]}"; do
    safe_test_name="$(echo "${test_id}" | tr '/.' '___')"
    log_file="${ITER_DIR}/${safe_test_name}.log"
    status_file="${ITER_DIR}/${safe_test_name}.status"

    SCRATCH_DIR="${ITER_DIR}/scratch-${safe_test_name}"
    mkdir -p "${SCRATCH_DIR}"
    set +e
    swift test --scratch-path "${SCRATCH_DIR}" --parallel --num-workers 1 --filter "${test_id}" >"${log_file}" 2>&1
    rc=$?
    set -e

    echo "${rc}" > "${status_file}"
  done
done

python3 - <<'PY'
import json
import re
from collections import Counter
from pathlib import Path

root = Path(".artifacts/quick")
latest = max([p for p in root.iterdir() if p.is_dir()], key=lambda p: p.stat().st_mtime)
incident_root = latest / "incidents"

iterations = 0
failures = 0
signatures = Counter()
errno_codes = Counter()

status_files = sorted(incident_root.glob("iter-*/**/*.status"))
for status_path in status_files:
    iterations += 1
    rc = int(status_path.read_text().strip())
    test_base = status_path.stem
    log_path = status_path.with_suffix(".log")
    text = log_path.read_text(errors="ignore") if log_path.exists() else ""

    if rc != 0:
        failures += 1
        m = re.search(r"error: -\[[^\]]+\]\s*:\s*failed(?:[:\s-]+)(.+)", text)
        if m:
            signatures[m.group(1).strip()] += 1
        else:
            m2 = re.search(r"failed: caught error: \"([^\"]+)\"", text)
            signatures[(m2.group(1).strip() if m2 else "unknown_failure_signature")] += 1

    for code in re.findall(r"NSPOSIXErrorDomain Code=(\d+)", text):
        errno_codes[int(code)] += 1

summary = {
    "artifactRoot": str(incident_root),
    "iterations": iterations,
    "failures": failures,
    "failureSignatures": signatures.most_common(10),
    "topErrnoCodes": errno_codes.most_common(10),
}

summary_path = incident_root / "summary.json"
summary_path.write_text(json.dumps(summary, indent=2) + "\n")

print("=== Repro summary ===")
print(f"artifactRoot: {summary['artifactRoot']}")
print(f"iterations: {summary['iterations']}")
print(f"failures: {summary['failures']}")
print("failureSignatures:")
for sig, n in summary["failureSignatures"]:
    print(f"  - {n}x {sig}")
print("topErrnoCodes:")
for code, n in summary["topErrnoCodes"]:
    print(f"  - errno {code}: {n}")
print(f"summaryFile: {summary_path}")
PY
