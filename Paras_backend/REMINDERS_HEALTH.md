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