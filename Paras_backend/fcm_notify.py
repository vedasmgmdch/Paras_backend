"""Deprecated standalone FCM sender.

This module is kept only to avoid import errors for legacy references.
Use utils.send_fcm_notification or the /push endpoints in main.py instead.
"""

from fastapi import FastAPI, Body
from utils import send_fcm_notification

app = FastAPI()

@app.post("/send-reminder/", deprecated=True)
def send_reminder(token: str = Body(...), title: str = Body(...), body: str = Body(...)):
    ok = send_fcm_notification(token, title, body)
    return {"ok": ok}
