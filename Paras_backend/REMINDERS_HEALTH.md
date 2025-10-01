## Reminder Reliability & Health

This backend now tracks lightweight in-memory metrics for the fallback reminder dispatcher.

Endpoint:

GET /reminders/health

Response shape:
{
  "last_run": <ISO timestamp | null>,
  "last_counts": {
    "sent": <int>,               // total FCM messages sent in last run (push + reminders)
    "dispatched_pushes": <int>,  // scheduled push rows processed
    "dispatched_reminders": <int>// reminder fallback notifications dispatched
  },
  "active_reminders": <int>      // count of active reminders (all patients)
}

Notes:
1. Metrics are ephemeral (memory only). A container restart clears them.
2. For persistence / dashboards, promote these into a table or external metrics sink later.
3. The scheduler invokes the same logic (dispatch_due_pushes) every 60s; manual POST /push/dispatch-due (with cron key) or /push/dispatch-mine also update metrics.

### Frontend Ack Flow

The Flutter `NotificationService.init` now accepts a callback. The hybrid reminder service wires this to automatically call `/reminders/ack` when the user interacts with (or the system delivers) a local reminder notification, preventing a duplicate fallback push.

Additionally, on startup a sweep acknowledges any reminders earlier today (minus a 10‑minute grace) to reduce false fallbacks after device downtime.

### Future Enhancements (Suggested)

* Persist last dispatch run + counts in a small `reminder_stats` table.
* Add per-patient counts (active reminders, last ack date) directly in health response for authenticated calls.
* Emit structured logs for each fallback decision (SKIP_ACKED, SKIP_GRACE, SEND_FALLBACK) to aid debugging.
* Add exponential backoff & jitter if FCM send failures spike to avoid thundering herd retries.

---
Updated: 2025-10-01

### New Diagnostics & Controls (2025-10-01)

Added internal refactor + richer debug:

1. Unified internal dispatcher `_internal_dispatch_due` used by both the public cron endpoint and the in-process scheduler. This removed fragile fake Request objects that caused `KeyError: 'query_string'` and silently prevented fallback dispatch.
2. Debug decision tracing:
  * Add `?debug=1` to `POST /push/dispatch-due` to receive a `decisions` array with reasons: `scheduled_push`, `skip_ack_today`, `skip_in_grace`, `send`.
  * Set environment variable `DISPATCH_DEBUG=1` to print scheduler cycle summaries every minute.
3. New endpoint `GET /reminders/debug` (auth required) returns raw timing fields: next_fire_local, next_fire_utc, last_ack_local_date, last_sent_utc, grace_minutes, and whether the reminder is currently due.

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `REMINDER_DEFAULT_GRACE` | Override grace_minutes on create/sync when client sends 0/none | unset (no override) |
| `REMINDER_DEFAULT_GRACE_OVERRIDE_ON_UPDATE` | If truthy, also override on PATCH when not explicitly supplied | 0 (disabled) |
| `DISPATCH_DEBUG` | Print scheduler dispatch debug dict each run | 0 |
| `SCHEDULER_ENABLED` | Enable periodic dispatcher | 1 |

### Frontend Sweep Change

The prior startup behavior auto‑ACKed any reminders earlier the same day (`_sweepMissedToday()`), which could suppress legitimate fallback pushes if the local notification never fired. This sweep is now gated:

```
HybridRemindersService.enableSweep = false; // default
```

Setting it to `true` restores legacy behavior; leave disabled to allow the server fallback to fire when local delivery failed.

### Troubleshooting Flow

1. Call `/reminders/debug` → confirm a reminder shows `due: true` once past local time.
2. Check `/push/dispatch-due?cron_key=...&dry_run=1&debug=1` → look for decision:
  * `skip_in_grace`: Wait or reduce grace (`REMINDER_DEFAULT_GRACE=5`).
  * `skip_ack_today`: Client acknowledged; verify user actually saw local notification. If not, ensure sweep remains disabled.
  * `send`: Should shortly appear in device (verify FCM token valid via `/push/diag`).
3. If no reminders listed but expected: verify timezone and hour/minute values on creation; ensure scheduler enabled.

### Suggested Next Enhancements

* Chain one-shot scheduling strategy (server: store next occurrence; client: schedule only next alarm) to avoid fragile repeating components.
* Add per-reminder metrics (last decision, skip reason counters).
* Automatic grace tuning: dynamically shrink grace if multiple consecutive days skip due to ACK sweep.

---
Document extended: 2025-10-01 (afternoon diagnostics pass)