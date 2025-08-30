import requests

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

from passlib.context import CryptContext
from jose import jwt
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import requests

def send_registration_email(to_email, user_name):
    EMAIL_MODE = os.getenv("EMAIL_MODE", "smtp")
    print(f"[DEBUG] EMAIL_MODE: {EMAIL_MODE}")
    subject = "Welcome to MGM Hospital App!"
    body = (
        f"Hello {user_name},\n\n"
        "You have registered in MGM Hospital's app.\n\n"
        "Thank you!"
    )

    EMAIL_HOST = os.getenv("EMAIL_HOST")
    EMAIL_PORT_RAW = os.getenv("EMAIL_PORT")
    EMAIL_USER = os.getenv("EMAIL_USER")
    EMAIL_PASS = os.getenv("EMAIL_PASS")
    EMAIL_FROM = os.getenv("EMAIL_FROM")

    if not EMAIL_HOST or not EMAIL_PORT_RAW or not EMAIL_USER or not EMAIL_PASS or not EMAIL_FROM:
        raise EnvironmentError("Missing one or more required email environment variables: EMAIL_HOST, EMAIL_PORT, EMAIL_USER, EMAIL_PASS, EMAIL_FROM")
    try:
        EMAIL_PORT = int(EMAIL_PORT_RAW)
    except Exception:
        raise ValueError("EMAIL_PORT environment variable must be an integer.")

    SIR_EMAIL = os.getenv("SIR_EMAIL")
    # Send to user
    msg = MIMEMultipart()
    msg["From"] = str(EMAIL_FROM)
    msg["To"] = to_email
    msg["Subject"] = subject
    msg.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP_SSL(EMAIL_HOST, EMAIL_PORT) as server:
            server.login(str(EMAIL_USER), str(EMAIL_PASS))
            server.sendmail(str(EMAIL_FROM), to_email, msg.as_string())
        print(f"Registration email sent to {to_email}")
    except Exception as e:
        print(f"Could not send email to user: {e}")

    # Always send to sir as a separate email
    if SIR_EMAIL:
        msg_sir = MIMEMultipart()
        msg_sir["From"] = str(EMAIL_FROM)
        msg_sir["To"] = SIR_EMAIL
        msg_sir["Subject"] = subject
        msg_sir.attach(MIMEText(body, "plain"))
        try:
            with smtplib.SMTP_SSL(EMAIL_HOST, EMAIL_PORT) as server:
                server.login(str(EMAIL_USER), str(EMAIL_PASS))
                server.sendmail(str(EMAIL_FROM), SIR_EMAIL, msg_sir.as_string())
            print(f"Registration email sent to sir: {SIR_EMAIL}")
        except Exception as e:
            print(f"Could not send email to sir: {e}")
    return True


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
    else:
        smtp_server = os.getenv("EMAIL_HOST")
        smtp_port = int(os.getenv("EMAIL_PORT", 587))
        smtp_user = os.getenv("EMAIL_USER")
        smtp_password = os.getenv("EMAIL_PASS")
        EMAIL_FROM = os.getenv("EMAIL_FROM")

        if not smtp_server:
            raise EnvironmentError("EMAIL_HOST environment variable must be set.")
        if not smtp_user or not smtp_password:
            raise EnvironmentError("EMAIL_USER and EMAIL_PASS environment variables must be set.")

        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"] = smtp_user
        msg["To"] = to_email

        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_password)
            server.sendmail(smtp_user, [to_email], msg.as_string())


        
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