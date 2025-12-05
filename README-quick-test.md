# MGM Backend — Quick Push Test

Use these steps to verify push end-to-end with minimal hassle.

## Prereqs
- Your server is running on Render at `{{BASE_URL}}`.
- You have one FCM device token registered for your account.

## 1) Get a token
POST `{{BASE_URL}}/login`
- Body (x-www-form-urlencoded): `username`, `password`
- Copy `access_token` from response.

## 2) Send a ping (no body)
POST `{{BASE_URL}}/push/ping`
- Header: `X-Auth-Token: <access_token>`
- Response: `{ "sent": n, "total": k }`

## 3) Send custom now
POST `{{BASE_URL}}/push/now`
- Header: `X-Auth-Token: <access_token>`
- Body (JSON or form):
```
{"title":"Ping","body":"It works!"}
```

## 4) Schedule and immediately dispatch
POST `{{BASE_URL}}/push/schedule-and-dispatch`
- Header: `X-Auth-Token: <access_token>`
- Body:
```
{"title":"Test","body":"Hello","send_at":"2025-09-23T09:00:00Z","force_now":true}
```

## (Optional) Dispatch only your due items
POST `{{BASE_URL}}/push/dispatch-mine?dry_run=true&limit=5`
- Header: `X-Auth-Token: <access_token>`

## Postman collection
Import `POSTMAN_collection.json` from this folder and fill the variables:
- `BASE_URL`, `USERNAME`, `PASSWORD`, `TOKEN`.

---

## Battery Optimization & Fallback Strategy

Android OEMs (Xiaomi, Oppo, Vivo, Huawei, Samsung aggressive modes) may delay or suppress local alarms / notifications when the app is backgrounded or killed. To mitigate:

- The app first schedules a LOCAL daily notification (fast, offline, instant UI).
- The backend keeps a canonical reminder record and only sends a fallback FCM push if:
	1. The scheduled local fire time + grace window has passed, AND
	2. No acknowledgement (ack) was received for that day.

Recommended device instructions to surface to users (one‑time screen or FAQ):
1. Disable battery optimization for the app (Settings > Battery > App battery usage > set to Unrestricted / No restrictions).
2. Allow autostart / background activity.
3. Keep notifications enabled (Settings > Apps > YourApp > Notifications).

If a user does nothing: fallback still ensures delivery, just possibly a few minutes late (after grace). If they optimize settings, they receive the faster local notification consistently and server rarely needs to push.

## Deployment Checklist (Render)

| Item | Action |
|------|--------|
| SECRET_KEY | Set in environment vars |
| CRON_SECRET | Set (random string) for /push/dispatch-due cron calls |
| SCHEDULER_ENABLED | Set to `1` on exactly ONE instance if scaling horizontally |
| GOOGLE creds | Service account JSON (if using FCM HTTP v1) or legacy server key |
| DATABASE_URL | Point to persistent Postgres (avoid SQLite for prod) |
| Pytz/APScheduler | Confirm installed from requirements.txt |

### Single vs Multi Instance
- Single instance: leave `SCHEDULER_ENABLED=1`.
- Multiple instances (e.g., autoscale): set `SCHEDULER_ENABLED=0` on all but one OR move scheduling to an external cron hitting `/push/dispatch-due` with the `X-CRON-KEY`.

### Cron (External)
If you disable in‑process scheduler, run every minute:
```
curl -X POST "${BASE_URL}/push/dispatch-due" -H "X-CRON-KEY: ${CRON_SECRET}" -d ''
```
Add `?dry_run=true` for testing before live enabling.

## Reminder Endpoints Quick Reference
| Endpoint | Method | Notes |
|----------|--------|-------|
| /reminders | POST | Create reminder |
| /reminders | GET | List reminders |
| /reminders/{id} | PATCH | Update (ack_today optional) |
| /reminders/{id} | DELETE | Delete |
| /reminders/{id}/ack | POST | Explicit daily acknowledgement |
| /reminders/reschedule-all | POST | Recompute next_fire for all |
| /reminders/sync | POST | Bulk upsert + optional prune |
| /reminders/health | GET | Stats (per user) |
| /healthz | GET | Unauth health (db flag) |

## Observability Tips
- Watch logs for `[Dispatch] Sent X reminder` lines (fallback in action).
- Sudden spike in `pending_after_grace` (from `/reminders/health`) indicates local notifications being suppressed.
- Add structured logging later (JSON) if you integrate a log shipper.

## Future Hardening Ideas
- Add Alembic migrations (the index `ix_reminder_patient_due_active` is implicit right now).
- Add rate limiting per user on reminder create/update.
- Consolidate push sending into a queue (Redis / Celery) if volume increases.

