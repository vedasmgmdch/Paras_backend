# Instruction Status Persistence & Migration

## Overview
Originally, patient instruction adherence ("instruction logs") was stored only locally on the device (SharedPreferences). Doctors saw nothing because no rows existed in the server table `instruction_status`.

## Phase 1 – Basic Sync
A POST `/instruction-status` endpoint was wired from the patient app. Each toggle sent a single row. We used `instruction_index = instruction.hashCode` (Dart hashCode). Problem: Dart's `hashCode` is not stable across launches/builds, so upsert matching (date+group+index) could produce duplicates later.

## Phase 2 – Deterministic Index & Bulk Migration
We introduced `stableInstructionIndex(group, instruction)` using a 32‑bit FNV‑1a style hash over the lower‑cased `group|instruction` string. This yields a consistent positive integer across runs.

Changes:
- Frontend now calls `stableInstructionIndex` instead of `hashCode`.
- A one‑time bulk sync runs after user data loads (`loadUserDetails`) if flag `instruction_bulk_synced_<username>` is not set. It posts *all* historical local logs with stable indices.
- Backend upsert widened: for each request we first delete existing rows for the (date, group) combination before inserting new ones. This collapses any legacy `hashCode` rows.

## Upsert Semantics
For each item in the payload, all rows for that patient/date/group are removed only once per (date, group) per request, then new rows inserted. This ensures:
- Legacy rows (old index values or text duplicates) are cleared.
- The payload is considered authoritative for that date+group.

## Future Enhancements
- If you later want to store *unfollowed* instructions too, always send a full set (followed true/false) for each (date, group) in a single POST.
- Add a uniqueness constraint on `(patient_id, date, group, instruction_index)` after data is clean.

## Backfill Guidance
If some users already synced with unstable indices before upgrading:
1. They will bulk sync on next launch (clears old rows).
2. No manual DB migration required.

## Removal Steps (when stable)
- Remove debug endpoint: `/doctor/patients/{username}/instruction-status-debug`.
- Add Alembic migration for uniqueness constraint (optional).

