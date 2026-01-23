# Known Issues

**Purpose:** Track issues that don't block adoption but need attention.

---

## Signature Verification in Export/Verify

**Status:** Known limitation  
**Severity:** Medium (affects trust signals)  
**Impact:** Export/restore verification fails with signature mismatch errors

**Symptoms:**
- `HelloBlazeDB` example fails at export verification step
- Error: "Payload hash mismatch - dump may be tampered"
- Signature verification errors in logs

**Likely Cause:**
- Deterministic ordering issue in dump format
- Metadata boundary problem
- Not a fundamental design flaw

**Acceptable Outcomes:**
1. Fix cleanly (preferred)
2. Document limitation loudly and temporarily

**Not Acceptable:**
- Pretending it doesn't exist
- Ignoring it

**Next Steps:**
- Investigate dump format deterministic ordering
- Check metadata boundary handling
- Fix without engine changes (if possible)

**Workaround:**
- Export works (data is correct)
- Verification step fails
- Restore may work despite verification failure (needs testing)

---

## Other Known Issues

None at this time.

---

**Note:** This document exists to be honest about limitations. Trust comes from transparency, not perfection.
