# Known Issues

**Purpose:** Track currently verified, user-facing issues that matter for public adopters.

**Full backlog:** [`WORK_REMAINING.md`](WORK_REMAINING.md) (prioritized sprints). This file lists only active, reproducible public caveats.

---

## Active caveats

### Dump restore and metadata signatures

When restoring from a `.blazedump` file:

- **Wrong password** can surface as a metadata signature verification failure (CLI reports this explicitly).
- **Cross-version restore** from older dumps may require `allowLegacyHashMismatch: true` on the restore API when hash algorithms differ between release lines.

**Work remaining:** Decide permanent policy (stricter verification vs documented legacy opt-in) — tracker ID **R-07** in `WORK_REMAINING.md`.

---

## Intentionally separate (not bugs)

Use these documents for limits that are by design, not defects:

- `Docs/COMPATIBILITY.md` — platform and version support
- `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md` — features deferred from the OSS core build
- `Docs/Status/DURABILITY_MODE_SUPPORT.md` — durability-path guarantees and limits
- `Docs/android-status.md` — Android/KMM integration status (scaffolding, not full product support)

---

**Note:** Historical release blockers and internal audit notes belong in `Docs/Audit/` or `Docs/Status/WORK_REMAINING.md`, not here.
