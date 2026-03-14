#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <artifact.json>"
  exit 2
fi

python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

artifact_path = Path(sys.argv[1])
data = json.loads(artifact_path.read_text())

file_probe = data.get("file", {})
wal = data.get("wal", {})
verify = data.get("verify", {})

layout_format = file_probe.get("layoutFormat", "unknown")
header_hex = file_probe.get("headerHex", "")
magic = (file_probe.get("framingHeader") or {}).get("magic")
declared = (file_probe.get("framingHeader") or {}).get("declaredLength")
file_size = file_probe.get("layoutFileSize", 0)
payload_sha = file_probe.get("payloadSha256")
stored = verify.get("storedSignatureHex16")
expected = verify.get("expectedSignatureHex16")

label = "unknown"
reason = []

if layout_format == "json" or header_hex.startswith("7b") or header_hex.startswith("5b"):
    label = "layout_format=json"
    reason.append("layout starts with JSON token")
elif magic is None:
    label = "framing_parse_invalid"
    reason.append("framing header missing/invalid")
elif wal.get("walFileSize", 0) > 0 and wal.get("trailingBytes", 0) > 0:
    label = "wal_boundary_invalid"
    reason.append("WAL has trailing bytes")
elif expected and stored and expected != stored:
    label = "crypto_or_metadata_mismatch"
    reason.append("signature mismatch with plausible framing")

if declared is not None and file_size and isinstance(declared, int):
    if declared > file_size:
        reason.append("declared length exceeds file size")

print("artifact:", artifact_path)
print("label:", label)
print("layout_format:", layout_format)
print("magic:", magic)
print("payload_sha256:", payload_sha)
print("expected_signature_hex16:", expected)
print("stored_signature_hex16:", stored)
print("wal_size:", wal.get("walFileSize", 0))
print("wal_trailing_bytes:", wal.get("trailingBytes", 0))
print("reason:", "; ".join(reason) if reason else "n/a")
PY
