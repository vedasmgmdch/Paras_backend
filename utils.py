import requests
import json
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GAuthRequest

def send_mailgun_email(to_email, subject, body):
    import os
    MAILGUN_API_KEY = os.getenv("MAILGUN_API_KEY")
    MAILGUN_DOMAIN = os.getenv("MAILGUN_DOMAIN")
    MAILGUN_BASE_URL = os.getenv("MAILGUN_BASE_URL", "https://api.mailgun.net/v3")
    EMAIL_FROM = os.getenv("EMAIL_FROM")
    if not (MAILGUN_API_KEY and MAILGUN_DOMAIN and EMAIL_FROM):
        print("Mailgun config missing!")
        return False
    url = f"{MAILGUN_BASE_URL}/{MAILGUN_DOMAIN}/messages"
    auth = ("api", MAILGUN_API_KEY)
    data = {
        "from": EMAIL_FROM,
        "to": to_email,
        "subject": subject,
        "text": body
    }
    response = requests.post(url, auth=auth, data=data)
    if response.status_code == 200:
        print(f"Mailgun: Email sent to {to_email}")
        return True
    else:
        print(f"Mailgun: Failed to send email: {response.text}")
        return False

import os
EMAIL_MODE = os.getenv("EMAIL_MODE", "smtp")
print(f"[DEBUG] EMAIL_MODE at startup: {EMAIL_MODE}")
FCM_HTTP_TIMEOUT = float(os.getenv("FCM_HTTP_TIMEOUT", "5"))

from passlib.context import CryptContext
from jose import jwt
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import requests


def _send_brevo_email(to_email: str, subject: str, body: str) -> bool:
    """Send email via Brevo (Sendinblue) SMTP API v3.

    Requires:
      - EMAIL_MODE=brevo
      - BREVO_API_KEY
      - EMAIL_FROM (must be a verified sender email in Brevo)
      - optional EMAIL_FROM_NAME
    """
    api_key = os.getenv("BREVO_API_KEY")
    email_from = os.getenv("EMAIL_FROM")
    from_name = os.getenv("EMAIL_FROM_NAME")
    if not api_key or not email_from:
        raise EnvironmentError("Missing BREVO_API_KEY and/or EMAIL_FROM")

    url = os.getenv("BREVO_BASE_URL", "https://api.brevo.com") + "/v3/smtp/email"
    headers = {
        "accept": "application/json",
        "api-key": api_key,
        "content-type": "application/json",
    }
    payload = {
        "sender": {"email": email_from, **({"name": from_name} if from_name else {})},
        "to": [{"email": to_email}],
        "subject": subject,
        "textContent": body,
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=20)
    if 200 <= resp.status_code < 300:
        return True
    print(f"Brevo: Failed to send email ({resp.status_code}): {resp.text}")
    return False


def _send_sendgrid_email(to_email: str, subject: str, body: str) -> bool:
    """Send email via SendGrid v3 Mail Send.

    Requires:
      - EMAIL_MODE=sendgrid
      - SENDGRID_API_KEY
      - EMAIL_FROM (a Single Sender verified email, or a verified domain sender)
      - optional EMAIL_FROM_NAME
    """
    api_key = os.getenv("SENDGRID_API_KEY")
    email_from = os.getenv("EMAIL_FROM")
    from_name = os.getenv("EMAIL_FROM_NAME")
    if not api_key or not email_from:
        raise EnvironmentError("Missing SENDGRID_API_KEY and/or EMAIL_FROM")

    url = os.getenv("SENDGRID_BASE_URL", "https://api.sendgrid.com") + "/v3/mail/send"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "personalizations": [{"to": [{"email": to_email}]}],
        "from": {"email": email_from, **({"name": from_name} if from_name else {})},
        "subject": subject,
        "content": [{"type": "text/plain", "value": body}],
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=20)
    if resp.status_code in (200, 202):
        return True
    print(f"SendGrid: Failed to send email ({resp.status_code}): {resp.text}")
    return False

