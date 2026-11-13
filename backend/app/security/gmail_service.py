
import base64
import os
from email.message import EmailMessage
from pathlib import Path

from app.security.private_config import GMAIL_PRIVATE_DIR, load_private_env
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build


BACKEND_DIR = Path(__file__).resolve().parents[2]
TOKEN_FILE = GMAIL_PRIVATE_DIR / "token.json"

SCOPES = [
    "https://www.googleapis.com/auth/gmail.send"
]


def send_gmail(
    recipient: str,
    subject: str,
    body_text: str,
    body_html: str | None = None,
) -> bool:
    load_private_env()

    sender = os.getenv("GMAIL_SENDER_EMAIL", "").strip()

    if not sender:
        raise RuntimeError("GMAIL_SENDER_EMAIL is not configured.")

    if not TOKEN_FILE.exists():
        raise RuntimeError("Gmail authorization token is missing.")

    credentials = Credentials.from_authorized_user_file(
        str(TOKEN_FILE),
        SCOPES,
    )

    if credentials.expired and credentials.refresh_token:
        credentials.refresh(Request())
        TOKEN_FILE.write_text(
            credentials.to_json(),
            encoding="utf-8",
        )

    if not credentials.valid:
        raise RuntimeError("Gmail authorization is invalid or expired.")

    message = EmailMessage()
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = subject

    message.set_content(body_text)

    if body_html:
        message.add_alternative(body_html, subtype="html")

    raw_message = base64.urlsafe_b64encode(
        message.as_bytes()
    ).decode("ascii")

    service = build(
        "gmail",
        "v1",
        credentials=credentials,
        cache_discovery=False,
    )

    result = (
        service.users()
        .messages()
        .send(
            userId="me",
            body={"raw": raw_message},
        )
        .execute()
    )

    return bool(result.get("id"))
