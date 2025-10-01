# Hybrid Reminder System

This document summarizes the new hybrid (local + server fallback) reminder design.

## Goals
- Local daily notification for fast, offline, precise delivery.
- Server fallback push if the device did not acknowledge within a grace window (default 20m) after scheduled time.
- Central management & analytics potential on server.

## Data Model (Reminder)
Fields: id, patient_id, title, body, hour, minute, timezone, active, next_fire_local, next_fire_utc, last_sent_utc, last_ack_local_date, grace_minutes, created_at, updated_at.

`next_fire_local` and `next_fire_utc` are recalculated whenever time, timezone, or activation state changes.

## Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | /reminders | Create new reminder |
| GET | /reminders | List all reminders for auth user |
| GET | /reminders/{id} | Get single reminder |
| PATCH | /reminders/{id} | Update fields / acknowledge today (ack_today=true) |
| DELETE | /reminders/{id} | Delete reminder |
| POST | /reminders/sync | Bulk sync (client sends snapshot) |
| POST | /reminders/ack | Explicit acknowledgement (by reminder_id) |

## Example cURL
Assume `$TOKEN` holds bearer token.

Create:
```
curl -X POST https://<host>/reminders \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 -d '{"title":"Morning Brush","body":"Brush teeth","hour":7,"minute":30,"timezone":"Asia/Kolkata","active":true,"grace_minutes":20}'
```

List:
```
curl -H "Authorization: Bearer $TOKEN" https://<host>/reminders
```

Update time:
```
curl -X PATCH https://<host>/reminders/12 \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 -d '{"hour":8,"minute":0}'
```

Acknowledge (explicit):
```
curl -X POST https://<host>/reminders/ack \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 -d '{"reminder_id":12}'
```

Bulk Sync (client authoritative list):
```
curl -X POST https://<host>/reminders/sync \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 -d '{"items":[{"title":"Morning","body":"Morning","hour":7,"minute":30,"timezone":"Asia/Kolkata","active":true,"grace_minutes":20}]}'
```

## Fallback Dispatch Logic (cron job / scheduler)
1. Select active reminders where `next_fire_utc <= now`.
2. For each reminder:
   - If `last_ack_local_date == today` (in user tz): advance schedule to next day, skip push.
   - Else determine if within grace period (scheduled local + grace_minutes). If grace not passed, skip this cycle.
   - After grace passes with no ack: send FCM push, update `last_sent_utc`, recompute next_fire_* for next day.

## Client Responsibilities
- Schedule local notification on create/update.
- On local fire (or user interaction), POST /reminders/ack to suppress fallback push.
- Periodically (e.g. app start, daily) call /reminders/sync to reconcile.

## Timezone Notes
Timezone must be an IANA name (e.g. `Asia/Kolkata`). If invalid, server falls back to UTC.

## Grace Minutes
A small delay (e.g. 20) reduces duplicate notifications (local + fallback) if device is slightly delayed in firing the local notification.

## Future Enhancements
- Add /reminders/health diagnostic endpoint (counts due, pending after grace).
- Add analytics for missed vs delivered.
- Retry/backoff for ack calls when offline.
- Encrypted payload / silent push to trigger local rescheduling.

## Local → Server ID Mapping
Current frontend hybrid adapter stores a local->server id map; for new installs without prior state, server id is reused as local id.

---
This file supports rapid testing and onboarding of the reminder feature.