def send_registration_email(to_email, user_name):
    subject = "Welcome to MGM Hospital App!"
    body = (
        f"Hello {user_name},\n\n"
        "You have registered in MGM Hospital's app.\n\n"
        "Thank you!"
    )

    ok_user = False
    try:
        ok_user = bool(send_email(to_email, subject, body))
    except Exception as e:
        print(f"Could not send registration email to user: {e}")

    sir_email = os.getenv("SIR_EMAIL")
    if sir_email:
        try:
            send_email(sir_email, subject, body)
        except Exception as e:
            print(f"Could not send registration email to sir: {e}")

    return ok_user


def send_email(to_email, subject, body):
    EMAIL_MODE = os.getenv("EMAIL_MODE", "smtp")
    print(f"[DEBUG] EMAIL_MODE in send_email: {EMAIL_MODE}")
    if EMAIL_MODE == "mailtrap_api":
        MAILTRAP_TOKEN = os.getenv("MAILTRAP_API_TOKEN")
        EMAIL_FROM = os.getenv("EMAIL_FROM", "your@email.com")
        if not MAILTRAP_TOKEN:
            print("MAILTRAP_API_TOKEN not set!")
            return False
        url = "https://send.api.mailtrap.io/api/send"
        headers = {
            "Authorization": f"Bearer {MAILTRAP_TOKEN}",
            "Content-Type": "application/json"
        }
        data = {
            "from": {"email": EMAIL_FROM},
            "to": [{"email": to_email}],
            "subject": subject,
            "text": body
        }
        response = requests.post(url, json=data, headers=headers)
        if response.status_code == 200:
            print(f"Email sent to {to_email} via Mailtrap API")
            return True
        else:
            print(f"Could not send email via Mailtrap API: {response.text}")
            return False
    elif EMAIL_MODE == "mailgun":
        return bool(send_mailgun_email(to_email, subject, body))
    elif EMAIL_MODE == "brevo":
        return _send_brevo_email(to_email, subject, body)
    elif EMAIL_MODE == "sendgrid":
        return _send_sendgrid_email(to_email, subject, body)
    else:
        smtp_server = os.getenv("EMAIL_HOST")
        smtp_port = int(os.getenv("EMAIL_PORT", 587))
        smtp_user = os.getenv("EMAIL_USER")
        smtp_password = os.getenv("EMAIL_PASS")
        email_from = os.getenv("EMAIL_FROM")

        if not smtp_server:
            raise EnvironmentError("EMAIL_HOST environment variable must be set.")
        if not smtp_user or not smtp_password:
            raise EnvironmentError("EMAIL_USER and EMAIL_PASS environment variables must be set.")

        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"] = email_from or smtp_user
        msg["To"] = to_email

        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_password)
            server.sendmail(smtp_user, [to_email], msg.as_string())

        return True


        
# Use environment for secrets if possible
SECRET_KEY = os.getenv("SECRET_KEY", "Priyans3628p")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 90  # 90 days

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

from typing import Optional
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

# ------------------------
# FCM Push Notifications
# ------------------------
def _get_v1_access_token(sa_info: dict) -> str:
    credentials = service_account.Credentials.from_service_account_info(
        sa_info,
        scopes=["https://www.googleapis.com/auth/firebase.messaging"],
    )
    credentials.refresh(GAuthRequest())
    return credentials.token

def _send_fcm_v1(token: str, title: str, body: str, data: dict | None, sa_info: dict, project_id: str) -> bool:
    access_token = _get_v1_access_token(sa_info)
    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; UTF-8",
    }
    payload = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "data": data or {},
        }
    }
    resp = requests.post(url, data=json.dumps(payload), headers=headers, timeout=FCM_HTTP_TIMEOUT)
    if resp.status_code in (200, 202):
        return True
    print(f"FCM v1 send failed {resp.status_code}: {resp.text}")
    return False

def _send_fcm_legacy(token: str, title: str, body: str, data: dict | None, server_key: str) -> bool:
    url = "https://fcm.googleapis.com/fcm/send"
    headers = {
        "Authorization": f"key={server_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "to": token,
        "notification": {"title": title, "body": body},
        "data": data or {},
        "priority": "high",
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=FCM_HTTP_TIMEOUT)
    if resp.status_code == 200:
        return True
    print(f"FCM legacy send failed {resp.status_code}: {resp.text}")
    return False

