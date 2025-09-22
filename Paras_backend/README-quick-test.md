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