def send_fcm_notification(token: str, title: str, body: str, data: dict | None = None) -> bool:
    sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    if not sa_json:
        sa_b64 = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON_B64")
        if sa_b64:
            try:
                import base64
                sa_json = base64.b64decode(sa_b64).decode("utf-8")
            except Exception as e:
                print(f"Failed to decode FIREBASE_SERVICE_ACCOUNT_JSON_B64: {e}")
                sa_json = None
    project_id_env = os.getenv("FIREBASE_PROJECT_ID")
    if sa_json:
        try:
            sa_info = json.loads(sa_json)
            project_id = project_id_env or sa_info.get("project_id")
            if project_id:
                return _send_fcm_v1(token, title, body, data, sa_info, project_id)
            else:
                print("FIREBASE_PROJECT_ID not set and missing project_id in service account JSON")
        except Exception as e:
            print(f"FCM v1 error, falling back to legacy: {e}")
    server_key = os.getenv("FCM_SERVER_KEY")
    if not server_key:
        print("FCM_SERVER_KEY not set and v1 not configured")
        return False
    return _send_fcm_legacy(token, title, body, data, server_key)

def send_fcm_to_tokens(tokens: list[str], title: str, body: str, data: dict | None = None) -> dict:
    results = {"success": 0, "failure": 0}
    for t in tokens:
        ok = send_fcm_notification(t, title, body, data)
        if ok:
            results["success"] += 1
        else:
            results["failure"] += 1
    return results

# --- Extended debug variant that returns raw responses and error hints ---
def send_fcm_notification_ex(
    token: str,
    title: str,
    body: str,
    data: dict | None = None,
    android_channel_id: str | None = None,
    data_only: bool = False,
) -> dict:
    """Send a single FCM message and return a structured result.

    Returns dict with keys: ok (bool), status (int|None), body (str|None), api ('v1'|'legacy'|None),
    error (str|None)
    """
    sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    api_used = None
    if not sa_json:
        sa_b64 = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON_B64")
        if sa_b64:
            try:
                import base64
                sa_json = base64.b64decode(sa_b64).decode("utf-8")
            except Exception as e:
                return {"ok": False, "status": None, "body": f"B64 decode error: {e}", "api": None, "error": "CONFIG"}
    project_id_env = os.getenv("FIREBASE_PROJECT_ID")
    if sa_json:
        try:
            sa_info = json.loads(sa_json)
            project_id = project_id_env or sa_info.get("project_id")
            if project_id:
                api_used = "v1"
                access_token = _get_v1_access_token(sa_info)
                url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
                headers = {
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json; UTF-8",
                }
                message = {
                    "token": token,
                    "data": data or {},
                }
                if not data_only:
                    message["notification"] = {"title": title, "body": body}
                if android_channel_id:
                    message["android"] = {
                        "priority": "HIGH",
                        "notification": {
                            "channel_id": android_channel_id,
                        },
                    }
                payload = {"message": message}
                resp = requests.post(url, data=json.dumps(payload), headers=headers, timeout=FCM_HTTP_TIMEOUT)
                ok = resp.status_code in (200, 202)
                return {"ok": ok, "status": resp.status_code, "body": resp.text, "api": api_used, "error": None if ok else "SEND_FAILED"}
            else:
                # fall through to legacy
                pass
        except Exception as e:
            # fall back to legacy
            last_err = str(e)
        else:
            last_err = None
    else:
        last_err = "NO_V1_CONFIG"

    server_key = os.getenv("FCM_SERVER_KEY")
    if not server_key:
        return {"ok": False, "status": None, "body": f"{last_err or 'No server key'}", "api": None, "error": "CONFIG"}
    api_used = "legacy"
    url = "https://fcm.googleapis.com/fcm/send"
    headers = {
        "Authorization": f"key={server_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "to": token,
        "data": data or {},
        "priority": "high",
    }
    if not data_only:
        notification_obj = {"title": title, "body": body}
        if android_channel_id:
            # Android 8+ channel routing for FCM legacy API
            notification_obj["android_channel_id"] = android_channel_id
        payload["notification"] = notification_obj
    resp = requests.post(url, json=payload, headers=headers, timeout=FCM_HTTP_TIMEOUT)
    ok = resp.status_code == 200
    return {"ok": ok, "status": resp.status_code, "body": resp.text, "api": api_used, "error": None if ok else "SEND_FAILED"}